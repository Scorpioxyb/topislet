import AppKit
import ApplicationServices
import Foundation
import MusicUsageDiagnostics
import OSLog
import SwiftUI

enum QishuiDirectSnapshotFreshnessPolicy {
    // A direct AX read is deliberately short-lived. It is used to reject a
    // stale MediaRemote identity, not as a long-term cache of the player.
    static let maximumAge: TimeInterval = 2.0

    static func accepts(checkedAt: Date, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(checkedAt)
        return age >= 0 && age <= maximumAge
    }
}

enum QishuiMediaRemoteAdmissionPolicy {
    // The source may hold an incomplete candidate for 2.4s, then perform one
    // duration repair with a 0.9s transport deadline. Keep PID state evidence
    // through that bounded window instead of falling back to unknown AX.
    static let maximumPlaybackEvidenceAge: TimeInterval = 2.4 + 0.9
    static func accepts(
        mediaTitle: String,
        mediaArtist: String,
        directTitle: String?,
        directArtist: String?,
        directCheckedAt: Date?,
        mediaIdentityObservedAt: Date? = nil,
        mediaHasCompleteMetadata: Bool = false,
        directHasPlaybackEvidence: Bool = true,
        mediaHasFreshProcessPlaybackEvidence: Bool = false,
        now: Date = Date()
    ) -> Bool {
        guard let directTitle, let directArtist, let directCheckedAt,
              QishuiDirectSnapshotFreshnessPolicy.accepts(
                  checkedAt: directCheckedAt,
                  now: now
              ) else {
            return true
        }
        // An AX label without state or progress is not contrary playback
        // evidence. Keep the fresh, PID-scoped source state while its bounded
        // metadata repair runs; never manufacture paused from an unknown AX.
        if !directHasPlaybackEvidence, mediaHasFreshProcessPlaybackEvidence {
            return true
        }
        if mediaHasCompleteMetadata, let mediaIdentityObservedAt,
           mediaIdentityObservedAt > directCheckedAt,
           QishuiDirectSnapshotFreshnessPolicy.accepts(checkedAt: mediaIdentityObservedAt, now: now) {
            return true
        }
        return QishuiTrackCoherencePolicy.matches(
            mediaTitle: mediaTitle,
            mediaArtist: mediaArtist,
            directTitle: directTitle,
            directArtist: directArtist
        )
    }
}

enum MusicSourceAvailability: String, Equatable {
    case preview
    case qishuiNotRunning
    case qishuiMediaRemoteSynced
    case qishuiMediaRemoteCached
    case qishuiDetectedAXLimited
    case systemNowPlayingRecognized
    case systemNowPlayingUnavailable
    case qishuiControlSent
    case neteaseMusicSynced
    case neteaseMusicControlSent
    case appleMusicSynced
    case appleMusicControlSent
    case appleMusicPermissionRequired
    case accessibilityRequired
}

enum MusicControlCommand: Sendable, Equatable {
    case playPause
    case nextTrack
    case previousTrack

    var label: String {
        switch self {
        case .playPause:
            return "播放/暂停"
        case .nextTrack:
            return "下一首"
        case .previousTrack:
            return "上一首"
        }
    }

}

enum MusicSeekInteraction {
    case click
    case drag

    var coalescingDelayNanoseconds: UInt64 {
        switch self {
        case .click:
            return 20_000_000
        case .drag:
            return 90_000_000
        }
    }
}

enum MusicSeekCancellationReason: String {
    case superseded
    case trackChanged = "track_changed"
    case sourceChanged = "source_changed"
    case sourceExited = "source_exited"
    case stateReset = "state_reset"
}

enum QishuiSeekPlaybackPolicy {
    static func shouldStartPlayback(
        observedIsPlaying: Bool?,
        sameTrack: Bool,
        operationIsCurrent: Bool
    ) -> Bool {
        observedIsPlaying == false && sameTrack && operationIsCurrent
    }
}

enum QishuiSeekSafety {
    // The adapter's seek command still follows the system media focus. It is
    // therefore only admitted after a fresh, PID-matched Qishui focus check.
    static let supportsTargetedSeek = false
    static let supportsGuardedMediaFocusSeek = true

    static func allowsGuardedSeek(
        hasVerifiedQishuiSource: Bool,
        hasCurrentTrack: Bool,
        hasDuration: Bool,
        isCached: Bool,
        hasCompetingPlayback: Bool
    ) -> Bool {
        supportsGuardedMediaFocusSeek
            && hasVerifiedQishuiSource
            && hasCurrentTrack
            && hasDuration
            && !isCached
            && !hasCompetingPlayback
    }
}

enum NeteaseMusicVerificationPolicy {
    static let discoveryInterval: TimeInterval = 0.5
    static let steadyInterval: TimeInterval = 1.0

    // MediaRemote's per-client stream can remain alive without delivering
    // later playback changes. A PID-targeted read is the correctness backstop.
    static func interval(
        isRunning: Bool,
        isSelected: Bool,
        playback: MusicSourcePlaybackLevel
    ) -> TimeInterval? {
        guard isRunning else { return nil }
        if !isSelected, playback != .playing {
            return discoveryInterval
        }
        return steadyInterval
    }
}

struct MusicSourceStatus: Equatable {
    let sourceName: String
    let availability: MusicSourceAvailability
    let headline: String
    let detail: String
    let checkedAt: Date

    var compactLabel: String {
        switch availability {
        case .preview:
            return "预览模式"
        case .qishuiNotRunning:
            return "汽水未运行"
        case .qishuiMediaRemoteSynced:
            return "实时同步"
        case .qishuiMediaRemoteCached:
            return "状态保持"
        case .qishuiDetectedAXLimited:
            return "直接适配中"
        case .systemNowPlayingRecognized:
            return "手动诊断"
        case .systemNowPlayingUnavailable:
            return "播放中不可读"
        case .qishuiControlSent:
            return "已发送控制"
        case .neteaseMusicSynced:
            return "网易云音乐"
        case .neteaseMusicControlSent:
            return "网易云音乐控制"
        case .appleMusicSynced:
            return "Apple Music"
        case .appleMusicControlSent:
            return "Apple Music 控制"
        case .appleMusicPermissionRequired:
            return "需要自动化权限"
        case .accessibilityRequired:
            return "需要辅助功能权限"
        }
    }

    var tint: Color {
        switch availability {
        case .preview:
            return .white.opacity(0.52)
        case .qishuiNotRunning:
            return .white.opacity(0.42)
        case .qishuiMediaRemoteSynced:
            return .green.opacity(0.95)
        case .qishuiMediaRemoteCached:
            return .orange.opacity(0.9)
        case .qishuiDetectedAXLimited:
            return .green.opacity(0.9)
        case .systemNowPlayingRecognized:
            return .cyan.opacity(0.95)
        case .systemNowPlayingUnavailable:
            return .orange.opacity(0.9)
        case .qishuiControlSent:
            return .cyan.opacity(0.9)
        case .neteaseMusicSynced:
            return .red.opacity(0.92)
        case .neteaseMusicControlSent:
            return .red.opacity(0.92)
        case .appleMusicSynced:
            return .pink.opacity(0.95)
        case .appleMusicControlSent:
            return .pink.opacity(0.95)
        case .appleMusicPermissionRequired:
            return .yellow.opacity(0.95)
        case .accessibilityRequired:
            return .yellow.opacity(0.95)
        }
    }
}

struct MusicControlOutcome: Equatable {
    let status: MusicSourceStatus
    let didSendCommand: Bool

    var shouldAdvancePreview: Bool {
        false
    }
}

enum AppleMusicRefreshPolicy {
    static func interval(
        isSelected: Bool,
        isPlaying: Bool,
        recentlyControlled: Bool,
        consecutiveFailures: Int
    ) -> TimeInterval {
        let baseInterval: TimeInterval
        if isSelected, isPlaying || recentlyControlled {
            baseInterval = 5
        } else if isSelected {
            baseInterval = 10
        } else {
            baseInterval = 15
        }
        let backoffMultiplier = min(
            pow(2, Double(max(consecutiveFailures, 0))),
            4
        )
        return baseInterval * backoffMultiplier
    }
}

enum AppleMusicSnapshotAdmissionDecision: Equatable {
    case accept
    case rejectOlder
    case retry(after: TimeInterval)
}

enum AppleMusicSnapshotAdmissionPolicy {
    static let retryDelays: [TimeInterval] = [0.25, 0.6, 1.2, 2.4]

    static func isIncompleteTransitionSnapshot(
        _ snapshot: MusicAppSnapshot
    ) -> Bool {
        guard case .ready = snapshot.availability,
              snapshot.instance != nil,
              let track = snapshot.track,
              !track.title.isEmpty else {
            return false
        }
        let artistIsMissing = track.artist?.isEmpty != false
        let albumIsMissing = track.album?.isEmpty != false
        return artistIsMissing && albumIsMissing
    }

    static func decision(
        current: MusicAppSnapshot?,
        candidate: MusicAppSnapshot,
        attempt: Int
    ) -> AppleMusicSnapshotAdmissionDecision {
        if let current, current.checkedAt > candidate.checkedAt {
            return .rejectOlder
        }
        guard retryDelays.indices.contains(attempt) else {
            return .accept
        }
        if isIncompleteTransitionSnapshot(candidate),
           current == nil || current?.instance == candidate.instance {
            return .retry(after: retryDelays[attempt])
        }
        guard let current,
              case .ready = current.availability,
              current.instance == candidate.instance,
              case .degraded = candidate.availability else {
            return .accept
        }
        return .retry(after: retryDelays[attempt])
    }
}

enum AppleMusicSourceAvailabilityPolicy {
    static func snapshotMatchesRunningInstance(
        runningProcessIdentifier: pid_t?,
        snapshotProcessIdentifier: pid_t?
    ) -> Bool {
        guard let runningProcessIdentifier else { return false }
        return snapshotProcessIdentifier == runningProcessIdentifier
    }

    static func isAvailable(
        isEnabled: Bool,
        runningProcessIdentifier: pid_t?,
        snapshotProcessIdentifier: pid_t?,
        snapshotIsReady: Bool,
        isForeground: Bool
    ) -> Bool {
        guard isEnabled, let runningProcessIdentifier else { return false }
        if isForeground {
            return true
        }
        return snapshotIsReady && snapshotMatchesRunningInstance(
            runningProcessIdentifier: runningProcessIdentifier,
            snapshotProcessIdentifier: snapshotProcessIdentifier
        )
    }
}

enum AppleMusicPlaybackSnapshotResolution: Equatable {
    case reject
    case acceptAndClear
}

struct AppleMusicPlaybackControlExpectation: Equatable {
    static let staleSnapshotGraceInterval: TimeInterval = 1.2

    let instance: MusicAppInstance
    let trackIdentity: MusicTrackIdentity
    let targetState: MusicPlaybackState
    let issuedAt: Date

    static func action(for targetState: MusicPlaybackState) -> MusicControlAction? {
        switch targetState {
        case .playing:
            return .play
        case .paused:
            return .pause
        case .stopped, .unknown:
            return nil
        }
    }

    func resolution(
        for snapshot: MusicAppSnapshot,
        at now: Date
    ) -> AppleMusicPlaybackSnapshotResolution {
        guard case .ready = snapshot.availability else {
            return .acceptAndClear
        }
        guard snapshot.instance == instance,
              snapshot.track?.identity == trackIdentity else {
            return .acceptAndClear
        }
        guard snapshot.playbackState != targetState else {
            return .acceptAndClear
        }
        if now.timeIntervalSince(issuedAt) < Self.staleSnapshotGraceInterval {
            return .reject
        }
        return .acceptAndClear
    }
}

enum MusicUsageHeartbeatPolicy {
    static let interval: TimeInterval = 15 * 60

    static func shouldRecord(lastRecordedAt: Date?, now: Date) -> Bool {
        now.timeIntervalSince(lastRecordedAt ?? .distantPast) >= interval
    }
}

@MainActor
final class MusicAdapterCoordinator {
    private let neteaseMusicAdapter = NeteaseMusicAppAdapter()
    private let musicSourceSelector = MusicSourceSelector()
    /// Apple Music state and orchestration (coordinator split step 4b).
    private let appleMusic = AppleMusicDriver()
    /// Qishui-only state and collaborators (coordinator split step 4.3).
    private let qishui = QishuiMusicAdapter()
    private lazy var qishuiLyrics = QishuiLyricPipeline(
        debugEnabled: ProcessInfo.processInfo.environment["TOPISLET_QISHUI_LYRIC_DEBUG"] == "1",
        host: QishuiLyricPipeline.Host(
            isObserving: { [weak self] in self?.isRealtimeObservationRunning ?? false },
            currentIdentity: { [weak self] in self?.qishuiLyricIdentity() },
            mediaTrack: { [weak self] in self?.qishui.latestMediaRemoteSnapshot?.currentTrack },
            directSnapshot: { [weak self] in self?.qishui.latestQishuiSnapshot },
            recordEvent: { [weak self] name, fields in self?.recordUsage(name, fields: fields) },
            publish: { [weak self] in self?.publishCurrentState() },
            debugSourceDescription: { [weak self] in String(describing: self?.selectedMusicSource()) }
        )
    )
    private let seeks = SeekCoordinator()

    init() {
        qishui.host = self
        appleMusic.host = self
    }

    func setQishuiTimedLyricsEnabled(_ enabled: Bool) {
        qishuiLyrics.setTimedLyricsEnabled(enabled)
    }

    private let logger = Logger(
        subsystem: "io.github.scorpioxyb.topislet",
        category: "MusicAdapter"
    )
    private let usage = MusicUsageEmitter()
    var qishuiControlAvailability: QishuiControlAvailability {
        qishui.latestQishuiControlAvailability
    }

    func resetQishuiControlVerificationForRecovery() {
        qishui.resetQishuiControlVerificationForRecovery()
    }

    func verifyQishuiControlsAfterRecovery() async {
        await qishui.verifyQishuiControlsAfterRecovery()
    }
    private var realtimeRefreshInFlight = false
    private var realtimeRefreshQueued = false
    private var realtimeUpdateHandler: ((MusicState, MusicSourceStatus) -> Void)?
    private var foregroundMusicSource: MusicSourceID?
    private var latestNeteaseMusicSnapshot: MusicAppSnapshot?
    private var neteaseMusicRefreshTask: Task<Void, Never>?
    private var neteaseMusicRefreshGeneration: UInt64 = 0
    private var lastNeteaseMusicRefreshStartedAt: Date?
    private var neteaseMusicControlRequestID: UInt64 = 0
    private var isRealtimeObservationRunning = false

    var initialState: MusicState {
        MusicState(
            track: qishui.placeholderTrack(statusLine: "正在等待汽水直接适配源"),
            isPlaying: false,
            progress: 0,
            lyricIndex: 0,
            canPlayPause: false,
            canPreviousTrack: false,
            canNextTrack: false,
            controlUnavailableReason: "正在等待汽水音乐。",
            hasCurrentTrack: false
        )
    }

    func startRealtimeObservation(onUpdate: @escaping (MusicState, MusicSourceStatus) -> Void) {
        usage.observationStarted(at: Date())
        isRealtimeObservationRunning = true
        realtimeUpdateHandler = onUpdate
        startQishuiLifecycleObservation()
        startNeteaseMusicObservation()
        if appleMusic.appleMusicEnabled {
            appleMusic.startAppleMusicObservation()
        }
        qishui.mediaRemoteAdapterStreamSource.setTrackTransitionStageHandler { [weak self] event in
            self?.usage.recordQishuiTransitionStage(event)
        }
        qishui.mediaRemoteAdapterStreamSource.setIdentityObservationHandler { [weak self] event in
            self?.recordUsage(event.name, fields: event.fields)
        }
        qishui.mediaRemoteAdapterStreamSource.start { [weak self] in
            guard let self else { return }
            self.refreshFromRealtimeSignal(onUpdate: onUpdate)
        }
        qishui.qishuiAXChangeMonitor.start { [weak self] notification in
            guard let self else { return }
            if QishuiAXNotificationBatch.structuralNotifications.contains(notification) {
                self.qishui.scheduleQishuiControlAvailabilityRefresh()
                self.qishui.scheduleQishuiLifecycleMetadataRefresh()
            }
            self.refreshFromRealtimeSignal(onUpdate: onUpdate)
        }
        qishui.scheduleQishuiControlAvailabilityRefresh()
        reconcileForegroundMusicSource()
        qishui.schedulePlaybackPositionRefresh()
        qishui.scheduleQishuiLifecycleMetadataRefresh()
    }

    func stopRealtimeObservation() {
        usage.observationStopped(at: Date())
        isRealtimeObservationRunning = false
        qishui.mediaRemoteAdapterStreamSource.setIdentityObservationHandler(nil)
        seeks.cancelResume()
        qishui.qishuiIdentityRefreshGeneration &+= 1
        qishui.qishuiIdentityRefreshInFlight = false
        qishui.lastQishuiIdentityRefreshAt = .distantPast
        qishuiLyrics.invalidate()
        qishui.qishuiLifecycleMetadataTask?.cancel()
        qishui.qishuiLifecycleMetadataTask = nil
        realtimeUpdateHandler = nil
        stopQishuiLifecycleObservation()
        stopNeteaseMusicObservation()
        appleMusic.stopAppleMusicObservation()
        foregroundMusicSource = nil
        usage.clearQishuiTransition()
        qishui.mediaRemoteAdapterStreamSource.setTrackTransitionStageHandler(nil)
        qishui.mediaRemoteAdapterStreamSource.stop()
        qishui.qishuiAXChangeMonitor.stop()
        qishui.cancelQishuiControlAvailabilityScheduling()
        qishui.playback.reset(clearTimelineFloor: true)
    }

    func setAppleMusicEnabled(_ enabled: Bool) {
        guard appleMusic.appleMusicEnabled != enabled else { return }
        appleMusic.appleMusicEnabled = enabled
        if enabled {
            if isRealtimeObservationRunning {
                appleMusic.startAppleMusicObservation()
            }
        } else {
            if foregroundMusicSource == .appleMusic {
                foregroundMusicSource = nil
            }
            appleMusic.stopAppleMusicObservation()
        }
        reconcileForegroundMusicSource()
        publishCurrentState()
    }

    func appleMusicSnapshotForSettings() async -> MusicAppSnapshot? {
        guard appleMusic.appleMusicEnabled else { return nil }
        if appleMusic.appleMusicRefreshTask == nil {
            appleMusic.scheduleAppleMusicRefresh(force: true)
        }
        let deadline = Date().addingTimeInterval(2)
        while appleMusic.appleMusicRefreshTask != nil,
              appleMusic.appleMusicEnabled,
              !Task.isCancelled,
              Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        guard appleMusic.appleMusicEnabled,
              !Task.isCancelled,
              appleMusic.appleMusicRefreshTask == nil else { return nil }
        return appleMusic.latestAppleMusicSnapshot
    }

    func neteaseMusicSnapshotForSettings() async -> MusicAppSnapshot? {
        let snapshot = await neteaseMusicAdapter.snapshot(refresh: .metadata)
        if case .notRunning = snapshot.availability {
            latestNeteaseMusicSnapshot = nil
            return nil
        }
        latestNeteaseMusicSnapshot = snapshot
        publishCurrentState()
        return snapshot
    }

    func invalidateAppleMusicAccess() {
        guard appleMusic.appleMusicEnabled else { return }
        appleMusic.stopAppleMusicObservation()
        if isRealtimeObservationRunning {
            appleMusic.startAppleMusicObservation()
        }
        publishCurrentState()
    }

    func playPause(_ state: MusicState) -> MusicState {
        state
    }

    func nextTrack() -> MusicState {
        MusicState(
            track: qishui.placeholderTrack(statusLine: "已发送切歌控制，等待汽水直接状态回读"),
            isPlaying: false,
            progress: 0,
            lyricIndex: 0,
            canPlayPause: false,
            canPreviousTrack: false,
            canNextTrack: false,
            hasCurrentTrack: false
        )
    }

    func previousTrack() -> MusicState {
        MusicState(
            track: qishui.placeholderTrack(statusLine: "已发送切歌控制，等待汽水直接状态回读"),
            isPlaying: false,
            progress: 0,
            lyricIndex: 0,
            canPlayPause: false,
            canPreviousTrack: false,
            canNextTrack: false,
            hasCurrentTrack: false
        )
    }

    func performControl(
        _ command: MusicControlCommand,
        displayedSourceBundleIdentifier: String?
    ) async -> MusicControlOutcome {
        let requestID = usage.nextRequestID()
        let source = MusicUsageEmitter.sourceLabel(MusicSourceID(
            bundleIdentifier: displayedSourceBundleIdentifier
        ))
        let commandLabel = Self.commandLabel(command)
        let startedAt = Date()
        let baselineState = selectedMusicState()
        let baselineTrackFingerprint = baselineState.hasCurrentTrack
            ? MusicUsageTrackFingerprint.make(
                source: source,
                title: baselineState.track.title,
                artist: baselineState.track.artist
            )
            : nil
        let targetPlayback: String?
        if command == .playPause {
            targetPlayback = baselineState.isPlaying ? "paused" : "playing"
        } else {
            targetPlayback = nil
        }
        var issuedFields = [
            "command": commandLabel,
            "request": String(requestID),
            "source": source
        ]
        if let targetPlayback {
            issuedFields["target_playback"] = targetPlayback
        }
        recordUsage("control_issued", fields: issuedFields)
        let outcome = await performControlImplementation(
            command,
            displayedSourceBundleIdentifier: displayedSourceBundleIdentifier
        )
        let completedAt = Date()
        let isAcceptedQishuiTrackTransition = outcome.didSendCommand
            && source == "qishui"
            && (command == .nextTrack || command == .previousTrack)
        let transitionID = isAcceptedQishuiTrackTransition
            ? "q\(requestID)"
            : nil
        var resultFields = [
            "command": commandLabel,
            "latency_ms": String(max(Int(completedAt.timeIntervalSince(startedAt) * 1_000), 0)),
            "outcome": outcome.didSendCommand ? "accepted" : "rejected",
            "request": String(requestID),
            "status": outcome.status.availability.rawValue,
            "source": source
        ]
        if let targetPlayback {
            resultFields["target_playback"] = targetPlayback
        }
        if let transitionID {
            resultFields["transition"] = transitionID
        }
        recordUsage("control_result", fields: resultFields)
        if let transitionID {
            usage.beginQishuiTransition(
                transitionID: transitionID,
                startedAt: completedAt,
                baselineTrackFingerprint: baselineTrackFingerprint
            )
            qishui.mediaRemoteAdapterStreamSource.beginTrackTransitionObservation(
                transitionID: transitionID,
                startedAt: completedAt
            )
            usage.recordQishuiTransitionStage(
                transitionID: transitionID,
                stage: "control_result",
                latencyMilliseconds: 0,
                hasArtist: !baselineState.track.artist.isEmpty,
                hasArtwork: baselineState.track.hasArtwork
                    || baselineState.track.artworkData != nil
                    || baselineState.track.artworkURL != nil,
                hasAlbum: !(qishui.latestMediaRemoteSnapshot?.currentTrack?.album ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                hasDuration: baselineState.duration != nil,
                wasDeferred: false
            )
        }
        return outcome
    }

    private func performControlImplementation(
        _ command: MusicControlCommand,
        displayedSourceBundleIdentifier: String?
    ) async -> MusicControlOutcome {
        guard let binding = DisplayedMusicControlBinding(
            displayedSourceBundleIdentifier: displayedSourceBundleIdentifier
        ) else {
            return MusicControlOutcome(
                status: invalidDisplayedSourceStatus(command: command),
                didSendCommand: false
            )
        }
        let selection = selectedMusicSelection()
        guard let authorization = MusicControlAuthorization(
            binding: binding,
            selection: selection
        ) else {
            return staleDisplayedSourceOutcome(
                command: command,
                binding: binding,
                selectedSource: selection.source
            )
        }
        if binding.source == .appleMusic {
            guard appleMusic.appleMusicEnabled else {
                return MusicControlOutcome(
                    status: MusicSourceStatus(
                        sourceName: "Apple Music",
                        availability: .systemNowPlayingUnavailable,
                        headline: "Apple Music 适配已关闭",
                        detail: "可在设置的音乐页重新启用。",
                        checkedAt: Date()
                    ),
                    didSendCommand: false
                )
            }
            return await performAppleMusicControl(command)
        }
        if binding.source == .neteaseMusic {
            return await performNeteaseMusicControl(command)
        }
        return await qishui.performQishuiControl(
            command,
            binding: binding,
            authorization: authorization
        )
    }

    private func performAppleMusicControl(
        _ command: MusicControlCommand
    ) async -> MusicControlOutcome {
        guard let snapshot = appleMusic.latestAppleMusicSnapshot,
              let instance = snapshot.instance,
              let track = snapshot.track else {
            return MusicControlOutcome(
                status: appleMusic.appleMusicControlStatus(
                    command: command,
                    succeeded: false,
                    diagnostic: "Apple Music 当前控制目标不可用。"
                ),
                didSendCommand: false
            )
        }
        let controlKind: MusicControlKind
        let defaultAction: MusicControlAction
        switch command {
        case .playPause:
            controlKind = .playPause
            defaultAction = .playPause
        case .previousTrack:
            controlKind = .previousTrack
            defaultAction = .previousTrack
        case .nextTrack:
            controlKind = .nextTrack
            defaultAction = .nextTrack
        }
        guard case let .ready(target, mechanism, _) = snapshot.controls.values[controlKind],
              target == instance,
              mechanism == .appleEvent else {
            return MusicControlOutcome(
                status: appleMusic.appleMusicControlStatus(
                    command: command,
                    succeeded: false,
                    diagnostic: "Apple Music 未提供匹配当前进程的控制能力。"
                ),
                didSendCommand: false
            )
        }

        appleMusic.appleMusicControlGeneration &+= 1
        let controlGeneration = appleMusic.appleMusicControlGeneration
        let controlIssuedAt = Date()
        appleMusic.lastAppleMusicControlAt = controlIssuedAt
        appleMusic.appleMusicTransitionTimeline.beginControl(
            command: command.label,
            baseline: "\(track.title) - \(track.artist ?? "")"
        )
        appleMusic.clearAppleMusicPlaybackControlExpectation()
        let resolvedAction: MusicControlAction
        if controlKind == .playPause,
           let optimisticSnapshot = appleMusic.appleMusicSnapshot(
            togglingPlaybackIn: snapshot,
            at: controlIssuedAt
           ),
           let targetedAction = AppleMusicPlaybackControlExpectation.action(
            for: optimisticSnapshot.playbackState
           ) {
            resolvedAction = targetedAction
            let expectation = AppleMusicPlaybackControlExpectation(
                instance: instance,
                trackIdentity: track.identity,
                targetState: optimisticSnapshot.playbackState,
                issuedAt: controlIssuedAt
            )
            appleMusic.beginAppleMusicPlaybackControlExpectation(
                expectation,
                generation: controlGeneration
            )
            appleMusic.latestAppleMusicSnapshot = optimisticSnapshot
            publishCurrentState()
        } else {
            resolvedAction = defaultAction
        }
        appleMusic.appleMusicControlRequestID &+= 1
        let request = MusicControlRequest(
            id: appleMusic.appleMusicControlRequestID,
            target: instance,
            expectedTrack: track.identity,
            action: resolvedAction
        )
        let result = await appleMusic.appleMusicAdapter.perform(request)
        let dispositionLabel: String
        switch result.disposition {
        case .accepted:
            dispositionLabel = "accepted"
        case .rejected:
            dispositionLabel = "rejected"
        case .failed:
            dispositionLabel = "failed"
        }
        appleMusic.appleMusicTransitionTimeline.record(
            .controlCompleted,
            detail: "command=\(command.label) disposition=\(dispositionLabel)"
        )
        let succeeded = result.disposition == .accepted
        guard controlGeneration == appleMusic.appleMusicControlGeneration else {
            return MusicControlOutcome(
                status: appleMusic.appleMusicControlStatus(
                    command: command,
                    succeeded: succeeded,
                    diagnostic: result.diagnostic
                ),
                didSendCommand: succeeded
            )
        }
        if succeeded {
            if controlKind != .previousTrack && controlKind != .nextTrack {
                appleMusic.scheduleAppleMusicRefresh(force: true)
            }
        } else if controlKind == .playPause {
            appleMusic.clearAppleMusicPlaybackControlExpectation()
            appleMusic.scheduleAppleMusicRefresh(force: true)
        }
        return MusicControlOutcome(
            status: appleMusic.appleMusicControlStatus(
                command: command,
                succeeded: succeeded,
                diagnostic: result.diagnostic
            ),
            didSendCommand: succeeded
        )
    }

    private func performNeteaseMusicControl(
        _ command: MusicControlCommand
    ) async -> MusicControlOutcome {
        guard let snapshot = neteaseMusicSnapshotForRunningInstance(),
              let instance = snapshot.instance,
              let track = snapshot.track else {
            return MusicControlOutcome(
                status: neteaseMusicControlStatus(
                    command: command,
                    succeeded: false,
                    diagnostic: "网易云音乐当前控制目标不可用。"
                ),
                didSendCommand: false
            )
        }
        let controlKind: MusicControlKind
        let action: MusicControlAction
        switch command {
        case .playPause:
            controlKind = .playPause
            action = .playPause
        case .previousTrack:
            controlKind = .previousTrack
            action = .previousTrack
        case .nextTrack:
            controlKind = .nextTrack
            action = .nextTrack
        }
        guard case let .ready(target, mechanism, _) = snapshot.controls.values[controlKind],
              target == instance,
              mechanism == .semanticAccessibility else {
            return MusicControlOutcome(
                status: neteaseMusicControlStatus(
                    command: command,
                    succeeded: false,
                    diagnostic: "网易云音乐未提供匹配当前进程的语义控制能力。"
                ),
                didSendCommand: false
            )
        }

        neteaseMusicControlRequestID &+= 1
        let result = await neteaseMusicAdapter.perform(MusicControlRequest(
            id: neteaseMusicControlRequestID,
            target: instance,
            expectedTrack: track.identity,
            action: action
        ))
        let succeeded = result.disposition == .accepted
        if succeeded {
            latestNeteaseMusicSnapshot = await neteaseMusicAdapter.snapshot(refresh: .cached)
            publishCurrentState()
        }
        return MusicControlOutcome(
            status: neteaseMusicControlStatus(
                command: command,
                succeeded: succeeded,
                diagnostic: result.diagnostic
            ),
            didSendCommand: succeeded
        )
    }

    private func invalidDisplayedSourceStatus(
        command: MusicControlCommand
    ) -> MusicSourceStatus {
        MusicSourceStatus(
            sourceName: "顶屿",
            availability: .systemNowPlayingUnavailable,
            headline: "未执行\(command.label)",
            detail: "岛当前显示的音乐来源不可识别；为避免控制其他应用，本次操作已取消。",
            checkedAt: Date()
        )
    }

    private func staleDisplayedSourceOutcome(
        command: MusicControlCommand,
        binding: DisplayedMusicControlBinding,
        selectedSource: MusicSourceID?
    ) -> MusicControlOutcome {
        MusicControlOutcome(
            status: MusicSourceStatus(
                sourceName: "顶屿",
                availability: .systemNowPlayingUnavailable,
                headline: "未执行\(command.label)",
                detail: "音乐来源已从 \(Self.sourceDisplayName(binding.source)) 切换为 \(Self.sourceDisplayName(selectedSource))；旧控制请求已取消。",
                checkedAt: Date()
            ),
            didSendCommand: false
        )
    }

    private func neteaseMusicControlStatus(
        command: MusicControlCommand,
        succeeded: Bool,
        diagnostic: String
    ) -> MusicSourceStatus {
        MusicSourceStatus(
            sourceName: "网易云音乐",
            availability: succeeded ? .neteaseMusicControlSent : .neteaseMusicSynced,
            headline: succeeded ? "已执行\(command.label)" : "未执行\(command.label)",
            detail: diagnostic,
            checkedAt: Date()
        )
    }

    func tick(_ state: MusicState) -> (music: MusicState, sourceStatus: MusicSourceStatus?) {
        qishui.scheduleQishuiIdentityRefresh()
        qishuiLyrics.scheduleRefresh()
        reconcileForegroundMusicSource()
        qishui.scheduleControlHealthCheckIfNeeded()
        appleMusic.scheduleAppleMusicRefresh(force: false)
        if qishui.playback.hasPendingOperation
            || qishui.shouldRefreshCachedPlaybackState()
            || qishui.shouldRefreshPlaybackPosition(state) {
            qishui.schedulePlaybackPositionRefresh()
        }
        _ = qishui.refreshSourceStatusIfNeeded()
        let selectedSource = selectedMusicSource()
        let neteaseMusicCandidate = neteaseMusicSourceCandidate()
        if let verificationInterval = NeteaseMusicVerificationPolicy.interval(
            isRunning: neteaseMusicCandidate.isAvailable,
            isSelected: selectedSource == .neteaseMusic,
            playback: neteaseMusicCandidate.playback
        ) {
            scheduleNeteaseMusicVerificationIfNeeded(
                minimumInterval: verificationInterval
            )
        }
        let update = selectedMusicUpdate(for: selectedSource)
        recordUsageHeartbeatIfNeeded(update.music)
        return update
    }

    func currentState() -> MusicState {
        selectedMusicUpdate().music
    }

    func appleMusicTransitionReport() -> String {
        appleMusic.appleMusicTransitionTimeline.report()
    }

    func latestAppleMusicTransitionReport() -> String {
        appleMusic.appleMusicTransitionTimeline.latestReport()
    }

    func noteMusicUIPublished(_ state: MusicState) {
        let completedTransitionID = usage.recordUIPublished(
            state,
            lyricAgeMilliseconds: { self.qishuiLyrics.publishedLyricAgeMilliseconds(for: state) }
        )
        if let completedTransitionID {
            qishui.mediaRemoteAdapterStreamSource.endTrackTransitionObservation(
                transitionID: completedTransitionID
            )
        }
        appleMusic.noteAppleMusicUIPublished(state)
    }

    func noteSeekConfirmed(
        sourceBundleIdentifier: String?,
        requestedAt: Date,
        targetProgress: Double,
        observedProgress: Double
    ) {
        recordUsage("seek_confirmed", fields: SeekCoordinator.UsageFields.confirmed(
            sourceBundleIdentifier: sourceBundleIdentifier,
            requestedAt: requestedAt,
            targetProgress: targetProgress,
            observedProgress: observedProgress
        ))
    }

    func noteSeekConfirmationTimeout(
        sourceBundleIdentifier: String?,
        requestedAt: Date,
        targetProgress: Double
    ) {
        recordUsage("seek_confirmation_timeout", fields: SeekCoordinator.UsageFields.confirmationTimeout(
            sourceBundleIdentifier: sourceBundleIdentifier,
            requestedAt: requestedAt,
            targetProgress: targetProgress
        ))
    }

    func noteSeekCancelled(
        sourceBundleIdentifier: String?,
        requestedAt: Date,
        targetProgress: Double,
        reason: MusicSeekCancellationReason
    ) {
        recordUsage("seek_cancelled", fields: SeekCoordinator.UsageFields.cancelled(
            sourceBundleIdentifier: sourceBundleIdentifier,
            requestedAt: requestedAt,
            targetProgress: targetProgress,
            reason: reason
        ))
    }

    func refreshPlaybackPositionNow() -> (music: MusicState, status: MusicSourceStatus) {
        let source = selectedMusicSource()
        if source == .appleMusic {
            appleMusic.scheduleAppleMusicRefresh(force: true)
            return (selectedMusicState(), selectedMusicStatus())
        }
        if source == .neteaseMusic {
            scheduleNeteaseMusicRefresh(refresh: .timeline)
            return (selectedMusicState(), selectedMusicStatus())
        }
        let status = qishui.refreshPlaybackPositionStatus()
        return (selectedMusicState(), status)
    }

    func refreshNowPlaying(promptForPermission: Bool = false) -> (music: MusicState, status: MusicSourceStatus) {
        let status = refreshSourceStatus(promptForPermission: promptForPermission, allowSynchronousRefresh: true)
        guard status.availability != .qishuiNotRunning,
              status.availability != .accessibilityRequired else {
            return (qishui.currentQishuiMusicState(), status)
        }

        let snapshot = qishui.nowPlayingBridge.capture(promptForPermission: promptForPermission)
        qishui.applyNowPlayingSnapshot(snapshot)
        return (qishui.currentQishuiMusicState(), qishui.cachedStatus)
    }

    func forceRefreshNowPlaying() -> (music: MusicState, status: MusicSourceStatus) {
        refreshNowPlaying(promptForPermission: true)
    }

    func seek(
        to progress: Double,
        interaction: MusicSeekInteraction,
        displayedSourceBundleIdentifier: String?
    ) async -> (music: MusicState, status: MusicSourceStatus) {
        let requestID = usage.nextRequestID()
        let source = MusicUsageEmitter.sourceLabel(MusicSourceID(
            bundleIdentifier: displayedSourceBundleIdentifier
        ))
        let startedAt = Date()
        recordUsage("seek_issued", fields: SeekCoordinator.UsageFields.issued(
            interaction: interaction, requestID: requestID, source: source, progress: progress
        ))
        let result = await performSeek(
            to: progress,
            interaction: interaction,
            displayedSourceBundleIdentifier: displayedSourceBundleIdentifier
        )
        recordUsage("seek_result", fields: SeekCoordinator.UsageFields.result(
            interaction: interaction, requestID: requestID, source: source,
            startedAt: startedAt, availability: result.status.availability
        ))
        return result
    }

    private func performSeek(
        to progress: Double,
        interaction: MusicSeekInteraction,
        displayedSourceBundleIdentifier: String?
    ) async -> (music: MusicState, status: MusicSourceStatus) {
        let seekGeneration = seeks.begin()
        guard let binding = DisplayedMusicControlBinding(
            displayedSourceBundleIdentifier: displayedSourceBundleIdentifier
        ) else {
            return (selectedMusicState(), SeekCoordinator.Status.unrecognizedSource())
        }
        guard let authorization = MusicControlAuthorization(
            binding: binding,
            selection: selectedMusicSelection()
        ) else {
            return (selectedMusicState(), SeekCoordinator.Status.sourceSwitched())
        }
        if binding.source == .appleMusic {
            return await seekAppleMusic(
                to: progress,
                interaction: interaction,
                authorization: authorization
            )
        }
        if binding.source == .neteaseMusic {
            return (neteaseMusicState(), SeekCoordinator.Status.neteaseUnsupported())
        }

        return await qishui.performQishuiSeek(
            to: progress,
            interaction: interaction,
            authorization: authorization,
            seekGeneration: seekGeneration
        )
    }

    private func seekAppleMusic(
        to progress: Double,
        interaction: MusicSeekInteraction,
        authorization: MusicControlAuthorization
    ) async -> (music: MusicState, status: MusicSourceStatus) {
        guard appleMusic.appleMusicEnabled,
              progress.isFinite,
              (0...1).contains(progress),
              let snapshot = appleMusic.latestAppleMusicSnapshot,
              let instance = snapshot.instance,
              let track = snapshot.track,
              track.identity.providerIdentifier != nil,
              let timeline = snapshot.timeline,
              timeline.duration > 0,
              case let .ready(target, mechanism, _) = snapshot.controls.values[.absoluteSeek],
              target == instance,
              mechanism == .appleEvent else {
            let status = MusicSourceStatus(
                sourceName: "Apple Music",
                availability: .appleMusicSynced,
                headline: "当前不能拖动进度",
                detail: "Apple Music 当前曲目缺少稳定 ID、时长或定向进度能力。",
                checkedAt: Date()
            )
            return (selectedMusicState(), status)
        }

        try? await Task.sleep(nanoseconds: interaction.coalescingDelayNanoseconds)
        guard appleMusic.appleMusicEnabled,
              AppleMusicAppAdapter.isRunning,
              appleMusic.latestAppleMusicSnapshot?.instance == instance,
              appleMusic.latestAppleMusicSnapshot?.track?.identity == track.identity,
              authorization.isValid(for: selectedMusicSelection()) else {
            let status = MusicSourceStatus(
                sourceName: "Apple Music",
                availability: .appleMusicSynced,
                headline: "已取消进度跳转",
                detail: "拖动期间 Apple Music 控制目标已变化，未发送控制。",
                checkedAt: Date()
            )
            return (selectedMusicState(), status)
        }

        appleMusic.appleMusicControlRequestID &+= 1
        appleMusic.appleMusicControlGeneration &+= 1
        let controlGeneration = appleMusic.appleMusicControlGeneration
        let result = await appleMusic.appleMusicAdapter.perform(MusicControlRequest(
            id: appleMusic.appleMusicControlRequestID,
            target: instance,
            expectedTrack: track.identity,
            action: .seekNormalized(progress)
        ))
        let succeeded = result.disposition == .accepted
        guard appleMusic.appleMusicEnabled,
              controlGeneration == appleMusic.appleMusicControlGeneration else {
            let status = MusicSourceStatus(
                sourceName: "Apple Music",
                availability: .appleMusicSynced,
                headline: "已取消进度跳转",
                detail: "操作期间 Apple Music 适配已关闭或目标已失效。",
                checkedAt: Date()
            )
            return (selectedMusicState(), status)
        }
        let status = MusicSourceStatus(
            sourceName: "Apple Music",
            availability: succeeded ? .appleMusicControlSent : .appleMusicSynced,
            headline: succeeded ? "已跳转播放进度" : "未跳转播放进度",
            detail: result.diagnostic,
            checkedAt: Date()
        )
        guard succeeded,
              AppleMusicAppAdapter.isRunning else {
            return (selectedMusicState(), status)
        }

        appleMusic.scheduleAppleMusicRefresh(force: true)
        var optimisticState = appleMusic.appleMusicState()
        optimisticState.progress = progress
        optimisticState.elapsedTime = timeline.duration * progress
        return (optimisticState, status)
    }

    func refreshControlFollowUp(
        forcePositionRefresh: Bool = false
    ) async -> (music: MusicState, status: MusicSourceStatus) {
        let selectedSource = selectedMusicSource()
        if selectedSource == .appleMusic {
            let route = musicSourceSelector.selection
            if let inFlightRefresh = appleMusic.appleMusicRefreshTask {
                await inFlightRefresh.value
                guard musicSourceSelector.selection == route else {
                    return (selectedMusicState(), selectedMusicStatus())
                }
                return (selectedMusicState(), selectedMusicStatus())
            }
            let snapshot = await appleMusic.appleMusicAdapter.snapshot(refresh: .timeline)
            guard musicSourceSelector.selection == route else {
                return (selectedMusicState(), selectedMusicStatus())
            }
            _ = appleMusic.admitAppleMusicSnapshot(snapshot)
            return (selectedMusicState(), selectedMusicStatus())
        }
        if selectedSource == .neteaseMusic {
            let snapshot = await neteaseMusicAdapter.snapshot(refresh: .timeline)
            if snapshot.instance != nil {
                latestNeteaseMusicSnapshot = snapshot
            }
            return (selectedMusicState(), selectedMusicStatus())
        }
        await qishui.refreshQishuiControlFollowUp(forcePositionRefresh: forcePositionRefresh)
        return (selectedMusicState(), selectedMusicStatus())
    }

    func invalidateQishuiCache() {
        let source = selectedMusicSource()
        if source == .appleMusic {
            appleMusic.scheduleAppleMusicRefresh(force: true)
            return
        }
        if source == .neteaseMusic {
            scheduleNeteaseMusicRefresh(refresh: .metadata)
            return
        }
        qishui.qishuiAdapter.invalidateAXCache()
        qishui.qishuiSemanticAXController.invalidateCache()
    }

    private func refreshFromRealtimeSignal(onUpdate: @escaping (MusicState, MusicSourceStatus) -> Void) {
        guard !realtimeRefreshInFlight else {
            realtimeRefreshQueued = true
            return
        }

        realtimeRefreshInFlight = true
        _ = refreshSourceStatus()
        qishuiLyrics.scheduleRefresh()
        if qishui.latestMediaRemoteSnapshot?.isVerifiedQishuiSource == true,
           qishui.latestMediaRemoteSnapshot?.currentTrack != nil,
           qishui.latestQishuiControlAvailability != .available {
            qishui.scheduleQishuiControlAvailabilityRefresh()
        }
        let update = selectedMusicUpdate()
        recordUsageState(update.music, status: update.sourceStatus)
        onUpdate(update.music, update.sourceStatus)
        realtimeRefreshInFlight = false

        if realtimeRefreshQueued {
            realtimeRefreshQueued = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.refreshFromRealtimeSignal(onUpdate: onUpdate)
            }
        }
    }

    private func publishCurrentState() {
        let update = selectedMusicUpdate()
        recordUsageState(update.music, status: update.sourceStatus)
        realtimeUpdateHandler?(update.music, update.sourceStatus)
    }

    func refreshSourceStatus(
        promptForPermission: Bool = false,
        allowSynchronousRefresh: Bool = false
    ) -> MusicSourceStatus {
        qishui.refreshSourceStatus(
            promptForPermission: promptForPermission,
            allowSynchronousRefresh: allowSynchronousRefresh
        )
    }

    private func startQishuiLifecycleObservation() {
        stopQishuiLifecycleObservation()
        let notificationCenter = NSWorkspace.shared.notificationCenter
        let terminatedObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let terminatedApplication = (
                notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            )
            let bundleIdentifier = terminatedApplication?.bundleIdentifier
            guard let source = Self.musicSourceID(for: bundleIdentifier) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let bundleIdentifier,
                   let terminatedProcessIdentifier = terminatedApplication?.processIdentifier,
                   NSRunningApplication.runningApplications(
                       withBundleIdentifier: bundleIdentifier
                   ).contains(where: {
                       !$0.isTerminated
                           && $0.processIdentifier != terminatedProcessIdentifier
                   }) {
                    return
                }
                self.recordUsage("source_process", fields: [
                    "lifecycle": "terminate",
                    "pid": String(terminatedApplication?.processIdentifier ?? 0),
                    "source": MusicUsageEmitter.sourceLabel(source)
                ])
                if self.foregroundMusicSource == source {
                    self.foregroundMusicSource = nil
                }
                switch source {
                case .qishui:
                    self.qishui.markQishuiNotRunning(reason: "lifecycle_termination")
                case .neteaseMusic:
                    self.neteaseMusicRefreshGeneration &+= 1
                    self.neteaseMusicRefreshTask?.cancel()
                    self.neteaseMusicRefreshTask = nil
                    self.lastNeteaseMusicRefreshStartedAt = nil
                    self.neteaseMusicAdapter.invalidateRunningInstance(
                        processIdentifier: terminatedApplication?.processIdentifier
                    )
                    self.latestNeteaseMusicSnapshot = nil
                case .appleMusic:
                    self.appleMusic.appleMusicRefreshGeneration &+= 1
                    self.appleMusic.appleMusicRefreshTask?.cancel()
                    self.appleMusic.appleMusicRefreshTask = nil
                    self.appleMusic.appleMusicRefreshQueued = false
                    self.appleMusic.cancelAppleMusicTransientRetry(resetAttempt: true)
                    self.appleMusic.clearAppleMusicPlaybackControlExpectation()
                    self.appleMusic.latestAppleMusicSnapshot = nil
                    self.appleMusic.lastAppleMusicRefreshCompletedAt = Date()
                    self.appleMusic.appleMusicConsecutiveRefreshFailures = 0
                }
                self.publishCurrentState()
            }
        }
        let launchedObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let launchedApplication = (
                notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            )
            let bundleIdentifier = launchedApplication?.bundleIdentifier
            guard let source = Self.musicSourceID(for: bundleIdentifier) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recordUsage("source_process", fields: [
                    "lifecycle": "launch",
                    "pid": String(launchedApplication?.processIdentifier ?? 0),
                    "source": MusicUsageEmitter.sourceLabel(source)
                ])
                switch source {
                case .qishui:
                    self.qishui.resetForQishuiLaunch()
                case .neteaseMusic:
                    self.neteaseMusicRefreshGeneration &+= 1
                    self.neteaseMusicRefreshTask?.cancel()
                    self.neteaseMusicRefreshTask = nil
                    self.lastNeteaseMusicRefreshStartedAt = nil
                case .appleMusic:
                    self.appleMusic.cancelAppleMusicTransientRetry(resetAttempt: true)
                    self.appleMusic.lastAppleMusicRefreshCompletedAt = nil
                    self.appleMusic.appleMusicConsecutiveRefreshFailures = 0
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
                switch source {
                case .qishui:
                    self.qishui.scheduleQishuiControlAvailabilityRefresh()
                    await self.qishui.refreshForegroundQishuiState()
                    return
                case .neteaseMusic:
                    self.neteaseMusicAdapter.rebindObservationToRunningInstance()
                    self.scheduleNeteaseMusicRefresh(refresh: .metadata, retryAttempt: 0)
                case .appleMusic:
                    guard self.appleMusic.appleMusicEnabled else { return }
                    self.appleMusic.scheduleAppleMusicRefresh(force: true)
                }
                self.publishCurrentState()
            }
        }
        let activatedObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let bundleIdentifier = (
                notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            )?.bundleIdentifier
            Task { @MainActor [weak self] in
                guard let self else { return }
                var source = Self.musicSourceID(for: bundleIdentifier)
                if source == .appleMusic, !self.appleMusic.appleMusicEnabled {
                    source = nil
                }
                guard source != self.foregroundMusicSource else { return }
                self.foregroundMusicSource = source
                self.publishCurrentState()
                switch source {
                case .qishui:
                    self.qishui.scheduleQishuiControlAvailabilityRefresh()
                    await self.qishui.refreshForegroundQishuiState()
                    return
                case .neteaseMusic:
                    self.scheduleNeteaseMusicRefresh(refresh: .metadata, retryAttempt: 0)
                case .appleMusic:
                    self.appleMusic.scheduleAppleMusicRefresh(force: true)
                case nil:
                    self.qishui.schedulePlaybackPositionRefresh()
                    self.appleMusic.scheduleAppleMusicRefresh(force: true)
                }
            }
        }
        qishui.qishuiLifecycleObservers = [
            terminatedObserver,
            launchedObserver,
            activatedObserver
        ]
    }

    private func stopQishuiLifecycleObservation() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        for observer in qishui.qishuiLifecycleObservers {
            notificationCenter.removeObserver(observer)
        }
        qishui.qishuiLifecycleObservers.removeAll()
    }

    private func startNeteaseMusicObservation() {
        neteaseMusicAdapter.start { [weak self] _ in
            self?.scheduleNeteaseMusicRefresh(refresh: .cached)
        }
        scheduleNeteaseMusicRefresh(refresh: .metadata, retryAttempt: 0)
    }

    private func stopNeteaseMusicObservation() {
        neteaseMusicRefreshGeneration &+= 1
        neteaseMusicRefreshTask?.cancel()
        neteaseMusicRefreshTask = nil
        lastNeteaseMusicRefreshStartedAt = nil
        neteaseMusicAdapter.stop()
        latestNeteaseMusicSnapshot = nil
    }

    private func scheduleNeteaseMusicRefresh(
        refresh: MusicSnapshotRefresh,
        delayNanoseconds: UInt64 = 0,
        retryAttempt: Int? = nil
    ) {
        lastNeteaseMusicRefreshStartedAt = Date()
        neteaseMusicRefreshGeneration &+= 1
        let generation = neteaseMusicRefreshGeneration
        neteaseMusicRefreshTask?.cancel()
        neteaseMusicRefreshTask = Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled, let self else { return }
            let snapshot = await self.neteaseMusicAdapter.snapshot(refresh: refresh)
            guard !Task.isCancelled,
                  generation == self.neteaseMusicRefreshGeneration else { return }
            self.neteaseMusicRefreshTask = nil
            if let retryAttempt,
               let retryDelay = NeteaseMusicRefreshRetryPolicy.nextDelay(
                afterFailedAttempt: retryAttempt,
                appIsRunning: !NSRunningApplication.runningApplications(
                    withBundleIdentifier: MusicAdapterRegistry.neteaseMusic
                        .descriptor.bundleIdentifier
                ).isEmpty,
                availability: snapshot.availability
               ) {
                self.scheduleNeteaseMusicRefresh(
                    refresh: .metadata,
                    delayNanoseconds: retryDelay,
                    retryAttempt: retryAttempt + 1
                )
                return
            }
            if case .notRunning = snapshot.availability {
                self.latestNeteaseMusicSnapshot = nil
            } else {
                let previousTrackIdentity = self.latestNeteaseMusicSnapshot?
                    .track?.identity
                self.latestNeteaseMusicSnapshot = snapshot
                if snapshot.track?.identity != previousTrackIdentity {
                    let processIdentifier = snapshot.instance?.processIdentifier ?? 0
                    let trackFingerprint = snapshot.track.map {
                        MusicUsageTrackFingerprint.make(
                            source: "netease_music",
                            title: $0.title,
                            artist: $0.artist ?? ""
                        )
                    } ?? "none"
                    let playbackState = Self.playbackStateLabel(snapshot.playbackState)
                    self.logger.notice(
                        "Netease snapshot changed pid=\(processIdentifier) track=\(trackFingerprint, privacy: .public) state=\(playbackState, privacy: .public)"
                    )
                }
            }
            self.publishCurrentState()
        }
    }

    private func scheduleNeteaseMusicVerificationIfNeeded(
        minimumInterval: TimeInterval,
        now: Date = Date()
    ) {
        guard neteaseMusicRefreshTask == nil else { return }
        if let lastNeteaseMusicRefreshStartedAt,
           now.timeIntervalSince(lastNeteaseMusicRefreshStartedAt)
            < minimumInterval {
            return
        }
        scheduleNeteaseMusicRefresh(refresh: .timeline)
    }

    nonisolated private static func musicSourceID(
        for bundleIdentifier: String?
    ) -> MusicSourceID? {
        MusicSourceID(bundleIdentifier: bundleIdentifier)
    }

    private func selectedMusicSelection() -> MusicSourceSelection {
        reconcileForegroundMusicSource()
        let previousSelection = musicSourceSelector.selection
        let selection = musicSourceSelector.update(
            qishui: qishui.qishuiSourceCandidate(),
            neteaseMusic: neteaseMusicSourceCandidate(),
            appleMusic: appleMusic.appleMusicSourceCandidate(),
            foregroundSource: foregroundMusicSource
        )
        if selection.generation != previousSelection.generation {
            qishui.mediaRemoteAdapterStreamSource.invalidatePendingSeekRequests()
            logger.notice(
                "Music source changed from=\(MusicUsageEmitter.sourceLabel(previousSelection.source), privacy: .public) to=\(MusicUsageEmitter.sourceLabel(selection.source), privacy: .public) foreground=\(MusicUsageEmitter.sourceLabel(self.foregroundMusicSource), privacy: .public)"
            )
            let reason: String
            if selection.source != nil,
               selection.source == foregroundMusicSource {
                reason = "foreground"
            } else if selection.source == nil {
                reason = "unavailable"
            } else {
                reason = "admission"
            }
            recordUsage("source_change", fields: [
                "foreground": MusicUsageEmitter.sourceLabel(foregroundMusicSource),
                "from": MusicUsageEmitter.sourceLabel(previousSelection.source),
                "generation": String(selection.generation),
                "reason": reason,
                "to": MusicUsageEmitter.sourceLabel(selection.source)
            ])
        }
        return selection
    }

    private func selectedMusicSource() -> MusicSourceID? {
        selectedMusicSelection().source
    }

    nonisolated static func commandLabel(_ command: MusicControlCommand) -> String {
        switch command {
        case .playPause:
            return "play_pause"
        case .nextTrack:
            return "next"
        case .previousTrack:
            return "previous"
        }
    }

    private func recordUsage(_ name: String, fields: [String: String] = [:]) {
        usage.record(name, fields: fields)
    }

    private func recordUsageHeartbeatIfNeeded(_ state: MusicState, now: Date = Date()) {
        usage.recordHeartbeatIfNeeded(
            isObserving: isRealtimeObservationRunning,
            hasTrack: state.hasCurrentTrack,
            isPlaying: state.isPlaying,
            source: MusicUsageEmitter.sourceLabel(MusicSourceID(
                bundleIdentifier: state.track.sourceBundleIdentifier
            ) ?? musicSourceSelector.selection.source),
            now: now
        )
    }

    private func recordUsageState(
        _ state: MusicState,
        status: MusicSourceStatus
    ) {
        let sourceID = MusicSourceID(
            bundleIdentifier: state.track.sourceBundleIdentifier
        ) ?? musicSourceSelector.selection.source
        let didChangeTrack = usage.recordState(
            state,
            status: status,
            sourceID: sourceID,
            mediaTrack: qishui.latestMediaRemoteSnapshot?.currentTrack.map { ($0.title, $0.artist) },
            directTrack: qishui.latestQishuiSnapshot?.currentTrack.map { ($0.title, $0.artist) }
        )
        if didChangeTrack,
           sourceID == .qishui,
           qishui.latestQishuiControlAvailability.allowsCachePrewarmAfterTrackChange {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                guard let self,
                      self.isRealtimeObservationRunning,
                      self.qishui.latestQishuiControlAvailability
                        .allowsCachePrewarmAfterTrackChange else { return }
                self.qishui.scheduleQishuiControlAvailabilityRefresh()
            }
        }
    }

    nonisolated private static func sourceDisplayName(_ source: MusicSourceID?) -> String {
        switch source {
        case .qishui:
            return "汽水音乐"
        case .neteaseMusic:
            return "网易云音乐"
        case .appleMusic:
            return "Apple Music"
        case nil:
            return "默认状态"
        }
    }

    nonisolated static func playbackStateLabel(
        _ state: MusicPlaybackState
    ) -> String {
        switch state {
        case .playing:
            return "playing"
        case .paused:
            return "paused"
        case .stopped:
            return "stopped"
        case .unknown:
            return "unknown"
        }
    }

    private func neteaseMusicSourceCandidate() -> MusicSourceCandidate {
        let runningProcessIdentifier = NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicAdapterRegistry.neteaseMusic.descriptor.bundleIdentifier
        ).first?.processIdentifier
        let snapshot = latestNeteaseMusicSnapshot
        let snapshotMatchesRunningInstance = runningProcessIdentifier != nil
            && snapshot?.instance?.processIdentifier == runningProcessIdentifier
        let playback: MusicSourcePlaybackLevel
        switch snapshotMatchesRunningInstance ? snapshot?.playbackState : nil {
        case .playing:
            playback = .playing
        case .paused:
            playback = .paused
        case .stopped, .unknown, nil:
            playback = .unknown
        }
        return MusicSourceCandidate(
            source: .neteaseMusic,
            isAvailable: runningProcessIdentifier != nil,
            hasTrack: snapshotMatchesRunningInstance && snapshot?.track != nil,
            playback: playback,
            isCached: false
        )
    }

    private func hasCompetingMusicPlayback(
        excluding source: MusicSourceID
    ) -> Bool {
        MusicSourceAdmissionPolicy.hasCompetingPlayback(
            excluding: source,
            candidates: [
                qishui.qishuiSourceCandidate(),
                neteaseMusicSourceCandidate(),
                appleMusic.appleMusicSourceCandidate()
            ]
        )
    }

    private func reconcileForegroundMusicSource() {
        var source = Self.musicSourceID(
            for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        if source == .appleMusic, !appleMusic.appleMusicEnabled {
            source = nil
        }
        guard source != foregroundMusicSource else { return }

        foregroundMusicSource = source
        switch source {
        case .qishui:
            Task { [weak self] in
                await self?.qishui.refreshForegroundQishuiState()
            }
        case .neteaseMusic:
            scheduleNeteaseMusicRefresh(refresh: .metadata)
        case .appleMusic:
            appleMusic.scheduleAppleMusicRefresh(force: true)
        case nil:
            qishui.schedulePlaybackPositionRefresh()
            appleMusic.scheduleAppleMusicRefresh(force: true)
        }
    }

    private func selectedMusicState() -> MusicState {
        musicState(for: musicSourceSelector.selection.source)
    }

    private func selectedMusicStatus() -> MusicSourceStatus {
        musicStatus(for: musicSourceSelector.selection.source)
    }

    private func selectedMusicUpdate() -> (music: MusicState, sourceStatus: MusicSourceStatus) {
        let source = selectedMusicSource()
        return selectedMusicUpdate(for: source)
    }

    private func selectedMusicUpdate(
        for source: MusicSourceID?
    ) -> (music: MusicState, sourceStatus: MusicSourceStatus) {
        return (musicState(for: source), musicStatus(for: source))
    }

    private func musicState(for source: MusicSourceID?) -> MusicState {
        switch source {
        case .appleMusic:
            return appleMusic.appleMusicState()
        case .neteaseMusic:
            return neteaseMusicState()
        case .qishui, nil:
            return qishui.currentQishuiMusicState()
        }
    }

    private func musicStatus(for source: MusicSourceID?) -> MusicSourceStatus {
        if source == .neteaseMusic {
            return neteaseMusicStatus()
        }
        guard source == .appleMusic else {
            return qishui.cachedStatus
        }
        return appleMusic.appleMusicStatus()
    }

    private func neteaseMusicStatus() -> MusicSourceStatus {
        guard let snapshot = neteaseMusicSnapshotForRunningInstance() else {
            return MusicSourceStatus(
                sourceName: "网易云音乐",
                availability: .neteaseMusicSynced,
                headline: "等待网易云音乐同步",
                detail: "已检测到网易云音乐，正在读取当前进程的专属播放状态。",
                checkedAt: Date()
            )
        }
        let trackText = snapshot.track.map { track in
            [track.title, track.artist]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " - ")
        } ?? "无当前歌曲"
        return MusicSourceStatus(
            sourceName: "网易云音乐",
            availability: .neteaseMusicSynced,
            headline: "已接入网易云音乐",
            detail: "\(trackText)。状态与控制均绑定 com.netease.163music 当前 PID。",
            checkedAt: snapshot.checkedAt
        )
    }

    private func neteaseMusicState() -> MusicState {
        guard let snapshot = neteaseMusicSnapshotForRunningInstance(),
              let track = snapshot.track else {
            return neteaseMusicIdleState()
        }
        let elapsedTime: TimeInterval?
        let duration: TimeInterval?
        let progress: Double
        if let timeline = snapshot.timeline {
            duration = timeline.duration
            let projected = timeline.elapsedTime
                + max(Date().timeIntervalSince(timeline.observedAt), 0) * timeline.playbackRate
            let clamped = min(max(projected, 0), timeline.duration)
            elapsedTime = clamped
            progress = timeline.duration > 0 ? clamped / timeline.duration : 0
        } else {
            duration = nil
            elapsedTime = nil
            progress = 0
        }
        return MusicState(
            track: MusicTrack(
                title: track.title,
                artist: track.artist ?? "网易云音乐",
                palette: [
                    Color(red: 0.90, green: 0.12, blue: 0.14),
                    Color(red: 0.18, green: 0.03, blue: 0.04)
                ],
                lyrics: track.lyrics,
                hasArtwork: track.artworkData != nil,
                artworkData: track.artworkData,
                artworkURL: nil,
                sourceBundleIdentifier: MusicAdapterRegistry.neteaseMusic.descriptor.bundleIdentifier
            ),
            isPlaying: snapshot.playbackState == .playing,
            progress: min(max(progress, 0), 1),
            lyricIndex: 0,
            elapsedTime: elapsedTime,
            duration: duration,
            canSeek: false,
            isPlaybackPending: false,
            canPlayPause: snapshot.controls.supports(.playPause),
            canPreviousTrack: snapshot.controls.supports(.previousTrack),
            canNextTrack: snapshot.controls.supports(.nextTrack),
            controlUnavailableReason: AXIsProcessTrusted()
                ? "网易云音乐当前没有提供这个控制。"
                : "需要辅助功能权限才能控制网易云音乐。",
            hasCurrentTrack: true
        )
    }

    private func neteaseMusicIdleState() -> MusicState {
        MusicState(
            track: MusicTrack(
                title: "网易云音乐",
                artist: "等待播放",
                palette: [
                    Color(red: 0.90, green: 0.12, blue: 0.14),
                    Color(red: 0.18, green: 0.03, blue: 0.04)
                ],
                lyrics: [],
                hasArtwork: false,
                artworkData: nil,
                artworkURL: nil,
                sourceBundleIdentifier: MusicAdapterRegistry.neteaseMusic.descriptor.bundleIdentifier
            ),
            isPlaying: false,
            progress: 0,
            lyricIndex: 0,
            elapsedTime: nil,
            duration: nil,
            canSeek: false,
            isPlaybackPending: false,
            canPlayPause: false,
            canPreviousTrack: false,
            canNextTrack: false,
            controlUnavailableReason: "网易云音乐当前没有可控制的歌曲。",
            hasCurrentTrack: false
        )
    }

    private func neteaseMusicSnapshotForRunningInstance() -> MusicAppSnapshot? {
        let runningProcessIdentifier = NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicAdapterRegistry.neteaseMusic.descriptor.bundleIdentifier
        ).first?.processIdentifier
        guard let snapshot = latestNeteaseMusicSnapshot,
              snapshot.instance?.processIdentifier == runningProcessIdentifier else {
            return nil
        }
        return snapshot
    }

    private func qishuiLyricIdentity() -> QishuiLyricIdentity? {
        guard selectedMusicSource() == .qishui else { return nil }
        let mediaIdentity: QishuiLyricIdentity?
        if let track = qishui.latestMediaRemoteSnapshot?.currentTrack,
           track.sourceBundleIdentifier == QishuiProcessLocator.bundleIdentifier,
           let processIdentifier = track.sourceProcessIdentifier {
            mediaIdentity = .init(processIdentifier: processIdentifier, title: track.title, artist: track.artist)
        } else {
            mediaIdentity = nil
        }
        let directIdentity: QishuiLyricIdentity?
        if let snapshot = qishui.latestQishuiSnapshot,
           let track = snapshot.currentTrack,
           let processIdentifier = snapshot.processIdentifier {
            directIdentity = .init(processIdentifier: processIdentifier, title: track.title, artist: track.artist)
        } else {
            directIdentity = nil
        }
        // One process inventory per decision, with playback identity always
        // winning over AX credit formatting and visible recommendations.
        return QishuiLyricIdentityPolicy.select(
            media: mediaIdentity, direct: directIdentity,
            runningProcesses: Set(QishuiProcessLocator.runningApplications().map(\.processIdentifier))
        )
    }

    private func cleanDisplayLyrics(_ lines: [String]) -> [String] {
        MusicLyricPresentation.clean(lines)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = max(Int(time.rounded()), 0)
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}

extension MusicAdapterCoordinator: QishuiMusicAdapterHost {
    var qishuiForegroundSource: MusicSourceID? { foregroundMusicSource }
    var qishuiUsage: MusicUsageEmitter { usage }
    var lyricPipeline: QishuiLyricPipeline { qishuiLyrics }
    var qishuiIsObserving: Bool { isRealtimeObservationRunning }
    var qishuiSeeks: SeekCoordinator { seeks }

    func qishuiHasCompetingPlayback(excluding source: MusicSourceID) -> Bool {
        hasCompetingMusicPlayback(excluding: source)
    }

    func qishuiPublish() {
        publishCurrentState()
    }

    func qishuiRecord(_ name: String, fields: [String: String]) {
        recordUsage(name, fields: fields)
    }

    func qishuiSelectedSource() -> MusicSourceID? {
        selectedMusicSource()
    }

    var qishuiSelectorSource: MusicSourceID? { musicSourceSelector.selection.source }

    func qishuiControlSelection() -> MusicSourceSelection {
        selectedMusicSelection()
    }

    func qishuiSelectedMusicState() -> MusicState {
        selectedMusicState()
    }

    func qishuiStaleDisplayedSourceOutcome(
        command: MusicControlCommand,
        binding: DisplayedMusicControlBinding,
        selectedSource: MusicSourceID?
    ) -> MusicControlOutcome {
        staleDisplayedSourceOutcome(command: command, binding: binding, selectedSource: selectedSource)
    }
}

extension MusicAdapterCoordinator: AppleMusicDriverHost {
    var appleMusicSelectorSource: MusicSourceID? { musicSourceSelector.selection.source }
    var appleMusicForegroundSource: MusicSourceID? { foregroundMusicSource }

    func appleMusicPublish() {
        publishCurrentState()
    }

    func appleMusicRecord(_ name: String, fields: [String: String]) {
        recordUsage(name, fields: fields)
    }
}
