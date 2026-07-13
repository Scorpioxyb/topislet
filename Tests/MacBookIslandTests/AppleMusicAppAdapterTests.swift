import AppleMusicBridge
import ApplicationServices
import Foundation
import Testing
@testable import MacBookIsland

@Test("Apple Music 列表字段解码为原子快照")
func appleMusicObservationDecodesAtomicFields() throws {
    let observation = try #require(AppleMusicObservation.decode(fields: [
        "ABC123",
        "Song",
        "Artist",
        "Album",
        "240.5",
        "42.25",
        "playing"
    ]))

    #expect(observation.persistentIdentifier == "ABC123")
    #expect(observation.title == "Song")
    #expect(observation.duration == 240.5)
    #expect(observation.elapsedTime == 42.25)
    #expect(observation.state == .playing)
    #expect(observation.trackIdentity?.providerIdentifier == "ABC123")
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
    let snapshot = TopIsletAppleMusicCopySnapshot(getpid(), &bridgeError)

    #expect(snapshot == nil)
    #expect(bridgeError?.code == -600)
}
