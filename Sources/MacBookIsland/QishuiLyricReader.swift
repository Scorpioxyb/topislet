import AppKit
import ApplicationServices
import Foundation

struct QishuiLyricIdentity: Equatable, Sendable {
    let processIdentifier: pid_t
    let title: String
    let artist: String
}

enum QishuiLyricIdentityPolicy {
    static func select(
        media: QishuiLyricIdentity?,
        direct: QishuiLyricIdentity?,
        runningProcesses: Set<pid_t>
    ) -> QishuiLyricIdentity? {
        if let media, runningProcesses.contains(media.processIdentifier) { return media }
        if let direct, runningProcesses.contains(direct.processIdentifier) { return direct }
        return nil
    }
}

struct QishuiLyricSnapshot: Equatable, Sendable {
    let identity: QishuiLyricIdentity
    let lines: [String]
    // Desktop rows can be current/next, previous/current, or a translation.
    // Preserve the source's visible rows without labelling the second as next.
    let isDesktopSnapshot: Bool
    let checkedAt: Date
}

enum QishuiLyricAttribution {
    static func normalize(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func matches(_ identity: QishuiLyricIdentity, title: String, artists: [String]) -> Bool {
        normalize(identity.title) == normalize(title)
            && normalizeArtist(identity.artist) == normalizeArtist(artists.joined(separator: ", "))
    }

    private static func normalizeArtist(_ value: String) -> String {
        value
            .split { ",，/、&".contains($0) }
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: ",")
    }

    static func acceptsDesktop(_ lines: [String], corpus: Set<String>) -> Bool {
        !lines.isEmpty && lines.count <= 2
            && lines.allSatisfy { corpus.contains(normalize($0)) }
    }
}

enum QishuiVerifiedActiveLyricPolicy {
    static func currentLines(activeParagraphs: [[String]], corpus: Set<String>) -> [String]? {
        guard activeParagraphs.count == 1 else { return nil }
        let rawLines = MusicLyricPresentation.clean(activeParagraphs[0])
        // The player wraps a long original lyric into multiple AX `line`
        // nodes before exposing the translation. Validate each raw fragment
        // against the verified corpus, then fold adjacent same-language
        // fragments back into the one visible lyric pair.
        guard !rawLines.isEmpty,
              rawLines.count <= 4,
              rawLines.allSatisfy({ corpus.contains(QishuiLyricAttribution.normalize($0)) }) else {
            return nil
        }
        var folded: [String] = []
        for line in rawLines {
            guard let previous = folded.last else {
                folded.append(line)
                continue
            }
            if containsCJK(previous) == containsCJK(line) {
                folded[folded.count - 1] = join(previous, line)
            } else {
                folded.append(line)
            }
        }
        guard folded.count <= 2 else { return nil }
        return folded
    }

    static func paragraphLines(_ paragraph: [String], corpus: Set<String>) -> [String]? {
        let rawLines = MusicLyricPresentation.clean(paragraph)
        guard !rawLines.isEmpty,
              rawLines.count <= 4,
              rawLines.allSatisfy({ corpus.contains(QishuiLyricAttribution.normalize($0)) }) else {
            return nil
        }

        var folded: [String] = []
        for line in rawLines {
            guard let previous = folded.last else {
                folded.append(line)
                continue
            }
            if containsCJK(previous) == containsCJK(line) {
                folded[folded.count - 1] = join(previous, line)
            } else {
                folded.append(line)
            }
        }
        guard folded.count <= 2 else { return nil }
        return folded
    }

    private static func join(_ lhs: String, _ rhs: String) -> String {
        containsCJK(lhs) || containsCJK(rhs) ? lhs + rhs : lhs + " " + rhs
    }

    private static func containsCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }
}

enum QishuiLyricDiscoveryPolicy {
    static let retryInterval: TimeInterval = 3

    static func shouldDiscoverParagraphs(paragraphCount: Int, lastAttemptAt: Date, now: Date) -> Bool {
        paragraphCount == 0 && now.timeIntervalSince(lastAttemptAt) >= retryInterval
    }
}

enum QishuiLyricRefreshPolicy {
    static func interval(hasVerifiedTimeline: Bool) -> TimeInterval {
        hasVerifiedTimeline ? 2 : 0.18
    }

    static func acceptedSnapshot(
        _ snapshot: QishuiLyricSnapshot,
        previous: QishuiLyricSnapshot?,
        now: Date
    ) -> QishuiLyricSnapshot {
        guard snapshot.lines.isEmpty,
              let previous,
              previous.identity == snapshot.identity,
              !previous.lines.isEmpty,
              QishuiLyricFreshnessPolicy.accepts(checkedAt: previous.checkedAt, now: now) else {
            return snapshot
        }
        // A transient AX miss must not erase a fresh row or renew stale words.
        return previous
    }
}

enum QishuiLyricFreshnessPolicy {
    // Keep a verified row only across a few missed AX frames. A longer grace
    // period leaves already-sung words visible after the source advances.
    static let maximumAge: TimeInterval = 0.72

    static func accepts(checkedAt: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(checkedAt)
        return age >= 0 && age <= maximumAge
    }
}

/// The desktop lyric window belongs to Soda's own process but does not expose
/// a track title. Require two matching reads when first attaching or after a
/// track change; once attached, publish its changing current row immediately.
struct QishuiDesktopLyricGate {
    private var identity: QishuiLyricIdentity?
    private var previousLines: [String] = []
    private var candidate: [String] = []
    private var attached = false

    mutating func accept(_ lines: [String], identity requested: QishuiLyricIdentity) -> Bool {
        guard !lines.isEmpty else { return false }
        if identity != requested {
            previousLines = candidate
            identity = requested
            candidate = []
            attached = false
        }
        if attached {
            candidate = lines
            return true
        }
        guard lines != previousLines else { return false }
        if candidate == lines {
            attached = true
            return true
        }
        candidate = lines
        return false
    }
}

/// Title and lyric DOM can update in separate renderer frames. Reject the
/// previous song's corpus and require two complete, matching corpus reads.
struct QishuiLyricCorpusGate {
    private var previous: Set<String> = []
    private var pending: Set<String>?
    private(set) var verified: Set<String> = []

    mutating func transition(sameProcess: Bool) {
        previous = sameProcess ? (verified.isEmpty ? previous : verified) : []
        pending = nil
        verified = []
    }

    mutating func accept(_ candidate: Set<String>) -> Bool {
        guard !candidate.isEmpty, candidate != previous else { pending = nil; return false }
        guard pending == candidate else { pending = candidate; return false }
        verified = candidate
        return true
    }
}

/// Read-only, queue-confined supplement. Never sets AX attributes, opens windows,
/// reads URLs, requests permission, or substitutes a guessed lyric time axis.
final class QishuiLyricReader: @unchecked Sendable {
    private let debugEnabled = ProcessInfo.processInfo.environment["TOPISLET_QISHUI_LYRIC_DEBUG"] == "1"
    private var identity: QishuiLyricIdentity?
    private var player: AXUIElement?
    private var titleRoot: AXUIElement?
    private var artistsRoot: AXUIElement?
    private var lyricsRoot: AXUIElement?
    private var desktopWindow: AXUIElement?
    private var desktopLyricsRoot: AXUIElement?
    private var desktopParagraphs: [AXUIElement] = []
    private var corpus = Set<String>()
    private var paragraphs: [AXUIElement] = []
    private var corpusGate = QishuiLyricCorpusGate()
    private var desktopGate = QishuiDesktopLyricGate()
    // AX renderer updates can replace the paragraph nodes for one or two
    // frames. Keep the last verified line for the bounded freshness window
    // instead of publishing an empty snapshot and visibly collapsing the
    // island back to title/artist. The identity gate remains unchanged.
    private var lastGoodSnapshot: QishuiLyricSnapshot?
    private var lastDiscovery = Date.distantPast
    private var lastParagraphDiscovery = Date.distantPast
    private var lastDesktopParagraphDiscovery = Date.distantPast
    private var deadline = Date.distantPast
    private var exhausted = false
    private var nodes = 0

    func read(identity requested: QishuiLyricIdentity) -> QishuiLyricSnapshot {
        let now = Date()
        deadline = now.addingTimeInterval(0.18)
        exhausted = false
        nodes = 0
        if identity != requested {
            corpusGate.transition(sameProcess: identity?.processIdentifier == requested.processIdentifier)
            identity = requested
            player = nil
            titleRoot = nil
            artistsRoot = nil
            lyricsRoot = nil
            desktopWindow = nil
            desktopLyricsRoot = nil
            desktopParagraphs = []
            corpus = []
            paragraphs = []
            lastGoodSnapshot = nil
            lastDiscovery = .distantPast
            lastParagraphDiscovery = .distantPast
            lastDesktopParagraphDiscovery = .distantPast
        }
        func result(_ lines: [String] = [], desktop: Bool = false) -> QishuiLyricSnapshot {
            if !exhausted, !lines.isEmpty {
                let snapshot = QishuiLyricSnapshot(
                    identity: requested,
                    lines: lines,
                    isDesktopSnapshot: desktop,
                    checkedAt: now
                )
                lastGoodSnapshot = snapshot
                return snapshot
            }

            if let lastGoodSnapshot,
               lastGoodSnapshot.identity == requested,
               QishuiLyricFreshnessPolicy.accepts(
                   checkedAt: lastGoodSnapshot.checkedAt,
                   now: now
               ) {
                return lastGoodSnapshot
            }

            return QishuiLyricSnapshot(
                identity: requested,
                lines: [],
                isDesktopSnapshot: false,
                checkedAt: now
            )
        }
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication(processIdentifier: requested.processIdentifier),
              !app.isTerminated, app.bundleIdentifier == "com.soda.music" else { return result() }
        let root = AXUIElementCreateApplication(requested.processIdentifier)
        let windows = children(root, attribute: "AXWindows")
        let lyricWindows = windows.filter { string($0, "AXTitle") == "桌面歌词" }
        desktopWindow = lyricWindows.count == 1 ? lyricWindows[0] : nil
        if desktopWindow == nil {
            desktopLyricsRoot = nil
            desktopParagraphs = []
        }
        let mainWindows = windows.filter { string($0, "AXTitle") == "汽水音乐" }
        // Chromium can expose a stale AXWindows entry while the focused
        // window still owns the live renderer tree. Prefer that focused
        // window when it is the Soda Music window; this is required for
        // background playback where the AXWindows subtree is empty.
        let focusedWindow: AXUIElement? = attribute(root, "AXFocusedWindow").flatMap { value in
            guard CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
            let element = value as! AXUIElement
            return string(element, "AXTitle") == "汽水音乐" ? element : nil
        }
        let mainWindow = focusedWindow ?? (mainWindows.count == 1 ? mainWindows[0] : nil)
        debugLog("windows=\(windows.count) lyricWindows=\(lyricWindows.count) mainWindows=\(mainWindows.count) focusedMain=\(focusedWindow != nil)")
        // Chromium's background AX tree can omit AXMinimized while the window
        // remains readable. Only an explicit `true` means the player is
        // minimized; treating nil as false is required for background audio.
        let canReadMain = mainWindow != nil
            && (mainWindow.flatMap { attribute($0, "AXMinimized") as? Bool } != true)
        let minimizedValue = mainWindow.map { attribute($0, "AXMinimized") }
        debugLog("canReadMain=\(canReadMain) minimized=\(String(describing: minimizedValue)) playerCached=\(player != nil)")
        if mainWindow == nil {
            player = nil
        } else if let mainWindow,
                  canReadMain,
                  now.timeIntervalSince(lastDiscovery) >= 3,
                  player == nil {
            lastDiscovery = now
            let matches = find(mainWindow) { self.classes($0).contains("fullscreen-player") }
            // During a renderer transition Soda can expose two fullscreen
            // player subtrees at once. Select the candidate whose title and
            // complete artist set match the already verified MediaRemote
            // identity; rejecting the whole window on node-count ambiguity
            // made lyrics disappear after an otherwise valid track change.
            let candidates = matches.isEmpty ? [mainWindow] : matches
            var selected: (player: AXUIElement, title: AXUIElement, artists: AXUIElement, lyrics: AXUIElement)?
            for candidate in candidates {
                let titles = find(candidate) { self.classes($0).contains("marquee") }
                let artistRoots = find(candidate) { self.classes($0).contains("artists") }
                let lyricRoots = find(candidate) { self.classes($0).contains("lyrics-view") }
                let candidateTitle = titles.first.map { texts($0).joined() } ?? ""
                let candidateArtists = artistRoots.first.map { root in
                    find(root) { self.classes($0).contains("artist-link") }
                        .map { texts($0).joined() }
                } ?? []
                debugLog("candidate classes=\(classes(candidate)) titles=\(titles.count) artists=\(artistRoots.count) lyrics=\(lyricRoots.count) title=\(candidateTitle) artists=\(candidateArtists)")
                guard let title = titles.first,
                      let artists = artistRoots.first,
                      let lyrics = lyricRoots.first,
                      QishuiLyricAttribution.matches(requested, title: candidateTitle, artists: candidateArtists) else {
                    continue
                }
                selected = (candidate, title, artists, lyrics)
                break
            }
            if let selected {
                player = selected.player
                titleRoot = selected.title
                artistsRoot = selected.artists
                lyricsRoot = selected.lyrics
            } else {
                player = nil
                titleRoot = nil
                artistsRoot = nil
                lyricsRoot = nil
            }
        }

        if canReadMain, player != nil {
            let title = titleRoot.map { texts($0).joined() } ?? ""
            let artists = artistsRoot.map { root in
                find(root) { self.classes($0).contains("artist-link") }
                    .map { texts($0).joined() }
            } ?? []
            debugLog("title=\(title) artists=\(artists)")
            if QishuiLyricAttribution.matches(requested, title: title, artists: artists) {
                if let lyricsRoot {
                    if QishuiLyricDiscoveryPolicy.shouldDiscoverParagraphs(
                        paragraphCount: paragraphs.count,
                        lastAttemptAt: lastParagraphDiscovery,
                        now: now
                    ) {
                        lastParagraphDiscovery = now
                        paragraphs = find(lyricsRoot) { self.classes($0).contains("paragraph") }
                    }
                    if !paragraphs.isEmpty, corpus.isEmpty {
                        let values = paragraphs.flatMap { MusicLyricPresentation.clean(self.texts($0)) }
                        // Do not retain a partial corpus after a timed-out traversal.
                        if !exhausted {
                            let candidate = Set(values.map(QishuiLyricAttribution.normalize))
                            if corpusGate.accept(candidate) { corpus = candidate }
                        } else {
                            paragraphs = []
                            lastParagraphDiscovery = now
                        }
                    }
                    var active = paragraphs.indices.filter {
                        let cls = self.classes(paragraphs[$0])
                        return cls.contains("active") && !cls.contains("disabled")
                    }
                    debugLog("paragraphs=\(paragraphs.count) corpus=\(corpus.count) active=\(active.count) exhausted=\(exhausted)")

                    // A renderer replacement can leave cached AX elements
                    // alive but no longer attached to the active paragraph.
                    // Rebuild immediately on an active miss; waiting for the
                    // old three-second discovery interval caused long visible
                    // gaps during normal lyric transitions.
                    if active.count != 1,
                       now.timeIntervalSince(lastParagraphDiscovery) >= 0.25 {
                        lastParagraphDiscovery = now
                        paragraphs = find(lyricsRoot) { self.classes($0).contains("paragraph") }
                        active = paragraphs.indices.filter {
                            let cls = self.classes(paragraphs[$0])
                            return cls.contains("active") && !cls.contains("disabled")
                        }
                    }
                    if active.count == 1, let index = active.first,
                       MusicLyricPresentation.isConfirmedInstrumental(texts(paragraphs[index])) {
                        return result(["纯音乐，请欣赏"])
                    }
                    if !corpus.isEmpty, active.count == 1, let index = active.first {
                        // A paragraph can contain original text and translation.
                        // Keep it together instead of assuming a second text is next.
                        if let lines = QishuiVerifiedActiveLyricPolicy.currentLines(
                            activeParagraphs: [texts(paragraphs[index])],
                            corpus: corpus
                        ) {
                            var publishedLines = lines
                            // The previous implementation published only the
                            // active paragraph. That made the expanded shelf
                            // look empty and prevented users from seeing the
                            // lyric sequence advance. Add exactly one adjacent
                            // paragraph when its complete original/translation
                            // pair is present in the same verified corpus.
                            let nextIndex = index + 1
                            if paragraphs.indices.contains(nextIndex),
                               let nextLines = QishuiVerifiedActiveLyricPolicy.paragraphLines(
                                   texts(paragraphs[nextIndex]),
                                   corpus: corpus
                               ),
                               !nextLines.isEmpty,
                               !nextLines.allSatisfy({ line in lines.contains(line) }) {
                                publishedLines.append(contentsOf: nextLines)
                            }
                            debugLog("active lines=\(publishedLines)")
                            return result(publishedLines)
                        }
                        debugLog("active rejected texts=\(texts(paragraphs[index]))")
                    }
                    if now.timeIntervalSince(lastDiscovery) >= 3 {
                        self.player = nil
                        paragraphs = []
                    }
                }
            } else {
                // Cached native element can survive a renderer replacement. Rediscover
                // at the bounded interval; never reuse another song's corpus.
                corpus = []
                paragraphs = []
                self.player = nil
            }
        }
        if let desktopWindow,
           (desktopParagraphs.isEmpty || now.timeIntervalSince(lastDesktopParagraphDiscovery) >= 1.5) {
            lastDesktopParagraphDiscovery = now
            let roots = find(desktopWindow) { self.classes($0).contains("lyrics") }
            desktopLyricsRoot = roots.count == 1 ? roots[0] : nil
            desktopParagraphs = desktopLyricsRoot.map { root in
                find(root) {
                    let cls = self.classes($0)
                    return cls.contains("paragraph") && !cls.contains("placeholder")
                }
            } ?? []
            if exhausted {
                desktopLyricsRoot = nil
                desktopParagraphs = []
            }
        }
        if desktopLyricsRoot != nil {
            // Soda's desktop view exposes two visible paragraph rows but no
            // `active` class. The first row is the highlighted current line.
            // Reading it does not touch the minimized main window's subtree.
            let lines = desktopParagraphs.prefix(2).compactMap { paragraph -> String? in
                let parts = MusicLyricPresentation.clean(texts(paragraph))
                let line = parts.joined(separator: " ")
                return line.isEmpty ? nil : line
            }
            if desktopGate.accept(lines, identity: requested) {
                return result(lines, desktop: true)
            }
        }

        return result()
    }

    private func debugLog(_ message: String) {
        guard debugEnabled else { return }
        fputs("[QishuiLyricReader] \(message)\n", stderr)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> Any? {
        guard Date() < deadline, nodes < 2500 else { exhausted = true; return nil }
        AXUIElementSetMessagingTimeout(element, 0.03)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func string(_ element: AXUIElement, _ name: String) -> String {
        attribute(element, name) as? String ?? ""
    }

    private func classes(_ element: AXUIElement) -> Set<String> {
        Set(attribute(element, "AXDOMClassList") as? [String] ?? [])
    }

    private func children(_ element: AXUIElement, attribute name: String = "AXChildren") -> [AXUIElement] {
        attribute(element, name) as? [AXUIElement] ?? []
    }

    /// Stop descending at a match: scopes remain small and nested lyric text is
    /// read separately. A deadline/size overrun invalidates the entire result.
    private func find(_ root: AXUIElement, matching: (AXUIElement) -> Bool) -> [AXUIElement] {
        var found: [AXUIElement] = []
        var visited = Set<CFHashCode>()
        func walk(_ element: AXUIElement, depth: Int) {
            guard !exhausted else { return }
            guard visited.insert(CFHash(element)).inserted else { return }
            guard depth <= 24 else { exhausted = true; return }
            nodes += 1
            if matching(element) { found.append(element); return }
            let descendants = children(element)
            guard descendants.count <= 220 else { exhausted = true; return }
            for child in descendants { walk(child, depth: depth + 1) }
        }
        walk(root, depth: 0)
        return found
    }

    private func texts(_ root: AXUIElement) -> [String] {
        find(root) { self.string($0, "AXRole") == "AXStaticText" }
            .map { string($0, "AXValue") }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
