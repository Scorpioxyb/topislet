import Foundation
import Testing
@testable import MacBookIsland

@Test("汽水会话失效后不能恢复上一首歌曲")
@MainActor
func invalidatedQishuiSessionCannotRestorePreviousTrack() throws {
    let source = makeStreamSource()
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

@Test("轮询旧 payload 不能伪造新鲜播放证据")
@MainActor
func pollingMergedPayloadDoesNotRefreshPlaybackEvidence() throws {
    let source = makeStreamSource()
    let startedAt = Date(timeIntervalSince1970: 950)
    let initial = Data(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.soda.music","contentItemIdentifier":"song-a","title":"Song A","artist":"Artist A","duration":180,"playing":1,"elapsedTimeNow":30}}"#.utf8)

    _ = source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 95
    )

    #expect(source.hasFreshVerifiedPlaybackEvidence(
        at: startedAt.addingTimeInterval(0.5),
        maxAge: 1.0
    ))
    _ = source.snapshot()
    #expect(!source.hasFreshVerifiedPlaybackEvidence(
        at: startedAt.addingTimeInterval(2.0),
        maxAge: 1.0
    ))
}

@Test("纯元数据事件不能延长播放证据有效期")
@MainActor
func metadataOnlyEventDoesNotRefreshPlaybackEvidence() throws {
    let source = makeStreamSource()
    let startedAt = Date(timeIntervalSince1970: 980)
    let initial = Data(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.soda.music","contentItemIdentifier":"song-a","title":"Song A","artist":"Artist A","duration":180,"playing":1,"elapsedTimeNow":30}}"#.utf8)
    let metadata = Data(#"{"type":"data","diff":true,"payload":{"album":"Album A"}}"#.utf8)

    _ = source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 98
    )
    _ = source.ingestStreamEnvelopeForTesting(
        metadata,
        receivedAt: startedAt.addingTimeInterval(2),
        receivedUptime: 100
    )

    #expect(!source.hasFreshVerifiedPlaybackEvidence(
        at: startedAt.addingTimeInterval(2.1),
        maxAge: 1.0
    ))
}

@Test("同曲播放事件缺少媒体 ID 时保留完整元数据")
@MainActor
func sparseSameTrackPlaybackEventKeepsMetadata() throws {
    let source = makeStreamSource()
    let startedAt = Date(timeIntervalSince1970: 985)
    let artwork = Data([0x01, 0x02, 0x03])
    let initial = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "processIdentifier": 123,
        "contentItemIdentifier": "song-a",
        "title": "Song A",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 180.0,
        "playing": 0,
        "elapsedTimeNow": 30.0,
        "artworkData": artwork.base64EncodedString()
    ])
    let playbackUpdate = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "processIdentifier": 123,
        "title": "Song A",
        "playing": 1,
        "elapsedTimeNow": 31.0
    ])

    _ = source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 98.5
    )
    let updated = try #require(source.ingestStreamEnvelopeForTesting(
        playbackUpdate,
        receivedAt: startedAt.addingTimeInterval(1),
        receivedUptime: 99.5
    )?.currentTrack)

    #expect(updated.title == "Song A")
    #expect(updated.artist == "Artist A")
    #expect(updated.album == "Album A")
    #expect(updated.duration == 180)
    #expect(updated.artworkData == artwork)
    #expect(updated.isPlaying == true)
    #expect(updated.elapsedTime == 31)

    let singleStableFieldUpdate = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "processIdentifier": 123,
        "contentItemIdentifier": "song-a-volatile",
        "title": "Song A",
        "artist": "Artist A",
        "playing": 0,
        "elapsedTimeNow": 32.0
    ])
    let afterSingleStableField = try #require(source.ingestStreamEnvelopeForTesting(
        singleStableFieldUpdate,
        receivedAt: startedAt.addingTimeInterval(1.2),
        receivedUptime: 99.7
    )?.currentTrack)
    #expect(afterSingleStableField.artist == "Artist A")
    #expect(afterSingleStableField.album == "Album A")
    #expect(afterSingleStableField.artworkData == artwork)
    #expect(afterSingleStableField.isPlaying == false)
    #expect(!source.hasFreshVerifiedPlaybackEvidence(
        at: startedAt.addingTimeInterval(1.3),
        maxAge: 0.5
    ))

    let completeNextTrack = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "processIdentifier": 123,
        "contentItemIdentifier": "song-b",
        "title": "Song A",
        "artist": "Artist B",
        "album": "Album B",
        "duration": 200.0,
        "playing": 1,
        "elapsedTimeNow": 0.5
    ])
    let staged = try #require(source.ingestStreamEnvelopeForTesting(
        completeNextTrack,
        receivedAt: startedAt.addingTimeInterval(2),
        receivedUptime: 100.5
    )?.currentTrack)
    #expect(staged.artist == "Artist A")
    #expect(staged.album == "Album A")
    #expect(staged.artworkData == artwork)
}

@Test("汽水新进程发布后拒绝旧 PID 迟到事件")
@MainActor
func retiredQishuiProcessCannotOverwriteRelaunchedProcess() throws {
    let source = MediaRemoteAdapterStreamSource(
        runningQishuiProcessIdentifiersProvider: { [111, 222] }
    )
    let startedAt = Date(timeIntervalSince1970: 1_100)
    let oldProcess = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "processIdentifier": 111,
        "contentItemIdentifier": "old-session",
        "title": "Song A",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 180.0,
        "playing": 1,
        "elapsedTimeNow": 30.0
    ])
    let newProcess = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "processIdentifier": 222,
        "contentItemIdentifier": "new-session",
        "title": "Song A",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 180.0,
        "playing": 0,
        "elapsedTimeNow": 4.0
    ])

    _ = source.ingestStreamEnvelopeForTesting(
        oldProcess,
        receivedAt: startedAt,
        receivedUptime: 110
    )
    source.invalidateQishuiSession(at: startedAt.addingTimeInterval(0.1))
    let relaunched = try #require(source.ingestStreamEnvelopeForTesting(
        newProcess,
        receivedAt: startedAt.addingTimeInterval(0.2),
        receivedUptime: 110.2
    )?.currentTrack)
    let afterLateOldProcess = try #require(source.ingestStreamEnvelopeForTesting(
        oldProcess,
        receivedAt: startedAt.addingTimeInterval(0.3),
        receivedUptime: 110.3
    )?.currentTrack)

    #expect(relaunched.sourceProcessIdentifier == 222)
    #expect(relaunched.isPlaying == false)
    #expect(relaunched.elapsedTime == 4)
    #expect(afterLateOldProcess == relaunched)

    let afterLatePosition = try #require(source.applyPlaybackPositionPayloadForTesting(
        [
            "bundleIdentifier": "com.soda.music",
            "processIdentifier": 111,
            "contentItemIdentifier": "old-session",
            "title": "Song A",
            "artist": "Artist A",
            "album": "Album A",
            "duration": 180.0,
            "playing": 1,
            "elapsedTimeNow": 99.0
        ],
        receivedAt: startedAt.addingTimeInterval(1),
        receivedUptime: 111
    )?.currentTrack)
    #expect(afterLatePosition == relaunched)
    #expect(!source.hasFreshVerifiedPlaybackEvidence(
        at: startedAt.addingTimeInterval(1.1),
        maxAge: 0.5
    ))
}

@Test("汽水 bundle 与 PID 必须指向同一运行实例")
@MainActor
func qishuiBundleAndProcessIdentityMustAgree() throws {
    let runningPIDs: Set<pid_t> = [222]
    #expect(MediaRemoteAdapterStreamSource.processIdentityIsConsistent(
        bundleIdentifier: "com.soda.music",
        processIdentifier: 222,
        runningQishuiProcessIdentifiers: runningPIDs
    ))
    #expect(!MediaRemoteAdapterStreamSource.processIdentityIsConsistent(
        bundleIdentifier: "com.soda.music",
        processIdentifier: 333,
        runningQishuiProcessIdentifiers: runningPIDs
    ))
    #expect(!MediaRemoteAdapterStreamSource.processIdentityIsConsistent(
        bundleIdentifier: "com.example.video",
        processIdentifier: 222,
        runningQishuiProcessIdentifiers: runningPIDs
    ))
    #expect(MediaRemoteAdapterStreamSource.processIdentityIsConsistent(
        bundleIdentifier: nil,
        processIdentifier: nil,
        runningQishuiProcessIdentifiers: runningPIDs
    ))
    #expect(!MediaRemoteAdapterStreamSource.processIdentityIsConsistent(
        bundleIdentifier: "com.soda.music",
        processIdentifier: 222,
        runningQishuiProcessIdentifiers: []
    ))
    #expect(!MediaRemoteAdapterStreamSource.processIdentityIsConsistent(
        bundleIdentifier: "com.soda.music",
        processIdentifier: nil,
        runningQishuiProcessIdentifiers: [222, 333]
    ))

    let stoppedSource = MediaRemoteAdapterStreamSource(
        runningQishuiProcessIdentifiersProvider: { [] }
    )
    let stalePayload = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "processIdentifier": 222,
        "title": "Stale Song",
        "playing": 1,
        "elapsedTimeNow": 42.0
    ])
    #expect(stoppedSource.ingestStreamEnvelopeForTesting(
        stalePayload,
        receivedAt: Date(timeIntervalSince1970: 1_200),
        receivedUptime: 120
    ) == nil)
}

@Test("同名稀疏新曲不能继承上一首进度")
@MainActor
func sparseSameTitleReplacementDoesNotReuseTimeline() throws {
    let source = makeStreamSource()
    let startedAt = Date(timeIntervalSince1970: 1_300)
    let initial = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "processIdentifier": 123,
        "contentItemIdentifier": "first-item",
        "title": "Intro",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 180.0,
        "playing": 1,
        "elapsedTimeNow": 60.0,
        "artworkData": Data([0x01]).base64EncodedString()
    ])
    let sparseReplacement = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "processIdentifier": 123,
        "contentItemIdentifier": "second-item",
        "title": "Intro",
        "artworkData": Data([0x02]).base64EncodedString()
    ])

    _ = source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 130
    )
    let replacement = try #require(source.ingestStreamEnvelopeForTesting(
        sparseReplacement,
        receivedAt: startedAt.addingTimeInterval(1),
        receivedUptime: 131
    )?.currentTrack)

    #expect(replacement.title == "Intro")
    #expect(replacement.artist == "汽水音乐")
    #expect(replacement.elapsedTime == nil)
    #expect(replacement.artworkData == Data([0x02]))
}

@Test("汽水 PID 切换后不能沿用旧进度锚点")
@MainActor
func qishuiProcessSwitchClearsPlaybackTimeline() throws {
    let source = MediaRemoteAdapterStreamSource(
        runningQishuiProcessIdentifiersProvider: { [111, 222] }
    )
    let startedAt = Date(timeIntervalSince1970: 1_400)
    let initial = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "processIdentifier": 111,
        "contentItemIdentifier": "old-process-item",
        "title": "Same Song",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 180.0,
        "playing": 1,
        "elapsedTimeNow": 70.0,
        "artworkData": Data([0x03]).base64EncodedString()
    ])
    let relaunched = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "processIdentifier": 222,
        "contentItemIdentifier": "new-process-item",
        "title": "Same Song",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 180.0,
        "artworkData": Data([0x04]).base64EncodedString()
    ])

    _ = source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 140
    )
    _ = source.ingestStreamEnvelopeForTesting(
        relaunched,
        receivedAt: startedAt.addingTimeInterval(1),
        receivedUptime: 141
    )
    let replacement = try #require(source.forceDeferredTrackPublicationForTesting(
        receivedAt: startedAt.addingTimeInterval(2.5),
        receivedUptime: 142.5
    )?.currentTrack)

    #expect(replacement.sourceProcessIdentifier == 222)
    #expect(replacement.elapsedTime == nil)
}

@Test("唯一新进程可补全缺失 PID 并切换会话")
@MainActor
func uniqueRunningQishuiProcessResolvesMissingPayloadPID() throws {
    var runningProcessIdentifiers: Set<pid_t> = [111]
    let source = MediaRemoteAdapterStreamSource(
        runningQishuiProcessIdentifiersProvider: { runningProcessIdentifiers }
    )
    let startedAt = Date(timeIntervalSince1970: 1_500)
    let initial = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "processIdentifier": 111,
        "contentItemIdentifier": "old-process-item",
        "title": "Same Song",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 180.0,
        "playing": 1,
        "elapsedTimeNow": 80.0,
        "artworkData": Data([0x05]).base64EncodedString()
    ])
    let firstPayloadWithoutPID = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "new-process-item",
        "title": "Same Song",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 180.0,
        "artworkData": Data([0x06]).base64EncodedString()
    ])

    _ = source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 150
    )
    runningProcessIdentifiers = [222]
    _ = source.ingestStreamEnvelopeForTesting(
        firstPayloadWithoutPID,
        receivedAt: startedAt.addingTimeInterval(1),
        receivedUptime: 151
    )
    let replacement = try #require(source.forceDeferredTrackPublicationForTesting(
        receivedAt: startedAt.addingTimeInterval(2.5),
        receivedUptime: 152.5
    )?.currentTrack)

    #expect(replacement.sourceProcessIdentifier == 222)
    #expect(replacement.elapsedTime == nil)
}

@Test("同名异媒体 ID 只共享一个稳定字段时不能复用时间轴")
@MainActor
func oneSharedStableFieldCannotAuthorizeTimelineReuse() {
    let source = makeStreamSource()
    let current: [String: Any] = [
        "bundleIdentifier": "com.soda.music",
        "processIdentifier": 123,
        "contentItemIdentifier": "first-item",
        "title": "Intro",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 180.0
    ]
    let oneSharedField: [String: Any] = [
        "bundleIdentifier": "com.soda.music",
        "processIdentifier": 123,
        "contentItemIdentifier": "second-item",
        "title": "Intro",
        "artist": "Artist A"
    ]
    var sameMediaItem = oneSharedField
    sameMediaItem["contentItemIdentifier"] = "first-item"

    #expect(!source.timelineIdentitiesMatchForTesting(current, oneSharedField))
    #expect(source.timelineIdentitiesMatchForTesting(current, sameMediaItem))
}

@Test("旧 PID 的同名元数据回包不能覆盖当前进程")
@MainActor
func staleProcessMetadataCannotOverwriteCurrentProcess() throws {
    let source = MediaRemoteAdapterStreamSource(
        runningQishuiProcessIdentifiersProvider: { [111, 222] }
    )
    let startedAt = Date(timeIntervalSince1970: 1_600)
    let currentArtwork = Data([0x20])
    let current = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "processIdentifier": 222,
        "contentItemIdentifier": "current-item",
        "title": "Same Song",
        "artist": "Artist A",
        "album": "Current Album",
        "duration": 180.0,
        "playing": 1,
        "elapsedTimeNow": 12.0,
        "artworkData": currentArtwork.base64EncodedString()
    ])

    _ = source.ingestStreamEnvelopeForTesting(
        current,
        receivedAt: startedAt,
        receivedUptime: 160
    )
    let afterStaleMetadata = try #require(source.applyMetadataPayloadForTesting(
        [
            "bundleIdentifier": "com.soda.music",
            "processIdentifier": 111,
            "contentItemIdentifier": "old-item",
            "title": "Same Song",
            "artist": "Artist A",
            "album": "Old Album",
            "artworkData": Data([0x21]).base64EncodedString()
        ],
        receivedAt: startedAt.addingTimeInterval(1),
        receivedUptime: 161
    )?.currentTrack)

    #expect(afterStaleMetadata.sourceProcessIdentifier == 222)
    #expect(afterStaleMetadata.album == "Current Album")
    #expect(afterStaleMetadata.artworkData == currentArtwork)
}

@Test("切歌门控期间不能用新曲证据授权上一首快照")
@MainActor
func deferredTrackTransitionInvalidatesPlaybackEvidence() throws {
    let source = makeStreamSource()
    let startedAt = Date(timeIntervalSince1970: 990)
    let initial = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-a",
        "title": "Song A",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 180.0,
        "playing": 1,
        "artworkData": Data([0x01]).base64EncodedString()
    ])
    let transition = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-b",
        "title": "Song B",
        "artist": "Artist B",
        "album": "Album B",
        "duration": 200.0,
        "playing": 0
    ])

    let committed = try #require(source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 99
    ))
    let deferred = try #require(source.ingestStreamEnvelopeForTesting(
        transition,
        receivedAt: startedAt.addingTimeInterval(0.2),
        receivedUptime: 99.2
    ))

    #expect(committed.currentTrack?.title == "Song A")
    #expect(deferred.currentTrack?.title == "Song A")
    #expect(!source.hasFreshVerifiedPlaybackEvidence(
        at: startedAt.addingTimeInterval(0.3),
        maxAge: 1.0
    ))
}

@Test("切歌门控期间位置刷新成功也不能授权旧快照")
@MainActor
func deferredPositionRefreshCannotAuthorizePreviousSnapshot() throws {
    let source = makeStreamSource()
    let startedAt = Date(timeIntervalSince1970: 995)
    let initial = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-a",
        "title": "Song A",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 180.0,
        "playing": 1,
        "artworkData": Data([0x01]).base64EncodedString()
    ])
    let transition = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "song-b",
        "title": "Song B",
        "artist": "Artist B",
        "album": "Album B",
        "duration": 200.0,
        "playing": 0
    ])

    _ = source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 99.5
    )
    _ = source.ingestStreamEnvelopeForTesting(
        transition,
        receivedAt: startedAt.addingTimeInterval(0.2),
        receivedUptime: 99.7
    )
    let refreshed = try #require(source.applyPlaybackPositionPayloadForTesting(
        [
            "contentItemIdentifier": "song-b",
            "elapsedTimeNow": 0.0,
            "playing": 0,
            "playbackRate": 0.0
        ],
        receivedAt: startedAt.addingTimeInterval(0.3),
        receivedUptime: 99.8
    ))

    #expect(refreshed.currentTrack?.title == "Song A")
    #expect(!source.hasFreshVerifiedPlaybackEvidence(
        at: startedAt.addingTimeInterval(0.4),
        maxAge: 1.0
    ))
}

@Test("元数据差分不能把缓存的 elapsedTimeNow 重新锚定为旧进度")
@MainActor
func metadataDiffDoesNotReanchorCachedElapsedTimeNow() throws {
    let source = makeStreamSource()
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
    let source = makeStreamSource()
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
    let source = makeStreamSource()
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
    let source = makeStreamSource()
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

@Test("十次连续切歌始终原子提交完整元数据")
@MainActor
func tenSequentialTrackTransitionsNeverPublishMixedMetadata() throws {
    let source = makeStreamSource()
    let startedAt = Date(timeIntervalSince1970: 2_500)
    let processIdentifier: pid_t = 123

    func trackPayload(_ index: Int, temporary: Bool = false) -> [String: Any] {
        [
            "bundleIdentifier": "com.soda.music",
            "processIdentifier": processIdentifier,
            "contentItemIdentifier": temporary ? "temporary-\(index)" : "song-\(index)",
            "title": "Song \(index)",
            "artist": "Artist \(index)",
            "album": "Album \(index)",
            "duration": 180.0 + Double(index),
            "elapsedTimeNow": Double(index),
            "playing": 1,
            "playbackRate": 1.0,
            "artworkData": Data([UInt8(index), 0xA5]).base64EncodedString()
        ]
    }

    let initial = try #require(source.ingestStreamEnvelopeForTesting(
        streamEnvelope(trackPayload(0)),
        receivedAt: startedAt,
        receivedUptime: 250
    ))
    var committedSnapshot = initial

    for index in 1...10 {
        let roundStartedAt = startedAt.addingTimeInterval(Double(index) * 2)
        let previousTrack = try #require(committedSnapshot.currentTrack)
        var sparsePayload = trackPayload(index, temporary: true)
        sparsePayload["artist"] = previousTrack.artist
        sparsePayload["album"] = previousTrack.album
        sparsePayload["duration"] = previousTrack.duration
        sparsePayload["artworkData"] = previousTrack.artworkData?.base64EncodedString()

        let staged = try #require(source.ingestStreamEnvelopeForTesting(
            streamEnvelope(sparsePayload),
            receivedAt: roundStartedAt,
            receivedUptime: 250 + Double(index) * 2
        ))
        #expect(staged == committedSnapshot)

        let staleGeneration = source.metadataRequestGenerationForTesting()
        let committed = try #require(source.ingestStreamEnvelopeForTesting(
            streamEnvelope(trackPayload(index)),
            receivedAt: roundStartedAt.addingTimeInterval(1.1),
            receivedUptime: 251.1 + Double(index) * 2
        ))
        let committedTrack = try #require(committed.currentTrack)

        #expect(committed.sampleID == initial.sampleID + UInt64(index))
        #expect(committedTrack.title == "Song \(index)")
        #expect(committedTrack.artist == "Artist \(index)")
        #expect(committedTrack.album == "Album \(index)")
        #expect(committedTrack.duration == 180.0 + Double(index))
        #expect(committedTrack.artworkData == Data([UInt8(index), 0xA5]))
        #expect(committedTrack.sourceProcessIdentifier == Optional(processIdentifier))

        let afterStaleMetadata = try #require(source.applyMetadataPayloadForTesting(
            trackPayload(index - 1),
            receivedAt: roundStartedAt.addingTimeInterval(1.2),
            receivedUptime: 251.2 + Double(index) * 2,
            requestGeneration: staleGeneration
        ))
        #expect(afterStaleMetadata == committed)
        committedSnapshot = committed
    }

    let finalTrack = try #require(source.snapshot()?.currentTrack)
    #expect(finalTrack.title == "Song 10")
    #expect(finalTrack.artist == "Artist 10")
    #expect(finalTrack.album == "Album 10")
    #expect(finalTrack.artworkData == Data([10, 0xA5]))
}

@Test("同曲播放事件的易变 contentItemIdentifier 不触发切歌门控")
@MainActor
func volatileContentIdentifierDoesNotDeferSameTrackUpdate() throws {
    let source = makeStreamSource()
    let startedAt = Date(timeIntervalSince1970: 3_000)
    let initial = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "same-title-a",
        "title": "Intro",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 90.0,
        "playing": 0,
        "artworkData": Data([0x0A]).base64EncodedString()
    ])
    let playbackUpdate = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "same-title-b",
        "title": "Intro",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 90.0,
        "playing": 1
    ])

    let initialSnapshot = try #require(source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 300
    ))
    let updated = try #require(source.ingestStreamEnvelopeForTesting(
        playbackUpdate,
        receivedAt: startedAt.addingTimeInterval(0.1),
        receivedUptime: 300.1
    )?.currentTrack)

    #expect(updated.artist == "Artist A")
    #expect(updated.album == "Album A")
    #expect(updated.duration == 90)
    #expect(updated.artworkData == Data([0x0A]))
    #expect(updated.isPlaying == true)
    #expect(source.snapshot()?.sampleID == initialSnapshot.sampleID + 1)
}

@Test("同名歌曲的稳定元数据变化仍进入切歌门控")
@MainActor
func sameTitleWithDifferentMetadataStillDefersTransition() throws {
    let source = makeStreamSource()
    let startedAt = Date(timeIntervalSince1970: 3_100)
    let initial = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "same-title-a",
        "title": "Intro",
        "artist": "Artist A",
        "album": "Album A",
        "duration": 90.0,
        "artworkData": Data([0x0A]).base64EncodedString()
    ])
    let transition = try streamEnvelope([
        "bundleIdentifier": "com.soda.music",
        "contentItemIdentifier": "same-title-b",
        "title": "Intro",
        "artist": "Artist B",
        "album": "Album B",
        "duration": 120.0
    ])

    let committed = try #require(source.ingestStreamEnvelopeForTesting(
        initial,
        receivedAt: startedAt,
        receivedUptime: 310
    ))
    let staged = try #require(source.ingestStreamEnvelopeForTesting(
        transition,
        receivedAt: startedAt.addingTimeInterval(0.1),
        receivedUptime: 310.1
    ))

    #expect(staged.currentTrack?.artist == "Artist A")
    #expect(staged.currentTrack?.album == "Album A")
    #expect(staged.currentTrack?.artworkData == Data([0x0A]))
    #expect(staged.sampleID == committed.sampleID)
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

    let oldArtworkSource = makeStreamSource()
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

    let oldArtistSource = makeStreamSource()
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
    let source = makeStreamSource()
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
    let source = makeStreamSource()
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
    let source = makeStreamSource()
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
    let source = makeStreamSource()
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

@Test("MediaRemote stream 停止和新代次会拒绝旧回调")
func streamLifecycleRejectsStaleCallbacks() {
    var lifecycle = MediaRemoteStreamLifecycle()
    let firstGeneration = lifecycle.beginStart()
    #expect(lifecycle.accepts(firstGeneration))

    lifecycle.beginStop()
    #expect(!lifecycle.accepts(firstGeneration))

    let secondGeneration = lifecycle.beginStart()
    #expect(secondGeneration != firstGeneration)
    #expect(!lifecycle.accepts(firstGeneration))
    #expect(lifecycle.accepts(secondGeneration))
}

@Test("MediaRemote stream 子进程忽略 TERM 时使用 KILL 收尾")
func streamProcessTerminationHasKillFallback() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    process.arguments = [
        "-e",
        "$SIG{TERM} = 'IGNORE'; select undef, undef, undef, 30;"
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    usleep(20_000)

    let startedAt = Date()
    MediaRemoteAdapterStreamSource.terminateStreamProcess(
        process,
        graceInterval: 0.05
    )
    let elapsed = Date().timeIntervalSince(startedAt)

    #expect(!process.isRunning)
    #expect(elapsed >= 0.05)
    #expect(elapsed < 0.8)
}

private func streamEnvelope(_ payload: [String: Any], diff: Bool = false) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "type": "data",
        "diff": diff,
        "payload": payload
    ])
}

@MainActor
private func makeStreamSource() -> MediaRemoteAdapterStreamSource {
    MediaRemoteAdapterStreamSource(
        runningQishuiProcessIdentifiersProvider: { [123] }
    )
}
