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

@Test("物理 UUID 身份首次使用时迁移旧屏幕编号校准")
@MainActor
func physicalDisplayIdentityMigratesLegacyCalibration() throws {
    let suiteName = "TopIsletTests.LayoutMigration.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let legacyIdentity = "内建视网膜显示器-1710x1107-scale2.0-id17"
    let legacySettings = LayoutCalibrationSettings(defaults: defaults)
    legacySettings.useDisplay(name: "内建视网膜显示器", identity: legacyIdentity)
    legacySettings.islandYOffset = 3.5
    legacySettings.notchHeightAdjustment = 2
    legacySettings.leftControlsXOffset = 18

    let migratedSettings = LayoutCalibrationSettings(defaults: defaults)
    migratedSettings.useDisplay(
        name: "内建视网膜显示器",
        identity: "display-physical-uuid-1710x1107-scale2.0",
        legacyIdentities: ["内建视网膜显示器-1710x1107-scale2.0-id42"],
        legacyIdentityPrefixes: ["内建视网膜显示器-1710x1107-scale2.0-id"]
    )

    #expect(migratedSettings.islandYOffset == 3.5)
    #expect(migratedSettings.notchHeightAdjustment == 2)
    #expect(migratedSettings.leftControlsXOffset == 18)

    let reloadedSettings = LayoutCalibrationSettings(defaults: defaults)
    reloadedSettings.useDisplay(
        name: "内建视网膜显示器",
        identity: "display-physical-uuid-1710x1107-scale2.0"
    )
    #expect(reloadedSettings.islandYOffset == 3.5)
    #expect(reloadedSettings.notchHeightAdjustment == 2)
    #expect(reloadedSettings.leftControlsXOffset == 18)
}

@Test("已有 UUID 校准不被旧屏幕编号数据覆盖")
@MainActor
func existingPhysicalDisplayCalibrationWinsOverLegacyValues() throws {
    let suiteName = "TopIsletTests.LayoutMigrationPrecedence.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let legacyIdentity = "legacy-display"
    let physicalIdentity = "physical-display"
    let settings = LayoutCalibrationSettings(defaults: defaults)
    settings.useDisplay(name: "旧屏幕", identity: legacyIdentity)
    settings.islandYOffset = 11
    settings.useDisplay(name: "物理屏幕", identity: physicalIdentity)
    settings.islandYOffset = 4

    let reloadedSettings = LayoutCalibrationSettings(defaults: defaults)
    reloadedSettings.useDisplay(
        name: "物理屏幕",
        identity: physicalIdentity,
        legacyIdentities: [legacyIdentity]
    )

    #expect(reloadedSettings.islandYOffset == 4)
}
