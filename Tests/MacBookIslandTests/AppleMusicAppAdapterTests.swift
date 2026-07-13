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
