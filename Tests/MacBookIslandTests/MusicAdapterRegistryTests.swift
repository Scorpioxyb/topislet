import Foundation
import Testing
@testable import MacBookIsland

@Test("音乐适配器注册表的 Bundle ID 必须唯一")
func musicAdapterBundleIdentifiersAreUnique() {
    let bundleIdentifiers = MusicAdapterRegistry.registrations.map {
        $0.descriptor.bundleIdentifier
    }

    #expect(Set(bundleIdentifiers).count == bundleIdentifiers.count)
}

@Test("汽水是当前唯一主适配音乐应用")
func qishuiIsTheOnlyActiveMusicAdapter() throws {
    let active = MusicAdapterRegistry.activeRegistrations
    let qishui = try #require(active.first)

    #expect(active.count == 1)
    #expect(qishui.descriptor.bundleIdentifier == "com.soda.music")
    #expect(qishui.capabilities.contains(.metadata))
    #expect(qishui.capabilities.contains(.progress))
    #expect(qishui.capabilities.contains(.playPause))
    #expect(!qishui.capabilities.contains(.absoluteSeek))
}

@Test("Apple Music 登记为 Alpha 支持并声明定向能力")
func appleMusicIsRegisteredAsAlpha() throws {
    let appleMusic = try #require(
        MusicAdapterRegistry.registration(forBundleIdentifier: "com.apple.Music")
    )

    #expect(appleMusic.implementationStatus == .alpha)
    #expect(appleMusic.capabilities.contains(.metadata))
    #expect(appleMusic.capabilities.contains(.artwork))
    #expect(appleMusic.capabilities.contains(.absoluteSeek))
}

@Test("网易云音乐登记为 Alpha 且不声明全局进度跳转")
func neteaseMusicIsRegisteredAsAlpha() throws {
    let neteaseMusic = try #require(
        MusicAdapterRegistry.registration(forBundleIdentifier: "com.netease.163music")
    )

    #expect(neteaseMusic.implementationStatus == .alpha)
    #expect(neteaseMusic.capabilities.contains(.metadata))
    #expect(neteaseMusic.capabilities.contains(.artwork))
    #expect(neteaseMusic.capabilities.contains(.playPause))
    #expect(!neteaseMusic.capabilities.contains(.absoluteSeek))
}

@Test("网易云运行状态区分未运行、待授权与已连接")
func neteaseMusicRuntimePresentationReflectsConnection() {
    #expect(MusicAdapterRuntimePresenter.neteaseMusic(
        isRunning: false,
        accessibilityTrusted: true,
        snapshotAvailability: nil
    ).level == .inactive)
    #expect(MusicAdapterRuntimePresenter.neteaseMusic(
        isRunning: true,
        accessibilityTrusted: false,
        snapshotAvailability: .ready
    ).level == .actionRequired)
    #expect(MusicAdapterRuntimePresenter.neteaseMusic(
        isRunning: true,
        accessibilityTrusted: true,
        snapshotAvailability: .ready
    ).level == .connected)
}

@Test("汽水运行状态区分未运行与辅助功能待授权")
func qishuiRuntimePresentationExplainsControlPermission() {
    #expect(MusicAdapterRuntimePresenter.qishui(
        isRunning: false,
        accessibilityTrusted: false
    ).level == .inactive)
    #expect(MusicAdapterRuntimePresenter.qishui(
        isRunning: true,
        accessibilityTrusted: false
    ).level == .actionRequired)
    #expect(MusicAdapterRuntimePresenter.qishui(
        isRunning: true,
        accessibilityTrusted: true
    ).level == .connected)
}

@Test("Apple Music 运行状态区分关闭、授权与连接异常")
func appleMusicRuntimePresentationReflectsProductState() {
    #expect(MusicAdapterRuntimePresenter.appleMusic(
        isEnabled: false,
        isRunning: true,
        automationAccess: .allowed,
        snapshotAvailability: .ready
    ).title == "已关闭")
    #expect(MusicAdapterRuntimePresenter.appleMusic(
        isEnabled: true,
        isRunning: true,
        automationAccess: .consentRequired,
        snapshotAvailability: nil
    ).level == .actionRequired)
    #expect(MusicAdapterRuntimePresenter.appleMusic(
        isEnabled: true,
        isRunning: true,
        automationAccess: .allowed,
        snapshotAvailability: .ready
    ).level == .connected)
    #expect(MusicAdapterRuntimePresenter.appleMusic(
        isEnabled: true,
        isRunning: true,
        automationAccess: .allowed,
        snapshotAvailability: .degraded(reason: "timeout")
    ).level == .error)
}

@Test("控制能力只能在绑定具体应用实例后声明可用")
func controlCapabilitiesRequireTargetInstance() {
    let target = MusicAppInstance(
        app: MusicAdapterRegistry.qishui.descriptor,
        processIdentifier: 42,
        launchedAt: nil
    )
    let controls = MusicControlCapabilities(values: [
        .playPause: .ready(
            target: target,
            mechanism: .semanticAccessibility,
            verifiedAt: Date(timeIntervalSince1970: 1_000)
        ),
        .absoluteSeek: .unavailable(reason: "没有汽水专属跳转接口")
    ])

    #expect(controls.supports(.playPause))
    #expect(!controls.supports(.absoluteSeek))
}
