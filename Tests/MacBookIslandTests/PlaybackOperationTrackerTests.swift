import Foundation
import Testing
@testable import MacBookIsland

private final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 2_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

private func requestedState(playing: Bool, elapsed: TimeInterval? = 30, duration: TimeInterval? = 180) -> MusicState {
    MusicState(
        track: MusicTrack(
            title: "Song A", artist: "Artist A", palette: [], lyrics: [], hasArtwork: true,
            artworkData: nil, artworkURL: nil, sourceBundleIdentifier: "com.soda.music"
        ),
        isPlaying: playing,
        progress: 0,
        lyricIndex: 0,
        elapsedTime: elapsed,
        duration: duration,
        canSeek: true,
        hasCurrentTrack: true
    )
}

private func mediaTrack(
    title: String = "Song A",
    artist: String = "Artist A",
    playing: Bool?,
    elapsed: TimeInterval?,
    duration: TimeInterval? = 180
) -> MediaRemoteNowPlayingTrack {
    MediaRemoteNowPlayingTrack(
        title: title, artist: artist, album: nil, artworkData: nil, isPlaying: playing,
        progress: 0, elapsedTime: elapsed, duration: duration,
        sourceBundleIdentifier: "com.soda.music", sourceProcessIdentifier: 1001, sourceName: "汽水音乐"
    )
}

private func snapshot(
    _ track: MediaRemoteNowPlayingTrack,
    at date: Date,
    sampleID: UInt64,
    origin: MediaRemoteSampleOrigin = .streamEvent,
    source: MediaRemoteSampleSource = .adapterStream
) -> MediaRemoteNowPlayingSnapshot {
    MediaRemoteNowPlayingSnapshot(
        isAvailable: true, isVerifiedQishuiSource: true, currentTrack: track, diagnostic: "",
        checkedAt: date, sampleID: sampleID, sampleOrigin: origin, sampleSource: source
    )
}

@Suite("播放操作跟踪")
@MainActor
struct PlaybackOperationTrackerTests {
    @Test("按暂停：进度停在按下时的位置，早于 0.2 秒或旧样本不算确认，新样本确认后交还给来源")
    func pauseHoldsFloorUntilFreshConfirmation() throws {
        let clock = TestClock()
        let tracker = PlaybackOperationTracker(clock: { clock.now })
        let pressedAt = clock.now
        let id = tracker.begin(requestedState: requestedState(playing: true), baselineSampleID: 7,
                               baselineSampleSource: .adapterStream)
        #expect(tracker.pendingOperation?.targetIsPlaying == false)
        #expect(tracker.timelineFloor?.elapsedTime == 30)

        clock.advance(1)
        let stale = mediaTrack(playing: true, elapsed: 30)
        let shown = tracker.liveTrack(from: stale, checkedAt: pressedAt.addingTimeInterval(-0.5),
                                      allowsTimelineFloorRelease: false)
        #expect(shown.isPlaying == false)
        #expect(shown.elapsedTime == 30)

        let paused = mediaTrack(playing: false, elapsed: 30.4)
        #expect(tracker.confirmFromMediaRemote(snapshot: snapshot(
            paused, at: pressedAt.addingTimeInterval(0.1), sampleID: 8)) == nil)
        #expect(tracker.confirmFromMediaRemote(snapshot: snapshot(
            paused, at: pressedAt.addingTimeInterval(0.5), sampleID: 7)) == nil)
        #expect(tracker.confirmFromMediaRemote(snapshot: snapshot(
            paused, at: pressedAt.addingTimeInterval(0.5), sampleID: 9, origin: .cached)) == nil)
        #expect(tracker.isCurrent(id))

        let confirmed = try #require(tracker.confirmFromMediaRemote(snapshot: snapshot(
            paused, at: pressedAt.addingTimeInterval(0.5), sampleID: 9)))
        #expect(confirmed.id == id)
        #expect(!tracker.hasPendingOperation)
        #expect(tracker.cachedOverride?.isPlaying == false)
        #expect(tracker.cachedOverride?.elapsedTime == 30.4)

        let released = tracker.liveTrack(from: paused, checkedAt: pressedAt.addingTimeInterval(0.5),
                                         allowsTimelineFloorRelease: true)
        #expect(released == paused)
        #expect(tracker.timelineFloor == nil)
    }

    @Test("按播放：乐观进度从锚点继续走")
    func playAdvancesOptimistically() {
        let clock = TestClock()
        let tracker = PlaybackOperationTracker(clock: { clock.now })
        tracker.begin(requestedState: requestedState(playing: false), baselineSampleID: 0,
                      baselineSampleSource: .unknown)
        #expect(tracker.timelineFloor == nil)
        clock.advance(2)
        let shown = tracker.liveTrack(from: mediaTrack(playing: false, elapsed: 30), checkedAt: clock.now,
                                      allowsTimelineFloorRelease: true)
        #expect(shown.isPlaying == true)
        #expect(abs((shown.elapsedTime ?? 0) - 32) < 0.001)
    }

    @Test("连按两次：新操作要先看到相反状态才算确认")
    func replacingOperationRequiresOppositeStateFirst() throws {
        let tracker = PlaybackOperationTracker()
        tracker.begin(requestedState: requestedState(playing: true), baselineSampleID: 0,
                      baselineSampleSource: .unknown)
        let second = tracker.begin(requestedState: requestedState(playing: false), baselineSampleID: 0,
                                   baselineSampleSource: .unknown)
        #expect(tracker.pendingOperation?.requiresObservedOppositeState == true)

        #expect(tracker.observeConfirmation(isPlaying: true, operationID: second) == nil)
        #expect(tracker.observeConfirmation(isPlaying: false, operationID: second) == nil)
        #expect(tracker.pendingOperation?.observedOppositeState == true)
        #expect(tracker.observeConfirmation(isPlaying: true, operationID: second - 1) == nil)
        let confirmed = try #require(tracker.observeConfirmation(isPlaying: true, operationID: second))
        #expect(confirmed.targetIsPlaying)
        #expect(!tracker.hasPendingOperation)
    }

    @Test("AX 推断确认：要求同一首歌、有推断结果且晚于 0.2 秒")
    func inferredPlaybackConfirmation() {
        let clock = TestClock()
        let tracker = PlaybackOperationTracker(clock: { clock.now })
        tracker.begin(requestedState: requestedState(playing: true), baselineSampleID: 0,
                      baselineSampleSource: .unknown)
        let same = PlaybackTrackIdentity(title: "Song A", artist: "Artist A")
        let other = PlaybackTrackIdentity(title: "Song B", artist: "Artist A")
        let early = clock.now.addingTimeInterval(0.1)
        let later = clock.now.addingTimeInterval(0.3)
        #expect(tracker.confirmFromInferredPlayback(directTrack: same, inferredIsPlaying: false, checkedAt: early) == nil)
        #expect(tracker.confirmFromInferredPlayback(directTrack: same, inferredIsPlaying: nil, checkedAt: later) == nil)
        #expect(tracker.confirmFromInferredPlayback(directTrack: other, inferredIsPlaying: false, checkedAt: later) == nil)
        #expect(tracker.confirmFromInferredPlayback(directTrack: same, inferredIsPlaying: false, checkedAt: later) != nil)
    }

    @Test("换歌后丢弃待确认操作与暂停下限；汽水占位歌手视为同一首")
    func trackMismatchDiscardsOperation() {
        let tracker = PlaybackOperationTracker()
        tracker.begin(requestedState: requestedState(playing: true), baselineSampleID: 0,
                      baselineSampleSource: .unknown)
        #expect(tracker.pendingTarget(title: "Song A", artist: "汽水音乐") == false)
        #expect(tracker.pendingTarget(title: "Song B", artist: "Artist A") == nil)
        #expect(!tracker.hasPendingOperation)
        #expect(tracker.timelineFloor == nil)
    }

    @Test("超时回调只在操作仍是当前时触发；完成后不再回滚")
    func timeoutFiresOnlyForCurrentOperation() async throws {
        let tracker = PlaybackOperationTracker(confirmationTimeout: 0.05)
        var expired: [Int] = []
        let first = tracker.begin(requestedState: requestedState(playing: true), baselineSampleID: 0,
                                  baselineSampleSource: .unknown)
        tracker.scheduleConfirmationTimeout(id: first) { expired.append($0) }
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(expired == [first])
        #expect(tracker.rollback(id: first))
        #expect(!tracker.hasPendingOperation)
        #expect(!tracker.rollback(id: first))

        let second = tracker.begin(requestedState: requestedState(playing: true), baselineSampleID: 0,
                                   baselineSampleSource: .unknown)
        tracker.scheduleConfirmationTimeout(id: second) { expired.append($0) }
        tracker.finish(id: second)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(expired == [first])
    }

    @Test("缓存覆盖：播放中按时间外推，暂停时不低于暂停下限，换歌清除")
    func cachedOverrideExtrapolatesAndRespectsFloor() {
        let clock = TestClock()
        let tracker = PlaybackOperationTracker(clock: { clock.now })
        tracker.updateCachedOverride(from: mediaTrack(playing: true, elapsed: 10), checkedAt: clock.now)
        clock.advance(2)
        let playing = tracker.cachedPlaybackTrack(from: mediaTrack(playing: false, elapsed: 5))
        #expect(playing.isPlaying == true)
        #expect(abs((playing.elapsedTime ?? 0) - 12) < 0.001)

        tracker.begin(requestedState: requestedState(playing: true, elapsed: 40), baselineSampleID: 0,
                      baselineSampleSource: .unknown)
        #expect(tracker.cachedPlaybackTrack(from: mediaTrack(playing: true, elapsed: 5)).elapsedTime == 5)
        tracker.reset(clearTimelineFloor: false)
        tracker.updateCachedOverride(from: mediaTrack(playing: false, elapsed: 35), checkedAt: clock.now)
        let held = tracker.cachedPlaybackTrack(from: mediaTrack(playing: false, elapsed: 35))
        #expect(held.elapsedTime == 40)

        _ = tracker.cachedPlaybackTrack(from: mediaTrack(title: "Song B", playing: true, elapsed: 1))
        #expect(tracker.cachedOverride == nil)
    }

    @Test("缓存覆盖刷新节流：一秒一次，待确认操作期间总是刷新")
    func cachedOverrideRefreshThrottle() {
        let clock = TestClock()
        let tracker = PlaybackOperationTracker(clock: { clock.now })
        #expect(tracker.shouldRefreshCachedOverride)
        tracker.noteCachedOverrideRefreshAttempt()
        #expect(!tracker.shouldRefreshCachedOverride)
        clock.advance(0.5)
        tracker.begin(requestedState: requestedState(playing: true), baselineSampleID: 0,
                      baselineSampleSource: .unknown)
        #expect(tracker.shouldRefreshCachedOverride)
        #expect(!tracker.cachedOverrideRefreshIsDue)
        clock.advance(0.5)
        #expect(tracker.cachedOverrideRefreshIsDue)
    }
}
