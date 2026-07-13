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

@Test("汽水是当前唯一启用的音乐适配器")
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

@Test("Apple Music 登记为实验适配并声明定向能力")
func appleMusicIsRegisteredAsExperimental() throws {
    let appleMusic = try #require(
        MusicAdapterRegistry.registration(forBundleIdentifier: "com.apple.Music")
    )

    #expect(appleMusic.implementationStatus == .experimental)
    #expect(appleMusic.capabilities.contains(.metadata))
    #expect(appleMusic.capabilities.contains(.absoluteSeek))
    #expect(!appleMusic.capabilities.contains(.artwork))
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
