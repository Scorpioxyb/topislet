import Foundation
import Testing
@testable import MacBookIsland

private func durationFixture(_ duration: Any? = nil) -> [String: Any] {
    var payload: [String: Any] = [
        "bundleIdentifier": "com.soda.music", "processIdentifier": 123,
        "contentItemIdentifier": "recording-a", "title": "Song A",
        "artist": "Artist A", "album": "Album A",
        "artworkData": Data([1, 2]).base64EncodedString(),
        "playing": 1, "playbackRate": 1, "elapsedTimeNow": 20.0
    ]
    payload["duration"] = duration
    return payload
}

private func durationEnvelope(_ payload: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["type": "data", "diff": false, "payload": payload])
}

@Test("同曲元数据补回时长，不能导入回包的旧暂停位置")
@MainActor
func metadataDurationRecoveryPreservesPlayback() throws {
    let source = MediaRemoteAdapterStreamSource(runningQishuiProcessIdentifiersProvider: { [123] })
    let now = Date()
    _ = source.ingestStreamEnvelopeForTesting(try durationEnvelope(durationFixture()), receivedAt: now, receivedUptime: 100)
    var reply = durationFixture(180.0)
    reply["playing"] = 0
    reply["playbackRate"] = 0
    reply["elapsedTimeNow"] = 4.0
    let track = try #require(source.applyMetadataPayloadForTesting(reply,
        receivedAt: now.addingTimeInterval(1), receivedUptime: 101)?.currentTrack)
    #expect(track.duration == 180)
    #expect(track.isPlaying == true)
    #expect(abs((track.elapsedTime ?? -1) - 21) < 0.01)
}

@Test("不同录音、歌手、PID及无效时长不能补入当前曲目")
@MainActor
func metadataDurationRecoveryRejectsForeignAndInvalidValues() throws {
    for (field, value) in [("title", "Song B" as Any), ("artist", "Artist B"),
                           ("album", "Album B"), ("contentItemIdentifier", "recording-b"),
                           ("processIdentifier", 999), ("duration", -1.0),
                           ("duration", 0.0), ("duration", Double.nan), ("duration", Double.infinity)] {
        let source = MediaRemoteAdapterStreamSource(runningQishuiProcessIdentifiersProvider: { [123, 999] })
        let now = Date()
        _ = source.ingestStreamEnvelopeForTesting(try durationEnvelope(durationFixture()), receivedAt: now, receivedUptime: 100)
        var reply = durationFixture(180.0)
        reply[field] = value
        let track = try #require(source.applyMetadataPayloadForTesting(reply, receivedAt: now,
            receivedUptime: 100)?.currentTrack)
        #expect(track.duration == nil, "Rejected field: \(field)")
        #expect(track.artist == "Artist A")
        #expect(track.album == "Album A")
    }
}

@Test("已有时长不能被补读覆盖")
@MainActor
func metadataDurationRecoveryPreservesExistingDuration() throws {
    let source = MediaRemoteAdapterStreamSource(runningQishuiProcessIdentifiersProvider: { [123] })
    let now = Date()
    _ = source.ingestStreamEnvelopeForTesting(try durationEnvelope(durationFixture(180.0)), receivedAt: now, receivedUptime: 100)
    let track = try #require(source.applyMetadataPayloadForTesting(durationFixture(240.0),
        receivedAt: now, receivedUptime: 100)?.currentTrack)
    #expect(track.duration == 180)
}

private final class DurationReadFixture: @unchecked Sendable {
    private let lock = NSLock()
    private let data: Data?
    private var reads = 0
    init(data: Data?) { self.data = data }
    var count: Int { lock.withLock { reads } }
    func read() -> Data? { lock.withLock { reads += 1; return data } }
}

@Test("封面歌手完整但时长缺失，事件补读能恢复进度条")
@MainActor
func missingDurationEventRestoresProgress() async throws {
    let reader = DurationReadFixture(data: try JSONSerialization.data(withJSONObject: durationFixture(180.0)))
    let source = MediaRemoteAdapterStreamSource(runningQishuiProcessIdentifiersProvider: { [123] },
        metadataDataReader: { reader.read() })
    let now = Date()
    _ = source.ingestStreamEnvelopeForTesting(try durationEnvelope(durationFixture()), receivedAt: now,
        receivedUptime: 100, schedulesMetadataRefresh: true)
    let deadline = Date().addingTimeInterval(0.5)
    while source.snapshot()?.currentTrack?.duration == nil, Date() < deadline {
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    #expect(source.snapshot()?.currentTrack?.duration == 180)
    #expect(reader.count == 1)
    #expect(source.snapshot()?.currentTrack?.isPlaying == true)
}

@Test("时长源未返回时，重复事件不能无限启动补读")
@MainActor
func missingDurationReadsAreBounded() async throws {
    let reader = DurationReadFixture(data: nil)
    let source = MediaRemoteAdapterStreamSource(runningQishuiProcessIdentifiersProvider: { [123] },
        metadataDataReader: { reader.read() })
    let payload = try durationEnvelope(durationFixture())
    for _ in 0..<4 {
        _ = source.ingestStreamEnvelopeForTesting(payload, receivedAt: Date(),
            receivedUptime: ProcessInfo.processInfo.systemUptime, schedulesMetadataRefresh: true)
        try await Task.sleep(nanoseconds: 370_000_000)
    }
    #expect(reader.count == 1)
    #expect(source.snapshot()?.currentTrack?.duration == nil)
}

@Test("切歌超时清掉疑似旧时长后仍能补回当前曲时长")
@MainActor
func deferredTimeoutRecoversSanitizedDuration() async throws {
    let reader = DurationReadFixture(data: try JSONSerialization.data(withJSONObject: durationFixture(180.0)))
    let source = MediaRemoteAdapterStreamSource(runningQishuiProcessIdentifiersProvider: { [123] },
        metadataDataReader: { reader.read() })
    let now = Date()
    var old = durationFixture(180.0)
    old["title"] = "Previous Song"; old["artist"] = "Previous Artist"
    old["album"] = "Previous Album"; old["contentItemIdentifier"] = "previous-recording"
    old["artworkData"] = Data([9, 8]).base64EncodedString()
    _ = source.ingestStreamEnvelopeForTesting(try durationEnvelope(old), receivedAt: now, receivedUptime: 100)
    // New recording with the old duration is conservatively deferred and sanitized.
    _ = source.ingestStreamEnvelopeForTesting(try durationEnvelope(durationFixture(180.0)),
        receivedAt: now.addingTimeInterval(0.1), receivedUptime: 100.1)
    let timedOut = source.forceDeferredTrackPublicationForTesting(receivedAt: now.addingTimeInterval(2.5),
        receivedUptime: 102.5, schedulesMetadataRefresh: true)
    #expect(timedOut?.currentTrack?.title == "Song A")
    #expect(timedOut?.currentTrack?.duration == nil)
    let deadline = Date().addingTimeInterval(0.5)
    while source.snapshot()?.currentTrack?.duration == nil, Date() < deadline {
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    #expect(source.snapshot()?.currentTrack?.duration == 180)
    #expect(reader.count == 1)
    #expect(source.snapshot()?.currentTrack?.isPlaying == true)
}
