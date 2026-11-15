import Testing
import Foundation
@testable import MacBookIsland

private func track(_ progress: Double?, isPlaying: Bool? = nil, title: String = "歌") -> QishuiDirectTrack {
    QishuiDirectTrack(title: title, artist: "歌手", artworkURL: nil, lyrics: [],
                      isPlaying: isPlaying, progress: progress, sourceName: "汽水窗口 AX")
}

@Test("汽水播放推断：进度前进判为播放，原地 1.35 秒判为暂停")
func qishuiInferenceFromProgress() {
    var inference = QishuiPlaybackInference()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    inference.update(track: track(0.30), checkedAt: t0)
    #expect(inference.inferredIsPlaying == nil)
    inference.update(track: track(0.31), checkedAt: t0.addingTimeInterval(1))
    #expect(inference.inferredIsPlaying == true)
    #expect(inference.label(for: track(0.31)) == "播放中")
    inference.update(track: track(0.31), checkedAt: t0.addingTimeInterval(2))
    #expect(inference.inferredIsPlaying == true)
    inference.update(track: track(0.31), checkedAt: t0.addingTimeInterval(2.4))
    #expect(inference.inferredIsPlaying == false)
    #expect(inference.label(for: track(0.31)) == "已暂停")
}

@Test("汽水播放推断：明确的播放标志优先，换歌与重置不沿用旧进度")
func qishuiInferenceExplicitFlagAndReset() {
    var inference = QishuiPlaybackInference()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    inference.update(track: track(0.5, isPlaying: false), checkedAt: t0)
    #expect(inference.inferredIsPlaying == false)
    // A different track's progress is not compared with the previous track.
    inference.update(track: track(0.6, title: "另一首"), checkedAt: t0.addingTimeInterval(1))
    #expect(inference.inferredIsPlaying == nil)
    inference.update(track: track(0.7, title: "另一首"), checkedAt: t0.addingTimeInterval(2))
    #expect(inference.inferredIsPlaying == true)
    inference.reset()
    #expect(inference.inferredIsPlaying == nil)
    #expect(inference.label(for: track(0.7)) == "等待进度变化确认")
}
