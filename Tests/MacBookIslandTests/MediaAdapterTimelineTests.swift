import Foundation
import Testing
@testable import MacBookIsland

@Test("暂停锚点保持用户点击时的位置")
func pauseAnchorUsesRequestPosition() {
    let requestElapsed: TimeInterval = 42.0
    let dispatchCompletionElapsed: TimeInterval = 42.45

    let anchor = PlaybackControlTimeline.anchorElapsed(
        targetIsPlaying: false,
        requestElapsed: requestElapsed,
        dispatchCompletionElapsed: dispatchCompletionElapsed
    )

    #expect(anchor == requestElapsed)
}

@Test("恢复播放可在请求位置缺失时使用控制完成位置")
func playbackAnchorFallsBackToCompletionPosition() {
    let dispatchCompletionElapsed: TimeInterval = 42.45

    let anchor = PlaybackControlTimeline.anchorElapsed(
        targetIsPlaying: true,
        requestElapsed: nil,
        dispatchCompletionElapsed: dispatchCompletionElapsed
    )

    #expect(anchor == dispatchCompletionElapsed)
}

@Test("暂停确认不会让进度越过点击锚点")
func pauseConfirmationKeepsRequestAnchor() {
    let requestAnchor: TimeInterval = 42.0
    let confirmedElapsed: TimeInterval = 42.45

    let elapsed = PlaybackControlTimeline.confirmedElapsed(
        targetIsPlaying: false,
        anchorElapsed: requestAnchor,
        confirmedElapsed: confirmedElapsed
    )

    #expect(elapsed == requestAnchor)
}

@Test("乐观暂停从点击瞬间冻结本地时间轴")
func optimisticPauseFreezesImmediately() {
    let issuedAt = Date(timeIntervalSince1970: 100)
    let elapsed = PlaybackControlTimeline.optimisticElapsed(
        targetIsPlaying: false,
        anchorElapsed: 42,
        issuedAt: issuedAt,
        now: issuedAt.addingTimeInterval(0.45),
        duration: 180
    )

    #expect(elapsed == 42)
}

@Test("乐观恢复播放从点击锚点推进本地时间轴")
func optimisticPlayAdvancesImmediately() {
    let issuedAt = Date(timeIntervalSince1970: 100)
    let elapsed = PlaybackControlTimeline.optimisticElapsed(
        targetIsPlaying: true,
        anchorElapsed: 42,
        issuedAt: issuedAt,
        now: issuedAt.addingTimeInterval(0.45),
        duration: 180
    )

    #expect(abs((elapsed ?? 0) - 42.45) < 0.0001)
}

@Test("旧控制结果不能收尾快速连点后的新操作")
func staleControlResultCannotResolveNewerOperation() {
    #expect(!PlaybackControlTimeline.isCurrentOperation(
        completedOperationID: 7,
        currentOperationID: 8
    ))
    #expect(PlaybackControlTimeline.isCurrentOperation(
        completedOperationID: 8,
        currentOperationID: 8
    ))
}

@Test("播放中的权威时间戳会在接收时折算为当前进度")
func authoritativeTimestampProjectsToReceiptTime() {
    let startedAt = Date(timeIntervalSince1970: 1_000)
    let anchor = PlaybackControlTimeline.authoritativeAnchor(
        trackIdentity: "song-a",
        elapsedTime: 160,
        elapsedTimeNow: nil,
        sourceTimestamp: startedAt,
        playbackRate: 1,
        isPlaying: true,
        duration: 300,
        receivedAt: startedAt.addingTimeInterval(15),
        receivedUptime: 500
    )

    #expect(anchor != nil)
    #expect(abs((anchor?.elapsedAtAnchor ?? 0) - 175) < 0.0001)
    #expect(abs((PlaybackControlTimeline.elapsed(from: anchor!, nowUptime: 500.4) ?? 0) - 175.4) < 0.0001)
}

@Test("新鲜 elapsedTimeNow 优先并可越过固定 sourceTimestamp 更新锚点")
func freshElapsedTimeNowReplacesFixedTimestampAnchor() {
    let fixedSourceTimestamp = Date(timeIntervalSince1970: 988)
    let firstReceivedAt = Date(timeIntervalSince1970: 1_000)
    let first = PlaybackControlTimeline.authoritativeAnchor(
        trackIdentity: "city-of-stars",
        elapsedTime: 51,
        elapsedTimeNow: 51,
        sourceTimestamp: fixedSourceTimestamp,
        playbackRate: 1,
        isPlaying: true,
        duration: 197,
        receivedAt: firstReceivedAt,
        receivedUptime: 100
    )!
    let fresh = PlaybackControlTimeline.authoritativeAnchor(
        trackIdentity: "city-of-stars",
        elapsedTime: 51,
        elapsedTimeNow: 63,
        sourceTimestamp: fixedSourceTimestamp,
        playbackRate: 1,
        isPlaying: true,
        duration: 197,
        receivedAt: firstReceivedAt.addingTimeInterval(12),
        receivedUptime: 112
    )!
    let accepted = PlaybackControlTimeline.accepting(fresh, over: first)

    #expect(first.elapsedAtAnchor == 51)
    #expect(accepted.elapsedAtAnchor == 63)
    #expect(accepted.sourceTimestamp == firstReceivedAt.addingTimeInterval(12))
}

@Test("迟到的旧权威样本不能覆盖较新的同曲锚点")
func staleAuthoritativeSampleCannotReplaceNewerAnchor() {
    let base = Date(timeIntervalSince1970: 1_000)
    let newer = PlaybackControlTimeline.authoritativeAnchor(
        trackIdentity: "song-a",
        elapsedTime: 175,
        elapsedTimeNow: nil,
        sourceTimestamp: base.addingTimeInterval(15),
        playbackRate: 1,
        isPlaying: true,
        duration: 300,
        receivedAt: base.addingTimeInterval(15),
        receivedUptime: 500
    )!
    let stale = PlaybackControlTimeline.authoritativeAnchor(
        trackIdentity: "song-a",
        elapsedTime: 160,
        elapsedTimeNow: nil,
        sourceTimestamp: base,
        playbackRate: 1,
        isPlaying: true,
        duration: 300,
        receivedAt: base.addingTimeInterval(16),
        receivedUptime: 501
    )!

    let accepted = PlaybackControlTimeline.accepting(stale, over: newer)

    #expect(accepted == newer)
    #expect(abs((PlaybackControlTimeline.elapsed(from: accepted, nowUptime: 501) ?? 0) - 176) < 0.0001)
}

@Test("暂停权威锚点立即冻结且不随本地时间推进")
func pausedAuthoritativeAnchorFreezesImmediately() {
    let now = Date(timeIntervalSince1970: 1_000)
    let anchor = PlaybackControlTimeline.authoritativeAnchor(
        trackIdentity: "song-a",
        elapsedTime: 42,
        elapsedTimeNow: 42,
        sourceTimestamp: now,
        playbackRate: 0,
        isPlaying: false,
        duration: 180,
        receivedAt: now,
        receivedUptime: 100
    )!

    #expect(PlaybackControlTimeline.elapsed(from: anchor, nowUptime: 101.5) == 42)
}

@Test("切歌后允许权威时间轴从新曲起点重置")
func changedTrackAcceptsTimelineReset() {
    let now = Date(timeIntervalSince1970: 1_000)
    let previous = PlaybackControlTimeline.authoritativeAnchor(
        trackIdentity: "song-a",
        elapsedTime: 175,
        elapsedTimeNow: nil,
        sourceTimestamp: now,
        playbackRate: 1,
        isPlaying: true,
        duration: 300,
        receivedAt: now,
        receivedUptime: 100
    )!
    let next = PlaybackControlTimeline.authoritativeAnchor(
        trackIdentity: "song-b",
        elapsedTime: 2,
        elapsedTimeNow: nil,
        sourceTimestamp: now.addingTimeInterval(-5),
        playbackRate: 1,
        isPlaying: true,
        duration: 240,
        receivedAt: now,
        receivedUptime: 100
    )!

    #expect(PlaybackControlTimeline.accepting(next, over: previous) == next)
}

@Test("切歌期间迟到的旧曲异步回读不能覆盖新曲")
func delayedAsyncReadCannotRestorePreviousTrack() {
    #expect(!PlaybackControlTimeline.shouldAcceptAsyncSample(
        requestSampleID: 20,
        currentSampleID: 21,
        responseTrackIdentity: "song-a",
        currentTrackIdentity: "song-b"
    ))
    #expect(PlaybackControlTimeline.shouldAcceptAsyncSample(
        requestSampleID: 20,
        currentSampleID: 21,
        responseTrackIdentity: "song-b",
        currentTrackIdentity: "song-b"
    ))
}

@Test("AX 旧进度不能覆盖同曲 MediaRemote 权威进度")
func axProgressCannotOverrideMediaRemoteElapsed() {
    let elapsed = PlaybackControlTimeline.cachedOverrideElapsed(
        mediaRemoteElapsed: 92,
        axProgress: 76.0 / 197.0,
        duration: 197,
        existingElapsed: nil,
        existingIsPlaying: nil,
        axIsPlaying: true
    )

    #expect(elapsed == 92)
}

@Test("AX 暂停只冻结时间轴且不能让进度倒退")
func axPauseFreezesWithoutTimelineRollback() {
    let firstPauseElapsed = PlaybackControlTimeline.cachedOverrideElapsed(
        mediaRemoteElapsed: 92,
        axProgress: 76.0 / 197.0,
        duration: 197,
        existingElapsed: 93,
        existingIsPlaying: true,
        axIsPlaying: false
    )
    let repeatedPauseElapsed = PlaybackControlTimeline.cachedOverrideElapsed(
        mediaRemoteElapsed: 92,
        axProgress: 76.0 / 197.0,
        duration: 197,
        existingElapsed: firstPauseElapsed,
        existingIsPlaying: false,
        axIsPlaying: false
    )

    #expect(firstPauseElapsed == 93)
    #expect(repeatedPauseElapsed == 93)
}

@Test("MediaRemote 缺少进度时才允许 AX progress 补位")
func axProgressFillsOnlyMissingMediaRemoteElapsed() {
    let elapsed = PlaybackControlTimeline.cachedOverrideElapsed(
        mediaRemoteElapsed: nil,
        axProgress: 76.0 / 197.0,
        duration: 197,
        existingElapsed: nil,
        existingIsPlaying: nil,
        axIsPlaying: true
    )

    #expect(abs((elapsed ?? 0) - 76) < 0.0001)
}
