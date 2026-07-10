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

enum MusicControlCommand: Sendable {
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

    var mediaKeyCode: Int {
        switch self {
        case .playPause:
            return 16
        case .nextTrack:
            return 17
        case .previousTrack:
            return 18
        }
    }

    var mediaRemoteCommandID: UInt32 {
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

private struct PendingTrackChangeOperation {
    let command: MusicControlCommand
    let issuedAt: Date
    let baselineIdentity: PlaybackTrackIdentity
    var candidateIdentity: PlaybackTrackIdentity?
    var candidateArtworkURL: URL?
    var candidateFirstSeenAt: Date?
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

@MainActor
final class MusicAdapterCoordinator {
    private let qishuiAdapter = QishuiAdapter()
    private let qishuiAXChangeMonitor = QishuiAXChangeMonitor()
    private let mediaRemoteAdapterStreamSource = MediaRemoteAdapterStreamSource()
    private let mediaRemoteSource = MediaRemoteNowPlayingSource()
    private let mediaKeyController = SystemMediaKeyController()
    private let focusedMediaKeyController = QishuiFocusedMediaKeyController()
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
    private var pendingTrackChangeOperation: PendingTrackChangeOperation?
    private var pendingTrackChangeTimeoutTask: Task<Void, Never>?
    private var trackControlRefreshDeadline: Date?
    private var trackControlBaselineIdentity: PlaybackTrackIdentity?
    private var nextPlaybackOperationID = 0
    private var playbackTimelineFloor: PlaybackTimelineFloor?
    private var cachedPlaybackOverride: CachedPlaybackOverride?
    private var lastCachedOverrideRefreshAttemptAt: Date?
    private var previousQishuiProgress: QishuiProgressSample?
    private var qishuiStationarySince: Date?
    private var inferredQishuiIsPlaying: Bool?
    private var realtimeRefreshInFlight = false
    private var realtimeRefreshQueued = false
    private var playbackPositionRefreshInFlight = false
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
        mediaRemoteAdapterStreamSource.start { [weak self] in
            guard let self else { return }
            self.refreshFromRealtimeSignal(onUpdate: onUpdate)
        }
        mediaRemoteSource.start { [weak self] in
            guard let self else { return }
            self.refreshFromRealtimeSignal(onUpdate: onUpdate)
        }
        qishuiAXChangeMonitor.start { [weak self] _ in
            guard let self else { return }
            self.refreshFromRealtimeSignal(onUpdate: onUpdate)
        }
    }

    func stopRealtimeObservation() {
        mediaRemoteAdapterStreamSource.stop()
        qishuiAXChangeMonitor.stop()
        resetPendingPlaybackOperation(clearTimelineFloor: true)
        finishPendingTrackChangeOperation()
        trackControlRefreshDeadline = nil
        trackControlBaselineIdentity = nil
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
        allowFocusedFallback: Bool = true
    ) -> MusicControlOutcome {
        let canAttemptControl = latestQishuiSnapshot?.isRunning == true || qishuiAdapter.isRunning()
        guard canAttemptControl else {
            latestNowPlayingTrack = nil
            latestMediaRemoteSnapshot = nil
            latestQishuiSnapshot = nil
            resetPendingPlaybackOperation(clearTimelineFloor: true)
            finishPendingTrackChangeOperation()
            trackControlRefreshDeadline = nil
            trackControlBaselineIdentity = nil
            previousQishuiProgress = nil
            qishuiStationarySince = nil
            inferredQishuiIsPlaying = nil
            cachedStatus = MusicSourceStatus(
                sourceName: "汽水音乐",
                availability: .qishuiNotRunning,
                headline: "未检测到汽水音乐",
                detail: "当前不显示假播放数据；打开汽水音乐后，灵动岛会检测运行状态。",
                checkedAt: Date()
            )
            return MusicControlOutcome(status: cachedStatus, didSendCommand: false)
        }

        _ = refreshSourceStatus()
        let controlBaseline = currentMusicState()
        let didPost: Bool
        let usedFocusRetargeting: Bool
        if canSafelySendMediaKeyControlToQishui() {
            didPost = mediaKeyController.post(command)
            usedFocusRetargeting = false
        } else if allowFocusedFallback, let qishuiApp = runningQishuiApplication() {
            didPost = focusedMediaKeyController.post(command, to: qishuiApp)
            usedFocusRetargeting = didPost
        } else {
            resetPendingPlaybackOperation(clearTimelineFloor: false)
            cachedStatus = MusicSourceStatus(
                sourceName: "汽水实时适配器",
                availability: .qishuiMediaRemoteCached,
                headline: "暂不发送\(command.label)",
                detail: allowFocusedFallback
                    ? "未检测到汽水音乐进程；不会把命令发送给当前视频播放器。"
                    : "当前启用严格控制策略，媒体焦点不在汽水音乐时不会短暂激活汽水，也不会把命令发送给当前视频播放器。",
                checkedAt: Date()
            )
            return MusicControlOutcome(status: cachedStatus, didSendCommand: false)
        }

        if command == .playPause, didPost {
            let currentState = currentMusicState()
            beginPendingPlaybackOperation(from: currentState)
        } else if didPost,
                  command == .nextTrack || command == .previousTrack {
            beginPendingTrackChangeOperation(command: command, from: controlBaseline)
        }
        cachedStatus = MusicSourceStatus(
            sourceName: "汽水音乐",
            availability: didPost ? .qishuiControlSent : .accessibilityRequired,
            headline: didPost ? "已发送\(command.label)" : "媒体键发送失败",
            detail: didPost
                ? (usedFocusRetargeting
                    ? "当前系统媒体焦点不在汽水音乐；已短暂激活汽水发送\(command.label)，随后恢复原 App，避免误控视频播放器。"
                    : "已向当前汽水音乐媒体源发送\(command.label)媒体键；等待汽水直接适配源回读真实状态。")
                : "系统没有创建媒体键事件，可能需要重新授权辅助功能权限。",
            checkedAt: Date()
        )
        return MusicControlOutcome(status: cachedStatus, didSendCommand: didPost)
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

    func refreshControlFollowUp() async -> (music: MusicState, status: MusicSourceStatus) {
        if pendingPlaybackOperation != nil || mediaRemoteAdapterStreamSource.hasPendingSeekTimeline() {
            _ = await mediaRemoteAdapterStreamSource.refreshPlaybackPositionAsync()
        }
        let shouldRefreshTrackControl = pendingTrackChangeOperation != nil
            || trackControlRefreshDeadline.map { Date() < $0 } == true
        if shouldRefreshTrackControl {
            qishuiAdapter.invalidateAXCache()
            let snapshot = qishuiAdapter.snapshot()
            if pendingTrackChangeOperation != nil {
                updatePendingTrackChangeConfirmation(snapshot: snapshot)
            } else {
                applyTrackControlFollowUpSnapshot(snapshot)
            }
        } else if trackControlRefreshDeadline != nil {
            trackControlRefreshDeadline = nil
            trackControlBaselineIdentity = nil
        }
        let status = refreshSourceStatus()
        return (currentMusicState(), status)
    }

    func invalidateQishuiCache() {
        qishuiAdapter.invalidateAXCache()
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
            finishPendingTrackChangeOperation()
            trackControlRefreshDeadline = nil
            trackControlBaselineIdentity = nil
            previousQishuiProgress = nil
            qishuiStationarySince = nil
            inferredQishuiIsPlaying = nil
            cachedStatus = MusicSourceStatus(
                sourceName: "汽水音乐",
                availability: .qishuiNotRunning,
                headline: "未检测到汽水音乐",
                detail: "当前不显示假播放数据；打开汽水音乐后，灵动岛会检测运行状态。",
                checkedAt: Date()
            )
            return cachedStatus
        }

        let adapterSnapshot = allowSynchronousRefresh
            ? (mediaRemoteAdapterStreamSource.refreshPlaybackPosition() ?? mediaRemoteAdapterStreamSource.snapshot())
            : mediaRemoteAdapterStreamSource.snapshot()

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
                if pendingTrackChangeOperation != nil {
                    updatePendingTrackChangeConfirmation(snapshot: directSnapshot)
                } else {
                    latestQishuiSnapshot = directSnapshot
                }
                if pendingTrackChangeOperation == nil,
                   let directTrack = directSnapshot.currentTrack {
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
        if pendingTrackChangeOperation != nil {
            updatePendingTrackChangeConfirmation(snapshot: snapshot)
        } else {
            latestQishuiSnapshot = snapshot
        }
        lastSourceRefreshAt = snapshot.checkedAt

        guard snapshot.isRunning else {
            latestNowPlayingTrack = nil
            latestMediaRemoteSnapshot = nil
            resetPendingPlaybackOperation(clearTimelineFloor: true)
            finishPendingTrackChangeOperation()
            trackControlRefreshDeadline = nil
            trackControlBaselineIdentity = nil
            previousQishuiProgress = nil
            qishuiStationarySince = nil
            inferredQishuiIsPlaying = nil
            cachedStatus = MusicSourceStatus(
                sourceName: "汽水音乐",
                availability: .qishuiNotRunning,
                headline: "未检测到汽水音乐",
                detail: "当前不显示假播放数据；打开汽水音乐后，灵动岛会检测运行状态。",
                checkedAt: Date()
            )
            return cachedStatus
        }

        if pendingTrackChangeOperation == nil,
           let track = snapshot.currentTrack {
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
        return refreshSourceStatus(allowSynchronousRefresh: true)
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
            if isCachedMediaFocus,
               let directTrack = latestQishuiSnapshot?.currentTrack {
                let isSameTrack = directTrack.title == effectiveTrack.title
                if !isSameTrack {
                    cachedPlaybackOverride = nil
                    playbackTimelineFloor = nil
                    if let operation = pendingPlaybackOperation,
                       operation.trackIdentity.title != directTrack.title {
                        resetPendingPlaybackOperation(clearTimelineFloor: true)
                    }
                }
                let pendingIsPlaying = pendingPlaybackOperation.flatMap { operation in
                    operation.trackIdentity.title == directTrack.title
                        ? operation.targetIsPlaying
                        : nil
                }
                let effectiveIsPlaying = pendingIsPlaying
                    ?? directTrack.isPlaying
                    ?? inferredQishuiIsPlaying
                    ?? effectiveTrack.isPlaying
                    ?? false
                return MusicState(
                    track: realTrack(from: directTrack, statusLine: statusLine),
                    isPlaying: effectiveIsPlaying,
                    progress: isSameTrack ? effectiveTrack.progress : 0,
                    lyricIndex: 0,
                    elapsedTime: isSameTrack ? effectiveTrack.elapsedTime : nil,
                    duration: isSameTrack ? effectiveTrack.duration : nil,
                    canSeek: false,
                    isPlaybackPending: pendingPlaybackOperation != nil
                )
            }
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
                let optimisticElapsed = operation.targetIsPlaying
                    ? anchorElapsed + Date().timeIntervalSince(operation.issuedAt)
                    : anchorElapsed
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
        if pendingTrackChangeOperation != nil {
            return true
        }
        guard pendingPlaybackOperation == nil,
              let lastCachedOverrideRefreshAttemptAt else { return true }
        return Date().timeIntervalSince(lastCachedOverrideRefreshAttemptAt) >= 1.0
    }

    private func beginPendingTrackChangeOperation(
        command: MusicControlCommand,
        from currentState: MusicState
    ) {
        let operation = PendingTrackChangeOperation(
            command: command,
            issuedAt: Date(),
            baselineIdentity: PlaybackTrackIdentity(
                title: currentState.track.title,
                artist: currentState.track.artist
            ),
            candidateIdentity: nil,
            candidateArtworkURL: nil,
            candidateFirstSeenAt: nil
        )
        pendingTrackChangeOperation = operation
        trackControlRefreshDeadline = Date().addingTimeInterval(3.0)
        trackControlBaselineIdentity = operation.baselineIdentity
        pendingTrackChangeTimeoutTask?.cancel()
        pendingTrackChangeTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            self?.expirePendingTrackChangeOperation(issuedAt: operation.issuedAt)
        }
    }

    private func updatePendingTrackChangeConfirmation(snapshot: QishuiDirectSnapshot) {
        guard var operation = pendingTrackChangeOperation,
              snapshot.checkedAt >= operation.issuedAt,
              let track = snapshot.currentTrack else { return }

        let identity = PlaybackTrackIdentity(title: track.title, artist: track.artist)
        guard !matches(identity, operation.baselineIdentity) else {
            operation.candidateIdentity = nil
            operation.candidateArtworkURL = nil
            operation.candidateFirstSeenAt = nil
            pendingTrackChangeOperation = operation
            return
        }

        if let candidateIdentity = operation.candidateIdentity,
           matches(identity, candidateIdentity),
           operation.candidateArtworkURL == track.artworkURL,
           let candidateFirstSeenAt = operation.candidateFirstSeenAt {
            guard snapshot.checkedAt.timeIntervalSince(candidateFirstSeenAt) >= 0.36 else {
                pendingTrackChangeOperation = operation
                return
            }
        } else {
            operation.candidateIdentity = identity
            operation.candidateArtworkURL = track.artworkURL
            operation.candidateFirstSeenAt = snapshot.checkedAt
            pendingTrackChangeOperation = operation
            return
        }

        latestQishuiSnapshot = snapshot
        previousQishuiProgress = nil
        qishuiStationarySince = nil
        inferredQishuiIsPlaying = track.isPlaying
        resetPendingPlaybackOperation(clearTimelineFloor: true)
        finishPendingTrackChangeOperation()
        cachedStatus = MusicSourceStatus(
            sourceName: "汽水直接适配",
            availability: .qishuiMediaRemoteCached,
            headline: "已确认\(operation.command.label)",
            detail: "汽水窗口已确认曲目切换为 \(track.title) - \(track.artist)；系统媒体焦点仍可由其他 App 持有。",
            checkedAt: snapshot.checkedAt
        )
    }

    private func expirePendingTrackChangeOperation(issuedAt: Date) {
        guard let operation = pendingTrackChangeOperation,
              operation.issuedAt == issuedAt else { return }

        finishPendingTrackChangeOperation()
        cachedStatus = MusicSourceStatus(
            sourceName: "汽水直接适配",
            availability: latestMediaRemoteSnapshot == nil
                ? .qishuiDetectedAXLimited
                : .qishuiMediaRemoteCached,
            headline: "未确认\(operation.command.label)",
            detail: "控制事件已经发送，但汽水窗口没有确认曲目变化；继续保留原歌曲，且不会把控制转交给当前视频播放器。",
            checkedAt: Date()
        )
    }

    private func applyTrackControlFollowUpSnapshot(_ snapshot: QishuiDirectSnapshot) {
        guard snapshot.isRunning,
              let track = snapshot.currentTrack else { return }

        let previousIdentity = latestQishuiSnapshot?.currentTrack.map {
            PlaybackTrackIdentity(title: $0.title, artist: $0.artist)
        }
        let nextIdentity = PlaybackTrackIdentity(title: track.title, artist: track.artist)
        let didChangeFromBaseline = trackControlBaselineIdentity.map {
            !matches($0, nextIdentity)
        } ?? true
        if let previousIdentity,
           !matches(previousIdentity, nextIdentity) {
            previousQishuiProgress = nil
            qishuiStationarySince = nil
            inferredQishuiIsPlaying = track.isPlaying
            resetPendingPlaybackOperation(clearTimelineFloor: true)
        }

        latestQishuiSnapshot = snapshot
        guard didChangeFromBaseline else { return }
        cachedStatus = MusicSourceStatus(
            sourceName: "汽水直接适配",
            availability: .qishuiMediaRemoteCached,
            headline: "已刷新汽水曲目",
            detail: "控制后的确认观察窗已读取 \(track.title) - \(track.artist)；系统媒体焦点仍可由其他 App 持有。",
            checkedAt: snapshot.checkedAt
        )
    }

    private func finishPendingTrackChangeOperation() {
        pendingTrackChangeOperation = nil
        pendingTrackChangeTimeoutTask?.cancel()
        pendingTrackChangeTimeoutTask = nil
    }

    private func updateCachedPlaybackOverride(from track: QishuiDirectTrack, checkedAt: Date) {
        guard let isPlaying = track.isPlaying ?? inferredQishuiIsPlaying else { return }
        let identity = PlaybackTrackIdentity(title: track.title, artist: track.artist)
        let mediaTrack = latestMediaRemoteSnapshot?.currentTrack
        let duration = mediaTrack.flatMap { matches(track: $0, identity: identity) ? $0.duration : nil }
        let elapsedTime: TimeInterval?
        if let progress = track.progress, let duration, duration > 0 {
            elapsedTime = min(max(progress, 0), 1) * duration
        } else if let existing = cachedPlaybackOverride,
                  matches(existing.trackIdentity, identity),
                  let existingElapsed = existing.elapsedTime {
            elapsedTime = existing.isPlaying
                ? existingElapsed + checkedAt.timeIntervalSince(existing.updatedAt)
                : existingElapsed
        } else if let operation = pendingPlaybackOperation,
                  matches(operation.trackIdentity, identity) {
            elapsedTime = operation.anchorElapsed
        } else {
            elapsedTime = mediaTrack?.elapsedTime
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
        let elapsedTime: TimeInterval?
        if operation.targetIsPlaying {
            elapsedTime = track.elapsedTime ?? operation.anchorElapsed
        } else if let anchorElapsed = operation.anchorElapsed {
            elapsedTime = max(track.elapsedTime ?? anchorElapsed, anchorElapsed)
        } else {
            elapsedTime = track.elapsedTime
        }
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
            artworkURL: nil
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
            artworkURL: nil
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
            artworkURL: track.artworkURL
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
            artworkURL: nil
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
            return "媒体键控制需要辅助功能权限"
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
            return "已发送媒体键控制，等待真实状态回读"
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

    private func beginPendingPlaybackOperation(from currentState: MusicState) {
        let replacesPendingOperation = pendingPlaybackOperation != nil
        nextPlaybackOperationID += 1
        let operation = PendingPlaybackOperation(
            id: nextPlaybackOperationID,
            targetIsPlaying: !currentState.isPlaying,
            issuedAt: Date(),
            trackIdentity: PlaybackTrackIdentity(
                title: currentState.track.title,
                artist: currentState.track.artist
            ),
            anchorElapsed: currentState.elapsedTime,
            anchorDuration: currentState.duration,
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
        let timeoutNanoseconds: UInt64 = replacesPendingOperation ? 1_200_000_000 : 4_000_000_000
        pendingPlaybackTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            guard !Task.isCancelled else { return }
            self?.expirePendingPlaybackOperation(id: operation.id)
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
        guard let operation = pendingPlaybackOperation,
              operation.id == id else { return }

        if !operation.targetIsPlaying {
            let directState = cachedPlaybackOverride.flatMap { override -> Bool? in
                guard override.updatedAt >= operation.issuedAt,
                      matches(override.trackIdentity, operation.trackIdentity) else { return nil }
                return override.isPlaying
            }
            if directState != operation.targetIsPlaying {
                playbackTimelineFloor = nil
            }
        }
        finishPendingPlaybackOperation(id: id)
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

    private func canSafelySendMediaKeyControlToQishui() -> Bool {
        if mediaRemoteAdapterStreamSource.hasCurrentVerifiedQishuiSource() {
            return true
        }

        guard let snapshot = latestMediaRemoteSnapshot,
              snapshot.isVerifiedQishuiSource,
              let track = snapshot.currentTrack else {
            return false
        }
        return track.sourceName == "MediaRemote Now Playing"
    }

    private func runningQishuiApplication() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.soda.music").first
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

private final class SystemMediaKeyController {
    @discardableResult
    func post(_ command: MusicControlCommand) -> Bool {
        let didPostDown = postAuxKey(command.mediaKeyCode, keyState: .down)
        usleep(20_000)
        let didPostUp = postAuxKey(command.mediaKeyCode, keyState: .up)
        return didPostDown && didPostUp
    }

    @discardableResult
    private func postAuxKey(_ keyCode: Int, keyState: MediaKeyState) -> Bool {
        let data1 = (keyCode << 16) | keyState.rawValue
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(keyState.rawValue)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )?.cgEvent else {
            return false
        }

        event.post(tap: .cghidEventTap)
        return true
    }
}

final class QishuiFocusedMediaKeyController {
    @discardableResult
    func post(_ command: MusicControlCommand, to qishuiApp: NSRunningApplication) -> Bool {
        let previousApp = NSWorkspace.shared.frontmostApplication
        let shouldRestorePrevious = previousApp?.processIdentifier != qishuiApp.processIdentifier

        guard shouldRestorePrevious else {
            return QishuiWindowControlClicker().post(command, to: qishuiApp)
        }

        let qishuiProcessIdentifier = qishuiApp.processIdentifier
        let previousProcessIdentifier = previousApp?.processIdentifier
        DispatchQueue.global(qos: .userInitiated).async {
            guard let qishuiApp = NSRunningApplication(processIdentifier: qishuiProcessIdentifier),
                  qishuiApp.activate(options: []) else { return }
            usleep(180_000)
            let qishuiStillOwnsFocus = DispatchQueue.main.sync {
                NSWorkspace.shared.frontmostApplication?.processIdentifier == qishuiProcessIdentifier
            }
            guard qishuiStillOwnsFocus else { return }
            _ = QishuiWindowControlClicker().post(command, to: qishuiApp)

            usleep(140_000)
            DispatchQueue.main.async {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == qishuiProcessIdentifier,
                      let previousProcessIdentifier,
                      let previousApp = NSRunningApplication(processIdentifier: previousProcessIdentifier) else {
                    return
                }
                previousApp.activate(options: [])
            }
        }
        return true
    }
}

private final class QishuiWindowControlClicker {
    @discardableResult
    func post(_ command: MusicControlCommand, to qishuiApp: NSRunningApplication) -> Bool {
        guard AXIsProcessTrusted(),
              let windowFrame = focusedWindowFrame(processIdentifier: qishuiApp.processIdentifier),
              windowFrame.width >= 400,
              windowFrame.height >= 300 else {
            return false
        }

        let horizontalOffset: CGFloat
        // Qishui 2.9.1 anchors its three transport controls around the window center.
        switch command {
        case .previousTrack:
            horizontalOffset = -86
        case .playPause:
            horizontalOffset = 0
        case .nextTrack:
            horizontalOffset = 86
        }

        let controlPoint = CGPoint(
            x: windowFrame.midX + horizontalOffset,
            y: windowFrame.maxY - 44
        )
        guard windowFrame.contains(controlPoint),
              let source = CGEventSource(stateID: .hidSystemState),
              let mouseDown = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: controlPoint,
                mouseButton: .left
              ),
              let mouseUp = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: controlPoint,
                mouseButton: .left
              ) else {
            return false
        }

        let originalMouseLocation = CGEvent(source: nil)?.location
        mouseDown.post(tap: .cghidEventTap)
        usleep(20_000)
        mouseUp.post(tap: .cghidEventTap)
        if let originalMouseLocation,
           let restoreMouse = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: originalMouseLocation,
            mouseButton: .left
           ) {
            usleep(20_000)
            restoreMouse.post(tap: .cghidEventTap)
        }
        return true
    }

    private func focusedWindowFrame(processIdentifier: pid_t) -> CGRect? {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success,
        let windowValue,
        CFGetTypeID(windowValue) == AXUIElementGetTypeID() else {
            return nil
        }

        let window = windowValue as! AXUIElement
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success,
        let positionValue,
        let sizeValue,
        CFGetTypeID(positionValue) == AXValueGetTypeID(),
        CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }
}

private enum MediaKeyState: Int {
    case down = 0xA00
    case up = 0xB00
}
