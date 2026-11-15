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

private struct ControlDispatchResult {
    let didPress: Bool
    let diagnostic: String
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
    private let qishuiAdapter = QishuiAdapter()
    private let neteaseMusicAdapter = NeteaseMusicAppAdapter()
    private let appleMusicTransitionTimeline = AppleMusicTransitionTimeline()
    private lazy var appleMusicAdapter = AppleMusicAppAdapter(
        transitionTimeline: appleMusicTransitionTimeline
    )
    private let musicSourceSelector = MusicSourceSelector()
    private let qishuiAXChangeMonitor = QishuiAXChangeMonitor()
    private let qishuiSemanticAXController = QishuiSemanticAXController()
    private lazy var qishuiLyrics = QishuiLyricPipeline(
        debugEnabled: ProcessInfo.processInfo.environment["TOPISLET_QISHUI_LYRIC_DEBUG"] == "1",
        host: QishuiLyricPipeline.Host(
            isObserving: { [weak self] in self?.isRealtimeObservationRunning ?? false },
            currentIdentity: { [weak self] in self?.qishuiLyricIdentity() },
            mediaTrack: { [weak self] in self?.latestMediaRemoteSnapshot?.currentTrack },
            directSnapshot: { [weak self] in self?.latestQishuiSnapshot },
            recordEvent: { [weak self] name, fields in self?.recordUsage(name, fields: fields) },
            publish: { [weak self] in self?.publishCurrentState() },
            debugSourceDescription: { [weak self] in String(describing: self?.selectedMusicSource()) }
        )
    )
    private let seeks = SeekCoordinator()

    func setQishuiTimedLyricsEnabled(_ enabled: Bool) {
        qishuiLyrics.setTimedLyricsEnabled(enabled)
    }

    private let qishuiWorkQueues = QishuiWorkQueues()
    private let mediaRemoteAdapterStreamSource = MediaRemoteAdapterStreamSource()
    private let nowPlayingBridge = NowPlayingAXBridge()
    private let logger = Logger(
        subsystem: "io.github.scorpioxyb.topislet",
        category: "MusicAdapter"
    )
    private let usage = MusicUsageEmitter()
    private let automaticRefreshInterval: TimeInterval = 5.0
    private let playbackPositionRefreshInterval: TimeInterval = 2.0
    private var latestQishuiSnapshot: QishuiDirectSnapshot?
    private var qishuiIdentityRefreshInFlight = false
    private var qishuiIdentityRefreshGeneration: UInt64 = 0
    private var lastQishuiTransitionIdentityRequested: QishuiLyricIdentity?
    private var lastQishuiIdentityRefreshAt = Date.distantPast
    private var qishuiLifecycleMetadataTask: Task<Void, Never>?
    private var latestQishuiControlAvailability: QishuiControlAvailability = .unknown
    var qishuiControlAvailability: QishuiControlAvailability {
        latestQishuiControlAvailability
    }

    func resetQishuiControlVerificationForRecovery() {
        cancelQishuiControlAvailabilityScheduling()
        latestQishuiControlAvailability = .unknown
        qishuiAdapter.invalidateAXCache()
        qishuiSemanticAXController.invalidateCache()
    }

    func verifyQishuiControlsAfterRecovery() async {
        // Recovery resets cancel the ordinary retry loop. Metadata refreshes
        // cannot substitute for a completed semantic control probe.
        cancelQishuiControlAvailabilityScheduling()
        let generation = qishuiControlAvailabilityGeneration
        guard let processIdentifier = runningQishuiApplication()?.processIdentifier else {
            latestQishuiControlAvailability = .notRunning
            publishCurrentState()
            return
        }
        let availability = await probeQishuiControlAvailability(
            processIdentifier: processIdentifier
        )
        let queues = qishuiWorkQueues
        let snapshot = await withCheckedContinuation { continuation in
            queues.metadata.async {
                continuation.resume(returning: queues.metadataSnapshot())
            }
        }
        guard MusicControlRecoveryPolicy.acceptsVerification(
            requestedGeneration: generation,
            currentGeneration: qishuiControlAvailabilityGeneration,
            requestedProcess: processIdentifier,
            currentProcess: runningQishuiApplication()?.processIdentifier,
            isCancelled: Task.isCancelled
        ), snapshot.processIdentifier == processIdentifier else { return }
        _ = applyQishuiDirectSnapshot(snapshot)
        latestQishuiControlAvailability = availability
        lastQishuiControlHealthCheckAt = Date()
        publishCurrentState()
        if availability != .available {
            scheduleQishuiControlAvailabilityRetry()
        }
    }
    private var latestMediaRemoteSnapshot: MediaRemoteNowPlayingSnapshot?
    private var lastSourceRefreshAt: Date?
    private var lastPlaybackPositionRefreshAt: Date?
    private var controlGeneration = 0
    private var qishuiControlAvailabilityGeneration: UInt64 = 0
    private var qishuiControlAvailabilityRefreshInFlight = false
    private var qishuiControlAvailabilityRefreshQueued = false
    private var lastQishuiControlHealthCheckAt: Date?
    private var qishuiControlAvailabilityRetryAttempt = 0
    private var qishuiControlAvailabilityRetryTask: Task<Void, Never>?
    private var lastTrackControlStartedAt: Date?
    private let playback = PlaybackOperationTracker()
    private var qishuiInference = QishuiPlaybackInference()
    private var realtimeRefreshInFlight = false
    private var realtimeRefreshQueued = false
    private var playbackPositionRefreshInFlight = false
    private var realtimeUpdateHandler: ((MusicState, MusicSourceStatus) -> Void)?
    private var qishuiLifecycleObservers: [NSObjectProtocol] = []
    private var foregroundMusicSource: MusicSourceID?
    private var latestNeteaseMusicSnapshot: MusicAppSnapshot?
    private var neteaseMusicRefreshTask: Task<Void, Never>?
    private var neteaseMusicRefreshGeneration: UInt64 = 0
    private var lastNeteaseMusicRefreshStartedAt: Date?
    private var neteaseMusicControlRequestID: UInt64 = 0
    private var latestAppleMusicSnapshot: MusicAppSnapshot?
    private var appleMusicEnabled = true
    private var isRealtimeObservationRunning = false
    private var appleMusicRefreshTask: Task<Void, Never>?
    private var appleMusicRefreshQueued = false
    private var appleMusicRefreshGeneration: UInt64 = 0
    private var appleMusicTransientRetryAttempt = 0
    private var appleMusicTransientRetryTask: Task<Void, Never>?
    private var lastAppleMusicRefreshCompletedAt: Date?
    private var lastAppleMusicControlAt: Date?
    private var appleMusicConsecutiveRefreshFailures = 0
    private var appleMusicControlRequestID: UInt64 = 0
    private var appleMusicControlGeneration: UInt64 = 0
    private var pendingAppleMusicPlaybackControl: AppleMusicPlaybackControlExpectation?
    private var appleMusicPlaybackExpectationTask: Task<Void, Never>?
    private var lastAppleMusicUIPublishFingerprint: String?
    private var cachedStatus = MusicSourceStatus(
        sourceName: "汽水音乐",
        availability: .preview,
        headline: "等待汽水音乐真实数据",
        detail: "当前不显示假歌曲；主线正在读取汽水音乐本地状态和可发现 IPC。",
        checkedAt: Date()
    )

    var initialState: MusicState {
        MusicState(
            track: placeholderTrack(statusLine: "正在等待汽水直接适配源"),
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
        if appleMusicEnabled {
            startAppleMusicObservation()
        }
        mediaRemoteAdapterStreamSource.setTrackTransitionStageHandler { [weak self] event in
            self?.usage.recordQishuiTransitionStage(event)
        }
        mediaRemoteAdapterStreamSource.setIdentityObservationHandler { [weak self] event in
            self?.recordUsage(event.name, fields: event.fields)
        }
        mediaRemoteAdapterStreamSource.start { [weak self] in
            guard let self else { return }
            self.refreshFromRealtimeSignal(onUpdate: onUpdate)
        }
        qishuiAXChangeMonitor.start { [weak self] notification in
            guard let self else { return }
            if QishuiAXNotificationBatch.structuralNotifications.contains(notification) {
                self.scheduleQishuiControlAvailabilityRefresh()
                self.scheduleQishuiLifecycleMetadataRefresh()
            }
            self.refreshFromRealtimeSignal(onUpdate: onUpdate)
        }
        scheduleQishuiControlAvailabilityRefresh()
        reconcileForegroundMusicSource()
        schedulePlaybackPositionRefresh()
        scheduleQishuiLifecycleMetadataRefresh()
    }

    func stopRealtimeObservation() {
        usage.observationStopped(at: Date())
        isRealtimeObservationRunning = false
        mediaRemoteAdapterStreamSource.setIdentityObservationHandler(nil)
        seeks.cancelResume()
        qishuiIdentityRefreshGeneration &+= 1
        qishuiIdentityRefreshInFlight = false
        lastQishuiIdentityRefreshAt = .distantPast
        qishuiLyrics.invalidate()
        qishuiLifecycleMetadataTask?.cancel()
        qishuiLifecycleMetadataTask = nil
        realtimeUpdateHandler = nil
        stopQishuiLifecycleObservation()
        stopNeteaseMusicObservation()
        stopAppleMusicObservation()
        foregroundMusicSource = nil
        usage.clearQishuiTransition()
        mediaRemoteAdapterStreamSource.setTrackTransitionStageHandler(nil)
        mediaRemoteAdapterStreamSource.stop()
        qishuiAXChangeMonitor.stop()
        cancelQishuiControlAvailabilityScheduling()
        playback.reset(clearTimelineFloor: true)
    }

    func setAppleMusicEnabled(_ enabled: Bool) {
        guard appleMusicEnabled != enabled else { return }
        appleMusicEnabled = enabled
        if enabled {
            if isRealtimeObservationRunning {
                startAppleMusicObservation()
            }
        } else {
            if foregroundMusicSource == .appleMusic {
                foregroundMusicSource = nil
            }
            stopAppleMusicObservation()
        }
        reconcileForegroundMusicSource()
        publishCurrentState()
    }

    func appleMusicSnapshotForSettings() async -> MusicAppSnapshot? {
        guard appleMusicEnabled else { return nil }
        if appleMusicRefreshTask == nil {
            scheduleAppleMusicRefresh(force: true)
        }
        let deadline = Date().addingTimeInterval(2)
        while appleMusicRefreshTask != nil,
              appleMusicEnabled,
              !Task.isCancelled,
              Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        guard appleMusicEnabled,
              !Task.isCancelled,
              appleMusicRefreshTask == nil else { return nil }
        return latestAppleMusicSnapshot
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
        guard appleMusicEnabled else { return }
        stopAppleMusicObservation()
        if isRealtimeObservationRunning {
            startAppleMusicObservation()
        }
        publishCurrentState()
    }

    func playPause(_ state: MusicState) -> MusicState {
        state
    }

    func nextTrack() -> MusicState {
        MusicState(
            track: placeholderTrack(statusLine: "已发送切歌控制，等待汽水直接状态回读"),
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
            track: placeholderTrack(statusLine: "已发送切歌控制，等待汽水直接状态回读"),
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
            mediaRemoteAdapterStreamSource.beginTrackTransitionObservation(
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
                hasAlbum: !(latestMediaRemoteSnapshot?.currentTrack?.album ?? "")
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
            guard appleMusicEnabled else {
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
        let canAttemptControl = runningQishuiApplication() != nil
        guard canAttemptControl else {
            markQishuiNotRunning()
            return MusicControlOutcome(status: cachedStatus, didSendCommand: false)
        }

        let now = Date()
        let followsRecentTrackControl = command == .playPause
            && lastTrackControlStartedAt.map { now.timeIntervalSince($0) < 1.0 } == true
        controlGeneration += 1
        let controlAttemptGeneration = controlGeneration
        if command != .playPause {
            lastTrackControlStartedAt = now
        }
        if followsRecentTrackControl {
            guard await synchronizeAfterQueuedTrackControl(
                generation: controlAttemptGeneration
            ) else {
                return MusicControlOutcome(status: cachedStatus, didSendCommand: false)
            }
            guard authorization.isValid(for: selectedMusicSelection()) else {
                return staleDisplayedSourceOutcome(
                    command: command,
                    binding: binding,
                    selectedSource: musicSourceSelector.selection.source
                )
            }
        }

        let targetProcessIdentifier = runningQishuiApplication()?.processIdentifier
        guard let targetProcessIdentifier else {
            markQishuiNotRunning()
            return MusicControlOutcome(status: cachedStatus, didSendCommand: false)
        }

        let controlAvailability: QishuiControlAvailability
        if latestQishuiControlAvailability.requiresPreflightBeforeControl {
            controlAvailability = await probeQishuiControlAvailability(
                processIdentifier: targetProcessIdentifier
            )
            latestQishuiControlAvailability = controlAvailability
        } else {
            controlAvailability = latestQishuiControlAvailability
        }
        guard controlAttemptGeneration == controlGeneration else {
            return MusicControlOutcome(status: cachedStatus, didSendCommand: false)
        }
        guard authorization.isValid(for: selectedMusicSelection()) else {
            return staleDisplayedSourceOutcome(
                command: command,
                binding: binding,
                selectedSource: musicSourceSelector.selection.source
            )
        }
        // A previous availability probe can legitimately be stale: Qishui may
        // have been minimized when the probe ran and expose its full AX tree
        // again after returning to the foreground.  Do not let that cached
        // `controlTreeUnavailable` result prevent the semantic controller from
        // performing its own PID-bound, unique-control discovery.  The
        // controller remains the final safety gate and rejects ambiguous or
        // missing controls without sending a command.
        let canAttemptSemanticControl: Bool
        switch controlAvailability {
        case .available, .controlTreeUnavailable, .unknown:
            canAttemptSemanticControl = true
        case .windowClosed, .accessibilityRequired, .notRunning:
            canAttemptSemanticControl = false
        }
        guard canAttemptSemanticControl else {
            cachedStatus = MusicSourceStatus(
                sourceName: "汽水音乐",
                availability: controlAvailability == .accessibilityRequired
                    ? .accessibilityRequired
                    : .qishuiMediaRemoteCached,
                headline: "当前无法执行\(command.label)",
                detail: controlAvailability.unavailableReason
                    ?? "汽水播放控件当前不可用。",
                checkedAt: Date()
            )
            publishCurrentState()
            return MusicControlOutcome(status: cachedStatus, didSendCommand: false)
        }

        _ = refreshSourceStatus()
        if command != .playPause {
            playback.reset(clearTimelineFloor: true)
        }
        let requestedState = currentQishuiMusicState()
        let playbackOperationID: Int?
        if command == .playPause {
            playbackOperationID = beginPendingPlaybackOperation(
                requestedState: requestedState
            )
            cachedStatus = MusicSourceStatus(
                sourceName: "汽水音乐",
                availability: .qishuiControlSent,
                headline: "正在执行\(command.label)",
                detail: "已立即切换本地播放状态，等待汽水状态回读确认。",
                checkedAt: Date()
            )
            publishCurrentState()
        } else {
            playbackOperationID = nil
        }
        let controlResult = await sendControl(
            command,
            generation: controlAttemptGeneration,
            processIdentifier: targetProcessIdentifier
        )
        guard controlAttemptGeneration == controlGeneration else {
            return MusicControlOutcome(status: cachedStatus, didSendCommand: false)
        }
        let didPost = controlResult.didPress
        if !didPost {
            latestQishuiControlAvailability = .controlTreeUnavailable
            scheduleQishuiControlAvailabilityRefresh()
        }

        if let playbackOperationID {
            if didPost {
                if playback.isCurrent(playbackOperationID) {
                    schedulePendingPlaybackConfirmationTimeout(id: playbackOperationID)
                }
                cachedStatus = MusicSourceStatus(
                    sourceName: "汽水音乐",
                    availability: .qishuiControlSent,
                    headline: "已执行\(command.label)",
                    detail: controlResult.diagnostic,
                    checkedAt: Date()
                )
                publishCurrentState()
            } else {
                let failureStatus = MusicSourceStatus(
                    sourceName: "汽水音乐",
                    availability: .qishuiMediaRemoteCached,
                    headline: "未执行\(command.label)",
                    detail: controlResult.diagnostic,
                    checkedAt: Date()
                )
                rollbackPendingPlaybackOperation(id: playbackOperationID, status: failureStatus)
            }
            return MusicControlOutcome(status: cachedStatus, didSendCommand: didPost)
        }

        if !didPost {
            playback.reset(clearTimelineFloor: false)
        }
        cachedStatus = MusicSourceStatus(
            sourceName: "汽水音乐",
            availability: didPost ? .qishuiControlSent : .qishuiMediaRemoteCached,
            headline: didPost ? "已执行\(command.label)" : "未执行\(command.label)",
            detail: controlResult.diagnostic,
            checkedAt: Date()
        )
        return MusicControlOutcome(status: cachedStatus, didSendCommand: didPost)
    }

    private func performAppleMusicControl(
        _ command: MusicControlCommand
    ) async -> MusicControlOutcome {
        guard let snapshot = latestAppleMusicSnapshot,
              let instance = snapshot.instance,
              let track = snapshot.track else {
            return MusicControlOutcome(
                status: appleMusicControlStatus(
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
                status: appleMusicControlStatus(
                    command: command,
                    succeeded: false,
                    diagnostic: "Apple Music 未提供匹配当前进程的控制能力。"
                ),
                didSendCommand: false
            )
        }

        appleMusicControlGeneration &+= 1
        let controlGeneration = appleMusicControlGeneration
        let controlIssuedAt = Date()
        lastAppleMusicControlAt = controlIssuedAt
        appleMusicTransitionTimeline.beginControl(
            command: command.label,
            baseline: "\(track.title) - \(track.artist ?? "")"
        )
        clearAppleMusicPlaybackControlExpectation()
        let resolvedAction: MusicControlAction
        if controlKind == .playPause,
           let optimisticSnapshot = appleMusicSnapshot(
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
            beginAppleMusicPlaybackControlExpectation(
                expectation,
                generation: controlGeneration
            )
            latestAppleMusicSnapshot = optimisticSnapshot
            publishCurrentState()
        } else {
            resolvedAction = defaultAction
        }
        appleMusicControlRequestID &+= 1
        let request = MusicControlRequest(
            id: appleMusicControlRequestID,
            target: instance,
            expectedTrack: track.identity,
            action: resolvedAction
        )
        let result = await appleMusicAdapter.perform(request)
        let dispositionLabel: String
        switch result.disposition {
        case .accepted:
            dispositionLabel = "accepted"
        case .rejected:
            dispositionLabel = "rejected"
        case .failed:
            dispositionLabel = "failed"
        }
        appleMusicTransitionTimeline.record(
            .controlCompleted,
            detail: "command=\(command.label) disposition=\(dispositionLabel)"
        )
        let succeeded = result.disposition == .accepted
        guard controlGeneration == appleMusicControlGeneration else {
            return MusicControlOutcome(
                status: appleMusicControlStatus(
                    command: command,
                    succeeded: succeeded,
                    diagnostic: result.diagnostic
                ),
                didSendCommand: succeeded
            )
        }
        if succeeded {
            if controlKind != .previousTrack && controlKind != .nextTrack {
                scheduleAppleMusicRefresh(force: true)
            }
        } else if controlKind == .playPause {
            clearAppleMusicPlaybackControlExpectation()
            scheduleAppleMusicRefresh(force: true)
        }
        return MusicControlOutcome(
            status: appleMusicControlStatus(
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

    private func appleMusicControlStatus(
        command: MusicControlCommand,
        succeeded: Bool,
        diagnostic: String
    ) -> MusicSourceStatus {
        MusicSourceStatus(
            sourceName: "Apple Music",
            availability: succeeded ? .appleMusicControlSent : .appleMusicSynced,
            headline: succeeded ? "已执行\(command.label)" : "未执行\(command.label)",
            detail: diagnostic,
            checkedAt: Date()
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

    private func sendControl(
        _ command: MusicControlCommand,
        generation: Int,
        processIdentifier: pid_t
    ) async -> ControlDispatchResult {
        guard generation == controlGeneration else {
            return ControlDispatchResult(
                didPress: false,
                diagnostic: "旧控制操作已失效，未触发汽水语义控件。"
            )
        }
        let semanticResult = await pressSemanticControl(
            command,
            processIdentifier: processIdentifier
        )
        guard generation == controlGeneration else {
            return ControlDispatchResult(
                didPress: false,
                diagnostic: "旧控制操作已失效，忽略其执行结果。"
            )
        }
        return ControlDispatchResult(
            didPress: semanticResult.didPress,
            diagnostic: semanticResult.diagnostic
        )
    }

    private func pressSemanticControl(
        _ command: MusicControlCommand,
        processIdentifier: pid_t
    ) async -> QishuiSemanticAXControlResult {
        let semanticController = qishuiSemanticAXController
        let queuedAt = Date()
        let measured: (QishuiSemanticAXControlResult, Int, Int) = await withCheckedContinuation { continuation in
            qishuiWorkQueues.controls.async {
                let startedAt = Date()
                let result = semanticController.press(
                    command,
                    processIdentifier: processIdentifier
                )
                continuation.resume(returning: (result,
                    max(0, Int(startedAt.timeIntervalSince(queuedAt) * 1_000)),
                    max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))))
            }
        }
        recordUsage("control_dispatch", fields: [
            "command": Self.commandLabel(command),
            "source": "qishui",
            "queue_wait_ms": String(measured.1),
            "press_ms": String(measured.2),
            "dispatch_path": measured.0.dispatchPath ?? "not_sent"
        ])
        return measured.0
    }

    private func probeQishuiControlAvailability(
        processIdentifier: pid_t
    ) async -> QishuiControlAvailability {
        let semanticController = qishuiSemanticAXController
        return await withCheckedContinuation { continuation in
            qishuiWorkQueues.controls.async {
                continuation.resume(returning:
                    semanticController.controlAvailability(
                        processIdentifier: processIdentifier
                    )
                )
            }
        }
    }

    private func runningQishuiApplication() -> NSRunningApplication? {
        let runningApplications = QishuiProcessLocator.runningApplications()
        let runningProcessIdentifiers = Set(
            runningApplications.map(\.processIdentifier)
        )
        let verifiedMediaRemoteProcessIdentifier: pid_t?
        if latestMediaRemoteSnapshot?.isVerifiedQishuiSource == true {
            verifiedMediaRemoteProcessIdentifier = latestMediaRemoteSnapshot?
                .currentTrack?
                .sourceProcessIdentifier
        } else {
            verifiedMediaRemoteProcessIdentifier = nil
        }
        let preferredProcessIdentifier = QishuiProcessSelectionPolicy
            .preferredProcessIdentifier(
                verifiedMediaRemoteProcessIdentifier: verifiedMediaRemoteProcessIdentifier,
                directSnapshotProcessIdentifier: latestQishuiSnapshot?.processIdentifier,
                runningProcessIdentifiers: runningProcessIdentifiers
            )
        if let preferredProcessIdentifier {
            return runningApplications.first {
                $0.processIdentifier == preferredProcessIdentifier
            }
        }
        guard runningApplications.count == 1 else { return nil }
        return runningApplications.first
    }

    private func synchronizeAfterQueuedTrackControl(
        generation: Int
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            qishuiWorkQueues.controls.async {
                continuation.resume()
            }
        }
        guard generation == controlGeneration,
              !Task.isCancelled else { return false }
        do {
            try await Task.sleep(nanoseconds: 120_000_000)
        } catch {
            return false
        }
        guard generation == controlGeneration else { return false }
        while playbackPositionRefreshInFlight {
            guard generation == controlGeneration,
                  !Task.isCancelled else { return false }
            do {
                try await Task.sleep(nanoseconds: 10_000_000)
            } catch {
                return false
            }
        }
        guard generation == controlGeneration else { return false }
        playbackPositionRefreshInFlight = true
        _ = await mediaRemoteAdapterStreamSource.refreshPlaybackPositionAsync()
        playbackPositionRefreshInFlight = false
        return generation == controlGeneration
    }

    func tick(_ state: MusicState) -> (music: MusicState, sourceStatus: MusicSourceStatus?) {
        scheduleQishuiIdentityRefresh()
        qishuiLyrics.scheduleRefresh()
        reconcileForegroundMusicSource()
        if isRealtimeObservationRunning,
           latestQishuiControlAvailability == .available,
           !qishuiControlAvailabilityRefreshInFlight,
           QishuiProcessLocator.isRunning(),
           MusicControlRecoveryPolicy.needsHealthCheck(
               lastCheck: lastQishuiControlHealthCheckAt, now: Date()
           ) {
            scheduleQishuiControlAvailabilityRefresh()
        }
        scheduleAppleMusicRefresh(force: false)
        if playback.hasPendingOperation
            || shouldRefreshCachedPlaybackState()
            || shouldRefreshPlaybackPosition(state) {
            schedulePlaybackPositionRefresh()
        }
        _ = refreshSourceStatusIfNeeded()
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
        appleMusicTransitionTimeline.report()
    }

    func latestAppleMusicTransitionReport() -> String {
        appleMusicTransitionTimeline.latestReport()
    }

    func noteMusicUIPublished(_ state: MusicState) {
        let completedTransitionID = usage.recordUIPublished(
            state,
            lyricAgeMilliseconds: { self.qishuiLyrics.publishedLyricAgeMilliseconds(for: state) }
        )
        if let completedTransitionID {
            mediaRemoteAdapterStreamSource.endTrackTransitionObservation(
                transitionID: completedTransitionID
            )
        }
        guard state.track.sourceBundleIdentifier
            == MusicAdapterRegistry.appleMusic.descriptor.bundleIdentifier else {
            lastAppleMusicUIPublishFingerprint = nil
            return
        }
        let artworkBytes = state.track.artworkData?.count ?? 0
        let fingerprint = [
            state.track.title,
            state.track.artist,
            String(artworkBytes),
            String(state.isPlaying)
        ].joined(separator: "\u{1f}")
        guard fingerprint != lastAppleMusicUIPublishFingerprint else { return }
        lastAppleMusicUIPublishFingerprint = fingerprint
        appleMusicTransitionTimeline.record(
            .uiPublished,
            detail: "track=\(state.track.title) artist=\(state.track.artist) artworkBytes=\(artworkBytes) isPlaying=\(state.isPlaying)"
        )
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
            scheduleAppleMusicRefresh(force: true)
            return (selectedMusicState(), selectedMusicStatus())
        }
        if source == .neteaseMusic {
            scheduleNeteaseMusicRefresh(refresh: .timeline)
            return (selectedMusicState(), selectedMusicStatus())
        }
        let status = refreshPlaybackPositionStatus()
        return (selectedMusicState(), status)
    }

    func refreshNowPlaying(promptForPermission: Bool = false) -> (music: MusicState, status: MusicSourceStatus) {
        let status = refreshSourceStatus(promptForPermission: promptForPermission, allowSynchronousRefresh: true)
        guard status.availability != .qishuiNotRunning,
              status.availability != .accessibilityRequired else {
            return (currentQishuiMusicState(), status)
        }

        let snapshot = nowPlayingBridge.capture(promptForPermission: promptForPermission)
        applyNowPlayingSnapshot(snapshot)
        return (currentQishuiMusicState(), cachedStatus)
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

        let refreshedSnapshot = await mediaRemoteAdapterStreamSource.refreshPlaybackPositionAsync()
        if let status = SeekCoordinator.trackChangeRejection(
            displayed: latestMediaRemoteSnapshot?.currentTrack,
            refreshed: refreshedSnapshot?.currentTrack
        ) {
            return (currentQishuiMusicState(), status)
        }
        if let refreshedSnapshot, refreshedSnapshot.isVerifiedQishuiSource {
            latestMediaRemoteSnapshot = refreshedSnapshot
        }
        let track: MediaRemoteNowPlayingTrack
        let duration: TimeInterval
        let targetProgress: Double
        let targetElapsed: TimeInterval
        switch SeekCoordinator.qishuiAdmission(
            progress: progress,
            snapshot: latestMediaRemoteSnapshot,
            refreshFailedWhileCached: refreshedSnapshot == nil
                && cachedStatus.availability == .qishuiMediaRemoteCached,
            hasCompetingPlayback: { hasCompetingMusicPlayback(excluding: .qishui) }
        ) {
        case let .rejected(status):
            return (currentQishuiMusicState(), status)
        case let .admitted(admittedTrack, admittedDuration, admittedProgress, admittedElapsed):
            track = admittedTrack
            duration = admittedDuration
            targetProgress = admittedProgress
            targetElapsed = admittedElapsed
        }

        guard authorization.isValid(for: selectedMusicSelection()) else {
            return (selectedMusicState(), SeekCoordinator.Status.sourceSwitchedBeforeSend())
        }

        let seekControlGeneration = controlGeneration
        let didSeek = await mediaRemoteAdapterStreamSource.seek(
            to: targetElapsed,
            coalescingDelayNanoseconds: interaction.coalescingDelayNanoseconds
        )
        guard authorization.isValid(for: selectedMusicSelection()) else {
            return (selectedMusicState(), SeekCoordinator.Status.sourceSwitchedBeforeResult())
        }
        let status = SeekCoordinator.Status.qishuiSent(didSeek)
        guard didSeek else {
            return (currentQishuiMusicState(), status)
        }

        playback.reset(clearTimelineFloor: true)
        var optimisticMusic = currentQishuiMusicState()
        optimisticMusic.progress = targetProgress
        optimisticMusic.elapsedTime = targetElapsed
        optimisticMusic.duration = duration
        cachedStatus = status
        if let processIdentifier = track.sourceProcessIdentifier {
            seeks.scheduleResumeIfPaused(
                identity: .init(processIdentifier: processIdentifier, title: track.title, artist: track.artist),
                generation: seekGeneration,
                isStillValid: { [weak self] in
                    guard let self else { return false }
                    return self.isRealtimeObservationRunning
                        && self.controlGeneration == seekControlGeneration
                        && self.selectedMusicSource() == .qishui
                },
                refresh: { [weak self] in
                    await self?.mediaRemoteAdapterStreamSource.refreshPlaybackPositionAsync()
                },
                startPlayback: { [weak self] processIdentifier in
                    guard let self else { return }
                    let result = await self.pressSemanticControl(.playPause, processIdentifier: processIdentifier)
                    self.recordUsage("seek_start_playback", fields: ["outcome": result.didPress ? "sent" : "unavailable"])
                    self.schedulePlaybackPositionRefresh()
                }
            )
        }
        return (optimisticMusic, status)
    }

    private func seekAppleMusic(
        to progress: Double,
        interaction: MusicSeekInteraction,
        authorization: MusicControlAuthorization
    ) async -> (music: MusicState, status: MusicSourceStatus) {
        guard appleMusicEnabled,
              progress.isFinite,
              (0...1).contains(progress),
              let snapshot = latestAppleMusicSnapshot,
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
        guard appleMusicEnabled,
              AppleMusicAppAdapter.isRunning,
              latestAppleMusicSnapshot?.instance == instance,
              latestAppleMusicSnapshot?.track?.identity == track.identity,
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

        appleMusicControlRequestID &+= 1
        appleMusicControlGeneration &+= 1
        let controlGeneration = appleMusicControlGeneration
        let result = await appleMusicAdapter.perform(MusicControlRequest(
            id: appleMusicControlRequestID,
            target: instance,
            expectedTrack: track.identity,
            action: .seekNormalized(progress)
        ))
        let succeeded = result.disposition == .accepted
        guard appleMusicEnabled,
              controlGeneration == appleMusicControlGeneration else {
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

        scheduleAppleMusicRefresh(force: true)
        var optimisticState = appleMusicState()
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
            if let inFlightRefresh = appleMusicRefreshTask {
                await inFlightRefresh.value
                guard musicSourceSelector.selection == route else {
                    return (selectedMusicState(), selectedMusicStatus())
                }
                return (selectedMusicState(), selectedMusicStatus())
            }
            let snapshot = await appleMusicAdapter.snapshot(refresh: .timeline)
            guard musicSourceSelector.selection == route else {
                return (selectedMusicState(), selectedMusicStatus())
            }
            _ = admitAppleMusicSnapshot(snapshot)
            return (selectedMusicState(), selectedMusicStatus())
        }
        if selectedSource == .neteaseMusic {
            let snapshot = await neteaseMusicAdapter.snapshot(refresh: .timeline)
            if snapshot.instance != nil {
                latestNeteaseMusicSnapshot = snapshot
            }
            return (selectedMusicState(), selectedMusicStatus())
        }
        if (forcePositionRefresh
            || playback.hasPendingOperation
            || mediaRemoteAdapterStreamSource.hasPendingSeekTimeline()),
           !playbackPositionRefreshInFlight {
            playbackPositionRefreshInFlight = true
            _ = await mediaRemoteAdapterStreamSource.refreshPlaybackPositionAsync()
            playbackPositionRefreshInFlight = false
        }
        _ = refreshSourceStatus()
        return (selectedMusicState(), selectedMusicStatus())
    }

    func invalidateQishuiCache() {
        let source = selectedMusicSource()
        if source == .appleMusic {
            scheduleAppleMusicRefresh(force: true)
            return
        }
        if source == .neteaseMusic {
            scheduleNeteaseMusicRefresh(refresh: .metadata)
            return
        }
        qishuiAdapter.invalidateAXCache()
        qishuiSemanticAXController.invalidateCache()
    }

    private func scheduleQishuiControlAvailabilityRefresh(
        cancelPendingRetry: Bool = true
    ) {
        if cancelPendingRetry {
            qishuiControlAvailabilityRetryTask?.cancel()
            qishuiControlAvailabilityRetryTask = nil
        }
        guard !qishuiControlAvailabilityRefreshInFlight else {
            qishuiControlAvailabilityRefreshQueued = true
            return
        }
        qishuiControlAvailabilityGeneration &+= 1
        let generation = qishuiControlAvailabilityGeneration
        guard let processIdentifier = runningQishuiApplication()?.processIdentifier else {
            qishuiControlAvailabilityRefreshQueued = false
            qishuiControlAvailabilityRetryAttempt = 0
            guard latestQishuiControlAvailability != .notRunning else { return }
            latestQishuiControlAvailability = .notRunning
            publishCurrentState()
            return
        }

        qishuiControlAvailabilityRefreshInFlight = true
        lastQishuiControlHealthCheckAt = Date()
        let semanticController = qishuiSemanticAXController
        qishuiWorkQueues.controls.async { [self] in
            let availability = semanticController.controlAvailability(
                processIdentifier: processIdentifier
            )
            Task { @MainActor [weak self] in
                guard let self,
                      generation == self.qishuiControlAvailabilityGeneration else {
                    return
                }
                self.qishuiControlAvailabilityRefreshInFlight = false
                let runningIdentifiers = Set(QishuiProcessLocator.runningApplications()
                    .map(\.processIdentifier))
                switch QishuiControlProbeCompletionPolicy.resolution(
                    requestedProcessIdentifier: processIdentifier,
                    runningProcessIdentifiers: runningIdentifiers
                ) {
                case .accept:
                    break
                case .discardAndRefresh:
                    // A retired probe cannot tear down the replacement's
                    // metadata/lyrics/position stream. Rebind this one probe.
                    self.scheduleQishuiControlAvailabilityRefresh()
                    return
                case .sourceExited:
                    self.markQishuiNotRunning(reason: "control_probe_inventory_empty")
                    return
                }
                if availability != self.latestQishuiControlAvailability {
                    self.latestQishuiControlAvailability = availability
                    self.publishCurrentState()
                }
                if self.qishuiControlAvailabilityRefreshQueued {
                    self.qishuiControlAvailabilityRefreshQueued = false
                    self.scheduleQishuiControlAvailabilityRefresh()
                    return
                }
                if availability == .available {
                    self.qishuiControlAvailabilityRetryAttempt = 0
                } else {
                    self.scheduleQishuiControlAvailabilityRetry()
                }
            }
        }
    }

    private func scheduleQishuiControlAvailabilityRetry() {
        qishuiControlAvailabilityRetryTask?.cancel()
        let attempt = qishuiControlAvailabilityRetryAttempt
        let delay = min(3.0 * pow(2.0, Double(attempt)), 12.0)
        qishuiControlAvailabilityRetryAttempt = min(attempt + 1, 2)
        qishuiControlAvailabilityRetryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.qishuiControlAvailabilityRetryTask = nil
            self.scheduleQishuiControlAvailabilityRefresh(cancelPendingRetry: false)
        }
    }

    private func cancelQishuiControlAvailabilityScheduling() {
        lastQishuiControlHealthCheckAt = nil
        qishuiControlAvailabilityGeneration &+= 1
        qishuiControlAvailabilityRefreshInFlight = false
        qishuiControlAvailabilityRefreshQueued = false
        qishuiControlAvailabilityRetryAttempt = 0
        qishuiControlAvailabilityRetryTask?.cancel()
        qishuiControlAvailabilityRetryTask = nil
    }

    private func refreshFromRealtimeSignal(onUpdate: @escaping (MusicState, MusicSourceStatus) -> Void) {
        guard !realtimeRefreshInFlight else {
            realtimeRefreshQueued = true
            return
        }

        realtimeRefreshInFlight = true
        _ = refreshSourceStatus()
        qishuiLyrics.scheduleRefresh()
        if latestMediaRemoteSnapshot?.isVerifiedQishuiSource == true,
           latestMediaRemoteSnapshot?.currentTrack != nil,
           latestQishuiControlAvailability != .available {
            scheduleQishuiControlAvailabilityRefresh()
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
        _ = promptForPermission
        guard qishuiAdapter.isRunning() else {
            markQishuiNotRunning()
            return cachedStatus
        }

        let canRefreshAdapterInBackground = mediaRemoteAdapterStreamSource.hasAdapterResources()
        if allowSynchronousRefresh, canRefreshAdapterInBackground {
            schedulePlaybackPositionRefresh()
        }
        let adapterSnapshot = mediaRemoteAdapterStreamSource.snapshot()

        if let adapterSnapshot,
           let track = adapterSnapshot.currentTrack,
           QishuiPlaybackInstancePolicy.acceptsSnapshot(
               snapshotProcessIdentifier: track.sourceProcessIdentifier,
               runningProcessIdentifiers: Set(QishuiProcessLocator.runningApplications().map(\.processIdentifier))
           ) {
            latestMediaRemoteSnapshot = adapterSnapshot
            lastSourceRefreshAt = adapterSnapshot.checkedAt
            scheduleQishuiTransitionIdentityReconciliation()
            let hasVerifiedClientState = mediaRemoteAdapterStreamSource.hasVerifiedQishuiClientState()
            if hasVerifiedClientState {
                if !playback.hasPendingOperation {
                    playback.updateCachedOverride(from: track, checkedAt: adapterSnapshot.checkedAt)
                }
                updateMediaRemotePlaybackConfirmation(snapshot: adapterSnapshot)
            } else if playback.shouldRefreshCachedOverride {
                playback.noteCachedOverrideRefreshAttempt()
                scheduleQishuiIdentityRefresh(force: true)
            }
            cachedStatus = MusicSourceStatus(
                sourceName: "汽水实时适配器",
                availability: hasVerifiedClientState ? .qishuiMediaRemoteSynced : .qishuiMediaRemoteCached,
                headline: hasVerifiedClientState ? "已接入汽水实时播放" : "保持汽水音乐显示",
                detail: "\(track.title) - \(track.artist)。来源：\(track.sourceName)。\(adapterSnapshot.diagnostic)",
                checkedAt: adapterSnapshot.checkedAt
            )
            return cachedStatus
        }

        guard allowSynchronousRefresh else {
            lastSourceRefreshAt = Date()
            return cachedStatus
        }

        // Startup and explicit position refreshes must not run a helper process on the UI actor.
        // The stream and the one in-flight detached refresh will publish the authoritative state.
        if canRefreshAdapterInBackground,
           adapterSnapshot == nil || adapterSnapshot?.isAvailable == true {
            lastSourceRefreshAt = Date()
            return cachedStatus
        }

        scheduleQishuiIdentityRefresh(force: true)
        return cachedStatus
    }

    private func applyQishuiDirectSnapshot(
        _ snapshot: QishuiDirectSnapshot
    ) -> MusicSourceStatus {
        let runningIdentifiers = Set(QishuiProcessLocator.runningApplications().map(\.processIdentifier))
        if snapshot.isRunning || !runningIdentifiers.isEmpty {
            guard QishuiPlaybackInstancePolicy.acceptsSnapshot(
                snapshotProcessIdentifier: snapshot.processIdentifier,
                runningProcessIdentifiers: runningIdentifiers
            ) else { return cachedStatus }
        }
        let directFingerprint = snapshot.currentTrack.map {
            MusicUsageTrackFingerprint.make(source: "qishui", title: $0.title, artist: $0.artist)
        } ?? "none"
        usage.recordDirectIdentityIfChanged(
            fingerprint: directFingerprint,
            hasTrack: snapshot.currentTrack != nil,
            hasProgress: snapshot.currentTrack?.progress != nil
        )
        latestQishuiSnapshot = snapshot
        applyQishuiWindowAvailability(snapshot.windowAvailability)
        lastSourceRefreshAt = snapshot.checkedAt

        guard snapshot.isRunning else {
            markQishuiNotRunning(checkedAt: snapshot.checkedAt, reason: "metadata_inventory")
            return cachedStatus
        }

        if let track = snapshot.currentTrack {
            qishuiInference.update(track: track, checkedAt: snapshot.checkedAt)
            if !playback.hasPendingOperation
                || updatePendingPlaybackConfirmation(checkedAt: snapshot.checkedAt) {
                playback.updateCachedOverride(
                    fromDirect: track,
                    inferredIsPlaying: qishuiInference.inferredIsPlaying,
                    mediaSnapshot: latestMediaRemoteSnapshot,
                    checkedAt: snapshot.checkedAt
                )
            }
            cachedStatus = MusicSourceStatus(
                sourceName: "汽水直接适配",
                availability: .qishuiDetectedAXLimited,
                headline: "已读取汽水实时播放",
                detail: "\(track.title) - \(track.artist)。来源：\(track.sourceName)。播放态：\(qishuiInference.label(for: track))。",
                checkedAt: snapshot.checkedAt
            )
            return cachedStatus
        }

        let queueDetail: String
        if snapshot.queueCacheTrackCount > 0 {
            let examples = snapshot.queueExamples.prefix(2).joined(separator: "；")
            queueDetail = "已读到队列缓存 \(snapshot.queueCacheTrackCount) 首\(examples.isEmpty ? "" : "，例如：\(examples)")。"
        } else {
            queueDetail = "暂未在本地状态文件中读到可用队列。"
        }

        cachedStatus = MusicSourceStatus(
            sourceName: "汽水直接适配",
            availability: .qishuiDetectedAXLimited,
            headline: "汽水音乐已运行",
            detail: "PID \(snapshot.processIdentifier.map(String.init) ?? "unknown")。\(queueDetail)\(snapshot.diagnostic)",
            checkedAt: snapshot.checkedAt
        )
        return cachedStatus
    }

    private func refreshForegroundQishuiState() async {
        guard foregroundMusicSource == .qishui,
              let processIdentifier = QishuiProcessLocator.application()?.processIdentifier else { return }
        _ = await refreshQishuiAXMetadata(processIdentifier: processIdentifier)
    }

    private func scheduleQishuiLifecycleMetadataRefresh() {
        qishuiLifecycleMetadataTask?.cancel()
        guard let processIdentifier = QishuiProcessLocator.application()?.processIdentifier else {
            qishuiLifecycleMetadataTask = nil
            return
        }
        qishuiLifecycleMetadataTask = Task { @MainActor [weak self] in
            // Only bootstrap a new observation/instance; no periodic metadata polling.
            for delay: UInt64 in [0, 350_000_000, 400_000_000, 500_000_000,
                                   650_000_000, 900_000_000, 1_200_000_000] {
                if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
                guard !Task.isCancelled, let self, self.isRealtimeObservationRunning,
                      QishuiProcessLocator.isRunning(processIdentifier: processIdentifier) else { return }
                if await self.refreshQishuiAXMetadata(processIdentifier: processIdentifier) { return }
                // A newly launched Electron process can report zero windows before
                // its main window is created. Exhaust the bounded read-only retries
                // in that case; observing a closed window never reveals it.
                if self.latestQishuiSnapshot?.windowAvailability == .accessibilityRequired { return }
            }
        }
    }

    private func refreshQishuiAXMetadata(processIdentifier: pid_t) async -> Bool {
        _ = refreshSourceStatus()
        let controller = qishuiSemanticAXController
        // AX exposes recommendation cards alongside the playback card. When
        // MediaRemote already has a verified Qishui identity, constrain the
        // AX scan to that identity so a recommendation cannot replace the
        // actual playing song.
        let expectedTitle = latestMediaRemoteSnapshot?.currentTrack?.title
        let expectedArtist = latestMediaRemoteSnapshot?.currentTrack?.artist
        let requestedIdentity = qishuiMediaIdentity()
        let requestedControlGeneration = controlGeneration
        let requestedSeekGeneration = seeks.generation
        let queues = qishuiWorkQueues
        let snapshot = await withCheckedContinuation { continuation in
            queues.metadata.async {
                _ = controller.prepareAccessibilityTree()
                continuation.resume(returning: queues.metadataSnapshot(
                    preferredTitle: expectedTitle,
                    preferredArtist: expectedArtist
                ))
            }
        }
        guard !Task.isCancelled, isRealtimeObservationRunning,
              requestedControlGeneration == controlGeneration,
              seeks.isCurrent(requestedSeekGeneration),
              snapshot.processIdentifier == processIdentifier,
              QishuiProcessLocator.isRunning(processIdentifier: processIdentifier),
              QishuiIdentityRefreshPolicy.accepts(
                  requested: requestedIdentity, current: qishuiMediaIdentity(),
                  result: snapshot.currentTrack.map {
                      .init(processIdentifier: processIdentifier, title: $0.title, artist: $0.artist)
                  }
              ) else { return false }
        _ = applyQishuiDirectSnapshot(snapshot)
        publishCurrentState()
        return snapshot.currentTrack != nil
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
                    self.markQishuiNotRunning(reason: "lifecycle_termination")
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
                    self.appleMusicRefreshGeneration &+= 1
                    self.appleMusicRefreshTask?.cancel()
                    self.appleMusicRefreshTask = nil
                    self.appleMusicRefreshQueued = false
                    self.cancelAppleMusicTransientRetry(resetAttempt: true)
                    self.clearAppleMusicPlaybackControlExpectation()
                    self.latestAppleMusicSnapshot = nil
                    self.lastAppleMusicRefreshCompletedAt = Date()
                    self.appleMusicConsecutiveRefreshFailures = 0
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
                    self.controlGeneration += 1
                    self.cancelQishuiControlAvailabilityScheduling()
                    self.latestQishuiControlAvailability = .unknown
                    self.clearQishuiPlaybackState()
                    self.lastSourceRefreshAt = nil
                    self.qishuiAdapter.invalidateAXCache()
                    self.qishuiSemanticAXController.invalidateCache()
                    self.mediaRemoteAdapterStreamSource.rebindAfterQishuiRelaunch()
                    self.scheduleQishuiControlAvailabilityRefresh()
                    self.scheduleQishuiLifecycleMetadataRefresh()
                case .neteaseMusic:
                    self.neteaseMusicRefreshGeneration &+= 1
                    self.neteaseMusicRefreshTask?.cancel()
                    self.neteaseMusicRefreshTask = nil
                    self.lastNeteaseMusicRefreshStartedAt = nil
                case .appleMusic:
                    self.cancelAppleMusicTransientRetry(resetAttempt: true)
                    self.lastAppleMusicRefreshCompletedAt = nil
                    self.appleMusicConsecutiveRefreshFailures = 0
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
                switch source {
                case .qishui:
                    self.scheduleQishuiControlAvailabilityRefresh()
                    await self.refreshForegroundQishuiState()
                    return
                case .neteaseMusic:
                    self.neteaseMusicAdapter.rebindObservationToRunningInstance()
                    self.scheduleNeteaseMusicRefresh(refresh: .metadata, retryAttempt: 0)
                case .appleMusic:
                    guard self.appleMusicEnabled else { return }
                    self.scheduleAppleMusicRefresh(force: true)
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
                if source == .appleMusic, !self.appleMusicEnabled {
                    source = nil
                }
                guard source != self.foregroundMusicSource else { return }
                self.foregroundMusicSource = source
                self.publishCurrentState()
                switch source {
                case .qishui:
                    self.scheduleQishuiControlAvailabilityRefresh()
                    await self.refreshForegroundQishuiState()
                    return
                case .neteaseMusic:
                    self.scheduleNeteaseMusicRefresh(refresh: .metadata, retryAttempt: 0)
                case .appleMusic:
                    self.scheduleAppleMusicRefresh(force: true)
                case nil:
                    self.schedulePlaybackPositionRefresh()
                    self.scheduleAppleMusicRefresh(force: true)
                }
            }
        }
        qishuiLifecycleObservers = [
            terminatedObserver,
            launchedObserver,
            activatedObserver
        ]
    }

    private func stopQishuiLifecycleObservation() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        for observer in qishuiLifecycleObservers {
            notificationCenter.removeObserver(observer)
        }
        qishuiLifecycleObservers.removeAll()
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

    private func markQishuiNotRunning(checkedAt: Date = Date(), reason: String = "inventory") {
        recordUsage("source_unavailable", fields: [
            "source": "qishui", "reason": reason,
            "had_media": latestMediaRemoteSnapshot?.currentTrack == nil ? "0" : "1",
            "had_direct": latestQishuiSnapshot?.currentTrack == nil ? "0" : "1"
        ])
        controlGeneration += 1
        cancelQishuiControlAvailabilityScheduling()
        clearQishuiPlaybackState()
        latestQishuiControlAvailability = .notRunning
        lastSourceRefreshAt = checkedAt
        qishuiAdapter.invalidateAXCache()
        qishuiSemanticAXController.invalidateCache()
        mediaRemoteAdapterStreamSource.invalidateQishuiSession()
        cachedStatus = MusicSourceStatus(
            sourceName: "汽水音乐",
            availability: .qishuiNotRunning,
            headline: "未检测到汽水音乐",
            detail: "当前不显示播放数据；重新打开汽水音乐后，顶屿会在检测到可信状态时恢复显示。",
            checkedAt: checkedAt
        )
    }

    private func clearQishuiPlaybackState() {
        lastQishuiTransitionIdentityRequested = nil
        qishuiLyrics.invalidate()
        qishuiLifecycleMetadataTask?.cancel()
        qishuiLifecycleMetadataTask = nil
        latestMediaRemoteSnapshot = nil
        latestQishuiSnapshot = nil
        lastPlaybackPositionRefreshAt = nil
        lastTrackControlStartedAt = nil
        playback.reset(clearTimelineFloor: true)
        qishuiInference.reset()
    }

    private func applyQishuiWindowAvailability(
        _ windowAvailability: QishuiControlAvailability
    ) {
        switch windowAvailability {
        case .available:
            break
        case .windowClosed,
             .controlTreeUnavailable,
             .accessibilityRequired,
             .notRunning,
             .unknown:
            latestQishuiControlAvailability = windowAvailability
        }
    }

    private func refreshSourceStatusIfNeeded() -> MusicSourceStatus? {
        let now = Date()
        if let lastSourceRefreshAt,
           now.timeIntervalSince(lastSourceRefreshAt) < automaticRefreshInterval {
            return nil
        }
        return refreshSourceStatus()
    }

    private func shouldRefreshPlaybackPosition(_ state: MusicState) -> Bool {
        guard state.isPlaying,
              state.duration != nil,
              state.elapsedTime != nil else { return false }

        let now = Date()
        guard lastPlaybackPositionRefreshAt.map({ now.timeIntervalSince($0) >= playbackPositionRefreshInterval }) ?? true else {
            return false
        }
        return true
    }

    private func shouldRefreshCachedPlaybackState() -> Bool {
        guard cachedStatus.availability == .qishuiMediaRemoteCached else { return false }
        return playback.cachedOverrideRefreshIsDue
    }

    private func refreshPlaybackPositionStatus() -> MusicSourceStatus {
        lastPlaybackPositionRefreshAt = Date()
        schedulePlaybackPositionRefresh()
        return refreshSourceStatus()
    }

    private func schedulePlaybackPositionRefresh() {
        guard !playbackPositionRefreshInFlight else { return }
        playbackPositionRefreshInFlight = true
        lastPlaybackPositionRefreshAt = Date()
        Task { [weak self] in
            guard let self else { return }
            _ = await self.mediaRemoteAdapterStreamSource.refreshPlaybackPositionAsync()
            _ = self.refreshSourceStatus()
            self.playbackPositionRefreshInFlight = false
            self.publishCurrentState()
        }
    }

    private func startAppleMusicObservation() {
        cancelAppleMusicTransientRetry(resetAttempt: true)
        appleMusicAdapter.start { [weak self] invalidation in
            switch invalidation {
            case .sourceChanged:
                self?.scheduleAppleMusicRefresh(force: true)
            case .cachedDataChanged:
                self?.publishCachedAppleMusicSnapshot()
            }
        }
        scheduleAppleMusicRefresh(force: true)
    }

    private func stopAppleMusicObservation() {
        appleMusicControlGeneration &+= 1
        appleMusicRefreshGeneration &+= 1
        appleMusicRefreshTask?.cancel()
        appleMusicRefreshTask = nil
        appleMusicRefreshQueued = false
        cancelAppleMusicTransientRetry(resetAttempt: true)
        lastAppleMusicRefreshCompletedAt = nil
        lastAppleMusicControlAt = nil
        clearAppleMusicPlaybackControlExpectation()
        appleMusicConsecutiveRefreshFailures = 0
        appleMusicAdapter.stop()
        latestAppleMusicSnapshot = nil
    }

    private func scheduleAppleMusicRefresh(force: Bool) {
        let now = Date()
        guard appleMusicEnabled, AppleMusicAppAdapter.isRunning else {
            appleMusicRefreshGeneration &+= 1
            appleMusicRefreshTask?.cancel()
            appleMusicRefreshTask = nil
            appleMusicRefreshQueued = false
            cancelAppleMusicTransientRetry(resetAttempt: true)
            appleMusicConsecutiveRefreshFailures = 0
            clearAppleMusicPlaybackControlExpectation()
            if latestAppleMusicSnapshot != nil {
                latestAppleMusicSnapshot = nil
                lastAppleMusicRefreshCompletedAt = now
                publishCurrentState()
            }
            return
        }

        if force {
            appleMusicTransientRetryTask?.cancel()
            appleMusicTransientRetryTask = nil
        }

        let isSelected = musicSourceSelector.selection.source == .appleMusic
        let isPlaying = latestAppleMusicSnapshot?.playbackState == .playing
        let recentlyControlled = lastAppleMusicControlAt.map {
            now.timeIntervalSince($0) < 2
        } ?? false
        let interval = AppleMusicRefreshPolicy.interval(
            isSelected: isSelected,
            isPlaying: isPlaying,
            recentlyControlled: recentlyControlled,
            consecutiveFailures: appleMusicConsecutiveRefreshFailures
        )
        if !force,
           let lastAppleMusicRefreshCompletedAt,
           now.timeIntervalSince(lastAppleMusicRefreshCompletedAt) < interval {
            return
        }
        if appleMusicRefreshTask != nil {
            if force {
                appleMusicRefreshQueued = true
            }
            return
        }

        appleMusicRefreshGeneration &+= 1
        let generation = appleMusicRefreshGeneration
        appleMusicRefreshTask = Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.appleMusicAdapter.snapshot(refresh: .metadata)
            guard !Task.isCancelled,
                  generation == self.appleMusicRefreshGeneration else { return }
            let admission = self.admitAppleMusicSnapshot(snapshot)
            if case .retryScheduled = admission {
                self.lastAppleMusicRefreshCompletedAt = Date()
                self.appleMusicConsecutiveRefreshFailures = min(
                    self.appleMusicConsecutiveRefreshFailures + 1,
                    3
                )
                self.appleMusicRefreshTask = nil
                self.appleMusicRefreshQueued = false
                return
            }
            self.lastAppleMusicRefreshCompletedAt = Date()
            if case .ready = snapshot.availability {
                self.appleMusicConsecutiveRefreshFailures = 0
            } else {
                self.appleMusicConsecutiveRefreshFailures = min(
                    self.appleMusicConsecutiveRefreshFailures + 1,
                    3
                )
            }
            self.appleMusicRefreshTask = nil
            self.publishCurrentState()
            if self.appleMusicRefreshQueued {
                self.appleMusicRefreshQueued = false
                self.scheduleAppleMusicRefresh(force: true)
            }
        }
    }

    private func scheduleAppleMusicTransientRetry(after delay: TimeInterval) {
        appleMusicTransientRetryTask?.cancel()
        appleMusicTransientRetryAttempt += 1
        let generation = appleMusicRefreshGeneration
        appleMusicTransientRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled,
                  let self,
                  generation == self.appleMusicRefreshGeneration else { return }
            self.appleMusicTransientRetryTask = nil
            self.scheduleAppleMusicRefresh(force: true)
        }
    }

    private func cancelAppleMusicTransientRetry(resetAttempt: Bool) {
        appleMusicTransientRetryTask?.cancel()
        appleMusicTransientRetryTask = nil
        if resetAttempt {
            appleMusicTransientRetryAttempt = 0
        }
    }

    private enum AppleMusicSnapshotAdmissionResult {
        case applied
        case rejected
        case retryScheduled
    }

    @discardableResult
    private func admitAppleMusicSnapshot(
        _ snapshot: MusicAppSnapshot
    ) -> AppleMusicSnapshotAdmissionResult {
        switch AppleMusicSnapshotAdmissionPolicy.decision(
            current: latestAppleMusicSnapshot,
            candidate: snapshot,
            attempt: appleMusicTransientRetryAttempt
        ) {
        case .rejectOlder:
            appleMusicTransitionTimeline.record(
                .snapshotRejected,
                detail: "reason=older checkedAt=\(snapshot.checkedAt.ISO8601Format())"
            )
            return .rejected
        case let .retry(after: retryDelay):
            appleMusicTransitionTimeline.record(
                .snapshotRejected,
                detail: "reason=transient-snapshot retryMs=\(Int(retryDelay * 1_000))"
            )
            scheduleAppleMusicTransientRetry(after: retryDelay)
            return .retryScheduled
        case .accept:
            break
        }
        if let expectation = pendingAppleMusicPlaybackControl {
            let now = Date()
            switch expectation.resolution(for: snapshot, at: now) {
            case .reject:
                appleMusicTransitionTimeline.record(
                    .snapshotRejected,
                    detail: "reason=playback-expectation track=\(snapshot.track?.title ?? "")"
                )
                return .rejected
            case .acceptAndClear:
                let matchesExpectedTrack = snapshot.instance == expectation.instance
                    && snapshot.track?.identity == expectation.trackIdentity
                if matchesExpectedTrack,
                   snapshot.playbackState == expectation.targetState {
                    recordUsage("playback_confirmed", fields: [
                        "evidence": "apple_event",
                        "latency_ms": String(max(
                            Int(now.timeIntervalSince(expectation.issuedAt) * 1_000),
                            0
                        )),
                        "source": "apple-music",
                        "target_playback": Self.playbackStateLabel(
                            expectation.targetState
                        )
                    ])
                } else if matchesExpectedTrack,
                          now.timeIntervalSince(expectation.issuedAt)
                            >= AppleMusicPlaybackControlExpectation
                                .staleSnapshotGraceInterval {
                    recordUsage("playback_confirmation_timeout", fields: [
                        "latency_ms": String(max(
                            Int(now.timeIntervalSince(expectation.issuedAt) * 1_000),
                            0
                        )),
                        "source": "apple-music",
                        "target_playback": Self.playbackStateLabel(
                            expectation.targetState
                        )
                    ])
                }
                clearAppleMusicPlaybackControlExpectation()
            }
        }
        cancelAppleMusicTransientRetry(resetAttempt: true)
        latestAppleMusicSnapshot = snapshot
        appleMusicTransitionTimeline.record(
            .snapshotApplied,
            detail: "source=authoritative track=\(snapshot.track?.title ?? "") artist=\(snapshot.track?.artist ?? "") artworkBytes=\(snapshot.track?.artworkData?.count ?? 0) revision=\(snapshot.revision)"
        )
        return .applied
    }

    private func beginAppleMusicPlaybackControlExpectation(
        _ expectation: AppleMusicPlaybackControlExpectation,
        generation: UInt64
    ) {
        clearAppleMusicPlaybackControlExpectation()
        pendingAppleMusicPlaybackControl = expectation
        appleMusicPlaybackExpectationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(
                AppleMusicPlaybackControlExpectation.staleSnapshotGraceInterval
                    * 1_000_000_000
            ))
            guard !Task.isCancelled,
                  let self,
                  appleMusicControlGeneration == generation,
                  pendingAppleMusicPlaybackControl == expectation else { return }
            self.recordUsage("playback_confirmation_timeout", fields: [
                "latency_ms": String(max(
                    Int(Date().timeIntervalSince(expectation.issuedAt) * 1_000),
                    0
                )),
                "source": "apple-music",
                "target_playback": Self.playbackStateLabel(expectation.targetState)
            ])
            pendingAppleMusicPlaybackControl = nil
            appleMusicPlaybackExpectationTask = nil
            scheduleAppleMusicRefresh(force: true)
        }
    }

    private func clearAppleMusicPlaybackControlExpectation() {
        appleMusicPlaybackExpectationTask?.cancel()
        appleMusicPlaybackExpectationTask = nil
        pendingAppleMusicPlaybackControl = nil
    }

    private func publishCachedAppleMusicSnapshot() {
        guard appleMusicEnabled else { return }
        let generation = appleMusicRefreshGeneration
        Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.appleMusicAdapter.snapshot(refresh: .cached)
            guard !Task.isCancelled,
                  self.appleMusicEnabled,
                  generation == self.appleMusicRefreshGeneration else { return }
            self.applyCachedAppleMusicArtwork(snapshot)
            self.publishCurrentState()
        }
    }

    private func applyCachedAppleMusicArtwork(_ snapshot: MusicAppSnapshot) {
        guard let artworkData = snapshot.track?.artworkData else { return }
        guard let current = latestAppleMusicSnapshot,
              current.instance == snapshot.instance,
              let currentTrack = current.track,
              currentTrack.identity == snapshot.track?.identity else {
            _ = admitAppleMusicSnapshot(snapshot)
            return
        }
        let updatedTrack = MusicTrackSnapshot(
            identity: currentTrack.identity,
            title: currentTrack.title,
            artist: currentTrack.artist,
            album: currentTrack.album,
            artworkData: artworkData,
            lyrics: currentTrack.lyrics
        )
        latestAppleMusicSnapshot = MusicAppSnapshot(
            descriptor: current.descriptor,
            instance: current.instance,
            availability: current.availability,
            track: updatedTrack,
            playbackState: current.playbackState,
            timeline: current.timeline,
            controls: current.controls,
            revision: max(current.revision, snapshot.revision),
            provenance: current.provenance,
            checkedAt: current.checkedAt,
            diagnostic: snapshot.diagnostic
        )
        appleMusicTransitionTimeline.record(
            .snapshotApplied,
            detail: "source=cached-artwork track=\(currentTrack.title) artist=\(currentTrack.artist ?? "") artworkBytes=\(artworkData.count) revision=\(max(current.revision, snapshot.revision))"
        )
    }

    private func appleMusicSnapshot(
        togglingPlaybackIn snapshot: MusicAppSnapshot,
        at now: Date
    ) -> MusicAppSnapshot? {
        let state: MusicPlaybackState
        switch snapshot.playbackState {
        case .playing:
            state = .paused
        case .paused:
            state = .playing
        case .stopped, .unknown:
            return nil
        }
        return appleMusicSnapshot(
            snapshot,
            settingPlaybackState: state,
            at: now,
            diagnostic: "已立即更新本地播放状态，等待 Apple Music 确认。"
        )
    }

    private func appleMusicSnapshot(
        _ snapshot: MusicAppSnapshot,
        settingPlaybackState playbackState: MusicPlaybackState,
        at now: Date,
        diagnostic: String
    ) -> MusicAppSnapshot? {
        guard playbackState == .playing || playbackState == .paused else {
            return nil
        }
        let timeline = snapshot.timeline.map { timeline in
            let projectedElapsed = timeline.elapsedTime
                + max(now.timeIntervalSince(timeline.observedAt), 0)
                    * timeline.playbackRate
            return MusicTimelineSnapshot(
                elapsedTime: min(max(projectedElapsed, 0), timeline.duration),
                duration: timeline.duration,
                playbackRate: playbackState == .playing ? 1 : 0,
                observedAt: now
            )
        }
        return MusicAppSnapshot(
            descriptor: snapshot.descriptor,
            instance: snapshot.instance,
            availability: snapshot.availability,
            track: snapshot.track,
            playbackState: playbackState,
            timeline: timeline,
            controls: snapshot.controls,
            revision: snapshot.revision &+ 1,
            provenance: snapshot.provenance,
            checkedAt: now,
            diagnostic: diagnostic
        )
    }

    private func selectedMusicSelection() -> MusicSourceSelection {
        reconcileForegroundMusicSource()
        let previousSelection = musicSourceSelector.selection
        let selection = musicSourceSelector.update(
            qishui: qishuiSourceCandidate(),
            neteaseMusic: neteaseMusicSourceCandidate(),
            appleMusic: appleMusicSourceCandidate(),
            foregroundSource: foregroundMusicSource
        )
        if selection.generation != previousSelection.generation {
            mediaRemoteAdapterStreamSource.invalidatePendingSeekRequests()
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

    nonisolated private static func commandLabel(_ command: MusicControlCommand) -> String {
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
            mediaTrack: latestMediaRemoteSnapshot?.currentTrack.map { ($0.title, $0.artist) },
            directTrack: latestQishuiSnapshot?.currentTrack.map { ($0.title, $0.artist) }
        )
        if didChangeTrack,
           sourceID == .qishui,
           latestQishuiControlAvailability.allowsCachePrewarmAfterTrackChange {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                guard let self,
                      self.isRealtimeObservationRunning,
                      self.latestQishuiControlAvailability
                        .allowsCachePrewarmAfterTrackChange else { return }
                self.scheduleQishuiControlAvailabilityRefresh()
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

    nonisolated private static func playbackStateLabel(
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

    private func qishuiSourceCandidate() -> MusicSourceCandidate {
        let mediaRemoteTrack = latestMediaRemoteSnapshot?.currentTrack
        let directTrack = latestQishuiSnapshot?.currentTrack
        let hasTrack = mediaRemoteTrack != nil || directTrack != nil
        let isPlaying = mediaRemoteTrack?.isPlaying
            ?? directTrack?.isPlaying
            ?? qishuiInference.inferredIsPlaying
        let playback: MusicSourcePlaybackLevel
        if isPlaying == true {
            playback = .playing
        } else if hasTrack {
            playback = .paused
        } else {
            playback = .unknown
        }
        let isRunning = qishuiAdapter.isRunning()
        return MusicSourceCandidate(
            source: .qishui,
            isAvailable: isRunning
                && (foregroundMusicSource == .qishui
                    || cachedStatus.availability != .qishuiNotRunning),
            hasTrack: hasTrack,
            playback: playback,
            isCached: cachedStatus.availability == .qishuiMediaRemoteCached
        )
    }

    private func hasCompetingMusicPlayback(
        excluding source: MusicSourceID
    ) -> Bool {
        MusicSourceAdmissionPolicy.hasCompetingPlayback(
            excluding: source,
            candidates: [
                qishuiSourceCandidate(),
                neteaseMusicSourceCandidate(),
                appleMusicSourceCandidate()
            ]
        )
    }

    private func appleMusicSourceCandidate() -> MusicSourceCandidate {
        let runningProcessIdentifier = NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicAdapterRegistry.appleMusic.descriptor.bundleIdentifier
        ).first?.processIdentifier
        guard appleMusicEnabled else {
            return MusicSourceCandidate(
                source: .appleMusic,
                isAvailable: false,
                hasTrack: false,
                playback: .unknown,
                isCached: false
            )
        }
        guard let snapshot = latestAppleMusicSnapshot else {
            return MusicSourceCandidate(
                source: .appleMusic,
                isAvailable: AppleMusicAppAdapter.isRunning,
                hasTrack: false,
                playback: .unknown,
                isCached: false
            )
        }
        let snapshotMatchesRunningInstance = AppleMusicSourceAvailabilityPolicy
            .snapshotMatchesRunningInstance(
                runningProcessIdentifier: runningProcessIdentifier,
                snapshotProcessIdentifier: snapshot.instance?.processIdentifier
            )
        let isReady: Bool
        if case .ready = snapshot.availability {
            isReady = true
        } else {
            isReady = false
        }
        let playback: MusicSourcePlaybackLevel
        switch snapshotMatchesRunningInstance ? snapshot.playbackState : .unknown {
        case .playing:
            playback = .playing
        case .paused:
            playback = .paused
        case .stopped, .unknown:
            playback = .unknown
        }
        return MusicSourceCandidate(
            source: .appleMusic,
            isAvailable: AppleMusicSourceAvailabilityPolicy.isAvailable(
                isEnabled: appleMusicEnabled,
                runningProcessIdentifier: runningProcessIdentifier,
                snapshotProcessIdentifier: snapshot.instance?.processIdentifier,
                snapshotIsReady: isReady,
                isForeground: foregroundMusicSource == .appleMusic
            ),
            hasTrack: snapshotMatchesRunningInstance && snapshot.track != nil,
            playback: playback,
            isCached: false
        )
    }

    private func reconcileForegroundMusicSource() {
        var source = Self.musicSourceID(
            for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        if source == .appleMusic, !appleMusicEnabled {
            source = nil
        }
        guard source != foregroundMusicSource else { return }

        foregroundMusicSource = source
        switch source {
        case .qishui:
            Task { [weak self] in
                await self?.refreshForegroundQishuiState()
            }
        case .neteaseMusic:
            scheduleNeteaseMusicRefresh(refresh: .metadata)
        case .appleMusic:
            scheduleAppleMusicRefresh(force: true)
        case nil:
            schedulePlaybackPositionRefresh()
            scheduleAppleMusicRefresh(force: true)
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
            return appleMusicState()
        case .neteaseMusic:
            return neteaseMusicState()
        case .qishui, nil:
            return currentQishuiMusicState()
        }
    }

    private func musicStatus(for source: MusicSourceID?) -> MusicSourceStatus {
        if source == .neteaseMusic {
            return neteaseMusicStatus()
        }
        guard source == .appleMusic else {
            return cachedStatus
        }
        guard let snapshot = appleMusicSnapshotForRunningInstance() else {
            return MusicSourceStatus(
                sourceName: "Apple Music",
                availability: .appleMusicSynced,
                headline: "等待 Apple Music 同步",
                detail: "已检测到 Apple Music，正在读取当前进程的歌曲状态。",
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
            sourceName: "Apple Music",
            availability: .appleMusicSynced,
            headline: "已接入 Apple Music",
            detail: "\(trackText)。通过 PID 定向 Apple Event 读取，不使用系统当前媒体。",
            checkedAt: snapshot.checkedAt
        )
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

    private func appleMusicState() -> MusicState {
        guard let snapshot = appleMusicSnapshotForRunningInstance(),
              let track = snapshot.track else {
            return appleMusicIdleState()
        }
        let elapsedTime: TimeInterval?
        let duration: TimeInterval?
        let progress: Double
        if let timeline = snapshot.timeline {
            duration = timeline.duration
            let projectedElapsed = timeline.elapsedTime
                + max(Date().timeIntervalSince(timeline.observedAt), 0) * timeline.playbackRate
            let clampedElapsed = min(max(projectedElapsed, 0), timeline.duration)
            elapsedTime = clampedElapsed
            progress = timeline.duration > 0 ? clampedElapsed / timeline.duration : 0
        } else {
            duration = nil
            elapsedTime = nil
            progress = 0
        }
        return MusicState(
            track: MusicTrack(
                title: track.title,
                artist: track.artist ?? "Apple Music",
                palette: [
                    Color(red: 0.96, green: 0.20, blue: 0.36),
                    Color(red: 0.18, green: 0.06, blue: 0.10)
                ],
                lyrics: track.lyrics,
                hasArtwork: track.artworkData != nil,
                artworkData: track.artworkData,
                artworkURL: nil,
                sourceBundleIdentifier: MusicAdapterRegistry.appleMusic.descriptor.bundleIdentifier
            ),
            isPlaying: snapshot.playbackState == .playing,
            progress: min(max(progress, 0), 1),
            lyricIndex: 0,
            elapsedTime: elapsedTime,
            duration: duration,
            canSeek: snapshot.controls.supports(.absoluteSeek),
            isPlaybackPending: false,
            canPlayPause: snapshot.controls.supports(.playPause),
            canPreviousTrack: snapshot.controls.supports(.previousTrack),
            canNextTrack: snapshot.controls.supports(.nextTrack),
            controlUnavailableReason: "Apple Music 当前没有提供这个控制。",
            hasCurrentTrack: true
        )
    }

    private func appleMusicIdleState() -> MusicState {
        MusicState(
            track: MusicTrack(
                title: "Apple Music",
                artist: "等待播放",
                palette: [
                    Color(red: 0.96, green: 0.20, blue: 0.36),
                    Color(red: 0.18, green: 0.06, blue: 0.10)
                ],
                lyrics: [],
                hasArtwork: false,
                artworkData: nil,
                artworkURL: nil,
                sourceBundleIdentifier: MusicAdapterRegistry.appleMusic.descriptor.bundleIdentifier
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
            controlUnavailableReason: "Apple Music 当前没有可控制的歌曲。",
            hasCurrentTrack: false
        )
    }

    private func appleMusicSnapshotForRunningInstance() -> MusicAppSnapshot? {
        let runningProcessIdentifier = NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicAdapterRegistry.appleMusic.descriptor.bundleIdentifier
        ).first?.processIdentifier
        guard let snapshot = latestAppleMusicSnapshot,
              AppleMusicSourceAvailabilityPolicy.snapshotMatchesRunningInstance(
                runningProcessIdentifier: runningProcessIdentifier,
                snapshotProcessIdentifier: snapshot.instance?.processIdentifier
              ) else {
            return nil
        }
        return snapshot
    }

    private func applyNowPlayingSnapshot(_ snapshot: NowPlayingAXSnapshot) {
        switch snapshot.availability {
        case let .recognized(track):
            cachedStatus = MusicSourceStatus(
                sourceName: "macOS 播放中",
                availability: .systemNowPlayingRecognized,
                headline: "已完成手动系统诊断",
                detail: "来自 macOS 控制中心“播放中”面板：\(track.rawLine)。该结果只用于诊断，不作为汽水直接适配主线。",
                checkedAt: snapshot.checkedAt
            )
        case .accessibilityRequired:
            cachedStatus = MusicSourceStatus(
                sourceName: "macOS 播放中",
                availability: .accessibilityRequired,
                headline: "需要辅助功能权限",
                detail: "读取系统“播放中”面板需要辅助功能权限。该入口仅用于手动诊断。",
                checkedAt: snapshot.checkedAt
            )
        case .controlCenterUnavailable:
            cachedStatus = MusicSourceStatus(
                sourceName: "macOS 播放中",
                availability: .systemNowPlayingUnavailable,
                headline: "未找到控制中心",
                detail: "无法读取系统“播放中”面板；该入口只用于手动诊断，不影响汽水直接适配主线。",
                checkedAt: snapshot.checkedAt
            )
        case .nowPlayingUnavailable:
            cachedStatus = MusicSourceStatus(
                sourceName: "macOS 播放中",
                availability: .systemNowPlayingUnavailable,
                headline: "系统播放信息不可用",
                detail: "控制中心当前没有暴露可读取的“播放中”内容；不会用假歌名替代。",
                checkedAt: snapshot.checkedAt
            )
        case let .failed(message):
            cachedStatus = MusicSourceStatus(
                sourceName: "macOS 播放中",
                availability: .systemNowPlayingUnavailable,
                headline: "系统播放信息读取失败",
                detail: message,
                checkedAt: snapshot.checkedAt
            )
        }
    }

    private func qishuiLyricIdentity() -> QishuiLyricIdentity? {
        guard selectedMusicSource() == .qishui else { return nil }
        let mediaIdentity: QishuiLyricIdentity?
        if let track = latestMediaRemoteSnapshot?.currentTrack,
           track.sourceBundleIdentifier == QishuiProcessLocator.bundleIdentifier,
           let processIdentifier = track.sourceProcessIdentifier {
            mediaIdentity = .init(processIdentifier: processIdentifier, title: track.title, artist: track.artist)
        } else {
            mediaIdentity = nil
        }
        let directIdentity: QishuiLyricIdentity?
        if let snapshot = latestQishuiSnapshot,
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

    private func scheduleQishuiTransitionIdentityReconciliation() {
        guard isRealtimeObservationRunning, selectedMusicSource() == .qishui,
              latestMediaRemoteSnapshot?.isVerifiedQishuiSource == true,
              let media = qishuiMediaIdentity(),
              let snapshot = latestQishuiSnapshot,
              let track = snapshot.currentTrack,
              let processIdentifier = snapshot.processIdentifier else { return }
        let direct = QishuiLyricIdentity(
            processIdentifier: processIdentifier, title: track.title, artist: track.artist
        )
        guard QishuiIdentityRefreshPolicy.needsTransitionReconciliation(
            media: media, direct: direct, directCheckedAt: snapshot.checkedAt,
            lastRequested: lastQishuiTransitionIdentityRequested,
            isReadInFlight: qishuiIdentityRefreshInFlight
        ) else { return }
        // Reconcile once for this new stream identity rather than waiting for
        // the normal identity tick. Existing PID/coherence gates still apply.
        lastQishuiTransitionIdentityRequested = media
        recordUsage("identity_reconcile_requested", fields: [
            "source": "qishui",
            "direct_age_ms": String(max(0, Int(Date().timeIntervalSince(snapshot.checkedAt) * 1_000)))
        ])
        scheduleQishuiIdentityRefresh(force: true)
    }

    private func scheduleQishuiIdentityRefresh(force: Bool = false) {
        guard isRealtimeObservationRunning,
              selectedMusicSource() == .qishui,
              !qishuiIdentityRefreshInFlight,
              (force || Date().timeIntervalSince(lastQishuiIdentityRefreshAt) >= 1.0),
              let processIdentifier = QishuiProcessLocator.application()?.processIdentifier else {
            return
        }
        qishuiIdentityRefreshInFlight = true
        qishuiIdentityRefreshGeneration &+= 1
        let generation = qishuiIdentityRefreshGeneration
        let requestedControlGeneration = controlGeneration
        let requestedSeekGeneration = seeks.generation
        lastQishuiIdentityRefreshAt = Date()
        let requestedIdentity = qishuiMediaIdentity()
        let expectedTitle = latestMediaRemoteSnapshot?.currentTrack?.title
        let expectedArtist = latestMediaRemoteSnapshot?.currentTrack?.artist
        let queues = qishuiWorkQueues
        queues.metadata.async { [weak self] in
            let snapshot = queues.metadataSnapshot(
                preferredTitle: expectedTitle,
                preferredArtist: expectedArtist
            )
            Task { @MainActor [weak self] in
                guard let self,
                      generation == self.qishuiIdentityRefreshGeneration else { return }
                self.qishuiIdentityRefreshInFlight = false
                guard self.isRealtimeObservationRunning,
                      self.selectedMusicSource() == .qishui,
                      requestedControlGeneration == self.controlGeneration,
                      self.seeks.isCurrent(requestedSeekGeneration),
                      QishuiProcessLocator.isRunning(processIdentifier: processIdentifier),
                      snapshot.processIdentifier == processIdentifier,
                      QishuiIdentityRefreshPolicy.accepts(
                          requested: requestedIdentity,
                          current: self.qishuiMediaIdentity(),
                          result: snapshot.currentTrack.map {
                              QishuiLyricIdentity(processIdentifier: processIdentifier,
                                                  title: $0.title, artist: $0.artist)
                          }
                      ) else {
                    return
                }
                _ = self.applyQishuiDirectSnapshot(snapshot)
                self.publishCurrentState()
            }
        }
    }

    private func qishuiMediaIdentity() -> QishuiLyricIdentity? {
        guard let track = latestMediaRemoteSnapshot?.currentTrack,
              track.sourceBundleIdentifier == QishuiProcessLocator.bundleIdentifier,
              let processIdentifier = track.sourceProcessIdentifier else { return nil }
        return .init(processIdentifier: processIdentifier, title: track.title, artist: track.artist)
    }

    private func currentQishuiMusicState() -> MusicState {
        let runningIdentifiers = Set(QishuiProcessLocator.runningApplications().map(\.processIdentifier))
        let statusLine = fallbackStatusLine(for: cachedStatus.availability)
        let controlsAvailable = latestQishuiControlAvailability.allowsControl
        let controlUnavailableReason = latestQishuiControlAvailability.unavailableReason
        let controlRecoveryAction = MusicControlRecoveryPolicy.action(
            sourceBundleIdentifier: QishuiProcessLocator.bundleIdentifier,
            qishuiAvailability: latestQishuiControlAvailability
        )
        if let snapshot = latestMediaRemoteSnapshot, let track = snapshot.currentTrack {
            let evidence = mediaRemoteAdapterStreamSource.processPlaybackEvidenceStatus(
                maxAge: QishuiMediaRemoteAdmissionPolicy.maximumPlaybackEvidenceAge,
                expectedSampleID: snapshot.sampleID,
                expectedProcessIdentifier: track.sourceProcessIdentifier)
            let directEvidence = latestQishuiSnapshot?.currentTrack.map {
                $0.isPlaying != nil || $0.progress != nil
            } ?? false
            usage.recordAdmissionEvidenceIfChanged(
                evidence: evidence,
                directPlayback: directEvidence,
                origin: String(describing: snapshot.sampleOrigin)
            )
        }
        let directMusicState: (QishuiDirectTrack) -> MusicState = { directTrack in
            let effectiveIsPlaying = self.playback.pendingTarget(
                title: directTrack.title,
                artist: directTrack.artist
            )
                ?? directTrack.isPlaying
                ?? self.qishuiInference.inferredIsPlaying
                ?? false
            return MusicState(
                track: self.realTrack(from: directTrack, statusLine: statusLine),
                isPlaying: effectiveIsPlaying,
                progress: directTrack.progress ?? 0,
                lyricIndex: 0,
                elapsedTime: nil,
                duration: nil,
                canSeek: false,
                isPlaybackPending: self.playback.hasPendingOperation,
                canPlayPause: controlsAvailable,
                canPreviousTrack: controlsAvailable,
                canNextTrack: controlsAvailable,
                controlUnavailableReason: controlUnavailableReason,
                controlRecoveryAction: controlRecoveryAction,
                hasCurrentTrack: true,
                playbackStateKnown: self.playback.pendingTarget(
                    title: directTrack.title,
                    artist: directTrack.artist
                ) != nil
                    || directTrack.isPlaying != nil
                    || self.qishuiInference.inferredIsPlaying != nil
            )
        }
        if let snapshot = latestMediaRemoteSnapshot,
           let track = snapshot.currentTrack,
           QishuiPlaybackInstancePolicy.acceptsSnapshot(
               snapshotProcessIdentifier: track.sourceProcessIdentifier,
               runningProcessIdentifiers: runningIdentifiers
           ),
           QishuiMediaRemoteAdmissionPolicy.accepts(
               mediaTitle: track.title,
               mediaArtist: track.artist,
               directTitle: latestQishuiSnapshot?.currentTrack?.title,
               directArtist: latestQishuiSnapshot?.currentTrack?.artist,
               directCheckedAt: latestQishuiSnapshot?.checkedAt,
               mediaIdentityObservedAt: snapshot.trackIdentityObservedAt,
               mediaHasCompleteMetadata: snapshot.isVerifiedQishuiSource
                   && snapshot.sampleSource == .adapterStream && snapshot.sampleOrigin != .cached
                   && track.duration.map { $0 > 0 } == true && track.artworkData != nil,
               directHasPlaybackEvidence: latestQishuiSnapshot?.currentTrack.map {
                   $0.isPlaying != nil || $0.progress != nil
               } ?? false,
               mediaHasFreshProcessPlaybackEvidence: mediaRemoteAdapterStreamSource
                   .hasFreshProcessPlaybackEvidence(maxAge: QishuiMediaRemoteAdmissionPolicy.maximumPlaybackEvidenceAge,
                       expectedSampleID: snapshot.sampleID,
                       expectedProcessIdentifier: track.sourceProcessIdentifier)
           ) {
            let isCachedMediaFocus = cachedStatus.availability == .qishuiMediaRemoteCached
            let liveTrack = playback.liveTrack(
                from: track,
                checkedAt: snapshot.checkedAt,
                allowsTimelineFloorRelease: !isCachedMediaFocus
                    && snapshot.sampleOrigin != .cached && snapshot.sampleOrigin != .unknown
            )
            let effectiveTrack = isCachedMediaFocus
                ? playback.cachedPlaybackTrack(from: liveTrack)
                : liveTrack
            let canGuardedSeek = QishuiSeekSafety.allowsGuardedSeek(
                hasVerifiedQishuiSource: snapshot.isVerifiedQishuiSource,
                hasCurrentTrack: true,
                hasDuration: effectiveTrack.duration.map { $0 > 0 } ?? false,
                isCached: isCachedMediaFocus
                    || snapshot.sampleOrigin == .cached,
                hasCompetingPlayback: hasCompetingMusicPlayback(excluding: .qishui)
            )
            return MusicState(
                track: realTrack(from: effectiveTrack, statusLine: statusLine),
                isPlaying: effectiveTrack.isPlaying ?? false,
                progress: effectiveTrack.progress,
                lyricIndex: 0,
                elapsedTime: effectiveTrack.elapsedTime,
                duration: effectiveTrack.duration,
                canSeek: canGuardedSeek,
                isPlaybackPending: playback.hasPendingOperation,
                canPlayPause: controlsAvailable,
                canPreviousTrack: controlsAvailable,
                canNextTrack: controlsAvailable,
                controlUnavailableReason: controlUnavailableReason,
                controlRecoveryAction: controlRecoveryAction,
                hasCurrentTrack: true,
                playbackStateKnown: true
            )
        }

        if let snapshot = latestQishuiSnapshot,
           let track = snapshot.currentTrack,
           QishuiPlaybackInstancePolicy.acceptsSnapshot(
               snapshotProcessIdentifier: snapshot.processIdentifier,
               runningProcessIdentifiers: runningIdentifiers
           ) {
            return directMusicState(track)
        }

        let pendingIsPlaying = playback.pendingOperation?.targetIsPlaying ?? false
        return MusicState(
            track: placeholderTrack(statusLine: statusLine),
            isPlaying: pendingIsPlaying,
            progress: 0,
            lyricIndex: 0,
            elapsedTime: nil,
            duration: nil,
            canSeek: false,
            isPlaybackPending: playback.hasPendingOperation,
            canPlayPause: controlsAvailable,
            canPreviousTrack: controlsAvailable,
            canNextTrack: controlsAvailable,
            controlUnavailableReason: controlUnavailableReason,
            controlRecoveryAction: controlRecoveryAction,
            hasCurrentTrack: false
        )
    }

    private func realTrack(from track: MediaRemoteNowPlayingTrack, statusLine _: String) -> MusicTrack {
        let lyricSnapshot = qishuiLyrics.lyrics(for: track)
        var result = MusicTrack(
            title: track.title,
            artist: track.artist,
            palette: [Color(red: 0.10, green: 0.72, blue: 0.58), Color(red: 0.05, green: 0.15, blue: 0.18)],
            lyrics: lyricSnapshot?.lines ?? [],
            hasArtwork: track.artworkData != nil,
            artworkData: track.artworkData,
            artworkURL: nil,
            sourceBundleIdentifier: track.sourceBundleIdentifier,
            lyricsAreDesktopSnapshot: lyricSnapshot?.isDesktopSnapshot ?? false
        )
        if qishuiLyrics.timedIdentity == lyricSnapshot?.identity,
           let current = lyricSnapshot?.lines.first {
            result.timedWords = QishuiTimedLyricParser.words(
                for: current, at: track.elapsedTime, in: qishuiLyrics.timedLines, trackDuration: track.duration
            )
        }
        return result
    }

    private func realTrack(from track: QishuiDirectTrack, statusLine _: String) -> MusicTrack {
        let lyrics = qishuiLyrics.lyrics(for: track)
        let identity = latestQishuiSnapshot?.processIdentifier.map {
            QishuiLyricIdentity(processIdentifier: $0, title: track.title, artist: track.artist)
        }
        let artwork = QishuiArtworkFallbackPolicy.artwork(from: latestMediaRemoteSnapshot, for: identity)
        return MusicTrack(
            title: track.title,
            artist: track.artist,
            palette: [Color(red: 0.12, green: 0.70, blue: 0.56), Color(red: 0.08, green: 0.16, blue: 0.18)],
            lyrics: lyrics?.lines ?? [],
            hasArtwork: artwork != nil || track.artworkURL != nil,
            artworkData: artwork,
            artworkURL: track.artworkURL,
            sourceBundleIdentifier: "com.soda.music",
            lyricsAreDesktopSnapshot: lyrics?.isDesktopSnapshot ?? false
        )
    }

    private func placeholderTrack(statusLine _: String) -> MusicTrack {
        MusicTrack(
            title: "汽水音乐",
            artist: "直接适配中",
            palette: [Color(red: 0.12, green: 0.70, blue: 0.56), Color(red: 0.10, green: 0.32, blue: 0.86)],
            lyrics: [],
            hasArtwork: false,
            artworkData: nil,
            artworkURL: nil,
            sourceBundleIdentifier: "com.soda.music"
        )
    }

    private func cleanDisplayLyrics(_ lines: [String]) -> [String] {
        MusicLyricPresentation.clean(lines)
    }

    private func fallbackStatusLine(for availability: MusicSourceAvailability) -> String {
        switch availability {
        case .qishuiNotRunning:
            return "未检测到汽水音乐"
        case .accessibilityRequired:
            return "汽水语义控制需要辅助功能权限"
        case .qishuiMediaRemoteSynced:
            return latestMediaRemoteSnapshot?.diagnostic ?? "已接入 macOS Now Playing 实时事件源"
        case .qishuiMediaRemoteCached:
            return latestMediaRemoteSnapshot?.diagnostic ?? "已保持最近一次汽水音乐状态"
        case .qishuiDetectedAXLimited:
            return latestQishuiSnapshot?.diagnostic ?? "等待汽水直接适配"
        case .systemNowPlayingRecognized:
            return "来自手动系统诊断，不作为自动同步源"
        case .systemNowPlayingUnavailable:
            return "手动系统诊断暂不可读"
        case .qishuiControlSent:
            return "已触发汽水语义控制，等待真实状态回读"
        case .neteaseMusicSynced:
            return "已接入网易云音乐专属状态"
        case .neteaseMusicControlSent:
            return "已向网易云音乐当前 PID 发送语义控制"
        case .appleMusicSynced:
            return "已接入 Apple Music"
        case .appleMusicControlSent:
            return "已向 Apple Music 发送控制"
        case .appleMusicPermissionRequired:
            return "Apple Music 需要自动化权限"
        case .preview:
            return "等待汽水音乐真实数据"
        }
    }

    private func updatePendingPlaybackConfirmation(checkedAt: Date) -> Bool {
        let directTrack = latestQishuiSnapshot?.currentTrack.map {
            PlaybackTrackIdentity(title: $0.title, artist: $0.artist)
        }
        guard let confirmed = playback.confirmFromInferredPlayback(
            directTrack: directTrack,
            inferredIsPlaying: qishuiInference.inferredIsPlaying,
            checkedAt: checkedAt
        ) else { return false }
        recordPlaybackConfirmed(confirmed, evidence: "ax_progress", confirmedAt: checkedAt)
        return true
    }

    private func updateMediaRemotePlaybackConfirmation(snapshot: MediaRemoteNowPlayingSnapshot) {
        guard let confirmed = playback.confirmFromMediaRemote(snapshot: snapshot) else { return }
        recordPlaybackConfirmed(confirmed, evidence: "mediaremote", confirmedAt: snapshot.checkedAt)
    }

    @discardableResult
    private func beginPendingPlaybackOperation(requestedState: MusicState) -> Int {
        playback.begin(
            requestedState: requestedState,
            baselineSampleID: latestMediaRemoteSnapshot?.sampleID ?? 0,
            baselineSampleSource: latestMediaRemoteSnapshot?.sampleSource ?? .unknown
        )
    }

    private func schedulePendingPlaybackConfirmationTimeout(id: Int) {
        playback.scheduleConfirmationTimeout(id: id) { [weak self] id in
            self?.expirePendingPlaybackOperation(id: id)
        }
    }

    private func recordPlaybackConfirmed(
        _ operation: PendingPlaybackOperation,
        evidence: String,
        confirmedAt: Date
    ) {
        recordUsage("playback_confirmed", fields: [
            "evidence": evidence,
            "latency_ms": String(max(
                Int(confirmedAt.timeIntervalSince(operation.issuedAt) * 1_000),
                0
            )),
            "source": "qishui",
            "target_playback": operation.targetIsPlaying ? "playing" : "paused"
        ])
    }

    private func expirePendingPlaybackOperation(id: Int) {
        if let operation = playback.pendingOperation,
           operation.id == id {
            recordUsage("playback_confirmation_timeout", fields: [
                "latency_ms": String(max(
                    Int(Date().timeIntervalSince(operation.issuedAt) * 1_000),
                    0
                )),
                "source": "qishui",
                "target_playback": operation.targetIsPlaying ? "playing" : "paused"
            ])
        }
        let timeoutStatus = MusicSourceStatus(
            sourceName: "汽水音乐",
            availability: .qishuiMediaRemoteCached,
            headline: "播放状态确认超时",
            detail: "未收到匹配的汽水状态回读，已恢复请求前的可信播放状态。",
            checkedAt: Date()
        )
        rollbackPendingPlaybackOperation(id: id, status: timeoutStatus)
    }

    private func rollbackPendingPlaybackOperation(
        id: Int,
        status: MusicSourceStatus
    ) {
        guard playback.rollback(id: id) else { return }
        cachedStatus = status
        publishCurrentState()
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = max(Int(time.rounded()), 0)
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}
