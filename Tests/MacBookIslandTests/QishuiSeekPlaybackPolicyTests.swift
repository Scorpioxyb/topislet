import Testing
@testable import MacBookIsland

@Test("暂停跳转后仅在同曲和操作仍有效且确认正在播放时恢复暂停")
func qishuiSeekPreservesPausedIntentWithoutBlindToggle() {
    #expect(QishuiSeekPlaybackPolicy.shouldRestorePause(wasPlaying: false, observedIsPlaying: true, sameTrack: true, operationIsCurrent: true))
    #expect(!QishuiSeekPlaybackPolicy.shouldRestorePause(wasPlaying: true, observedIsPlaying: true, sameTrack: true, operationIsCurrent: true))
    #expect(!QishuiSeekPlaybackPolicy.shouldRestorePause(wasPlaying: false, observedIsPlaying: false, sameTrack: true, operationIsCurrent: true))
    #expect(!QishuiSeekPlaybackPolicy.shouldRestorePause(wasPlaying: false, observedIsPlaying: nil, sameTrack: true, operationIsCurrent: true))
    #expect(!QishuiSeekPlaybackPolicy.shouldRestorePause(wasPlaying: false, observedIsPlaying: true, sameTrack: false, operationIsCurrent: true))
    #expect(!QishuiSeekPlaybackPolicy.shouldRestorePause(wasPlaying: false, observedIsPlaying: true, sameTrack: true, operationIsCurrent: false))
}
