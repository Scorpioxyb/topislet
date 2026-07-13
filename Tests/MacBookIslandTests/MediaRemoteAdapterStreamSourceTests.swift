import Foundation
import Testing
@testable import MacBookIsland

@Test("汽水会话失效后不能恢复上一首歌曲")
@MainActor
func invalidatedQishuiSessionCannotRestorePreviousTrack() throws {
    let source = MediaRemoteAdapterStreamSource()
    let startedAt = Date(timeIntervalSince1970: 900)
    let initial = Data(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.soda.music","contentItemIdentifier":"song-a","title":"Song A","artist":"Artist A","duration":180,"playing":1,"elapsedTimeNow":30}}"#.utf8)
    let latePosition = Data(#"{"type":"data","diff":true,"payload":{"elapsedTimeNow":31,"playing":1}}"#.utf8)

    let first = try #require(source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 90
    ))
    let previousGeneration = source.metadataRequestGenerationForTesting()
    #expect(first.currentTrack?.title == "Song A")
    #expect(source.hasVerifiedQishuiClientState())

    source.invalidateQishuiSession()

    #expect(source.snapshot() == nil)
    #expect(!source.hasVerifiedQishuiClientState())
    #expect(source.metadataRequestGenerationForTesting() > previousGeneration)

    let afterLatePosition = source.ingestStreamEnvelopeForTesting(
        latePosition,
        receivedAt: startedAt.addingTimeInterval(1),
        receivedUptime: 91
    )
    #expect(afterLatePosition?.currentTrack == nil)
}

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

@Test("切歌候选不能发布新歌名与上一首元数据的混合状态")
@MainActor
func trackTransitionRetainsPreviousCompleteSnapshotUntilAtomicCommit() throws {
    let source = MediaRemoteAdapterStreamSource()
    let startedAt = Date(timeIntervalSince1970: 2_000)
    let artworkA = Data([0x01, 0x02, 0x03])
    let artworkB = Data([0x04, 0x05, 0x06])

    let initial = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-a",
        "title": "I Just Might",
        "artist": "Bruno Mars",
        "album": "I Just Might",
        "duration": 196.5,
        "playing": 1,
        "artworkData": artworkA.base64EncodedString()
    ])
    let transitional = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "temporary-song-b",
        "title": "Plot Twist",
        "artist": "Bruno Mars",
        "album": "I Just Might",
        "duration": 196.5,
        "playing": 1
    ])
    let complete = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-b",
        "title": "Plot Twist",
        "artist": "Drake",
        "album": "ICEMAN",
        "duration": 195.7,
        "playing": 1,
        "artworkData": artworkB.base64EncodedString()
    ])

    let first = try #require(source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 200
    ))
    let staged = try #require(source.ingestStreamEnvelopeForTesting(
        transitional,
        receivedAt: startedAt.addingTimeInterval(0.1),
        receivedUptime: 200.1
    ))
    let polled = try #require(source.snapshot())

    #expect(staged.currentTrack?.title == "I Just Might")
    #expect(staged.currentTrack?.artist == "Bruno Mars")
    #expect(staged.currentTrack?.artworkData == artworkA)
    #expect(polled == staged)
    #expect(staged.sampleID == first.sampleID)

    let committed = try #require(source.ingestStreamEnvelopeForTesting(
        complete,
        receivedAt: startedAt.addingTimeInterval(1.1),
        receivedUptime: 201.1
    ))
    let track = try #require(committed.currentTrack)
    #expect(track.title == "Plot Twist")
    #expect(track.artist == "Drake")
    #expect(track.album == "ICEMAN")
    #expect(track.artworkData == artworkB)
    #expect(committed.sampleID == first.sampleID + 1)
}

@Test("同名媒体项只变更 contentItemIdentifier 时仍进入切歌门控")
@MainActor
func contentIdentifierChangeDefersSameTitleTransition() throws {
    let source = MediaRemoteAdapterStreamSource()
    let startedAt = Date(timeIntervalSince1970: 3_000)
    let initial = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "same-title-a",
        "title": "Intro",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 90.0,
        "artworkData": Data([0x0A]).base64EncodedString()
    ])
    let transitional = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "same-title-b",
        "title": "Intro",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 90.0
    ])

    _ = source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 300
    )
    let staged = try #require(source.ingestStreamEnvelopeForTesting(
        transitional,
        receivedAt: startedAt.addingTimeInterval(0.1),
        receivedUptime: 300.1
    )?.currentTrack)

    #expect(staged.artist == "Artist A")
    #expect(staged.artworkData == Data([0x0A]))
}

@Test("任一确认来自上一首的歌手或封面都不能提前提交")
@MainActor
func singleCarriedMetadataFieldStillDefersTransition() throws {
    let startedAt = Date(timeIntervalSince1970: 3_200)
    let artworkA = Data([0x41])
    let artworkB = Data([0x42])

    let initial = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-a",
        "title": "Song A",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 100.0,
        "artworkData": artworkA.base64EncodedString()
    ])

    let oldArtworkSource = MediaRemoteAdapterStreamSource()
    _ = oldArtworkSource.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 320
    )
    let oldArtworkCandidate = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-b",
        "title": "Song B",
        "artist": "Artist B",
        "album": "Album B",
        "duration": 101.0,
        "artworkData": artworkA.base64EncodedString()
    ])
    let afterOldArtwork = try #require(oldArtworkSource.ingestStreamEnvelopeForTesting(
        oldArtworkCandidate,
        receivedAt: startedAt.addingTimeInterval(0.1),
        receivedUptime: 320.1
    )?.currentTrack)
    #expect(afterOldArtwork.title == "Song A")
    #expect(afterOldArtwork.artworkData == artworkA)

    let oldArtistSource = MediaRemoteAdapterStreamSource()
    _ = oldArtistSource.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 320
    )
    let oldArtistCandidate = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-b",
        "title": "Song B",
        "artist": "Artist A",
        "album": "Album B",
        "duration": 101.0,
        "artworkData": artworkB.base64EncodedString()
    ])
    let afterOldArtist = try #require(oldArtistSource.ingestStreamEnvelopeForTesting(
        oldArtistCandidate,
        receivedAt: startedAt.addingTimeInterval(0.1),
        receivedUptime: 320.1
    )?.currentTrack)
    #expect(afterOldArtist.title == "Song A")
    #expect(afterOldArtist.artist == "Artist A")
}

@Test("A 到 B 到 C 超时降级会清除从 B 继承的全部元数据")
@MainActor
func rapidTransitionFallbackDropsIntermediateMetadata() throws {
    let source = MediaRemoteAdapterStreamSource()
    let startedAt = Date(timeIntervalSince1970: 3_300)
    let initial = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-a",
        "title": "Song A",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 100.0,
        "artworkData": Data([0x51]).base64EncodedString()
    ])
    let songB = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-b",
        "title": "Song B",
        "artist": "Artist B",
        "album": "Album A",
        "duration": 110.0,
        "artworkData": Data([0x52]).base64EncodedString()
    ])
    let songCCarryingB = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-c",
        "title": "Song C",
        "artist": "Artist B",
        "album": "Album A",
        "duration": 110.0,
        "artworkData": Data([0x52]).base64EncodedString()
    ])

    _ = source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 330
    )
    _ = source.ingestStreamEnvelopeForTesting(
        songB,
        receivedAt: startedAt.addingTimeInterval(0.1),
        receivedUptime: 330.1
    )
    let beforeFallback = try #require(source.ingestStreamEnvelopeForTesting(
        songCCarryingB,
        receivedAt: startedAt.addingTimeInterval(0.2),
        receivedUptime: 330.2
    )?.currentTrack)
    #expect(beforeFallback.title == "Song A")

    let fallback = try #require(source.forceDeferredTrackPublicationForTesting(
        receivedAt: startedAt.addingTimeInterval(2.7),
        receivedUptime: 332.7
    )?.currentTrack)
    #expect(fallback.title == "Song C")
    #expect(fallback.artist == "汽水音乐")
    #expect(fallback.album == nil)
    #expect(fallback.duration == nil)
    #expect(fallback.artworkData == nil)
}

@Test("自然切歌空 payload 不能清空已提交曲目或绕过后续门控")
@MainActor
func emptyTransitionPayloadRetainsCommittedTrack() throws {
    let source = MediaRemoteAdapterStreamSource()
    let startedAt = Date(timeIntervalSince1970: 3_500)
    let initialArtwork = Data([0x31])
    let initial = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-a",
        "title": "Song A",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 120.0,
        "artworkData": initialArtwork.base64EncodedString()
    ])
    let empty = try streamEnvelope([:])
    let nextWithoutArtwork = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-b",
        "title": "Song B",
        "artist": "Artist B",
        "album": "Album B",
        "duration": 121.0
    ])

    let committed = try #require(source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 350
    ))
    let afterEmpty = try #require(source.ingestStreamEnvelopeForTesting(
        empty,
        receivedAt: startedAt.addingTimeInterval(0.1),
        receivedUptime: 350.1
    ))
    let afterNextText = try #require(source.ingestStreamEnvelopeForTesting(
        nextWithoutArtwork,
        receivedAt: startedAt.addingTimeInterval(0.2),
        receivedUptime: 350.2
    ))

    #expect(afterEmpty == committed)
    #expect(afterNextText == committed)
    #expect(source.snapshot() == committed)
    #expect(afterNextText.currentTrack?.artworkData == initialArtwork)
}

@Test("切歌超时降级不能沿用上一首歌手专辑时长或封面")
@MainActor
func timeoutFallbackDropsCarriedMetadata() throws {
    let source = MediaRemoteAdapterStreamSource()
    let startedAt = Date(timeIntervalSince1970: 4_000)
    let oldArtwork = Data([0x11, 0x12])
    let initial = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-a",
        "title": "Song A",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 180.0,
        "artworkData": oldArtwork.base64EncodedString()
    ])
    let transitional = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-b",
        "title": "Song B",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 180.0,
        "artworkData": oldArtwork.base64EncodedString()
    ])

    _ = source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 400
    )
    _ = source.ingestStreamEnvelopeForTesting(
        transitional,
        receivedAt: startedAt.addingTimeInterval(0.1),
        receivedUptime: 400.1
    )
    let fallback = try #require(source.forceDeferredTrackPublicationForTesting(
        receivedAt: startedAt.addingTimeInterval(2.5),
        receivedUptime: 402.5
    )?.currentTrack)

    #expect(fallback.title == "Song B")
    #expect(fallback.artist == "汽水音乐")
    #expect(fallback.album == nil)
    #expect(fallback.duration == nil)
    #expect(fallback.artworkData == nil)
}

@Test("快速 A 到 B 到 C 时 B 的迟到元数据不能覆盖 C 候选")
@MainActor
func staleMetadataGenerationCannotOverwriteNewerTransition() throws {
    let source = MediaRemoteAdapterStreamSource()
    let startedAt = Date(timeIntervalSince1970: 5_000)
    let initial = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-a",
        "title": "Song A",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 180.0,
        "artworkData": Data([0x21]).base64EncodedString()
    ])
    let songB = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-b",
        "title": "Song B",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 180.0
    ])
    let songC = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-c",
        "title": "Song C",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 180.0
    ])
    let completeC = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-c-final",
        "title": "Song C",
        "artist": "Artist C",
        "album": "Album C",
        "duration": 200.0,
        "artworkData": Data([0x23]).base64EncodedString()
    ])

    _ = source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 500
    )
    _ = source.ingestStreamEnvelopeForTesting(
        songB,
        receivedAt: startedAt.addingTimeInterval(0.1),
        receivedUptime: 500.1
    )
    let songBGeneration = source.metadataRequestGenerationForTesting()
    _ = source.ingestStreamEnvelopeForTesting(
        songC,
        receivedAt: startedAt.addingTimeInterval(0.2),
        receivedUptime: 500.2
    )

    let afterStaleResponse = try #require(source.applyMetadataPayloadForTesting(
        [
            "artist": "Artist B",
            "album": "Album B",
            "artworkData": Data([0x22]).base64EncodedString()
        ],
        receivedAt: startedAt.addingTimeInterval(0.3),
        receivedUptime: 500.3,
        requestGeneration: songBGeneration
    )?.currentTrack)
    #expect(afterStaleResponse.title == "Song A")
    #expect(afterStaleResponse.artist == "Artist A")

    let committed = try #require(source.ingestStreamEnvelopeForTesting(
        completeC,
        receivedAt: startedAt.addingTimeInterval(1.0),
        receivedUptime: 501
    )?.currentTrack)
    #expect(committed.title == "Song C")
    #expect(committed.artist == "Artist C")
    #expect(committed.album == "Album C")
    #expect(committed.artworkData == Data([0x23]))
}

@Test("带封面的适配器读取挂起时会在硬超时内终止")
func artworkReadHasHardProcessTimeout() {
    let script = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/hanging-mediaremote-adapter.pl")
    let startedAt = Date()
    let data = MediaRemoteAdapterStreamSource.runGetDataForTesting(
        script: script,
        includeArtwork: true
    )
    let elapsed = Date().timeIntervalSince(startedAt)

    #expect(data == nil)
    #expect(elapsed >= 0.8)
    #expect(elapsed < 1.8)
}

private func streamEnvelope(_ payload: [String: Any], diff: Bool = false) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "type": "data",
        "diff": diff,
        "payload": payload
    ])
}
