import Testing
import Foundation
@testable import MacBookIsland

private let pid: pid_t = 4242
private let songA = QishuiLyricIdentity(processIdentifier: pid, title: "歌 A", artist: "歌手")
private let songB = QishuiLyricIdentity(processIdentifier: pid, title: "歌 B", artist: "歌手")

private func token(identity: QishuiLyricIdentity? = songA) -> PublishedTrackToken {
    PublishedTrackToken(source: .qishui, processIdentifier: pid, identity: identity,
                        controlGeneration: 3, seekGeneration: 7)
}

private func admits(
    _ token: PublishedTrackToken,
    resultPID: pid_t? = pid,
    result: QishuiLyricIdentity? = songA,
    control: Int = 3,
    seek: UInt64 = 7,
    current: QishuiLyricIdentity? = songA,
    running: Bool = true
) -> Bool {
    token.admits(
        resultProcessIdentifier: resultPID,
        resultTitle: result?.title,
        resultArtist: result?.artist,
        currentControlGeneration: control,
        currentSeekGeneration: seek,
        currentIdentity: current,
        isProcessRunning: { _ in running }
    )
}

@Test("曲目令牌：同一进程、代次未变、身份未变的读取可以写入")
func publishedTrackTokenAdmitsUnchangedRead() {
    #expect(admits(token()))
    #expect(admits(token(identity: nil), result: nil, current: nil))
}

@Test("曲目令牌：读取期间发生控制或跳转，结果作废")
func publishedTrackTokenRejectsAfterControlOrSeek() {
    #expect(!admits(token(), control: 4))
    #expect(!admits(token(), seek: 8))
}

@Test("曲目令牌：结果不属于请求的进程，或该进程已退出，结果作废")
func publishedTrackTokenRejectsOtherOrExitedProcess() {
    #expect(!admits(token(), resultPID: 5151))
    #expect(!admits(token(), resultPID: nil))
    #expect(!admits(token(), running: false))
}

@Test("曲目令牌：读取期间切歌，只接受已经描述新歌的结果")
func publishedTrackTokenFollowsIdentityChange() {
    #expect(admits(token(), result: songB, current: songB))
    #expect(!admits(token(), result: songA, current: songB))
    #expect(!admits(token(), result: nil, current: songB))
}
