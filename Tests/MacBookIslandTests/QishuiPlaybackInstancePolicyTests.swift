import Foundation
import Testing
@testable import MacBookIsland

@Test("完整流与新鲜 AX 身份冲突时只触发一次立即核验，保留 PID 与同曲门禁")
func qishuiTransitionReconciliationIsBoundedAndSourceSpecific() {
    let now = Date(timeIntervalSince1970: 100)
    let media = QishuiLyricIdentity(processIdentifier: 42, title: "New", artist: "A, B")
    let old = QishuiLyricIdentity(processIdentifier: 42, title: "Old", artist: "A")
    let formatted = QishuiLyricIdentity(processIdentifier: 42, title: " New ", artist: "B / A")
    let otherProcess = QishuiLyricIdentity(processIdentifier: 43, title: "Old", artist: "A")
    func needs(_ direct: QishuiLyricIdentity, age: TimeInterval = 0.3,
               last: QishuiLyricIdentity? = nil, inFlight: Bool = false) -> Bool {
        QishuiIdentityRefreshPolicy.needsTransitionReconciliation(
            media: media, direct: direct, directCheckedAt: now.addingTimeInterval(-age),
            lastRequested: last, isReadInFlight: inFlight, now: now
        )
    }
    #expect(needs(old))
    #expect(!needs(old, last: media))
    #expect(!needs(old, inFlight: true))
    #expect(!needs(old, age: 2.1))
    #expect(!needs(otherProcess))
    #expect(!needs(formatted))
    #expect(!needs(old, age: -0.1))
}

@Test("后台读取期间切歌时拒绝旧曲回写，但允许已经跟上新曲的 AX 结果")
func qishuiIdentityReadCannotRestorePreviousTrack() {
    let old = QishuiLyricIdentity(processIdentifier: 42, title: "Old", artist: "A")
    let new = QishuiLyricIdentity(processIdentifier: 42, title: "New", artist: "A, B")
    let formatted = QishuiLyricIdentity(processIdentifier: 42, title: " New ", artist: "B / A")
    #expect(!QishuiIdentityRefreshPolicy.accepts(requested: old, current: new, result: old))
    #expect(!QishuiIdentityRefreshPolicy.accepts(requested: old, current: new, result: nil))
    #expect(QishuiIdentityRefreshPolicy.accepts(requested: old, current: new, result: formatted))
    #expect(QishuiIdentityRefreshPolicy.accepts(requested: old, current: old, result: new))
}

@Test("首次媒体身份到达或离开时，不接纳无归属的旧 AX 读取")
func qishuiIdentityReadRequiresCurrentPlaybackAfterTransition() {
    let track = QishuiLyricIdentity(processIdentifier: 42, title: "Song", artist: "A")
    let otherProcess = QishuiLyricIdentity(processIdentifier: 43, title: "Song", artist: "A")
    #expect(!QishuiIdentityRefreshPolicy.accepts(requested: nil, current: track, result: otherProcess))
    #expect(!QishuiIdentityRefreshPolicy.accepts(requested: track, current: nil, result: track))
    #expect(QishuiIdentityRefreshPolicy.accepts(requested: nil, current: track, result: track))
    #expect(QishuiIdentityRefreshPolicy.accepts(requested: nil, current: nil, result: track))
}

@Test("重启后旧汽水快照不能显示为新进程的歌曲和播放进度")
func oldQishuiPlaybackCannotSurviveProcessReplacement() {
    #expect(QishuiPlaybackInstancePolicy.acceptsSnapshot(
        snapshotProcessIdentifier: 100, runningProcessIdentifiers: [100]
    ))
    #expect(!QishuiPlaybackInstancePolicy.acceptsSnapshot(
        snapshotProcessIdentifier: 100, runningProcessIdentifiers: [101]
    ))
    #expect(QishuiPlaybackInstancePolicy.acceptsSnapshot(
        snapshotProcessIdentifier: 101, runningProcessIdentifiers: [101]
    ))
}

@Test("汽水已退出或快照没有进程身份时不继承播放状态")
func unboundQishuiPlaybackIsRejected() {
    #expect(!QishuiPlaybackInstancePolicy.acceptsSnapshot(
        snapshotProcessIdentifier: 100, runningProcessIdentifiers: []
    ))
    #expect(!QishuiPlaybackInstancePolicy.acceptsSnapshot(
        snapshotProcessIdentifier: nil, runningProcessIdentifiers: [101]
    ))
}

@Test("旧控件预检不能清空新汽水实例的媒体会话")
func retiredControlProbeCannotInvalidateReplacementSession() {
    #expect(QishuiControlProbeCompletionPolicy.resolution(
        requestedProcessIdentifier: 100, runningProcessIdentifiers: [101]) == .discardAndRefresh)
    #expect(QishuiControlProbeCompletionPolicy.resolution(
        requestedProcessIdentifier: 100, runningProcessIdentifiers: [101, 102]) == .discardAndRefresh)
    #expect(!QishuiPlaybackInstancePolicy.acceptsSnapshot(
        snapshotProcessIdentifier: 100, runningProcessIdentifiers: [101]))
    #expect(QishuiPlaybackInstancePolicy.acceptsSnapshot(
        snapshotProcessIdentifier: 101, runningProcessIdentifiers: [101]))
}

@Test("控件预检按精确 PID 的新鲜应用清单完成，只有清单为空才能清会话")
func controlProbeExitRequiresEmptyApplicationInventory() {
    #expect(QishuiControlProbeCompletionPolicy.resolution(
        requestedProcessIdentifier: 100, runningProcessIdentifiers: [100]) == .accept)
    #expect(QishuiControlProbeCompletionPolicy.resolution(
        requestedProcessIdentifier: 100, runningProcessIdentifiers: [100, 101]) == .accept)
    #expect(QishuiControlProbeCompletionPolicy.resolution(
        requestedProcessIdentifier: 100, runningProcessIdentifiers: []) == .sourceExited)
}
