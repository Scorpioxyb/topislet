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
        canSeek: false,
        hasCurrentTrack: true
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
    #expect(MusicUpdatePolicy.didChangeSource(
        current: current,
        candidate: candidate
    ))
}

@Test("同一音乐来源切歌不会误清理控制反馈")
func sameSourceTrackChangeKeepsControlFeedback() {
    let current = musicState(
        title: "Track A",
        progress: 0.5,
        elapsedTime: 90,
        duration: 180
    )
    let candidate = musicState(
        title: "Track B",
        progress: 0,
        elapsedTime: 0,
        duration: 200
    )

    #expect(!MusicUpdatePolicy.didChangeSource(
        current: current,
        candidate: candidate
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

@Test("空状态不触发悬停展开")
func emptyStateDoesNotExpandOnHover() {
    #expect(!IslandHoverExpansionPolicy.allowsExpansion(
        activeFeature: .music,
        hasCurrentMusicTrack: false,
        hasPendingNotification: false
    ))
    #expect(IslandHoverExpansionPolicy.allowsExpansion(
        activeFeature: .music,
        hasCurrentMusicTrack: true,
        hasPendingNotification: false
    ))
    #expect(IslandHoverExpansionPolicy.allowsExpansion(
        activeFeature: .timer,
        hasCurrentMusicTrack: false,
        hasPendingNotification: false
    ))
    #expect(!IslandHoverExpansionPolicy.allowsExpansion(
        activeFeature: .notification,
        hasCurrentMusicTrack: false,
        hasPendingNotification: false
    ))
}

@Test("真实歌曲首次出现时自动切到紧凑音乐岛")
func firstRealTrackPromotesCollapsedIslandOnce() {
    #expect(MusicPresentationTransitionPolicy.shouldPromoteToCompact(
        activeFeature: .music,
        currentMode: .collapsed,
        isArmed: true,
        hadCurrentTrack: false,
        hasCurrentTrack: true,
        hasPendingNotification: false
    ))
    #expect(!MusicPresentationTransitionPolicy.shouldPromoteToCompact(
        activeFeature: .music,
        currentMode: .collapsed,
        isArmed: true,
        hadCurrentTrack: true,
        hasCurrentTrack: true,
        hasPendingNotification: false
    ))
    #expect(!MusicPresentationTransitionPolicy.shouldPromoteToCompact(
        activeFeature: .timer,
        currentMode: .collapsed,
        isArmed: true,
        hadCurrentTrack: false,
        hasCurrentTrack: true,
        hasPendingNotification: false
    ))
    #expect(!MusicPresentationTransitionPolicy.shouldPromoteToCompact(
        activeFeature: .music,
        currentMode: .expanded,
        isArmed: true,
        hadCurrentTrack: false,
        hasCurrentTrack: true,
        hasPendingNotification: false
    ))
    #expect(!MusicPresentationTransitionPolicy.shouldPromoteToCompact(
        activeFeature: .music,
        currentMode: .collapsed,
        isArmed: false,
        hadCurrentTrack: false,
        hasCurrentTrack: true,
        hasPendingNotification: false
    ))

    #expect(MusicPresentationTransitionPolicy.shouldDisarmForUserRequest(.collapsed))
    #expect(!MusicPresentationTransitionPolicy.shouldDisarmForUserRequest(.compact))
    #expect(!MusicPresentationTransitionPolicy
        .shouldResetToDefaultAfterAllSourcesExit(currentMode: .collapsed))
    #expect(MusicPresentationTransitionPolicy
        .shouldResetToDefaultAfterAllSourcesExit(currentMode: .compact))
    #expect(MusicPresentationTransitionPolicy
        .shouldResetToDefaultAfterAllSourcesExit(currentMode: .expanded))
}
