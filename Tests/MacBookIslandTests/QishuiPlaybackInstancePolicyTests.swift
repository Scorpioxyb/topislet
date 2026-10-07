import Testing
@testable import MacBookIsland

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
