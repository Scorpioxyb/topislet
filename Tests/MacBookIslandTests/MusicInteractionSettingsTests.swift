import Foundation
import Testing
@testable import MacBookIsland

@Test("展开方式持久化，旧自动歌词展开偏好迁移，重置恢复悬停")
@MainActor
func musicExpansionPreferenceMigration() throws {
    let name = "TopIsletTests.Interaction.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    #expect(AppSettings(defaults: defaults).musicExpansionMode == .hover)
    defaults.set(true, forKey: "MacBookIsland.AppSettings.autoExpandMusicLyrics")
    let migrated = AppSettings(defaults: defaults)
    #expect(migrated.musicExpansionMode == .pinned)
    migrated.musicExpansionMode = .click
    #expect(AppSettings(defaults: defaults).musicExpansionMode == .click)
    migrated.showMusicLyrics = true
    #expect(migrated.musicExpansionMode == .click)
    migrated.resetToDefaults()
    #expect(AppSettings(defaults: defaults).musicExpansionMode == .hover)
    #expect(!migrated.showMusicLyrics)
}

@Test("点击展开直接打开音乐；没有可用控制时仍进入活动中心")
func musicTapUsesSelectedExpansionMode() {
    for expansion in MusicExpansionMode.allCases {
        let result = CollapsedIslandTapPolicy.destination(
            activeFeature: .music, hasCurrentMusicTrack: true,
            musicControlsAvailable: true, hasPendingNotification: false,
            musicExpansionMode: expansion
        )
        #expect(result.feature == .music)
        #expect(result.mode == (expansion == .hover ? .compact : .expanded))
        #expect(CollapsedIslandTapPolicy.destination(
            activeFeature: .music, hasCurrentMusicTrack: true,
            musicControlsAvailable: false, hasPendingNotification: false,
            musicExpansionMode: expansion
        ).feature == .activityCenter)
    }
}

@Test("展开方式只影响音乐；保持展开不因外部点击收起且不抢占其他活动")
func musicExpansionIsScopedAndRespectsExplicitCollapse() {
    for expansion in MusicExpansionMode.allCases {
        #expect(MusicInteractionPolicy.allowsHover(feature: .music, expansion: expansion)
            == (expansion == .hover))
        #expect(MusicInteractionPolicy.allowsHover(feature: .timer, expansion: expansion))
        #expect(MusicInteractionPolicy.allowsOutsideCollapse(feature: .music, expansion: expansion)
            == (expansion != .pinned))
        #expect(MusicInteractionPolicy.allowsOutsideCollapse(feature: .notification, expansion: expansion))
        #expect(MusicInteractionPolicy.arrivalMode(currentMode: .collapsed, expansion: expansion)
            == (expansion == .pinned ? .expanded : .collapsed))
        #expect(!MusicInteractionPolicy.shouldOpenOnPreferenceChange(
            feature: .timer, hasTrack: true, expansion: expansion))
        #expect(!MusicInteractionPolicy.shouldOpenOnPreferenceChange(
            feature: .music, hasTrack: false, expansion: expansion))
    }
    // Metadata/lyric updates do not use arrivalMode; an explicit collapse remains owned by the user.
    #expect(MusicInteractionPolicy.shouldOpenOnPreferenceChange(
        feature: .music, hasTrack: true, expansion: .pinned))
}
