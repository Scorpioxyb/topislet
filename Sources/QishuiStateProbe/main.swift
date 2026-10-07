import Foundation
import MusicUsageDiagnostics

struct FileSnapshot: Equatable {
    let size: UInt64
    let modifiedAt: TimeInterval
}

struct ProbeConfig {
    let root: URL
    let watchSeconds: Int?
    let interval: TimeInterval
}

let home = FileManager.default.homeDirectoryForCurrentUser
let defaultRoot = home
    .appendingPathComponent("Library/Containers/com.soda.music/Data/Library/Application Support/SodaMusic")

let args = CommandLine.arguments
let watchSeconds: Int? = {
    guard let index = args.firstIndex(of: "--watch"), args.indices.contains(index + 1) else { return nil }
    return Int(args[index + 1])
}()
let interval: TimeInterval = {
    guard let index = args.firstIndex(of: "--interval-ms"),
          args.indices.contains(index + 1),
          let milliseconds = Double(args[index + 1]) else {
        return 1.0
    }
    return max(milliseconds / 1_000, 0.01)
}()

let config = ProbeConfig(root: defaultRoot, watchSeconds: watchSeconds, interval: interval)
let probe = QishuiStateProbe(config: config)

if let watchSeconds {
    probe.watch(seconds: watchSeconds)
} else {
    probe.printSummary()
}

final class QishuiStateProbe {
    private let config: ProbeConfig
    private let fileManager = FileManager.default

    private var watchedRoots: [URL] {
        [
            config.root.appendingPathComponent("LunaStorage"),
            config.root.appendingPathComponent("Local Storage/leveldb"),
            config.root.appendingPathComponent("Session Storage"),
            config.root.appendingPathComponent("IndexedDB/app_resources_0.indexeddb.leveldb"),
            config.root.appendingPathComponent("LunaCacheV2")
        ]
    }

    init(config: ProbeConfig) {
        self.config = config
    }

    func printSummary() {
        print("QishuiStateProbe")
        let safeRoot = QishuiProbePrivacy.rootDescription(
            root: config.root,
            home: home
        )
        print("root=\(safeRoot)")
        print("mode=summary")
        print("")
        printLunaStorageSummary()
        print("")
        printSnapshotSummary(snapshotFiles())
    }

    func watch(seconds: Int) {
        print("QishuiStateProbe")
        let safeRoot = QishuiProbePrivacy.rootDescription(
            root: config.root,
            home: home
        )
        print("root=\(safeRoot)")
        print("mode=watch")
        print("seconds=\(seconds)")
        print("intervalMilliseconds=\(Int(config.interval * 1_000))")
        print("hint=播放/暂停/切歌时观察 changed 文件；本工具只读汽水目录，不打开控制中心。")
        print("")

        var previous = snapshotFiles()
        printSnapshotSummary(previous)

        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while Date() < deadline {
            Thread.sleep(forTimeInterval: config.interval)
            let current = snapshotFiles()
            let changes = diff(old: previous, new: current)
            if !changes.isEmpty {
                print("")
                print("CHANGES \(isoTimestamp())")
                for change in changes.prefix(30) {
                    print(change.summary(relativeTo: config.root))
                    inspectChangedFile(change.url)
                }
                if changes.count > 30 {
                    print("- truncatedChanges=\(changes.count - 30)")
                }
            }
            previous = current
        }
    }

    private func printLunaStorageSummary() {
        let luna = config.root.appendingPathComponent("LunaStorage")
        print("LUNA_STORAGE")
        guard let files = try? fileManager.contentsOfDirectory(at: luna, includingPropertiesForKeys: nil) else {
            print("- bucket=LunaStorage unavailable=1")
            return
        }

        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            print("- \(QishuiProbePrivacy.fileDescription(url: file, relativeTo: config.root))")
            guard let json = decodeLunaJSON(file) else {
                print("  decode=unavailable")
                continue
            }
            printJSONSummary(json, indent: "  ")
        }
    }

    private func printSnapshotSummary(_ snapshot: [URL: FileSnapshot]) {
        print("WATCHED_FILES")
        print("- count=\(snapshot.count)")
        for root in watchedRoots {
            let count = snapshot.keys.filter { $0.path.hasPrefix(root.path) }.count
            print("- \(root.lastPathComponent)=\(count)")
        }
    }

    private func snapshotFiles() -> [URL: FileSnapshot] {
        var result: [URL: FileSnapshot] = [:]
        for root in watchedRoots where fileManager.fileExists(atPath: root.path) {
            if isDirectory(root) {
                guard let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for case let url as URL in enumerator {
                    guard isRegularFile(url), shouldWatch(url) else { continue }
                    if let snapshot = snapshot(for: url) {
                        result[url] = snapshot
                    }
                }
            } else if let snapshot = snapshot(for: root) {
                result[root] = snapshot
            }
        }
        return result
    }

    private func shouldWatch(_ url: URL) -> Bool {
        let path = url.path
        if path.contains("/LunaCacheV2/") {
            let name = url.lastPathComponent
            return name == "entries.db"
                || name == "info.db"
                || name == "access.db"
                || name.hasSuffix(".bin")
        }
        return true
    }

    private func snapshot(for url: URL) -> FileSnapshot? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modifiedAt = values.contentModificationDate?.timeIntervalSince1970 else {
            return nil
        }
        return FileSnapshot(size: UInt64(values.fileSize ?? 0), modifiedAt: modifiedAt)
    }

    private func diff(old: [URL: FileSnapshot], new: [URL: FileSnapshot]) -> [FileChange] {
        let all = Set(old.keys).union(new.keys)
        return all.compactMap { url in
            let before = old[url]
            let after = new[url]
            guard before != after else { return nil }
            return FileChange(url: url, before: before, after: after)
        }
        .sorted { lhs, rhs in
            (lhs.after?.modifiedAt ?? lhs.before?.modifiedAt ?? 0) > (rhs.after?.modifiedAt ?? rhs.before?.modifiedAt ?? 0)
        }
    }

    private func inspectChangedFile(_ url: URL) {
        if url.path.contains("/LunaStorage/"), let json = decodeLunaJSON(url) {
            printJSONSummary(json, indent: "  ")
            return
        }

        let interesting = interestingPatternCounts(in: url)
        guard !interesting.isEmpty else { return }
        for key in interesting.keys.sorted() {
            print("  matchedPattern=\(key) count=\(interesting[key] ?? 0)")
        }
    }

    private func decodeLunaJSON(_ url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url), data.count > 4 else { return nil }
        let magic = String(data: data.prefix(4), encoding: .utf8)
        guard magic == "LUNA" else { return nil }
        let compressed = data.dropFirst(4)
        guard let decompressed = gzipDecompress(Data(compressed)) else { return nil }
        return try? JSONSerialization.jsonObject(with: decompressed)
    }

    private func gzipDecompress(_ data: Data) -> Data? {
        let tempDirectory = fileManager.temporaryDirectory
        let token = UUID().uuidString
        let inputURL = tempDirectory.appendingPathComponent("qishui-\(token).gz")
        let outputURL = tempDirectory.appendingPathComponent("qishui-\(token).json")
        defer {
            try? fileManager.removeItem(at: inputURL)
            try? fileManager.removeItem(at: outputURL)
        }

        do {
            try data.write(to: inputURL)
            fileManager.createFile(atPath: outputURL.path, contents: nil)
        } catch {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-dc", inputURL.path]

        guard let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            return nil
        }
        let error = Pipe()
        process.standardOutput = outputHandle
        process.standardError = error

        do {
            try process.run()
            process.waitUntilExit()
            try? outputHandle.close()
            guard process.terminationStatus == 0 else { return nil }
            return try Data(contentsOf: outputURL)
        } catch {
            return nil
        }
    }

    private func printJSONSummary(_ json: Any, indent: String) {
        if let dictionary = json as? [String: Any] {
            let keys = Set(dictionary.keys.map(QishuiProbePrivacy.keyLabel)).sorted()
            print("\(indent)keys=\(keys.prefix(18).joined(separator: ","))\(keys.count > 18 ? ",..." : "")")
            let candidates = collectCandidateFields(json)
            for candidate in candidates.prefix(14) {
                print("\(indent)\(candidate)")
            }
            if candidates.count > 14 {
                print("\(indent)truncatedCandidates=\(candidates.count - 14)")
            }
            if let queueSummary = summarizeQueueCache(dictionary) {
                for line in queueSummary {
                    print("\(indent)\(line)")
                }
            }
        } else {
            print("\(indent)jsonType=\(type(of: json))")
        }
    }

    private func collectCandidateFields(_ json: Any) -> [String] {
        let keywords = [
            "current", "playing", "player", "queue", "media", "track",
            "lyric", "cover", "progress", "duration", "playable", "isPlaying"
        ]
        var results: [String] = []

        func walk(_ value: Any, path: String, depth: Int) {
            guard depth <= 7, results.count < 80 else { return }
            if let dictionary = value as? [String: Any] {
                for key in dictionary.keys.sorted() {
                    let childPath = path.isEmpty ? key : "\(path).\(key)"
                    let child = dictionary[key] as Any
                    if keywords.contains(where: { key.localizedCaseInsensitiveContains($0) }) {
                        if !(child is [String: Any]) && !(child is [Any]) {
                            results.append("candidateField=\(QishuiProbePrivacy.candidateFieldLabel(for: key)) type=\(scalarType(child))")
                        }
                    }
                    walk(child, path: childPath, depth: depth + 1)
                }
            } else if let array = value as? [Any] {
                for (index, child) in array.prefix(8).enumerated() {
                    walk(child, path: "\(path)[\(index)]", depth: depth + 1)
                }
            }
        }

        walk(json, path: "", depth: 0)
        return results
    }

    private func summarizeQueueCache(_ dictionary: [String: Any]) -> [String]? {
        var lines: [String] = []
        var trackCount = 0
        var completeArtistCount = 0
        var completeAlbumCount = 0
        var completeDurationCount = 0
        var completeArtworkReferenceCount = 0
        var currentPointerCount = 0

        for key in dictionary.keys.sorted() {
            guard let queue = dictionary[key] as? [String: Any],
                  let playables = queue["playables"] as? [[String: Any]] else {
                continue
            }
            if queue["currentPlayableKey"] != nil {
                currentPointerCount += 1
            }
            trackCount += playables.count
            for playable in playables {
                guard let track = playable["track"] as? [String: Any] else { continue }
                let artists = (track["artists"] as? [[String: Any]])?
                    .compactMap { $0["name"] as? String } ?? []
                if !artists.isEmpty { completeArtistCount += 1 }
                if containsNonEmptyValue(in: track, matching: ["album", "album_name"]) {
                    completeAlbumCount += 1
                }
                if containsNumericValue(in: track, matching: ["duration", "duration_ms"]) {
                    completeDurationCount += 1
                }
                if containsNonEmptyValue(
                    in: track,
                    matching: ["cover", "cover_url", "url_cover", "image", "uri"]
                ) {
                    completeArtworkReferenceCount += 1
                }
            }
        }

        guard trackCount > 0 else { return nil }
        lines.append("queueTrackCount=\(trackCount)")
        lines.append("queueCurrentPointerCount=\(currentPointerCount)")
        lines.append("tracksWithArtist=\(completeArtistCount)")
        lines.append("tracksWithAlbum=\(completeAlbumCount)")
        lines.append("tracksWithDuration=\(completeDurationCount)")
        lines.append("tracksWithArtworkReference=\(completeArtworkReferenceCount)")
        return lines
    }

    private func interestingPatternCounts(in url: URL) -> [String: Int] {
        guard let snapshot = snapshot(for: url), snapshot.size <= 25_000_000 else { return [:] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/strings")
        process.arguments = ["-a", url.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [:] }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            let patterns = [
                "currentPlayableKey", "isPlaying", "mediaDetail", "lyrics",
                "queue", "player", "playable", "url_cover", "cover_url",
                "track", "artist", "duration", "progress"
            ]
            var counts: [String: Int] = [:]
            for line in text.split(separator: "\n") {
                for pattern in patterns where line.localizedCaseInsensitiveContains(pattern) {
                    counts[pattern, default: 0] += 1
                }
            }
            return counts
        } catch {
            return [:]
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
    }

    private func containsNonEmptyValue(
        in value: Any,
        matching keys: Set<String>,
        depth: Int = 0
    ) -> Bool {
        guard depth <= 6 else { return false }
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                if keys.contains(key.lowercased()), !isEmptyScalar(child) {
                    return true
                }
                if containsNonEmptyValue(in: child, matching: keys, depth: depth + 1) {
                    return true
                }
            }
        } else if let array = value as? [Any] {
            return array.contains { containsNonEmptyValue(in: $0, matching: keys, depth: depth + 1) }
        }
        return false
    }

    private func containsNumericValue(
        in value: Any,
        matching keys: Set<String>,
        depth: Int = 0
    ) -> Bool {
        guard depth <= 6 else { return false }
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                if keys.contains(key.lowercased()), child is NSNumber {
                    return true
                }
                if containsNumericValue(in: child, matching: keys, depth: depth + 1) {
                    return true
                }
            }
        } else if let array = value as? [Any] {
            return array.contains { containsNumericValue(in: $0, matching: keys, depth: depth + 1) }
        }
        return false
    }

    private func isEmptyScalar(_ value: Any) -> Bool {
        if value is NSNull { return true }
        if let string = value as? String { return string.isEmpty }
        return false
    }

    private func scalarType(_ value: Any) -> String {
        switch value {
        case is NSNull:
            return "null"
        case is Bool:
            return "bool"
        case is NSNumber:
            return "number"
        case is String:
            return "string"
        default:
            return "other"
        }
    }

    private func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

struct FileChange {
    let url: URL
    let before: FileSnapshot?
    let after: FileSnapshot?

    func summary(relativeTo root: URL) -> String {
        let file = QishuiProbePrivacy.fileDescription(url: url, relativeTo: root)
        switch (before, after) {
        case (nil, let after?):
            return "- created \(file) size=\(after.size)"
        case (let before?, nil):
            return "- deleted \(file) oldSize=\(before.size)"
        case (let before?, let after?):
            return "- changed \(file) size=\(before.size)->\(after.size)"
        default:
            return "- changed \(file)"
        }
    }
}
