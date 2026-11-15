import Foundation
import Testing
@testable import MacBookIsland

private func qishuiTrack(
    title: String = "Song A",
    artist: String = "Artist A",
    playing: Bool? = false,
    duration: TimeInterval? = 200,
    pid: pid_t = 1001
) -> MediaRemoteNowPlayingTrack {
    MediaRemoteNowPlayingTrack(
        title: title, artist: artist, album: nil, artworkData: nil, isPlaying: playing,
        progress: 0, elapsedTime: 10, duration: duration,
        sourceBundleIdentifier: "com.soda.music", sourceProcessIdentifier: pid, sourceName: "汽水音乐"
    )
}

private func snapshot(
    _ track: MediaRemoteNowPlayingTrack?,
    verified: Bool = true,
    origin: MediaRemoteSampleOrigin = .streamEvent
) -> MediaRemoteNowPlayingSnapshot {
    MediaRemoteNowPlayingSnapshot(
        isAvailable: true, isVerifiedQishuiSource: verified, currentTrack: track, diagnostic: "",
        checkedAt: Date(timeIntervalSince1970: 1_000), sampleID: 1, sampleOrigin: origin,
        sampleSource: .adapterStream
    )
}

private let identity = QishuiLyricIdentity(processIdentifier: 1001, title: "Song A", artist: "Artist A")

@Suite("进度跳转协调")
@MainActor
struct SeekCoordinatorTests {
    @Test("准入：合法请求给出夹紧后的目标；缺时长、越界、未核验都拒绝")
    func admissionAcceptsOnlyVerifiedTimedTracks() throws {
        guard case let .admitted(track, duration, target, elapsed) = SeekCoordinator.qishuiAdmission(
            progress: 0.25, snapshot: snapshot(qishuiTrack()),
            refreshFailedWhileCached: false, hasCompetingPlayback: { false }
        ) else { Issue.record("expected admission"); return }
        #expect(track.title == "Song A")
        #expect(duration == 200)
        #expect(target == 0.25)
        #expect(elapsed == 50)

        let rejectedInputs: [(Double, MediaRemoteNowPlayingSnapshot?)] = [
            (1.2, snapshot(qishuiTrack())),
            (.nan, snapshot(qishuiTrack())),
            (0.5, nil),
            (0.5, snapshot(qishuiTrack(), verified: false)),
            (0.5, snapshot(qishuiTrack(duration: nil))),
            (0.5, snapshot(qishuiTrack(duration: 0))),
            (0.5, snapshot(nil))
        ]
        for (progress, sample) in rejectedInputs {
            guard case let .rejected(status) = SeekCoordinator.qishuiAdmission(
                progress: progress, snapshot: sample,
                refreshFailedWhileCached: false, hasCompetingPlayback: { false }
            ) else { Issue.record("expected rejection for \(progress)"); continue }
            #expect(status.availability == .qishuiMediaRemoteSynced)
            #expect(status.headline == "当前不能拖动进度")
        }
    }

    @Test("准入：缓存样本、刷新失败的缓存态、其他来源同时播放都保持只读")
    func admissionRefusesCachedOrCompetingState() {
        let cases: [(MediaRemoteNowPlayingSnapshot, Bool, Bool, String)] = [
            (snapshot(qishuiTrack(), origin: .cached), false, false, "缓存"),
            (snapshot(qishuiTrack()), true, false, "缓存"),
            (snapshot(qishuiTrack()), false, true, "其他已适配音乐源")
        ]
        for (sample, refreshFailed, competing, phrase) in cases {
            guard case let .rejected(status) = SeekCoordinator.qishuiAdmission(
                progress: 0.5, snapshot: sample,
                refreshFailedWhileCached: refreshFailed, hasCompetingPlayback: { competing }
            ) else { Issue.record("expected rejection"); continue }
            #expect(status.availability == .qishuiMediaRemoteCached)
            #expect(status.detail.contains(phrase))
        }
    }

    @Test("准入：样本无效时不去查询其他来源")
    func admissionSkipsCompetitionCheckForInvalidSample() {
        var asked = false
        _ = SeekCoordinator.qishuiAdmission(
            progress: 0.5, snapshot: nil,
            refreshFailedWhileCached: false, hasCompetingPlayback: { asked = true; return false }
        )
        #expect(!asked)
    }

    @Test("拖动中换歌：显示的歌与刷新到的歌不同才取消；缺一边不判断")
    func trackChangeRejection() {
        #expect(SeekCoordinator.trackChangeRejection(
            displayed: qishuiTrack(), refreshed: qishuiTrack(title: "Song B")
        )?.headline == "已取消进度跳转")
        #expect(SeekCoordinator.trackChangeRejection(displayed: qishuiTrack(), refreshed: qishuiTrack()) == nil)
        #expect(SeekCoordinator.trackChangeRejection(displayed: nil, refreshed: qishuiTrack(title: "Song B")) == nil)
        #expect(SeekCoordinator.trackChangeRejection(displayed: qishuiTrack(), refreshed: nil) == nil)
    }

    @Test("跳转后续播：同一首且确认暂停才按播放；已在播放或换歌就停；状态未知继续等")
    func resumeDecision() {
        #expect(SeekCoordinator.resumeDecision(snapshot: snapshot(qishuiTrack(playing: false)), identity: identity) == .startPlayback)
        #expect(SeekCoordinator.resumeDecision(snapshot: snapshot(qishuiTrack(playing: true)), identity: identity) == .stop)
        #expect(SeekCoordinator.resumeDecision(snapshot: snapshot(qishuiTrack(title: "Song B")), identity: identity) == .stop)
        #expect(SeekCoordinator.resumeDecision(snapshot: snapshot(qishuiTrack(pid: 2002)), identity: identity) == .stop)
        #expect(SeekCoordinator.resumeDecision(snapshot: snapshot(qishuiTrack(playing: nil)), identity: identity) == .keepWaiting)
        #expect(SeekCoordinator.resumeDecision(snapshot: snapshot(qishuiTrack(), origin: .cached), identity: identity) == .keepWaiting)
        #expect(SeekCoordinator.resumeDecision(snapshot: snapshot(qishuiTrack(), verified: false), identity: identity) == .keepWaiting)
        #expect(SeekCoordinator.resumeDecision(snapshot: nil, identity: identity) == .keepWaiting)
    }

    @Test("续播最多按一次，且只在仍是当前跳转、协调器条件仍成立时")
    func resumeStartsPlaybackOnceForCurrentSeek() async throws {
        let seeks = SeekCoordinator(resumePollInterval: .milliseconds(5), resumePollLimit: 6)
        var samples = [snapshot(qishuiTrack(playing: nil)), snapshot(qishuiTrack(playing: false))]
        var pressed: [pid_t] = []
        let generation = seeks.begin()
        seeks.scheduleResumeIfPaused(
            identity: identity, generation: generation, isStillValid: { true },
            refresh: { samples.isEmpty ? nil : samples.removeFirst() },
            startPlayback: { pressed.append($0) }
        )
        try await Task.sleep(for: .milliseconds(200))
        #expect(pressed == [1001])
    }

    @Test("新跳转取代旧跳转的续播；协调器条件失效时不按")
    func resumeIsCancelledBySupersedingSeekOrInvalidation() async throws {
        let seeks = SeekCoordinator(resumePollInterval: .milliseconds(20), resumePollLimit: 3)
        var pressed = 0
        let first = seeks.begin()
        seeks.scheduleResumeIfPaused(
            identity: identity, generation: first, isStillValid: { true },
            refresh: { snapshot(qishuiTrack(playing: false)) },
            startPlayback: { _ in pressed += 1 }
        )
        #expect(seeks.hasPendingResume)
        let second = seeks.begin()
        #expect(!seeks.isCurrent(first))
        #expect(seeks.isCurrent(second))
        #expect(!seeks.hasPendingResume)
        seeks.scheduleResumeIfPaused(
            identity: identity, generation: first, isStillValid: { true },
            refresh: { snapshot(qishuiTrack(playing: false)) },
            startPlayback: { _ in pressed += 1 }
        )
        #expect(!seeks.hasPendingResume)
        seeks.scheduleResumeIfPaused(
            identity: identity, generation: second, isStillValid: { false },
            refresh: { snapshot(qishuiTrack(playing: false)) },
            startPlayback: { _ in pressed += 1 }
        )
        try await Task.sleep(for: .milliseconds(150))
        #expect(pressed == 0)
    }

    @Test("使用诊断字段：千分比夹紧取整，延迟不为负，来源与取消原因照旧")
    func usageFields() {
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(SeekCoordinator.UsageFields.issued(
            interaction: .drag, requestID: 7, source: "qishui", progress: 1.4
        ) == ["interaction": "drag", "request": "7", "source": "qishui", "target_permille": "1000"])
        let result = SeekCoordinator.UsageFields.result(
            interaction: .click, requestID: 7, source: "qishui", startedAt: start,
            availability: .qishuiControlSent, now: start.addingTimeInterval(0.1234)
        )
        #expect(result["outcome"] == "accepted")
        #expect(result["latency_ms"] == "123")
        #expect(result["status"] == MusicSourceAvailability.qishuiControlSent.rawValue)
        #expect(SeekCoordinator.UsageFields.result(
            interaction: .click, requestID: 7, source: "qishui", startedAt: start,
            availability: .qishuiMediaRemoteCached, now: start
        )["outcome"] == "rejected")
        #expect(SeekCoordinator.UsageFields.confirmed(
            sourceBundleIdentifier: "com.soda.music", requestedAt: start,
            targetProgress: 0.4994, observedProgress: -0.2, now: start.addingTimeInterval(-1)
        ) == ["latency_ms": "0", "observed_permille": "0", "source": "qishui", "target_permille": "499"])
        #expect(SeekCoordinator.UsageFields.cancelled(
            sourceBundleIdentifier: nil, requestedAt: start, targetProgress: 0.5,
            reason: .trackChanged, now: start
        )["reason"] == "track_changed")
        #expect(SeekCoordinator.UsageFields.confirmationTimeout(
            sourceBundleIdentifier: "com.soda.music", requestedAt: start, targetProgress: 0.5, now: start
        ).keys.sorted() == ["latency_ms", "source", "target_permille"])
    }
}
