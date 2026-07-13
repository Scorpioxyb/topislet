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

    static func decode(fields: [String]) -> AppleMusicObservation? {
        guard fields.count == 7 else { return nil }
        let state = playbackState(from: fields[6])
        let title = fields[1].nilIfEmpty
        return AppleMusicObservation(
            persistentIdentifier: fields[0].nilIfEmpty,
            title: title,
            artist: fields[2].nilIfEmpty,
            album: fields[3].nilIfEmpty,
            duration: positiveFiniteDouble(fields[4]),
            elapsedTime: nonnegativeFiniteDouble(fields[5]),
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

private enum AppleMusicBridgeRunner {
    static func readObservation(
        processIdentifier: pid_t
    ) -> Result<AppleMusicObservation, AppleMusicBridgeFailure> {
        var bridgeError: NSError?
        guard let snapshot = TopIsletAppleMusicCopySnapshot(
            processIdentifier,
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
        guard let observation = AppleMusicObservation.decode(fields: fields) else {
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
    private var revision: UInt64 = 0

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

    func snapshot(refresh _: MusicSnapshotRefresh) async -> MusicAppSnapshot {
        let checkedAt = Date()
        guard let app = runningApplication() else {
            lastObservation = nil
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
                processIdentifier: processIdentifier
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
            guard runningApplication()?.processIdentifier == processIdentifier else {
                return unavailableSnapshot(
                    availability: .notRunning,
                    checkedAt: checkedAt,
                    diagnostic: "Apple Music 应用实例在读取过程中发生变化。"
                )
            }
            if observation != lastObservation {
                revision &+= 1
                lastObservation = observation
            }
            return readySnapshot(
                observation: observation,
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
                artworkData: nil,
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
            diagnostic: "已通过定向 Apple Event 读取 Apple Music。"
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
