import AppKit
import Darwin
import Foundation

private final class MediaRemoteProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func store(_ value: Data) {
        lock.lock()
        data = value
        lock.unlock()
    }

    func value() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

private struct MediaRemoteTrackTimelineIdentity {
    let bundleIdentifier: String?
    let processIdentifier: pid_t?
    let contentItemIdentifier: String?
    let title: String
    let artist: String?
    let album: String?
    let duration: TimeInterval?
}

private struct MediaRemoteSeekTimelineAnchor {
    let trackIdentity: MediaRemoteTrackTimelineIdentity
    let targetElapsedTime: TimeInterval
    var elapsedTime: TimeInterval
    let issuedAt: Date
    var updatedAt: Date
    var isPlaying: Bool
    let confirmationDeadline: Date
    var didObserveTarget: Bool
    var coherentSince: Date?
}

private enum MediaRemoteStreamPayloadMerge: Equatable {
    case replacement
    case confirmedSameTrack
    case ambiguousPlaybackPatch
    case ignoredProcess
}

private enum MediaRemotePayloadTrackRelationship {
    case different
    case confirmedSameTrack
    case ambiguousPlaybackPatch
}

struct MediaRemoteStreamLifecycle {
    private(set) var generation: UInt64 = 0
    private(set) var isStopping = true

    mutating func beginStart() -> UInt64 {
        generation &+= 1
        isStopping = false
        return generation
    }

    mutating func beginStop() {
        generation &+= 1
        isStopping = true
    }

    func accepts(_ candidateGeneration: UInt64) -> Bool {
        !isStopping && generation == candidateGeneration
    }
}

@MainActor
final class MediaRemoteAdapterStreamSource {
    typealias ChangeHandler = @MainActor @Sendable () -> Void

    private let qishuiBundleIdentifier = "com.soda.music"
    private let seekCommandQueue = DispatchQueue(
        label: "MacBookIsland.MediaRemoteSeek"
    )
    private var seekCommandGeneration = 0
    private var seekTimelineAnchor: MediaRemoteSeekTimelineAnchor?
    private var seekTimelineConfirmationTask: Task<Void, Never>?
    private var process: Process?
    private var outputBuffer = Data()
    private var mergedPayload: [String: Any] = [:]
    private var lastPublishedPayload: [String: Any] = [:]
    private var deferredTrackPublicationTask: Task<Void, Never>?
    private var deferredTrackPublicationGeneration = 0
    private var deferredTrackPublicationStartedAt: Date?
    private var deferredTrackBaselinePayload: [String: Any]?
    private var deferredTrackReferencePayloads: [[String: Any]] = []
    private var deferredTrackCandidateIdentity: String?
    private var deferredTimelinePayload: [String: Any]?
    private var latestSnapshot: MediaRemoteNowPlayingSnapshot?
    private var latestRawSnapshot: MediaRemoteNowPlayingSnapshot?
    private var lastVerifiedQishuiSnapshot: MediaRemoteNowPlayingSnapshot?
    private var playbackPositionAnchor: PlaybackControlTimeline.AuthoritativeAnchor?
    private var playbackPositionTrackIdentity: MediaRemoteTrackTimelineIdentity?
    private var latestSignature: String?
    private var artworkCache: [String: Data] = [:]
    private var artworkCacheOrder: [String] = []
    private var artworkFetchInFlight = false
    private var metadataRequestGeneration = 0
    private var pendingArtworkRequestLookupKey: String?
    private var lastArtworkRequestLookupKey: String?
    private var lastArtworkRequestAt: Date?
    private let lastVerifiedQishuiSnapshotTTL: TimeInterval = 5 * 60
    private var sampleID: UInt64 = 0
    private var sampleOrigin: MediaRemoteSampleOrigin = .unknown
    private var lastPlaybackEvidenceAt: Date?
    private var lastPlaybackEvidenceTrackIdentity: String?
    private var retiredSourceProcessIdentifiers: [pid_t: Date] = [:]
    private let retiredSourceProcessIdentifierTTL: TimeInterval = 30
    private var qishuiSessionGeneration: UInt64 = 0
    private var streamLifecycle = MediaRemoteStreamLifecycle()
    private var restartTask: Task<Void, Never>?
    private var changeHandler: ChangeHandler?
    private let runningQishuiProcessIdentifiersProvider: () -> Set<pid_t>

    init(
        runningQishuiProcessIdentifiersProvider: @escaping () -> Set<pid_t> = {
            Set(
                NSRunningApplication.runningApplications(
                    withBundleIdentifier: "com.soda.music"
                ).filter { !$0.isTerminated }.map(\.processIdentifier)
            )
        }
    ) {
        self.runningQishuiProcessIdentifiersProvider = runningQishuiProcessIdentifiersProvider
    }

    func start(onChange: @escaping ChangeHandler) {
        guard process == nil else { return }
        restartTask?.cancel()
        restartTask = nil
        let generation = streamLifecycle.beginStart()
        changeHandler = onChange
        guard let paths = adapterPaths() else {
            let snapshot = MediaRemoteNowPlayingSnapshot(
                isAvailable: false,
                isVerifiedQishuiSource: false,
                currentTrack: nil,
                diagnostic: "MediaRemote Adapter 资源未找到；已降级到普通 MediaRemote/AX。",
                checkedAt: Date()
            )
            latestRawSnapshot = snapshot
            latestSnapshot = snapshot
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = Self.streamArguments(
            script: paths.script.path,
            framework: paths.framework.path,
            bundleIdentifier: qishuiBundleIdentifier
        )

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self, weak process] in
                guard let self,
                      let process,
                      streamLifecycle.accepts(generation),
                      self.process === process else { return }
                consume(data, onChange: onChange)
            }
        }

        process.terminationHandler = { [weak self, weak process] _ in
            Task { @MainActor [weak self, weak process] in
                guard let self,
                      let process,
                      streamLifecycle.accepts(generation),
                      self.process === process else { return }
                if let pipe = process.standardOutput as? Pipe {
                    pipe.fileHandleForReading.readabilityHandler = nil
                }
                process.terminationHandler = nil
                self.process = nil
                outputBuffer.removeAll()
                scheduleRestart(onChange: onChange, generation: generation)
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            latestSnapshot = MediaRemoteNowPlayingSnapshot(
                isAvailable: false,
                isVerifiedQishuiSource: false,
                currentTrack: nil,
                diagnostic: "MediaRemote Adapter 启动失败：\(error.localizedDescription)。",
                checkedAt: Date()
            )
            scheduleRestart(onChange: onChange, generation: generation)
        }
    }

    func snapshot() -> MediaRemoteNowPlayingSnapshot? {
        if deferredTrackPublicationStartedAt != nil {
            return latestSnapshot
        }
        if !mergedPayload.isEmpty {
            let rawSnapshot = snapshot(
                from: mergedPayload,
                existingArtwork: reusableArtwork(for: mergedPayload),
                timelinePayload: nil
            )
            return remember(snapshot: rawSnapshot)
        }
        return latestSnapshot
    }

    func hasVerifiedQishuiClientState() -> Bool {
        guard let snapshot = latestRawSnapshot ?? latestSnapshot else { return false }
        return snapshot.isVerifiedQishuiSource
    }

    func hasFreshVerifiedPlaybackEvidence(
        at now: Date = Date(),
        maxAge: TimeInterval
    ) -> Bool {
        guard maxAge >= 0,
              deferredTrackPublicationStartedAt == nil,
              let lastPlaybackEvidenceAt,
              let lastPlaybackEvidenceTrackIdentity,
              now >= lastPlaybackEvidenceAt,
              now.timeIntervalSince(lastPlaybackEvidenceAt) <= maxAge,
              lastPlaybackEvidenceTrackIdentity == payloadTrackIdentity(mergedPayload),
              let snapshot = latestRawSnapshot ?? latestSnapshot,
              snapshot.isVerifiedQishuiSource,
              snapshot.currentTrack != nil,
              snapshot.sampleOrigin != .cached else {
            return false
        }
        return true
    }

    func hasPendingSeekTimeline() -> Bool {
        guard let anchor = seekTimelineAnchor else { return false }
        if anchor.didObserveTarget || Date() < anchor.confirmationDeadline {
            return true
        }
        clearSeekTimelineAnchor()
        return false
    }

    func hasAdapterResources() -> Bool {
        adapterPaths() != nil
    }

    func invalidateQishuiSession(
        at now: Date = Date(),
        retireProcessIdentifier: Bool = true
    ) {
        qishuiSessionGeneration &+= 1
        invalidatePendingSeekRequests()
        if retireProcessIdentifier,
           let processIdentifier = pidValue(mergedPayload["processIdentifier"])
               ?? latestRawSnapshot?.currentTrack?.sourceProcessIdentifier {
            retireSourceProcessIdentifier(processIdentifier, at: now)
        }
        outputBuffer.removeAll()
        mergedPayload.removeAll()
        lastPublishedPayload.removeAll()
        clearDeferredTrackPublication()
        latestSnapshot = nil
        latestRawSnapshot = nil
        lastVerifiedQishuiSnapshot = nil
        playbackPositionAnchor = nil
        playbackPositionTrackIdentity = nil
        latestSignature = nil
        metadataRequestGeneration += 1
        pendingArtworkRequestLookupKey = nil
        lastArtworkRequestLookupKey = nil
        lastArtworkRequestAt = nil
        artworkCache.removeAll()
        artworkCacheOrder.removeAll()
        clearSeekTimelineAnchor()
        sampleOrigin = .unknown
        lastPlaybackEvidenceAt = nil
        lastPlaybackEvidenceTrackIdentity = nil
    }

    func invalidatePendingSeekRequests() {
        seekCommandGeneration &+= 1
        seekTimelineConfirmationTask?.cancel()
        seekTimelineConfirmationTask = nil
        clearSeekTimelineAnchor()
    }

    func refreshOnce() -> MediaRemoteNowPlayingSnapshot {
        guard let paths = adapterPaths(),
              let rawPayload = Self.runGet(
                script: paths.script,
                framework: paths.framework,
                bundleIdentifier: qishuiBundleIdentifier,
                includeArtwork: true
              ),
              let payload = payloadResolvingProcessIdentifier(rawPayload) else {
            let snapshot = MediaRemoteNowPlayingSnapshot(
                isAvailable: false,
                isVerifiedQishuiSource: false,
                currentTrack: nil,
                diagnostic: "MediaRemote Adapter 单次读取失败。",
                checkedAt: Date(),
                sampleID: sampleID,
                sampleOrigin: sampleOrigin,
                sampleSource: .adapterStream
            )
            latestRawSnapshot = snapshot
            latestSnapshot = snapshot
            return snapshot
        }

        advanceSample(origin: .synchronousRead)
        let rawSnapshot = snapshot(
            from: payload,
            existingArtwork: nil,
            timelinePayload: payload
        )
        if rawSnapshot.isVerifiedQishuiSource {
            recordPlaybackEvidenceIfPresent(
                payload,
                identityPayload: payload,
                receivedAt: rawSnapshot.checkedAt
            )
        }
        return remember(snapshot: rawSnapshot)
    }

    func refreshPlaybackPosition() -> MediaRemoteNowPlayingSnapshot? {
        guard let paths = adapterPaths(),
              let payload = Self.runGet(
                script: paths.script,
                framework: paths.framework,
                bundleIdentifier: qishuiBundleIdentifier,
                includeArtwork: false
              ) else {
            return nil
        }

        return applyPlaybackPositionPayload(payload)
    }

    func refreshPlaybackPositionAsync() async -> MediaRemoteNowPlayingSnapshot? {
        guard let paths = adapterPaths() else { return nil }
        let requestSampleID = sampleID
        let requestSessionGeneration = qishuiSessionGeneration
        let expectedProcessIdentifier = pidValue(mergedPayload["processIdentifier"])
        let data = await Task.detached(priority: .utility) {
            Self.runGetData(
                script: paths.script,
                framework: paths.framework,
                bundleIdentifier: self.qishuiBundleIdentifier,
                includeArtwork: false
            )
        }.value
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any] else { return nil }
        return applyPlaybackPositionPayload(
            payload,
            requestSampleID: requestSampleID,
            requestSessionGeneration: requestSessionGeneration,
            expectedProcessIdentifier: expectedProcessIdentifier
        )
    }

    func seek(
        to elapsedTime: TimeInterval,
        coalescingDelayNanoseconds: UInt64
    ) async -> Bool {
        guard let paths = adapterPaths(),
              elapsedTime.isFinite,
              elapsedTime >= 0 else { return false }

        seekCommandGeneration &+= 1
        let generation = seekCommandGeneration
        let currentTrack = latestRawSnapshot?.currentTrack ?? latestSnapshot?.currentTrack
        let currentTrackIdentity = currentTrack.map(trackTimelineIdentity)
        let positionMicros = max(
            Int64((elapsedTime * 1_000_000).rounded()),
            0
        )

        do {
            try await Task.sleep(nanoseconds: coalescingDelayNanoseconds)
        } catch {
            return false
        }
        guard generation == seekCommandGeneration,
              hasVerifiedQishuiClientState(),
              let currentTrackIdentity else { return false }

        let bundleIdentifier = qishuiBundleIdentifier
        let expectedProcessIdentifier = runningQishuiProcessIdentifier()
        guard expectedProcessIdentifier != nil else { return false }

        let didSeek = await withCheckedContinuation { continuation in
            seekCommandQueue.async {
                let sourceIsStillQishui = Self.isCurrentQishuiPlaybackSource(
                    script: paths.script,
                    framework: paths.framework,
                    bundleIdentifier: bundleIdentifier,
                    expectedProcessIdentifier: expectedProcessIdentifier
                )
                let didSeek = sourceIsStillQishui && Self.runCommand(
                    script: paths.script,
                    framework: paths.framework,
                    arguments: ["seek", "\(positionMicros)"]
                )
                continuation.resume(returning: didSeek)
            }
        }

        guard didSeek, generation == seekCommandGeneration else {
            return false
        }

        let now = Date()
        seekTimelineAnchor = MediaRemoteSeekTimelineAnchor(
            trackIdentity: currentTrackIdentity,
            targetElapsedTime: elapsedTime,
            elapsedTime: elapsedTime,
            issuedAt: now,
            updatedAt: now,
            isPlaying: currentTrack?.isPlaying ?? true,
            confirmationDeadline: now.addingTimeInterval(5),
            didObserveTarget: false,
            coherentSince: nil
        )
        scheduleSeekTimelineConfirmationTimeout(for: now)
        return true
    }

    private func applyPlaybackPositionPayload(
        _ rawPayload: [String: Any],
        requestSampleID: UInt64? = nil,
        requestSessionGeneration: UInt64? = nil,
        expectedProcessIdentifier: pid_t? = nil,
        receivedAt: Date = Date(),
        receivedUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> MediaRemoteNowPlayingSnapshot? {
        if let requestSessionGeneration,
           requestSessionGeneration != qishuiSessionGeneration {
            return latestSnapshot
        }
        guard let payload = payloadResolvingProcessIdentifier(rawPayload) else {
            return latestSnapshot
        }
        let responseProcessIdentifier = pidValue(payload["processIdentifier"])
        if let expectedProcessIdentifier,
           responseProcessIdentifier != expectedProcessIdentifier {
            return latestSnapshot
        }
        guard payloadProcessIdentityIsConsistent(payload) else {
            return latestSnapshot
        }
        if let responseProcessIdentifier,
           isRetiredSourceProcessIdentifier(responseProcessIdentifier, at: receivedAt) {
            return latestSnapshot
        }
        if let currentProcessIdentifier = pidValue(mergedPayload["processIdentifier"]),
           let responseProcessIdentifier,
           currentProcessIdentifier != responseProcessIdentifier {
            return latestSnapshot
        }
        if let requestSampleID,
           !PlaybackControlTimeline.shouldAcceptAsyncSample(
                requestSampleID: requestSampleID,
                currentSampleID: sampleID,
                responseTrackIdentity: payloadPlaybackTimelineIdentity(payload),
                currentTrackIdentity: playbackPositionAnchor?.trackIdentity
           ) {
            return latestSnapshot
        }
        let merge = mergeObservedStreamPayload(
            payload,
            isDiff: stringValue(payload["title"])?.adapterTrimmedNonEmpty == nil,
            observedAt: receivedAt
        )
        guard merge != .ignoredProcess else { return latestSnapshot }
        recordPlaybackEvidenceIfPresent(
            payload,
            identityPayload: mergedPayload,
            receivedAt: receivedAt
        )
        let shouldDefer = deferredTrackPublicationStartedAt != nil
            ? shouldDeferDeferredTrackPublication(mergedPayload)
            : shouldDeferTrackPublication(
                from: lastPublishedPayload,
                to: mergedPayload
            )
        if shouldDefer {
            beginDeferredTrackPublication(
                timelinePayload: payload,
                startedAt: receivedAt
            )
            if let changeHandler {
                scheduleDeferredTrackPublication(onChange: changeHandler)
            }
            return latestSnapshot
        }
        clearDeferredTrackPublication()
        advanceSample(origin: .synchronousRead)
        let rawSnapshot = snapshot(
            from: mergedPayload,
            existingArtwork: reusableArtwork(for: mergedPayload),
            timelinePayload: payload,
            receivedAt: receivedAt,
            receivedUptime: receivedUptime
        )
        let effectiveSnapshot = remember(snapshot: rawSnapshot)
        if let track = rawSnapshot.currentTrack {
            let signature = trackSignature(track)
            let didChangeTrack = signature != latestSignature
            latestSignature = signature
            _ = requestFreshMetadataIfNeeded(
                for: track,
                didChangeTrack: didChangeTrack,
                onChange: changeHandler
            )
        }
        return effectiveSnapshot
    }

    func applyPlaybackPositionPayloadForTesting(
        _ payload: [String: Any],
        receivedAt: Date,
        receivedUptime: TimeInterval
    ) -> MediaRemoteNowPlayingSnapshot? {
        applyPlaybackPositionPayload(
            payload,
            receivedAt: receivedAt,
            receivedUptime: receivedUptime
        )
    }

    func stop() {
        streamLifecycle.beginStop()
        restartTask?.cancel()
        restartTask = nil
        changeHandler = nil
        let activeProcess = process
        process = nil
        if let pipe = activeProcess?.standardOutput as? Pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        activeProcess?.terminationHandler = nil
        if let activeProcess {
            Self.terminateStreamProcess(activeProcess)
        }
        invalidateQishuiSession(retireProcessIdentifier: false)
    }

    func rebindAfterQishuiRelaunch() {
        guard let changeHandler else {
            invalidateQishuiSession(retireProcessIdentifier: false)
            return
        }

        // The private stream client can be started before Qishui exists. In that
        // state it stays alive but does not necessarily attach when a later
        // Qishui process appears. Restarting here also advances the lifecycle
        // generation, so output from the pre-launch process cannot repopulate
        // the newly cleared session.
        stop()
        start(onChange: changeHandler)
    }

    nonisolated static func terminateStreamProcess(
        _ process: Process,
        graceInterval: TimeInterval = 0.2
    ) {
        guard process.isRunning else { return }
        process.terminate()
        let terminationDeadline = Date().addingTimeInterval(graceInterval)
        while process.isRunning, Date() < terminationDeadline {
            usleep(10_000)
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
        let killDeadline = Date().addingTimeInterval(0.2)
        while process.isRunning, Date() < killDeadline {
            usleep(10_000)
        }
        if !process.isRunning {
            process.waitUntilExit()
        }
    }

    private func consume(_ data: Data, onChange: @escaping ChangeHandler) {
        outputBuffer.append(data)

        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let lineData = outputBuffer.prefix(upTo: newline)
            outputBuffer.removeSubrange(...newline)
            guard !lineData.isEmpty else { continue }
            handleLine(Data(lineData), onChange: onChange)
        }
    }

    private func handleLine(_ lineData: Data, onChange: @escaping ChangeHandler) {
        guard let envelope = decodedStreamEnvelope(lineData) else { return }
        let receivedAt = Date()
        let payload = envelope.payload
        if holdTransientEmptyPayloadIfNeeded(payload) {
            return
        }
        let merge = mergeObservedStreamPayload(
            payload,
            isDiff: envelope.isDiff,
            observedAt: receivedAt
        )
        guard merge != .ignoredProcess else { return }
        if merge != .ambiguousPlaybackPatch {
            recordPlaybackEvidenceIfPresent(
                payload,
                identityPayload: mergedPayload,
                receivedAt: receivedAt
            )
        }

        let shouldDefer = deferredTrackPublicationStartedAt != nil
            ? shouldDeferDeferredTrackPublication(mergedPayload)
            : shouldDeferTrackPublication(from: lastPublishedPayload, to: mergedPayload)
        if shouldDefer {
            beginDeferredTrackPublication(timelinePayload: payload)
            scheduleDeferredTrackPublication(onChange: onChange)
            return
        }

        clearDeferredTrackPublication()
        _ = publishMergedPayload(
            origin: .streamEvent,
            timelinePayload: payload,
            onChange: onChange
        )
    }

    private func publishMergedPayload(
        origin: MediaRemoteSampleOrigin,
        timelinePayload: [String: Any]?,
        onChange: ChangeHandler?,
        receivedAt: Date = Date(),
        receivedUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        allowsMetadataRefresh: Bool = true
    ) -> MediaRemoteNowPlayingSnapshot {
        advanceSample(origin: origin)
        let rawSnapshot = snapshot(
            from: mergedPayload,
            existingArtwork: reusableArtwork(for: mergedPayload),
            timelinePayload: timelinePayload,
            receivedAt: receivedAt,
            receivedUptime: receivedUptime
        )
        let effectiveSnapshot = remember(snapshot: rawSnapshot)
        lastPublishedPayload = mergedPayload
        if let track = rawSnapshot.currentTrack {
            let signature = trackSignature(track)
            let didChangeTrack = signature != latestSignature
            latestSignature = signature
            if allowsMetadataRefresh {
                let didQueueFreshMetadata = requestFreshMetadataIfNeeded(
                    for: track,
                    didChangeTrack: didChangeTrack,
                    onChange: onChange
                )
                if didChangeTrack, track.artworkData == nil, didQueueFreshMetadata {
                    return effectiveSnapshot
                }
            }
        }
        onChange?()
        return effectiveSnapshot
    }

    private func decodedStreamEnvelope(
        _ lineData: Data
    ) -> (payload: [String: Any], isDiff: Bool)? {
        guard let object = try? JSONSerialization.jsonObject(with: lineData),
              let envelope = object as? [String: Any],
              envelope["type"] as? String == "data",
              let payload = envelope["payload"] as? [String: Any] else {
            return nil
        }
        return (payload, boolValue(envelope["diff"]) ?? false)
    }

    private func mergeStreamPayload(
        _ payload: [String: Any],
        isDiff: Bool
    ) -> MediaRemoteStreamPayloadMerge {
        if isDiff {
            mergePayloadFields(payload)
            return .confirmedSameTrack
        }

        switch payloadTrackRelationship(mergedPayload, payload) {
        case .different:
            mergedPayload = payload
            return .replacement
        case .confirmedSameTrack:
            mergePayloadFields(payload)
            return .confirmedSameTrack
        case .ambiguousPlaybackPatch:
            mergePayloadFields(payload.filter {
                Self.ambiguousPlaybackPatchKeys.contains($0.key)
            })
            return .ambiguousPlaybackPatch
        }
    }

    private static let ambiguousPlaybackPatchKeys: Set<String> = [
        "playing",
        "playbackRate",
        "elapsedTime",
        "elapsedTimeNow",
        "timestamp"
    ]

    private static let ambiguousPlaybackPayloadKeys = ambiguousPlaybackPatchKeys.union([
        "bundleIdentifier",
        "processIdentifier",
        "contentItemIdentifier",
        "title",
        "artist",
        "album",
        "duration"
    ])

    private func mergePayloadFields(_ payload: [String: Any]) {
        for (key, value) in payload {
            if value is NSNull {
                mergedPayload.removeValue(forKey: key)
            } else {
                mergedPayload[key] = value
            }
        }
    }

    private func payloadTrackRelationship(
        _ current: [String: Any],
        _ update: [String: Any]
    ) -> MediaRemotePayloadTrackRelationship {
        guard let currentTitle = stringValue(current["title"])?.adapterTrimmedNonEmpty,
              let updateTitle = stringValue(update["title"])?.adapterTrimmedNonEmpty,
              currentTitle == updateTitle else {
            return .different
        }

        if let currentBundle = stringValue(current["bundleIdentifier"])?.adapterTrimmedNonEmpty,
           let updateBundle = stringValue(update["bundleIdentifier"])?.adapterTrimmedNonEmpty,
           currentBundle != updateBundle {
            return .different
        }
        if let currentProcessIdentifier = pidValue(current["processIdentifier"]),
           let updateProcessIdentifier = pidValue(update["processIdentifier"]),
           currentProcessIdentifier != updateProcessIdentifier {
            return .different
        }

        let currentIdentifier = stringValue(current["contentItemIdentifier"])?.adapterTrimmedNonEmpty
        let updateIdentifier = stringValue(update["contentItemIdentifier"])?.adapterTrimmedNonEmpty
        if let currentIdentifier,
           let updateIdentifier,
           currentIdentifier == updateIdentifier {
            return .confirmedSameTrack
        }

        var matchingStableFieldCount = 0
        for key in ["artist", "album"] {
            guard let currentValue = stringValue(current[key])?.adapterTrimmedNonEmpty,
                  let updateValue = stringValue(update[key])?.adapterTrimmedNonEmpty else {
                continue
            }
            guard currentValue.caseInsensitiveCompare(updateValue) == .orderedSame else {
                return .different
            }
            matchingStableFieldCount += 1
        }
        if let currentDuration = doubleValue(current["duration"]),
           let updateDuration = doubleValue(update["duration"]) {
            guard abs(currentDuration - updateDuration) <= 0.75 else {
                return .different
            }
            matchingStableFieldCount += 1
        }
        if matchingStableFieldCount >= 2 {
            return .confirmedSameTrack
        }
        if isAmbiguousPlaybackPayload(update) {
            return .ambiguousPlaybackPatch
        }
        return .different
    }

    private func isAmbiguousPlaybackPayload(_ payload: [String: Any]) -> Bool {
        let hasPlaybackValue = payload.keys.contains {
            Self.ambiguousPlaybackPatchKeys.contains($0)
        }
        return hasPlaybackValue && payload.keys.allSatisfy {
            Self.ambiguousPlaybackPayloadKeys.contains($0)
        }
    }

    private func mergeObservedStreamPayload(
        _ rawPayload: [String: Any],
        isDiff: Bool,
        observedAt: Date = Date()
    ) -> MediaRemoteStreamPayloadMerge {
        guard let payload = payloadResolvingProcessIdentifier(rawPayload) else {
            return .ignoredProcess
        }
        guard payloadProcessIdentityIsConsistent(payload) else {
            return .ignoredProcess
        }
        if let processIdentifier = pidValue(payload["processIdentifier"]),
           isRetiredSourceProcessIdentifier(processIdentifier, at: observedAt) {
            return .ignoredProcess
        }
        let previousPayload = mergedPayload
        let previousIdentity = payloadTrackIdentity(mergedPayload)
        let previousProcessIdentifier = pidValue(mergedPayload["processIdentifier"])
        let merge = mergeStreamPayload(payload, isDiff: isDiff)
        let nextProcessIdentifier = pidValue(mergedPayload["processIdentifier"])
        if let previousProcessIdentifier,
           let nextProcessIdentifier,
           previousProcessIdentifier != nextProcessIdentifier {
            qishuiSessionGeneration &+= 1
            retireSourceProcessIdentifier(previousProcessIdentifier, at: observedAt)
            playbackPositionAnchor = nil
            playbackPositionTrackIdentity = nil
            clearSeekTimelineAnchor()
        }
        let nextIdentity = payloadTrackIdentity(mergedPayload)
        if let nextIdentity, nextIdentity != previousIdentity {
            metadataRequestGeneration += 1
            if deferredTrackPublicationStartedAt != nil {
                appendDeferredTrackReference(previousPayload)
                deferredTrackCandidateIdentity = nextIdentity
                deferredTrackPublicationStartedAt = observedAt
            }
        }
        return merge
    }

    private func retireSourceProcessIdentifier(
        _ processIdentifier: pid_t,
        at now: Date
    ) {
        retiredSourceProcessIdentifiers = retiredSourceProcessIdentifiers.filter {
            now.timeIntervalSince($0.value) <= retiredSourceProcessIdentifierTTL
        }
        retiredSourceProcessIdentifiers[processIdentifier] = now
    }

    private func isRetiredSourceProcessIdentifier(
        _ processIdentifier: pid_t,
        at now: Date
    ) -> Bool {
        guard let retiredAt = retiredSourceProcessIdentifiers[processIdentifier] else {
            return false
        }
        if now.timeIntervalSince(retiredAt) <= retiredSourceProcessIdentifierTTL {
            return true
        }
        retiredSourceProcessIdentifiers.removeValue(forKey: processIdentifier)
        return false
    }

    static func processIdentityIsConsistent(
        bundleIdentifier: String?,
        processIdentifier: pid_t?,
        runningQishuiProcessIdentifiers: Set<pid_t>
    ) -> Bool {
        guard !runningQishuiProcessIdentifiers.isEmpty else { return false }
        if let bundleIdentifier, let processIdentifier {
            return bundleIdentifier == "com.soda.music"
                && runningQishuiProcessIdentifiers.contains(processIdentifier)
        }
        if let processIdentifier {
            return runningQishuiProcessIdentifiers.contains(processIdentifier)
        }
        guard runningQishuiProcessIdentifiers.count == 1 else { return false }
        return bundleIdentifier == nil || bundleIdentifier == "com.soda.music"
    }

    private func payloadResolvingProcessIdentifier(
        _ rawPayload: [String: Any]
    ) -> [String: Any]? {
        let runningProcessIdentifiers = runningQishuiProcessIdentifiersProvider()
        var payload = rawPayload
        if pidValue(payload["processIdentifier"]) == nil {
            let bundleIdentifier = stringValue(payload["bundleIdentifier"])
            let processIdentifier: pid_t?
            if bundleIdentifier == qishuiBundleIdentifier {
                processIdentifier = runningProcessIdentifiers.count == 1
                    ? runningProcessIdentifiers.first
                    : nil
            } else if bundleIdentifier == nil,
                      let currentProcessIdentifier = pidValue(mergedPayload["processIdentifier"]),
                      runningProcessIdentifiers.contains(currentProcessIdentifier) {
                processIdentifier = currentProcessIdentifier
            } else if bundleIdentifier == nil,
                      runningProcessIdentifiers.count == 1 {
                processIdentifier = runningProcessIdentifiers.first
            } else {
                processIdentifier = nil
            }
            guard let processIdentifier else { return nil }
            payload["processIdentifier"] = processIdentifier
        }
        guard Self.processIdentityIsConsistent(
            bundleIdentifier: stringValue(payload["bundleIdentifier"]),
            processIdentifier: pidValue(payload["processIdentifier"]),
            runningQishuiProcessIdentifiers: runningProcessIdentifiers
        ) else {
            return nil
        }
        return payload
    }

    private func payloadProcessIdentityIsConsistent(
        _ payload: [String: Any]
    ) -> Bool {
        return Self.processIdentityIsConsistent(
            bundleIdentifier: stringValue(payload["bundleIdentifier"]),
            processIdentifier: pidValue(payload["processIdentifier"]),
            runningQishuiProcessIdentifiers: runningQishuiProcessIdentifiersProvider()
        )
    }

    private func appendDeferredTrackReference(_ payload: [String: Any]) {
        guard !payload.isEmpty else { return }
        let identity = payloadTrackIdentity(payload)
        guard !deferredTrackReferencePayloads.contains(where: {
            payloadTrackIdentity($0) == identity
        }) else { return }
        deferredTrackReferencePayloads.append(payload)
        if deferredTrackReferencePayloads.count > 6 {
            deferredTrackReferencePayloads.removeFirst()
        }
    }

    private func holdTransientEmptyPayloadIfNeeded(
        _ payload: [String: Any],
        startedAt: Date = Date()
    ) -> Bool {
        guard payload.isEmpty, !lastPublishedPayload.isEmpty else { return false }
        metadataRequestGeneration += 1
        mergedPayload.removeAll()
        beginDeferredTrackPublication(timelinePayload: payload, startedAt: startedAt)
        deferredTrackPublicationTask?.cancel()
        deferredTrackPublicationTask = nil
        deferredTrackPublicationGeneration += 1
        return true
    }

    func ingestStreamEnvelopeForTesting(
        _ lineData: Data,
        receivedAt: Date,
        receivedUptime: TimeInterval
    ) -> MediaRemoteNowPlayingSnapshot? {
        guard let envelope = decodedStreamEnvelope(lineData) else { return nil }
        if holdTransientEmptyPayloadIfNeeded(envelope.payload, startedAt: receivedAt) {
            return latestSnapshot
        }
        let merge = mergeObservedStreamPayload(
            envelope.payload,
            isDiff: envelope.isDiff,
            observedAt: receivedAt
        )
        if merge == .ignoredProcess {
            return latestSnapshot
        }
        if merge != .ambiguousPlaybackPatch {
            recordPlaybackEvidenceIfPresent(
                envelope.payload,
                identityPayload: mergedPayload,
                receivedAt: receivedAt
            )
        }
        let shouldDefer = deferredTrackPublicationStartedAt != nil
            ? shouldDeferDeferredTrackPublication(mergedPayload)
            : shouldDeferTrackPublication(from: lastPublishedPayload, to: mergedPayload)
        if shouldDefer {
            beginDeferredTrackPublication(
                timelinePayload: envelope.payload,
                startedAt: receivedAt
            )
            deferredTrackPublicationGeneration += 1
            return latestSnapshot
        }

        clearDeferredTrackPublication()
        return publishMergedPayload(
            origin: .streamEvent,
            timelinePayload: envelope.payload,
            onChange: nil,
            receivedAt: receivedAt,
            receivedUptime: receivedUptime
        )
    }

    private func shouldDeferTrackPublication(
        from previous: [String: Any],
        to update: [String: Any]
    ) -> Bool {
        guard !previous.isEmpty,
              let previousIdentity = payloadTrackIdentity(previous),
              let updateIdentity = payloadTrackIdentity(update),
              previousIdentity != updateIdentity else {
            return false
        }

        return shouldDeferTrackPublication(
            to: update,
            referencePayloads: [previous]
        )
    }

    private func shouldDeferDeferredTrackPublication(_ update: [String: Any]) -> Bool {
        let references = deferredTrackReferencePayloads.isEmpty
            ? [deferredTrackBaselinePayload ?? lastPublishedPayload]
            : deferredTrackReferencePayloads
        return shouldDeferTrackPublication(to: update, referencePayloads: references)
    }

    private func shouldDeferTrackPublication(
        to update: [String: Any],
        referencePayloads: [[String: Any]]
    ) -> Bool {
        guard payloadArtworkData(update) != nil else { return true }
        return referencePayloads.contains { metadataCarriesOver(from: $0, to: update) }
    }

    private func metadataCarriesOver(
        from previous: [String: Any],
        to update: [String: Any]
    ) -> Bool {

        let previousArtist = stringValue(previous["artist"])?.adapterTrimmedNonEmpty
        let updateArtist = stringValue(update["artist"])?.adapterTrimmedNonEmpty
        let previousAlbum = stringValue(previous["album"])?.adapterTrimmedNonEmpty
        let updateAlbum = stringValue(update["album"])?.adapterTrimmedNonEmpty
        let previousDuration = doubleValue(previous["duration"])
        let updateDuration = doubleValue(update["duration"])
        let artistStayedOld = previousArtist != nil && previousArtist == updateArtist
        let albumStayedOld = previousAlbum != nil && previousAlbum == updateAlbum
        let durationStayedOld = previousDuration != nil
            && updateDuration != nil
            && abs((previousDuration ?? 0) - (updateDuration ?? 0)) < 0.01
        let artworkStayedOld = dataValue(previous["artworkData"]).map {
            $0 == payloadArtworkData(update)
        } ?? false
        return [
            artistStayedOld,
            albumStayedOld,
            durationStayedOld,
            artworkStayedOld
        ].contains(true)
    }

    private func beginDeferredTrackPublication(
        timelinePayload: [String: Any],
        startedAt: Date = Date()
    ) {
        if deferredTrackPublicationStartedAt == nil {
            deferredTrackPublicationStartedAt = startedAt
            deferredTrackBaselinePayload = lastPublishedPayload
            deferredTrackReferencePayloads = lastPublishedPayload.isEmpty
                ? []
                : [lastPublishedPayload]
            deferredTrackCandidateIdentity = payloadTrackIdentity(mergedPayload)
        }
        deferredTimelinePayload = timelinePayload
    }

    private func clearDeferredTrackPublication() {
        deferredTrackPublicationTask?.cancel()
        deferredTrackPublicationTask = nil
        deferredTrackPublicationStartedAt = nil
        deferredTrackBaselinePayload = nil
        deferredTrackReferencePayloads.removeAll()
        deferredTrackCandidateIdentity = nil
        deferredTimelinePayload = nil
        deferredTrackPublicationGeneration += 1
    }

    private func scheduleDeferredTrackPublication(
        onChange: @escaping ChangeHandler,
        delayNanoseconds: UInt64 = 180_000_000
    ) {
        deferredTrackPublicationGeneration += 1
        let generation = deferredTrackPublicationGeneration
        let targetIdentity = deferredTrackCandidateIdentity ?? payloadTrackIdentity(mergedPayload)
        deferredTrackPublicationTask?.cancel()
        deferredTrackPublicationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled, let self,
                  generation == self.deferredTrackPublicationGeneration else { return }

            if let paths = self.adapterPaths() {
                let bundleIdentifier = self.qishuiBundleIdentifier
                let data = await Task.detached(priority: .userInitiated) {
                    Self.runGetData(
                        script: paths.script,
                        framework: paths.framework,
                        bundleIdentifier: bundleIdentifier,
                        includeArtwork: true
                    )
                }.value
                guard !Task.isCancelled,
                      generation == self.deferredTrackPublicationGeneration else { return }
                if let data,
                   let object = try? JSONSerialization.jsonObject(with: data),
                   let rawPayload = object as? [String: Any],
                   let payload = self.payloadResolvingProcessIdentifier(rawPayload),
                   pidValue(payload["processIdentifier"]).map({
                       !self.isRetiredSourceProcessIdentifier($0, at: Date())
                   }) ?? true,
                   self.payloadTrackIdentity(payload) == targetIdentity {
                    self.mergedPayload = payload
                    self.recordPlaybackEvidenceIfPresent(
                        payload,
                        identityPayload: payload,
                        receivedAt: Date()
                    )
                    if self.shouldDeferDeferredTrackPublication(payload),
                       Date().timeIntervalSince(
                        self.deferredTrackPublicationStartedAt ?? Date()
                       ) < 2.4 {
                        self.deferredTrackPublicationTask = nil
                        self.scheduleDeferredTrackPublication(
                            onChange: onChange,
                            delayNanoseconds: 140_000_000
                        )
                        return
                    }
                } else if Date().timeIntervalSince(
                    self.deferredTrackPublicationStartedAt ?? Date()
                ) < 2.4 {
                    self.deferredTrackPublicationTask = nil
                    self.scheduleDeferredTrackPublication(
                        onChange: onChange,
                        delayNanoseconds: 140_000_000
                    )
                    return
                }
            }

            let timelinePayload = self.deferredTimelinePayload
            let references = self.deferredTrackReferencePayloads
            let shouldSanitize = self.shouldDeferDeferredTrackPublication(self.mergedPayload)
            if shouldSanitize {
                self.mergedPayload = self.sanitizedTrackTransitionPayload(
                    self.mergedPayload,
                    previousPayloads: references
                )
            }
            self.clearDeferredTrackPublication()
            _ = self.publishMergedPayload(
                origin: .synchronousRead,
                timelinePayload: timelinePayload,
                onChange: onChange,
                allowsMetadataRefresh: false
            )
        }
    }

    func forceDeferredTrackPublicationForTesting(
        receivedAt: Date,
        receivedUptime: TimeInterval
    ) -> MediaRemoteNowPlayingSnapshot? {
        guard deferredTrackPublicationStartedAt != nil else { return latestSnapshot }
        let timelinePayload = deferredTimelinePayload
        mergedPayload = sanitizedTrackTransitionPayload(
            mergedPayload,
            previousPayloads: deferredTrackReferencePayloads
        )
        clearDeferredTrackPublication()
        return publishMergedPayload(
            origin: .synchronousRead,
            timelinePayload: timelinePayload,
            onChange: nil,
            receivedAt: receivedAt,
            receivedUptime: receivedUptime,
            allowsMetadataRefresh: false
        )
    }

    private func remember(snapshot rawSnapshot: MediaRemoteNowPlayingSnapshot) -> MediaRemoteNowPlayingSnapshot {
        latestRawSnapshot = rawSnapshot

        if rawSnapshot.isVerifiedQishuiSource, rawSnapshot.currentTrack != nil {
            lastVerifiedQishuiSnapshot = rawSnapshot
            latestSnapshot = rawSnapshot
            return rawSnapshot
        }

        if let cachedSnapshot = recentQishuiSnapshot(whileCurrentSourceIs: rawSnapshot) {
            latestSnapshot = cachedSnapshot
            return cachedSnapshot
        }

        latestSnapshot = rawSnapshot
        return rawSnapshot
    }

    private func recentQishuiSnapshot(
        whileCurrentSourceIs rawSnapshot: MediaRemoteNowPlayingSnapshot
    ) -> MediaRemoteNowPlayingSnapshot? {
        guard let cachedSnapshot = lastVerifiedQishuiSnapshot,
              let cachedTrack = cachedSnapshot.currentTrack else {
            return nil
        }

        let now = Date()
        guard now.timeIntervalSince(cachedSnapshot.checkedAt) <= lastVerifiedQishuiSnapshotTTL else {
            lastVerifiedQishuiSnapshot = nil
            return nil
        }

        guard !runningQishuiProcessIdentifiersProvider().isEmpty else {
            lastVerifiedQishuiSnapshot = nil
            return nil
        }

        let track = cachedDisplayTrack(from: cachedTrack, cachedAt: cachedSnapshot.checkedAt, now: now)
        return MediaRemoteNowPlayingSnapshot(
            isAvailable: true,
            isVerifiedQishuiSource: true,
            currentTrack: track,
            diagnostic: "\(rawSnapshot.diagnostic) 已保持最近一次汽水音乐可信状态用于显示。",
            checkedAt: now,
            sampleID: cachedSnapshot.sampleID,
            sampleOrigin: .cached,
            sampleSource: .adapterStream
        )
    }

    private func cachedDisplayTrack(
        from track: MediaRemoteNowPlayingTrack,
        cachedAt: Date,
        now: Date
    ) -> MediaRemoteNowPlayingTrack {
        let elapsed: TimeInterval?
        let progress: Double
        if track.isPlaying == true,
           let cachedElapsed = track.elapsedTime,
           let duration = track.duration,
           duration > 0 {
            let liveElapsed = min(max(cachedElapsed + now.timeIntervalSince(cachedAt), 0), duration)
            elapsed = liveElapsed
            progress = min(max(liveElapsed / duration, 0), 1)
        } else {
            elapsed = track.elapsedTime
            progress = track.progress
        }

        return MediaRemoteNowPlayingTrack(
            title: track.title,
            artist: track.artist,
            album: track.album,
            artworkData: track.artworkData,
            isPlaying: track.isPlaying,
            progress: progress,
            elapsedTime: elapsed,
            duration: track.duration,
            sourceBundleIdentifier: track.sourceBundleIdentifier,
            sourceProcessIdentifier: track.sourceProcessIdentifier,
            sourceName: "MediaRemote Adapter Stream (recent Qishui)"
        )
    }

    private func snapshot(
        from payload: [String: Any],
        existingArtwork: Data?,
        timelinePayload: [String: Any]?,
        receivedAt: Date = Date(),
        receivedUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> MediaRemoteNowPlayingSnapshot {
        let checkedAt = receivedAt
        guard !payload.isEmpty else {
            return MediaRemoteNowPlayingSnapshot(
                isAvailable: true,
                isVerifiedQishuiSource: false,
                currentTrack: nil,
                diagnostic: "MediaRemote Adapter 暂无播放数据。",
                checkedAt: checkedAt,
                sampleID: sampleID,
                sampleOrigin: sampleOrigin,
                sampleSource: .adapterStream
            )
        }

        let bundleID = stringValue(payload["bundleIdentifier"])
        let pid = pidValue(payload["processIdentifier"])
        let verified = payloadProcessIdentityIsConsistent(payload)
            && (bundleID == qishuiBundleIdentifier || isQishuiPID(pid))
        guard verified else {
            let source = bundleID ?? pid.map { "pid \($0)" } ?? "unknown"
            return MediaRemoteNowPlayingSnapshot(
                isAvailable: true,
                isVerifiedQishuiSource: false,
                currentTrack: nil,
                diagnostic: "MediaRemote Adapter 当前来源不是汽水音乐：\(source)。",
                checkedAt: checkedAt,
                sampleID: sampleID,
                sampleOrigin: sampleOrigin,
                sampleSource: .adapterStream
            )
        }

        guard let title = stringValue(payload["title"])?.adapterTrimmedNonEmpty else {
            return MediaRemoteNowPlayingSnapshot(
                isAvailable: true,
                isVerifiedQishuiSource: true,
                currentTrack: nil,
                diagnostic: "MediaRemote Adapter 已确认汽水来源，但未给出歌名。",
                checkedAt: checkedAt,
                sampleID: sampleID,
                sampleOrigin: sampleOrigin,
                sampleSource: .adapterStream
            )
        }

        let artist = stringValue(payload["artist"])?.adapterTrimmedNonEmpty ?? "汽水音乐"
        let album = stringValue(payload["album"])?.adapterTrimmedNonEmpty
        let duration = doubleValue(payload["duration"])
        let isPlaying = boolValue(payload["playing"])
            ?? doubleValue(payload["playbackRate"]).map { $0 > 0.01 }
        let timelineIdentity = trackTimelineIdentity(
            bundleIdentifier: bundleID,
            processIdentifier: pid,
            contentItemIdentifier: stringValue(payload["contentItemIdentifier"])?.adapterTrimmedNonEmpty,
            title: title,
            artist: artist,
            album: album,
            duration: duration
        )
        let elapsed = resolvedElapsedTime(
            from: payload,
            timelinePayload: timelinePayload,
            trackIdentity: timelineIdentity,
            isPlaying: isPlaying,
            duration: duration,
            receivedAt: receivedAt,
            receivedUptime: receivedUptime
        )
        let progress: Double
        if let elapsed, let duration, duration > 0 {
            progress = min(max(elapsed / duration, 0), 1)
        } else {
            progress = 0
        }

        let payloadSignature = [
            bundleID ?? "",
            title,
            artist,
            album ?? ""
        ].joined(separator: "\u{1f}")
        let artworkData = dataValue(payload["artworkData"]) ?? existingArtwork ?? artworkCache[payloadSignature]
        if let artworkData {
            rememberArtwork(artworkData, for: payloadSignature)
        }
        let track = MediaRemoteNowPlayingTrack(
            title: title,
            artist: artist,
            album: album,
            artworkData: artworkData,
            isPlaying: isPlaying,
            progress: progress,
            elapsedTime: elapsed,
            duration: duration,
            sourceBundleIdentifier: bundleID,
            sourceProcessIdentifier: pid,
            sourceName: "MediaRemote Adapter Stream"
        )

        return MediaRemoteNowPlayingSnapshot(
            isAvailable: true,
            isVerifiedQishuiSource: true,
            currentTrack: track,
            diagnostic: "已通过 MediaRemote Adapter 实时读取汽水音乐；来源 \(bundleID ?? "pid \(pid ?? 0)")，封面 \(artworkData.map { "\($0.count) bytes" } ?? "补充中")。",
            checkedAt: checkedAt,
            sampleID: sampleID,
            sampleOrigin: sampleOrigin,
            sampleSource: .adapterStream
        )
    }

    private func advanceSample(origin: MediaRemoteSampleOrigin) {
        sampleID &+= 1
        sampleOrigin = origin
    }

    private func recordPlaybackEvidenceIfPresent(
        _ payload: [String: Any],
        identityPayload: [String: Any],
        receivedAt: Date
    ) {
        let hasPlaybackState = boolValue(payload["playing"]) != nil
            || doubleValue(payload["playbackRate"]) != nil
        let hasPlaybackPosition = doubleValue(payload["elapsedTimeNow"]) != nil
            || doubleValue(payload["elapsedTime"]) != nil
        guard hasPlaybackState || hasPlaybackPosition,
              let identity = payloadTrackIdentity(identityPayload) else {
            return
        }
        lastPlaybackEvidenceAt = receivedAt
        lastPlaybackEvidenceTrackIdentity = identity
    }

    private func requestFreshMetadataIfNeeded(
        for track: MediaRemoteNowPlayingTrack?,
        didChangeTrack: Bool,
        onChange: ChangeHandler?
    ) -> Bool {
        guard let track else { return false }
        let needsArtist = track.artist == "汽水音乐"
        let needsArtwork = track.artworkData == nil
        guard needsArtist || needsArtwork else { return false }
        return requestFreshMetadata(for: track, onChange: onChange, force: didChangeTrack)
    }

    nonisolated static func streamArguments(
        script: String,
        framework: String,
        bundleIdentifier: String
    ) -> [String] {
        [
            script,
            framework,
            "stream-client",
            bundleIdentifier,
            "--debounce=40",
            "--no-diff"
        ]
    }

    private func requestFreshMetadata(
        for track: MediaRemoteNowPlayingTrack,
        onChange: ChangeHandler?,
        force: Bool = false
    ) -> Bool {
        guard let onChange, let paths = adapterPaths() else { return false }
        let lookupKey = trackLookupKey(track)
        if artworkFetchInFlight {
            pendingArtworkRequestLookupKey = lookupKey
            return true
        }

        let now = Date()
        if !force,
           lastArtworkRequestLookupKey == lookupKey,
           let lastArtworkRequestAt,
           now.timeIntervalSince(lastArtworkRequestAt) < 0.35 {
            return false
        }
        lastArtworkRequestLookupKey = lookupKey
        lastArtworkRequestAt = now
        artworkFetchInFlight = true
        let requestGeneration = metadataRequestGeneration
        let requestSessionGeneration = qishuiSessionGeneration
        let expectedProcessIdentifier = track.sourceProcessIdentifier
            ?? pidValue(mergedPayload["processIdentifier"])

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let payload = Self.runGet(
                script: paths.script,
                framework: paths.framework,
                bundleIdentifier: self?.qishuiBundleIdentifier ?? "com.soda.music",
                includeArtwork: true
            )
            Task { @MainActor in
                guard let self else { return }
                self.artworkFetchInFlight = false
                guard requestGeneration == self.metadataRequestGeneration,
                      self.deferredTrackPublicationStartedAt == nil else {
                    self.requestPendingFreshMetadataIfNeeded(
                        onChange: onChange,
                        completedLookupKey: nil
                    )
                    return
                }
                let receivedAt = Date()
                guard let payload,
                      let payload = self.validatedMetadataPayload(
                        payload,
                        requestSessionGeneration: requestSessionGeneration,
                        expectedProcessIdentifier: expectedProcessIdentifier,
                        receivedAt: receivedAt
                      ) else {
                    self.requestPendingFreshMetadataIfNeeded(onChange: onChange, completedLookupKey: nil)
                    return
                }
                let nextSnapshot = self.metadataSnapshot(
                    from: payload,
                    existingArtwork: nil,
                    receivedAt: receivedAt,
                    receivedUptime: ProcessInfo.processInfo.systemUptime
                )
                guard let nextTrack = nextSnapshot.currentTrack else {
                    _ = self.remember(snapshot: nextSnapshot)
                    self.requestPendingFreshMetadataIfNeeded(onChange: onChange, completedLookupKey: nil)
                    return
                }
                let currentTrack = self.latestSnapshot?.currentTrack
                guard currentTrack.map({ self.metadataResponse(nextTrack, matches: $0) }) ?? true else {
                    self.requestPendingFreshMetadataIfNeeded(onChange: onChange, completedLookupKey: self.trackLookupKey(nextTrack))
                    return
                }
                let responseLookupKey = self.trackLookupKey(nextTrack)
                self.mergeMetadata(from: payload)
                let mergedSnapshot = self.metadataSnapshot(
                    from: self.mergedPayload,
                    existingArtwork: nextTrack.artworkData,
                    receivedAt: Date(),
                    receivedUptime: ProcessInfo.processInfo.systemUptime
                )
                _ = self.remember(snapshot: mergedSnapshot)
                self.lastPublishedPayload = self.mergedPayload
                if let mergedTrack = mergedSnapshot.currentTrack {
                    self.latestSignature = self.trackSignature(mergedTrack)
                }
                onChange()
                self.requestPendingFreshMetadataIfNeeded(onChange: onChange, completedLookupKey: responseLookupKey)
            }
        }
        return true
    }

    private func metadataSnapshot(
        from payload: [String: Any],
        existingArtwork: Data?,
        receivedAt: Date,
        receivedUptime: TimeInterval
    ) -> MediaRemoteNowPlayingSnapshot {
        snapshot(
            from: payload,
            existingArtwork: existingArtwork,
            timelinePayload: nil,
            receivedAt: receivedAt,
            receivedUptime: receivedUptime
        )
    }

    func applyMetadataPayloadForTesting(
        _ rawPayload: [String: Any],
        receivedAt: Date,
        receivedUptime: TimeInterval,
        requestGeneration: Int? = nil
    ) -> MediaRemoteNowPlayingSnapshot? {
        if let requestGeneration, requestGeneration != metadataRequestGeneration {
            return latestSnapshot
        }
        if deferredTrackPublicationStartedAt != nil {
            return latestSnapshot
        }
        guard let payload = validatedMetadataPayload(
            rawPayload,
            requestSessionGeneration: qishuiSessionGeneration,
            expectedProcessIdentifier: pidValue(mergedPayload["processIdentifier"]),
            receivedAt: receivedAt
        ) else {
            return latestSnapshot
        }
        mergeMetadata(from: payload)
        let rawSnapshot = metadataSnapshot(
            from: mergedPayload,
            existingArtwork: reusableArtwork(for: mergedPayload),
            receivedAt: receivedAt,
            receivedUptime: receivedUptime
        )
        let effectiveSnapshot = remember(snapshot: rawSnapshot)
        lastPublishedPayload = mergedPayload
        return effectiveSnapshot
    }

    func metadataRequestGenerationForTesting() -> Int {
        metadataRequestGeneration
    }

    private func mergeMetadata(from payload: [String: Any]) {
        for key in ["artist", "album", "artworkData"] {
            guard let value = payload[key] else { continue }
            if value is NSNull {
                mergedPayload.removeValue(forKey: key)
            } else {
                mergedPayload[key] = value
            }
        }
    }

    private func validatedMetadataPayload(
        _ rawPayload: [String: Any],
        requestSessionGeneration: UInt64,
        expectedProcessIdentifier: pid_t?,
        receivedAt: Date
    ) -> [String: Any]? {
        guard requestSessionGeneration == qishuiSessionGeneration,
              let payload = payloadResolvingProcessIdentifier(rawPayload) else {
            return nil
        }
        let responseProcessIdentifier = pidValue(payload["processIdentifier"])
        if let expectedProcessIdentifier,
           responseProcessIdentifier != expectedProcessIdentifier {
            return nil
        }
        if let responseProcessIdentifier,
           isRetiredSourceProcessIdentifier(responseProcessIdentifier, at: receivedAt) {
            return nil
        }
        if let currentProcessIdentifier = pidValue(mergedPayload["processIdentifier"]),
           responseProcessIdentifier != currentProcessIdentifier {
            return nil
        }
        return payload
    }

    private func requestPendingFreshMetadataIfNeeded(onChange: ChangeHandler?, completedLookupKey: String?) {
        guard let pendingLookupKey = pendingArtworkRequestLookupKey else { return }
        pendingArtworkRequestLookupKey = nil

        guard pendingLookupKey != completedLookupKey,
              let track = latestSnapshot?.currentTrack else {
            return
        }
        _ = requestFreshMetadata(for: track, onChange: onChange, force: true)
    }

    nonisolated private static func runGet(
        script: URL,
        framework: URL,
        bundleIdentifier: String,
        includeArtwork: Bool
    ) -> [String: Any]? {
        guard let data = runGetData(
            script: script,
            framework: framework,
            bundleIdentifier: bundleIdentifier,
            includeArtwork: includeArtwork
        ),
        let object = try? JSONSerialization.jsonObject(with: data),
        let payload = object as? [String: Any] else {
            return nil
        }
        return payload
    }

    nonisolated private static func runGetData(
        script: URL,
        framework: URL,
        bundleIdentifier: String?,
        includeArtwork: Bool
    ) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        var arguments = [script.path, framework.path]
        if let bundleIdentifier {
            arguments += ["get-client", bundleIdentifier]
        } else {
            arguments.append("get")
        }
        arguments.append("--now")
        if !includeArtwork {
            arguments.append("--no-artwork")
        }
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            let outputBuffer = MediaRemoteProcessOutputBuffer()
            let outputFinished = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .utility).async {
                outputBuffer.store(output.fileHandleForReading.readDataToEndOfFile())
                outputFinished.signal()
            }

            let deadline = Date().addingTimeInterval(includeArtwork ? 0.9 : 2.0)
            while process.isRunning, Date() < deadline {
                usleep(20_000)
            }
            if process.isRunning {
                process.terminate()
                let terminationDeadline = Date().addingTimeInterval(0.2)
                while process.isRunning, Date() < terminationDeadline {
                    usleep(10_000)
                }
                if process.isRunning {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                }
            }
            let exitDeadline = Date().addingTimeInterval(0.2)
            while process.isRunning, Date() < exitDeadline {
                usleep(10_000)
            }
            guard !process.isRunning else { return nil }
            _ = outputFinished.wait(timeout: .now() + 0.5)
            return process.terminationStatus == 0 ? outputBuffer.value() : nil
        } catch {
            return nil
        }
    }

    nonisolated private static func runCommand(
        script: URL,
        framework: URL,
        arguments: [String]
    ) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, framework.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(2.0)
            while process.isRunning, Date() < deadline {
                usleep(20_000)
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                return false
            }
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    nonisolated private static func isCurrentQishuiPlaybackSource(
        script: URL,
        framework: URL,
        bundleIdentifier: String,
        expectedProcessIdentifier: pid_t?
    ) -> Bool {
        guard let expectedProcessIdentifier,
              let data = runGetData(
                  script: script,
                  framework: framework,
                  bundleIdentifier: nil,
                  includeArtwork: false
              ),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any],
              payload["bundleIdentifier"] as? String == bundleIdentifier else {
            return false
        }

        let processIdentifier: pid_t?
        if let value = payload["processIdentifier"] as? NSNumber {
            processIdentifier = value.int32Value
        } else if let value = payload["processIdentifier"] as? String {
            processIdentifier = Int32(value)
        } else {
            processIdentifier = nil
        }
        return processIdentifier == expectedProcessIdentifier
    }

    nonisolated static func runGetDataForTesting(
        script: URL,
        includeArtwork: Bool
    ) -> Data? {
        runGetData(
            script: script,
            framework: URL(fileURLWithPath: "/tmp/TestMediaRemoteAdapter.framework"),
            bundleIdentifier: "com.soda.music",
            includeArtwork: includeArtwork
        )
    }

    private func resolvedElapsedTime(
        from payload: [String: Any],
        timelinePayload: [String: Any]?,
        trackIdentity: MediaRemoteTrackTimelineIdentity,
        isPlaying: Bool?,
        duration: TimeInterval?,
        receivedAt: Date,
        receivedUptime: TimeInterval
    ) -> TimeInterval? {
        let identity = playbackTimelineIdentity(from: payload, fallback: trackIdentity)
        if let timelinePayload {
            let sourceTimestamp = stringValue(timelinePayload["timestamp"])
                .flatMap { ISO8601DateFormatter().date(from: $0) }
            if let candidate = PlaybackControlTimeline.authoritativeAnchor(
                trackIdentity: identity,
                elapsedTime: doubleValue(timelinePayload["elapsedTime"]),
                elapsedTimeNow: doubleValue(timelinePayload["elapsedTimeNow"]),
                sourceTimestamp: sourceTimestamp,
                playbackRate: doubleValue(timelinePayload["playbackRate"])
                    ?? doubleValue(payload["playbackRate"]),
                isPlaying: isPlaying,
                duration: duration,
                receivedAt: receivedAt,
                receivedUptime: receivedUptime
            ) {
                let acceptedAnchor = PlaybackControlTimeline.accepting(
                    candidate,
                    over: playbackPositionAnchor
                )
                playbackPositionAnchor = acceptedAnchor
                if acceptedAnchor.trackIdentity == candidate.trackIdentity {
                    playbackPositionTrackIdentity = trackIdentity
                }
            }
        }
        let rawElapsed = playbackPositionAnchor.flatMap { anchor -> TimeInterval? in
            let structuredIdentityMatches = playbackPositionTrackIdentity.map {
                timelineIdentity($0, matches: trackIdentity)
            } ?? false
            guard anchor.trackIdentity == identity || structuredIdentityMatches else {
                return nil
            }
            if structuredIdentityMatches {
                playbackPositionTrackIdentity = trackIdentity
            }
            return PlaybackControlTimeline.elapsed(from: anchor, nowUptime: receivedUptime)
        } ?? doubleValue(payload["elapsedTimeNow"])
            ?? currentElapsedTime(from: payload)
            ?? doubleValue(payload["elapsedTime"])
        guard var anchor = seekTimelineAnchor else { return rawElapsed }
        guard timelineIdentity(anchor.trackIdentity, matches: trackIdentity) else {
            clearSeekTimelineAnchor()
            return rawElapsed
        }

        let now = Date()
        if anchor.isPlaying {
            anchor.elapsedTime += max(now.timeIntervalSince(anchor.updatedAt), 0)
        }
        anchor.updatedAt = now
        if let isPlaying {
            anchor.isPlaying = isPlaying
        }
        let elapsed = anchor.elapsedTime
        let rawBaseElapsed = doubleValue(payload["elapsedTime"])
        let hasFreshTimestamp = stringValue(payload["timestamp"])
            .flatMap { ISO8601DateFormatter().date(from: $0) }
            .map { $0 >= anchor.issuedAt.addingTimeInterval(-0.5) }
            ?? false
        if let rawBaseElapsed,
           abs(rawBaseElapsed - anchor.targetElapsedTime) <= 1.0 {
            anchor.didObserveTarget = true
        }
        if hasFreshTimestamp,
           let rawElapsed,
           abs(rawElapsed - elapsed) <= 1.0 {
            anchor.didObserveTarget = true
        }
        guard anchor.didObserveTarget || now < anchor.confirmationDeadline else {
            clearSeekTimelineAnchor()
            return rawElapsed
        }

        if hasFreshTimestamp, let rawElapsed, abs(rawElapsed - elapsed) <= 1.0 {
            if let coherentSince = anchor.coherentSince,
               now.timeIntervalSince(coherentSince) >= 0.8 {
                clearSeekTimelineAnchor()
                return rawElapsed
            }
            anchor.coherentSince = anchor.coherentSince ?? now
        } else {
            anchor.coherentSince = nil
        }
        seekTimelineAnchor = anchor
        if let duration, duration > 0 {
            return min(max(elapsed, 0), duration)
        }
        return max(elapsed, 0)
    }

    private func playbackTimelineIdentity(
        from payload: [String: Any],
        fallback: MediaRemoteTrackTimelineIdentity
    ) -> String {
        payloadPlaybackTimelineIdentity(payload) ?? [
            fallback.bundleIdentifier ?? "",
            fallback.processIdentifier.map(String.init) ?? "",
            fallback.title,
            fallback.artist ?? "",
            fallback.album ?? "",
            fallback.duration.map { String(format: "%.3f", $0) } ?? ""
        ].joined(separator: "\u{1f}")
    }

    private func payloadPlaybackTimelineIdentity(_ payload: [String: Any]) -> String? {
        payloadTrackIdentity(payload)
    }

    private func currentElapsedTime(from payload: [String: Any]) -> Double? {
        guard let elapsed = doubleValue(payload["elapsedTime"]) else { return nil }
        guard let timestampText = stringValue(payload["timestamp"]),
              let timestamp = ISO8601DateFormatter().date(from: timestampText) else {
            return elapsed
        }
        let playbackRate = doubleValue(payload["playbackRate"]) ?? 0
        guard playbackRate >= 0 else { return elapsed }
        return elapsed + Date().timeIntervalSince(timestamp) * playbackRate
    }

    private func scheduleSeekTimelineConfirmationTimeout(for anchorIssuedAt: Date) {
        seekTimelineConfirmationTask?.cancel()
        seekTimelineConfirmationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self,
                  let anchor = self.seekTimelineAnchor,
                  anchor.issuedAt == anchorIssuedAt,
                  !anchor.didObserveTarget,
                  Date() >= anchor.confirmationDeadline else {
                return
            }
            self.seekTimelineAnchor = nil
            self.seekTimelineConfirmationTask = nil
            _ = await self.refreshPlaybackPositionAsync()
            self.changeHandler?()
        }
    }

    private func clearSeekTimelineAnchor() {
        seekTimelineAnchor = nil
        seekTimelineConfirmationTask?.cancel()
        seekTimelineConfirmationTask = nil
    }

    private func adapterPaths() -> (script: URL, framework: URL)? {
        let candidates: [URL] = [
            Bundle.main.resourceURL?.appendingPathComponent("MediaRemoteAdapter"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Vendor/MediaRemoteAdapter"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Vendor/MediaRemoteAdapter")
        ].compactMap { $0 }

        for root in candidates {
            let script = root.appendingPathComponent("mediaremote-adapter.pl")
            let framework = root.appendingPathComponent("MediaRemoteAdapter.framework")
            if FileManager.default.fileExists(atPath: script.path),
               FileManager.default.fileExists(atPath: framework.path) {
                return (script, framework)
            }
        }
        return nil
    }

    private func isQishuiPID(_ pid: pid_t?) -> Bool {
        guard let pid,
              let app = NSRunningApplication(processIdentifier: pid) else {
            return false
        }
        return app.bundleIdentifier == qishuiBundleIdentifier
            || app.executableURL?.path.hasPrefix("/Applications/汽水音乐.app/") == true
            || app.bundleURL?.path.hasPrefix("/Applications/汽水音乐.app/") == true
    }

    private func runningQishuiProcessIdentifier() -> pid_t? {
        let identifiers = runningQishuiProcessIdentifiersProvider()
        guard identifiers.count == 1 else { return nil }
        return identifiers.first
    }

    private func scheduleRestart(
        onChange: @escaping ChangeHandler,
        generation: UInt64
    ) {
        guard restartTask == nil,
              process == nil,
              streamLifecycle.accepts(generation) else { return }
        restartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled,
                  let self,
                  streamLifecycle.accepts(generation),
                  process == nil else { return }
            restartTask = nil
            start(onChange: onChange)
        }
    }

    private func trackSignature(_ track: MediaRemoteNowPlayingTrack) -> String {
        [
            track.sourceBundleIdentifier ?? "",
            track.title,
            track.artist,
            track.album ?? ""
        ].joined(separator: "\u{1f}")
    }

    private func trackTimelineIdentity(_ track: MediaRemoteNowPlayingTrack) -> MediaRemoteTrackTimelineIdentity {
        trackTimelineIdentity(
            bundleIdentifier: track.sourceBundleIdentifier,
            processIdentifier: track.sourceProcessIdentifier,
            contentItemIdentifier: nil,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration
        )
    }

    private func trackTimelineIdentity(
        bundleIdentifier: String?,
        processIdentifier: pid_t?,
        contentItemIdentifier: String?,
        title: String,
        artist: String,
        album: String?,
        duration: TimeInterval?
    ) -> MediaRemoteTrackTimelineIdentity {
        MediaRemoteTrackTimelineIdentity(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            contentItemIdentifier: contentItemIdentifier,
            title: title,
            artist: artist == "汽水音乐" ? nil : artist,
            album: album,
            duration: duration
        )
    }

    private func timelineIdentity(
        _ current: MediaRemoteTrackTimelineIdentity,
        matches update: MediaRemoteTrackTimelineIdentity
    ) -> Bool {
        guard current.title == update.title else { return false }
        if let currentBundle = current.bundleIdentifier,
           let updateBundle = update.bundleIdentifier,
           currentBundle != updateBundle {
            return false
        }
        if let currentProcessIdentifier = current.processIdentifier,
           let updateProcessIdentifier = update.processIdentifier,
           currentProcessIdentifier != updateProcessIdentifier {
            return false
        }

        var matchingStableFieldCount = 0
        if let currentDuration = current.duration,
           let updateDuration = update.duration,
           abs(currentDuration - updateDuration) > 0.75 {
            return false
        } else if current.duration != nil, update.duration != nil {
            matchingStableFieldCount += 1
        }
        if let currentArtist = current.artist,
           let updateArtist = update.artist,
           currentArtist.caseInsensitiveCompare(updateArtist) != .orderedSame {
            return false
        } else if current.artist != nil, update.artist != nil {
            matchingStableFieldCount += 1
        }
        if let currentAlbum = current.album,
           let updateAlbum = update.album,
           currentAlbum.caseInsensitiveCompare(updateAlbum) != .orderedSame {
            return false
        } else if current.album != nil, update.album != nil {
            matchingStableFieldCount += 1
        }
        let contentItemIdentifierMatches = current.contentItemIdentifier.map {
            $0 == update.contentItemIdentifier
        } ?? false
        return matchingStableFieldCount >= 2 || contentItemIdentifierMatches
    }

    func timelineIdentitiesMatchForTesting(
        _ currentPayload: [String: Any],
        _ updatePayload: [String: Any]
    ) -> Bool {
        func identity(from payload: [String: Any]) -> MediaRemoteTrackTimelineIdentity? {
            guard let title = stringValue(payload["title"])?.adapterTrimmedNonEmpty else {
                return nil
            }
            return MediaRemoteTrackTimelineIdentity(
                bundleIdentifier: stringValue(payload["bundleIdentifier"]),
                processIdentifier: pidValue(payload["processIdentifier"]),
                contentItemIdentifier: stringValue(payload["contentItemIdentifier"])?.adapterTrimmedNonEmpty,
                title: title,
                artist: stringValue(payload["artist"])?.adapterTrimmedNonEmpty,
                album: stringValue(payload["album"])?.adapterTrimmedNonEmpty,
                duration: doubleValue(payload["duration"])
            )
        }

        guard let current = identity(from: currentPayload),
              let update = identity(from: updatePayload) else {
            return false
        }
        return timelineIdentity(current, matches: update)
    }

    private func trackLookupKey(_ track: MediaRemoteNowPlayingTrack) -> String {
        [
            track.sourceBundleIdentifier ?? track.sourceProcessIdentifier.map { "pid:\($0)" } ?? "",
            track.title
        ].joined(separator: "\u{1f}")
    }

    private func payloadTrackIdentity(_ payload: [String: Any]) -> String? {
        let contentIdentifier = stringValue(payload["contentItemIdentifier"])?.adapterTrimmedNonEmpty
        let title = stringValue(payload["title"])?.adapterTrimmedNonEmpty
        guard contentIdentifier != nil || title != nil else { return nil }
        let artist = stringValue(payload["artist"])?.adapterTrimmedNonEmpty
        let album = stringValue(payload["album"])?.adapterTrimmedNonEmpty
        let duration = doubleValue(payload["duration"])
        if let title, artist != nil || album != nil || duration != nil {
            return [
                stringValue(payload["bundleIdentifier"]) ?? "",
                pidValue(payload["processIdentifier"]).map(String.init) ?? "",
                title,
                artist?.lowercased() ?? "",
                album?.lowercased() ?? "",
                duration.map { String(format: "%.3f", $0) } ?? ""
            ].joined(separator: "\u{1f}")
        }
        return [
            stringValue(payload["bundleIdentifier"]) ?? "",
            pidValue(payload["processIdentifier"]).map(String.init) ?? "",
            contentIdentifier ?? "",
            title ?? ""
        ].joined(separator: "\u{1f}")
    }

    private func payloadArtworkData(_ payload: [String: Any]) -> Data? {
        if let artworkData = dataValue(payload["artworkData"]) {
            return artworkData
        }
        guard let signature = payloadSignature(payload) else { return nil }
        return artworkCache[signature]
    }

    private func sanitizedTrackTransitionPayload(
        _ payload: [String: Any],
        previousPayloads: [[String: Any]]
    ) -> [String: Any] {
        var sanitized = payload

        let candidateArtist = stringValue(payload["artist"])?.adapterTrimmedNonEmpty
        if candidateArtist != nil,
           previousPayloads.contains(where: {
               stringValue($0["artist"])?.adapterTrimmedNonEmpty == candidateArtist
           }) {
            sanitized.removeValue(forKey: "artist")
        }

        let candidateAlbum = stringValue(payload["album"])?.adapterTrimmedNonEmpty
        if candidateAlbum != nil,
           previousPayloads.contains(where: {
               stringValue($0["album"])?.adapterTrimmedNonEmpty == candidateAlbum
           }) {
            sanitized.removeValue(forKey: "album")
        }

        if let candidateDuration = doubleValue(payload["duration"]),
           previousPayloads.contains(where: {
               doubleValue($0["duration"]).map {
                   abs($0 - candidateDuration) < 0.01
               } ?? false
           }) {
            sanitized.removeValue(forKey: "duration")
        }

        let candidateArtwork = dataValue(payload["artworkData"])
        if candidateArtwork == nil || previousPayloads.contains(where: {
            dataValue($0["artworkData"]) == candidateArtwork
        }) {
            sanitized.removeValue(forKey: "artworkData")
            sanitized.removeValue(forKey: "artworkMimeType")
        }
        return sanitized
    }

    private func metadataResponse(
        _ response: MediaRemoteNowPlayingTrack,
        matches current: MediaRemoteNowPlayingTrack
    ) -> Bool {
        guard (response.sourceBundleIdentifier ?? "") == (current.sourceBundleIdentifier ?? ""),
              response.title == current.title else {
            return false
        }
        if let responseProcessIdentifier = response.sourceProcessIdentifier,
           let currentProcessIdentifier = current.sourceProcessIdentifier,
           responseProcessIdentifier != currentProcessIdentifier {
            return false
        }

        let currentArtist = current.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let responseArtist = response.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentArtist != "汽水音乐",
           responseArtist != "汽水音乐",
           currentArtist != responseArtist {
            return false
        }

        if let currentAlbum = current.album?.trimmingCharacters(in: .whitespacesAndNewlines),
           let responseAlbum = response.album?.trimmingCharacters(in: .whitespacesAndNewlines),
           !currentAlbum.isEmpty,
           !responseAlbum.isEmpty,
           currentAlbum != responseAlbum {
            return false
        }

        return true
    }

    private func reusableArtwork(for payload: [String: Any]) -> Data? {
        guard let latestTrack = latestSnapshot?.currentTrack,
              payloadSignature(payload) == trackSignature(latestTrack) else {
            guard let signature = payloadSignature(payload) else { return nil }
            return artworkCache[signature]
        }
        return latestTrack.artworkData ?? artworkCache[trackSignature(latestTrack)]
    }

    private func payloadSignature(_ payload: [String: Any]) -> String? {
        guard let title = stringValue(payload["title"])?.adapterTrimmedNonEmpty else { return nil }
        return [
            stringValue(payload["bundleIdentifier"]) ?? "",
            title,
            stringValue(payload["artist"])?.adapterTrimmedNonEmpty ?? "汽水音乐",
            stringValue(payload["album"])?.adapterTrimmedNonEmpty ?? ""
        ].joined(separator: "\u{1f}")
    }

    private func rememberArtwork(_ data: Data, for signature: String) {
        artworkCache[signature] = data
        artworkCacheOrder.removeAll { $0 == signature }
        artworkCacheOrder.append(signature)
        while artworkCacheOrder.count > 24 {
            let removed = artworkCacheOrder.removeFirst()
            artworkCache.removeValue(forKey: removed)
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            if value == "true" || value == "1" { return true }
            if value == "false" || value == "0" { return false }
        }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Float { return Double(value) }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func pidValue(_ value: Any?) -> pid_t? {
        guard let intValue = doubleValue(value).map(Int32.init), intValue > 0 else { return nil }
        return pid_t(intValue)
    }

    private func dataValue(_ value: Any?) -> Data? {
        if let value = value as? Data { return value }
        guard let string = value as? String else { return nil }
        return Data(base64Encoded: string)
    }
}

private extension String {
    var adapterTrimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
