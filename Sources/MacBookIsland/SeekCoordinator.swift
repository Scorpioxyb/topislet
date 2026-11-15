import Foundation

/// Coordinator-side half of a guarded seek (GLOBAL_PLAN 4.2, step 3).
///
/// Owns which seek is current, the admission check before a Qishui seek is
/// sent, the status shown for each way a seek can end, the follow-up that
/// resumes a paused song after a seek lands, and the anonymous usage fields.
/// `MusicAdapterCoordinator` still owns source selection, control
/// authorization, sending and publishing; `IslandModel` still decides when the
/// displayed position counts as confirmed.
@MainActor
final class SeekCoordinator {
    enum QishuiAdmission {
        case rejected(MusicSourceStatus)
        case admitted(
            track: MediaRemoteNowPlayingTrack,
            duration: TimeInterval,
            targetProgress: Double,
            targetElapsed: TimeInterval
        )
    }

    /// What one post-seek sample means for the resume follow-up.
    enum ResumeDecision: Equatable {
        /// No usable sample yet, or the play state is unknown.
        case keepWaiting
        /// Another song, or the source is already playing: never toggle it.
        case stop
        /// Same song, observed paused: seeking expresses play intent.
        case startPlayback
    }

    private(set) var generation: UInt64 = 0
    private var resumeTask: Task<Void, Never>?
    private let resumePollInterval: Duration
    private let resumePollLimit: Int

    init(resumePollInterval: Duration = .milliseconds(250), resumePollLimit: Int = 12) {
        self.resumePollInterval = resumePollInterval
        self.resumePollLimit = resumePollLimit
    }

    var hasPendingResume: Bool { resumeTask != nil }

    /// Waits for the scheduled resume, if any, to finish. Tests use this
    /// instead of a fixed sleep, which is flaky on a busy CI runner.
    func waitForResume() async {
        await resumeTask?.value
    }

    /// Starts a new seek. It supersedes the previous one, including any
    /// resume follow-up that seek scheduled.
    @discardableResult
    func begin() -> UInt64 {
        generation &+= 1
        cancelResume()
        return generation
    }

    func isCurrent(_ generation: UInt64) -> Bool {
        generation == self.generation
    }

    func cancelResume() {
        resumeTask?.cancel()
        resumeTask = nil
    }

    /// After a Qishui seek is sent, polls up to `resumePollLimit` fresh samples
    /// and starts playback once if the same song is observed paused.
    /// `isStillValid` is the coordinator's own gate (observation running,
    /// control generation unchanged, Qishui still selected); it is checked
    /// before and after every refresh, together with this seek being current.
    func scheduleResumeIfPaused(
        identity: QishuiLyricIdentity,
        generation: UInt64,
        isStillValid: @escaping @MainActor () -> Bool,
        refresh: @escaping @MainActor () async -> MediaRemoteNowPlayingSnapshot?,
        startPlayback: @escaping @MainActor (pid_t) async -> Void
    ) {
        guard isCurrent(generation) else { return }
        let interval = resumePollInterval
        let limit = resumePollLimit
        resumeTask = Task { @MainActor [weak self] in
            for _ in 0..<limit {
                do { try await Task.sleep(for: interval) }
                catch { return }
                guard let self, !Task.isCancelled,
                      self.isCurrent(generation), isStillValid() else { return }
                let snapshot = await refresh()
                guard !Task.isCancelled,
                      self.isCurrent(generation), isStillValid() else { return }
                switch Self.resumeDecision(snapshot: snapshot, identity: identity) {
                case .keepWaiting:
                    continue
                case .stop:
                    return
                case .startPlayback:
                    await startPlayback(identity.processIdentifier)
                    return
                }
            }
        }
    }

    nonisolated static func resumeDecision(
        snapshot: MediaRemoteNowPlayingSnapshot?,
        identity: QishuiLyricIdentity
    ) -> ResumeDecision {
        guard let snapshot, snapshot.isVerifiedQishuiSource,
              snapshot.sampleOrigin != .cached,
              let track = snapshot.currentTrack else { return .keepWaiting }
        let sameTrack = track.sourceProcessIdentifier == identity.processIdentifier
            && QishuiTrackCoherencePolicy.matches(
                mediaTitle: identity.title, mediaArtist: identity.artist,
                directTitle: track.title, directArtist: track.artist
            )
        guard sameTrack else { return .stop }
        if track.isPlaying == true { return .stop }
        return QishuiSeekPlaybackPolicy.shouldStartPlayback(
            observedIsPlaying: track.isPlaying,
            sameTrack: sameTrack, operationIsCurrent: true
        ) ? .startPlayback : .keepWaiting
    }

    // MARK: Qishui admission

    /// The song changed while the user was dragging: the old song's time must
    /// not be applied to the new one.
    nonisolated static func trackChangeRejection(
        displayed: MediaRemoteNowPlayingTrack?,
        refreshed: MediaRemoteNowPlayingTrack?,
        now: Date = Date()
    ) -> MusicSourceStatus? {
        guard let refreshed, let displayed,
              !QishuiTrackCoherencePolicy.matches(
                  mediaTitle: displayed.title,
                  mediaArtist: displayed.artist,
                  directTitle: refreshed.title,
                  directArtist: refreshed.artist
              ) else { return nil }
        return MusicSourceStatus(
            sourceName: "汽水实时适配器",
            availability: .qishuiMediaRemoteSynced,
            headline: "已取消进度跳转",
            detail: "拖动过程中歌曲已经切换；没有把旧歌曲的时间应用到新歌曲。",
            checkedAt: now
        )
    }

    /// Whether a Qishui seek may be sent. `snapshot` is the latest verified
    /// sample after the pre-send refresh; `refreshFailedWhileCached` is true
    /// when that refresh returned nothing and the source is showing cached
    /// state. `QishuiSeekSafety.allowsGuardedSeek` stays the only admission
    /// rule for the system-media-focus seek.
    static func qishuiAdmission(
        progress: Double,
        snapshot: MediaRemoteNowPlayingSnapshot?,
        refreshFailedWhileCached: Bool,
        hasCompetingPlayback: () -> Bool,
        now: Date = Date()
    ) -> QishuiAdmission {
        guard progress.isFinite,
              (0...1).contains(progress),
              let snapshot,
              snapshot.isVerifiedQishuiSource,
              let track = snapshot.currentTrack,
              let duration = track.duration,
              duration > 0 else {
            return .rejected(MusicSourceStatus(
                sourceName: "汽水实时适配器",
                availability: .qishuiMediaRemoteSynced,
                headline: "当前不能拖动进度",
                detail: "汽水当前没有暴露可验证的歌曲时长或专属播放状态，进度条保持只读。",
                checkedAt: now
            ))
        }

        let isCached = snapshot.sampleOrigin == .cached || refreshFailedWhileCached
        let competing = hasCompetingPlayback()
        guard QishuiSeekSafety.allowsGuardedSeek(
            hasVerifiedQishuiSource: snapshot.isVerifiedQishuiSource,
            hasCurrentTrack: true,
            hasDuration: true,
            isCached: isCached,
            hasCompetingPlayback: competing
        ) else {
            let detail = competing
                ? "检测到其他已适配音乐源同时播放；为避免系统焦点跳转到错误播放器，进度条暂时保持只读。"
                : "汽水当前处于缓存或未确认状态；为避免误控其他播放器，进度条暂时保持只读。"
            return .rejected(MusicSourceStatus(
                sourceName: "汽水实时适配器",
                availability: .qishuiMediaRemoteCached,
                headline: "当前不能拖动进度",
                detail: detail,
                checkedAt: now
            ))
        }

        let targetProgress = min(max(progress, 0), 1)
        return .admitted(
            track: track,
            duration: duration,
            targetProgress: targetProgress,
            targetElapsed: duration * targetProgress
        )
    }

    // MARK: Statuses

    enum Status {
        nonisolated static func unrecognizedSource(now: Date = Date()) -> MusicSourceStatus {
            MusicSourceStatus(
                sourceName: "顶屿",
                availability: .systemNowPlayingUnavailable,
                headline: "未执行进度跳转",
                detail: "岛当前显示的音乐来源不可识别；为避免控制其他应用，本次操作已取消。",
                checkedAt: now
            )
        }

        nonisolated static func sourceSwitched(now: Date = Date()) -> MusicSourceStatus {
            cancelled("音乐来源已切换；旧进度跳转请求已取消。", now: now)
        }

        nonisolated static func sourceSwitchedBeforeSend(now: Date = Date()) -> MusicSourceStatus {
            cancelled("进度跳转发送前音乐来源已经切换；本次操作未执行。", now: now)
        }

        nonisolated static func sourceSwitchedBeforeResult(now: Date = Date()) -> MusicSourceStatus {
            cancelled("进度跳转完成前音乐来源已经切换；本次操作结果不进入当前岛。", now: now)
        }

        nonisolated static func neteaseUnsupported(now: Date = Date()) -> MusicSourceStatus {
            MusicSourceStatus(
                sourceName: "网易云音乐",
                availability: .neteaseMusicSynced,
                headline: "当前不能拖动进度",
                detail: "网易云音乐 Alpha 尚未暴露 PID 定向进度跳转；顶屿不会使用可能误控其他媒体的全局跳转。",
                checkedAt: now
            )
        }

        nonisolated static func qishuiSent(_ didSeek: Bool, now: Date = Date()) -> MusicSourceStatus {
            MusicSourceStatus(
                sourceName: "汽水实时适配器",
                availability: didSeek ? .qishuiControlSent : .qishuiMediaRemoteSynced,
                headline: didSeek ? "已跳转播放进度" : "未跳转播放进度",
                detail: didSeek
                    ? "已在汽水仍占用系统媒体焦点时发送跳转请求，等待实时状态确认。"
                    : "汽水系统媒体焦点校验未通过，未发送进度跳转。",
                checkedAt: now
            )
        }

        private nonisolated static func cancelled(_ detail: String, now: Date) -> MusicSourceStatus {
            MusicSourceStatus(
                sourceName: "顶屿",
                availability: .systemNowPlayingUnavailable,
                headline: "已取消进度跳转",
                detail: detail,
                checkedAt: now
            )
        }
    }

    // MARK: Usage fields

    /// Fields of the anonymous `seek_*` usage events. Progress is reported in
    /// permille and latency in whole milliseconds, never negative.
    enum UsageFields {
        nonisolated static func issued(
            interaction: MusicSeekInteraction,
            requestID: UInt64,
            source: String,
            progress: Double
        ) -> [String: String] {
            [
                "interaction": interaction.usageLabel,
                "request": String(requestID),
                "source": source,
                "target_permille": permille(progress)
            ]
        }

        nonisolated static func result(
            interaction: MusicSeekInteraction,
            requestID: UInt64,
            source: String,
            startedAt: Date,
            availability: MusicSourceAvailability,
            now: Date = Date()
        ) -> [String: String] {
            let accepted = availability == .qishuiControlSent
                || availability == .appleMusicControlSent
            return [
                "interaction": interaction.usageLabel,
                "latency_ms": latency(since: startedAt, now: now),
                "outcome": accepted ? "accepted" : "rejected",
                "request": String(requestID),
                "status": availability.rawValue,
                "source": source
            ]
        }

        nonisolated static func confirmed(
            sourceBundleIdentifier: String?,
            requestedAt: Date,
            targetProgress: Double,
            observedProgress: Double,
            now: Date = Date()
        ) -> [String: String] {
            [
                "latency_ms": latency(since: requestedAt, now: now),
                "observed_permille": permille(observedProgress),
                "source": sourceLabel(sourceBundleIdentifier),
                "target_permille": permille(targetProgress)
            ]
        }

        nonisolated static func confirmationTimeout(
            sourceBundleIdentifier: String?,
            requestedAt: Date,
            targetProgress: Double,
            now: Date = Date()
        ) -> [String: String] {
            [
                "latency_ms": latency(since: requestedAt, now: now),
                "source": sourceLabel(sourceBundleIdentifier),
                "target_permille": permille(targetProgress)
            ]
        }

        nonisolated static func cancelled(
            sourceBundleIdentifier: String?,
            requestedAt: Date,
            targetProgress: Double,
            reason: MusicSeekCancellationReason,
            now: Date = Date()
        ) -> [String: String] {
            [
                "latency_ms": latency(since: requestedAt, now: now),
                "reason": reason.rawValue,
                "source": sourceLabel(sourceBundleIdentifier),
                "target_permille": permille(targetProgress)
            ]
        }

        nonisolated static func permille(_ progress: Double) -> String {
            String(Int((min(max(progress, 0), 1) * 1_000).rounded()))
        }

        private nonisolated static func latency(since start: Date, now: Date) -> String {
            String(max(Int(now.timeIntervalSince(start) * 1_000), 0))
        }

        private nonisolated static func sourceLabel(_ bundleIdentifier: String?) -> String {
            MusicUsageEmitter.sourceLabel(MusicSourceID(bundleIdentifier: bundleIdentifier))
        }
    }
}

extension MusicSeekInteraction {
    var usageLabel: String {
        switch self {
        case .click: "click"
        case .drag: "drag"
        }
    }
}
