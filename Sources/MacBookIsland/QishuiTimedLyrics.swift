import Foundation

struct QishuiTimedWord: Equatable, Sendable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

struct QishuiTimedLine: Equatable, Sendable {
    let text: String
    let words: [QishuiTimedWord]
}

/// Session-only cache of successful, identity-verified corpora. A different
/// duration never reuses another recording's timestamps, even with equal names.
struct QishuiTimedLyricCache {
    private struct Key: Hashable {
        let title: String
        let artist: String
        let duration: TimeInterval
    }

    private let capacity: Int
    private var entries: [Key: [QishuiTimedLine]] = [:]
    private var recency: [Key] = []

    init(capacity: Int = 24) { self.capacity = max(1, capacity) }

    mutating func lines(title: String, artist: String, duration: TimeInterval) -> [QishuiTimedLine]? {
        let key = Key(title: title, artist: artist, duration: duration)
        guard let lines = entries[key] else { return nil }
        recency.removeAll { $0 == key }
        recency.append(key)
        return lines
    }

    mutating func insert(_ lines: [QishuiTimedLine], title: String, artist: String, duration: TimeInterval) {
        guard !lines.isEmpty, duration.isFinite, duration > 0 else { return }
        let key = Key(title: title, artist: artist, duration: duration)
        entries[key] = lines
        recency.removeAll { $0 == key }
        recency.append(key)
        if recency.count > capacity {
            entries.removeValue(forKey: recency.removeFirst())
        }
    }
}

enum QishuiTimedLyricRetryPolicy {
    static func interval(failureCount: Int) -> TimeInterval {
        guard failureCount > 0 else { return 0 }
        return min(3 * pow(2, Double(min(failureCount - 1, 4))), 30)
    }
}

enum QishuiTimedArtistPolicy {
    static func matches(_ expected: String, _ candidate: String) -> Bool {
        guard !canonical(expected).isEmpty else { return false }
        if canonical(expected) == canonical(candidate) { return true }
        // MediaRemote separates credits with comma-space. Only interpret the
        // provider's slash as a separator for an explicitly multi-artist input;
        // a single artist such as AC/DC must remain an indivisible name.
        let expectedNames = names(expected.components(separatedBy: ", "))
        guard expectedNames.count > 1 else { return false }
        return expectedNames == names(candidate.replacingOccurrences(of: "/", with: ", ").components(separatedBy: ", "))
    }

    static func matches(_ expected: String, _ candidates: [String]) -> Bool {
        let expectedNames = names(expected.components(separatedBy: ", "))
        return !expectedNames.isEmpty && expectedNames == names(candidates)
    }

    private static func names(_ values: [String]) -> Set<String> {
        Set(values.map(canonical).filter { !$0.isEmpty })
    }

    private static func canonical(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum QishuiTimedLyricParser {
    static func upcomingFirstLine(at position: TimeInterval, in lines: [QishuiTimedLine]) -> QishuiTimedLine? {
        guard let first = lines.first,
              let start = first.words.first?.start,
              position >= 0,
              position + 0.12 < start else { return nil }
        return first
    }

    static func parse(_ content: String) -> [QishuiTimedLine] {
        let linePattern = try! NSRegularExpression(pattern: #"^\[(\d+),(\d+)\](.*)$"#)
        let wordPattern = try! NSRegularExpression(pattern: #"<(\d+),(\d+),\d+>([^<]*)"#)
        return content.split(separator: "\n").compactMap { raw in
            let line = String(raw)
            let ns = line as NSString
            guard let header = linePattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                  let lineStart = Double(ns.substring(with: header.range(at: 1))) else { return nil }
            let body = ns.substring(with: header.range(at: 3))
            let bodyNS = body as NSString
            let words = wordPattern.matches(in: body, range: NSRange(location: 0, length: bodyNS.length)).compactMap { match -> QishuiTimedWord? in
                guard let offset = Double(bodyNS.substring(with: match.range(at: 1))),
                      let duration = Double(bodyNS.substring(with: match.range(at: 2))) else { return nil }
                let text = bodyNS.substring(with: match.range(at: 3))
                guard !text.isEmpty else { return nil }
                let start = (lineStart + offset) / 1000
                return QishuiTimedWord(text: text, start: start, end: start + duration / 1000)
            }
            guard !words.isEmpty else { return nil }
            return QishuiTimedLine(text: words.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines), words: words)
        }
    }

    static func words(
        for currentLine: String,
        at position: TimeInterval?,
        in lines: [QishuiTimedLine],
        trackDuration: TimeInterval? = nil
    ) -> [QishuiTimedWord] {
        let key = normalized(currentLine)
        guard !key.isEmpty else { return [] }
        if let position,
           let active = activeLine(at: position, in: lines, trackDuration: trackDuration) {
            // Use the same sentence lifetime as display, including instrumental
            // gaps. Repeated chorus text must bind to its active occurrence.
            return normalized(active.current.text) == key ? active.current.words : []
        }
        let matches = lines.filter { normalized($0.text) == key }
        if matches.count == 1 { return matches[0].words }
        return []
    }

    static func activeLine(
        at position: TimeInterval,
        in lines: [QishuiTimedLine],
        trackDuration: TimeInterval? = nil
    ) -> (current: QishuiTimedLine, next: QishuiTimedLine?)? {
        guard let index = lines.lastIndex(where: { ($0.words.first?.start ?? .infinity) <= position + 0.12 }),
              let lastWord = lines[index].words.last else { return nil }
        let holdsFinalLine = index == lines.count - 1
            && trackDuration.map { position <= $0 + 0.25 } == true
        // Keep the last verified sentence through an instrumental gap. The
        // next sentence replaces it at its own timestamp; clearing it after
        // 0.9 s made the lyric card repeatedly collapse between lines.
        guard holdsFinalLine || index < lines.count - 1 || position <= lastWord.end + 0.9 else { return nil }
        let next = lines.indices.contains(index + 1) ? lines[index + 1] : nil
        return (lines[index], next)
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }
}

/// Optional network supplement. Search sends only the current title and artist
/// to the lyric provider. Both search and detail must agree with MediaRemote.
struct QishuiTimedLyricSource {
    private let readData: @Sendable (URL) async -> Data?

    init(readData: (@Sendable (URL) async -> Data?)? = nil) {
        self.readData = readData ?? { await Self.read($0) }
    }

    func fetch(title: String, artist: String, duration: TimeInterval) async -> [QishuiTimedLine] {
        guard !title.isEmpty, !artist.isEmpty, duration.isFinite, duration > 0 else { return [] }
        var search = URLComponents(string: "https://api-vehicle.volcengine.com/v2/search/type")!
        search.queryItems = [
            .init(name: "keyword", value: "\(title) \(artist)"),
            .init(name: "search_type", value: "music"),
            .init(name: "limit", value: "20"),
            .init(name: "real_offset", value: "0"),
            .init(name: "search_source", value: "qishui"),
            .init(name: "aid", value: "386088")
        ]
        guard !Task.isCancelled,
              let searchURL = search.url,
              let data = await readData(searchURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let body = json["data"] as? [String: Any],
              let candidates = body["list"] as? [[String: Any]] else { return [] }
        let matches = candidates.filter { item in
            guard let foundTitle = item["title"] as? String,
                  let author = item["author_info"] as? [String: Any],
                  let foundArtist = author["name"] as? String,
                  let seconds = item["duration"] as? Double else { return false }
            return canonical(foundTitle) == canonical(title)
                && QishuiTimedArtistPolicy.matches(artist, foundArtist)
                && abs(seconds - duration) <= 3
        }
        let ordered = matches.sorted {
            abs(($0["duration"] as? Double ?? 0) - duration)
                < abs(($1["duration"] as? Double ?? 0) - duration)
        }
        guard !Task.isCancelled,
              let best = ordered.first,
              ordered.count == 1 || abs((ordered[1]["duration"] as? Double ?? 0) - duration)
                - abs((best["duration"] as? Double ?? 0) - duration) >= 1,
              let trackID = best["item_id"] as? String,
              trackID.range(of: #"^\d{10,22}$"#, options: .regularExpression) != nil,
              let detailURL = URL(string: "https://beta-luna.douyin.com/luna/h5/seo_track?track_id=\(trackID)&device_platform=web"),
              let detailData = await readData(detailURL),
              let detail = (try? JSONSerialization.jsonObject(with: detailData)) as? [String: Any],
              let seo = detail["seo_track"] as? [String: Any],
              let verifiedTrack = seo["track"] as? [String: Any],
              let verifiedTitle = verifiedTrack["name"] as? String,
              let verifiedArtists = verifiedTrack["artists"] as? [[String: Any]],
              let verifiedDuration = verifiedTrack["duration"] as? Double,
              canonical(verifiedTitle) == canonical(title),
              QishuiTimedArtistPolicy.matches(artist, verifiedArtists.compactMap { $0["name"] as? String }),
              abs(verifiedDuration / 1000 - duration) <= 3,
              let lyric = detail["lyric"] as? [String: Any],
              let content = lyric["content"] as? String else { return [] }
        guard !Task.isCancelled else { return [] }
        return QishuiTimedLyricParser.parse(content)
    }

    private static func read(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 2_000_000 else { return nil }
        return data
    }

    private func canonical(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
