import AppleMusicBridge
import ApplicationServices
import Foundation
import Testing
@testable import MacBookIsland

@Test("Apple Music 列表字段解码为原子快照")
func appleMusicObservationDecodesAtomicFields() throws {
    let artworkData = Data([0xFF, 0xD8, 0xFF, 0xE0])
    let observation = try #require(AppleMusicObservation.decode(fields: [
        "ABC123",
        "Song",
        "Artist",
        "Album",
        "240.5",
        "42.25",
        "playing"
    ], artworkData: artworkData))

    #expect(observation.persistentIdentifier == "ABC123")
    #expect(observation.title == "Song")
    #expect(observation.duration == 240.5)
    #expect(observation.elapsedTime == 42.25)
    #expect(observation.artworkData == artworkData)
    #expect(observation.state == .playing)
    #expect(observation.trackIdentity?.providerIdentifier == "ABC123")
}

@Test("Apple Music playerInfo 可提前形成电台封面候选")
func appleMusicPlayerInfoCreatesArtworkCandidate() throws {
    let candidate = try #require(AppleMusicPlayerInfoCandidate(userInfo: [
        "Name": "Strippers Lives Matter",
        "Artist": "Rob49",
        "Album": "Let Me Fly (Deluxe)",
        "Player State": "Playing"
    ]))

    #expect(candidate.title == "Strippers Lives Matter")
    #expect(candidate.artist == "Rob49")
    #expect(candidate.album == "Let Me Fly (Deluxe)")
    #expect(candidate.observation.trackIdentity?.fallbackSignature
        == candidate.fallbackSignature)
}

@Test("Apple Music 封面合并不改变权威播放字段")
func appleMusicArtworkMergePreservesObservation() throws {
    let observation = try #require(AppleMusicObservation.decode(fields: [
        "ABC123", "Song", "Artist", "Album", "240", "42", "paused"
    ]))
    let artworkData = Data([0x01, 0x02, 0x03])
    let merged = observation.withArtworkData(artworkData)

    #expect(merged.artworkData == artworkData)
    #expect(merged.persistentIdentifier == observation.persistentIdentifier)
    #expect(merged.elapsedTime == observation.elapsedTime)
    #expect(merged.duration == observation.duration)
    #expect(merged.state == observation.state)
}

@Test("Apple Music 封面正负缓存遵守 TTL")
func appleMusicArtworkCacheRespectsRetryTTL() {
    let identity = MusicTrackIdentity(
        providerIdentifier: "ABC123",
        fallbackSignature: "Song"
    )
    let startedAt = Date(timeIntervalSince1970: 1_000)
    var cache = AppleMusicArtworkCache(retryInterval: 30)

    #expect(cache.shouldFetch(for: identity, at: startedAt))
    cache.recordAttempt(for: identity, at: startedAt)
    #expect(!cache.shouldFetch(
        for: identity,
        at: startedAt.addingTimeInterval(29)
    ))
    #expect(cache.shouldFetch(
        for: identity,
        at: startedAt.addingTimeInterval(30)
    ))

    let artworkData = Data([0x01, 0x02, 0x03])
    let didStoreArtwork = cache.store(
        artworkData,
        for: identity,
        at: startedAt
    )
    #expect(didStoreArtwork)
    #expect(cache.data(for: identity) == artworkData)
    #expect(!cache.shouldFetch(
        for: identity,
        at: startedAt.addingTimeInterval(300)
    ))
}

@Test("Apple Music 封面缓存限制条目和总字节")
func appleMusicArtworkCacheEvictsOldEntries() {
    let first = MusicTrackIdentity(
        providerIdentifier: "A",
        fallbackSignature: "A"
    )
    let second = MusicTrackIdentity(
        providerIdentifier: "B",
        fallbackSignature: "B"
    )
    var cache = AppleMusicArtworkCache(
        maximumEntryCount: 2,
        maximumArtworkBytes: 4,
        maximumTotalBytes: 4
    )
    let now = Date(timeIntervalSince1970: 1_000)

    let didStoreFirst = cache.store(
        Data([0x01, 0x02, 0x03]),
        for: first,
        at: now
    )
    let didStoreSecond = cache.store(
        Data([0x04, 0x05, 0x06]),
        for: second,
        at: now
    )
    #expect(didStoreFirst)
    #expect(didStoreSecond)
    #expect(cache.data(for: first) == nil)
    #expect(cache.data(for: second) == Data([0x04, 0x05, 0x06]))
    #expect(cache.totalBytes == 3)
    let didStoreOversized = cache.store(
        Data(repeating: 0xFF, count: 5),
        for: first,
        at: now
    )
    #expect(!didStoreOversized)
}

@Test("Apple Music 封面失败缓存区分无匹配与临时失败")
func appleMusicArtworkCacheBacksOffFailures() {
    let identity = MusicTrackIdentity(
        providerIdentifier: "ABC123",
        fallbackSignature: "Song"
    )
    let startedAt = Date(timeIntervalSince1970: 1_000)
    var cache = AppleMusicArtworkCache(retryInterval: 10)

    cache.recordFailure(.transient, for: identity, at: startedAt)
    #expect(!cache.shouldFetch(
        for: identity,
        at: startedAt.addingTimeInterval(9)
    ))
    #expect(cache.shouldFetch(
        for: identity,
        at: startedAt.addingTimeInterval(10)
    ))

    cache.recordFailure(
        .notFound,
        for: identity,
        at: startedAt.addingTimeInterval(10)
    )
    #expect(!cache.shouldFetch(
        for: identity,
        at: startedAt.addingTimeInterval(309)
    ))
    #expect(cache.shouldFetch(
        for: identity,
        at: startedAt.addingTimeInterval(310)
    ))
}

@Test("Apple Music 异步封面不重锚时间轴或控制验证时间")
func appleMusicArtworkOnlyUpdatePreservesAuthoritativeSnapshot() throws {
    let descriptor = MusicAdapterRegistry.appleMusic.descriptor
    let instance = MusicAppInstance(
        app: descriptor,
        processIdentifier: 42,
        launchedAt: Date(timeIntervalSince1970: 900)
    )
    let identity = MusicTrackIdentity(
        providerIdentifier: "ABC123",
        fallbackSignature: "Song"
    )
    let checkedAt = Date(timeIntervalSince1970: 1_000)
    let observedAt = Date(timeIntervalSince1970: 999)
    let controls = MusicControlCapabilities(values: [
        .playPause: .ready(
            target: instance,
            mechanism: .appleEvent,
            verifiedAt: checkedAt
        )
    ])
    let snapshot = MusicAppSnapshot(
        descriptor: descriptor,
        instance: instance,
        availability: .ready,
        track: MusicTrackSnapshot(
            identity: identity,
            title: "Song",
            artist: "Artist",
            album: "Album",
            artworkData: nil,
            lyrics: []
        ),
        playbackState: .playing,
        timeline: MusicTimelineSnapshot(
            elapsedTime: 42,
            duration: 240,
            playbackRate: 1,
            observedAt: observedAt
        ),
        controls: controls,
        revision: 7,
        provenance: MusicSnapshotProvenance(
            bundleIdentifier: descriptor.bundleIdentifier,
            mechanisms: [.appleEvent]
        ),
        checkedAt: checkedAt,
        diagnostic: "authoritative"
    )
    let artworkData = Data([0x01, 0x02, 0x03])
    let updated = try #require(appleMusicSnapshotByReplacingArtworkData(
        snapshot,
        artworkData: artworkData,
        identity: identity,
        revision: 8
    ))

    #expect(updated.track?.artworkData == artworkData)
    #expect(updated.timeline == snapshot.timeline)
    #expect(updated.controls == snapshot.controls)
    #expect(updated.checkedAt == snapshot.checkedAt)
    #expect(updated.revision == 8)

    let differentProviderIdentity = MusicTrackIdentity(
        providerIdentifier: "DIFFERENT-ID",
        fallbackSignature: identity.fallbackSignature
    )
    #expect(appleMusicSnapshotByReplacingArtworkData(
        snapshot,
        artworkData: artworkData,
        identity: differentProviderIdentity,
        revision: 8
    ) == nil)
}

@Test("Apple Music 稳态轮询以通知为主并降低频率")
func appleMusicRefreshPolicyUsesLowFrequencyFallback() {
    #expect(AppleMusicRefreshPolicy.interval(
        isSelected: true,
        isPlaying: true,
        recentlyControlled: false,
        consecutiveFailures: 0
    ) == 5)
    #expect(AppleMusicRefreshPolicy.interval(
        isSelected: true,
        isPlaying: false,
        recentlyControlled: false,
        consecutiveFailures: 0
    ) == 10)
    #expect(AppleMusicRefreshPolicy.interval(
        isSelected: false,
        isPlaying: true,
        recentlyControlled: false,
        consecutiveFailures: 0
    ) == 15)
}

@Test("Apple Music 轮询失败会指数退避")
func appleMusicRefreshPolicyBacksOffFailures() {
    #expect(AppleMusicRefreshPolicy.interval(
        isSelected: true,
        isPlaying: true,
        recentlyControlled: false,
        consecutiveFailures: 1
    ) == 10)
    #expect(AppleMusicRefreshPolicy.interval(
        isSelected: true,
        isPlaying: true,
        recentlyControlled: false,
        consecutiveFailures: 4
    ) == 20)
}

@Test("Apple Music 停止状态不伪造歌曲和进度")
func stoppedAppleMusicDoesNotCreateFakeTrack() throws {
    let observation = try #require(AppleMusicObservation.decode(fields: [
        "", "", "", "", "", "", "stopped"
    ]))

    #expect(observation.trackIdentity == nil)
    #expect(observation.duration == nil)
    #expect(observation.elapsedTime == nil)
    #expect(observation.state == .stopped)
}

@Test("Apple Music 自动化权限状态映射稳定")
func appleMusicAutomationStatusMapping() {
    #expect(AppleMusicAppAdapter.automationAccess(for: noErr) == .allowed)
    #expect(AppleMusicAppAdapter.automationAccess(for: -600) == .targetNotRunning)
    #expect(AppleMusicAppAdapter.automationAccess(
        for: OSStatus(errAEEventWouldRequireUserConsent)
    ) == .consentRequired)
    #expect(AppleMusicAppAdapter.automationAccess(
        for: OSStatus(errAEEventNotPermitted)
    ) == .denied)
}

@Test("Apple Music 桥拒绝非 Music 进程 PID")
func appleMusicBridgeRejectsNonMusicProcess() {
    var bridgeError: NSError?
    let snapshot = TopIsletAppleMusicCopySnapshot(getpid(), false, &bridgeError)

    #expect(snapshot == nil)
    #expect(bridgeError?.code == -600)
}
