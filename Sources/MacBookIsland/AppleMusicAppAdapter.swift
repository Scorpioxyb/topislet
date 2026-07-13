import AppKit
import AppleMusicBridge
import ApplicationServices
import Foundation

enum AppleMusicAutomationAccess: Equatable, Sendable {
    case allowed
    case targetNotRunning
    case consentRequired
    case denied
    case unavailable(status: OSStatus)

    var displayName: String {
        switch self {
        case .allowed:
            return "已授权"
        case .targetNotRunning:
            return "等待 Apple Music 运行"
        case .consentRequired:
            return "需要授权"
        case .denied:
            return "已拒绝"
        case let .unavailable(status):
            return "不可用（\(status)）"
        }
    }

    var diagnosticCode: String {
        switch self {
        case .allowed:
            return "allowed"
        case .targetNotRunning:
            return "targetNotRunning"
        case .consentRequired:
            return "consentRequired"
        case .denied:
            return "denied"
        case let .unavailable(status):
            return "unavailable:\(status)"
        }
    }
}

struct AppleMusicObservation: Equatable, Sendable {
    let persistentIdentifier: String?
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
    let duration: TimeInterval?
    let elapsedTime: TimeInterval?
    let state: MusicPlaybackState

    var trackIdentity: MusicTrackIdentity? {
        guard let title, !title.isEmpty else { return nil }
        return MusicTrackIdentity(
            providerIdentifier: persistentIdentifier,
            fallbackSignature: [title, artist ?? "", album ?? ""]
                .joined(separator: "\u{1f}")
        )
    }

    static func decode(
        fields: [String],
        artworkData: Data? = nil
    ) -> AppleMusicObservation? {
        guard fields.count == 7 else { return nil }
        let state = playbackState(from: fields[6])
        let title = fields[1].nilIfEmpty
        return AppleMusicObservation(
            persistentIdentifier: fields[0].nilIfEmpty,
            title: title,
            artist: fields[2].nilIfEmpty,
            album: fields[3].nilIfEmpty,
            artworkData: artworkData,
            duration: positiveFiniteDouble(fields[4]),
            elapsedTime: nonnegativeFiniteDouble(fields[5]),
            state: state
        )
    }

    func withArtworkData(_ artworkData: Data?) -> AppleMusicObservation {
        AppleMusicObservation(
            persistentIdentifier: persistentIdentifier,
            title: title,
            artist: artist,
            album: album,
            artworkData: artworkData,
            duration: duration,
            elapsedTime: elapsedTime,
            state: state
        )
    }

    static func playbackState(from rawValue: String) -> MusicPlaybackState {
        switch rawValue.lowercased() {
        case "playing", "fast forwarding", "rewinding":
            return .playing
        case "paused":
            return .paused
        case "stopped":
            return .stopped
        default:
            return .unknown
        }
    }

    private static func positiveFiniteDouble(_ rawValue: String) -> Double? {
        guard let value = Double(rawValue), value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func nonnegativeFiniteDouble(_ rawValue: String) -> Double? {
        guard let value = Double(rawValue), value.isFinite, value >= 0 else { return nil }
        return value
    }
}

func appleMusicSnapshotByReplacingArtworkData(
    _ snapshot: MusicAppSnapshot,
    artworkData: Data,
    identity: MusicTrackIdentity,
    revision: UInt64
) -> MusicAppSnapshot? {
    guard let track = snapshot.track,
          track.identity == identity else { return nil }
    let updatedTrack = MusicTrackSnapshot(
        identity: track.identity,
        title: track.title,
        artist: track.artist,
        album: track.album,
        artworkData: artworkData,
        lyrics: track.lyrics
    )
    return MusicAppSnapshot(
        descriptor: snapshot.descriptor,
        instance: snapshot.instance,
        availability: snapshot.availability,
        track: updatedTrack,
        playbackState: snapshot.playbackState,
        timeline: snapshot.timeline,
        controls: snapshot.controls,
        revision: revision,
        provenance: snapshot.provenance,
        checkedAt: snapshot.checkedAt,
        diagnostic: "Apple Music 播放状态保持原快照；封面 \(artworkData.count) bytes 已异步补齐。"
    )
}

private struct AppleMusicBridgeFailure: Error, Sendable {
    let diagnostic: String
}

struct AppleMusicArtworkCache: Sendable {
    enum FailureKind: Sendable {
        case notFound
        case transient
    }

    private struct Entry: Sendable {
        var data: Data?
        var attemptedAt: Date
        var retryAfter: Date
        var transientFailureCount: Int
    }

    private var entries: [MusicTrackIdentity: Entry] = [:]
    private var order: [MusicTrackIdentity] = []
    private(set) var totalBytes = 0
    let retryInterval: TimeInterval
    let maximumEntryCount: Int
    let maximumArtworkBytes: Int
    let maximumTotalBytes: Int

    init(
        retryInterval: TimeInterval = 30,
        maximumEntryCount: Int = 16,
        maximumArtworkBytes: Int = 8 * 1024 * 1024,
        maximumTotalBytes: Int = 24 * 1024 * 1024
    ) {
        self.retryInterval = retryInterval
        self.maximumEntryCount = maximumEntryCount
        self.maximumArtworkBytes = maximumArtworkBytes
        self.maximumTotalBytes = maximumTotalBytes
    }

    func data(for identity: MusicTrackIdentity) -> Data? {
        entries[identity]?.data
    }

    func shouldFetch(
        for identity: MusicTrackIdentity,
        at now: Date
    ) -> Bool {
        guard let entry = entries[identity] else { return true }
        guard entry.data == nil else { return false }
        return now >= entry.retryAfter
    }

    mutating func recordAttempt(
        for identity: MusicTrackIdentity,
        at now: Date
    ) {
        let existingData = entries[identity]?.data
        entries[identity] = Entry(
            data: existingData,
            attemptedAt: now,
            retryAfter: now.addingTimeInterval(retryInterval),
            transientFailureCount: entries[identity]?.transientFailureCount ?? 0
        )
        touch(identity)
        trimIfNeeded()
    }

    mutating func recordFailure(
        _ failure: FailureKind,
        for identity: MusicTrackIdentity,
        at now: Date
    ) {
        if let existingData = entries[identity]?.data {
            totalBytes -= existingData.count
        }
        let previousFailureCount = entries[identity]?.transientFailureCount ?? 0
        let transientFailureCount: Int
        let retryDelay: TimeInterval
        switch failure {
        case .notFound:
            transientFailureCount = 0
            retryDelay = max(retryInterval, 5 * 60)
        case .transient:
            transientFailureCount = min(previousFailureCount + 1, 5)
            retryDelay = min(
                retryInterval * pow(2, Double(transientFailureCount - 1)),
                5 * 60
            )
        }
        entries[identity] = Entry(
            data: nil,
            attemptedAt: now,
            retryAfter: now.addingTimeInterval(retryDelay),
            transientFailureCount: transientFailureCount
        )
        touch(identity)
        trimIfNeeded()
    }

    @discardableResult
    mutating func store(
        _ data: Data,
        for identity: MusicTrackIdentity,
        at now: Date
    ) -> Bool {
        guard !data.isEmpty,
              data.count <= maximumArtworkBytes else { return false }
        if let existingData = entries[identity]?.data {
            totalBytes -= existingData.count
        }
        entries[identity] = Entry(
            data: data,
            attemptedAt: now,
            retryAfter: .distantFuture,
            transientFailureCount: 0
        )
        totalBytes += data.count
        touch(identity)
        trimIfNeeded()
        return entries[identity]?.data != nil
    }

    private mutating func touch(_ identity: MusicTrackIdentity) {
        order.removeAll { $0 == identity }
        order.append(identity)
    }

    private mutating func trimIfNeeded() {
        while order.count > maximumEntryCount
            || totalBytes > maximumTotalBytes {
            guard let removedIdentity = order.first else { break }
            order.removeFirst()
            if let removedData = entries.removeValue(
                forKey: removedIdentity
            )?.data {
                totalBytes -= removedData.count
            }
        }
    }
}

private enum AppleMusicBridgeRunner {
    static func readObservation(
        processIdentifier: pid_t,
        includeArtwork: Bool
    ) -> Result<AppleMusicObservation, AppleMusicBridgeFailure> {
        var bridgeError: NSError?
        guard let snapshot = TopIsletAppleMusicCopySnapshot(
            processIdentifier,
            includeArtwork,
            &bridgeError
        ) else {
            return .failure(failure(bridgeError))
        }
        let fields = [
            snapshot["persistentIdentifier"] as? String ?? "",
            snapshot["title"] as? String ?? "",
            snapshot["artist"] as? String ?? "",
            snapshot["album"] as? String ?? "",
            numberText(snapshot["duration"]),
            numberText(snapshot["elapsedTime"]),
            snapshot["state"] as? String ?? "unknown"
        ]
        guard let observation = AppleMusicObservation.decode(
            fields: fields,
            artworkData: snapshot["artworkData"] as? Data
        ) else {
            return .failure(AppleMusicBridgeFailure(
                diagnostic: "Apple Music 返回了无法解析的播放快照。"
            ))
        }
        return .success(observation)
    }

    static func perform(
        processIdentifier: pid_t,
        action: MusicControlAction,
        expectedTrack: MusicTrackIdentity?
    ) -> Result<Void, AppleMusicBridgeFailure> {
        let actionName: String
        let normalizedProgress: Double
        switch action {
        case .playPause:
            actionName = "playPause"
            normalizedProgress = 0
        case .previousTrack:
            actionName = "previousTrack"
            normalizedProgress = 0
        case .nextTrack:
            actionName = "nextTrack"
            normalizedProgress = 0
        case let .seekNormalized(progress):
            guard progress.isFinite, (0...1).contains(progress) else {
                return .failure(AppleMusicBridgeFailure(
                    diagnostic: "Apple Music 进度目标必须位于 0 到 1。"
                ))
            }
            actionName = "seekNormalized"
            normalizedProgress = progress
        }

        var bridgeError: NSError?
        let succeeded = TopIsletAppleMusicPerformAction(
            processIdentifier,
            actionName,
            expectedTrack?.providerIdentifier,
            expectedTrack?.fallbackSignature,
            normalizedProgress,
            &bridgeError
        )
        return succeeded ? .success(()) : .failure(failure(bridgeError))
    }

    private static func numberText(_ value: Any?) -> String {
        guard let number = value as? NSNumber else { return "" }
        return String(
            format: "%.9f",
            locale: Locale(identifier: "en_US_POSIX"),
            number.doubleValue
        )
    }

    private static func failure(_ error: NSError?) -> AppleMusicBridgeFailure {
        let message = error?.localizedDescription
            ?? "Apple Music 定向通信失败。"
        return AppleMusicBridgeFailure(
            diagnostic: error.map { "\(message)（\($0.code)）" } ?? message
        )
    }
}

enum AppleMusicArtworkLoadResult: Sendable {
    case success(Data)
    case notFound
    case transientFailure
}

typealias AppleMusicArtworkLoading = @Sendable (
    pid_t,
    AppleMusicObservation
) async -> AppleMusicArtworkLoadResult

private final class AppleMusicArtworkBridgeRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

private final class AppleMusicArtworkBridgeExecutor: @unchecked Sendable {
    static let shared = AppleMusicArtworkBridgeExecutor()

    private let queue = DispatchQueue(
        label: "TopIslet.AppleMusicArtworkBridge"
    )

    func readObservation(
        processIdentifier: pid_t,
        request: AppleMusicArtworkBridgeRequest
    ) async -> Result<AppleMusicObservation, AppleMusicBridgeFailure>? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard !request.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                let result = AppleMusicBridgeRunner.readObservation(
                    processIdentifier: processIdentifier,
                    includeArtwork: true
                )
                continuation.resume(
                    returning: request.isCancelled ? nil : result
                )
            }
        }
    }
}

private enum AppleMusicArtworkLoader {
    static func load(
        processIdentifier: pid_t,
        observation: AppleMusicObservation
    ) async -> AppleMusicArtworkLoadResult {
        let request = AppleMusicArtworkBridgeRequest()
        let directResult = await withTaskCancellationHandler {
            await AppleMusicArtworkBridgeExecutor.shared.readObservation(
                processIdentifier: processIdentifier,
                request: request
            )
        } onCancel: {
            request.cancel()
        }
        guard !Task.isCancelled,
              let directResult,
              case let .success(directObservation) = directResult,
              directObservation.trackIdentity == observation.trackIdentity else {
            return .transientFailure
        }
        if let artworkData = directObservation.artworkData {
            return .success(artworkData)
        }
        switch await AppleMusicCatalogArtworkResolver().artworkData(for: observation) {
        case let .success(data):
            return .success(data)
        case .notFound:
            return .notFound
        case .transientFailure:
            return .transientFailure
        }
    }
}

@MainActor
final class AppleMusicAppAdapter: MusicAppAdapter {
    let descriptor = MusicAdapterRegistry.appleMusic.descriptor

    private var notificationToken: NSObjectProtocol?
    private var playerInfoDebounceTask: Task<Void, Never>?
    private var invalidationHandler: (@MainActor @Sendable (
        MusicAdapterInvalidation
    ) -> Void)?
    private var lastObservation: AppleMusicObservation?
    private var lastInstance: MusicAppInstance?
    private var lastSnapshot: MusicAppSnapshot?
    private var revision: UInt64 = 0
    private var artworkCache = AppleMusicArtworkCache()
    private let artworkLoader: AppleMusicArtworkLoading
    private let controlQueue = DispatchQueue(
        label: "TopIslet.AppleMusicControl"
    )
    private var artworkFetchTask: Task<Void, Never>?
    private var artworkFetchIdentity: MusicTrackIdentity?
    private var artworkFetchGeneration: UInt64 = 0

    init(
        artworkLoader: AppleMusicArtworkLoading? = nil
    ) {
        self.artworkLoader = artworkLoader ?? { processIdentifier, observation in
            await AppleMusicArtworkLoader.load(
                processIdentifier: processIdentifier,
                observation: observation
            )
        }
    }

    func start(
        onInvalidation: @escaping @MainActor @Sendable (
            MusicAdapterInvalidation
        ) -> Void
    ) {
        stop()
        invalidationHandler = onInvalidation
        notificationToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.playerInfoDebounceTask?.cancel()
                self.playerInfoDebounceTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    guard !Task.isCancelled else { return }
                    self?.invalidationHandler?(.sourceChanged)
                }
            }
        }
    }

    func stop() {
        if let notificationToken {
            DistributedNotificationCenter.default().removeObserver(notificationToken)
        }
        notificationToken = nil
        playerInfoDebounceTask?.cancel()
        playerInfoDebounceTask = nil
        cancelArtworkFetch()
        invalidationHandler = nil
    }

    func snapshot(refresh: MusicSnapshotRefresh) async -> MusicAppSnapshot {
        let checkedAt = Date()
        guard let app = runningApplication() else {
            cancelArtworkFetch()
            lastObservation = nil
            lastInstance = nil
            lastSnapshot = nil
            return unavailableSnapshot(
                availability: .notRunning,
                checkedAt: checkedAt,
                diagnostic: "Apple Music 未运行；顶屿不会自动启动它。"
            )
        }

        let instance = MusicAppInstance(
            app: descriptor,
            processIdentifier: app.processIdentifier,
            launchedAt: app.launchDate
        )
        if case .cached = refresh {
            guard lastInstance == instance,
                  let lastSnapshot else {
                return unavailableSnapshot(
                    instance: instance,
                    availability: .degraded(reason: "Apple Music 尚无缓存快照。"),
                    checkedAt: checkedAt,
                    diagnostic: "Apple Music 尚无缓存快照；本次未发送 Apple Event。"
                )
            }
            return lastSnapshot
        }
        let access = Self.automationAccess(
            prompt: false,
            processIdentifier: app.processIdentifier
        )
        guard access == .allowed else {
            return unavailableSnapshot(
                instance: instance,
                availability: .permissionRequired(permission: "自动化 - Apple Music"),
                checkedAt: checkedAt,
                diagnostic: "Apple Music 自动化状态：\(access.displayName)。"
            )
        }

        let processIdentifier = app.processIdentifier
        let result = await Task.detached(priority: .userInitiated) {
            AppleMusicBridgeRunner.readObservation(
                processIdentifier: processIdentifier,
                includeArtwork: false
            )
        }.value
        switch result {
        case let .failure(error):
            return unavailableSnapshot(
                instance: instance,
                availability: .degraded(reason: error.diagnostic),
                checkedAt: checkedAt,
                diagnostic: error.diagnostic
            )
        case let .success(observation):
            var resolvedObservation = observation
            if let identity = observation.trackIdentity {
                if let artworkData = artworkCache.data(for: identity) {
                    resolvedObservation = observation.withArtworkData(artworkData)
                }
            }
            guard runningApplication()?.processIdentifier == processIdentifier else {
                return unavailableSnapshot(
                    availability: .notRunning,
                    checkedAt: checkedAt,
                    diagnostic: "Apple Music 应用实例在读取过程中发生变化。"
                )
            }
            if resolvedObservation != lastObservation {
                revision &+= 1
                lastObservation = resolvedObservation
            }
            lastInstance = instance
            if case .metadata = refresh {
                scheduleArtworkFetch(
                    for: observation,
                    instance: instance,
                    processIdentifier: processIdentifier,
                    at: checkedAt
                )
            }
            let snapshot = readySnapshot(
                observation: resolvedObservation,
                instance: instance,
                checkedAt: checkedAt
            )
            lastSnapshot = snapshot
            return snapshot
        }
    }

    func perform(_ request: MusicControlRequest) async -> MusicControlResult {
        guard request.target.app.bundleIdentifier == descriptor.bundleIdentifier,
              let app = runningApplication(),
              app.processIdentifier == request.target.processIdentifier else {
            return MusicControlResult(
                requestID: request.id,
                disposition: .rejected,
                diagnostic: "Apple Music 应用实例已变化，未发送控制。"
            )
        }
        let processIdentifier = request.target.processIdentifier
        guard Self.automationAccess(
            prompt: false,
            processIdentifier: processIdentifier
        ) == .allowed else {
            return MusicControlResult(
                requestID: request.id,
                disposition: .rejected,
                diagnostic: "Apple Music 自动化权限不可用，未发送控制。"
            )
        }

        let action = request.action
        let expectedTrack = request.expectedTrack
        let controlQueue = controlQueue
        let result = await withCheckedContinuation { continuation in
            controlQueue.async {
                continuation.resume(returning: AppleMusicBridgeRunner.perform(
                    processIdentifier: processIdentifier,
                    action: action,
                    expectedTrack: expectedTrack
                ))
            }
        }
        switch result {
        case let .failure(error):
            return MusicControlResult(
                requestID: request.id,
                disposition: .failed,
                diagnostic: error.diagnostic
            )
        case .success:
            return MusicControlResult(
                requestID: request.id,
                disposition: .accepted,
                diagnostic: "Apple Music 已接受定向控制，等待新快照确认。"
            )
        }
    }

    static func automationAccess(prompt: Bool) -> AppleMusicAutomationAccess {
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicAdapterRegistry.appleMusic.descriptor.bundleIdentifier
        ).first else {
            return .targetNotRunning
        }
        return automationAccess(
            prompt: prompt,
            processIdentifier: app.processIdentifier
        )
    }

    private static func automationAccess(
        prompt: Bool,
        processIdentifier: pid_t
    ) -> AppleMusicAutomationAccess {
        var target = AEAddressDesc()
        var targetProcessIdentifier = processIdentifier
        let createStatus = withUnsafeBytes(of: &targetProcessIdentifier) { bytes in
            AECreateDesc(
                DescType(typeKernelProcessID),
                bytes.baseAddress,
                bytes.count,
                &target
            )
        }
        guard createStatus == noErr else {
            return .unavailable(status: OSStatus(createStatus))
        }
        defer { AEDisposeDesc(&target) }

        let status = AEDeterminePermissionToAutomateTarget(
            &target,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            prompt
        )
        return automationAccess(for: status)
    }

    nonisolated static func automationAccess(for status: OSStatus) -> AppleMusicAutomationAccess {
        switch status {
        case noErr:
            return .allowed
        case -600:
            return .targetNotRunning
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .consentRequired
        case OSStatus(errAEEventNotPermitted):
            return .denied
        default:
            return .unavailable(status: status)
        }
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicAdapterRegistry.appleMusic.descriptor.bundleIdentifier
        ).isEmpty
    }

    private func runningApplication() -> NSRunningApplication? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: descriptor.bundleIdentifier)
            .first
    }

    private func scheduleArtworkFetch(
        for observation: AppleMusicObservation,
        instance: MusicAppInstance,
        processIdentifier: pid_t,
        at now: Date
    ) {
        guard let identity = observation.trackIdentity,
              artworkCache.data(for: identity) == nil,
              artworkCache.shouldFetch(for: identity, at: now) else {
            return
        }
        if artworkFetchIdentity == identity,
           artworkFetchTask != nil {
            return
        }

        cancelArtworkFetch()
        artworkCache.recordAttempt(for: identity, at: now)
        artworkFetchGeneration &+= 1
        let generation = artworkFetchGeneration
        artworkFetchIdentity = identity
        let artworkLoader = artworkLoader
        artworkFetchTask = Task(priority: .utility) { [weak self] in
            let result = await artworkLoader(processIdentifier, observation)
            guard !Task.isCancelled,
                  let self,
                  generation == self.artworkFetchGeneration else {
                return
            }
            self.finishArtworkFetch(
                result,
                identity: identity,
                instance: instance,
                generation: generation
            )
        }
    }

    private func finishArtworkFetch(
        _ result: AppleMusicArtworkLoadResult,
        identity: MusicTrackIdentity,
        instance: MusicAppInstance,
        generation: UInt64
    ) {
        guard generation == artworkFetchGeneration else { return }
        artworkFetchTask = nil
        artworkFetchIdentity = nil
        guard lastInstance == instance,
              runningApplication()?.processIdentifier == instance.processIdentifier,
              lastObservation?.trackIdentity == identity else {
            return
        }
        let completedAt = Date()
        switch result {
        case .notFound:
            artworkCache.recordFailure(
                .notFound,
                for: identity,
                at: completedAt
            )
            return
        case .transientFailure:
            artworkCache.recordFailure(
                .transient,
                for: identity,
                at: completedAt
            )
            return
        case let .success(data):
            guard artworkCache.store(data, for: identity, at: completedAt) else {
                artworkCache.recordFailure(
                    .transient,
                    for: identity,
                    at: completedAt
                )
                return
            }
        }
        guard let artworkData = artworkCache.data(for: identity),
              let lastObservation,
              lastObservation.artworkData != artworkData,
              let lastSnapshot,
              let updatedSnapshot = appleMusicSnapshotByReplacingArtworkData(
                lastSnapshot,
                artworkData: artworkData,
                identity: identity,
                revision: revision &+ 1
              ) else {
            return
        }
        self.lastObservation = lastObservation.withArtworkData(artworkData)
        revision &+= 1
        self.lastSnapshot = updatedSnapshot
        invalidationHandler?(.cachedDataChanged)
    }

    private func cancelArtworkFetch() {
        artworkFetchGeneration &+= 1
        artworkFetchTask?.cancel()
        artworkFetchTask = nil
        artworkFetchIdentity = nil
    }

    private func readySnapshot(
        observation: AppleMusicObservation,
        instance: MusicAppInstance,
        checkedAt: Date
    ) -> MusicAppSnapshot {
        let track = observation.trackIdentity.map { identity in
            MusicTrackSnapshot(
                identity: identity,
                title: observation.title ?? "Apple Music",
                artist: observation.artist,
                album: observation.album,
                artworkData: observation.artworkData,
                lyrics: []
            )
        }
        let timeline: MusicTimelineSnapshot?
        if let elapsedTime = observation.elapsedTime,
           let duration = observation.duration {
            timeline = MusicTimelineSnapshot(
                elapsedTime: min(max(elapsedTime, 0), duration),
                duration: duration,
                playbackRate: observation.state == .playing ? 1 : 0,
                observedAt: checkedAt
            )
        } else {
            timeline = nil
        }
        let verifiedAt = checkedAt
        let readyControl = MusicControlCapability.ready(
            target: instance,
            mechanism: .appleEvent,
            verifiedAt: verifiedAt
        )
        var controlValues: [MusicControlKind: MusicControlCapability] = [
            .playPause: readyControl
        ]
        if track != nil {
            controlValues[.previousTrack] = readyControl
            controlValues[.nextTrack] = readyControl
        }
        if observation.persistentIdentifier != nil,
           timeline != nil {
            controlValues[.absoluteSeek] = readyControl
        }
        let controls = MusicControlCapabilities(values: controlValues)
        return MusicAppSnapshot(
            descriptor: descriptor,
            instance: instance,
            availability: .ready,
            track: track,
            playbackState: observation.state,
            timeline: timeline,
            controls: controls,
            revision: revision,
            provenance: MusicSnapshotProvenance(
                bundleIdentifier: descriptor.bundleIdentifier,
                mechanisms: [.appleEvent]
            ),
            checkedAt: checkedAt,
            diagnostic: "已通过定向 Apple Event 读取 Apple Music；封面 \(track?.artworkData.map { "\($0.count) bytes" } ?? "暂未提供")。"
        )
    }

    private func unavailableSnapshot(
        instance: MusicAppInstance? = nil,
        availability: MusicAppAvailability,
        checkedAt: Date,
        diagnostic: String
    ) -> MusicAppSnapshot {
        MusicAppSnapshot(
            descriptor: descriptor,
            instance: instance,
            availability: availability,
            track: nil,
            playbackState: .unknown,
            timeline: nil,
            controls: .none,
            revision: revision,
            provenance: MusicSnapshotProvenance(
                bundleIdentifier: descriptor.bundleIdentifier,
                mechanisms: [.appleEvent]
            ),
            checkedAt: checkedAt,
            diagnostic: diagnostic
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
