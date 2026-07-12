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

    var targetedMediaRemoteCommandID: UInt32 {
        switch self {
        case .playPause:
            return 2
        case .nextTrack:
            return 4
        case .previousTrack:
            return 5
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

@MainActor
final class MusicAdapterCoordinator {
    private let qishuiAdapter = QishuiAdapter()
    private let qishuiAXChangeMonitor = QishuiAXChangeMonitor()
    private let qishuiSemanticAXController = QishuiSemanticAXController()
    private let qishuiControlQueue = DispatchQueue(label: "MacBookIsland.QishuiSemanticControl")
    private let mediaRemoteAdapterStreamSource = MediaRemoteAdapterStreamSource()
    private let mediaRemoteSource = MediaRemoteNowPlayingSource()
    private let nowPlayingBridge = NowPlayingAXBridge()
    private let automaticRefreshInterval: TimeInterval = 5.0
    private let playbackPositionRefreshInterval: TimeInterval = 2.0
    private var latestNowPlayingTrack: NowPlayingAXTrack?
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
        mediaRemoteAdapterStreamSource.start { [weak self] in
            guard let self else { return }
            self.refreshFromRealtimeSignal(onUpdate: onUpdate)
        }
        qishuiAXChangeMonitor.start { [weak self] _ in
            guard let self else { return }
            self.refreshFromRealtimeSignal(onUpdate: onUpdate)
        }
        schedulePlaybackPositionRefresh()
    }

    func stopRealtimeObservation() {
        realtimeUpdateHandler = nil
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

    func performControl(_ command: MusicControlCommand) async -> MusicControlOutcome {
        let canAttemptControl = latestQishuiSnapshot?.isRunning == true || qishuiAdapter.isRunning()
        guard canAttemptControl else {
            latestNowPlayingTrack = nil
            latestMediaRemoteSnapshot = nil
            latestQishuiSnapshot = nil
            resetPendingPlaybackOperation(clearTimelineFloor: true)
            previousQishuiProgress = nil
            qishuiStationarySince = nil
            inferredQishuiIsPlaying = nil
            cachedStatus = MusicSourceStatus(
                sourceName: "汽水音乐",
                availability: .qishuiNotRunning,
                headline: "未检测到汽水音乐",
                detail: "当前不显示假播放数据；打开汽水音乐后，顶屿会自动检测运行状态。",
                checkedAt: Date()
            )
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

        _ = refreshSourceStatus()
        if command != .playPause {
            resetPendingPlaybackOperation(clearTimelineFloor: true)
        }
        let requestedState = currentMusicState()
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
            generation: controlAttemptGeneration
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

    private func sendControl(
        _ command: MusicControlCommand,
        generation: Int
    ) async -> ControlDispatchResult {
        guard generation == controlGeneration else {
            return ControlDispatchResult(
                didPress: false,
                diagnostic: "旧控制操作已失效，未触发汽水语义控件。"
            )
        }
        let semanticResult = await pressSemanticControl(command)
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
        _ command: MusicControlCommand
    ) async -> QishuiSemanticAXControlResult {
        let semanticController = qishuiSemanticAXController
        return await withCheckedContinuation { continuation in
            qishuiControlQueue.async {
                continuation.resume(returning: semanticController.press(command))
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
        if pendingPlaybackOperation != nil
            || shouldRefreshCachedPlaybackState()
            || shouldRefreshPlaybackPosition(state) {
            schedulePlaybackPositionRefresh()
        }
        let status = refreshSourceStatusIfNeeded()
        let music = currentMusicState()
        return (music, status)
    }

    func currentState() -> MusicState {
        currentMusicState()
    }

    func refreshPlaybackPositionNow() -> (music: MusicState, status: MusicSourceStatus) {
        let status = refreshPlaybackPositionStatus()
        return (currentMusicState(), status)
    }

    func refreshNowPlaying(promptForPermission: Bool = false) -> (music: MusicState, status: MusicSourceStatus) {
        let status = refreshSourceStatus(promptForPermission: promptForPermission, allowSynchronousRefresh: true)
        guard status.availability != .qishuiNotRunning,
              status.availability != .accessibilityRequired else {
            return (currentMusicState(), status)
        }

        let snapshot = nowPlayingBridge.capture(promptForPermission: promptForPermission)
        applyNowPlayingSnapshot(snapshot)
        return (currentMusicState(), cachedStatus)
    }

    func forceRefreshNowPlaying() -> (music: MusicState, status: MusicSourceStatus) {
        refreshNowPlaying(promptForPermission: true)
    }

    func seek(
        to progress: Double,
        interaction: MusicSeekInteraction
    ) async -> (music: MusicState, status: MusicSourceStatus) {
        guard let snapshot = latestMediaRemoteSnapshot,
              snapshot.isVerifiedQishuiSource,
              let track = snapshot.currentTrack,
              let duration = track.duration,
              duration > 0 else {
            cachedStatus = MusicSourceStatus(
                sourceName: "汽水实时适配器",
                availability: .systemNowPlayingUnavailable,
                headline: "当前不能拖动进度",
                detail: "汽水音乐没有通过实时适配源暴露可跳转的时长；不会用假进度替代。",
                checkedAt: Date()
            )
            return (currentMusicState(), cachedStatus)
        }

        let canSeekDirectly = mediaRemoteAdapterStreamSource.hasCurrentVerifiedQishuiSource()
            || track.sourceName == "MediaRemote Now Playing"
        guard canSeekDirectly else {
            cachedStatus = MusicSourceStatus(
                sourceName: "汽水实时适配器",
                availability: .qishuiMediaRemoteCached,
                headline: "暂不跳转播放进度",
                detail: "当前版本的进度跳转仍依赖系统当前媒体源；检测到媒体焦点不在汽水时，已阻止把跳转发送给视频播放器。",
                checkedAt: Date()
            )
            return (currentMusicState(), cachedStatus)
        }

        let targetProgress = min(max(progress, 0), 1)
        let targetElapsed = duration * targetProgress
        guard await mediaRemoteAdapterStreamSource.seek(
            to: targetElapsed,
            coalescingDelayNanoseconds: interaction.coalescingDelayNanoseconds
        ) else {
            cachedStatus = MusicSourceStatus(
                sourceName: "汽水实时适配器",
                availability: .systemNowPlayingUnavailable,
                headline: "进度跳转失败",
                detail: "已尝试向汽水音乐发送跳转请求，但底层适配器没有确认成功；界面不会假装已经跳转。",
                checkedAt: Date()
            )
            return (currentMusicState(), cachedStatus)
        }

        resetPendingPlaybackOperation(clearTimelineFloor: true)

        cachedStatus = MusicSourceStatus(
            sourceName: "汽水实时适配器",
            availability: .qishuiControlSent,
            headline: "已请求跳转播放进度",
            detail: "已向汽水音乐发送跳转到 \(formatTime(targetElapsed)) 的请求，等待实时适配源回读确认。",
            checkedAt: Date()
        )
        var optimisticMusic = currentMusicState()
        optimisticMusic.progress = targetProgress
        optimisticMusic.elapsedTime = targetElapsed
        return (optimisticMusic, cachedStatus)
    }

    func refreshControlFollowUp(
        forcePositionRefresh: Bool = false
    ) async -> (music: MusicState, status: MusicSourceStatus) {
        if (forcePositionRefresh
            || pendingPlaybackOperation != nil
            || mediaRemoteAdapterStreamSource.hasPendingSeekTimeline()),
           !playbackPositionRefreshInFlight {
            playbackPositionRefreshInFlight = true
            _ = await mediaRemoteAdapterStreamSource.refreshPlaybackPositionAsync()
            playbackPositionRefreshInFlight = false
        }
        let status = refreshSourceStatus()
        return (currentMusicState(), status)
    }

    func invalidateQishuiCache() {
        qishuiAdapter.invalidateAXCache()
        qishuiSemanticAXController.invalidateCache()
    }

    private func refreshFromRealtimeSignal(onUpdate: @escaping (MusicState, MusicSourceStatus) -> Void) {
        guard !realtimeRefreshInFlight else {
            realtimeRefreshQueued = true
            return
        }

        realtimeRefreshInFlight = true
        let status = refreshSourceStatus()
        onUpdate(currentMusicState(), status)
        realtimeRefreshInFlight = false

        if realtimeRefreshQueued {
            realtimeRefreshQueued = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.refreshFromRealtimeSignal(onUpdate: onUpdate)
            }
        }
    }

    private func publishCurrentState() {
        realtimeUpdateHandler?(currentMusicState(), cachedStatus)
    }

    func refreshSourceStatus(
        promptForPermission: Bool = false,
        allowSynchronousRefresh: Bool = false
    ) -> MusicSourceStatus {
        _ = promptForPermission
        guard qishuiAdapter.isRunning() else {
            latestNowPlayingTrack = nil
            latestMediaRemoteSnapshot = nil
            latestQishuiSnapshot = nil
            lastSourceRefreshAt = Date()
            resetPendingPlaybackOperation(clearTimelineFloor: true)
            previousQishuiProgress = nil
            qishuiStationarySince = nil
            inferredQishuiIsPlaying = nil
            cachedStatus = MusicSourceStatus(
                sourceName: "汽水音乐",
                availability: .qishuiNotRunning,
                headline: "未检测到汽水音乐",
                detail: "当前不显示假播放数据；打开汽水音乐后，顶屿会自动检测运行状态。",
                checkedAt: Date()
            )
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
            let isCurrentMediaFocus = mediaRemoteAdapterStreamSource.hasCurrentVerifiedQishuiSource()
            if isCurrentMediaFocus {
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
                availability: isCurrentMediaFocus ? .qishuiMediaRemoteSynced : .qishuiMediaRemoteCached,
                headline: isCurrentMediaFocus ? "已接入汽水实时播放" : "保持汽水音乐显示",
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

        let mediaRemoteSnapshot = mediaRemoteSource.snapshot()
        latestMediaRemoteSnapshot = mediaRemoteSnapshot
        lastSourceRefreshAt = mediaRemoteSnapshot.checkedAt

        if let track = mediaRemoteSnapshot.currentTrack {
            if mediaRemoteSnapshot.isVerifiedQishuiSource {
                updateMediaRemotePlaybackConfirmation(snapshot: mediaRemoteSnapshot)
            }
            cachedStatus = MusicSourceStatus(
                sourceName: "汽水 MediaRemote",
                availability: .qishuiMediaRemoteSynced,
                headline: "已接入汽水实时播放",
                detail: "\(track.title) - \(track.artist)。来源：\(track.sourceName)。\(mediaRemoteSnapshot.diagnostic)",
                checkedAt: mediaRemoteSnapshot.checkedAt
            )
            return cachedStatus
        }

        let snapshot = qishuiAdapter.snapshot()
        latestQishuiSnapshot = snapshot
        lastSourceRefreshAt = snapshot.checkedAt

        guard snapshot.isRunning else {
            latestNowPlayingTrack = nil
            latestMediaRemoteSnapshot = nil
            resetPendingPlaybackOperation(clearTimelineFloor: true)
            previousQishuiProgress = nil
            qishuiStationarySince = nil
            inferredQishuiIsPlaying = nil
            cachedStatus = MusicSourceStatus(
                sourceName: "汽水音乐",
                availability: .qishuiNotRunning,
                headline: "未检测到汽水音乐",
                detail: "当前不显示假播放数据；打开汽水音乐后，顶屿会自动检测运行状态。",
                checkedAt: Date()
            )
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

    private func applyNowPlayingSnapshot(_ snapshot: NowPlayingAXSnapshot) {
        switch snapshot.availability {
        case let .recognized(track):
            latestNowPlayingTrack = track
            resetPendingPlaybackOperation(clearTimelineFloor: false)
            cachedStatus = MusicSourceStatus(
                sourceName: "macOS 播放中",
                availability: .systemNowPlayingRecognized,
                headline: "已完成手动系统诊断",
                detail: "来自 macOS 控制中心“播放中”面板：\(track.rawLine)。该结果只用于诊断，不作为汽水直接适配主线。",
                checkedAt: snapshot.checkedAt
            )
        case .accessibilityRequired:
            latestNowPlayingTrack = nil
            resetPendingPlaybackOperation(clearTimelineFloor: false)
            cachedStatus = MusicSourceStatus(
                sourceName: "macOS 播放中",
                availability: .accessibilityRequired,
                headline: "需要辅助功能权限",
                detail: "读取系统“播放中”面板需要辅助功能权限。该入口仅用于手动诊断。",
                checkedAt: snapshot.checkedAt
            )
        case .controlCenterUnavailable:
            latestNowPlayingTrack = nil
            resetPendingPlaybackOperation(clearTimelineFloor: false)
            cachedStatus = MusicSourceStatus(
                sourceName: "macOS 播放中",
                availability: .systemNowPlayingUnavailable,
                headline: "未找到控制中心",
                detail: "无法读取系统“播放中”面板；该入口只用于手动诊断，不影响汽水直接适配主线。",
                checkedAt: snapshot.checkedAt
            )
        case .nowPlayingUnavailable:
            latestNowPlayingTrack = nil
            resetPendingPlaybackOperation(clearTimelineFloor: false)
            cachedStatus = MusicSourceStatus(
                sourceName: "macOS 播放中",
                availability: .systemNowPlayingUnavailable,
                headline: "系统播放信息不可用",
                detail: "控制中心当前没有暴露可读取的“播放中”内容；不会用假歌名替代。",
                checkedAt: snapshot.checkedAt
            )
        case let .failed(message):
            latestNowPlayingTrack = nil
            resetPendingPlaybackOperation(clearTimelineFloor: false)
            cachedStatus = MusicSourceStatus(
                sourceName: "macOS 播放中",
                availability: .systemNowPlayingUnavailable,
                headline: "系统播放信息读取失败",
                detail: message,
                checkedAt: snapshot.checkedAt
            )
        }
    }

    private func currentMusicState() -> MusicState {
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
                canSeek: !isCachedMediaFocus && (effectiveTrack.duration.map { $0 > 0 } ?? false),
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

        if let track = latestNowPlayingTrack {
            let effectiveIsPlaying = pendingPlaybackTarget(title: track.title, artist: track.artist)
                ?? track.isPlaying
                ?? false
            return MusicState(
                track: realTrack(from: track, statusLine: statusLine),
                isPlaying: effectiveIsPlaying,
                progress: effectiveIsPlaying ? 1 : 0,
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

    private func realTrack(from track: NowPlayingAXTrack, statusLine _: String) -> MusicTrack {
        MusicTrack(
            title: track.title,
            artist: track.artist,
            palette: [Color(red: 0.08, green: 0.66, blue: 0.74), Color(red: 0.18, green: 0.18, blue: 0.22)],
            lyrics: [],
            hasArtwork: false,
            artworkData: nil,
            artworkURL: nil,
            sourceBundleIdentifier: "com.soda.music"
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
