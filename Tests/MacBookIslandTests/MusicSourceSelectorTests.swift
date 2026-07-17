import Foundation
import Testing
@testable import MacBookIsland

private func candidate(
    _ source: MusicSourceID,
    available: Bool = true,
    hasTrack: Bool = true,
    playback: MusicSourcePlaybackLevel,
    cached: Bool = false
) -> MusicSourceCandidate {
    MusicSourceCandidate(
        source: source,
        isAvailable: available,
        hasTrack: hasTrack,
        playback: playback,
        isCached: cached
    )
}

@Test("三来源同时播放时优先级为汽水、网易云、Apple Music")
func threeSourcePlaybackPriorityIsStable() {
    let selector = MusicSourceSelector()
    let allPlaying = selector.update(
        qishui: candidate(.qishui, playback: .playing),
        neteaseMusic: candidate(.neteaseMusic, playback: .playing),
        appleMusic: candidate(.appleMusic, playback: .playing)
    )
    #expect(allPlaying.source == .qishui)

    let afterQishuiExit = selector.update(
        qishui: candidate(
            .qishui,
            available: false,
            hasTrack: false,
            playback: .unknown
        ),
        neteaseMusic: candidate(.neteaseMusic, playback: .playing),
        appleMusic: candidate(.appleMusic, playback: .playing)
    )
    #expect(afterQishuiExit.source == .neteaseMusic)
}

@Test("前台网易云立即成为显示和控制来源")
func foregroundNeteaseMusicSwitchesImmediately() {
    let selector = MusicSourceSelector()
    _ = selector.update(
        qishui: candidate(.qishui, playback: .playing),
        neteaseMusic: candidate(.neteaseMusic, playback: .paused),
        appleMusic: candidate(.appleMusic, playback: .playing)
    )
    let selection = selector.update(
        qishui: candidate(.qishui, playback: .playing),
        neteaseMusic: candidate(.neteaseMusic, playback: .paused),
        appleMusic: candidate(.appleMusic, playback: .playing),
        foregroundSource: .neteaseMusic
    )

    #expect(selection.source == .neteaseMusic)
}

@Test("网易云退出后立即回退到 Apple Music")
func neteaseMusicExitFallsBackImmediately() {
    let selector = MusicSourceSelector()
    _ = selector.update(
        qishui: candidate(
            .qishui,
            available: false,
            hasTrack: false,
            playback: .unknown
        ),
        neteaseMusic: candidate(.neteaseMusic, playback: .playing),
        appleMusic: candidate(.appleMusic, playback: .paused)
    )
    let selection = selector.update(
        qishui: candidate(
            .qishui,
            available: false,
            hasTrack: false,
            playback: .unknown
        ),
        neteaseMusic: candidate(
            .neteaseMusic,
            available: false,
            hasTrack: false,
            playback: .unknown
        ),
        appleMusic: candidate(.appleMusic, playback: .paused)
    )

    #expect(selection.source == .appleMusic)
}

@Test("两者同时播放时汽水优先")
func qishuiWinsWhenBothArePlaying() {
    let selector = MusicSourceSelector()
    let selection = selector.update(
        qishui: candidate(.qishui, playback: .playing),
        appleMusic: candidate(.appleMusic, playback: .playing)
    )

    #expect(selection.source == .qishui)
}

@Test("汽水暂停且 Apple Music 播放时延迟切换")
func appleMusicRequiresStablePlaybackBeforeSwitch() {
    let selector = MusicSourceSelector()
    let startedAt = Date(timeIntervalSince1970: 100)
    _ = selector.update(
        qishui: candidate(.qishui, playback: .playing),
        appleMusic: candidate(.appleMusic, playback: .paused),
        at: startedAt
    )

    let pending = selector.update(
        qishui: candidate(.qishui, playback: .paused),
        appleMusic: candidate(.appleMusic, playback: .playing),
        at: startedAt.addingTimeInterval(0.1)
    )
    let committed = selector.update(
        qishui: candidate(.qishui, playback: .paused),
        appleMusic: candidate(.appleMusic, playback: .playing),
        at: startedAt.addingTimeInterval(
            0.11 + MusicSourceSelector.appleMusicSwitchDelay
        )
    )

    #expect(pending.source == .qishui)
    #expect(committed.source == .appleMusic)
}

@Test("双来源快速抖动不会切换且稳定播放在一个 tick 内提交")
func rapidSourceFlappingDoesNotChangeSelection() {
    let selector = MusicSourceSelector()
    let startedAt = Date(timeIntervalSince1970: 200)
    _ = selector.update(
        qishui: candidate(.qishui, playback: .playing),
        appleMusic: candidate(.appleMusic, playback: .paused),
        at: startedAt
    )

    for index in 1...100 {
        let appleMusicIsPlaying = index.isMultiple(of: 2)
        let selection = selector.update(
            qishui: candidate(
                .qishui,
                playback: appleMusicIsPlaying ? .paused : .playing
            ),
            appleMusic: candidate(
                .appleMusic,
                playback: appleMusicIsPlaying ? .playing : .paused
            ),
            at: startedAt.addingTimeInterval(Double(index) * 0.05)
        )
        #expect(selection.source == .qishui)
    }

    let stableStartedAt = startedAt.addingTimeInterval(5.1)
    _ = selector.update(
        qishui: candidate(.qishui, playback: .paused),
        appleMusic: candidate(.appleMusic, playback: .playing),
        at: stableStartedAt
    )
    let committed = selector.update(
        qishui: candidate(.qishui, playback: .paused),
        appleMusic: candidate(.appleMusic, playback: .playing),
        at: stableStartedAt.addingTimeInterval(0.5)
    )

    #expect(committed.source == .appleMusic)
}

@Test("汽水退出时立即切到可用的 Apple Music")
func qishuiExitInvalidatesCurrentSelectionImmediately() {
    let selector = MusicSourceSelector()
    _ = selector.update(
        qishui: candidate(.qishui, playback: .playing),
        appleMusic: candidate(.appleMusic, playback: .paused)
    )

    let selection = selector.update(
        qishui: candidate(
            .qishui,
            available: false,
            hasTrack: false,
            playback: .unknown
        ),
        appleMusic: candidate(.appleMusic, playback: .paused)
    )

    #expect(selection.source == .appleMusic)
}

@Test("两者暂停时保持当前来源")
func pausedSourcesKeepCurrentSelection() {
    let selector = MusicSourceSelector()
    _ = selector.update(
        qishui: candidate(
            .qishui,
            available: false,
            hasTrack: false,
            playback: .unknown
        ),
        appleMusic: candidate(.appleMusic, playback: .paused)
    )
    let selection = selector.update(
        qishui: candidate(.qishui, playback: .paused),
        appleMusic: candidate(.appleMusic, playback: .paused)
    )

    #expect(selection.source == .appleMusic)
}

@Test("缓存汽水不能从 Apple Music 抢回来源")
func cachedQishuiCannotStealSelection() {
    let selector = MusicSourceSelector()
    _ = selector.update(
        qishui: candidate(
            .qishui,
            available: false,
            hasTrack: false,
            playback: .unknown
        ),
        appleMusic: candidate(.appleMusic, playback: .playing)
    )
    let selection = selector.update(
        qishui: candidate(.qishui, playback: .playing, cached: true),
        appleMusic: candidate(.appleMusic, playback: .paused)
    )

    #expect(selection.source == .appleMusic)
}

@Test("当前汽水仅有缓存播放态时会让位给真实 Apple Music")
func cachedCurrentQishuiYieldsToFreshAppleMusic() {
    let selector = MusicSourceSelector()
    let startedAt = Date(timeIntervalSince1970: 100)
    _ = selector.update(
        qishui: candidate(.qishui, playback: .playing),
        appleMusic: candidate(.appleMusic, playback: .paused),
        at: startedAt
    )

    let pending = selector.update(
        qishui: candidate(.qishui, playback: .playing, cached: true),
        appleMusic: candidate(.appleMusic, playback: .playing),
        at: startedAt.addingTimeInterval(0.1)
    )
    let committed = selector.update(
        qishui: candidate(.qishui, playback: .playing, cached: true),
        appleMusic: candidate(.appleMusic, playback: .playing),
        at: startedAt.addingTimeInterval(0.95)
    )

    #expect(pending.source == .qishui)
    #expect(committed.source == .appleMusic)
}

@Test("前台 Apple Music 立即覆盖正在播放的汽水")
func foregroundAppleMusicWinsOverPlayingQishui() {
    let selector = MusicSourceSelector()
    _ = selector.update(
        qishui: candidate(.qishui, playback: .playing),
        appleMusic: candidate(.appleMusic, playback: .paused)
    )

    let selection = selector.update(
        qishui: candidate(.qishui, playback: .playing),
        appleMusic: candidate(.appleMusic, playback: .paused),
        foregroundSource: .appleMusic
    )

    #expect(selection.source == .appleMusic)
}

@Test("前台汽水立即覆盖正在播放的 Apple Music")
func foregroundQishuiWinsOverPlayingAppleMusic() {
    let selector = MusicSourceSelector()
    _ = selector.update(
        qishui: candidate(.qishui, playback: .paused),
        appleMusic: candidate(.appleMusic, playback: .playing)
    )

    let selection = selector.update(
        qishui: candidate(.qishui, playback: .paused),
        appleMusic: candidate(.appleMusic, playback: .playing),
        foregroundSource: .qishui
    )

    #expect(selection.source == .qishui)
}

@Test("前台音乐应用无当前歌曲时仍显示该应用")
func foregroundAvailableSourceDoesNotRequireTrack() {
    let selector = MusicSourceSelector()
    let selection = selector.update(
        qishui: candidate(.qishui, playback: .playing),
        appleMusic: candidate(
            .appleMusic,
            hasTrack: false,
            playback: .unknown
        ),
        foregroundSource: .appleMusic
    )

    #expect(selection.source == .appleMusic)
}

@Test("前台来源不可用时回退到真实播放来源")
func unavailableForegroundSourceFallsBackToPlayback() {
    let selector = MusicSourceSelector()
    let selection = selector.update(
        qishui: candidate(.qishui, playback: .playing),
        appleMusic: candidate(
            .appleMusic,
            available: false,
            hasTrack: false,
            playback: .unknown
        ),
        foregroundSource: .appleMusic
    )

    #expect(selection.source == .qishui)
}

@Test("未适配的视频前台应用不能抢走汽水来源")
func unsupportedForegroundMediaCannotStealQishuiSelection() {
    let selector = MusicSourceSelector()
    let unsupportedForegroundSources = [
        "com.apple.QuickTimePlayerX",
        "com.apple.Safari",
        "com.google.Chrome"
    ]

    for bundleIdentifier in unsupportedForegroundSources {
        let foregroundSource = MusicSourceID(bundleIdentifier: bundleIdentifier)
        let selection = selector.update(
            qishui: candidate(.qishui, playback: .playing),
            appleMusic: candidate(.appleMusic, playback: .paused),
            foregroundSource: foregroundSource
        )

        #expect(foregroundSource == nil)
        #expect(selection.source == .qishui)
    }
}

@Test("汽水控制绑定来自岛当前显示来源")
func qishuiControlBindingUsesDisplayedSource() {
    let binding = DisplayedMusicControlBinding(
        displayedSourceBundleIdentifier: "com.soda.music"
    )

    #expect(binding?.source == .qishui)
}

@Test("Apple Music 控制绑定来自岛当前显示来源")
func appleMusicControlBindingUsesDisplayedSource() {
    let binding = DisplayedMusicControlBinding(
        displayedSourceBundleIdentifier: "com.apple.Music"
    )

    #expect(binding?.source == .appleMusic)
}

@Test("未知显示来源必须拒绝控制")
func unknownDisplayedSourceFailsClosed() {
    let binding = DisplayedMusicControlBinding(
        displayedSourceBundleIdentifier: "com.example.unsupported"
    )

    #expect(binding == nil)
}
