import Testing
@testable import MacBookIsland

@Test("辅助功能失效时汽水和网易云控制按钮提供恢复入口")
func accessibilityControlledMusicSourcesOfferPermissionRecovery() {
    #expect(MusicControlPermissionRecoveryPolicy.allowsRecovery(
        sourceBundleIdentifier: "com.soda.music",
        accessibilityTrusted: false
    ))
    #expect(MusicControlPermissionRecoveryPolicy.allowsRecovery(
        sourceBundleIdentifier: "com.netease.163music",
        accessibilityTrusted: false
    ))
}

@Test("已授权或非 AX 音乐来源不提供辅助功能恢复入口")
func unrelatedMusicSourcesDoNotOfferPermissionRecovery() {
    #expect(!MusicControlPermissionRecoveryPolicy.allowsRecovery(
        sourceBundleIdentifier: "com.soda.music",
        accessibilityTrusted: true
    ))
    #expect(!MusicControlPermissionRecoveryPolicy.allowsRecovery(
        sourceBundleIdentifier: "com.apple.Music",
        accessibilityTrusted: false
    ))
    #expect(!MusicControlPermissionRecoveryPolicy.allowsRecovery(
        sourceBundleIdentifier: nil,
        accessibilityTrusted: false
    ))
}
