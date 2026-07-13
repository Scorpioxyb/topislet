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

private struct AppleMusicBridgeFailure: Error, Sendable {
    let diagnostic: String
}

struct AppleMusicArtworkCache: Sendable {
    private struct Entry: Sendable {
        var data: Data?
        var attemptedAt: Date
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
        return now.timeIntervalSince(entry.attemptedAt) >= retryInterval
    }

    mutating func recordAttempt(
        for identity: MusicTrackIdentity,
        at now: Date
    ) {
        let existingData = entries[identity]?.data
        entries[identity] = Entry(data: existingData, attemptedAt: now)
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
        entries[identity] = Entry(data: data, attemptedAt: now)
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

@MainActor
final class AppleMusicAppAdapter: MusicAppAdapter {
    let descriptor = MusicAdapterRegistry.appleMusic.descriptor

    private var notificationToken: NSObjectProtocol?
    private var invalidationHandler: (@MainActor @Sendable () -> Void)?
    private var lastObservation: AppleMusicObservation?
    private var lastInstance: MusicAppInstance?
    private var revision: UInt64 = 0
    private var artworkCache = AppleMusicArtworkCache()

    func start(
        onInvalidation: @escaping @MainActor @Sendable () -> Void
    ) {
        stop()
        invalidationHandler = onInvalidation
        notificationToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.invalidationHandler?()
            }
        }
    }

    func stop() {
        if let notificationToken {
            DistributedNotificationCenter.default().removeObserver(notificationToken)
        }
        notificationToken = nil
        invalidationHandler = nil
    }

    func snapshot(refresh: MusicSnapshotRefresh) async -> MusicAppSnapshot {
        let checkedAt = Date()
        guard let app = runningApplication() else {
            lastObservation = nil
            lastInstance = nil
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
                  let lastObservation else {
                return unavailableSnapshot(
                    instance: instance,
                    availability: .degraded(reason: "Apple Music 尚无缓存快照。"),
                    checkedAt: checkedAt,
                    diagnostic: "Apple Music 尚无缓存快照；本次未发送 Apple Event。"
                )
            }
            let cachedObservation: AppleMusicObservation
            if let identity = lastObservation.trackIdentity,
               let artworkData = artworkCache.data(for: identity) {
                cachedObservation = lastObservation.withArtworkData(artworkData)
            } else {
                cachedObservation = lastObservation
            }
            return readySnapshot(
                observation: cachedObservation,
                instance: instance,
                checkedAt: checkedAt
            )
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
                } else if case .metadata = refresh,
                          artworkCache.shouldFetch(for: identity, at: checkedAt) {
                    artworkCache.recordAttempt(for: identity, at: checkedAt)
                    let artworkResult = await Task.detached(priority: .utility) {
                        AppleMusicBridgeRunner.readObservation(
                            processIdentifier: processIdentifier,
                            includeArtwork: true
                        )
                    }.value
                    if case let .success(artworkObservation) = artworkResult,
                       artworkObservation.trackIdentity == identity {
                        if let artworkData = artworkObservation.artworkData {
                            _ = artworkCache.store(
                                artworkData,
                                for: identity,
                                at: checkedAt
                            )
                            resolvedObservation = observation.withArtworkData(
                                artworkCache.data(for: identity)
                            )
                        }
                    }
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
            return readySnapshot(
                observation: resolvedObservation,
                instance: instance,
                checkedAt: checkedAt
            )
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
        let result = await Task.detached(priority: .userInitiated) {
            AppleMusicBridgeRunner.perform(
                processIdentifier: processIdentifier,
                action: action,
                expectedTrack: expectedTrack
            )
        }.value
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
