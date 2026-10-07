import CryptoKit
import Foundation

/// Keeps the local Qishui storage probe useful without printing user content.
public enum QishuiProbePrivacy {
    private static let candidateLabels: [(String, String)] = [
        ("currentplayablekey", "current_playable"),
        ("isplaying", "playing"),
        ("playbackrate", "playback_rate"),
        ("elapsedtimenow", "elapsed_time"),
        ("elapsedtime", "elapsed_time"),
        ("duration", "duration"),
        ("progress", "progress"),
        ("lyrics", "lyrics"),
        ("lyric", "lyrics"),
        ("url_cover", "artwork"),
        ("cover_url", "artwork"),
        ("cover", "artwork"),
        ("album", "album"),
        ("artist", "artist"),
        ("player", "player"),
        ("queue", "queue"),
        ("media", "media"),
        ("track", "track"),
        ("playing", "playing"),
        ("current", "current")
    ]

    private static let safeTopLevelKeys: Set<String> = [
        "appSettings", "auto_launch_default_set", "commerceState", "desktopLyrics",
        "did_first_use_time", "playQuality", "shortcutSettings", "userInfoStateCache",
        "volume", "windowPosition:desktopLyrics", "windowSize:main"
    ]

    private static let safeBuckets: Set<String> = [
        "LunaStorage",
        "Local Storage/leveldb",
        "Session Storage",
        "IndexedDB/app_resources_0.indexeddb.leveldb",
        "LunaCacheV2"
    ]

    public static func rootDescription(root: URL, home: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        guard rootPath != homePath else { return "~" }
        guard rootPath.hasPrefix(homePath + "/") else { return "<redacted-root>" }
        return "~/" + String(rootPath.dropFirst(homePath.count + 1))
    }

    /// Returns a structural label. Unknown keys intentionally collapse to one value.
    public static func keyLabel(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "key" }
        if safeTopLevelKeys.contains(trimmed) {
            return trimmed
        }

        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("u_") {
            if let separator = trimmed.firstIndex(of: ":") {
                let suffix = String(trimmed[trimmed.index(after: separator)...])
                return isSafeStructuralToken(suffix)
                    ? "u_<redacted>:\(suffix)"
                    : "u_<redacted>"
            }
            return "u_<redacted>"
        }
        if lowercased.hasPrefix("track-") || lowercased.hasPrefix("track_") {
            return "track-<redacted>"
        }
        if let label = candidateLabels.first(where: { lowercased.contains($0.0) })?.1 {
            return label
        }
        return "key"
    }

    public static func candidateFieldLabel(for key: String) -> String {
        let lowercased = key.lowercased()
        return candidateLabels.first(where: { lowercased.contains($0.0) })?.1 ?? "field"
    }

    public static func fileDescription(url: URL, relativeTo root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        let relativePath: String
        if filePath.hasPrefix(rootPath + "/") {
            relativePath = String(filePath.dropFirst(rootPath.count + 1))
        } else {
            relativePath = "outside-root"
        }
        let bucket = safeBuckets.first(where: { relativePath == $0 || relativePath.hasPrefix($0 + "/") })
            ?? "other"
        let fileType = URL(fileURLWithPath: relativePath).pathExtension.lowercased()
        let normalizedFileType = isSafeStructuralToken(fileType) ? fileType : "other"
        return "bucket=\(bucket) fileToken=\(fileToken(relativePath)) fileType=\(normalizedFileType)"
    }

    public static func fileToken(_ relativePath: String) -> String {
        let digest = SHA256.hash(data: Data(relativePath.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private static func isSafeStructuralToken(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            scalar == "_" || scalar == ":" || scalar == "-"
                || ("a"..."z").contains(scalar)
                || ("A"..."Z").contains(scalar)
                || ("0"..."9").contains(scalar)
        }
    }
}
