import Foundation
import Testing
@testable import MacBookIsland

@Suite("跨 get-now 与 stream 的权威播放时钟")
struct PlaybackMixedClockRegressionTests {
    @Test("get-now 后同一秒的源暂停冻结在确认位置，不能沿接收时钟继续推进", arguments: [990.0, 1000.0])
    @MainActor
    func getNowThenPauseStreamFreezesConfirmedPosition(initialSourceSecond: Double) throws {
        let source = makeSource()
        let second = Date(timeIntervalSince1970: 1_000)
        _ = source.ingestStreamEnvelopeForTesting(
            try envelope(initialPlayingPayload(sourceSecond: initialSourceSecond, elapsedNow: 104.4)),
            receivedAt: second.addingTimeInterval(0.8), receivedUptime: 100.8)

        // A get-client --now result establishes a receipt-time position. The
        // subsequent stream pause has the source's integer-second timestamp,
        // which is newer than the original source event but earlier than that
        // get-now receipt. Both payloads name exactly the same PID and track.
        let paused = try #require(source.ingestStreamEnvelopeForTesting(
            try envelope([
                "bundleIdentifier": "com.soda.music", "processIdentifier": 123,
                "contentItemIdentifier": "clock-song", "title": "Clock Song",
                "artist": "Fixture Artist", "playing": 0, "playbackRate": 0.0,
                "elapsedTime": 104.783106, "timestamp": timestamp(1_000)
            ], diff: true),
            receivedAt: second.addingTimeInterval(1.1), receivedUptime: 101.1
        )?.currentTrack)
        #expect(paused.isPlaying == false)
        #expect(abs((paused.elapsedTime ?? -1) - 104.783106) < 0.000001)

        let later = try #require(source.ingestStreamEnvelopeForTesting(
            try envelope(["artist": "Fixture Artist"], diff: true),
            receivedAt: second.addingTimeInterval(12), receivedUptime: 112
        )?.currentTrack)
        #expect(later.isPlaying == false)
        #expect(abs((later.elapsedTime ?? -1) - 104.783106) < 0.000001)
    }

    @Test("真正早于 get-now 原始源事件的迟到暂停不能覆盖当前播放位置")
    @MainActor
    func pauseOlderThanOriginalSourceEventCannotReplaceGetNow() throws {
        let source = makeSource()
        let second = Date(timeIntervalSince1970: 1_000)
        _ = source.ingestStreamEnvelopeForTesting(
            try envelope(initialPlayingPayload(sourceSecond: 990, elapsedNow: 104.4)),
            receivedAt: second.addingTimeInterval(0.8), receivedUptime: 100.8)

        let afterOldPause = try #require(source.ingestStreamEnvelopeForTesting(
            try envelope([
                "playing": 0, "playbackRate": 0.0,
                "elapsedTime": 80.0, "timestamp": timestamp(989)
            ], diff: true),
            receivedAt: second.addingTimeInterval(1.1), receivedUptime: 101.1
        )?.currentTrack)
        #expect(abs((afterOldPause.elapsedTime ?? -1) - 104.7) < 0.000001)
        #expect(afterOldPause.isPlaying == true)

        let later = try #require(source.ingestStreamEnvelopeForTesting(
            try envelope(["artist": "Fixture Artist"], diff: true),
            receivedAt: second.addingTimeInterval(2.1), receivedUptime: 102.1
        )?.currentTrack)
        #expect(abs((later.elapsedTime ?? -1) - 105.7) < 0.000001)
        #expect(later.isPlaying == true)
        let positionOnly = try #require(source.ingestStreamEnvelopeForTesting(
            try envelope(["elapsedTimeNow": 106.0, "timestamp": timestamp(1002)], diff: true),
            receivedAt: second.addingTimeInterval(2.4), receivedUptime: 102.4
        )?.currentTrack)
        #expect(positionOnly.isPlaying == true)
        let afterPosition = try #require(source.ingestStreamEnvelopeForTesting(
            try envelope(["artist": "Fixture Artist"], diff: true),
            receivedAt: second.addingTimeInterval(3.4), receivedUptime: 103.4
        )?.currentTrack)
        #expect(abs((afterPosition.elapsedTime ?? -1) - 107.0) < 0.000001)
    }

    @Test("新源恢复播放后迟到的上一秒暂停不能通过宽松接收时间规则覆盖它")
    @MainActor
    func previousSecondPauseCannotReplaceNewerResume() throws {
        let source = makeSource()
        let second = Date(timeIntervalSince1970: 1_000)
        _ = source.ingestStreamEnvelopeForTesting(
            try envelope(initialPlayingPayload(sourceSecond: 1_001, elapsedNow: 105.4)),
            receivedAt: second.addingTimeInterval(1.4), receivedUptime: 101.4)

        let afterLatePause = try #require(source.ingestStreamEnvelopeForTesting(
            try envelope([
                "playing": 0, "playbackRate": 0.0,
                "elapsedTime": 105.4, "timestamp": timestamp(1_000)
            ], diff: true),
            receivedAt: second.addingTimeInterval(1.6), receivedUptime: 101.6
        )?.currentTrack)
        #expect(abs((afterLatePause.elapsedTime ?? -1) - 105.6) < 0.000001)
        #expect(afterLatePause.isPlaying == true)

        let later = try #require(source.ingestStreamEnvelopeForTesting(
            try envelope(["artist": "Fixture Artist"], diff: true),
            receivedAt: second.addingTimeInterval(2.6), receivedUptime: 102.6
        )?.currentTrack)
        #expect(abs((later.elapsedTime ?? -1) - 106.6) < 0.000001)
        #expect(later.isPlaying == true)
    }

    @MainActor
    private func makeSource() -> MediaRemoteAdapterStreamSource {
        MediaRemoteAdapterStreamSource(runningQishuiProcessIdentifiersProvider: { [123] })
    }

    @Test("只带播放状态的有效暂停不能被旧位置锚点继续推进")
    @MainActor
    func stateOnlyPauseFreezesExistingPosition() throws {
        let source = makeSource()
        let second = Date(timeIntervalSince1970: 1_000)
        _ = source.ingestStreamEnvelopeForTesting(
            try envelope(initialPlayingPayload(sourceSecond: 1000, elapsedNow: 104.4)),
            receivedAt: second.addingTimeInterval(0.8), receivedUptime: 100.8)
        let paused = try #require(source.ingestStreamEnvelopeForTesting(
            try envelope(["playing": 0, "playbackRate": 0, "timestamp": timestamp(1001)], diff: true),
            receivedAt: second.addingTimeInterval(1.1), receivedUptime: 101.1
        )?.currentTrack)
        #expect(paused.isPlaying == false)
        #expect(abs((paused.elapsedTime ?? -1) - 104.7) < 0.000001)
        let later = try #require(source.ingestStreamEnvelopeForTesting(
            try envelope(["artist": "Fixture Artist"], diff: true),
            receivedAt: second.addingTimeInterval(3.1), receivedUptime: 103.1
        )?.currentTrack)
        #expect(later.isPlaying == false)
        #expect(abs((later.elapsedTime ?? -1) - 104.7) < 0.000001)
        let resumed = try #require(source.ingestStreamEnvelopeForTesting(
            try envelope(["playing": 1, "timestamp": timestamp(1004)], diff: true),
            receivedAt: second.addingTimeInterval(4.1), receivedUptime: 104.1
        )?.currentTrack)
        #expect(resumed.isPlaying == true)
        let advancing = try #require(source.ingestStreamEnvelopeForTesting(
            try envelope(["artist": "Fixture Artist"], diff: true),
            receivedAt: second.addingTimeInterval(5.1), receivedUptime: 105.1
        )?.currentTrack)
        #expect(advancing.isPlaying == true)
        #expect(abs((advancing.elapsedTime ?? -1) - 105.7) < 0.000001)
    }

    @Test("迟到旧播放消息也不能恢复已确认的暂停按钮和时间轴")
    @MainActor
    func stalePlayingCannotResumeNewerPause() throws {
        let source = makeSource()
        let second = Date(timeIntervalSince1970: 1000)
        var initial = initialPlayingPayload(sourceSecond: 1001, elapsedNow: 104.4)
        initial["playing"] = 0
        initial["playbackRate"] = 0
        _ = source.ingestStreamEnvelopeForTesting(
            try envelope(initial), receivedAt: second.addingTimeInterval(1.1), receivedUptime: 101.1)
        let stale = try #require(source.ingestStreamEnvelopeForTesting(
            try envelope(["playing": 1, "playbackRate": 1, "elapsedTimeNow": 104.4,
                          "timestamp": timestamp(1000)], diff: true),
            receivedAt: second.addingTimeInterval(1.4), receivedUptime: 101.4
        )?.currentTrack)
        #expect(stale.isPlaying == false)
        let later = try #require(source.ingestStreamEnvelopeForTesting(
            try envelope(["artist": "Fixture Artist"], diff: true),
            receivedAt: second.addingTimeInterval(2.4), receivedUptime: 102.4
        )?.currentTrack)
        #expect(later.isPlaying == false)
        #expect(abs((later.elapsedTime ?? -1) - 104.4) < 0.000001)
    }

    private func initialPlayingPayload(sourceSecond: TimeInterval, elapsedNow: Double) -> [String: Any] {
        ["bundleIdentifier": "com.soda.music", "processIdentifier": 123,
         "contentItemIdentifier": "clock-song", "title": "Clock Song",
         "artist": "Fixture Artist", "duration": 240.0,
         "playing": 1, "playbackRate": 1.0,
         "elapsedTime": 94.4, "elapsedTimeNow": elapsedNow,
         "timestamp": timestamp(sourceSecond)]
    }

    private func envelope(_ payload: [String: Any], diff: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["type": "data", "diff": diff, "payload": payload])
    }

    private func timestamp(_ second: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: second))
    }
}
