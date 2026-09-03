import AppKit
import ApplicationServices
import Darwin
import Foundation

enum QishuiControlAvailability: String, Equatable, Sendable {
    case available
    case windowClosed
    case controlTreeUnavailable
    case accessibilityRequired
    case notRunning
    case unknown

    var allowsControl: Bool {
        self == .available
    }

    var requiresPreflightBeforeControl: Bool {
        !allowsControl
    }

    var allowsCachePrewarmAfterTrackChange: Bool {
        allowsControl
    }

    var unavailableReason: String? {
        switch self {
        case .available:
            return nil
        case .windowClosed:
            return "汽水主窗口已关闭；请先显示或最小化汽水窗口。"
        case .controlTreeUnavailable:
            return "汽水辅助功能控件暂不可用；顶屿会在后台自动重试。"
        case .accessibilityRequired:
            return "顶屿需要辅助功能权限才能控制汽水音乐。"
        case .notRunning:
            return "汽水音乐当前未运行。"
        case .unknown:
            return "正在确认汽水播放控件是否可用。"
        }
    }
}

struct QishuiSemanticAXControlResult: Sendable {
    let didPress: Bool
    let diagnostic: String
}

final class QishuiSemanticAXController: @unchecked Sendable {
    private static let manualAccessibilityAttribute = "AXManualAccessibility"
    private static let incompleteDiscoveryNodeThreshold = 256

    struct CandidateFacts: Equatable {
        let windowIsNormal: Bool
        let windowIsPrimary: Bool
        let windowIsVisible: Bool
        let windowIsMinimized: Bool
        let containerIsVisible: Bool
        let controlsAreEnabled: Bool
        let controlsAreInsideWindow: Bool
        let relativeY: Double?
        let hasPlaybackTimeContext: Bool
    }

    private struct CachedControls {
        let processIdentifier: pid_t
        let previous: AXUIElement
        let playPause: AXUIElement
        let next: AXUIElement
        let container: AXUIElement

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

    private struct DiscoveredControls {
        let controls: CachedControls
        let container: AXUIElement
    }

    private struct ElementIdentity: Hashable {
        let element: AXUIElement

        init(element: AXUIElement) {
            self.element = element
        }

        static func == (lhs: ElementIdentity, rhs: ElementIdentity) -> Bool {
            CFEqual(lhs.element, rhs.element)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(CFHash(element))
        }
    }

    private struct ControlSetIdentity: Hashable {
        let previous: ElementIdentity
        let playPause: ElementIdentity
        let next: ElementIdentity
    }

    private let maximumDepth = 18
    private let maximumNodeCount = 8_000
    private let messagingTimeout: Float = 0.08
    private let lock = NSLock()
    private var cachedControls: CachedControls?

    func press(
        _ command: MusicControlCommand,
        processIdentifier expectedProcessIdentifier: pid_t? = nil
    ) -> QishuiSemanticAXControlResult {
        lock.lock()
        defer { lock.unlock() }
        guard AXIsProcessTrusted() else {
            cachedControls = nil
            return QishuiSemanticAXControlResult(
                didPress: false,
                diagnostic: "需要在系统设置中允许顶屿使用辅助功能。"
            )
        }

        let app = QishuiProcessLocator.application(
            preferredProcessIdentifier: expectedProcessIdentifier,
            requirePreferredProcessIdentifier: expectedProcessIdentifier != nil
        )
        guard let app else {
            cachedControls = nil
            return QishuiSemanticAXControlResult(
                didPress: false,
                diagnostic: expectedProcessIdentifier == nil
                    ? "未检测到汽水音乐进程。"
                    : "岛当前显示的汽水音乐进程已失效，未发送\(command.label)。"
            )
        }

        let processIdentifier = app.processIdentifier
        guard enableManualAccessibility(processIdentifier: processIdentifier) else {
            cachedControls = nil
            return QishuiSemanticAXControlResult(
                didPress: false,
                diagnostic: "无法初始化汽水音乐的辅助功能控件树，未发送\(command.label)。"
            )
        }
        if let cachedControls,
           cachedControls.processIdentifier == processIdentifier,
           Self.isEligibleHealthCandidate(candidateFacts(for: cachedControls)) {
            let cachedResult = performPress(cachedControls.element(for: command))
            if cachedResult == .success {
                return QishuiSemanticAXControlResult(
                    didPress: true,
                    diagnostic: "已通过汽水音乐语义化播放控件执行\(command.label)。"
                )
            }
            self.cachedControls = nil
        }

        let discovery = discoverControlsWithRecovery(
            processIdentifier: processIdentifier
        )
        guard discovery.matches.count == 1, let match = discovery.matches.first else {
            cachedControls = nil
            let controlAvailability = Self.windowAvailability(
                processIdentifier: processIdentifier
            )
            let detail: String
            if discovery.matches.isEmpty, controlAvailability == .windowClosed {
                detail = "汽水主窗口已关闭，当前没有可验证的播放控件；请先显示或最小化汽水窗口。为避免激活汽水或误控其他媒体，未发送\(command.label)。"
            } else if discovery.matches.isEmpty {
                detail = "汽水窗口仍存在，但扫描 \(discovery.scanned) 个辅助功能节点后未找到唯一播放控制组；汽水辅助功能树可能暂不可用。为避免误操作，未发送\(command.label)。"
            } else {
                detail = "发现 \(discovery.matches.count) 个候选播放控制组；为避免误操作，未发送\(command.label)。"
            }
            return QishuiSemanticAXControlResult(didPress: false, diagnostic: detail)
        }

        let controls = match.controls
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

    func prepareAccessibilityTree() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard AXIsProcessTrusted(),
              let app = QishuiProcessLocator.application() else {
            return false
        }
        return enableManualAccessibility(
            processIdentifier: app.processIdentifier
        )
    }

    func controlAvailability(
        processIdentifier expectedProcessIdentifier: pid_t?
    ) -> QishuiControlAvailability {
        lock.lock()
        defer { lock.unlock() }

        let windowAvailability = Self.windowAvailability(
            processIdentifier: expectedProcessIdentifier
        )
        switch windowAvailability {
        case .available, .controlTreeUnavailable:
            break
        case .windowClosed, .accessibilityRequired, .notRunning, .unknown:
            cachedControls = nil
            return windowAvailability
        }
        guard let processIdentifier = expectedProcessIdentifier,
              enableManualAccessibility(processIdentifier: processIdentifier) else {
            cachedControls = nil
            return .unknown
        }

        if let cachedControls,
           cachedControls.processIdentifier == processIdentifier,
           Self.isEligibleHealthCandidate(candidateFacts(for: cachedControls)) {
            return .available
        }

        let discovery = discoverControlsWithRecovery(
            processIdentifier: processIdentifier
        )
        let availability = Self.resolveSemanticControlAvailability(
            windowAvailability: windowAvailability,
            candidateCount: discovery.matches.count
        )
        if availability == .available, let match = discovery.matches.first {
            cachedControls = match.controls
        } else {
            cachedControls = nil
        }
        return availability
    }

    func diagnostic() -> String {
        lock.lock()
        defer { lock.unlock() }
        guard AXIsProcessTrusted() else { return "accessibilityTrusted=false" }
        guard let app = QishuiProcessLocator.application() else {
            return "qishuiRunning=false"
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        let manualAccessibilityEnabled = boolAttribute(
            application,
            Self.manualAccessibilityAttribute
        )

        let discovery = discoverControls(processIdentifier: app.processIdentifier)
        var lines = [
            "accessibilityTrusted=true",
            "pid=\(app.processIdentifier)",
            "manualAccessibilityEnabled=\(manualAccessibilityEnabled)",
            "scanned=\(discovery.scanned)",
            "candidateCount=\(discovery.matches.count)"
        ]
        lines.append(contentsOf: rootDiagnostics(processIdentifier: app.processIdentifier))
        for (index, match) in discovery.matches.enumerated() {
            lines.append("candidate[\(index)]=\(diagnosticDescription(for: match))")
        }
        return lines.joined(separator: "\n")
    }

    private func rootDiagnostics(processIdentifier: pid_t) -> [String] {
        let application = AXUIElementCreateApplication(processIdentifier)
        let roots = applicationRoots(of: application)
        var lines = [
            "applicationRole=\(stringAttribute(application, kAXRoleAttribute as String))",
            "applicationChildren=\(children(of: application).count)",
            "applicationTraversalChildren=\(traversalChildren(of: application).count)",
            "applicationRoots=\(roots.count)"
        ]
        for attribute in [
            kAXFocusedWindowAttribute as String,
            "AXMainWindow",
            kAXWindowsAttribute as String,
            kAXFocusedUIElementAttribute as String,
            kAXChildrenAttribute as String
        ] {
            guard let value = copyAttribute(application, attribute) else {
                lines.append("attribute[\(attribute)]=nil")
                continue
            }
            let elements = accessibilityElements(from: value)
            let roles = elements.map { stringAttribute($0, kAXRoleAttribute as String) }
            lines.append("attribute[\(attribute)]=count:\(elements.count),roles:\(roles.joined(separator: ","))")
        }
        for (index, root) in roots.enumerated() {
            lines.append(
                "root[\(index)]=role:\(stringAttribute(root, kAXRoleAttribute as String)),children:\(children(of: root).count),traversal:\(traversalChildren(of: root).count),hash:\(CFHash(root))"
            )
        }
        return lines
    }

    static func canProceedAfterManualAccessibility(
        setResult: AXError,
        isEnabled: Bool
    ) -> Bool {
        setResult == .success || isEnabled
    }

    static func shouldRetrySparseDiscovery(
        scannedNodeCount: Int,
        candidateCount: Int,
        attempt: Int
    ) -> Bool {
        candidateCount == 0
            && scannedNodeCount <= incompleteDiscoveryNodeThreshold
            && attempt < 2
    }

    static func isEligibleCandidate(_ facts: CandidateFacts) -> Bool {
        guard facts.windowIsNormal,
              facts.windowIsPrimary,
              facts.windowIsVisible,
              !facts.windowIsMinimized,
              facts.containerIsVisible,
              facts.controlsAreEnabled,
              facts.controlsAreInsideWindow,
              facts.hasPlaybackTimeContext,
              let relativeY = facts.relativeY else { return false }
        return relativeY >= 0.72 && relativeY <= 1.02
    }

    static func isEligibleHealthCandidate(_ facts: CandidateFacts) -> Bool {
        if isEligibleCandidate(facts) {
            return true
        }
        guard facts.windowIsNormal,
              facts.windowIsPrimary,
              facts.windowIsMinimized,
              facts.controlsAreEnabled,
              facts.controlsAreInsideWindow,
              facts.hasPlaybackTimeContext,
              let relativeY = facts.relativeY else { return false }
        return relativeY >= 0.72 && relativeY <= 1.02
    }

    static func resolveWindowAvailability(
        isRunning: Bool,
        accessibilityTrusted: Bool,
        windowReadSucceeded: Bool,
        reportedWindowCount: Int,
        standardWindowCount: Int
    ) -> QishuiControlAvailability {
        guard isRunning else { return .notRunning }
        guard accessibilityTrusted else { return .accessibilityRequired }
        guard windowReadSucceeded else { return .unknown }
        guard reportedWindowCount > 0 else { return .windowClosed }
        return standardWindowCount > 0 ? .available : .controlTreeUnavailable
    }

    static func resolveSemanticControlAvailability(
        windowAvailability: QishuiControlAvailability,
        candidateCount: Int?
    ) -> QishuiControlAvailability {
        switch windowAvailability {
        case .available, .controlTreeUnavailable:
            guard let candidateCount else { return .unknown }
            return candidateCount == 1 ? .available : .controlTreeUnavailable
        case .windowClosed, .accessibilityRequired, .notRunning, .unknown:
            return windowAvailability
        }
    }

    static func windowAvailability(
        processIdentifier expectedProcessIdentifier: pid_t?
    ) -> QishuiControlAvailability {
        guard let processIdentifier = expectedProcessIdentifier,
              QishuiProcessLocator.isRunning(
                  processIdentifier: processIdentifier
              ) else {
            return .notRunning
        }
        guard AXIsProcessTrusted() else { return .accessibilityRequired }

        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.08)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &value
        )
        guard result == .success, let values = value as? [Any] else {
            return .unknown
        }

        let standardWindowCount = values.reduce(into: 0) { count, value in
            guard CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() else {
                return
            }
            let window = value as! AXUIElement
            var roleValue: CFTypeRef?
            var subroleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                window,
                kAXRoleAttribute as CFString,
                &roleValue
            ) == .success,
            AXUIElementCopyAttributeValue(
                window,
                kAXSubroleAttribute as CFString,
                &subroleValue
            ) == .success,
            roleValue as? String == kAXWindowRole as String,
            subroleValue as? String == kAXStandardWindowSubrole as String else {
                return
            }
            count += 1
        }
        return resolveWindowAvailability(
            isRunning: true,
            accessibilityTrusted: true,
            windowReadSucceeded: true,
            reportedWindowCount: values.count,
            standardWindowCount: standardWindowCount
        )
    }

    private func discoverControlsWithRecovery(
        processIdentifier: pid_t
    ) -> (matches: [DiscoveredControls], scanned: Int) {
        var discovery = discoverControls(processIdentifier: processIdentifier)
        for attempt in 0..<2 where Self.shouldRetrySparseDiscovery(
            scannedNodeCount: discovery.scanned,
            candidateCount: discovery.matches.count,
            attempt: attempt
        ) {
            if attempt == 0 {
                _ = rebuildManualAccessibility(
                    processIdentifier: processIdentifier
                )
            }
            usleep(attempt == 0 ? 80_000 : 160_000)
            discovery = discoverControls(
                processIdentifier: processIdentifier,
                timeout: attempt == 0 ? 0.25 : 0.5
            )
        }
        return discovery
    }

    private func discoverControls(
        processIdentifier: pid_t,
        timeout: Float? = nil
    ) -> (matches: [DiscoveredControls], scanned: Int) {
        let effectiveTimeout = timeout ?? messagingTimeout
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, effectiveTimeout)

        var queue = [QueueItem(element: application, depth: 0)]
        for root in applicationRoots(of: application) {
            queue.append(QueueItem(element: root, depth: 0))
        }
        var queueIndex = 0
        var visited = Set<ElementIdentity>()
        var matches: [DiscoveredControls] = []
        var matchedControlSets = Set<ControlSetIdentity>()

        while queueIndex < queue.count, visited.count < maximumNodeCount {
            let item = queue[queueIndex]
            queueIndex += 1

            let identity = ElementIdentity(element: item.element)
            guard visited.insert(identity).inserted else { continue }
            AXUIElementSetMessagingTimeout(item.element, effectiveTimeout)

            if let orderedControls = playbackControls(in: item.element),
               hasPlaybackTimeContext(around: item.element) {
                let controls = CachedControls(
                    processIdentifier: processIdentifier,
                    previous: orderedControls[0],
                    playPause: orderedControls[1],
                    next: orderedControls[2],
                    container: item.element
                )
                let controlSetIdentity = ControlSetIdentity(
                    previous: ElementIdentity(element: orderedControls[0]),
                    playPause: ElementIdentity(element: orderedControls[1]),
                    next: ElementIdentity(element: orderedControls[2])
                )
                if Self.isEligibleHealthCandidate(candidateFacts(for: controls)),
                   matchedControlSets.insert(controlSetIdentity).inserted {
                    matches.append(
                        DiscoveredControls(
                            controls: controls,
                            container: item.element
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

    private func enableManualAccessibility(processIdentifier: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        let result = AXUIElementSetAttributeValue(
            application,
            Self.manualAccessibilityAttribute as CFString,
            kCFBooleanTrue
        )
        let isEnabled = boolAttribute(
            application,
            Self.manualAccessibilityAttribute
        )
        return Self.canProceedAfterManualAccessibility(
            setResult: result,
            isEnabled: isEnabled
        )
    }

    private func rebuildManualAccessibility(processIdentifier: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.25)
        _ = AXUIElementSetAttributeValue(
            application,
            Self.manualAccessibilityAttribute as CFString,
            kCFBooleanFalse
        )
        usleep(20_000)
        let result = AXUIElementSetAttributeValue(
            application,
            Self.manualAccessibilityAttribute as CFString,
            kCFBooleanTrue
        )
        return Self.canProceedAfterManualAccessibility(
            setResult: result,
            isEnabled: boolAttribute(
                application,
                Self.manualAccessibilityAttribute
            )
        )
    }

    private func standardWindows(processIdentifier: pid_t) -> [AXUIElement] {
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let value = copyAttribute(application, kAXWindowsAttribute as String) else {
            return []
        }
        return accessibilityElements(from: value).filter { window in
            stringAttribute(window, kAXRoleAttribute as String) == kAXWindowRole as String
                && stringAttribute(window, kAXSubroleAttribute as String)
                    == kAXStandardWindowSubrole as String
        }
    }

    private func isUniqueStandardWindow(
        _ window: AXUIElement,
        processIdentifier: pid_t
    ) -> Bool {
        let windows = standardWindows(processIdentifier: processIdentifier)
        return windows.count == 1 && CFEqual(windows[0], window)
    }

    private func diagnosticDescription(for match: DiscoveredControls) -> String {
        let window = windowAncestor(of: match.container)
        let containerFrame = frame(of: match.container)
        let windowFrame = window.flatMap(frame)
        let relativeY = containerFrame.flatMap { controlsFrame in
            windowFrame.map { windowFrame in
                (controlsFrame.midY - windowFrame.minY) / max(windowFrame.height, 1)
            }
        }
        let context = nearbyContext(around: match.container)
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(180)
        return [
            "windowTitle=\(window.map { stringAttribute($0, kAXTitleAttribute as String) } ?? "")",
            "windowRole=\(window.map { stringAttribute($0, kAXRoleAttribute as String) } ?? "")",
            "windowSubrole=\(window.map { stringAttribute($0, kAXSubroleAttribute as String) } ?? "")",
            "windowMain=\(window.map { boolAttribute($0, kAXMainAttribute as String) } ?? false)",
            "windowFocused=\(window.map { boolAttribute($0, kAXFocusedAttribute as String) } ?? false)",
            "windowMinimized=\(window.map { boolAttribute($0, kAXMinimizedAttribute as String) } ?? false)",
            "windowVisible=\(window.map(isVisible) ?? false)",
            "containerVisible=\(isVisible(match.container))",
            "containerFrame=\(frameDescription(containerFrame))",
            "windowFrame=\(frameDescription(windowFrame))",
            "relativeY=\(relativeY.map { String(format: "%.3f", $0) } ?? "nil")",
            "context=\(context)"
        ].joined(separator: ",")
    }

    private func candidateFacts(for controls: CachedControls) -> CandidateFacts {
        let window = windowAncestor(of: controls.container)
        let controlsFrame = frame(of: controls.container)
        let windowFrame = window.flatMap(frame)
        let relativeY = controlsFrame.flatMap { controlsFrame in
            windowFrame.map { windowFrame in
                Double((controlsFrame.midY - windowFrame.minY) / max(windowFrame.height, 1))
            }
        }
        let controlsAreInsideWindow = controlsFrame.flatMap { controlsFrame in
            windowFrame.map { windowFrame in
                windowFrame.insetBy(dx: -1, dy: -1).contains(controlsFrame)
            }
        } ?? false
        let windowRole = window.map { stringAttribute($0, kAXRoleAttribute as String) } ?? ""
        let windowSubrole = window.map { stringAttribute($0, kAXSubroleAttribute as String) } ?? ""
        return CandidateFacts(
            windowIsNormal: windowRole == kAXWindowRole as String
                && windowSubrole == kAXStandardWindowSubrole as String,
            windowIsPrimary: window.map {
                boolAttribute($0, kAXMainAttribute as String)
                    || boolAttribute($0, kAXFocusedAttribute as String)
                    || isUniqueStandardWindow(
                        $0,
                        processIdentifier: controls.processIdentifier
                    )
            } ?? false,
            windowIsVisible: window.map(isVisible) ?? false,
            windowIsMinimized: window.map {
                boolAttribute($0, kAXMinimizedAttribute as String)
            } ?? true,
            containerIsVisible: isVisible(controls.container),
            controlsAreEnabled: [controls.previous, controls.playPause, controls.next]
                .allSatisfy { supportsPress($0) && isEnabled($0) },
            controlsAreInsideWindow: controlsAreInsideWindow,
            relativeY: relativeY,
            hasPlaybackTimeContext: hasPlaybackTimeContext(around: controls.container)
        )
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

    private func windowAncestor(of element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<24 {
            guard let candidate = current else { return nil }
            if stringAttribute(candidate, kAXRoleAttribute as String) == kAXWindowRole as String {
                return candidate
            }
            guard let parent = copyAttribute(candidate, kAXParentAttribute as String),
                  CFGetTypeID(parent as CFTypeRef) == AXUIElementGetTypeID() else {
                return nil
            }
            current = (parent as! AXUIElement)
        }
        return nil
    }

    private func nearbyContext(around element: AXUIElement) -> String {
        var current: AXUIElement? = element
        for _ in 0..<3 {
            guard let candidate = current else { break }
            let texts = descendantTexts(in: candidate, maximumDepth: 2)
            if !texts.isEmpty { return texts.joined(separator: " | ") }
            guard let parent = copyAttribute(candidate, kAXParentAttribute as String),
                  CFGetTypeID(parent as CFTypeRef) == AXUIElementGetTypeID() else { break }
            current = (parent as! AXUIElement)
        }
        return ""
    }

    private func descendantTexts(in root: AXUIElement, maximumDepth: Int) -> [String] {
        var queue = [QueueItem(element: root, depth: 0)]
        var queueIndex = 0
        var visited = Set<ElementIdentity>()
        var texts: [String] = []
        while queueIndex < queue.count, visited.count < 300, texts.count < 20 {
            let item = queue[queueIndex]
            queueIndex += 1
            guard visited.insert(ElementIdentity(element: item.element)).inserted else { continue }
            for attribute in [
                kAXTitleAttribute as String,
                kAXValueAttribute as String,
                kAXDescriptionAttribute as String
            ] {
                let text = stringAttribute(item.element, attribute)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty, !texts.contains(text) { texts.append(text) }
            }
            guard item.depth < maximumDepth else { continue }
            for child in children(of: item.element) {
                queue.append(QueueItem(element: child, depth: item.depth + 1))
            }
        }
        return texts
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

    private func frameDescription(_ frame: CGRect?) -> String {
        guard let frame else { return "nil" }
        return String(
            format: "%.1f:%.1f:%.1f:%.1f",
            frame.origin.x,
            frame.origin.y,
            frame.width,
            frame.height
        )
    }

    private func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        guard let value = copyAttribute(element, attribute) else { return false }
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return false
    }

    private func isVisible(_ element: AXUIElement) -> Bool {
        if boolAttribute(element, "AXHidden") { return false }
        if let value = copyAttribute(element, "AXVisible") {
            if let visible = value as? Bool { return visible }
            if let visible = value as? NSNumber { return visible.boolValue }
        }
        guard let frame = frame(of: element) else { return false }
        return frame.width > 0 && frame.height > 0
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
