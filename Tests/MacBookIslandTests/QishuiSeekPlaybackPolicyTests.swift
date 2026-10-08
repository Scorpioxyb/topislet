import Testing
@testable import MacBookIsland

@Test("跳转后只对确认暂停的同曲启动播放，不反向暂停或盲切")
func qishuiSeekStartsPlaybackWithoutBlindToggle() {
    #expect(QishuiSeekPlaybackPolicy.shouldStartPlayback(observedIsPlaying: false, sameTrack: true, operationIsCurrent: true))
    #expect(!QishuiSeekPlaybackPolicy.shouldStartPlayback(observedIsPlaying: true, sameTrack: true, operationIsCurrent: true))
    #expect(!QishuiSeekPlaybackPolicy.shouldStartPlayback(observedIsPlaying: nil, sameTrack: true, operationIsCurrent: true))
    #expect(!QishuiSeekPlaybackPolicy.shouldStartPlayback(observedIsPlaying: false, sameTrack: false, operationIsCurrent: true))
    #expect(!QishuiSeekPlaybackPolicy.shouldStartPlayback(observedIsPlaying: false, sameTrack: true, operationIsCurrent: false))
}
