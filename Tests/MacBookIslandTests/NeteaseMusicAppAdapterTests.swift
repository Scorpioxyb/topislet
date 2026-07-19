import Foundation
import Testing
@testable import MacBookIsland

@MainActor
private final class NeteasePayloadReaderStub {
    private var payloads: [MediaRemoteClientPayload]
    private(set) var artworkRequests: [Bool] = []

    init(payloads: [MediaRemoteClientPayload]) {
        self.payloads = payloads
    }

    func read(includeArtwork: Bool) -> MediaRemoteClientPayload? {
        artworkRequests.append(includeArtwork)
        guard !payloads.isEmpty else { return nil }
        return payloads.removeFirst()
    }
}

@MainActor
private final class NeteaseInvalidationRecorder {
    private(set) var values: [MusicAdapterInvalidation] = []

    func record(_ invalidation: MusicAdapterInvalidation) {
        values.append(invalidation)
    }
}

@Test("网易云运行但尚无曲目时继续发现，避免来源选择死锁")
func neteaseVerificationDiscoversFirstTrackBeforeSelection() {
    #expect(NeteaseMusicVerificationPolicy.shouldVerify(
        isSelected: false,
        isRunning: true,
        hasTrack: false,
        isRebindVerificationActive: false
    ))
    #expect(NeteaseMusicVerificationPolicy.shouldVerify(
        isSelected: true,
        isRunning: true,
        hasTrack: true,
        isRebindVerificationActive: false
    ))
    #expect(NeteaseMusicVerificationPolicy.shouldVerify(
        isSelected: false,
        isRunning: true,
        hasTrack: true,
        isRebindVerificationActive: true
    ))
    #expect(!NeteaseMusicVerificationPolicy.shouldVerify(
        isSelected: false,
        isRunning: true,
        hasTrack: true,
        isRebindVerificationActive: false
    ))
    #expect(!NeteaseMusicVerificationPolicy.shouldVerify(
        isSelected: false,
        isRunning: false,
        hasTrack: false,
        isRebindVerificationActive: true
    ))
}

@Test("网易云启动阶段只对运行中的瞬时不可用状态执行有界重试")
func neteaseStartupRefreshRetryIsBounded() {
    #expect(NeteaseMusicRefreshRetryPolicy.nextDelay(
        afterFailedAttempt: 0,
        appIsRunning: true,
        availability: .notRunning
    ) == 350_000_000)
    #expect(NeteaseMusicRefreshRetryPolicy.nextDelay(
        afterFailedAttempt: 1,
        appIsRunning: true,
        availability: .degraded(reason: "client starting")
    ) == 700_000_000)
    #expect(NeteaseMusicRefreshRetryPolicy.nextDelay(
        afterFailedAttempt: 2,
        appIsRunning: true,
        availability: .notRunning
    ) == 1_200_000_000)
    #expect(NeteaseMusicRefreshRetryPolicy.nextDelay(
        afterFailedAttempt: 3,
        appIsRunning: true,
        availability: .notRunning
    ) == nil)
    #expect(NeteaseMusicRefreshRetryPolicy.nextDelay(
        afterFailedAttempt: 0,
        appIsRunning: false,
        availability: .notRunning
    ) == nil)
    #expect(NeteaseMusicRefreshRetryPolicy.nextDelay(
        afterFailedAttempt: 0,
        appIsRunning: true,
        availability: .ready
    ) == nil)
}

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

private struct NeteasePlaceholderTransitionFixture {
    let old: MediaRemoteClientPayload
    let placeholder: MediaRemoteClientPayload
    let complete: MediaRemoteClientPayload
    let newArtwork: Data
}

private func neteasePlaceholderTransitionFixture() throws
    -> NeteasePlaceholderTransitionFixture {
    let oldArtwork = Data([0x01, 0x02])
    let newArtwork = Data([0x03, 0x04])
    let old = try MediaRemoteClientBridge.decode(
        neteaseJSONData(
            title: "Giftig",
            artist: "Rammstein",
            album: "Zeit",
            duration: 188.309,
            artworkData: oldArtwork
        ),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_000)
    )
    let placeholder = try MediaRemoteClientBridge.decode(
        neteaseJSONData(
            title: "Zeit",
            artist: "Rammstein",
            album: "Zeit",
            duration: 30.041,
            artworkData: newArtwork,
            playing: false
        ),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_001)
    )
    let complete = try MediaRemoteClientBridge.decode(
        neteaseJSONData(
            title: "Zeit",
            artist: "Rammstein",
            album: "Zeit",
            duration: 321.749,
            artworkData: newArtwork,
            playing: true
        ),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_002)
    )
    return NeteasePlaceholderTransitionFixture(
        old: old,
        placeholder: placeholder,
        complete: complete,
        newArtwork: newArtwork
    )
}

private func neteaseSparseTimelineJSONData(playing: Bool?) throws -> Data {
    var payload: [String: Any] = [
        "bundleIdentifier": "com.netease.163music",
        "processIdentifier": 62598,
        "contentItemIdentifier": "focus-change-uuid",
        "title": "Sweet Boy",
        "artist": "Malcolm Todd",
        "album": "Sweet Boy",
        "duration": 180.072
    ]
    if let playing {
        payload["playing"] = playing
        payload["playbackRate"] = playing ? 1 : 0
    }
    return try JSONSerialization.data(withJSONObject: payload)
}

private func neteaseJSONData(
    title: String,
    artist: String,
    album: String,
    duration: TimeInterval,
    artworkData: Data?,
    playing: Bool = true
) throws -> Data {
    var payload: [String: Any] = [
        "bundleIdentifier": "com.netease.163music",
        "processIdentifier": 62598,
        "title": title,
        "artist": artist,
        "album": album,
        "elapsedTime": 0,
        "duration": duration,
        "playbackRate": playing ? 1 : 0,
        "playing": playing
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

@Test("网易云播放中切歌等待短暂 paused 占位状态收敛")
func neteasePlayingTransitionWaitsForPlaybackConfirmation() {
    let issuedAt = Date(timeIntervalSince1970: 1_000)

    #expect(NeteaseMusicAppAdapter.shouldAwaitPlaybackConfirmation(
        expectedState: .playing,
        candidateIsPlaying: false,
        issuedAt: issuedAt,
        now: issuedAt.addingTimeInterval(1.5)
    ))
    #expect(NeteaseMusicAppAdapter.shouldAwaitPlaybackConfirmation(
        expectedState: .playing,
        candidateIsPlaying: nil,
        issuedAt: issuedAt,
        now: issuedAt.addingTimeInterval(1.5)
    ))
    #expect(!NeteaseMusicAppAdapter.shouldAwaitPlaybackConfirmation(
        expectedState: .playing,
        candidateIsPlaying: true,
        issuedAt: issuedAt,
        now: issuedAt.addingTimeInterval(1.5)
    ))
    #expect(!NeteaseMusicAppAdapter.shouldAwaitPlaybackConfirmation(
        expectedState: .playing,
        candidateIsPlaying: false,
        issuedAt: issuedAt,
        now: issuedAt.addingTimeInterval(2.3)
    ))
    #expect(!NeteaseMusicAppAdapter.shouldAwaitPlaybackConfirmation(
        expectedState: .paused,
        candidateIsPlaying: false,
        issuedAt: issuedAt,
        now: issuedAt.addingTimeInterval(1.5)
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

@MainActor
@Test("网易云同曲稀疏媒体焦点事件不能清空可信播放态和时间线")
func neteaseSparseFocusEventPreservesAuthoritativeTimeline() throws {
    let instance = MusicAppInstance(
        app: MusicAdapterRegistry.neteaseMusic.descriptor,
        processIdentifier: 62598,
        launchedAt: Date(timeIntervalSince1970: 900)
    )
    let adapter = NeteaseMusicAppAdapter(runningInstancesProvider: { [instance] })
    let complete = try MediaRemoteClientBridge.decode(
        neteaseJSONData(playing: true),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_000)
    )
    let focusEvent = try MediaRemoteClientBridge.decode(
        neteaseSparseTimelineJSONData(playing: false),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_005)
    )

    _ = adapter.applyPayloadForTesting(complete)
    let preserved = adapter.applyPayloadForTesting(focusEvent)

    #expect(preserved.playbackState == .playing)
    #expect(preserved.timeline?.elapsedTime == 11.125)
    #expect(preserved.timeline?.duration == 180.072)
    #expect(preserved.timeline?.playbackRate == 1)
    #expect(preserved.track?.artworkData == Data([0xFF, 0xD8, 0xFF]))
}

@MainActor
@Test("网易云自然切歌不发布 paused 临时时长占位快照")
func neteaseNaturalTransitionWaitsForCompletePlayingSnapshot() async throws {
    let instance = MusicAppInstance(
        app: MusicAdapterRegistry.neteaseMusic.descriptor,
        processIdentifier: 62598,
        launchedAt: Date(timeIntervalSince1970: 900)
    )
    let transition = try neteasePlaceholderTransitionFixture()
    let reader = NeteasePayloadReaderStub(payloads: [
        transition.placeholder,
        transition.complete
    ])
    let recorder = NeteaseInvalidationRecorder()
    let adapter = NeteaseMusicAppAdapter(
        runningInstancesProvider: { [instance] },
        payloadReaderForTesting: { includeArtwork in
            reader.read(includeArtwork: includeArtwork)
        }
    )
    _ = adapter.applyPayloadForTesting(transition.old)
    adapter.start { invalidation in
        recorder.record(invalidation)
    }

    adapter.receiveStreamPayloadForTesting(transition.placeholder)
    let immediate = await adapter.snapshot(refresh: .cached)
    #expect(immediate.track?.title == "Giftig")
    #expect(immediate.playbackState == .playing)

    try await Task.sleep(nanoseconds: 250_000_000)
    let committed = await adapter.snapshot(refresh: .cached)

    #expect(committed.track?.title == "Zeit")
    #expect(committed.track?.artworkData == transition.newArtwork)
    #expect(committed.timeline?.duration == 321.749)
    #expect(committed.playbackState == .playing)
    #expect(committed.timeline?.playbackRate == 1)
    #expect(reader.artworkRequests == [true, true])
    #expect(recorder.values == [.sourceChanged])
    adapter.stop()
}

@MainActor
@Test("网易云前台元数据刷新也拒绝 paused 临时时长占位快照")
func neteaseForegroundMetadataRefreshUsesTransitionGate() async throws {
    let instance = MusicAppInstance(
        app: MusicAdapterRegistry.neteaseMusic.descriptor,
        processIdentifier: 62598,
        launchedAt: Date(timeIntervalSince1970: 900)
    )
    let transition = try neteasePlaceholderTransitionFixture()
    let reader = NeteasePayloadReaderStub(payloads: [
        transition.placeholder,
        transition.complete
    ])
    let recorder = NeteaseInvalidationRecorder()
    let adapter = NeteaseMusicAppAdapter(
        runningInstancesProvider: { [instance] },
        payloadReaderForTesting: { includeArtwork in
            reader.read(includeArtwork: includeArtwork)
        }
    )
    _ = adapter.applyPayloadForTesting(transition.old)
    adapter.start { invalidation in
        recorder.record(invalidation)
    }

    let immediate = await adapter.snapshot(refresh: .metadata)
    #expect(immediate.track?.title == "Giftig")
    #expect(immediate.playbackState == .playing)

    try await Task.sleep(nanoseconds: 250_000_000)
    let committed = await adapter.snapshot(refresh: .cached)

    #expect(committed.track?.title == "Zeit")
    #expect(committed.track?.artworkData == transition.newArtwork)
    #expect(committed.timeline?.duration == 321.749)
    #expect(committed.playbackState == .playing)
    #expect(committed.timeline?.playbackRate == 1)
    #expect(reader.artworkRequests == [true, true])
    #expect(recorder.values == [.sourceChanged])
    adapter.stop()
}

@MainActor
@Test("网易云状态流漏报后校验会原子恢复同封面后台切歌")
func neteaseVerificationRecoversMissedSameArtworkTransition() async throws {
    let instance = MusicAppInstance(
        app: MusicAdapterRegistry.neteaseMusic.descriptor,
        processIdentifier: 62598,
        launchedAt: Date(timeIntervalSince1970: 900)
    )
    let artwork = Data([0x01, 0x02, 0x03])
    let oldPayload = try MediaRemoteClientBridge.decode(
        neteaseJSONData(
            title: "Engel",
            artist: "Rammstein",
            album: "Sehnsucht",
            duration: 264.6,
            artworkData: artwork
        ),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_000)
    )
    let timelineCandidate = try MediaRemoteClientBridge.decode(
        neteaseJSONData(
            title: "Du hast",
            artist: "Rammstein",
            album: "Sehnsucht",
            duration: 235.6,
            artworkData: nil
        ),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_001)
    )
    let confirmedPayload = try MediaRemoteClientBridge.decode(
        neteaseJSONData(
            title: "Du hast",
            artist: "Rammstein",
            album: "Sehnsucht",
            duration: 235.6,
            artworkData: artwork
        ),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_002)
    )
    let reader = NeteasePayloadReaderStub(payloads: [
        timelineCandidate,
        confirmedPayload,
        confirmedPayload
    ])
    let recorder = NeteaseInvalidationRecorder()
    let adapter = NeteaseMusicAppAdapter(
        runningInstancesProvider: { [instance] },
        payloadReaderForTesting: { includeArtwork in
            reader.read(includeArtwork: includeArtwork)
        }
    )
    _ = adapter.applyPayloadForTesting(oldPayload)
    adapter.start { invalidation in
        recorder.record(invalidation)
    }

    let immediate = await adapter.snapshot(refresh: .timeline)
    #expect(immediate.track?.title == "Engel")
    #expect(immediate.track?.artworkData == artwork)

    try await Task.sleep(nanoseconds: 250_000_000)
    let recovered = await adapter.snapshot(refresh: .cached)

    #expect(recovered.track?.title == "Du hast")
    #expect(recovered.track?.artist == "Rammstein")
    #expect(recovered.track?.album == "Sehnsucht")
    #expect(recovered.track?.artworkData == artwork)
    #expect(recovered.timeline?.duration == 235.6)
    #expect(reader.artworkRequests == [false, true, true])
    #expect(recorder.values == [.sourceChanged])
    adapter.stop()
}

@MainActor
@Test("网易云新 PID 重绑后会确认首次播放竞态")
func neteaseRebindConfirmsPlaybackStartedDuringFirstRead() async throws {
    let instance = MusicAppInstance(
        app: MusicAdapterRegistry.neteaseMusic.descriptor,
        processIdentifier: 62598,
        launchedAt: Date(timeIntervalSince1970: 900)
    )
    let paused = try MediaRemoteClientBridge.decode(
        neteaseJSONData(playing: false),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_000)
    )
    let playing = try MediaRemoteClientBridge.decode(
        neteaseJSONData(playing: true),
        expectedBundleIdentifier: "com.netease.163music",
        runningProcessIdentifiers: [62598],
        observedAt: Date(timeIntervalSince1970: 1_001)
    )
    let reader = NeteasePayloadReaderStub(payloads: [paused, playing])
    let recorder = NeteaseInvalidationRecorder()
    let adapter = NeteaseMusicAppAdapter(
        runningInstancesProvider: { [instance] },
        payloadReaderForTesting: { includeArtwork in
            reader.read(includeArtwork: includeArtwork)
        }
    )
    adapter.start { invalidation in
        recorder.record(invalidation)
    }
    adapter.rebindObservationToRunningInstance()

    let initial = await adapter.snapshot(refresh: .metadata)
    #expect(initial.playbackState == .paused)

    try await Task.sleep(nanoseconds: 350_000_000)
    let confirmed = await adapter.snapshot(refresh: .cached)

    #expect(confirmed.track?.title == "Sweet Boy")
    #expect(confirmed.playbackState == .playing)
    #expect(confirmed.timeline?.playbackRate == 1)
    #expect(reader.artworkRequests == [true, true])
    #expect(recorder.values == [.sourceChanged])
    adapter.stop()
}
