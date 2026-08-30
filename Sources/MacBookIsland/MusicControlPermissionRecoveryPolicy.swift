import Foundation

enum MusicControlPermissionRecoveryPolicy {
    private static let accessibilityControlledSources: Set<String> = [
        "com.soda.music",
        "com.netease.163music"
    ]

    static func allowsRecovery(
        sourceBundleIdentifier: String?,
        accessibilityTrusted: Bool
    ) -> Bool {
        guard !accessibilityTrusted,
              let sourceBundleIdentifier else { return false }
        return accessibilityControlledSources.contains(sourceBundleIdentifier)
    }
}
