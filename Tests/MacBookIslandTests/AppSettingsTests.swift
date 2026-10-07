import Foundation
import Testing
@testable import MacBookIsland

@Test("Apple Music 适配默认开启且会持久化用户选择")
@MainActor
func appleMusicSettingPersistsUserChoice() throws {
    let suiteName = "TopIsletTests.AppSettings.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let initial = AppSettings(defaults: defaults)
    #expect(initial.appleMusicEnabled)

    initial.appleMusicEnabled = false
    let reloaded = AppSettings(defaults: defaults)
    #expect(!reloaded.appleMusicEnabled)
}

@Test("歌词显示偏好默认关闭且会持久化用户选择")
@MainActor
func musicLyricsSettingPersistsUserChoice() throws {
    let suiteName = "TopIsletTests.AppSettings.Lyrics.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let initial = AppSettings(defaults: defaults)
    #expect(!initial.showMusicLyrics)

    initial.showMusicLyrics = true
    let reloaded = AppSettings(defaults: defaults)
    #expect(reloaded.showMusicLyrics)
}

@Test("歌词自动展开偏好默认关闭且会持久化用户选择")
@MainActor
func musicLyricsAutoExpansionSettingPersistsUserChoice() throws {
    let suiteName = "TopIsletTests.AppSettings.LyricsAutoExpand.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let initial = AppSettings(defaults: defaults)
    #expect(!initial.autoExpandMusicLyrics)

    initial.autoExpandMusicLyrics = true
    let reloaded = AppSettings(defaults: defaults)
    #expect(reloaded.autoExpandMusicLyrics)
}
