import AppKit
import Foundation
import SwiftUI

/// What `AppleMusicDriver` needs from the coordinator. Held weakly; see
/// Docs/engineering/COORDINATOR_SPLIT_STEP4.md (step 4b).
@MainActor
protocol AppleMusicDriverHost: AnyObject {
    /// The selector's last selection, read without updating it.
    var appleMusicSelectorSource: MusicSourceID? { get }
    var appleMusicForegroundSource: MusicSourceID? { get }
    func appleMusicPublish()
    func appleMusicRecord(_ name: String, fields: [String: String])
}

/// Apple Music state and orchestration on top of `AppleMusicAppAdapter`:
/// refresh scheduling, snapshot admission, playback-control expectations and
/// the published state. Moved out of `MusicAdapterCoordinator` unchanged
/// (coordinator split step 4b); coordinator state is reached only through
/// `host`, evaluated at the same points as before.
@MainActor
final class AppleMusicDriver {
    weak var host: AppleMusicDriverHost?

    let appleMusicTransitionTimeline = AppleMusicTransitionTimeline()
    lazy var appleMusicAdapter = AppleMusicAppAdapter(
        transitionTimeline: appleMusicTransitionTimeline
    )
    var latestAppleMusicSnapshot: MusicAppSnapshot?
    var appleMusicEnabled = true
    var appleMusicRefreshTask: Task<Void, Never>?
    var appleMusicRefreshQueued = false
    var appleMusicRefreshGeneration: UInt64 = 0
    var appleMusicTransientRetryAttempt = 0
    var appleMusicTransientRetryTask: Task<Void, Never>?
    var lastAppleMusicRefreshCompletedAt: Date?
    var lastAppleMusicControlAt: Date?
    var appleMusicConsecutiveRefreshFailures = 0
    var appleMusicControlRequestID: UInt64 = 0
    var appleMusicControlGeneration: UInt64 = 0
    var pendingAppleMusicPlaybackControl: AppleMusicPlaybackControlExpectation?
    var appleMusicPlaybackExpectationTask: Task<Void, Never>?
    var lastAppleMusicUIPublishFingerprint: String?

    func startAppleMusicObservation() {
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

    func stopAppleMusicObservation() {
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

    func scheduleAppleMusicRefresh(force: Bool) {
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
                host?.appleMusicPublish()
            }
            return
        }

        if force {
            appleMusicTransientRetryTask?.cancel()
            appleMusicTransientRetryTask = nil
        }

        let isSelected = host?.appleMusicSelectorSource == .appleMusic
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
            self.host?.appleMusicPublish()
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

    func cancelAppleMusicTransientRetry(resetAttempt: Bool) {
        appleMusicTransientRetryTask?.cancel()
        appleMusicTransientRetryTask = nil
        if resetAttempt {
            appleMusicTransientRetryAttempt = 0
        }
    }

    enum AppleMusicSnapshotAdmissionResult {
        case applied
        case rejected
        case retryScheduled
    }

    @discardableResult
    func admitAppleMusicSnapshot(
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
                    host?.appleMusicRecord("playback_confirmed", fields: [
                        "evidence": "apple_event",
                        "latency_ms": String(max(
                            Int(now.timeIntervalSince(expectation.issuedAt) * 1_000),
                            0
                        )),
                        "source": "apple-music",
                        "target_playback": MusicAdapterCoordinator.playbackStateLabel(
                            expectation.targetState
                        )
                    ])
                } else if matchesExpectedTrack,
                          now.timeIntervalSince(expectation.issuedAt)
                            >= AppleMusicPlaybackControlExpectation
                                .staleSnapshotGraceInterval {
                    host?.appleMusicRecord("playback_confirmation_timeout", fields: [
                        "latency_ms": String(max(
                            Int(now.timeIntervalSince(expectation.issuedAt) * 1_000),
                            0
                        )),
                        "source": "apple-music",
                        "target_playback": MusicAdapterCoordinator.playbackStateLabel(
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

    func beginAppleMusicPlaybackControlExpectation(
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
            self.host?.appleMusicRecord("playback_confirmation_timeout", fields: [
                "latency_ms": String(max(
                    Int(Date().timeIntervalSince(expectation.issuedAt) * 1_000),
                    0
                )),
                "source": "apple-music",
                "target_playback": MusicAdapterCoordinator.playbackStateLabel(expectation.targetState)
            ])
            pendingAppleMusicPlaybackControl = nil
            appleMusicPlaybackExpectationTask = nil
            scheduleAppleMusicRefresh(force: true)
        }
    }

    func clearAppleMusicPlaybackControlExpectation() {
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
            self.host?.appleMusicPublish()
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

    func appleMusicSnapshot(
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

    func appleMusicControlStatus(
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

    func appleMusicSourceCandidate() -> MusicSourceCandidate {
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
                isForeground: host?.appleMusicForegroundSource == .appleMusic
            ),
            hasTrack: snapshotMatchesRunningInstance && snapshot.track != nil,
            playback: playback,
            isCached: false
        )
    }

    func appleMusicState() -> MusicState {
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

    func appleMusicStatus() -> MusicSourceStatus {
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

    func noteAppleMusicUIPublished(_ state: MusicState) {
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
}
