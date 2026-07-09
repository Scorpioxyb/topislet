import AppKit
import ApplicationServices
import Foundation

struct NowPlayingAXTrack: Equatable {
    let title: String
    let artist: String
    let rawLine: String
    let isPlaying: Bool?
}

struct NowPlayingAXSnapshot: Equatable {
    enum Availability: Equatable {
        case recognized(NowPlayingAXTrack)
        case accessibilityRequired
        case controlCenterUnavailable
        case nowPlayingUnavailable
        case failed(String)
    }

    let availability: Availability
    let checkedAt: Date
}

@MainActor
final class NowPlayingAXBridge {
    func capture(promptForPermission: Bool = false) -> NowPlayingAXSnapshot {
        guard accessibilityTrusted(promptForPermission: promptForPermission) else {
            return NowPlayingAXSnapshot(availability: .accessibilityRequired, checkedAt: Date())
        }

        guard let controlCenter = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else {
            return NowPlayingAXSnapshot(availability: .controlCenterUnavailable, checkedAt: Date())
        }

        let controlCenterElement = AXUIElementCreateApplication(controlCenter.processIdentifier)
        guard let nowPlayingButton = findElement(in: controlCenterElement, maxDepth: 5, matches: { element in
            let identifier = stringAttribute(element, "AXIdentifier")
            let description = stringAttribute(element, kAXDescriptionAttribute)
            return identifier == "com.apple.menuextra.now-playing"
                || description.localizedCaseInsensitiveContains("播放中")
                || description.localizedCaseInsensitiveContains("now playing")
        }) else {
            return NowPlayingAXSnapshot(availability: .nowPlayingUnavailable, checkedAt: Date())
        }

        let pressResult = AXUIElementPerformAction(nowPlayingButton, kAXPressAction as CFString)
        guard pressResult == .success else {
            return NowPlayingAXSnapshot(availability: .failed("无法打开系统播放中面板：\(pressResult.rawValue)"), checkedAt: Date())
        }

        Thread.sleep(forTimeInterval: 0.55)
        defer {
            AXUIElementPerformAction(nowPlayingButton, kAXCancelAction as CFString)
            postEscapeKey()
        }

        let windows = (copyAttribute(controlCenterElement, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        let focusedWindow = copyAttribute(controlCenterElement, kAXFocusedWindowAttribute).flatMap { value -> AXUIElement? in
            guard CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
        let searchRoots = ([focusedWindow].compactMap { $0 } + windows)

        for root in searchRoots {
            if let track = collectTrackCandidates(in: root, maxDepth: 7).first {
                return NowPlayingAXSnapshot(availability: .recognized(track), checkedAt: Date())
            }

            let lines = collectStaticTextValues(in: root, maxDepth: 7)
            guard let rawLine = lines.first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 }) else {
                continue
            }
            let track = parseTrack(rawLine: rawLine, buttonDescriptions: collectButtonDescriptions(in: root, maxDepth: 7))
            return NowPlayingAXSnapshot(availability: .recognized(track), checkedAt: Date())
        }

        return NowPlayingAXSnapshot(availability: .nowPlayingUnavailable, checkedAt: Date())
    }

    private func collectTrackCandidates(in root: AXUIElement, maxDepth: Int) -> [NowPlayingAXTrack] {
        var candidates: [NowPlayingAXTrack] = []
        var seen = Set<CFHashCode>()

        func walk(_ element: AXUIElement, depth: Int) {
            let key = CFHash(element)
            guard !seen.contains(key), depth <= maxDepth else { return }
            seen.insert(key)

            if stringAttribute(element, kAXRoleAttribute) == "AXGroup" {
                let lines = uniqueNonEmpty(collectStaticTextValues(in: element, maxDepth: 2))
                let buttons = uniqueNonEmpty(collectButtonDescriptions(in: element, maxDepth: 2))
                if lines.count == 1, !buttons.isEmpty {
                    candidates.append(parseTrack(rawLine: lines[0], buttonDescriptions: buttons))
                }
            }

            for child in childElements(element) {
                walk(child, depth: depth + 1)
            }
        }

        walk(root, depth: 0)
        return candidates
    }

    private func uniqueNonEmpty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return nil }
            seen.insert(trimmed)
            return trimmed
        }
    }

    private func accessibilityTrusted(promptForPermission: Bool) -> Bool {
        if promptForPermission {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    private func parseTrack(rawLine: String, buttonDescriptions: [String]) -> NowPlayingAXTrack {
        let cleaned = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        var title = cleaned
        var artist = "系统播放中"

        if let commaRange = cleaned.range(of: "、") {
            title = String(cleaned[..<commaRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let remainder = String(cleaned[commaRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let dashRange = remainder.range(of: " – ") {
                artist = String(remainder[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if !remainder.isEmpty {
                artist = remainder
            }
        } else if let dashRange = cleaned.range(of: " – ") {
            title = String(cleaned[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            artist = String(cleaned[dashRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let isPlaying: Bool?
        if buttonDescriptions.contains(where: { $0.contains("暂停") || $0.localizedCaseInsensitiveContains("pause") }) {
            isPlaying = true
        } else if buttonDescriptions.contains(where: { $0.contains("播放") || $0.localizedCaseInsensitiveContains("play") }) {
            isPlaying = false
        } else {
            isPlaying = nil
        }

        return NowPlayingAXTrack(
            title: title.isEmpty ? cleaned : title,
            artist: artist.isEmpty ? "系统播放中" : artist,
            rawLine: cleaned,
            isPlaying: isPlaying
        )
    }

    private func collectStaticTextValues(in root: AXUIElement, maxDepth: Int) -> [String] {
        collectValues(in: root, maxDepth: maxDepth) { element in
            guard stringAttribute(element, kAXRoleAttribute) == "AXStaticText" else { return nil }
            return stringAttribute(element, kAXValueAttribute)
        }
    }

    private func collectButtonDescriptions(in root: AXUIElement, maxDepth: Int) -> [String] {
        collectValues(in: root, maxDepth: maxDepth) { element in
            guard stringAttribute(element, kAXRoleAttribute) == "AXButton" else { return nil }
            return stringAttribute(element, kAXDescriptionAttribute)
        }
    }

    private func collectValues(in root: AXUIElement, maxDepth: Int, value: (AXUIElement) -> String?) -> [String] {
        var values: [String] = []
        var seen = Set<CFHashCode>()

        func walk(_ element: AXUIElement, depth: Int) {
            let key = CFHash(element)
            guard !seen.contains(key), depth <= maxDepth else { return }
            seen.insert(key)

            if let text = value(element)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                values.append(text)
            }

            for child in childElements(element) {
                walk(child, depth: depth + 1)
            }
        }

        walk(root, depth: 0)
        return values
    }

    private func findElement(
        in root: AXUIElement,
        maxDepth: Int,
        matches: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        var seen = Set<CFHashCode>()

        func walk(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            let key = CFHash(element)
            guard !seen.contains(key), depth <= maxDepth else { return nil }
            seen.insert(key)

            if matches(element) {
                return element
            }

            for child in childElements(element) {
                if let found = walk(child, depth: depth + 1) {
                    return found
                }
            }
            return nil
        }

        return walk(root, depth: 0)
    }

    private func childElements(_ element: AXUIElement) -> [AXUIElement] {
        let childAttributes = [
            kAXChildrenAttribute,
            kAXMenuBarAttribute,
            "AXExtrasMenuBar",
            "AXVisibleChildren",
            "AXChildrenInNavigationOrder",
            "AXContents",
            "AXFocusedWindow",
            "AXFocusedUIElement"
        ]

        var children: [AXUIElement] = []
        for attribute in childAttributes {
            guard let value = copyAttribute(element, attribute) else { continue }
            if let array = value as? [Any] {
                for item in array where CFGetTypeID(item as CFTypeRef) == AXUIElementGetTypeID() {
                    children.append(item as! AXUIElement)
                }
            } else if CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() {
                children.append(value as! AXUIElement)
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

    private func postEscapeKey() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false) else {
            return
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
