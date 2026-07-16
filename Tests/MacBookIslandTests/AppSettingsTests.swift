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
