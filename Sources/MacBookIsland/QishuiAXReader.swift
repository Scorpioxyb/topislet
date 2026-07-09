import AppKit
import ApplicationServices
import Foundation

struct QishuiAXReadResult: Equatable {
    let track: QishuiDirectTrack?
    let requiresAccessibility: Bool
    let diagnostic: String
    let scannedNodeCount: Int
}

final class QishuiAXReader {
    private let imagePrefixes: [String]
    private let maxDepth = 30
    private let maxChildrenPerNode = 220
    private let maxNodes = 6_000
    private let axMessageTimeout: Float = 0.35
    private let cachedProfileTTL: TimeInterval = 1.4
    private var preferredContentRoot: AXUIElement?
    private var cachedProfile: CachedTrackProfile?

    init(imagePrefixes: [String]) {
        self.imagePrefixes = imagePrefixes
    }

    func invalidateCache() {
        cachedProfile = nil
    }

    func read(from app: NSRunningApplication) -> QishuiAXReadResult {
        let startedAt = Date()
        guard AXIsProcessTrusted() else {
            return QishuiAXReadResult(
                track: nil,
                requiresAccessibility: true,
                diagnostic: "汽水直接 AX 同步需要辅助功能权限；不会改用控制中心或 OCR。",
                scannedNodeCount: 0
            )
        }

        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, axMessageTimeout)
        let readResult = readTrack(from: root)
        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
        guard readResult.track != nil || !readResult.nodes.isEmpty else {
            return QishuiAXReadResult(
                track: nil,
                requiresAccessibility: false,
                diagnostic: "汽水 AX 已授权，但没有读到窗口节点；请确认汽水音乐窗口未最小化。读取耗时 \(elapsedMs)ms。",
                scannedNodeCount: 0
            )
        }

        guard let track = readResult.track else {
            return QishuiAXReadResult(
                track: nil,
                requiresAccessibility: false,
                diagnostic: "汽水 AX 已授权，但未找到当前播放卡片；当前只接受汽水窗口直接暴露的数据。读取耗时 \(elapsedMs)ms。",
                scannedNodeCount: readResult.nodes.count
            )
        }

        return QishuiAXReadResult(
            track: track,
            requiresAccessibility: false,
            diagnostic: "已从汽水窗口 AX 读取当前歌曲、歌手、封面和可见歌词。读取耗时 \(elapsedMs)ms；命中 \(readResult.sourceLabel)。",
            scannedNodeCount: readResult.nodes.count
        )
    }

    private func readTrack(from appElement: AXUIElement) -> (track: QishuiDirectTrack?, nodes: [AXNodeRecord], sourceLabel: String) {
        if let cachedTrack = readCachedTrack() {
            return (cachedTrack, [], "缓存的汽水播放节点")
        }

        let roots = contentRoots(from: appElement)
        var attempts: [(label: String, element: AXUIElement)] = []
        var seen = Set<CFHashCode>()

        if let preferredContentRoot {
            attempts.append(("上次命中的汽水内容区", preferredContentRoot))
            seen.insert(CFHash(preferredContentRoot))
        }

        for root in roots {
            let key = CFHash(root.element)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            attempts.append(root)
        }

        if attempts.isEmpty {
            attempts.append(("汽水应用根节点", appElement))
        }

        var combinedNodes: [AXNodeRecord] = []
        var firstNonEmptyNodes: [AXNodeRecord] = []

        for attempt in attempts {
            let nodes = collectNodes(from: attempt.element, pathPrefix: attempt.label)
            if firstNonEmptyNodes.isEmpty, !nodes.isEmpty {
                firstNonEmptyNodes = nodes
            }
            if let track = extractTrack(from: nodes) {
                preferredContentRoot = attempt.element
                return (track, nodes, attempt.label)
            }
            combinedNodes.append(contentsOf: nodes)
        }

        if let track = extractTrack(from: combinedNodes) {
            preferredContentRoot = nil
            return (track, combinedNodes, "组合汽水内容区")
        }

        return (nil, combinedNodes.isEmpty ? firstNonEmptyNodes : combinedNodes, "汽水内容区")
    }

    private func collectNodes(from root: AXUIElement, pathPrefix: String) -> [AXNodeRecord] {
        var nodes: [AXNodeRecord] = []
        var seen = Set<CFHashCode>()

        func walk(_ element: AXUIElement, path: String, depth: Int) {
            guard depth <= maxDepth, nodes.count < maxNodes else { return }
            AXUIElementSetMessagingTimeout(element, axMessageTimeout)

            let key = CFHash(element)
            guard !seen.contains(key) else { return }
            seen.insert(key)

            let record = AXNodeRecord(
                element: element,
                order: nodes.count,
                path: path,
                role: stringAttribute(element, kAXRoleAttribute as String),
                title: stringAttribute(element, kAXTitleAttribute as String),
                value: stringAttribute(element, kAXValueAttribute as String),
                description: stringAttribute(element, kAXDescriptionAttribute as String),
                url: stringAttribute(element, "AXURL"),
                frame: frame(of: element)
            )
            nodes.append(record)

            for (index, child) in childElements(of: element).prefix(maxChildrenPerNode).enumerated() {
                walk(child, path: "\(path).child[\(index)]", depth: depth + 1)
            }
        }

        walk(root, path: pathPrefix, depth: 0)
        return nodes
    }

    private func contentRoots(from appElement: AXUIElement) -> [(label: String, element: AXUIElement)] {
        let attributes = [
            kAXFocusedWindowAttribute as String,
            "AXMainWindow",
            kAXWindowsAttribute as String,
            kAXFocusedUIElementAttribute as String,
            kAXChildrenAttribute as String
        ]

        var roots: [(label: String, element: AXUIElement)] = []
        var seen = Set<CFHashCode>()

        func add(_ element: AXUIElement, label: String) {
            AXUIElementSetMessagingTimeout(element, axMessageTimeout)
            let role = stringAttribute(element, kAXRoleAttribute as String)
            guard !isChromeRole(role) else { return }
            let key = CFHash(element)
            guard !seen.contains(key) else { return }
            seen.insert(key)
            roots.append((label, element))
        }

        for attribute in attributes {
            guard let value = copyAttribute(appElement, attribute) else { continue }
            if let array = value as? [Any] {
                for item in array where CFGetTypeID(item as CFTypeRef) == AXUIElementGetTypeID() {
                    add(item as! AXUIElement, label: attribute)
                }
            } else if CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() {
                add(value as! AXUIElement, label: attribute)
            }
        }

        return roots
    }

    private func extractTrack(from nodes: [AXNodeRecord]) -> QishuiDirectTrack? {
        let imageNodes = nodes
            .filter { $0.isImage && $0.frameArea >= 900 && imageDescriptor(from: $0) != nil }
            .sorted { lhs, rhs in
                if lhs.frameArea == rhs.frameArea {
                    return lhs.order < rhs.order
                }
                return lhs.frameArea > rhs.frameArea
            }

        for cover in imageNodes {
            guard let coverFrame = cover.frame else { continue }
            guard let title = titleNearCover(coverFrame, nodes: nodes) else { continue }

            let artists = artistsNearCover(coverFrame, titleFrame: title.frame, nodes: nodes)
            guard !artists.isEmpty else { continue }

            let artworkURL = artworkURL(from: cover)
            let lyrics = lyricsNearCover(coverFrame, nodes: nodes)
            let progress = progressRatio(from: nodes, coverFrame: coverFrame)
            cachedProfile = CachedTrackProfile(
                cachedAt: Date(),
                cover: cover.element,
                title: title.node.element,
                artists: artists.map { $0.node.element },
                lyrics: lyrics.map { $0.node.element },
                progressCandidates: progressCandidateNodes(from: nodes, coverFrame: coverFrame).map { $0.element }
            )
            return QishuiDirectTrack(
                title: title.text,
                artist: artists.map(\.text).joined(separator: " / "),
                artworkURL: artworkURL,
                lyrics: lyrics.isEmpty ? ["汽水窗口已同步，暂未暴露可见歌词"] : Array(lyrics.map(\.text).prefix(4)),
                isPlaying: nil,
                progress: progress,
                sourceName: "汽水窗口 AX"
            )
        }

        return nil
    }

    private func readCachedTrack() -> QishuiDirectTrack? {
        guard let cachedProfile else { return nil }
        guard Date().timeIntervalSince(cachedProfile.cachedAt) <= cachedProfileTTL else {
            self.cachedProfile = nil
            return nil
        }

        let title = cleanText(text(from: cachedProfile.title))
        guard isLikelySongOrArtistText(title), !isKnownNonTitleText(title) else {
            self.cachedProfile = nil
            return nil
        }

        let artists = uniqueTexts(cachedProfile.artists.map { text(from: $0) })
            .filter { isLikelySongOrArtistText($0) && !isKnownNonTitleText($0) }
        guard !artists.isEmpty else {
            self.cachedProfile = nil
            return nil
        }

        let cachedCoverRecord = record(from: cachedProfile.cover, order: 0, path: "cached.cover")
        let cachedArtworkURL: URL?
        if let cachedCoverRecord {
            cachedArtworkURL = artworkURL(from: cachedCoverRecord)
        } else {
            cachedArtworkURL = nil
        }
        let lyrics = uniqueTexts(cachedProfile.lyrics.map { text(from: $0) })
            .filter(isLikelyLyricText)
        let progress = cachedProgressRatio(from: cachedProfile.progressCandidates)

        return QishuiDirectTrack(
            title: title,
            artist: artists.joined(separator: " / "),
            artworkURL: cachedArtworkURL,
            lyrics: lyrics.isEmpty ? ["汽水窗口已同步，暂未暴露可见歌词"] : Array(lyrics.prefix(4)),
            isPlaying: nil,
            progress: progress,
            sourceName: "汽水窗口 AX"
        )
    }

    private func titleNearCover(_ coverFrame: CGRect, nodes: [AXNodeRecord]) -> (node: AXNodeRecord, text: String, frame: CGRect?)? {
        let lowerBound = coverFrame.maxY - 8
        let upperBound = coverFrame.maxY + 88

        let candidates = nodes.compactMap { node -> (node: AXNodeRecord, text: String, score: CGFloat)? in
            guard node.isStaticText, let frame = node.frame else { return nil }
            guard frame.minY >= lowerBound, frame.minY <= upperBound else { return nil }
            guard frame.minX >= coverFrame.minX - 24, frame.minX <= coverFrame.maxX + 80 else { return nil }
            let text = cleanText(node.primaryText)
            guard isLikelySongOrArtistText(text) else { return nil }
            guard !isArtistSeparator(text), !isKnownNonTitleText(text) else { return nil }

            let verticalTarget = coverFrame.maxY + 30
            let verticalDistance = abs(frame.minY - verticalTarget)
            let xDistance = abs(frame.minX - coverFrame.minX)
            return (node, text, verticalDistance + xDistance * 0.25)
        }

        guard let best = candidates.sorted(by: { $0.score < $1.score }).first else { return nil }
        return (best.node, best.text, best.node.frame)
    }

    private func artistsNearCover(
        _ coverFrame: CGRect,
        titleFrame: CGRect?,
        nodes: [AXNodeRecord]
    ) -> [(node: AXNodeRecord, text: String)] {
        let titleY = titleFrame?.minY ?? coverFrame.maxY + 30
        let lowerBound = titleY + 8
        let upperBound = titleY + 58

        let linkArtists = nodes
            .filter { $0.isLink }
            .compactMap { node -> (node: AXNodeRecord, order: Int, text: String)? in
                guard let frame = node.frame else { return nil }
                guard frame.minY >= lowerBound, frame.minY <= upperBound else { return nil }
                guard frame.minX >= coverFrame.minX - 24, frame.minX <= coverFrame.maxX + 180 else { return nil }
                let text = cleanText(node.description.isEmpty ? node.primaryText : node.description)
                guard isLikelySongOrArtistText(text), !isKnownNonTitleText(text) else { return nil }
                return (node, node.order, text)
            }

        if !linkArtists.isEmpty {
            return uniqueTextNodes(linkArtists.sorted { $0.order < $1.order }.map { ($0.node, $0.text) })
        }

        let staticArtists = nodes
            .filter { $0.isStaticText }
            .compactMap { node -> (node: AXNodeRecord, order: Int, text: String)? in
                guard let frame = node.frame else { return nil }
                guard frame.minY >= lowerBound, frame.minY <= upperBound else { return nil }
                guard frame.minX >= coverFrame.minX - 24, frame.minX <= coverFrame.maxX + 180 else { return nil }
                let text = cleanText(node.primaryText)
                guard isLikelySongOrArtistText(text), !isArtistSeparator(text), !isKnownNonTitleText(text) else { return nil }
                return (node, node.order, text)
            }

        return uniqueTextNodes(staticArtists.sorted { $0.order < $1.order }.map { ($0.node, $0.text) })
    }

    private func lyricsNearCover(_ coverFrame: CGRect, nodes: [AXNodeRecord]) -> [(node: AXNodeRecord, text: String)] {
        let minX = coverFrame.maxX + 36
        let lowerY = coverFrame.minY - 40
        let upperY = coverFrame.maxY + 140

        let lyricTexts = nodes
            .filter { $0.isStaticText }
            .compactMap { node -> (node: AXNodeRecord, order: Int, text: String)? in
                guard let frame = node.frame else { return nil }
                guard frame.minX >= minX, frame.minY >= lowerY, frame.minY <= upperY else { return nil }
                let text = cleanText(node.primaryText)
                guard isLikelyLyricText(text) else { return nil }
                return (node, node.order, text)
            }
            .sorted { $0.order < $1.order }

        return uniqueTextNodes(lyricTexts.map { ($0.node, $0.text) })
    }

    private func progressRatio(from nodes: [AXNodeRecord], coverFrame: CGRect) -> Double {
        let staticCandidates = progressCandidates(from: nodes.filter(\.isStaticText), coverFrame: coverFrame)
        if let best = staticCandidates.sorted(by: progressCandidateSort).first {
            return best.ratio
        }

        let groupCandidates = progressCandidates(from: nodes.filter { !$0.isStaticText }, coverFrame: coverFrame)
        if let best = groupCandidates.sorted(by: progressCandidateSort).first {
            return best.ratio
        }

        return 0
    }

    private func progressCandidates(
        from nodes: [AXNodeRecord],
        coverFrame: CGRect
    ) -> [ProgressCandidate] {
        nodes.flatMap { node -> [ProgressCandidate] in
            let texts = uniqueTexts([node.value, node.title, node.description])
            return texts.compactMap { text in
                guard let parsed = parseProgress(text) else { return nil }
                let frame = node.frame
                let y = frame?.minY ?? 0
                let bottomBarBias = y >= coverFrame.maxY + 120 ? 1_000.0 : 0
                return ProgressCandidate(
                    node: node,
                    ratio: parsed.ratio,
                    y: y,
                    bottomBarBias: bottomBarBias,
                    order: node.order
                )
            }
        }
    }

    private func progressCandidateNodes(from nodes: [AXNodeRecord], coverFrame: CGRect) -> [AXNodeRecord] {
        let staticCandidates = progressCandidates(from: nodes.filter(\.isStaticText), coverFrame: coverFrame)
        if !staticCandidates.isEmpty {
            return staticCandidates.sorted(by: progressCandidateSort).map(\.node)
        }

        return progressCandidates(from: nodes.filter { !$0.isStaticText }, coverFrame: coverFrame)
            .sorted(by: progressCandidateSort)
            .map(\.node)
    }

    private func progressCandidateSort(_ lhs: ProgressCandidate, _ rhs: ProgressCandidate) -> Bool {
        if lhs.bottomBarBias != rhs.bottomBarBias {
            return lhs.bottomBarBias > rhs.bottomBarBias
        }
        if lhs.y != rhs.y {
            return lhs.y > rhs.y
        }
        return lhs.order < rhs.order
    }

    private func cachedProgressRatio(from elements: [AXUIElement]) -> Double {
        for element in elements {
            let texts = uniqueTexts([
                stringAttribute(element, kAXValueAttribute as String),
                stringAttribute(element, kAXTitleAttribute as String),
                stringAttribute(element, kAXDescriptionAttribute as String)
            ])
            for text in texts {
                if let parsed = parseProgress(text) {
                    return parsed.ratio
                }
            }
        }
        return 0
    }

    private func parseProgress(_ text: String) -> (ratio: Double, elapsed: Double, duration: Double)? {
        let pattern = #"(\d{1,2}):(\d{2})\s*/\s*(\d{1,2}):(\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges == 5 else {
            return nil
        }

        func number(at index: Int) -> Double? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return Double(text[range])
        }

        guard let elapsedMinutes = number(at: 1),
              let elapsedSeconds = number(at: 2),
              let durationMinutes = number(at: 3),
              let durationSeconds = number(at: 4) else {
            return nil
        }

        let elapsed = elapsedMinutes * 60 + elapsedSeconds
        let duration = durationMinutes * 60 + durationSeconds
        guard duration > 0, elapsed >= 0, elapsed <= duration + 3 else { return nil }
        return (min(max(elapsed / duration, 0), 1), elapsed, duration)
    }

    private func artworkURL(from node: AXNodeRecord) -> URL? {
        if let url = URL(string: node.url), url.scheme?.hasPrefix("http") == true {
            return url
        }

        guard let descriptor = imageDescriptor(from: node) else { return nil }
        if let url = URL(string: descriptor), url.scheme?.hasPrefix("http") == true {
            return url
        }

        let prefixes = imagePrefixes.isEmpty
            ? ["https://p3-luna.douyinpic.com/img/", "https://p6-luna.douyinpic.com/img/"]
            : imagePrefixes

        for prefix in prefixes {
            guard let url = joinedImageURL(prefix: prefix, path: descriptor) else { continue }
            return url
        }
        return nil
    }

    private func imageDescriptor(from node: AXNodeRecord) -> String? {
        let descriptor = cleanText(node.description.isEmpty ? node.primaryText : node.description)
        guard descriptor.contains(".jpg") || descriptor.contains(".jpeg") || descriptor.contains(".png") || descriptor.contains(".webp") else {
            return nil
        }
        return descriptor
    }

    private func joinedImageURL(prefix: String, path: String) -> URL? {
        let normalizedPrefix = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: "\(normalizedPrefix)/\(normalizedPath)")
    }

    private func uniqueTexts(_ texts: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for text in texts {
            let normalized = cleanText(text)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append(normalized)
        }
        return result
    }

    private func uniqueTextNodes(_ nodes: [(node: AXNodeRecord, text: String)]) -> [(node: AXNodeRecord, text: String)] {
        var seen = Set<String>()
        var result: [(node: AXNodeRecord, text: String)] = []
        for item in nodes {
            let normalized = cleanText(item.text)
            guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            result.append((item.node, normalized))
        }
        return result
    }

    private func isLikelySongOrArtistText(_ text: String) -> Bool {
        let text = cleanText(text)
        guard text.count >= 2, text.count <= 80 else { return false }
        guard !isArtistSeparator(text) else { return false }
        guard text.range(of: #"^\d+$"#, options: .regularExpression) == nil else { return false }
        guard text.range(of: #"^\d{1,2}:\d{2}"#, options: .regularExpression) == nil else { return false }
        return true
    }

    private func isLikelyLyricText(_ text: String) -> Bool {
        let text = cleanText(text)
        guard text.count >= 2, text.count <= 90 else { return false }
        guard !isArtistSeparator(text), !isKnownNonTitleText(text) else { return false }
        guard text.range(of: #"^\d{1,2}:\d{2}"#, options: .regularExpression) == nil else { return false }
        return true
    }

    private func isArtistSeparator(_ text: String) -> Bool {
        [",", "，", "/", "、", "&"].contains(cleanText(text))
    }

    private func isKnownNonTitleText(_ text: String) -> Bool {
        let lowercased = cleanText(text).lowercased()
        let blocked: Set<String> = [
            "vip",
            "音质",
            "历史播放",
            "收藏的歌单和专辑",
            "暂无歌词，请欣赏",
            "正在加载歌词",
            "汽水音乐"
        ]
        return blocked.contains(lowercased)
    }

    private func cleanText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> Any? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String {
        guard let value = copyAttribute(element, attribute) else { return "" }
        if let string = value as? String { return string }
        if let attributed = value as? NSAttributedString { return attributed.string }
        if CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() { return "" }
        return String(describing: value)
    }

    private func text(from element: AXUIElement) -> String {
        cleanText(record(from: element, order: 0, path: "cached")?.primaryText ?? "")
    }

    private func record(from element: AXUIElement, order: Int, path: String) -> AXNodeRecord? {
        AXUIElementSetMessagingTimeout(element, axMessageTimeout)
        let role = stringAttribute(element, kAXRoleAttribute as String)
        let title = stringAttribute(element, kAXTitleAttribute as String)
        let value = stringAttribute(element, kAXValueAttribute as String)
        let description = stringAttribute(element, kAXDescriptionAttribute as String)
        let url = stringAttribute(element, "AXURL")
        guard !role.isEmpty || !title.isEmpty || !value.isEmpty || !description.isEmpty || !url.isEmpty else {
            return nil
        }
        return AXNodeRecord(
            element: element,
            order: order,
            path: path,
            role: role,
            title: title,
            value: value,
            description: description,
            url: url,
            frame: frame(of: element)
        )
    }

    private func childElements(of element: AXUIElement) -> [AXUIElement] {
        let childAttributes = [
            kAXChildrenAttribute as String,
            "AXVisibleChildren",
            "AXChildrenInNavigationOrder",
            "AXContents",
            "AXRows",
            "AXColumns",
            "AXTabs",
            kAXWindowsAttribute as String,
            "AXSections",
            "AXTitleUIElement",
            "AXLinkedUIElements",
            kAXFocusedUIElementAttribute as String,
            kAXFocusedWindowAttribute as String,
            "AXMainWindow"
        ]

        var children: [AXUIElement] = []
        for attribute in childAttributes {
            guard let value = copyAttribute(element, attribute) else { continue }
            if let array = value as? [Any] {
                for item in array where CFGetTypeID(item as CFTypeRef) == AXUIElementGetTypeID() {
                    let child = item as! AXUIElement
                    let role = stringAttribute(child, kAXRoleAttribute as String)
                    guard !isChromeRole(role) else { continue }
                    children.append(child)
                }
            } else if CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() {
                let child = value as! AXUIElement
                let role = stringAttribute(child, kAXRoleAttribute as String)
                guard !isChromeRole(role) else { continue }
                children.append(child)
            }
        }

        var seen = Set<CFHashCode>()
        return children.filter { child in
            let key = CFHash(child)
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func isChromeRole(_ role: String) -> Bool {
        role == kAXMenuBarRole as String
            || role == kAXMenuRole as String
            || role == kAXMenuItemRole as String
            || role == "AXMenuBarItem"
            || role.localizedCaseInsensitiveContains("menu")
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = copyAttribute(element, kAXPositionAttribute as String),
              let sizeValue = copyAttribute(element, kAXSizeAttribute as String) else {
            return nil
        }
        guard CFGetTypeID(positionValue as CFTypeRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue as CFTypeRef) == AXValueGetTypeID() else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }
}

private struct AXNodeRecord {
    let element: AXUIElement
    let order: Int
    let path: String
    let role: String
    let title: String
    let value: String
    let description: String
    let url: String
    let frame: CGRect?

    var primaryText: String {
        if !value.isEmpty { return value }
        if !title.isEmpty { return title }
        if !description.isEmpty { return description }
        return url
    }

    var isStaticText: Bool {
        role == kAXStaticTextRole as String || role.localizedCaseInsensitiveContains("static")
    }

    var isLink: Bool {
        role == "AXLink" || role.localizedCaseInsensitiveContains("link")
    }

    var isImage: Bool {
        role == kAXImageRole as String || role.localizedCaseInsensitiveContains("image")
    }

    var frameArea: CGFloat {
        guard let frame else { return 0 }
        return max(frame.width, 0) * max(frame.height, 0)
    }
}

private struct ProgressCandidate {
    let node: AXNodeRecord
    let ratio: Double
    let y: CGFloat
    let bottomBarBias: Double
    let order: Int
}

private struct CachedTrackProfile {
    let cachedAt: Date
    let cover: AXUIElement
    let title: AXUIElement
    let artists: [AXUIElement]
    let lyrics: [AXUIElement]
    let progressCandidates: [AXUIElement]
}
