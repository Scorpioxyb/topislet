import Foundation
import Testing
@testable import MacBookIsland

@Test("切歌交付只认可完整目标，不能把旧 AX 或跨来源帧计为完成")
func transitionDeliveryRequiresActualCompleteTarget() {
    let event = QishuiTrackTransitionStageEvent(
        transitionID: "test", stage: .atomicComplete, latencyMilliseconds: 600,
        hasArtist: true, hasArtwork: true, hasAlbum: true, hasDuration: true, wasDeferred: true,
        candidateTrackIdentity: QishuiLyricIdentity(
            processIdentifier: 123, title: "Song B", artist: "Artist"))
    var state = musicState(title: "Song B", progress: 0.1, elapsedTime: 20, duration: 200)
    #expect(!QishuiTransitionDeliveryPolicy.accepts(state: state, complete: event))
    func track(title: String = "Song B", artist: String = "Artist", source: String = "com.soda.music") -> MusicTrack {
        MusicTrack(title: title, artist: artist, palette: [], lyrics: [], hasArtwork: true,
            artworkData: Data([0x62]), artworkURL: nil, sourceBundleIdentifier: source)
    }
    state.track = track()
    #expect(QishuiTransitionDeliveryPolicy.accepts(state: state, complete: event))
    state.duration = nil
    #expect(!QishuiTransitionDeliveryPolicy.accepts(state: state, complete: event))
    state.duration = 200
    state.track = track(title: "Song A")
    #expect(!QishuiTransitionDeliveryPolicy.accepts(state: state, complete: event))
    state.track = track(artist: "Another Artist")
    #expect(!QishuiTransitionDeliveryPolicy.accepts(state: state, complete: event))
    state.track = track(source: "com.apple.Music")
    #expect(!QishuiTransitionDeliveryPolicy.accepts(state: state, complete: event))
}

@Test("播放真假不变但权威状态变为未知时仍需更新图标")
func playbackAuthorityChangePublishesWithoutTimelineChange() {
    let current = musicState(title: "Song", progress: 0.2, elapsedTime: 20, duration: 100)
    var candidate = current
    candidate.playbackStateKnown = false
    #expect(MusicUpdatePolicy.playbackPresentationChanged(current: current, candidate: candidate))
    #expect(MusicUpdatePolicy.playbackPresentationChanged(current: candidate, candidate: current))
    #expect(!MusicUpdatePolicy.playbackPresentationChanged(current: current, candidate: current))
    candidate = current
    candidate.isPlaying = !current.isPlaying
    #expect(MusicUpdatePolicy.playbackPresentationChanged(current: current, candidate: candidate))
}

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

@Test("同来源新歌缺少时间轴时不能被旧歌进度保护吞掉")
func newTrackWithoutTimingDoesNotKeepOldTrack() {
    let current = musicState(title: "Track A", progress: 0.5, elapsedTime: 90, duration: 180)
    let candidate = musicState(title: "Track B", progress: 0, elapsedTime: nil, duration: nil)
    #expect(!MusicUpdatePolicy.shouldIgnoreUntrustedProgressReset(
        current: current, candidate: candidate, sourceAvailability: .qishuiDetectedAXLimited
    ))
}

@Test("保留同曲时间轴时仍同步播放状态可信度与控制能力")
func preservedTimelineUpdatesPlaybackAuthority() {
    let current = musicState(title: "Current", progress: 0.5, elapsedTime: 90, duration: 180)
    var candidate = musicState(title: "Current", progress: 0, elapsedTime: nil, duration: nil)
    candidate.playbackStateKnown = false
    candidate.isPlaybackPending = true
    candidate.canPlayPause = false
    candidate.canPreviousTrack = false
    candidate.canNextTrack = false
    candidate.controlUnavailableReason = "Unavailable"
    #expect(MusicUpdatePolicy.shouldIgnoreUntrustedProgressReset(
        current: current, candidate: candidate, sourceAvailability: .qishuiDetectedAXLimited
    ))
    let result = MusicUpdatePolicy.preservingTimeline(current: current, candidate: candidate)
    #expect(result.track == current.track)
    #expect(result.elapsedTime == 90 && result.duration == 180 && result.progress == 0.5)
    #expect(!result.playbackStateKnown && !result.isPlaying && result.isPlaybackPending)
    #expect(!result.canPlayPause && !result.canPreviousTrack && !result.canNextTrack)
    #expect(result.controlUnavailableReason == candidate.controlUnavailableReason)
}

@Test("同名不同歌手不能沿用旧歌的进度与歌词")
func changedArtistWithoutTimingDoesNotKeepOldTrack() {
    let current = musicState(title: "Same title", progress: 0.5, elapsedTime: 90, duration: 180)
    var candidate = musicState(title: "Same title", progress: 0, elapsedTime: nil, duration: nil)
    candidate.track = MusicTrack(
        title: candidate.track.title, artist: "Another Artist", palette: [], lyrics: [],
        hasArtwork: false, artworkData: nil, artworkURL: nil,
        sourceBundleIdentifier: candidate.track.sourceBundleIdentifier
    )
    #expect(!MusicUpdatePolicy.shouldIgnoreUntrustedProgressReset(
        current: current, candidate: candidate, sourceAvailability: .qishuiDetectedAXLimited
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

@Test("空岛只响应点击，不因悬停展开空内容")
func activityCenterDoesNotExpandOnHover() {
    #expect(!IslandExpansionPolicy.allowsExpansion(
        activeFeature: .activityCenter,
        hasCurrentMusicTrack: false,
        hasPendingNotification: false
    ))
    #expect(!IslandExpansionPolicy.allowsExpansion(
        activeFeature: .music,
        hasCurrentMusicTrack: false,
        hasPendingNotification: false
    ))
    #expect(IslandExpansionPolicy.allowsExpansion(
        activeFeature: .music,
        hasCurrentMusicTrack: true,
        hasPendingNotification: false
    ))
    #expect(IslandExpansionPolicy.allowsExpansion(
        activeFeature: .timer,
        hasCurrentMusicTrack: false,
        hasPendingNotification: false
    ))
    #expect(!IslandExpansionPolicy.allowsExpansion(
        activeFeature: .notification,
        hasCurrentMusicTrack: false,
        hasPendingNotification: false
    ))
}

@Test("空岛点击直接打开活动中心，真实音乐仍进入音乐紧凑态")
func collapsedIslandTapRoutesToUsefulContent() {
    #expect(CollapsedIslandTapPolicy.destination(
        activeFeature: .music,
        hasCurrentMusicTrack: false,
        hasPendingNotification: false
    ) == IslandPresentationDestination(feature: .activityCenter, mode: .expanded))
    #expect(CollapsedIslandTapPolicy.destination(
        activeFeature: .activityCenter,
        hasCurrentMusicTrack: false,
        hasPendingNotification: false
    ) == IslandPresentationDestination(feature: .activityCenter, mode: .expanded))
    #expect(CollapsedIslandTapPolicy.destination(
        activeFeature: .activityCenter,
        hasCurrentMusicTrack: true,
        hasPendingNotification: false
    ) == IslandPresentationDestination(feature: .music, mode: .compact))
    #expect(CollapsedIslandTapPolicy.destination(
        activeFeature: .music,
        hasCurrentMusicTrack: true,
        hasPendingNotification: false
    ) == IslandPresentationDestination(feature: .music, mode: .compact))
    #expect(CollapsedIslandTapPolicy.destination(
        activeFeature: .notification,
        hasCurrentMusicTrack: false,
        hasPendingNotification: false
    ) == IslandPresentationDestination(feature: .activityCenter, mode: .expanded))
    #expect(CollapsedIslandTapPolicy.destination(
        activeFeature: .timer,
        hasCurrentMusicTrack: false,
        hasPendingNotification: false
    ) == IslandPresentationDestination(feature: .timer, mode: .compact))
    #expect(CollapsedIslandTapPolicy.destination(
        activeFeature: .notification,
        hasCurrentMusicTrack: false,
        hasPendingNotification: true
    ) == IslandPresentationDestination(feature: .notification, mode: .compact))
}

@Test("音乐控制不可用时折叠岛降级到活动中心")
func collapsedIslandTapFallsBackWhenMusicControlsAreUnavailable() {
    #expect(CollapsedIslandTapPolicy.destination(
        activeFeature: .music,
        hasCurrentMusicTrack: true,
        musicControlsAvailable: false,
        hasPendingNotification: false
    ) == IslandPresentationDestination(feature: .activityCenter, mode: .expanded))
    #expect(CollapsedIslandTapPolicy.destination(
        activeFeature: .activityCenter,
        hasCurrentMusicTrack: true,
        musicControlsAvailable: false,
        hasPendingNotification: false
    ) == IslandPresentationDestination(feature: .activityCenter, mode: .expanded))
}

@Test("只有至少一个定向控制可用时才把音乐作为可交互活动")
func musicActivityPresentationRequiresAControl() {
    #expect(MusicActivityPresentationPolicy.controlsAvailable(
        canPlayPause: true,
        canPreviousTrack: false,
        canNextTrack: false
    ))
    #expect(MusicActivityPresentationPolicy.controlsAvailable(
        canPlayPause: false,
        canPreviousTrack: false,
        canNextTrack: true
    ))
    #expect(!MusicActivityPresentationPolicy.controlsAvailable(
        canPlayPause: false,
        canPreviousTrack: false,
        canNextTrack: false
    ))
}

@Test("专注计时提供四个固定时长并换算为秒")
func focusTimerPresetsExposeSupportedDurations() {
    #expect(FocusTimerPreset.allCases.map(\.rawValue) == [5, 15, 25, 45])
    #expect(FocusTimerPreset.fiveMinutes.durationSeconds == 300)
    #expect(FocusTimerPreset.twentyFiveMinutes.durationSeconds == 1_500)
    #expect(FocusTimerPreset.fortyFiveMinutes.title == "45 分钟")
}

@Test("提醒结束后只恢复仍在运行的计时活动")
func notificationReturnsToLiveTimerOnly() {
    #expect(IslandActivityArbitrationPolicy.featureAfterNotification(
        returnFeature: .timer,
        timerIsRunning: true,
        hasCurrentMusicTrack: false
    ) == .timer)
    #expect(IslandActivityArbitrationPolicy.featureAfterNotification(
        returnFeature: .timer,
        timerIsRunning: false,
        hasCurrentMusicTrack: false
    ) == .activityCenter)
    #expect(IslandActivityArbitrationPolicy.featureAfterNotification(
        returnFeature: .music,
        timerIsRunning: true,
        hasCurrentMusicTrack: true
    ) == .music)
    #expect(IslandActivityArbitrationPolicy.featureAfterNotification(
        returnFeature: .activityCenter,
        timerIsRunning: false,
        hasCurrentMusicTrack: true
    ) == .music)
    #expect(IslandActivityArbitrationPolicy.featureAfterNotification(
        returnFeature: nil,
        timerIsRunning: false,
        hasCurrentMusicTrack: false
    ) == .activityCenter)
}

@Test("真实音乐出现时只接管空活动中心")
func musicTakesOverIdleActivityCenter() {
    #expect(IslandActivityArbitrationPolicy.shouldMusicTakeOver(
        activeFeature: .activityCenter,
        becameAvailable: true,
        timerIsRunning: false,
        hasPendingNotification: false
    ))
    #expect(!IslandActivityArbitrationPolicy.shouldMusicTakeOver(
        activeFeature: .activityCenter,
        becameAvailable: true,
        timerIsRunning: true,
        hasPendingNotification: false
    ))
    #expect(!IslandActivityArbitrationPolicy.shouldMusicTakeOver(
        activeFeature: .notification,
        becameAvailable: true,
        timerIsRunning: false,
        hasPendingNotification: true
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
