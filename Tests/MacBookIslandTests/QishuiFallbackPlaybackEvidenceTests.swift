import Foundation
import Testing
@testable import MacBookIsland

@Test("无播放证据的 AX 身份不能挤掉新鲜 PID 专属播放状态")
func unknownAXPlaybackCannotDisplaceFreshSourceState() {
    let now = Date(timeIntervalSince1970: 100)
    func admits(directEvidence: Bool, sourceEvidence: Bool) -> Bool {
        QishuiMediaRemoteAdmissionPolicy.accepts(mediaTitle: "Current", mediaArtist: "汽水音乐",
            directTitle: "AX Label", directArtist: "Artist", directCheckedAt: now,
            mediaHasCompleteMetadata: false, directHasPlaybackEvidence: directEvidence,
            mediaHasFreshProcessPlaybackEvidence: sourceEvidence, now: now)
    }
    #expect(admits(directEvidence: false, sourceEvidence: true))
    #expect(!admits(directEvidence: true, sourceEvidence: true))
    #expect(!admits(directEvidence: false, sourceEvidence: false))
}

private func evidenceEnvelope(_ payload: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["type":"data", "diff":false, "payload":payload])
}

@Test("超时清理元数据不丢掉同进程播放证据，但不能授权跨曲时间轴")
@MainActor
func sanitationRetainsProcessEvidenceWithoutTrackAuthorization() throws {
    let source = MediaRemoteAdapterStreamSource(runningQishuiProcessIdentifiersProvider: { [123] })
    let now = Date(timeIntervalSince1970: 100)
    let initial: [String: Any] = ["bundleIdentifier":"com.soda.music", "processIdentifier":123,
        "title":"Previous", "artist":"Artist", "album":"Album", "duration":180,
        "contentItemIdentifier":"old", "playing":1, "elapsedTimeNow":20.0,
        "artworkData":Data([1]).base64EncodedString()]
    var next = initial
    next["title"] = "Current"; next["contentItemIdentifier"] = "new"; next["elapsedTimeNow"] = 0.0
    _ = source.ingestStreamEnvelopeForTesting(try evidenceEnvelope(initial), receivedAt: now,
        receivedUptime: 100)
    _ = source.ingestStreamEnvelopeForTesting(try evidenceEnvelope(next), receivedAt: now.addingTimeInterval(0.1),
        receivedUptime: 100.1)
    #expect(source.hasFreshProcessPlaybackEvidence(at: now.addingTimeInterval(0.2), maxAge: 0.8))
    #expect(!source.hasFreshVerifiedPlaybackEvidence(at: now.addingTimeInterval(0.2), maxAge: 0.8))
    _ = source.forceDeferredTrackPublicationForTesting(receivedAt: now.addingTimeInterval(0.3), receivedUptime: 100.3)
    #expect(source.snapshot()?.currentTrack?.artist == "汽水音乐")
    #expect(source.hasFreshProcessPlaybackEvidence(at: now.addingTimeInterval(0.4), maxAge: 0.8))
    #expect(!source.hasFreshVerifiedPlaybackEvidence(at: now.addingTimeInterval(0.4), maxAge: 0.8))
    #expect(!source.hasFreshProcessPlaybackEvidence(at: now.addingTimeInterval(0.4), maxAge: 0.8,
        expectedProcessIdentifier: 999))
    #expect(!source.hasFreshProcessPlaybackEvidence(at: now.addingTimeInterval(0.4), maxAge: 0.8,
        expectedSampleID: 999))
    let currentSampleID = try #require(source.snapshot()?.sampleID)
    #expect(source.hasFreshProcessPlaybackEvidence(at: now.addingTimeInterval(0.4), maxAge: 0.8,
        expectedSampleID: currentSampleID, expectedProcessIdentifier: 123))
    #expect(!source.hasFreshProcessPlaybackEvidence(at: now.addingTimeInterval(1), maxAge: 0.8))
    #expect(!source.hasFreshProcessPlaybackEvidence(at: now, maxAge: 0.8))
    source.invalidateQishuiSession()
    #expect(!source.hasFreshProcessPlaybackEvidence(at: now.addingTimeInterval(0.4), maxAge: 0.8))
}

@Test("切歌等待保留同进程已发布播放基准，未知AX不得提前取代；明确暂停不能沿用旧playing")
@MainActor
func pendingPublicationKeepsMatchingProcessPlaybackBaseline() throws {
    let now = Date(timeIntervalSince1970: 100)
    for playing in [1, 0, -1] {
        let source = MediaRemoteAdapterStreamSource(runningQishuiProcessIdentifiersProvider: { [123] })
        let old: [String: Any] = ["bundleIdentifier":"com.soda.music", "processIdentifier":123,
            "title":"Previous", "artist":"Artist", "album":"Album", "duration":180,
            "contentItemIdentifier":"old", "playing":1, "elapsedTimeNow":20.0,
            "artworkData":Data([1]).base64EncodedString()]
        let baseline = try #require(source.ingestStreamEnvelopeForTesting(try evidenceEnvelope(old),
            receivedAt:now, receivedUptime:100))
        var next = old
        next["title"]="Current"; next["contentItemIdentifier"]="new"
        next["playing"] = playing < 0 ? nil : playing
        next["elapsedTimeNow"]=0.0
        _ = source.ingestStreamEnvelopeForTesting(try evidenceEnvelope(next),
            receivedAt:now.addingTimeInterval(0.1), receivedUptime:100.1)
        let evidence = source.hasFreshProcessPlaybackEvidence(at:now.addingTimeInterval(0.2), maxAge:0.8,
            expectedSampleID:baseline.sampleID, expectedProcessIdentifier:123)
        #expect(evidence == (playing == 1))
        #expect(!source.hasFreshVerifiedPlaybackEvidence(at:now.addingTimeInterval(0.2), maxAge:0.8))
        #expect(source.snapshot()?.currentTrack?.title == "Previous")
        #expect(QishuiMediaRemoteAdmissionPolicy.accepts(mediaTitle:"Previous", mediaArtist:"Artist",
            directTitle:"AX Label", directArtist:"Artist", directCheckedAt:now.addingTimeInterval(0.15),
            directHasPlaybackEvidence:false, mediaHasFreshProcessPlaybackEvidence:evidence,
            now:now.addingTimeInterval(0.2)) == (playing == 1))
        #expect(!source.hasFreshProcessPlaybackEvidence(at:now.addingTimeInterval(0.2), maxAge:0.8,
            expectedSampleID:baseline.sampleID + 1, expectedProcessIdentifier:123))
        #expect(!source.hasFreshProcessPlaybackEvidence(at:now.addingTimeInterval(0.2), maxAge:0.8,
            expectedSampleID:baseline.sampleID, expectedProcessIdentifier:999))
        #expect(!source.hasFreshProcessPlaybackEvidence(at:now.addingTimeInterval(1), maxAge:0.8))
        source.invalidateQishuiSession()
        #expect(!source.hasFreshProcessPlaybackEvidence(at:now.addingTimeInterval(0.2), maxAge:0.8))
    }
}

@Test("AX未知不能在切歌2.4秒等待结束时绕过播放证据保护")
@MainActor
func deferredDeadlineStillProtectsUnknownAXFallback() throws {
    let source = MediaRemoteAdapterStreamSource(runningQishuiProcessIdentifiersProvider: { [123] })
    let now = Date(timeIntervalSince1970: 100)
    let old: [String: Any] = ["bundleIdentifier":"com.soda.music", "processIdentifier":123,
        "title":"Previous", "artist":"Artist", "album":"Album", "duration":180,
        "contentItemIdentifier":"old", "playing":1, "elapsedTimeNow":20.0,
        "artworkData":Data([1]).base64EncodedString()]
    var next = old
    next["title"]="Current"; next["contentItemIdentifier"]="new"; next["elapsedTimeNow"]=0.0
    _ = source.ingestStreamEnvelopeForTesting(try evidenceEnvelope(old), receivedAt: now, receivedUptime: 100)
    _ = source.ingestStreamEnvelopeForTesting(try evidenceEnvelope(next), receivedAt: now.addingTimeInterval(0.1), receivedUptime: 100.1)
    _ = source.forceDeferredTrackPublicationForTesting(receivedAt: now.addingTimeInterval(2.5), receivedUptime: 102.5)
    let evidence = source.hasFreshProcessPlaybackEvidence(at: now.addingTimeInterval(2.6),
        maxAge: QishuiMediaRemoteAdmissionPolicy.maximumPlaybackEvidenceAge)
    #expect(evidence)
    #expect(QishuiMediaRemoteAdmissionPolicy.accepts(mediaTitle: "Current", mediaArtist: "汽水音乐",
        directTitle:"AX Label", directArtist:"Artist", directCheckedAt:now.addingTimeInterval(2.5),
        directHasPlaybackEvidence:false, mediaHasFreshProcessPlaybackEvidence:evidence,
        now:now.addingTimeInterval(2.6)))
    #expect(!source.hasFreshProcessPlaybackEvidence(at: now.addingTimeInterval(3.5),
        maxAge: QishuiMediaRemoteAdmissionPolicy.maximumPlaybackEvidenceAge))
}
