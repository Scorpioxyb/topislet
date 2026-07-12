import Foundation
import Testing
@testable import MacBookIsland

@Test("元数据差分不能把缓存的 elapsedTimeNow 重新锚定为旧进度")
@MainActor
func metadataDiffDoesNotReanchorCachedElapsedTimeNow() throws {
    let source = MediaRemoteAdapterStreamSource()
    let startedAt = Date(timeIntervalSince1970: 1_000)
    let initial = Data(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.soda.music","contentItemIdentifier":"song-a","title":"SLOW MOTION","artist":"Jonah Marais","album":"SLOW MOTION REMIXES","duration":187,"playing":1,"playbackRate":1,"elapsedTimeNow":11}}"#.utf8)
    let metadataDiff = Data(#"{"type":"data","diff":true,"payload":{"album":"SLOW MOTION REMIXES"}}"#.utf8)

    let first = try #require(source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 100
    )?.currentTrack)
    let afterMetadata = try #require(source.ingestStreamEnvelopeForTesting(
        metadataDiff,
        receivedAt: startedAt.addingTimeInterval(18),
        receivedUptime: 118
    )?.currentTrack)

    #expect(first.elapsedTime == 11)
    #expect(abs((afterMetadata.elapsedTime ?? 0) - 29) < 0.0001)
}

@Test("位置差分使用完整 mergedPayload 身份并采纳最新 elapsedTimeNow")
@MainActor
func positionDiffUsesMergedMetadataAndFreshTimeline() throws {
    let source = MediaRemoteAdapterStreamSource()
    let startedAt = Date(timeIntervalSince1970: 1_000)
    let initial = Data(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.soda.music","contentItemIdentifier":"song-a","title":"SLOW MOTION","artist":"Jonah Marais","duration":187,"playing":1,"playbackRate":1,"elapsedTime":11,"elapsedTimeNow":11,"timestamp":"1970-01-01T00:16:28Z"}}"#.utf8)
    _ = source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 100
    )

    let refreshed = try #require(source.applyPlaybackPositionPayloadForTesting(
        [
            "elapsedTime": 11.0,
            "elapsedTimeNow": 29.0,
            "timestamp": "1970-01-01T00:16:28Z",
            "playing": 1,
            "playbackRate": 1.0
        ],
        receivedAt: startedAt.addingTimeInterval(18),
        receivedUptime: 118
    )?.currentTrack)

    #expect(refreshed.title == "SLOW MOTION")
    #expect(abs((refreshed.elapsedTime ?? 0) - 29) < 0.0001)
}

@Test("metadata 回包携带的旧时间字段不能覆盖当前权威锚点")
@MainActor
func metadataResponseCannotOverwriteTimeline() throws {
    let source = MediaRemoteAdapterStreamSource()
    let startedAt = Date(timeIntervalSince1970: 1_000)
    let initial = Data(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.soda.music","contentItemIdentifier":"song-a","title":"SLOW MOTION","artist":"Jonah Marais","duration":187,"playing":1,"playbackRate":1,"elapsedTimeNow":11}}"#.utf8)
    _ = source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 100
    )
    _ = source.applyPlaybackPositionPayloadForTesting(
        ["elapsedTimeNow": 29.0, "playing": 1, "playbackRate": 1.0],
        receivedAt: startedAt.addingTimeInterval(18),
        receivedUptime: 118
    )

    let afterMetadata = try #require(source.applyMetadataPayloadForTesting(
        [
            "bundleIdentifier": "com.soda.music",
            "contentItemIdentifier": "song-a",
            "title": "SLOW MOTION",
            "artist": "Jonah Marais",
            "album": "SLOW MOTION REMIXES",
            "duration": 187.0,
            "playing": 1,
            "playbackRate": 1.0,
            "elapsedTimeNow": 11.0
        ],
        receivedAt: startedAt.addingTimeInterval(19),
        receivedUptime: 119
    )?.currentTrack)

    #expect(afterMetadata.album == "SLOW MOTION REMIXES")
    #expect(abs((afterMetadata.elapsedTime ?? 0) - 30) < 0.0001)
}
