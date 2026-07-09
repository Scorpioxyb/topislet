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

enum MusicControlCommand {
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
    private var pendingPlaybackState: Bool?
    private var pendingPlaybackStateIssuedAt: Date?
    private var previousQishuiProgress: QishuiProgressSample?
    private var qishuiStationarySince: Date?
    private var inferredQishuiIsPlaying: Bool?
    private var realtimeRefreshInFlight = false
    private var realtimeRefreshQueued = false
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
            pendingPlaybackState = nil
            pendingPlaybackStateIssuedAt = nil
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
        let didPost: Bool
        let usedFocusRetargeting: Bool
        if canSafelySendMediaKeyControlToQishui() {
            didPost = mediaKeyController.post(command)
            usedFocusRetargeting = false
        } else if allowFocusedFallback, let qishuiApp = runningQishuiApplication() {
            didPost = focusedMediaKeyController.post(command, to: qishuiApp)
            usedFocusRetargeting = didPost
        } else {
            pendingPlaybackState = nil
            pendingPlaybackStateIssuedAt = nil
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
            let currentPlaybackState = latestMediaRemoteSnapshot?.currentTrack?.isPlaying
                ?? latestQishuiSnapshot?.currentTrack?.isPlaying
                ?? inferredQishuiIsPlaying
                ?? latestNowPlayingTrack?.isPlaying
                ?? false
            pendingPlaybackState = !currentPlaybackState
            pendingPlaybackStateIssuedAt = Date()
        } else if command == .nextTrack || command == .previousTrack {
            latestNowPlayingTrack = nil
            latestMediaRemoteSnapshot = nil
            latestQishuiSnapshot = nil
            previousQishuiProgress = nil
            qishuiStationarySince = nil
            inferredQishuiIsPlaying = nil
            pendingPlaybackState = nil
            pendingPlaybackStateIssuedAt = nil
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
        let status = shouldRefreshPlaybackPosition(state)
            ? refreshPlaybackPositionStatus()
            : refreshSourceStatusIfNeeded()
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

    func seek(to progress: Double) -> (music: MusicState, status: MusicSourceStatus) {
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
        guard mediaRemoteAdapterStreamSource.seek(to: targetElapsed) else {
            cachedStatus = MusicSourceStatus(
                sourceName: "汽水实时适配器",
                availability: .systemNowPlayingUnavailable,
                headline: "进度跳转失败",
                detail: "已尝试向汽水音乐发送跳转请求，但底层适配器没有确认成功；界面不会假装已经跳转。",
                checkedAt: Date()
            )
            return (currentMusicState(), cachedStatus)
        }

        let refreshedSnapshot = mediaRemoteAdapterStreamSource.refreshOnce()
        if refreshedSnapshot.currentTrack != nil {
            latestMediaRemoteSnapshot = refreshedSnapshot
            lastSourceRefreshAt = refreshedSnapshot.checkedAt
        }

        cachedStatus = MusicSourceStatus(
            sourceName: "汽水实时适配器",
            availability: .qishuiControlSent,
            headline: "已请求跳转播放进度",
            detail: "已向汽水音乐发送跳转到 \(formatTime(targetElapsed)) 的请求，等待实时适配源回读确认。",
            checkedAt: Date()
        )
        return (currentMusicState(), cachedStatus)
    }

    func refreshControlFollowUp() -> (music: MusicState, status: MusicSourceStatus) {
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
            pendingPlaybackState = nil
            pendingPlaybackStateIssuedAt = nil
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
            updateMediaRemotePlaybackConfirmation(track: track, checkedAt: adapterSnapshot.checkedAt)
            let isCurrentMediaFocus = mediaRemoteAdapterStreamSource.hasCurrentVerifiedQishuiSource()
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
            updateMediaRemotePlaybackConfirmation(track: track, checkedAt: mediaRemoteSnapshot.checkedAt)
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
            pendingPlaybackState = nil
            pendingPlaybackStateIssuedAt = nil
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

        if let track = snapshot.currentTrack {
            updateQishuiPlaybackInference(track: track, checkedAt: snapshot.checkedAt)
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

    private func refreshPlaybackPositionStatus() -> MusicSourceStatus {
        lastPlaybackPositionRefreshAt = Date()
        return refreshSourceStatus(allowSynchronousRefresh: true)
    }

    private func applyNowPlayingSnapshot(_ snapshot: NowPlayingAXSnapshot) {
        switch snapshot.availability {
        case let .recognized(track):
            latestNowPlayingTrack = track
            pendingPlaybackState = nil
            pendingPlaybackStateIssuedAt = nil
            cachedStatus = MusicSourceStatus(
                sourceName: "macOS 播放中",
                availability: .systemNowPlayingRecognized,
                headline: "已完成手动系统诊断",
                detail: "来自 macOS 控制中心“播放中”面板：\(track.rawLine)。该结果只用于诊断，不作为汽水直接适配主线。",
                checkedAt: snapshot.checkedAt
            )
        case .accessibilityRequired:
            latestNowPlayingTrack = nil
            pendingPlaybackState = nil
            pendingPlaybackStateIssuedAt = nil
            cachedStatus = MusicSourceStatus(
                sourceName: "macOS 播放中",
                availability: .accessibilityRequired,
                headline: "需要辅助功能权限",
                detail: "读取系统“播放中”面板需要辅助功能权限。该入口仅用于手动诊断。",
                checkedAt: snapshot.checkedAt
            )
        case .controlCenterUnavailable:
            latestNowPlayingTrack = nil
            pendingPlaybackState = nil
            pendingPlaybackStateIssuedAt = nil
            cachedStatus = MusicSourceStatus(
                sourceName: "macOS 播放中",
                availability: .systemNowPlayingUnavailable,
                headline: "未找到控制中心",
                detail: "无法读取系统“播放中”面板；该入口只用于手动诊断，不影响汽水直接适配主线。",
                checkedAt: snapshot.checkedAt
            )
        case .nowPlayingUnavailable:
            latestNowPlayingTrack = nil
            pendingPlaybackState = nil
            pendingPlaybackStateIssuedAt = nil
            cachedStatus = MusicSourceStatus(
                sourceName: "macOS 播放中",
                availability: .systemNowPlayingUnavailable,
                headline: "系统播放信息不可用",
                detail: "控制中心当前没有暴露可读取的“播放中”内容；不会用假歌名替代。",
                checkedAt: snapshot.checkedAt
            )
        case let .failed(message):
            latestNowPlayingTrack = nil
            pendingPlaybackState = nil
            pendingPlaybackStateIssuedAt = nil
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
            let liveTrack = liveMediaRemoteTrack(from: track, checkedAt: snapshot.checkedAt)
            return MusicState(
                track: realTrack(from: liveTrack, statusLine: statusLine),
                isPlaying: liveTrack.isPlaying ?? false,
                progress: liveTrack.progress,
                lyricIndex: 0,
                elapsedTime: liveTrack.elapsedTime,
                duration: liveTrack.duration,
                canSeek: !isCachedMediaFocus && (liveTrack.duration.map { $0 > 0 } ?? false),
                isPlaybackPending: pendingPlaybackState != nil
            )
        }

        if let track = latestQishuiSnapshot?.currentTrack {
            let effectiveIsPlaying = track.isPlaying
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
                isPlaybackPending: pendingPlaybackState != nil
            )
        }

        if let track = latestNowPlayingTrack {
            let effectiveIsPlaying = track.isPlaying ?? false
            return MusicState(
                track: realTrack(from: track, statusLine: statusLine),
                isPlaying: effectiveIsPlaying,
                progress: effectiveIsPlaying ? 1 : 0,
                lyricIndex: 0,
                elapsedTime: nil,
                duration: nil,
                canSeek: false,
                isPlaybackPending: pendingPlaybackState != nil
            )
        }

        return MusicState(
            track: placeholderTrack(statusLine: statusLine),
            isPlaying: false,
            progress: 0,
            lyricIndex: 0,
            elapsedTime: nil,
            duration: nil,
            canSeek: false,
            isPlaybackPending: pendingPlaybackState != nil
        )
    }

    private func liveMediaRemoteTrack(
        from track: MediaRemoteNowPlayingTrack,
        checkedAt: Date
    ) -> MediaRemoteNowPlayingTrack {
        guard track.isPlaying == true,
              let elapsed = track.elapsedTime,
              let duration = track.duration,
              duration > 0 else {
            return track
        }

        let liveElapsed = min(max(elapsed + Date().timeIntervalSince(checkedAt), 0), duration)
        let liveProgress = min(max(liveElapsed / duration, 0), 1)
        return MediaRemoteNowPlayingTrack(
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
        updatePendingPlaybackConfirmation(checkedAt: checkedAt)
    }

    private func updatePendingPlaybackConfirmation(checkedAt: Date) {
        guard let pendingPlaybackState else { return }

        if let inferredQishuiIsPlaying, inferredQishuiIsPlaying == pendingPlaybackState {
            self.pendingPlaybackState = nil
            pendingPlaybackStateIssuedAt = nil
            return
        }

        guard let issuedAt = pendingPlaybackStateIssuedAt else { return }
        if checkedAt.timeIntervalSince(issuedAt) >= 2.2 {
            self.pendingPlaybackState = nil
            pendingPlaybackStateIssuedAt = nil
        }
    }

    private func updateMediaRemotePlaybackConfirmation(track: MediaRemoteNowPlayingTrack, checkedAt: Date) {
        if let pendingPlaybackState,
           let isPlaying = track.isPlaying,
           pendingPlaybackState == isPlaying {
            self.pendingPlaybackState = nil
            pendingPlaybackStateIssuedAt = nil
            return
        }

        guard let issuedAt = pendingPlaybackStateIssuedAt else { return }
        if checkedAt.timeIntervalSince(issuedAt) >= 1.2 {
            pendingPlaybackState = nil
            pendingPlaybackStateIssuedAt = nil
        }
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

        if shouldRestorePrevious {
            qishuiApp.activate(options: [])
            usleep(180_000)
        }

        let didPost = SystemMediaKeyController().post(command)

        if shouldRestorePrevious, let previousApp {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                previousApp.activate(options: [])
            }
        }

        return didPost
    }
}

private enum MediaKeyState: Int {
    case down = 0xA00
    case up = 0xB00
}
