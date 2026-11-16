import AppKit
import Foundation
import MusicUsageDiagnostics
import SwiftUI

/// Callbacks from the Qishui adapter into the coordinator. The adapter holds the
/// host weakly; the coordinator owns the adapter.
private struct ControlDispatchResult {
    let didPress: Bool
    let diagnostic: String
}

@MainActor
protocol QishuiMusicAdapterHost: AnyObject {
    var qishuiForegroundSource: MusicSourceID? { get }
    var qishuiUsage: MusicUsageEmitter { get }
    var lyricPipeline: QishuiLyricPipeline { get }
    /// Realtime observation is running.
    var qishuiIsObserving: Bool { get }
    var qishuiSeeks: SeekCoordinator { get }
    func qishuiHasCompetingPlayback(excluding source: MusicSourceID) -> Bool
    func qishuiPublish()
    func qishuiRecord(_ name: String, fields: [String: String])
    /// Has side effects (selector update, `source_change`, seek invalidation):
    /// call it exactly where the coordinator did.
    func qishuiSelectedSource() -> MusicSourceID?
    /// The selector's last selection, read without updating it.
    var qishuiSelectorSource: MusicSourceID? { get }
    /// Updates the selector like `qishuiSelectedSource()`; same call-site rule.
    func qishuiControlSelection() -> MusicSourceSelection
    func qishuiSelectedMusicState() -> MusicState
    func qishuiStaleDisplayedSourceOutcome(
        command: MusicControlCommand,
        binding: DisplayedMusicControlBinding,
        selectedSource: MusicSourceID?
    ) -> MusicControlOutcome
}

/// Qishui (汽水音乐) state, status ingestion and state building, owned apart from the coordinator.
///
/// Step 4.3 moved the stored properties here. Step 4.4 moved stream and snapshot
/// ingestion, status text, state building and pending playback confirmation; the
/// coordinator forwards `refreshSourceStatus` and calls back through `host`.
/// Later steps move identity refresh, lifecycle hooks and controls.
/// See Docs/engineering/COORDINATOR_SPLIT_STEP4.md.
@MainActor
final class QishuiMusicAdapter {
    let qishuiAdapter = QishuiAdapter()
    let qishuiAXChangeMonitor = QishuiAXChangeMonitor()
    let qishuiSemanticAXController = QishuiSemanticAXController()
    let qishuiWorkQueues = QishuiWorkQueues()
    let mediaRemoteAdapterStreamSource = MediaRemoteAdapterStreamSource()
    let nowPlayingBridge = NowPlayingAXBridge()
    var latestQishuiSnapshot: QishuiDirectSnapshot?
    var qishuiIdentityRefreshInFlight = false
    var qishuiIdentityRefreshGeneration: UInt64 = 0
    var lastQishuiTransitionIdentityRequested: QishuiLyricIdentity?
    var lastQishuiIdentityRefreshAt = Date.distantPast
    var qishuiLifecycleMetadataTask: Task<Void, Never>?
    var latestQishuiControlAvailability: QishuiControlAvailability = .unknown
    var latestMediaRemoteSnapshot: MediaRemoteNowPlayingSnapshot?
    var lastSourceRefreshAt: Date?
    var lastPlaybackPositionRefreshAt: Date?
    var controlGeneration = 0
    var qishuiControlAvailabilityGeneration: UInt64 = 0
    var qishuiControlAvailabilityRefreshInFlight = false
    var qishuiControlAvailabilityRefreshQueued = false
    var lastQishuiControlHealthCheckAt: Date?
    var qishuiControlAvailabilityRetryAttempt = 0
    var qishuiControlAvailabilityRetryTask: Task<Void, Never>?
    var lastTrackControlStartedAt: Date?
    let playback = PlaybackOperationTracker()
    var qishuiInference = QishuiPlaybackInference()
    var playbackPositionRefreshInFlight = false
    var qishuiLifecycleObservers: [NSObjectProtocol] = []
    var cachedStatus = MusicSourceStatus(
        sourceName: "汽水音乐",
        availability: .preview,
        headline: "等待汽水音乐真实数据",
        detail: "当前不显示假歌曲；主线正在读取汽水音乐本地状态和可发现 IPC。",
        checkedAt: Date()
    )
    weak var host: QishuiMusicAdapterHost?
    private let automaticRefreshInterval: TimeInterval = 5.0
    private let playbackPositionRefreshInterval: TimeInterval = 2.0

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

    func applyQishuiDirectSnapshot(
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
        host?.qishuiUsage.recordDirectIdentityIfChanged(
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

    func markQishuiNotRunning(checkedAt: Date = Date(), reason: String = "inventory") {
        host?.qishuiRecord("source_unavailable", fields: [
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

    func clearQishuiPlaybackState() {
        lastQishuiTransitionIdentityRequested = nil
        host?.lyricPipeline.invalidate()
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

    func refreshSourceStatusIfNeeded() -> MusicSourceStatus? {
        let now = Date()
        if let lastSourceRefreshAt = lastSourceRefreshAt,
           now.timeIntervalSince(lastSourceRefreshAt) < automaticRefreshInterval {
            return nil
        }
        return refreshSourceStatus()
    }

    func shouldRefreshPlaybackPosition(_ state: MusicState) -> Bool {
        guard state.isPlaying,
              state.duration != nil,
              state.elapsedTime != nil else { return false }

        let now = Date()
        guard lastPlaybackPositionRefreshAt.map({ now.timeIntervalSince($0) >= playbackPositionRefreshInterval }) ?? true else {
            return false
        }
        return true
    }

    func shouldRefreshCachedPlaybackState() -> Bool {
        guard cachedStatus.availability == .qishuiMediaRemoteCached else { return false }
        return playback.cachedOverrideRefreshIsDue
    }

    func refreshPlaybackPositionStatus() -> MusicSourceStatus {
        lastPlaybackPositionRefreshAt = Date()
        schedulePlaybackPositionRefresh()
        return refreshSourceStatus()
    }

    func schedulePlaybackPositionRefresh() {
        guard !playbackPositionRefreshInFlight else { return }
        playbackPositionRefreshInFlight = true
        lastPlaybackPositionRefreshAt = Date()
        Task { [weak self] in
            guard let self else { return }
            _ = await self.mediaRemoteAdapterStreamSource.refreshPlaybackPositionAsync()
            _ = self.refreshSourceStatus()
            self.playbackPositionRefreshInFlight = false
            self.host?.qishuiPublish()
        }
    }

    func qishuiSourceCandidate() -> MusicSourceCandidate {
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
                && (host?.qishuiForegroundSource == .qishui
                    || cachedStatus.availability != .qishuiNotRunning),
            hasTrack: hasTrack,
            playback: playback,
            isCached: cachedStatus.availability == .qishuiMediaRemoteCached
        )
    }

    func applyNowPlayingSnapshot(_ snapshot: NowPlayingAXSnapshot) {
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

    func currentQishuiMusicState() -> MusicState {
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
            host?.qishuiUsage.recordAdmissionEvidenceIfChanged(
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
                hasCompetingPlayback: host?.qishuiHasCompetingPlayback(excluding: .qishui) ?? true
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
        let lyricSnapshot = host?.lyricPipeline.lyrics(for: track)
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
        if host?.lyricPipeline.timedIdentity == lyricSnapshot?.identity,
           let current = lyricSnapshot?.lines.first {
            result.timedWords = QishuiTimedLyricParser.words(
                for: current, at: track.elapsedTime, in: host?.lyricPipeline.timedLines ?? [], trackDuration: track.duration
            )
        }
        return result
    }

    private func realTrack(from track: QishuiDirectTrack, statusLine _: String) -> MusicTrack {
        let lyrics = host?.lyricPipeline.lyrics(for: track)
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

    func placeholderTrack(statusLine _: String) -> MusicTrack {
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
    func beginPendingPlaybackOperation(requestedState: MusicState) -> Int {
        playback.begin(
            requestedState: requestedState,
            baselineSampleID: latestMediaRemoteSnapshot?.sampleID ?? 0,
            baselineSampleSource: latestMediaRemoteSnapshot?.sampleSource ?? .unknown
        )
    }

    func schedulePendingPlaybackConfirmationTimeout(id: Int) {
        playback.scheduleConfirmationTimeout(id: id) { [weak self] id in
            self?.expirePendingPlaybackOperation(id: id)
        }
    }

    private func recordPlaybackConfirmed(
        _ operation: PendingPlaybackOperation,
        evidence: String,
        confirmedAt: Date
    ) {
        host?.qishuiRecord("playback_confirmed", fields: [
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
            host?.qishuiRecord("playback_confirmation_timeout", fields: [
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

    func rollbackPendingPlaybackOperation(
        id: Int,
        status: MusicSourceStatus
    ) {
        guard playback.rollback(id: id) else { return }
        cachedStatus = status
        host?.qishuiPublish()
    }

    // MARK: Identity refresh and lifecycle (coordinator split step 4.5)

    /// Qishui part of the coordinator's launch observer, called at the original
    /// position, before the 250ms wait.
    func resetForQishuiLaunch() {
        controlGeneration += 1
        cancelQishuiControlAvailabilityScheduling()
        latestQishuiControlAvailability = .unknown
        clearQishuiPlaybackState()
        lastSourceRefreshAt = nil
        qishuiAdapter.invalidateAXCache()
        qishuiSemanticAXController.invalidateCache()
        mediaRemoteAdapterStreamSource.rebindAfterQishuiRelaunch()
        scheduleQishuiControlAvailabilityRefresh()
        scheduleQishuiLifecycleMetadataRefresh()
    }

    func refreshForegroundQishuiState() async {
        guard host?.qishuiForegroundSource == .qishui,
              let processIdentifier = QishuiProcessLocator.application()?.processIdentifier else { return }
        _ = await refreshQishuiAXMetadata(processIdentifier: processIdentifier)
    }

    func scheduleQishuiLifecycleMetadataRefresh() {
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
                guard !Task.isCancelled, let self, self.host?.qishuiIsObserving == true,
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
        guard let requestedSeekGeneration = host?.qishuiSeeks.generation else { return false }
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
        guard !Task.isCancelled, let host, host.qishuiIsObserving,
              requestedControlGeneration == controlGeneration,
              host.qishuiSeeks.isCurrent(requestedSeekGeneration),
              snapshot.processIdentifier == processIdentifier,
              QishuiProcessLocator.isRunning(processIdentifier: processIdentifier),
              QishuiIdentityRefreshPolicy.accepts(
                  requested: requestedIdentity, current: qishuiMediaIdentity(),
                  result: snapshot.currentTrack.map {
                      .init(processIdentifier: processIdentifier, title: $0.title, artist: $0.artist)
                  }
              ) else { return false }
        _ = applyQishuiDirectSnapshot(snapshot)
        host.qishuiPublish()
        return snapshot.currentTrack != nil
    }

    private func scheduleQishuiTransitionIdentityReconciliation() {
        guard let host, host.qishuiIsObserving, host.qishuiSelectedSource() == .qishui,
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
        host.qishuiRecord("identity_reconcile_requested", fields: [
            "source": "qishui",
            "direct_age_ms": String(max(0, Int(Date().timeIntervalSince(snapshot.checkedAt) * 1_000)))
        ])
        scheduleQishuiIdentityRefresh(force: true)
    }

    func scheduleQishuiIdentityRefresh(force: Bool = false) {
        guard let host, host.qishuiIsObserving,
              host.qishuiSelectedSource() == .qishui,
              !qishuiIdentityRefreshInFlight,
              (force || Date().timeIntervalSince(lastQishuiIdentityRefreshAt) >= 1.0),
              let processIdentifier = QishuiProcessLocator.application()?.processIdentifier else {
            return
        }
        qishuiIdentityRefreshInFlight = true
        qishuiIdentityRefreshGeneration &+= 1
        let generation = qishuiIdentityRefreshGeneration
        let requestedControlGeneration = controlGeneration
        let requestedSeekGeneration = host.qishuiSeeks.generation
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
                guard let host = self.host, host.qishuiIsObserving,
                      host.qishuiSelectedSource() == .qishui,
                      requestedControlGeneration == self.controlGeneration,
                      host.qishuiSeeks.isCurrent(requestedSeekGeneration),
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
                host.qishuiPublish()
            }
        }
    }

    private func qishuiMediaIdentity() -> QishuiLyricIdentity? {
        guard let track = latestMediaRemoteSnapshot?.currentTrack,
              track.sourceBundleIdentifier == QishuiProcessLocator.bundleIdentifier,
              let processIdentifier = track.sourceProcessIdentifier else { return nil }
        return .init(processIdentifier: processIdentifier, title: track.title, artist: track.artist)
    }

    // MARK: Control availability and health check (coordinator split step 4.6)

    /// Periodic health check, called from the coordinator's `tick` at the original position.
    func scheduleControlHealthCheckIfNeeded() {
        if host?.qishuiIsObserving == true,
           latestQishuiControlAvailability == .available,
           !qishuiControlAvailabilityRefreshInFlight,
           QishuiProcessLocator.isRunning(),
           MusicControlRecoveryPolicy.needsHealthCheck(
               lastCheck: lastQishuiControlHealthCheckAt, now: Date()
           ) {
            scheduleQishuiControlAvailabilityRefresh()
        }
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
            host?.qishuiPublish()
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
        host?.qishuiPublish()
        if availability != .available {
            scheduleQishuiControlAvailabilityRetry()
        }
    }

    func probeQishuiControlAvailability(
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

    func runningQishuiApplication() -> NSRunningApplication? {
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

    func scheduleQishuiControlAvailabilityRefresh(
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
            host?.qishuiPublish()
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
                    self.host?.qishuiPublish()
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

    func cancelQishuiControlAvailabilityScheduling() {
        lastQishuiControlHealthCheckAt = nil
        qishuiControlAvailabilityGeneration &+= 1
        qishuiControlAvailabilityRefreshInFlight = false
        qishuiControlAvailabilityRefreshQueued = false
        qishuiControlAvailabilityRetryAttempt = 0
        qishuiControlAvailabilityRetryTask?.cancel()
        qishuiControlAvailabilityRetryTask = nil
    }

    // MARK: Control sending and seek (coordinator split step 4.7)

    /// Qishui branch of the coordinator's `performControlImplementation`, after the
    /// displayed-source binding and authorization were established there.
    func performQishuiControl(
        _ command: MusicControlCommand,
        binding: DisplayedMusicControlBinding,
        authorization: MusicControlAuthorization
    ) async -> MusicControlOutcome {
        guard let host else { return MusicControlOutcome(status: cachedStatus, didSendCommand: false) }
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
            guard authorization.isValid(for: host.qishuiControlSelection()) else {
                return host.qishuiStaleDisplayedSourceOutcome(
                    command: command,
                    binding: binding,
                    selectedSource: host.qishuiSelectorSource
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
        guard authorization.isValid(for: host.qishuiControlSelection()) else {
            return host.qishuiStaleDisplayedSourceOutcome(
                command: command,
                binding: binding,
                selectedSource: host.qishuiSelectorSource
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
            host.qishuiPublish()
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
            host.qishuiPublish()
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
                host.qishuiPublish()
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

    /// Qishui branch of the coordinator's `performSeek`, after the seek generation,
    /// binding and authorization were established there.
    func performQishuiSeek(
        to progress: Double,
        interaction: MusicSeekInteraction,
        authorization: MusicControlAuthorization,
        seekGeneration: UInt64
    ) async -> (music: MusicState, status: MusicSourceStatus) {
        guard let host else { return (currentQishuiMusicState(), cachedStatus) }
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
            hasCompetingPlayback: { host.qishuiHasCompetingPlayback(excluding: .qishui) }
        ) {
        case let .rejected(status):
            return (currentQishuiMusicState(), status)
        case let .admitted(admittedTrack, admittedDuration, admittedProgress, admittedElapsed):
            track = admittedTrack
            duration = admittedDuration
            targetProgress = admittedProgress
            targetElapsed = admittedElapsed
        }

        guard authorization.isValid(for: host.qishuiControlSelection()) else {
            return (host.qishuiSelectedMusicState(), SeekCoordinator.Status.sourceSwitchedBeforeSend())
        }

        let seekControlGeneration = controlGeneration
        let didSeek = await mediaRemoteAdapterStreamSource.seek(
            to: targetElapsed,
            coalescingDelayNanoseconds: interaction.coalescingDelayNanoseconds
        )
        guard authorization.isValid(for: host.qishuiControlSelection()) else {
            return (host.qishuiSelectedMusicState(), SeekCoordinator.Status.sourceSwitchedBeforeResult())
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
            host.qishuiSeeks.scheduleResumeIfPaused(
                identity: .init(processIdentifier: processIdentifier, title: track.title, artist: track.artist),
                generation: seekGeneration,
                isStillValid: { [weak self] in
                    guard let self, let host = self.host else { return false }
                    return host.qishuiIsObserving
                        && self.controlGeneration == seekControlGeneration
                        && host.qishuiSelectedSource() == .qishui
                },
                refresh: { [weak self] in
                    await self?.mediaRemoteAdapterStreamSource.refreshPlaybackPositionAsync()
                },
                startPlayback: { [weak self] processIdentifier in
                    guard let self else { return }
                    let result = await self.pressSemanticControl(.playPause, processIdentifier: processIdentifier)
                    self.host?.qishuiRecord("seek_start_playback", fields: ["outcome": result.didPress ? "sent" : "unavailable"])
                    self.schedulePlaybackPositionRefresh()
                }
            )
        }
        return (optimisticMusic, status)
    }

    /// Qishui part of the coordinator's `refreshControlFollowUp`.
    func refreshQishuiControlFollowUp(forcePositionRefresh: Bool) async {
        if (forcePositionRefresh
            || playback.hasPendingOperation
            || mediaRemoteAdapterStreamSource.hasPendingSeekTimeline()),
           !playbackPositionRefreshInFlight {
            playbackPositionRefreshInFlight = true
            _ = await mediaRemoteAdapterStreamSource.refreshPlaybackPositionAsync()
            playbackPositionRefreshInFlight = false
        }
        _ = refreshSourceStatus()
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
        host?.qishuiRecord("control_dispatch", fields: [
            "command": MusicAdapterCoordinator.commandLabel(command),
            "source": "qishui",
            "queue_wait_ms": String(measured.1),
            "press_ms": String(measured.2),
            "dispatch_path": measured.0.dispatchPath ?? "not_sent"
        ])
        return measured.0
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
}
