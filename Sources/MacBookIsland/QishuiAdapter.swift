import AppKit
import Foundation

struct QishuiDirectTrack: Equatable {
    let title: String
    let artist: String
    let artworkURL: URL?
    let lyrics: [String]
    let isPlaying: Bool?
    let progress: Double?
    let sourceName: String
}

struct QishuiDirectSnapshot: Equatable {
    let isRunning: Bool
    let processIdentifier: pid_t?
    let supportRoot: URL
    let currentTrack: QishuiDirectTrack?
    let desktopLyricsEnabled: Bool?
    let queueCacheTrackCount: Int
    let queueExamples: [String]
    let diagnostic: String
    let checkedAt: Date
}

final class QishuiAdapter {
    private let bundleIdentifier = "com.soda.music"
    private let fileManager = FileManager.default
    private let axReader = QishuiAXReader(imagePrefixes: [])
    private var lastProcessIdentifier: pid_t?
    private let supportRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.soda.music/Data/Library/Application Support/SodaMusic")

    func isRunning() -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first != nil
    }

    func invalidateAXCache() {
        axReader.invalidateCache()
    }

    func snapshot() -> QishuiDirectSnapshot {
        let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
        guard let runningApp else {
            lastProcessIdentifier = nil
            axReader.invalidateCache()
            return QishuiDirectSnapshot(
                isRunning: false,
                processIdentifier: nil,
                supportRoot: supportRoot,
                currentTrack: nil,
                desktopLyricsEnabled: nil,
                queueCacheTrackCount: 0,
                queueExamples: [],
                diagnostic: "未检测到汽水音乐进程。",
                checkedAt: Date()
            )
        }

        if lastProcessIdentifier != runningApp.processIdentifier {
            lastProcessIdentifier = runningApp.processIdentifier
            axReader.invalidateCache()
        }

        let axResult = axReader.read(from: runningApp)
        let currentTrack = axResult.track

        let diagnostic: String
        if let currentTrack, currentTrack.sourceName == "汽水窗口 AX" {
            diagnostic = "\(axResult.diagnostic) 扫描节点 \(axResult.scannedNodeCount) 个；为降低延迟，本轮未读取汽水本地缓存目录。"
        } else if axResult.requiresAccessibility {
            diagnostic = axResult.diagnostic
        } else if axResult.scannedNodeCount > 0 {
            diagnostic = "\(axResult.diagnostic) 已扫描节点 \(axResult.scannedNodeCount) 个；为避免卡顿，自动同步不再读取汽水本地缓存目录。"
        } else {
            diagnostic = "已检测到汽水音乐进程，但未读到可见窗口播放态；自动同步不会打开控制中心、不会使用 OCR，也不会读取可能阻塞的本地缓存目录。"
        }

        return QishuiDirectSnapshot(
            isRunning: true,
            processIdentifier: runningApp.processIdentifier,
            supportRoot: supportRoot,
            currentTrack: currentTrack,
            desktopLyricsEnabled: nil,
            queueCacheTrackCount: 0,
            queueExamples: [],
            diagnostic: diagnostic,
            checkedAt: Date()
        )
    }

    private func decodedLunaStorageFiles() -> [String: Any] {
        let lunaRoot = supportRoot.appendingPathComponent("LunaStorage")
        guard let files = try? fileManager.contentsOfDirectory(at: lunaRoot, includingPropertiesForKeys: nil) else {
            return [:]
        }

        var decoded: [String: Any] = [:]
        for file in files {
            guard let json = decodeLunaJSON(file) else { continue }
            decoded[file.lastPathComponent] = json
        }
        return decoded
    }

    private func firstCurrentTrack(in lunaFiles: [String: Any]) -> QishuiDirectTrack? {
        for (name, json) in lunaFiles.sorted(by: { $0.key < $1.key }) {
            if let track = extractCurrentTrack(from: json, sourceName: "LunaStorage/\(name)") {
                return track
            }
        }
        return nil
    }

    private func extractCurrentTrack(from json: Any, sourceName: String) -> QishuiDirectTrack? {
        func walk(_ value: Any, depth: Int) -> QishuiDirectTrack? {
            guard depth <= 8 else { return nil }

            if let dictionary = value as? [String: Any] {
                if let track = extractSharedStateTrack(from: dictionary, sourceName: sourceName) {
                    return track
                }
                if let track = extractQueueTrack(from: dictionary, player: dictionary["player"] as? [String: Any], sourceName: sourceName) {
                    return track
                }
                for key in dictionary.keys.sorted() {
                    if let track = walk(dictionary[key] as Any, depth: depth + 1) {
                        return track
                    }
                }
            } else if let array = value as? [Any] {
                for item in array.prefix(20) {
                    if let track = walk(item, depth: depth + 1) {
                        return track
                    }
                }
            }

            return nil
        }

        return walk(json, depth: 0)
    }

    private func extractSharedStateTrack(from dictionary: [String: Any], sourceName: String) -> QishuiDirectTrack? {
        guard let player = dictionary["player"] as? [String: Any] else { return nil }

        let queueState = dictionary["queue"] as? [String: Any]
        let queueTrack = queueState.flatMap { extractPlayable(fromQueueState: $0) }
        let mediaDetail = player["mediaDetail"] as? [String: Any]
        let mediaPlayable = mediaDetail?["playable"] as? [String: Any]
        let playable = mediaPlayable ?? queueTrack

        guard let playable else { return nil }
        return makeTrack(
            from: playable,
            player: player,
            mediaDetail: mediaDetail,
            sourceName: sourceName
        )
    }

    private func extractQueueTrack(
        from dictionary: [String: Any],
        player: [String: Any]?,
        sourceName: String
    ) -> QishuiDirectTrack? {
        guard let playable = extractPlayable(fromQueueState: dictionary) else { return nil }
        return makeTrack(from: playable, player: player, mediaDetail: nil, sourceName: sourceName)
    }

    private func extractPlayable(fromQueueState queueState: [String: Any]) -> [String: Any]? {
        let queue = (queueState["queue"] as? [String: Any]) ?? queueState
        guard let currentKey = string(queue["currentPlayableKey"]) else { return nil }

        if let playables = queue["playables"] as? [String: Any] {
            return playables[currentKey] as? [String: Any]
        }

        if let playables = queue["playables"] as? [[String: Any]] {
            return playables.first { string($0["key"]) == currentKey }
        }

        return nil
    }

    private func makeTrack(
        from playable: [String: Any],
        player: [String: Any]?,
        mediaDetail: [String: Any]?,
        sourceName: String
    ) -> QishuiDirectTrack? {
        let track = (playable["track"] as? [String: Any]) ?? playable
        guard let title = string(playable["name"]) ?? string(track["name"]), !title.isEmpty else {
            return nil
        }

        let artist = artistNames(from: playable) ?? artistNames(from: track) ?? "汽水音乐"
        let progress = progressRatio(player: player, track: track)
        let playerMediaDetail = player?["mediaDetail"] as? [String: Any]
        let lyrics = lyricLines(from: mediaDetail?["lyrics"])
            + lyricLines(from: playerMediaDetail?["lyrics"])
        let artwork = artworkURL(from: playable) ?? artworkURL(from: track)

        return QishuiDirectTrack(
            title: title,
            artist: artist,
            artworkURL: artwork,
            lyrics: lyrics.isEmpty ? ["来自汽水音乐直接适配源"] : Array(lyrics.prefix(4)),
            isPlaying: bool(player?["isPlaying"]),
            progress: progress,
            sourceName: sourceName
        )
    }

    private func progressRatio(player: [String: Any]?, track: [String: Any]) -> Double {
        guard let player else { return 0 }
        let progressSeconds = double(player["progressSeconds"]) ?? 0
        let durationSeconds = double(player["durationSeconds"])
            ?? double(track["duration"]).map { $0 / 1000 }
            ?? 0
        guard durationSeconds > 0 else { return 0 }
        return min(max(progressSeconds / durationSeconds, 0), 1)
    }

    private func summarizeQueueCache(_ json: Any?) -> (trackCount: Int, examples: [String]) {
        guard let dictionary = json as? [String: Any] else { return (0, []) }

        var trackCount = 0
        var examples: [String] = []
        for key in dictionary.keys.sorted() {
            guard let queue = dictionary[key] as? [String: Any] else { continue }
            if let playables = queue["playables"] as? [[String: Any]] {
                trackCount += playables.count
                examples.append(contentsOf: playables.prefix(3).compactMap { exampleLine(from: $0) })
            } else if let playables = queue["playables"] as? [String: Any] {
                trackCount += playables.count
                examples.append(contentsOf: playables.values.prefix(3).compactMap { $0 as? [String: Any] }.compactMap { exampleLine(from: $0) })
            }
        }
        return (trackCount, Array(examples.prefix(6)))
    }

    private func exampleLine(from playable: [String: Any]) -> String? {
        let track = (playable["track"] as? [String: Any]) ?? playable
        guard let name = string(playable["name"]) ?? string(track["name"]) else { return nil }
        let artists = artistNames(from: playable) ?? artistNames(from: track) ?? "未知艺人"
        return "\(name) - \(artists)"
    }

    private func desktopLyricsEnabled(in json: Any?) -> Bool? {
        guard let dictionary = json as? [String: Any],
              let desktopLyrics = dictionary["desktopLyrics"] as? [String: Any] else {
            return nil
        }
        return bool(desktopLyrics["enabled"])
    }

    private func artistNames(from dictionary: [String: Any]) -> String? {
        guard let artists = dictionary["artists"] as? [[String: Any]] else { return nil }
        let names = artists.compactMap { string($0["name"]) }
        return names.isEmpty ? nil : names.joined(separator: "/")
    }

    private func artworkURL(from dictionary: [String: Any]) -> URL? {
        if let url = imageURL(from: dictionary["cover_url"] as? [String: Any]) {
            return url
        }
        if let album = dictionary["album"] as? [String: Any],
           let url = imageURL(from: album["url_cover"] as? [String: Any]) {
            return url
        }
        if let url = imageURL(from: dictionary["url_cover"] as? [String: Any]) {
            return url
        }
        return nil
    }

    private func imagePrefixes(in lunaFiles: [String: Any]) -> [String] {
        var prefixes: [String] = []
        var seen = Set<String>()

        func add(_ value: String) {
            guard value.hasPrefix("https://"),
                  value.contains("douyinpic.com/img") else {
                return
            }
            guard !seen.contains(value) else { return }
            seen.insert(value)
            prefixes.append(value)
        }

        func walk(_ value: Any, depth: Int) {
            guard depth <= 8, prefixes.count < 8 else { return }
            if let string = value as? String {
                add(string)
            } else if let array = value as? [Any] {
                for item in array.prefix(80) {
                    walk(item, depth: depth + 1)
                }
            } else if let dictionary = value as? [String: Any] {
                for key in dictionary.keys.sorted() {
                    walk(dictionary[key] as Any, depth: depth + 1)
                }
            }
        }

        for key in lunaFiles.keys.sorted() {
            walk(lunaFiles[key] as Any, depth: 0)
        }
        return prefixes
    }

    private func imageURL(from descriptor: [String: Any]?) -> URL? {
        guard let descriptor,
              let uri = string(descriptor["uri"]),
              let prefixes = descriptor["urls"] as? [String],
              let prefix = prefixes.first else {
            return nil
        }
        return URL(string: prefix + uri)
    }

    private func lyricLines(from value: Any?) -> [String] {
        guard let lyrics = value as? [String: Any],
              let content = string(lyrics["content"]) else {
            return []
        }

        return content
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: #"\[[^\]]+\]"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private func decodeLunaJSON(_ url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url), data.count > 4 else { return nil }
        guard String(data: data.prefix(4), encoding: .utf8) == "LUNA" else { return nil }
        guard let decompressed = gzipDecompress(Data(data.dropFirst(4))) else { return nil }
        return try? JSONSerialization.jsonObject(with: decompressed)
    }

    private func gzipDecompress(_ data: Data) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-dc"]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            input.fileHandleForWriting.write(data)
            try? input.fileHandleForWriting.close()
            let result = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return result
        } catch {
            return nil
        }
    }

    private func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            if value == "true" || value == "1" { return true }
            if value == "false" || value == "0" { return false }
        }
        return nil
    }

    private func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Float { return Double(value) }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}
