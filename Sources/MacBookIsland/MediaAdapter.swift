import AppKit
import ApplicationServices
import Foundation
import SwiftUI

enum MusicSourceAvailability: String, Equatable {
    case preview
    case qishuiNotRunning
    case qishuiMediaRemoteSynced
    case qishuiMediaRemoteCached
    case qishuiDetectedAXLimited
    case systemNowPlayingRecognized
    case systemNowPlayingUnavailable
    case qishuiControlSent
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
            return 60_000_000
        case .drag:
            return 180_000_000
        }
    }
}

enum QishuiSeekSafety {
    // MediaRemote only exposes a system-global seek command. Until Qishui exposes
    // a client-targeted seek primitive, enabling it can move another app's video.
    static let supportsTargetedSeek = false
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

private struct PlaybackTrackIdentity: Equatable {
    let title: String
    let artist: String
}

private struct PendingPlaybackOperation {
    let id: Int
    let targetIsPlaying: Bool
    let issuedAt: Date
    let trackIdentity: PlaybackTrackIdentity
    let anchorElapsed: TimeInterval?
    let anchorDuration: TimeInterval?
    let baselineSampleID: UInt64
    let baselineSampleSource: MediaRemoteSampleSource
    let requiresObservedOppositeState: Bool
    var observedOppositeState: Bool
}

private struct PlaybackTimelineFloor {
    let trackIdentity: PlaybackTrackIdentity
    let elapsedTime: TimeInterval
}

private struct CachedPlaybackOverride {
    let trackIdentity: PlaybackTrackIdentity
    let isPlaying: Bool
    let elapsedTime: TimeInterval?
    let duration: TimeInterval?
    let updatedAt: Date
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

@MainActor
final class MusicAdapterCoordinator {
    private let qishuiAdapter = QishuiAdapter()
    private let appleMusicAdapter = AppleMusicAppAdapter()
    private let musicSourceSelector = MusicSourceSelector()
    private let qishuiAXChangeMonitor = QishuiAXChangeMonitor()
    private let qishuiSemanticAXController = QishuiSemanticAXController()
    private let qishuiControlQueue = DispatchQueue(label: "MacBookIsland.QishuiSemanticControl")
    private let mediaRemoteAdapterStreamSource = MediaRemoteAdapterStreamSource()
    private let nowPlayingBridge = NowPlayingAXBridge()
    private let automaticRefreshInterval: TimeInterval = 5.0
    private let playbackPositionRefreshInterval: TimeInterval = 2.0
    private var latestQishuiSnapshot: QishuiDirectSnapshot?
    private var latestMediaRemoteSnapshot: MediaRemoteNowPlayingSnapshot?
    private var lastSourceRefreshAt: Date?
    private var lastPlaybackPositionRefreshAt: Date?
    private var pendingPlaybackOperation: PendingPlaybackOperation?
    private var pendingPlaybackTimeoutTask: Task<Void, Never>?
    private var nextPlaybackOperationID = 0
    private var controlGeneration = 0
    private var lastTrackControlStartedAt: Date?
    private var playbackTimelineFloor: PlaybackTimelineFloor?
    private var cachedPlaybackOverride: CachedPlaybackOverride?
    private var lastCachedOverrideRefreshAttemptAt: Date?
    private var previousQishuiProgress: QishuiProgressSample?
    private var qishuiStationarySince: Date?
    private var inferredQishuiIsPlaying: Bool?
    private var realtimeRefreshInFlight = false
    private var realtimeRefreshQueued = false
    private var playbackPositionRefreshInFlight = false
    private var realtimeUpdateHandler: ((MusicState, MusicSourceStatus) -> Void)?
    private var qishuiLifecycleObservers: [NSObjectProtocol] = []
    private var foregroundMusicSource: MusicSourceID?
    private var latestAppleMusicSnapshot: MusicAppSnapshot?
    private var appleMusicRefreshTask: Task<Void, Never>?
    private var appleMusicRefreshQueued = false
    private var appleMusicRefreshGeneration: UInt64 = 0
    private var lastAppleMusicRefreshCompletedAt: Date?
    private var lastAppleMusicControlAt: Date?
    private var appleMusicConsecutiveRefreshFailures = 0
    private var appleMusicControlRequestID: UInt64 = 0
    private var appleMusicControlGeneration: UInt64 = 0
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
            lyricIndex: 0
        )
    }

    func startRealtimeObservation(onUpdate: @escaping (MusicState, MusicSourceStatus) -> Void) {
        realtimeUpdateHandler = onUpdate
        startQishuiLifecycleObservation()
        appleMusicAdapter.start { [weak self] invalidation in
            switch invalidation {
            case .sourceChanged:
                self?.scheduleAppleMusicRefresh(force: true)
            case .cachedDataChanged:
                self?.publishCachedAppleMusicSnapshot()
            }
        }
        scheduleAppleMusicRefresh(force: true)
        mediaRemoteAdapterStreamSource.start { [weak self] in
            guard let self else { return }
            self.refreshFromRealtimeSignal(onUpdate: onUpdate)
        }
        qishuiAXChangeMonitor.start { [weak self] _ in
            guard let self else { return }
            self.refreshFromRealtimeSignal(onUpdate: onUpdate)
        }
        reconcileForegroundMusicSource()
        schedulePlaybackPositionRefresh()
    }

    func stopRealtimeObservation() {
        realtimeUpdateHandler = nil
        stopQishuiLifecycleObservation()
        appleMusicRefreshGeneration &+= 1
        appleMusicRefreshTask?.cancel()
        appleMusicRefreshTask = nil
        appleMusicRefreshQueued = false
        lastAppleMusicRefreshCompletedAt = nil
        lastAppleMusicControlAt = nil
        appleMusicConsecutiveRefreshFailures = 0
        appleMusicAdapter.stop()
        latestAppleMusicSnapshot = nil
        foregroundMusicSource = nil
        mediaRemoteAdapterStreamSource.stop()
        qishuiAXChangeMonitor.stop()
        resetPendingPlaybackOperation(clearTimelineFloor: true)
    }

    func playPause(_ state: MusicState) -> MusicState {
        state
    }

    func nextTrack() -> MusicState {
        MusicState(track: placeholderTrack(statusLine: "已发送切歌控制，等待汽水直接状态回读"), isPlaying: false, progress: 0, lyricIndex: 0)
    }

    func previousTrack() -> MusicState {
        MusicState(track: placeholderTrack(statusLine: "已发送切歌控制，等待汽水直接状态回读"), isPlaying: false, progress: 0, lyricIndex: 0)
    }

    func performControl(
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
        if binding.source == .appleMusic {
            return await performAppleMusicControl(command)
        }
        let canAttemptControl = latestQishuiSnapshot?.isRunning == true || qishuiAdapter.isRunning()
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
        }

        let targetProcessIdentifier = latestQishuiSnapshot?.processIdentifier
            ?? NSRunningApplication.runningApplications(
                withBundleIdentifier: MusicAdapterRegistry.qishui.descriptor.bundleIdentifier
            ).first?.processIdentifier
        guard let targetProcessIdentifier else {
            markQishuiNotRunning()
            return MusicControlOutcome(status: cachedStatus, didSendCommand: false)
        }

        _ = refreshSourceStatus()
        if command != .playPause {
            resetPendingPlaybackOperation(clearTimelineFloor: true)
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

        if let playbackOperationID {
            if didPost {
                if isCurrentPlaybackOperation(playbackOperationID) {
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
            resetPendingPlaybackOperation(clearTimelineFloor: false)
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

        appleMusicControlRequestID &+= 1
        let request = MusicControlRequest(
            id: appleMusicControlRequestID,
            target: instance,
            expectedTrack: track.identity,
            action: action
        )
        appleMusicControlGeneration &+= 1
        let controlGeneration = appleMusicControlGeneration
        lastAppleMusicControlAt = Date()
        let baselineSnapshot = snapshot
        if controlKind == .playPause,
           let optimisticSnapshot = appleMusicSnapshot(
            togglingPlaybackIn: snapshot,
            at: Date()
           ) {
            latestAppleMusicSnapshot = optimisticSnapshot
            publishCurrentState()
        }
        let result = await appleMusicAdapter.perform(request)
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
            scheduleAppleMusicRefresh(force: true)
        } else if controlKind == .playPause,
                  let current = latestAppleMusicSnapshot,
                  current.instance == baselineSnapshot.instance,
                  current.track?.identity == baselineSnapshot.track?.identity,
                  let restoredSnapshot = appleMusicSnapshot(
                    current,
                    settingPlaybackState: baselineSnapshot.playbackState,
                    at: Date(),
                    diagnostic: "Apple Music 控制失败，已恢复本地播放状态。"
                  ) {
            latestAppleMusicSnapshot = restoredSnapshot
            publishCurrentState()
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
        return await withCheckedContinuation { continuation in
            qishuiControlQueue.async {
                continuation.resume(returning: semanticController.press(
                    command,
                    processIdentifier: processIdentifier
                ))
            }
        }
    }

    private func synchronizeAfterQueuedTrackControl(
        generation: Int
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            qishuiControlQueue.async {
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
        reconcileForegroundMusicSource()
        scheduleAppleMusicRefresh(force: false)
        if pendingPlaybackOperation != nil
            || shouldRefreshCachedPlaybackState()
            || shouldRefreshPlaybackPosition(state) {
            schedulePlaybackPositionRefresh()
        }
        _ = refreshSourceStatusIfNeeded()
        return selectedMusicUpdate()
    }

    func currentState() -> MusicState {
        selectedMusicUpdate().music
    }

    func refreshPlaybackPositionNow() -> (music: MusicState, status: MusicSourceStatus) {
        if selectedMusicSource() == .appleMusic {
            scheduleAppleMusicRefresh(force: true)
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
        let binding = DisplayedMusicControlBinding(
            displayedSourceBundleIdentifier: displayedSourceBundleIdentifier
        )
        if binding?.source == .appleMusic {
            return await seekAppleMusic(
                to: progress,
                interaction: interaction
            )
        }
        _ = progress
        _ = interaction
        cachedStatus = MusicSourceStatus(
            sourceName: "汽水实时适配器",
            availability: .systemNowPlayingUnavailable,
            headline: "当前不能拖动进度",
            detail: "汽水音乐尚未提供可定向调用的进度跳转接口。为避免把操作发送给抖音等系统当前媒体，顶屿已停用全局进度跳转。",
            checkedAt: Date()
        )
        return (currentQishuiMusicState(), cachedStatus)
    }

    private func seekAppleMusic(
        to progress: Double,
        interaction: MusicSeekInteraction
    ) async -> (music: MusicState, status: MusicSourceStatus) {
        guard progress.isFinite,
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
        guard AppleMusicAppAdapter.isRunning,
              latestAppleMusicSnapshot?.instance == instance,
              latestAppleMusicSnapshot?.track?.identity == track.identity else {
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
        let result = await appleMusicAdapter.perform(MusicControlRequest(
            id: appleMusicControlRequestID,
            target: instance,
            expectedTrack: track.identity,
            action: .seekNormalized(progress)
        ))
        let succeeded = result.disposition == .accepted
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
        if selectedMusicSource() == .appleMusic {
            let route = musicSourceSelector.selection
            let snapshot = await appleMusicAdapter.snapshot(refresh: .timeline)
            guard musicSourceSelector.selection == route else {
                return (selectedMusicState(), selectedMusicStatus())
            }
            applyAppleMusicSnapshotIfNewer(snapshot)
            return (selectedMusicState(), selectedMusicStatus())
        }
        if (forcePositionRefresh
            || pendingPlaybackOperation != nil
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
        if selectedMusicSource() == .appleMusic {
            scheduleAppleMusicRefresh(force: true)
            return
        }
        qishuiAdapter.invalidateAXCache()
        qishuiSemanticAXController.invalidateCache()
    }

    private func refreshFromRealtimeSignal(onUpdate: @escaping (MusicState, MusicSourceStatus) -> Void) {
        guard !realtimeRefreshInFlight else {
            realtimeRefreshQueued = true
            return
        }

        realtimeRefreshInFlight = true
        _ = refreshSourceStatus()
        let update = selectedMusicUpdate()
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
           let track = adapterSnapshot.currentTrack {
            latestMediaRemoteSnapshot = adapterSnapshot
            lastSourceRefreshAt = adapterSnapshot.checkedAt
            let hasVerifiedClientState = mediaRemoteAdapterStreamSource.hasVerifiedQishuiClientState()
            if hasVerifiedClientState {
                if pendingPlaybackOperation == nil {
                    updateCachedPlaybackOverride(from: track, checkedAt: adapterSnapshot.checkedAt)
                }
                updateMediaRemotePlaybackConfirmation(snapshot: adapterSnapshot)
            } else if shouldRefreshCachedPlaybackOverride() {
                lastCachedOverrideRefreshAttemptAt = Date()
                let directSnapshot = qishuiAdapter.snapshot()
                latestQishuiSnapshot = directSnapshot
                if let directTrack = directSnapshot.currentTrack {
                    updateQishuiPlaybackInference(track: directTrack, checkedAt: directSnapshot.checkedAt)
                    if pendingPlaybackOperation == nil
                        || updatePendingPlaybackConfirmation(checkedAt: directSnapshot.checkedAt) {
                        updateCachedPlaybackOverride(from: directTrack, checkedAt: directSnapshot.checkedAt)
                    }
                }
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

        let snapshot = qishuiAdapter.snapshot()
        return applyQishuiDirectSnapshot(snapshot)
    }

    private func applyQishuiDirectSnapshot(
        _ snapshot: QishuiDirectSnapshot
    ) -> MusicSourceStatus {
        latestQishuiSnapshot = snapshot
        lastSourceRefreshAt = snapshot.checkedAt

        guard snapshot.isRunning else {
            markQishuiNotRunning(checkedAt: snapshot.checkedAt)
            return cachedStatus
        }

        if let track = snapshot.currentTrack {
            updateQishuiPlaybackInference(track: track, checkedAt: snapshot.checkedAt)
            if pendingPlaybackOperation == nil
                || updatePendingPlaybackConfirmation(checkedAt: snapshot.checkedAt) {
                updateCachedPlaybackOverride(from: track, checkedAt: snapshot.checkedAt)
            }
            cachedStatus = MusicSourceStatus(
                sourceName: "汽水直接适配",
                availability: .qishuiDetectedAXLimited,
                headline: "已读取汽水实时播放",
                detail: "\(track.title) - \(track.artist)。来源：\(track.sourceName)。播放态：\(qishuiPlaybackLabel(track))。",
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
        _ = refreshSourceStatus()
        if latestMediaRemoteSnapshot?.currentTrack != nil {
            publishCurrentState()
            return
        }

        let controller = qishuiSemanticAXController
        let snapshot = await withCheckedContinuation { continuation in
            qishuiControlQueue.async {
                _ = controller.prepareAccessibilityTree()
                continuation.resume(returning: QishuiAdapter().snapshot())
            }
        }
        guard foregroundMusicSource == .qishui else { return }
        _ = applyQishuiDirectSnapshot(snapshot)
        publishCurrentState()
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
                if self.foregroundMusicSource == source {
                    self.foregroundMusicSource = nil
                }
                switch source {
                case .qishui:
                    self.markQishuiNotRunning()
                case .appleMusic:
                    self.appleMusicRefreshGeneration &+= 1
                    self.appleMusicRefreshTask?.cancel()
                    self.appleMusicRefreshTask = nil
                    self.appleMusicRefreshQueued = false
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
            let bundleIdentifier = (
                notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            )?.bundleIdentifier
            guard let source = Self.musicSourceID(for: bundleIdentifier) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch source {
                case .qishui:
                    self.lastSourceRefreshAt = nil
                    self.qishuiAdapter.invalidateAXCache()
                    self.qishuiSemanticAXController.invalidateCache()
                case .appleMusic:
                    self.lastAppleMusicRefreshCompletedAt = nil
                    self.appleMusicConsecutiveRefreshFailures = 0
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
                switch source {
                case .qishui:
                    await self.refreshForegroundQishuiState()
                    return
                case .appleMusic:
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
                let source = Self.musicSourceID(for: bundleIdentifier)
                guard source != self.foregroundMusicSource else { return }
                self.foregroundMusicSource = source
                self.publishCurrentState()
                switch source {
                case .qishui:
                    await self.refreshForegroundQishuiState()
                    return
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

    nonisolated private static func musicSourceID(
        for bundleIdentifier: String?
    ) -> MusicSourceID? {
        MusicSourceID(bundleIdentifier: bundleIdentifier)
    }

    private func markQishuiNotRunning(checkedAt: Date = Date()) {
        controlGeneration += 1
        latestMediaRemoteSnapshot = nil
        latestQishuiSnapshot = nil
        lastSourceRefreshAt = checkedAt
        lastPlaybackPositionRefreshAt = nil
        lastTrackControlStartedAt = nil
        resetPendingPlaybackOperation(clearTimelineFloor: true)
        previousQishuiProgress = nil
        qishuiStationarySince = nil
        inferredQishuiIsPlaying = nil
        qishuiAdapter.invalidateAXCache()
        qishuiSemanticAXController.invalidateCache()
        mediaRemoteAdapterStreamSource.invalidateQishuiSession()
        cachedStatus = MusicSourceStatus(
            sourceName: "汽水音乐",
            availability: .qishuiNotRunning,
            headline: "未检测到汽水音乐",
            detail: "当前不显示播放数据；打开汽水音乐后，顶屿会自动恢复。",
            checkedAt: checkedAt
        )
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
        guard let lastCheckedAt = lastCachedOverrideRefreshAttemptAt else {
            return true
        }
        return Date().timeIntervalSince(lastCheckedAt) >= 1.0
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

    private func scheduleAppleMusicRefresh(force: Bool) {
        let now = Date()
        guard AppleMusicAppAdapter.isRunning else {
            appleMusicRefreshGeneration &+= 1
            appleMusicRefreshTask?.cancel()
            appleMusicRefreshTask = nil
            appleMusicRefreshQueued = false
            appleMusicConsecutiveRefreshFailures = 0
            if latestAppleMusicSnapshot != nil {
                latestAppleMusicSnapshot = nil
                lastAppleMusicRefreshCompletedAt = now
                publishCurrentState()
            }
            return
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
            self.applyAppleMusicSnapshotIfNewer(snapshot)
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

    private func applyAppleMusicSnapshotIfNewer(_ snapshot: MusicAppSnapshot) {
        if let current = latestAppleMusicSnapshot,
           current.checkedAt > snapshot.checkedAt {
            return
        }
        latestAppleMusicSnapshot = snapshot
    }

    private func publishCachedAppleMusicSnapshot() {
        Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.appleMusicAdapter.snapshot(refresh: .cached)
            guard !Task.isCancelled else { return }
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
            applyAppleMusicSnapshotIfNewer(snapshot)
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

    private func selectedMusicSource() -> MusicSourceID? {
        reconcileForegroundMusicSource()
        return musicSourceSelector.update(
            qishui: qishuiSourceCandidate(),
            appleMusic: appleMusicSourceCandidate(),
            foregroundSource: foregroundMusicSource
        ).source
    }

    private func qishuiSourceCandidate() -> MusicSourceCandidate {
        let mediaRemoteTrack = latestMediaRemoteSnapshot?.currentTrack
        let directTrack = latestQishuiSnapshot?.currentTrack
        let hasTrack = mediaRemoteTrack != nil || directTrack != nil
        let isPlaying = mediaRemoteTrack?.isPlaying
            ?? directTrack?.isPlaying
            ?? inferredQishuiIsPlaying
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

    private func appleMusicSourceCandidate() -> MusicSourceCandidate {
        guard let snapshot = latestAppleMusicSnapshot else {
            return MusicSourceCandidate(
                source: .appleMusic,
                isAvailable: AppleMusicAppAdapter.isRunning,
                hasTrack: false,
                playback: .unknown,
                isCached: false
            )
        }
        let isFresh = Date().timeIntervalSince(snapshot.checkedAt) <= 8
        let isReady: Bool
        if case .ready = snapshot.availability {
            isReady = true
        } else {
            isReady = false
        }
        let playback: MusicSourcePlaybackLevel
        switch snapshot.playbackState {
        case .playing:
            playback = .playing
        case .paused:
            playback = .paused
        case .stopped, .unknown:
            playback = .unknown
        }
        return MusicSourceCandidate(
            source: .appleMusic,
            isAvailable: AppleMusicAppAdapter.isRunning
                && (foregroundMusicSource == .appleMusic
                    || (isFresh && isReady && snapshot.instance != nil)),
            hasTrack: snapshot.track != nil,
            playback: playback,
            isCached: false
        )
    }

    private func reconcileForegroundMusicSource() {
        let source = Self.musicSourceID(
            for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        guard source != foregroundMusicSource else { return }

        foregroundMusicSource = source
        switch source {
        case .qishui:
            Task { [weak self] in
                await self?.refreshForegroundQishuiState()
            }
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
        return (musicState(for: source), musicStatus(for: source))
    }

    private func musicState(for source: MusicSourceID?) -> MusicState {
        switch source {
        case .appleMusic:
            return appleMusicState()
        case .qishui, nil:
            return currentQishuiMusicState()
        }
    }

    private func musicStatus(for source: MusicSourceID?) -> MusicSourceStatus {
        guard source == .appleMusic,
              let snapshot = latestAppleMusicSnapshot else {
            return cachedStatus
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

    private func appleMusicState() -> MusicState {
        guard let snapshot = latestAppleMusicSnapshot,
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
            isPlaybackPending: false
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
            isPlaybackPending: false
        )
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

    private func currentQishuiMusicState() -> MusicState {
        let statusLine = fallbackStatusLine(for: cachedStatus.availability)
        if let snapshot = latestMediaRemoteSnapshot,
           let track = snapshot.currentTrack {
            let isCachedMediaFocus = cachedStatus.availability == .qishuiMediaRemoteCached
            let liveTrack = liveMediaRemoteTrack(
                from: track,
                checkedAt: snapshot.checkedAt,
                allowsTimelineFloorRelease: !isCachedMediaFocus
            )
            let effectiveTrack = isCachedMediaFocus
                ? cachedPlaybackTrack(from: liveTrack)
                : liveTrack
            return MusicState(
                track: realTrack(from: effectiveTrack, statusLine: statusLine),
                isPlaying: effectiveTrack.isPlaying ?? false,
                progress: effectiveTrack.progress,
                lyricIndex: 0,
                elapsedTime: effectiveTrack.elapsedTime,
                duration: effectiveTrack.duration,
                canSeek: QishuiSeekSafety.supportsTargetedSeek
                    && !isCachedMediaFocus
                    && (effectiveTrack.duration.map { $0 > 0 } ?? false),
                isPlaybackPending: pendingPlaybackOperation != nil
            )
        }

        if let track = latestQishuiSnapshot?.currentTrack {
            let effectiveIsPlaying = pendingPlaybackTarget(title: track.title, artist: track.artist)
                ?? track.isPlaying
                ?? inferredQishuiIsPlaying
                ?? false
            return MusicState(
                track: realTrack(from: track, statusLine: statusLine),
                isPlaying: effectiveIsPlaying,
                progress: track.progress ?? 0,
                lyricIndex: 0,
                elapsedTime: nil,
                duration: nil,
                canSeek: false,
                isPlaybackPending: pendingPlaybackOperation != nil
            )
        }

        let pendingIsPlaying = pendingPlaybackOperation?.targetIsPlaying ?? false
        return MusicState(
            track: placeholderTrack(statusLine: statusLine),
            isPlaying: pendingIsPlaying,
            progress: 0,
            lyricIndex: 0,
            elapsedTime: nil,
            duration: nil,
            canSeek: false,
            isPlaybackPending: pendingPlaybackOperation != nil
        )
    }

    private func liveMediaRemoteTrack(
        from track: MediaRemoteNowPlayingTrack,
        checkedAt: Date,
        allowsTimelineFloorRelease: Bool
    ) -> MediaRemoteNowPlayingTrack {
        if let operation = pendingPlaybackOperation {
            guard matches(track: track, identity: operation.trackIdentity) else {
                resetPendingPlaybackOperation(clearTimelineFloor: true)
                return liveMediaRemoteTrack(
                    from: track,
                    checkedAt: checkedAt,
                    allowsTimelineFloorRelease: allowsTimelineFloorRelease
                )
            }

            let duration = operation.anchorDuration ?? track.duration
            let anchorElapsed = operation.anchorElapsed ?? track.elapsedTime
            let elapsed: TimeInterval?
            let progress: Double
            if let anchorElapsed, let duration, duration > 0 {
                let optimisticElapsed = PlaybackControlTimeline.optimisticElapsed(
                    targetIsPlaying: operation.targetIsPlaying,
                    anchorElapsed: anchorElapsed,
                    issuedAt: operation.issuedAt,
                    now: Date(),
                    duration: duration
                ) ?? anchorElapsed
                let clampedElapsed = min(max(optimisticElapsed, 0), duration)
                elapsed = clampedElapsed
                progress = min(max(clampedElapsed / duration, 0), 1)
            } else {
                elapsed = anchorElapsed
                progress = track.progress
            }

            return MediaRemoteNowPlayingTrack(
                title: track.title,
                artist: track.artist,
                album: track.album,
                artworkData: track.artworkData,
                isPlaying: operation.targetIsPlaying,
                progress: progress,
                elapsedTime: elapsed,
                duration: duration,
                sourceBundleIdentifier: track.sourceBundleIdentifier,
                sourceProcessIdentifier: track.sourceProcessIdentifier,
                sourceName: track.sourceName
            )
        }

        let liveTrack: MediaRemoteNowPlayingTrack
        if track.isPlaying == true,
           let elapsed = track.elapsedTime,
           let duration = track.duration,
           duration > 0 {
            let liveElapsed = min(max(elapsed + Date().timeIntervalSince(checkedAt), 0), duration)
            let liveProgress = min(max(liveElapsed / duration, 0), 1)
            liveTrack = MediaRemoteNowPlayingTrack(
                title: track.title,
                artist: track.artist,
                album: track.album,
                artworkData: track.artworkData,
                isPlaying: track.isPlaying,
                progress: liveProgress,
                elapsedTime: liveElapsed,
                duration: duration,
                sourceBundleIdentifier: track.sourceBundleIdentifier,
                sourceProcessIdentifier: track.sourceProcessIdentifier,
                sourceName: track.sourceName
            )
        } else {
            liveTrack = track
        }

        guard let floor = playbackTimelineFloor else { return liveTrack }
        guard matches(track: liveTrack, identity: floor.trackIdentity) else {
            playbackTimelineFloor = nil
            return liveTrack
        }
        if liveTrack.isPlaying == true, allowsTimelineFloorRelease {
            playbackTimelineFloor = nil
            return liveTrack
        }
        guard let duration = liveTrack.duration,
              duration > 0 else { return liveTrack }

        if allowsTimelineFloorRelease,
           liveTrack.isPlaying != true,
           let elapsedTime = liveTrack.elapsedTime,
           floor.elapsedTime - elapsedTime > max(3.0, duration * 0.03) {
            playbackTimelineFloor = nil
            return liveTrack
        }

        let incomingElapsed = allowsTimelineFloorRelease
            ? (liveTrack.elapsedTime ?? floor.elapsedTime)
            : floor.elapsedTime
        let stableElapsed = min(max(max(floor.elapsedTime, incomingElapsed), 0), duration)
        playbackTimelineFloor = PlaybackTimelineFloor(
            trackIdentity: floor.trackIdentity,
            elapsedTime: stableElapsed
        )

        return MediaRemoteNowPlayingTrack(
            title: liveTrack.title,
            artist: liveTrack.artist,
            album: liveTrack.album,
            artworkData: liveTrack.artworkData,
            isPlaying: false,
            progress: min(max(stableElapsed / duration, 0), 1),
            elapsedTime: stableElapsed,
            duration: duration,
            sourceBundleIdentifier: liveTrack.sourceBundleIdentifier,
            sourceProcessIdentifier: liveTrack.sourceProcessIdentifier,
            sourceName: liveTrack.sourceName
        )
    }

    private func shouldRefreshCachedPlaybackOverride() -> Bool {
        guard pendingPlaybackOperation == nil,
              let lastCachedOverrideRefreshAttemptAt else { return true }
        return Date().timeIntervalSince(lastCachedOverrideRefreshAttemptAt) >= 1.0
    }

    private func updateCachedPlaybackOverride(from track: QishuiDirectTrack, checkedAt: Date) {
        guard let isPlaying = track.isPlaying ?? inferredQishuiIsPlaying else { return }
        let identity = PlaybackTrackIdentity(title: track.title, artist: track.artist)
        let mediaSnapshot = latestMediaRemoteSnapshot
        let mediaTrack = mediaSnapshot?.currentTrack.flatMap {
            matches(track: $0, identity: identity) ? $0 : nil
        }
        let existingOverride = cachedPlaybackOverride.flatMap {
            matches($0.trackIdentity, identity) ? $0 : nil
        }
        let duration = mediaTrack?.duration ?? existingOverride?.duration
        let mediaRemoteElapsed = mediaTrack?.elapsedTime.map { elapsed in
            guard mediaTrack?.isPlaying == true,
                  existingOverride?.isPlaying != false,
                  let mediaSnapshot else { return elapsed }
            return elapsed + max(checkedAt.timeIntervalSince(mediaSnapshot.checkedAt), 0)
        }
        let existingElapsed = existingOverride?.elapsedTime.map { elapsed in
            guard existingOverride?.isPlaying == true,
                  let updatedAt = existingOverride?.updatedAt else { return elapsed }
            return elapsed + max(checkedAt.timeIntervalSince(updatedAt), 0)
        }
        let elapsedTime = PlaybackControlTimeline.cachedOverrideElapsed(
            mediaRemoteElapsed: mediaRemoteElapsed,
            axProgress: track.progress,
            duration: duration,
            existingElapsed: existingElapsed,
            existingIsPlaying: existingOverride?.isPlaying,
            axIsPlaying: isPlaying
        ) ?? pendingPlaybackOperation.flatMap { operation in
            matches(operation.trackIdentity, identity) ? operation.anchorElapsed : nil
        }

        cachedPlaybackOverride = CachedPlaybackOverride(
            trackIdentity: identity,
            isPlaying: isPlaying,
            elapsedTime: elapsedTime,
            duration: duration,
            updatedAt: checkedAt
        )
        lastCachedOverrideRefreshAttemptAt = checkedAt
    }

    private func updateCachedPlaybackOverride(
        from track: MediaRemoteNowPlayingTrack,
        checkedAt: Date
    ) {
        guard let isPlaying = track.isPlaying else { return }
        cachedPlaybackOverride = CachedPlaybackOverride(
            trackIdentity: PlaybackTrackIdentity(title: track.title, artist: track.artist),
            isPlaying: isPlaying,
            elapsedTime: track.elapsedTime,
            duration: track.duration,
            updatedAt: checkedAt
        )
        lastCachedOverrideRefreshAttemptAt = checkedAt
    }

    private func updateCachedPlaybackOverride(
        from track: MediaRemoteNowPlayingTrack,
        operation: PendingPlaybackOperation,
        checkedAt: Date
    ) {
        let duration = track.duration ?? operation.anchorDuration
        let elapsedTime = PlaybackControlTimeline.confirmedElapsed(
            targetIsPlaying: operation.targetIsPlaying,
            anchorElapsed: operation.anchorElapsed,
            confirmedElapsed: track.elapsedTime
        )
        cachedPlaybackOverride = CachedPlaybackOverride(
            trackIdentity: operation.trackIdentity,
            isPlaying: operation.targetIsPlaying,
            elapsedTime: elapsedTime,
            duration: duration,
            updatedAt: checkedAt
        )
        lastCachedOverrideRefreshAttemptAt = checkedAt
    }

    private func cachedPlaybackTrack(
        from track: MediaRemoteNowPlayingTrack
    ) -> MediaRemoteNowPlayingTrack {
        guard pendingPlaybackOperation == nil,
              let override = cachedPlaybackOverride else { return track }
        guard matches(track: track, identity: override.trackIdentity) else {
            cachedPlaybackOverride = nil
            return track
        }

        let duration = override.duration ?? track.duration
        var elapsedTime = override.elapsedTime ?? track.elapsedTime
        if override.isPlaying, let elapsedTimeValue = elapsedTime {
            elapsedTime = elapsedTimeValue + Date().timeIntervalSince(override.updatedAt)
            playbackTimelineFloor = nil
        }
        if let duration, duration > 0, let elapsedTimeValue = elapsedTime {
            elapsedTime = min(max(elapsedTimeValue, 0), duration)
        }
        if !override.isPlaying,
           let floor = playbackTimelineFloor,
           matches(track: track, identity: floor.trackIdentity) {
            elapsedTime = max(elapsedTime ?? floor.elapsedTime, floor.elapsedTime)
            playbackTimelineFloor = PlaybackTimelineFloor(
                trackIdentity: floor.trackIdentity,
                elapsedTime: elapsedTime ?? floor.elapsedTime
            )
        }

        let progress: Double
        if let duration, duration > 0, let elapsedTime {
            progress = min(max(elapsedTime / duration, 0), 1)
        } else {
            progress = track.progress
        }
        return MediaRemoteNowPlayingTrack(
            title: track.title,
            artist: track.artist,
            album: track.album,
            artworkData: track.artworkData,
            isPlaying: override.isPlaying,
            progress: progress,
            elapsedTime: elapsedTime,
            duration: duration,
            sourceBundleIdentifier: track.sourceBundleIdentifier,
            sourceProcessIdentifier: track.sourceProcessIdentifier,
            sourceName: track.sourceName
        )
    }

    private func realTrack(from track: MediaRemoteNowPlayingTrack, statusLine _: String) -> MusicTrack {
        return MusicTrack(
            title: track.title,
            artist: track.artist,
            palette: [Color(red: 0.10, green: 0.72, blue: 0.58), Color(red: 0.05, green: 0.15, blue: 0.18)],
            lyrics: [],
            hasArtwork: track.artworkData != nil,
            artworkData: track.artworkData,
            artworkURL: nil,
            sourceBundleIdentifier: track.sourceBundleIdentifier
        )
    }

    private func realTrack(from track: QishuiDirectTrack, statusLine _: String) -> MusicTrack {
        let lyrics = cleanDisplayLyrics(track.lyrics)
        return MusicTrack(
            title: track.title,
            artist: track.artist,
            palette: [Color(red: 0.12, green: 0.70, blue: 0.56), Color(red: 0.08, green: 0.16, blue: 0.18)],
            lyrics: lyrics,
            hasArtwork: track.artworkURL != nil,
            artworkData: nil,
            artworkURL: track.artworkURL,
            sourceBundleIdentifier: "com.soda.music"
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
        let diagnosticTokens = [
            "MediaRemote",
            "Adapter",
            "来源：",
            "播放态：",
            "已发送",
            "已请求",
            "实时同步",
            "同步来源",
            "辅助功能",
            "控制中心",
            "手动诊断",
            "适配器",
            "PID "
        ]

        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty else { return false }
                return !diagnosticTokens.contains { line.localizedCaseInsensitiveContains($0) }
            }
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

    private func updateQishuiPlaybackInference(track: QishuiDirectTrack, checkedAt: Date) {
        let signature = qishuiSignature(track)
        if let isPlaying = track.isPlaying {
            inferredQishuiIsPlaying = isPlaying
            qishuiStationarySince = isPlaying ? nil : checkedAt
        } else if let previous = previousQishuiProgress,
                  previous.signature == signature,
                  let currentProgress = track.progress,
                  checkedAt.timeIntervalSince(previous.checkedAt) >= 0.15 {
            let progressDelta = currentProgress - previous.progress
            if progressDelta > 0.0005 {
                inferredQishuiIsPlaying = true
                qishuiStationarySince = nil
            } else if progressDelta < -0.01 {
                qishuiStationarySince = nil
            } else if abs(progressDelta) <= 0.0002,
                      currentProgress > 0,
                      currentProgress < 0.995 {
                let stationarySince = qishuiStationarySince ?? previous.checkedAt
                qishuiStationarySince = stationarySince
                if checkedAt.timeIntervalSince(stationarySince) >= 1.35 {
                    inferredQishuiIsPlaying = false
                }
            } else {
                qishuiStationarySince = nil
            }
        } else {
            qishuiStationarySince = nil
            inferredQishuiIsPlaying = nil
        }

        if let progress = track.progress {
            previousQishuiProgress = QishuiProgressSample(
                signature: signature,
                progress: progress,
                checkedAt: checkedAt
            )
        }
    }

    private func updatePendingPlaybackConfirmation(checkedAt: Date) -> Bool {
        guard let operation = pendingPlaybackOperation,
              checkedAt.timeIntervalSince(operation.issuedAt) >= 0.2,
              let inferredQishuiIsPlaying,
              let track = latestQishuiSnapshot?.currentTrack,
              matches(
                PlaybackTrackIdentity(title: track.title, artist: track.artist),
                operation.trackIdentity
              ) else { return false }

        return observePlaybackConfirmation(
            isPlaying: inferredQishuiIsPlaying,
            operationID: operation.id
        )
    }

    private func updateMediaRemotePlaybackConfirmation(snapshot: MediaRemoteNowPlayingSnapshot) {
        guard let operation = pendingPlaybackOperation,
              snapshot.sampleOrigin != .cached,
              snapshot.sampleOrigin != .unknown,
              isNewSample(snapshot, for: operation),
              snapshot.checkedAt.timeIntervalSince(operation.issuedAt) >= 0.2,
              let track = snapshot.currentTrack,
              matches(track: track, identity: operation.trackIdentity),
              let isPlaying = track.isPlaying else { return }

        let didAccept = observePlaybackConfirmation(isPlaying: isPlaying, operationID: operation.id)
        if didAccept {
            updateCachedPlaybackOverride(from: track, operation: operation, checkedAt: snapshot.checkedAt)
        }
    }

    @discardableResult
    private func beginPendingPlaybackOperation(requestedState: MusicState) -> Int {
        let replacesPendingOperation = pendingPlaybackOperation != nil
        let targetIsPlaying = !requestedState.isPlaying
        nextPlaybackOperationID += 1
        let operation = PendingPlaybackOperation(
            id: nextPlaybackOperationID,
            targetIsPlaying: targetIsPlaying,
            issuedAt: Date(),
            trackIdentity: PlaybackTrackIdentity(
                title: requestedState.track.title,
                artist: requestedState.track.artist
            ),
            anchorElapsed: PlaybackControlTimeline.anchorElapsed(
                targetIsPlaying: targetIsPlaying,
                requestElapsed: requestedState.elapsedTime,
                dispatchCompletionElapsed: nil
            ),
            anchorDuration: requestedState.duration,
            baselineSampleID: latestMediaRemoteSnapshot?.sampleID ?? 0,
            baselineSampleSource: latestMediaRemoteSnapshot?.sampleSource ?? .unknown,
            requiresObservedOppositeState: replacesPendingOperation,
            observedOppositeState: false
        )

        pendingPlaybackOperation = operation
        if operation.targetIsPlaying {
            playbackTimelineFloor = nil
        } else if let anchorElapsed = operation.anchorElapsed {
            playbackTimelineFloor = PlaybackTimelineFloor(
                trackIdentity: operation.trackIdentity,
                elapsedTime: anchorElapsed
            )
        }

        pendingPlaybackTimeoutTask?.cancel()
        pendingPlaybackTimeoutTask = nil
        return operation.id
    }

    private func schedulePendingPlaybackConfirmationTimeout(id: Int) {
        guard isCurrentPlaybackOperation(id) else { return }
        pendingPlaybackTimeoutTask?.cancel()
        pendingPlaybackTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.expirePendingPlaybackOperation(id: id)
        }
    }

    private func observePlaybackConfirmation(isPlaying: Bool, operationID: Int) -> Bool {
        guard var operation = pendingPlaybackOperation,
              operation.id == operationID else { return false }

        guard isPlaying == operation.targetIsPlaying else {
            operation.observedOppositeState = true
            pendingPlaybackOperation = operation
            return false
        }
        guard !operation.requiresObservedOppositeState || operation.observedOppositeState else {
            return false
        }

        finishPendingPlaybackOperation(id: operation.id)
        return true
    }

    private func isNewSample(
        _ snapshot: MediaRemoteNowPlayingSnapshot,
        for operation: PendingPlaybackOperation
    ) -> Bool {
        guard snapshot.sampleID > 0 else { return false }
        guard snapshot.sampleSource == operation.baselineSampleSource else { return true }
        return snapshot.sampleID > operation.baselineSampleID
    }

    private func finishPendingPlaybackOperation(id: Int) {
        guard pendingPlaybackOperation?.id == id else { return }
        pendingPlaybackOperation = nil
        pendingPlaybackTimeoutTask?.cancel()
        pendingPlaybackTimeoutTask = nil
    }

    private func expirePendingPlaybackOperation(id: Int) {
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
        guard isCurrentPlaybackOperation(id) else { return }
        pendingPlaybackOperation = nil
        pendingPlaybackTimeoutTask?.cancel()
        pendingPlaybackTimeoutTask = nil
        playbackTimelineFloor = nil
        cachedStatus = status
        publishCurrentState()
    }

    private func isCurrentPlaybackOperation(_ id: Int) -> Bool {
        PlaybackControlTimeline.isCurrentOperation(
            completedOperationID: id,
            currentOperationID: pendingPlaybackOperation?.id
        )
    }

    private func resetPendingPlaybackOperation(clearTimelineFloor: Bool) {
        pendingPlaybackOperation = nil
        pendingPlaybackTimeoutTask?.cancel()
        pendingPlaybackTimeoutTask = nil
        if clearTimelineFloor {
            playbackTimelineFloor = nil
            cachedPlaybackOverride = nil
            lastCachedOverrideRefreshAttemptAt = nil
        }
    }

    private func matches(track: MediaRemoteNowPlayingTrack, identity: PlaybackTrackIdentity) -> Bool {
        matches(
            PlaybackTrackIdentity(title: track.title, artist: track.artist),
            identity
        )
    }

    private func pendingPlaybackTarget(title: String, artist: String) -> Bool? {
        guard let operation = pendingPlaybackOperation else { return nil }
        let identity = PlaybackTrackIdentity(title: title, artist: artist)
        guard matches(identity, operation.trackIdentity) else {
            resetPendingPlaybackOperation(clearTimelineFloor: true)
            return nil
        }
        return operation.targetIsPlaying
    }

    private func matches(_ lhs: PlaybackTrackIdentity, _ rhs: PlaybackTrackIdentity) -> Bool {
        guard lhs.title == rhs.title else { return false }
        return lhs.artist == rhs.artist
            || lhs.artist == "汽水音乐"
            || rhs.artist == "汽水音乐"
    }

    private func qishuiPlaybackLabel(_ track: QishuiDirectTrack) -> String {
        if let isPlaying = track.isPlaying ?? inferredQishuiIsPlaying {
            return isPlaying ? "播放中" : "已暂停"
        }
        return "等待进度变化确认"
    }

    private func qishuiSignature(_ track: QishuiDirectTrack) -> String {
        "\(track.title)\u{1f}\(track.artist)"
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = max(Int(time.rounded()), 0)
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
}

private struct QishuiProgressSample {
    let signature: String
    let progress: Double
    let checkedAt: Date
}
