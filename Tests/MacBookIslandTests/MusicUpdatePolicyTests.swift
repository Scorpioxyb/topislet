import Foundation
import Testing
@testable import MacBookIsland

private func musicState(
    title: String,
    progress: Double,
    elapsedTime: TimeInterval?,
    duration: TimeInterval?,
    sourceBundleIdentifier: String = "com.soda.music"
) -> MusicState {
    MusicState(
        track: MusicTrack(
            title: title,
            artist: "Artist",
            palette: [],
            lyrics: [],
            hasArtwork: false,
            artworkData: nil,
            artworkURL: nil,
            sourceBundleIdentifier: sourceBundleIdentifier
        ),
        isPlaying: elapsedTime != nil,
        progress: progress,
        lyricIndex: 0,
        elapsedTime: elapsedTime,
        duration: duration,
        canSeek: false
    )
}

@Test("跨音乐应用切换不能被进度归零保护拦截")
func sourceSwitchAlwaysAcceptsCandidate() {
    let current = musicState(
        title: "Apple Track",
        progress: 0.5,
        elapsedTime: 90,
        duration: 180,
        sourceBundleIdentifier: "com.apple.Music"
    )
    let candidate = musicState(
        title: "Qishui Track",
        progress: 0,
        elapsedTime: nil,
        duration: nil
    )

    #expect(!MusicUpdatePolicy.shouldIgnoreUntrustedProgressReset(
        current: current,
        candidate: candidate,
        sourceAvailability: .qishuiDetectedAXLimited
    ))
}

@Test("普通 AX 瞬时归零仍保留可信时间轴")
func transientUntrustedResetIsIgnored() {
    let current = musicState(
        title: "Current",
        progress: 0.5,
        elapsedTime: 90,
        duration: 180
    )
    let candidate = musicState(
        title: "Current",
        progress: 0,
        elapsedTime: nil,
        duration: nil
    )

    #expect(MusicUpdatePolicy.shouldIgnoreUntrustedProgressReset(
        current: current,
        candidate: candidate,
        sourceAvailability: .qishuiDetectedAXLimited
    ))
}

@Test("汽水退出必须清除最后一首歌曲")
func qishuiExitAlwaysAcceptsIdleReset() {
    let current = musicState(
        title: "Current",
        progress: 0.5,
        elapsedTime: 90,
        duration: 180
    )
    let candidate = musicState(
        title: "汽水音乐",
        progress: 0,
        elapsedTime: nil,
        duration: nil
    )

    #expect(!MusicUpdatePolicy.shouldIgnoreUntrustedProgressReset(
        current: current,
        candidate: candidate,
        sourceAvailability: .qishuiNotRunning
    ))
}
