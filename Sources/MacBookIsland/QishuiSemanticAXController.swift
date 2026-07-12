import AppKit
import ApplicationServices
import Foundation

struct QishuiSemanticAXControlResult: Sendable {
    let didPress: Bool
    let diagnostic: String
}

final class QishuiSemanticAXController: @unchecked Sendable {
    private struct CachedControls {
        let processIdentifier: pid_t
        let previous: AXUIElement
        let playPause: AXUIElement
        let next: AXUIElement

        func element(for command: MusicControlCommand) -> AXUIElement {
            switch command {
            case .previousTrack:
                return previous
            case .playPause:
                return playPause
            case .nextTrack:
                return next
            }
        }
    }

    private struct QueueItem {
        let element: AXUIElement
        let depth: Int
    }

    private struct ElementIdentity: Hashable {
        let rawValue: UInt

        init(element: AXUIElement) {
            rawValue = UInt(bitPattern: Unmanaged.passUnretained(element).toOpaque())
        }
    }

    private let bundleIdentifier = "com.soda.music"
    private let maximumDepth = 18
    private let maximumNodeCount = 8_000
    private let messagingTimeout: Float = 0.08
    private let lock = NSLock()
    private var cachedControls: CachedControls?

    func press(_ command: MusicControlCommand) -> QishuiSemanticAXControlResult {
        lock.lock()
        defer { lock.unlock() }
        guard AXIsProcessTrusted() else {
            cachedControls = nil
            return QishuiSemanticAXControlResult(
                didPress: false,
                diagnostic: "需要在系统设置中允许顶屿使用辅助功能。"
            )
        }

        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first else {
            cachedControls = nil
            return QishuiSemanticAXControlResult(
                didPress: false,
                diagnostic: "未检测到汽水音乐进程。"
            )
        }

        let processIdentifier = app.processIdentifier
        if let cachedControls,
           cachedControls.processIdentifier == processIdentifier {
            let cachedResult = performPress(cachedControls.element(for: command))
            if cachedResult == .success {
                return QishuiSemanticAXControlResult(
                    didPress: true,
                    diagnostic: "已通过汽水音乐语义化播放控件执行\(command.label)。"
                )
            }
            self.cachedControls = nil
        }

        let discovery = discoverControls(processIdentifier: processIdentifier)
        guard discovery.matches.count == 1, let controls = discovery.matches.first else {
            cachedControls = nil
            let detail = discovery.matches.isEmpty
                ? "扫描 \(discovery.scanned) 个汽水辅助功能节点后未找到唯一播放控制组；为避免误操作，未发送\(command.label)。"
                : "发现 \(discovery.matches.count) 个候选播放控制组；为避免误操作，未发送\(command.label)。"
            return QishuiSemanticAXControlResult(didPress: false, diagnostic: detail)
        }

        cachedControls = controls
        let result = performPress(controls.element(for: command))
        guard result == .success else {
            cachedControls = nil
            return QishuiSemanticAXControlResult(
                didPress: false,
                diagnostic: "汽水播放控件拒绝了\(command.label)操作（AXError \(result.rawValue)）。"
            )
        }

        return QishuiSemanticAXControlResult(
            didPress: true,
            diagnostic: "已通过汽水音乐语义化播放控件执行\(command.label)。"
        )
    }

    func invalidateCache() {
        lock.lock()
        defer { lock.unlock() }
        cachedControls = nil
    }

    private func discoverControls(processIdentifier: pid_t) -> (matches: [CachedControls], scanned: Int) {
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)

        var queue = [QueueItem(element: application, depth: 0)]
        for root in applicationRoots(of: application) {
            queue.append(QueueItem(element: root, depth: 0))
        }
        var queueIndex = 0
        var visited = Set<ElementIdentity>()
        var matches: [CachedControls] = []
        var matchedElements = Set<ElementIdentity>()

        while queueIndex < queue.count, visited.count < maximumNodeCount {
            let item = queue[queueIndex]
            queueIndex += 1

            let identity = ElementIdentity(element: item.element)
            guard visited.insert(identity).inserted else { continue }
            AXUIElementSetMessagingTimeout(item.element, messagingTimeout)

            if let orderedControls = playbackControls(in: item.element),
               hasPlaybackTimeContext(around: item.element) {
                if matchedElements.insert(identity).inserted {
                    matches.append(
                        CachedControls(
                            processIdentifier: processIdentifier,
                            previous: orderedControls[0],
                            playPause: orderedControls[1],
                            next: orderedControls[2]
                        )
                    )
                }
            }

            guard item.depth < maximumDepth,
                  !isMenuElement(item.element) else { continue }
            for child in traversalChildren(of: item.element) {
                queue.append(QueueItem(element: child, depth: item.depth + 1))
            }
        }

        return (matches, visited.count)
    }

    private func playbackControls(in element: AXUIElement) -> [AXUIElement]? {
        guard stringAttribute(element, kAXRoleAttribute as String) == kAXGroupRole as String else {
            return nil
        }

        let children = children(of: element)
        guard children.count == 3 else { return nil }
        guard children.allSatisfy({ supportsPress($0) && isEnabled($0) }) else { return nil }

        let framedChildren = children.compactMap { child -> (AXUIElement, CGRect)? in
            guard let frame = frame(of: child), frame.width > 0, frame.height > 0 else { return nil }
            return (child, frame)
        }
        guard framedChildren.count == 3 else { return nil }

        let ordered = framedChildren.sorted { $0.1.midX < $1.1.midX }
        let left = ordered[0].1.size
        let center = ordered[1].1.size
        let right = ordered[2].1.size
        let sideWidth = max(left.width, right.width)
        let sideDifference = abs(left.width - right.width) / max(sideWidth, 1)
        let maximumHeight = max(left.height, center.height, right.height)
        let minimumHeight = min(left.height, center.height, right.height)

        guard center.width >= sideWidth * 1.12,
              sideDifference <= 0.2,
              minimumHeight / max(maximumHeight, 1) >= 0.78 else {
            return nil
        }

        return ordered.map(\.0)
    }

    private func hasPlaybackTimeContext(around controls: AXUIElement) -> Bool {
        var current: AXUIElement? = controls
        for _ in 0..<3 {
            guard let element = current else { return false }
            if containsPlaybackTime(in: element, maximumDepth: 3) {
                return true
            }
            guard let parent = copyAttribute(element, kAXParentAttribute as String),
                  CFGetTypeID(parent as CFTypeRef) == AXUIElementGetTypeID() else {
                current = nil
                continue
            }
            current = (parent as! AXUIElement)
        }
        return false
    }

    private func containsPlaybackTime(in root: AXUIElement, maximumDepth: Int) -> Bool {
        var queue = [QueueItem(element: root, depth: 0)]
        var queueIndex = 0
        var visited = Set<ElementIdentity>()

        while queueIndex < queue.count, visited.count < 500 {
            let item = queue[queueIndex]
            queueIndex += 1
            guard visited.insert(ElementIdentity(element: item.element)).inserted else { continue }

            let text = [
                stringAttribute(item.element, kAXValueAttribute as String),
                stringAttribute(item.element, kAXDescriptionAttribute as String)
            ].joined(separator: " ")
            if text.range(
                of: #"\b\d{1,2}:\d{2}\s*/\s*\d{1,2}:\d{2}\b"#,
                options: .regularExpression
            ) != nil {
                return true
            }

            guard item.depth < maximumDepth else { continue }
            for child in children(of: item.element) {
                queue.append(QueueItem(element: child, depth: item.depth + 1))
            }
        }
        return false
    }

    private func performPress(_ element: AXUIElement) -> AXError {
        guard supportsPress(element), isEnabled(element) else { return .actionUnsupported }
        return AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    private func supportsPress(_ element: AXUIElement) -> Bool {
        var actionNames: CFArray?
        let result = AXUIElementCopyActionNames(element, &actionNames)
        guard result == .success, let actions = actionNames as? [String] else { return false }
        return actions.contains(kAXPressAction as String)
    }

    private func isEnabled(_ element: AXUIElement) -> Bool {
        guard let value = copyAttribute(element, kAXEnabledAttribute as String) else { return true }
        if let enabled = value as? Bool { return enabled }
        if let enabled = value as? NSNumber { return enabled.boolValue }
        return true
    }

    private func isMenuElement(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(element, kAXRoleAttribute as String)
        return role == kAXMenuBarRole as String
            || role == kAXMenuRole as String
            || role == kAXMenuItemRole as String
            || role == "AXMenuBarItem"
            || role.localizedCaseInsensitiveContains("menu")
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        guard let value = copyAttribute(element, kAXChildrenAttribute as String) else { return [] }
        return accessibilityElements(from: value)
    }

    private func traversalChildren(of element: AXUIElement) -> [AXUIElement] {
        let attributes = [
            kAXChildrenAttribute as String,
            "AXVisibleChildren",
            "AXChildrenInNavigationOrder",
            "AXContents",
            "AXRows",
            "AXColumns",
            "AXTabs",
            "AXSections",
            "AXTitleUIElement",
            "AXLinkedUIElements"
        ]

        for attribute in attributes {
            guard let value = copyAttribute(element, attribute) else { continue }
            let elements = accessibilityElements(from: value)
            if !elements.isEmpty {
                return elements
            }
        }
        return []
    }

    private func applicationRoots(of application: AXUIElement) -> [AXUIElement] {
        let attributes = [
            kAXFocusedWindowAttribute as String,
            "AXMainWindow",
            kAXWindowsAttribute as String,
            kAXFocusedUIElementAttribute as String,
            kAXChildrenAttribute as String
        ]

        var elements: [AXUIElement] = []
        for attribute in attributes {
            guard let value = copyAttribute(application, attribute) else { continue }
            elements.append(contentsOf: accessibilityElements(from: value))
        }
        var seen = Set<ElementIdentity>()
        return elements.filter { element in
            seen.insert(ElementIdentity(element: element)).inserted
        }
    }

    private func accessibilityElements(from value: Any) -> [AXUIElement] {
        let values = value as? [Any] ?? [value]
        var seen = Set<ElementIdentity>()
        return values.compactMap { value in
            guard CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
            let child = value as! AXUIElement
            guard seen.insert(ElementIdentity(element: child)).inserted else { return nil }
            return child
        }
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = copyAttribute(element, kAXPositionAttribute as String),
              let sizeValue = copyAttribute(element, kAXSizeAttribute as String),
              CFGetTypeID(positionValue as CFTypeRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue as CFTypeRef) == AXValueGetTypeID() else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: point, size: size)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String {
        guard let value = copyAttribute(element, attribute) else { return "" }
        if let value = value as? String { return value }
        if let value = value as? NSAttributedString { return value.string }
        return ""
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> Any? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }
}
