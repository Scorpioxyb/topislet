import Foundation
import Testing
@testable import MacBookIsland

@Test("恢复默认布局会立即持久化当前屏幕的全部默认值")
@MainActor
func layoutResetPersistsAllDefaultsForCurrentDisplay() throws {
    let suiteName = "TopIsletTests.LayoutCalibration.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = LayoutCalibrationSettings(defaults: defaults)
    settings.useDisplay(name: "测试屏幕", identity: "display-a")
    settings.islandYOffset = 18
    settings.notchHeightAdjustment = 6
    settings.expandedHeightAdjustment = 44
    settings.expandedTopControlsTopOffset = 11
    settings.leftControlsXOffset = 4
    settings.leftControlsYOffset = 5
    settings.rightControlsXOffset = 7
    settings.rightControlsYOffset = 8
    settings.expandedContentTopGap = 63

    settings.resetToDefaults()

    let reloaded = LayoutCalibrationSettings(defaults: defaults)
    reloaded.useDisplay(name: "测试屏幕", identity: "display-a")
    #expect(reloaded.islandYOffset == 0)
    #expect(reloaded.notchHeightAdjustment == 1)
    #expect(reloaded.expandedHeightAdjustment == 0)
    #expect(reloaded.expandedTopControlsTopOffset == 4)
    #expect(reloaded.leftControlsXOffset == 22)
    #expect(reloaded.leftControlsYOffset == 0)
    #expect(reloaded.rightControlsXOffset == 22)
    #expect(reloaded.rightControlsYOffset == -1)
    #expect(reloaded.expandedContentTopGap == 46)
}

@Test("恢复默认布局只影响当前屏幕")
@MainActor
func layoutResetDoesNotOverwriteOtherDisplays() throws {
    let suiteName = "TopIsletTests.LayoutCalibration.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = LayoutCalibrationSettings(defaults: defaults)
    settings.useDisplay(name: "屏幕 A", identity: "display-a")
    settings.islandYOffset = 9
    settings.useDisplay(name: "屏幕 B", identity: "display-b")
    settings.islandYOffset = 17

    settings.resetToDefaults()

    #expect(settings.islandYOffset == 0)
    settings.useDisplay(name: "屏幕 A", identity: "display-a")
    #expect(settings.islandYOffset == 9)
}
