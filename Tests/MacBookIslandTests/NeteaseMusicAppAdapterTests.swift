import Foundation
import Testing
@testable import MacBookIsland

private func neteaseJSONData(
    bundleIdentifier: String = "com.netease.163music",
    processIdentifier: Int = 62598,
    contentItemIdentifier: String = "first-uuid",
    artworkData: Data? = Data([0xFF, 0xD8, 0xFF]),
    playing: Bool = true
) throws -> Data {
    var payload: [String: Any] = [
        "bundleIdentifier": bundleIdentifier,
        "processIdentifier": processIdentifier,
        "contentItemIdentifier": contentItemIdentifier,
        "title": "Sweet Boy",
        "artist": "Malcolm Todd",
        "album": "Sweet Boy",
        "elapsedTime": 6.125,
        "elapsedTimeNow": 6.125,
        "duration": 180.072,
        "playbackRate": playing ? 1 : 0,
        "playing": playing
    ]
    if let artworkData {
        payload["artworkData"] = artworkData.base64EncodedString()
    }
    return try JSONSerialization.data(withJSONObject: payload)
}

private func neteaseJSONData(
    title: String,
    artist: String,
    album: String,
    duration: TimeInterval,
    artworkData: Data?
) throws -> Data {
    var payload: [String: Any] = [
        "bundleIdentifier": "com.netease.163music",
        "processIdentifier": 62598,
        "title": title,
        "artist": artist,
        "album": album,
        "elapsedTime": 0,
        "duration": duration,
        "playbackRate": 1,
        "playing": true
    ]
    if let artworkData {
        payload["artworkData"] = artworkData.base64EncodedString()
    }
    return try JSONSerialization.data(withJSONObject: payload)
}

@Test("网易云专属 payload 必须同时匹配 Bundle ID 与运行 PID")
func neteasePayloadRequiresBundleAndRunningProcess() throws {
    let observedAt = Date(timeIntervalSince1970: 1_000)
    let payload = try MediaRemoteClientBridge.decode(
        neteaseJSONData(),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: observedAt
    )

    #expect(payload.processIdentifier == 62598)
    #expect(payload.title == "Sweet Boy")
    #expect(payload.artist == "Malcolm Todd")
    #expect(payload.artworkData == Data([0xFF, 0xD8, 0xFF]))
    #expect(payload.elapsedTime == 6.125)

    #expect(throws: MediaRemoteClientBridgeError.unexpectedBundleIdentifier) {
        try MediaRemoteClientBridge.decode(
            neteaseJSONData(bundleIdentifier: "com.apple.Music"),
            expectedBundleIdentifier: "com.netease.163music",
            runningProcessIdentifiers: [62598],
            observedAt: observedAt
        )
    }
    #expect(throws: MediaRemoteClientBridgeError.staleProcessIdentifier) {
        try MediaRemoteClientBridge.decode(
            neteaseJSONData(),
            expectedBundleIdentifier: "com.netease.163music",
            runningProcessIdentifiers: [70000],
            observedAt: observedAt
        )
    }
}

@Test("网易云易变 UUID 不会误判为切歌")
func neteaseVolatileContentIdentifierDoesNotChangeTrackIdentity() throws {
    let first = try MediaRemoteClientBridge.decode(
        neteaseJSONData(contentItemIdentifier: "first-uuid"),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_000)
    )
    let second = try MediaRemoteClientBridge.decode(
        neteaseJSONData(contentItemIdentifier: "second-uuid"),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_001)
    )

    #expect(first.contentItemIdentifier != second.contentItemIdentifier)
    #expect(first.stableTrackSignature == second.stableTrackSignature)
}

@Test("网易云切歌指纹识别旧元数据与新时长混合快照")
func neteaseTransitionFingerprintRejectsMixedMetadata() throws {
    let oldArtwork = Data([0x01, 0x02])
    let newArtwork = Data([0x03, 0x04])
    let old = try MediaRemoteClientBridge.decode(
        neteaseJSONData(
            title: "Sweet Boy",
            artist: "Malcolm Todd",
            album: "Sweet Boy",
            duration: 180.072,
            artworkData: oldArtwork
        ),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_000)
    )
    let mixed = try MediaRemoteClientBridge.decode(
        neteaseJSONData(
            title: "Sweet Boy",
            artist: "Malcolm Todd",
            album: "Sweet Boy",
            duration: 182.059,
            artworkData: oldArtwork
        ),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_001)
    )
    let complete = try MediaRemoteClientBridge.decode(
        neteaseJSONData(
            title: "Баллада",
            artist: "Xcho/МОТ",
            album: "Баллада",
            duration: 182.059,
            artworkData: newArtwork
        ),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_002)
    )

    #expect(mixed.stableTrackSignature != old.stableTrackSignature)
    #expect(mixed.descriptiveTrackSignature == old.descriptiveTrackSignature)
    #expect(mixed.transitionFingerprint != complete.transitionFingerprint)
    #expect(complete.transitionFingerprint == complete.transitionFingerprint)
}

@Test("网易云完整切歌指纹同时约束元数据、时长和封面")
func neteaseCompleteTransitionFingerprintMustRemainStable() throws {
    let first = try MediaRemoteClientBridge.decode(
        neteaseJSONData(
            title: "Баллада",
            artist: "Xcho/МОТ",
            album: "Баллада",
            duration: 182.059,
            artworkData: Data([0x03, 0x04])
        ),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_000)
    )
    let stable = try MediaRemoteClientBridge.decode(
        neteaseJSONData(
            title: "Баллада",
            artist: "Xcho/МОТ",
            album: "Баллада",
            duration: 182.059,
            artworkData: Data([0x03, 0x04])
        ),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_100)
    )
    let artworkStillChanging = try MediaRemoteClientBridge.decode(
        neteaseJSONData(
            title: "Баллада",
            artist: "Xcho/МОТ",
            album: "Баллада",
            duration: 182.059,
            artworkData: Data([0x09])
        ),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_200)
    )

    #expect(first.transitionFingerprint == stable.transitionFingerprint)
    #expect(first.transitionFingerprint != artworkStillChanging.transitionFingerprint)
}

@Test("网易云不同封面可作为完整切歌的强确认")
func neteaseChangedArtworkConfirmsTransition() {
    let oldArtwork = Data([0x01, 0x02])
    let newArtwork = Data([0x03, 0x04])

    #expect(NeteaseMusicAppAdapter.artworkConfirmsTransition(
        candidate: newArtwork,
        baseline: oldArtwork
    ))
    #expect(!NeteaseMusicAppAdapter.artworkConfirmsTransition(
        candidate: oldArtwork,
        baseline: oldArtwork
    ))
    #expect(!NeteaseMusicAppAdapter.artworkConfirmsTransition(
        candidate: nil,
        baseline: oldArtwork
    ))
}

@MainActor
@Test("网易云同曲暂停更新保留封面并冻结时间线")
func neteasePausePreservesArtworkAndFreezesTimeline() throws {
    let instance = MusicAppInstance(
        app: MusicAdapterRegistry.neteaseMusic.descriptor,
        processIdentifier: 62598,
        launchedAt: Date(timeIntervalSince1970: 900)
    )
    let adapter = NeteaseMusicAppAdapter(runningInstancesProvider: { [instance] })
    let playing = try MediaRemoteClientBridge.decode(
        neteaseJSONData(playing: true),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_000)
    )
    let paused = try MediaRemoteClientBridge.decode(
        neteaseJSONData(
            contentItemIdentifier: "changed-uuid",
            artworkData: nil,
            playing: false
        ),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_005)
    )

    let first = adapter.applyPayloadForTesting(playing)
    let second = adapter.applyPayloadForTesting(paused)

    #expect(first.track?.identity == second.track?.identity)
    #expect(second.track?.artworkData == Data([0xFF, 0xD8, 0xFF]))
    #expect(second.playbackState == .paused)
    #expect(second.timeline?.playbackRate == 0)
    #expect(second.instance?.processIdentifier == 62598)
}
