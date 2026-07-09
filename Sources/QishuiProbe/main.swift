import AppKit
import ApplicationServices
import Foundation

struct ProbeConfig {
    var bundleIdentifier = "com.soda.music"
    var appName = "汽水音乐"
    var maxDepth = 8
    var maxChildrenPerNode = 80
    var includeFullTree = true
    var includeAttributeNames = true
    var includeSystemExtras = true
    var openNowPlayingPopover = false
    var includeAX = true
    var includeCGWindows = true
    var includeRuntimeIPC = true
    var includeStaticAsar = true
    var includeMediaRemote = false
    var promptForAccessibility = false
    var maxStaticMatchesPerCategory = 24
}

struct Candidate {
    let path: String
    let role: String
    let title: String
    let value: String
    let description: String
    let actions: [String]

    var hasUsefulText: Bool {
        [title, value, description].contains { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count >= 2
        }
    }

    var isButtonLike: Bool {
        role.localizedCaseInsensitiveContains("button") || !actions.isEmpty
    }

    var isImageLike: Bool {
        role.localizedCaseInsensitiveContains("image")
    }
}

final class AXProbe {
    private let config: ProbeConfig
    private var candidates: [Candidate] = []
    private var visited = Set<ObjectIdentifierBox>()

    init(config: ProbeConfig) {
        self.config = config
    }

    func run() {
        printHeader()

        let isTrusted = accessibilityTrusted()
        print("accessibilityTrusted=\(isTrusted)")

        guard let app = locateTargetApplication() else {
            print("status=not_running")
            print("Open \(config.appName) first, then run: swift run QishuiProbe")
            print("")
            if config.includeStaticAsar {
                printStaticAsarScan(bundleURL: defaultBundleURL())
            }
            return
        }

        print("status=running")
        print("pid=\(app.processIdentifier)")
        print("localizedName=\(app.localizedName ?? "")")
        print("bundleIdentifier=\(app.bundleIdentifier ?? "")")
        print("bundleURL=\(app.bundleURL?.path ?? "")")
        print("executableURL=\(app.executableURL?.path ?? "")")
        print("")

        if config.includeRuntimeIPC {
            printRuntimeIPC(for: app)
            print("")
        }

        if config.includeCGWindows {
            printCoreGraphicsWindows(for: app)
            print("")
        }

        if config.includeMediaRemote {
            MediaRemoteProbe().run()
            print("")
        }

        guard config.includeAX else {
            if config.includeStaticAsar {
                printStaticAsarScan(bundleURL: app.bundleURL ?? defaultBundleURL())
            }
            return
        }

        guard isTrusted else {
            print("AX_SKIPPED")
            print("Grant Accessibility permission to the launching app, then run again.")
            print("")
            if config.includeStaticAsar {
                printStaticAsarScan(bundleURL: app.bundleURL ?? defaultBundleURL())
            }
            return
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        dumpApplication(appElement)
        if config.includeSystemExtras {
            dumpSystemAccessibilityReferences()
        }
        printSummary()

        if config.includeStaticAsar {
            print("")
            printStaticAsarScan(bundleURL: app.bundleURL ?? defaultBundleURL())
        }
    }

    private func printHeader() {
        print("QishuiProbe")
        print("timestamp=\(ISO8601DateFormatter().string(from: Date()))")
        print("targetBundleIdentifier=\(config.bundleIdentifier)")
        print("targetAppName=\(config.appName)")
        print("maxDepth=\(config.maxDepth)")
        print("")
    }

    private func locateTargetApplication() -> NSRunningApplication? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: config.bundleIdentifier).first {
            return app
        }

        return NSWorkspace.shared.runningApplications.first { app in
            let name = app.localizedName ?? ""
            let bundleID = app.bundleIdentifier ?? ""
            return name.contains(config.appName)
                || bundleID == config.bundleIdentifier
                || bundleID.localizedCaseInsensitiveContains("soda")
        }
    }

    private func accessibilityTrusted() -> Bool {
        if config.promptForAccessibility {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    private func defaultBundleURL() -> URL {
        URL(fileURLWithPath: "/Applications/\(config.appName).app")
    }

    private func dumpApplication(_ appElement: AXUIElement) {
        print("APPLICATION")
        dumpNode(appElement, path: "app", depth: config.maxDepth)
        print("")

        dumpSpecialReferences(
            owner: "app",
            element: appElement,
            attributes: [
                kAXMenuBarAttribute as String,
                "AXExtrasMenuBar",
                kAXFocusedWindowAttribute as String,
                kAXFocusedUIElementAttribute as String,
                kAXChildrenAttribute as String
            ]
        )
        print("")

        if let windows = copyAttribute(appElement, kAXWindowsAttribute) as? [AXUIElement], !windows.isEmpty {
            print("windows=\(windows.count)")
            for (index, window) in windows.enumerated() {
                print("")
                print("WINDOW[\(index)]")
                dumpNode(window, path: "window[\(index)]", depth: 0)
            }
        } else {
            print("windows=0")
        }
    }

    private func dumpSystemAccessibilityReferences() {
        print("")
        print("SYSTEM_ACCESSIBILITY")

        let systemWideElement = AXUIElementCreateSystemWide()
        dumpSpecialReferences(
            owner: "system",
            element: systemWideElement,
            attributes: [
                "AXFocusedApplication",
                kAXFocusedWindowAttribute as String,
                kAXFocusedUIElementAttribute as String,
                kAXMenuBarAttribute as String,
                "AXExtrasMenuBar"
            ]
        )

        let systemUIServerApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemuiserver")
        guard let systemUIServer = systemUIServerApps.first else {
            print("")
            print("systemUIServer=not_running")
            return
        }

        print("")
        print("SYSTEM_UI_SERVER")
        print("pid=\(systemUIServer.processIdentifier)")
        let systemUIServerElement = AXUIElementCreateApplication(systemUIServer.processIdentifier)
        dumpNode(systemUIServerElement, path: "systemUIServer.app", depth: config.maxDepth)
        dumpSpecialReferences(
            owner: "systemUIServer",
            element: systemUIServerElement,
            attributes: [
                kAXMenuBarAttribute as String,
                "AXExtrasMenuBar",
                kAXFocusedWindowAttribute as String,
                kAXFocusedUIElementAttribute as String,
                kAXChildrenAttribute as String
            ]
        )

        let controlCenterApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter")
        guard let controlCenter = controlCenterApps.first else {
            print("")
            print("controlCenter=not_running")
            return
        }

        print("")
        print("CONTROL_CENTER")
        print("pid=\(controlCenter.processIdentifier)")
        let controlCenterElement = AXUIElementCreateApplication(controlCenter.processIdentifier)
        dumpNode(controlCenterElement, path: "controlCenter.app", depth: config.maxDepth)
        dumpSpecialReferences(
            owner: "controlCenter",
            element: controlCenterElement,
            attributes: [
                kAXWindowsAttribute as String,
                kAXMenuBarAttribute as String,
                "AXExtrasMenuBar",
                kAXFocusedWindowAttribute as String,
                kAXFocusedUIElementAttribute as String,
                kAXChildrenAttribute as String
            ]
        )

        if config.openNowPlayingPopover {
            dumpNowPlayingPopover(controlCenterElement: controlCenterElement)
        }
    }

    private func dumpNowPlayingPopover(controlCenterElement: AXUIElement) {
        print("")
        print("NOW_PLAYING_POPOVER")

        guard let nowPlayingButton = findElement(
            in: controlCenterElement,
            maxDepth: 5,
            matches: { element in
                let identifier = stringAttribute(element, "AXIdentifier")
                let description = stringAttribute(element, kAXDescriptionAttribute)
                return identifier == "com.apple.menuextra.now-playing"
                    || description.localizedCaseInsensitiveContains("播放中")
                    || description.localizedCaseInsensitiveContains("now playing")
            }
        ) else {
            print("nowPlayingButton=not_found")
            return
        }

        let pressResult = AXUIElementPerformAction(nowPlayingButton, kAXPressAction as CFString)
        print("pressResult=\(pressResult.rawValue)")
        usleep(600_000)

        dumpSpecialReferences(
            owner: "controlCenter.nowPlayingOpen",
            element: controlCenterElement,
            attributes: [
                kAXWindowsAttribute as String,
                kAXFocusedWindowAttribute as String,
                kAXFocusedUIElementAttribute as String,
                kAXChildrenAttribute as String
            ]
        )

        let cancelResult = AXUIElementPerformAction(nowPlayingButton, kAXCancelAction as CFString)
        print("cancelResult=\(cancelResult.rawValue)")
        postEscapeKey()
    }

    private func dumpSpecialReferences(owner: String, element: AXUIElement, attributes: [String]) {
        print("AX_REFERENCES[\(owner)]")

        var foundAny = false
        for attribute in attributes {
            guard let value = copyAttribute(element, attribute) else {
                continue
            }
            foundAny = true

            if let array = value as? [Any] {
                print("- \(owner).\(attribute) count=\(array.count)")
                for (index, item) in array.prefix(config.maxChildrenPerNode).enumerated() {
                    guard CFGetTypeID(item as CFTypeRef) == AXUIElementGetTypeID() else {
                        print("  - \(owner).\(attribute)[\(index)] value=\(quote(String(describing: item)))")
                        continue
                    }
                    dumpNode(item as! AXUIElement, path: "\(owner).\(attribute)[\(index)]", depth: 0)
                }
                if array.count > config.maxChildrenPerNode {
                    print("  - ... skipped \(array.count - config.maxChildrenPerNode) values")
                }
            } else if CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() {
                print("- \(owner).\(attribute) element=true")
                dumpNode(value as! AXUIElement, path: "\(owner).\(attribute)", depth: 0)
            } else {
                print("- \(owner).\(attribute) value=\(quote(String(describing: value)))")
            }
        }

        if !foundAny {
            print("- none")
        }
    }

    private func dumpNode(_ element: AXUIElement, path: String, depth: Int) {
        guard depth <= config.maxDepth else { return }

        let elementHash = CFHash(element)
        if visited.contains(ObjectIdentifierBox(raw: elementHash)) {
            if config.includeFullTree {
                let indent = String(repeating: "  ", count: depth)
                print("\(indent)- \(path) visited=true")
            }
            return
        }
        visited.insert(ObjectIdentifierBox(raw: elementHash))

        let role = stringAttribute(element, kAXRoleAttribute)
        let title = stringAttribute(element, kAXTitleAttribute)
        let value = stringAttribute(element, kAXValueAttribute)
        let description = stringAttribute(element, kAXDescriptionAttribute)
        let identifier = stringAttribute(element, "AXIdentifier")
        let enabled = boolAttribute(element, kAXEnabledAttribute)
        let actions = actionNames(element)
        let frame = frameDescription(element)
        let attributeNames = includeAttributeNames(element)

        let candidate = Candidate(
            path: path,
            role: role,
            title: title,
            value: value,
            description: description,
            actions: actions
        )
        if candidate.hasUsefulText || candidate.isButtonLike || candidate.isImageLike {
            candidates.append(candidate)
        }

        if config.includeFullTree {
            let indent = String(repeating: "  ", count: depth)
            var parts: [String] = []
            if !role.isEmpty { parts.append("role=\(quote(role))") }
            if !title.isEmpty { parts.append("title=\(quote(title))") }
            if !value.isEmpty { parts.append("value=\(quote(value))") }
            if !description.isEmpty { parts.append("desc=\(quote(description))") }
            if !identifier.isEmpty { parts.append("id=\(quote(identifier))") }
            if let enabled { parts.append("enabled=\(enabled)") }
            if !actions.isEmpty { parts.append("actions=\(actions.joined(separator: ","))") }
            if !frame.isEmpty { parts.append("frame=\(frame)") }
            if config.includeAttributeNames, !attributeNames.isEmpty {
                parts.append("attrs=\(attributeNames.joined(separator: ","))")
            }
            print("\(indent)- \(path) \(parts.joined(separator: " "))")
        }

        guard shouldDescendIntoChildren(role: role, title: title, path: path) else {
            return
        }

        let children = childElements(element)
        guard !children.isEmpty else {
            return
        }

        for (index, child) in children.prefix(config.maxChildrenPerNode).enumerated() {
            dumpNode(child, path: "\(path).child[\(index)]", depth: depth + 1)
        }

        if children.count > config.maxChildrenPerNode {
            let indent = String(repeating: "  ", count: depth + 1)
            print("\(indent)- ... skipped \(children.count - config.maxChildrenPerNode) children")
        }
    }

    private func printSummary() {
        print("")
        print("SUMMARY")

        let textCandidates = candidates
            .filter(\.hasUsefulText)
            .prefix(80)
        print("")
        print("textCandidates=\(textCandidates.count)")
        for item in textCandidates {
            print("- path=\(item.path) role=\(quote(item.role)) title=\(quote(item.title)) value=\(quote(item.value)) desc=\(quote(item.description))")
        }

        let buttons = candidates
            .filter(\.isButtonLike)
            .prefix(80)
        print("")
        print("buttonCandidates=\(buttons.count)")
        for item in buttons {
            print("- path=\(item.path) role=\(quote(item.role)) title=\(quote(item.title)) desc=\(quote(item.description)) actions=\(item.actions.joined(separator: ","))")
        }

        let images = candidates
            .filter(\.isImageLike)
            .prefix(40)
        print("")
        print("imageCandidates=\(images.count)")
        for item in images {
            print("- path=\(item.path) role=\(quote(item.role)) title=\(quote(item.title)) desc=\(quote(item.description))")
        }
    }

    private func printCoreGraphicsWindows(for app: NSRunningApplication) {
        guard let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            print("cgWindows=unavailable")
            return
        }

        let candidates = windows.filter { window in
            let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            return ownerPID == app.processIdentifier
                || owner == app.localizedName
                || owner.contains(config.appName)
                || owner.localizedCaseInsensitiveContains("soda")
        }

        print("cgWindows=\(candidates.count)")
        for (index, window) in candidates.enumerated() {
            let windowID = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let name = window[kCGWindowName as String] as? String ?? ""
            let layer = window[kCGWindowLayer as String] ?? ""
            let alpha = window[kCGWindowAlpha as String] ?? ""
            let sharing = window[kCGWindowSharingState as String] ?? ""
            let onscreen = window[kCGWindowIsOnscreen as String] ?? ""
            let bounds = window[kCGWindowBounds as String] ?? [:]
            print("- cgWindow[\(index)] id=\(windowID) ownerPID=\(ownerPID) owner=\(quote(owner)) name=\(quote(name)) layer=\(layer) alpha=\(alpha) sharing=\(sharing) onscreen=\(onscreen) bounds=\(bounds)")
        }
    }

    private func printRuntimeIPC(for app: NSRunningApplication) {
        print("RUNTIME_PROCESS_AND_IPC")

        let rows = processRows()
        let pids = processTreePIDs(rootPID: app.processIdentifier, rows: rows)
        let discoveredRows = pids.compactMap { pid in
            rows.first(where: { $0.pid == pid }) ?? processRow(pid: pid)
        }
        print("processTreePIDs=\(pids.map(String.init).joined(separator: ","))")

        for row in discoveredRows {
            print("- process pid=\(row.pid) ppid=\(row.ppid) args=\(quote(row.args))")
        }

        let runtimeHints = discoveredRows.flatMap { protocolHints(in: $0.args) }
        print("")
        print("runtimeProtocolHints=\(runtimeHints.count)")
        for hint in Array(runtimeHints.prefix(80)) {
            print("- \(hint)")
        }

        print("")
        print("runtimeNetworkSockets")
        for pid in pids {
            let output = runProcess("/usr/sbin/lsof", arguments: ["-n", "-P", "-a", "-p", "\(pid)", "-i"], timeoutSeconds: 12)
            if output.hasPrefix("process_timeout") || output.hasPrefix("process_error") {
                print("- pid=\(pid) networkSockets=unavailable \(output)")
                continue
            }
            let lines = output.splitLines().dropFirst().filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if lines.isEmpty {
                print("- pid=\(pid) networkSockets=0")
            } else {
                print("- pid=\(pid) networkSockets=\(lines.count)")
                for line in lines.prefix(40) {
                    print("  \(line)")
                }
            }
        }

        print("")
        print("runtimeLocalStorageAndIPCFiles")
        for pid in pids {
            let output = runProcess("/usr/sbin/lsof", arguments: ["-n", "-P", "-p", "\(pid)"], timeoutSeconds: 12)
            if output.hasPrefix("process_timeout") || output.hasPrefix("process_error") {
                print("- pid=\(pid) ipcOrStorageHints=unavailable \(output)")
                continue
            }
            let interesting = output.splitLines().filter { line in
                let lower = line.lowercased()
                return lower.contains("local storage")
                    || lower.contains("leveldb")
                    || lower.contains("webstorage")
                    || lower.contains("indexeddb")
                    || lower.contains("sodamusic")
                    || lower.contains("singleton")
                    || lower.contains(".sock")
                    || lower.contains("socket")
                    || lower.contains("pipe")
                    || lower.contains("unix")
            }

            print("- pid=\(pid) ipcOrStorageHints=\(interesting.count)")
            for line in interesting.prefix(60) {
                print("  \(line)")
            }
        }
    }

    private func printStaticAsarScan(bundleURL: URL) {
        print("STATIC_ASAR_SCAN")
        let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources")
        print("resourcesPath=\(resourcesURL.path)")

        let asarNames = [
            "app.asar",
            "app-arm64.asar",
            "app-x64.asar",
            "main.asar",
            "desktopLyrics.asar"
        ]

        let categories: [(name: String, keywords: [String])] = [
            ("ipc", ["ipcMain", "ipcRenderer", "contextBridge", "webContents.send", ".invoke(", ".handle(", "preload"]),
            ("protocols_ports", ["registerSchemesAsPrivileged", "registerFileProtocol", "registerProtocol", "protocol.handle", "standard-schemes", "secure-schemes", "app://", "soda://", "luna://", "localhost", "127.0.0.1", "port"]),
            ("tray_status", ["Tray", "tray", "StatusItem", "status", "menubar", "Menu", "setContextMenu", "showMenu"]),
            ("lyrics", ["desktopLyrics", "lyrics", "lyric", "toggleDesktopLyrics", "setLyricsClickable", "updateHeight", "isLocked"]),
            ("transport", ["togglePlay", "playNext", "playPrevious", "userNext", "userPrevious", "isPlaying", "queue", "player"]),
            ("shared_state_storage", ["sharedState", "localStorage", "LocalStorage", "indexedDB", "leveldb", "Ue(\"player\")", "Ue(\"queue\")", "Ue(\"desktopLyrics\")", "desktopLyrics\",", "player\","])
        ]

        for name in asarNames {
            let url = resourcesURL.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("")
                print("ASAR \(name) missing")
                continue
            }

            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            print("")
            print("ASAR \(name) size=\(size)")

            let stringsOutput = runProcess("/usr/bin/strings", arguments: ["-a", url.path], timeoutSeconds: 12)
            guard !stringsOutput.isEmpty else {
                print("- strings=empty_or_unavailable")
                continue
            }

            for category in categories {
                let matches = snippets(in: stringsOutput, keywords: category.keywords, limit: config.maxStaticMatchesPerCategory)
                print("- \(category.name)=\(matches.count)")
                for match in matches {
                    print("  [\(match.keyword)] \(quote(match.snippet))")
                }
            }
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

    private func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        copyAttribute(element, attribute) as? Bool
    }

    private func actionNames(_ element: AXUIElement) -> [String] {
        var actions: CFArray?
        let result = AXUIElementCopyActionNames(element, &actions)
        guard result == .success, let actions else { return [] }
        return (actions as? [String]) ?? []
    }

    private func includeAttributeNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        let result = AXUIElementCopyAttributeNames(element, &names)
        guard result == .success, let names else { return [] }
        return ((names as? [String]) ?? []).sorted()
    }

    private func childElements(_ element: AXUIElement) -> [AXUIElement] {
        let childAttributes = [
            kAXChildrenAttribute,
            "AXVisibleChildren",
            "AXChildrenInNavigationOrder",
            "AXContents",
            "AXRows",
            "AXColumns",
            "AXTabs",
            "AXMenuBar",
            "AXExtrasMenuBar",
            "AXSections",
            "AXTitleUIElement",
            "AXLinkedUIElements",
            "AXFocusedUIElement",
            "AXFocusedWindow",
            "AXMainWindow",
            "AXToolbarButton",
            "AXStatusItem",
            "AXCloseButton",
            "AXMinimizeButton",
            "AXZoomButton",
            "AXFullScreenButton"
        ]

        var children: [AXUIElement] = []
        for attribute in childAttributes {
            guard let value = copyAttribute(element, attribute) else { continue }

            if let array = value as? [Any] {
                for item in array {
                    if CFGetTypeID(item as CFTypeRef) == AXUIElementGetTypeID() {
                        children.append(item as! AXUIElement)
                    }
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

    private func frameDescription(_ element: AXUIElement) -> String {
        guard let positionValue = copyAttribute(element, kAXPositionAttribute),
              let sizeValue = copyAttribute(element, kAXSizeAttribute) else {
            return ""
        }

        guard CFGetTypeID(positionValue as CFTypeRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue as CFTypeRef) == AXValueGetTypeID() else {
            return ""
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return "x:\(Int(point.x)),y:\(Int(point.y)),w:\(Int(size.width)),h:\(Int(size.height))"
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

    private func postEscapeKey() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false) else {
            return
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func shouldDescendIntoChildren(role: String, title: String, path: String) -> Bool {
        if role == "AXMenuBarItem", title == "Apple" {
            return false
        }

        if path.contains(".AXMenuBar.child[0]") || path.contains(".AXChildren[1].child[0]") {
            return false
        }

        return true
    }

    private func processRows() -> [ProcessRow] {
        let output = runProcess("/bin/ps", arguments: ["-wwaxo", "pid,ppid,args"])
        return output.splitLines().dropFirst().compactMap(parseProcessRow)
    }

    private func processRow(pid: pid_t) -> ProcessRow? {
        let output = runProcess("/bin/ps", arguments: ["-wwp", "\(pid)", "-o", "pid=", "-o", "ppid=", "-o", "args="])
        return output.splitLines().compactMap(parseProcessRow).first
    }

    private func parseProcessRow(_ line: String) -> ProcessRow? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 3,
              let pidInt = Int32(String(parts[0])),
              let ppidInt = Int32(String(parts[1])) else {
            return nil
        }
        return ProcessRow(pid: pidInt, ppid: ppidInt, args: String(parts[2]))
    }

    private func processTreePIDs(rootPID: pid_t, rows: [ProcessRow]) -> [pid_t] {
        var result = Set<pid_t>([rootPID])
        var changed = true

        while changed {
            changed = false
            for row in rows where result.contains(row.ppid) && !result.contains(row.pid) {
                result.insert(row.pid)
                changed = true
            }

            for pid in Array(result) {
                let output = runProcess("/usr/bin/pgrep", arguments: ["-P", "\(pid)"], timeoutSeconds: 2)
                for line in output.splitLines() {
                    if let child = Int32(line.trimmingCharacters(in: .whitespacesAndNewlines)),
                       !result.contains(child) {
                        result.insert(child)
                        changed = true
                    }
                }
            }
        }

        return result.sorted()
    }

    private func protocolHints(in args: String) -> [String] {
        let tokens = args.split(separator: " ").map(String.init)
        let interestingPrefixes = [
            "--standard-schemes=",
            "--secure-schemes=",
            "--cors-schemes=",
            "--fetch-schemes=",
            "--service-worker-schemes=",
            "--app-path=",
            "--user-data-dir=",
            "--remote-debugging-port=",
            "--inspect",
            "--port="
        ]

        return tokens.filter { token in
            interestingPrefixes.contains { token.hasPrefix($0) }
                || token.localizedCaseInsensitiveContains("localhost")
                || token.contains("127.0.0.1")
                || token.localizedCaseInsensitiveContains("ipc")
        }
    }

    private func runProcess(_ executablePath: String, arguments: [String], timeoutSeconds: TimeInterval = 8) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                semaphore.signal()
            }

            if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
                process.terminate()
                return "process_timeout executable=\(executablePath) args=\(arguments.joined(separator: " ")) timeout=\(timeoutSeconds)s"
            }

            let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: stdoutData, as: UTF8.self)
            let errorOutput = String(decoding: stderrData, as: UTF8.self)
            return output + (errorOutput.isEmpty ? "" : "\n\(errorOutput)")
        } catch {
            return "process_error executable=\(executablePath) args=\(arguments.joined(separator: " ")) error=\(error)"
        }
    }

    private func snippets(in text: String, keywords: [String], limit: Int) -> [(keyword: String, snippet: String)] {
        var matches: [(keyword: String, snippet: String)] = []

        for keyword in keywords {
            var searchRange = text.startIndex..<text.endIndex
            var perKeyword = 0

            while let range = text.range(of: keyword, options: [.caseInsensitive], range: searchRange) {
                let lower = text.index(range.lowerBound, offsetBy: -120, limitedBy: text.startIndex) ?? text.startIndex
                let upper = text.index(range.upperBound, offsetBy: 220, limitedBy: text.endIndex) ?? text.endIndex
                var snippet = String(text[lower..<upper])
                snippet = snippet
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\r", with: " ")
                    .replacingOccurrences(of: "\t", with: " ")
                while snippet.contains("  ") {
                    snippet = snippet.replacingOccurrences(of: "  ", with: " ")
                }
                matches.append((keyword, snippet.trimmingCharacters(in: .whitespacesAndNewlines)))

                perKeyword += 1
                if matches.count >= limit || perKeyword >= 4 {
                    break
                }

                searchRange = range.upperBound..<text.endIndex
            }

            if matches.count >= limit {
                break
            }
        }

        return matches
    }

    private func quote(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: " ")
        return "\"\(cleaned)\""
    }
}

struct ObjectIdentifierBox: Hashable {
    let raw: CFHashCode
}

struct ProcessRow {
    let pid: pid_t
    let ppid: pid_t
    let args: String
}

final class MediaRemoteProbe {
    private typealias NowPlayingInfoCallback = @convention(block) (CFDictionary?) -> Void
    private typealias GetNowPlayingInfo = @convention(c) (DispatchQueue, @escaping NowPlayingInfoCallback) -> Void
    private typealias LocalOriginCallback = @convention(block) (UnsafeRawPointer?) -> Void
    private typealias GetLocalOrigin = @convention(c) (DispatchQueue, @escaping LocalOriginCallback) -> Void
    private typealias GetNowPlayingInfoForOrigin = @convention(c) (UnsafeRawPointer, DispatchQueue, @escaping NowPlayingInfoCallback) -> Void
    private typealias NowPlayingClientCallback = @convention(block) (UnsafeRawPointer?) -> Void
    private typealias GetNowPlayingClient = @convention(c) (DispatchQueue, @escaping NowPlayingClientCallback) -> Void
    private typealias GetNowPlayingInfoForClient = @convention(c) (UnsafeRawPointer, DispatchQueue, @escaping NowPlayingInfoCallback) -> Void
    private typealias IsPlayingCallback = @convention(block) (Bool) -> Void
    private typealias GetNowPlayingApplicationIsPlaying = @convention(c) (DispatchQueue, @escaping IsPlayingCallback) -> Void
    private typealias PlaybackStateCallback = @convention(block) (UInt32) -> Void
    private typealias GetNowPlayingApplicationPlaybackState = @convention(c) (DispatchQueue, @escaping PlaybackStateCallback) -> Void
    private typealias PIDCallback = @convention(block) (pid_t) -> Void
    private typealias GetNowPlayingApplicationPID = @convention(c) (DispatchQueue, @escaping PIDCallback) -> Void
    private typealias DisplayIDCallback = @convention(block) (CFString?) -> Void
    private typealias GetNowPlayingApplicationDisplayID = @convention(c) (DispatchQueue, @escaping DisplayIDCallback) -> Void

    func run() {
        print("MEDIA_REMOTE")
        print("privateAPI=true")

        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else {
            print("status=unavailable")
            if let error = dlerror() {
                print("dlopenError=\(String(cString: error))")
            }
            return
        }

        print("status=loaded")
        printIsPlaying(handle: handle)
        printPlaybackState(handle: handle)
        printApplicationPID(handle: handle)
        printApplicationDisplayID(handle: handle)
        printNowPlayingInfo(handle: handle)
        printNowPlayingInfoForClient(handle: handle)
        printNowPlayingInfoForLocalOrigin(handle: handle)
    }

    private func printIsPlaying(handle: UnsafeMutableRawPointer) {
        guard let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") else {
            print("isPlayingSymbol=missing")
            return
        }

        let function = unsafeBitCast(symbol, to: GetNowPlayingApplicationIsPlaying.self)
        let semaphore = DispatchSemaphore(value: 0)
        var received: Bool?

        function(DispatchQueue.global(qos: .userInitiated)) { isPlaying in
            received = isPlaying
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 2) == .success {
            print("isPlaying=\(received.map(String.init) ?? "unknown")")
        } else {
            print("isPlaying=timeout")
        }
    }

    private func printPlaybackState(handle: UnsafeMutableRawPointer) {
        guard let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPlaybackState") else {
            print("playbackStateSymbol=missing")
            return
        }

        let function = unsafeBitCast(symbol, to: GetNowPlayingApplicationPlaybackState.self)
        let semaphore = DispatchSemaphore(value: 0)
        var received: UInt32?

        function(DispatchQueue.global(qos: .userInitiated)) { playbackState in
            received = playbackState
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 2) == .success {
            print("playbackState=\(received.map(String.init) ?? "unknown")")
        } else {
            print("playbackState=timeout")
        }
    }

    private func printApplicationPID(handle: UnsafeMutableRawPointer) {
        guard let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") else {
            print("applicationPIDSymbol=missing")
            return
        }

        let function = unsafeBitCast(symbol, to: GetNowPlayingApplicationPID.self)
        let semaphore = DispatchSemaphore(value: 0)
        var received: pid_t?

        function(DispatchQueue.global(qos: .userInitiated)) { pid in
            received = pid
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 2) == .success {
            print("applicationPID=\(received.map(String.init) ?? "unknown")")
        } else {
            print("applicationPID=timeout")
        }
    }

    private func printApplicationDisplayID(handle: UnsafeMutableRawPointer) {
        guard let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationDisplayID") else {
            print("applicationDisplayIDSymbol=missing")
            return
        }

        let function = unsafeBitCast(symbol, to: GetNowPlayingApplicationDisplayID.self)
        let semaphore = DispatchSemaphore(value: 0)
        var received: String?

        function(DispatchQueue.global(qos: .userInitiated)) { displayID in
            received = displayID as String?
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 2) == .success {
            print("applicationDisplayID=\(received ?? "nil")")
        } else {
            print("applicationDisplayID=timeout")
        }
    }

    private func printNowPlayingInfo(handle: UnsafeMutableRawPointer) {
        guard let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else {
            print("nowPlayingInfoSymbol=missing")
            return
        }

        let function = unsafeBitCast(symbol, to: GetNowPlayingInfo.self)
        let semaphore = DispatchSemaphore(value: 0)
        var received: NSDictionary?

        function(DispatchQueue.global(qos: .userInitiated)) { info in
            received = info as NSDictionary?
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + 2) == .success else {
            print("nowPlayingInfo=timeout")
            return
        }

        guard let received else {
            print("nowPlayingInfo=nil")
            return
        }

        print("nowPlayingInfoKeys=\(received.allKeys.count)")
        let fields = [
            "kMRMediaRemoteNowPlayingInfoTitle": "title",
            "kMRMediaRemoteNowPlayingInfoArtist": "artist",
            "kMRMediaRemoteNowPlayingInfoAlbum": "album",
            "kMRMediaRemoteNowPlayingInfoDuration": "duration",
            "kMRMediaRemoteNowPlayingInfoElapsedTime": "elapsedTime",
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": "playbackRate",
            "kMRMediaRemoteNowPlayingInfoBundleIdentifier": "bundleIdentifier",
            "kMRMediaRemoteNowPlayingInfoArtworkData": "artworkData"
        ]

        for (key, label) in fields {
            guard let value = received[key] else { continue }
            if let data = value as? Data {
                print("\(label)=<data \(data.count) bytes>")
            } else {
                print("\(label)=\(quoteValue(value))")
            }
        }
    }

    private func printNowPlayingInfoForClient(handle: UnsafeMutableRawPointer) {
        guard let clientSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingClient") else {
            print("nowPlayingClientSymbol=missing")
            return
        }
        guard let infoSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfoForClient") else {
            print("nowPlayingInfoForClientSymbol=missing")
            return
        }

        let getClient = unsafeBitCast(clientSymbol, to: GetNowPlayingClient.self)
        let getInfoForClient = unsafeBitCast(infoSymbol, to: GetNowPlayingInfoForClient.self)

        let clientSemaphore = DispatchSemaphore(value: 0)
        var client: UnsafeRawPointer?
        getClient(DispatchQueue.global(qos: .userInitiated)) { receivedClient in
            client = receivedClient
            clientSemaphore.signal()
        }

        guard clientSemaphore.wait(timeout: .now() + 2) == .success, let client else {
            print("nowPlayingClient=nil")
            return
        }
        print("nowPlayingClient=\(client)")

        let infoSemaphore = DispatchSemaphore(value: 0)
        var received: NSDictionary?
        getInfoForClient(client, DispatchQueue.global(qos: .userInitiated)) { info in
            received = info as NSDictionary?
            infoSemaphore.signal()
        }

        guard infoSemaphore.wait(timeout: .now() + 2) == .success else {
            print("nowPlayingInfoForClient=timeout")
            return
        }

        guard let received else {
            print("nowPlayingInfoForClient=nil")
            return
        }

        print("nowPlayingInfoForClientKeys=\(received.allKeys.count)")
        printNowPlayingFields(received)
    }

    private func printNowPlayingInfoForLocalOrigin(handle: UnsafeMutableRawPointer) {
        guard let localOriginSymbol = dlsym(handle, "MRMediaRemoteGetLocalOrigin") else {
            print("localOriginSymbol=missing")
            return
        }
        guard let infoSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfoForOrigin") else {
            print("nowPlayingInfoForOriginSymbol=missing")
            return
        }

        let getLocalOrigin = unsafeBitCast(localOriginSymbol, to: GetLocalOrigin.self)
        let getInfoForOrigin = unsafeBitCast(infoSymbol, to: GetNowPlayingInfoForOrigin.self)

        let originSemaphore = DispatchSemaphore(value: 0)
        var origin: UnsafeRawPointer?
        getLocalOrigin(DispatchQueue.global(qos: .userInitiated)) { receivedOrigin in
            origin = receivedOrigin
            originSemaphore.signal()
        }

        guard originSemaphore.wait(timeout: .now() + 2) == .success, let origin else {
            print("localOrigin=nil")
            return
        }

        let infoSemaphore = DispatchSemaphore(value: 0)
        var received: NSDictionary?
        getInfoForOrigin(origin, DispatchQueue.global(qos: .userInitiated)) { info in
            received = info as NSDictionary?
            infoSemaphore.signal()
        }

        guard infoSemaphore.wait(timeout: .now() + 2) == .success else {
            print("nowPlayingInfoForOrigin=timeout")
            return
        }

        guard let received else {
            print("nowPlayingInfoForOrigin=nil")
            return
        }

        print("nowPlayingInfoForOriginKeys=\(received.allKeys.count)")
        printNowPlayingFields(received)
    }

    private func printNowPlayingFields(_ received: NSDictionary) {
        let fields = [
            "kMRMediaRemoteNowPlayingInfoTitle": "title",
            "kMRMediaRemoteNowPlayingInfoArtist": "artist",
            "kMRMediaRemoteNowPlayingInfoAlbum": "album",
            "kMRMediaRemoteNowPlayingInfoDuration": "duration",
            "kMRMediaRemoteNowPlayingInfoElapsedTime": "elapsedTime",
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": "playbackRate",
            "kMRMediaRemoteNowPlayingInfoBundleIdentifier": "bundleIdentifier",
            "kMRMediaRemoteNowPlayingInfoArtworkData": "artworkData"
        ]

        for (key, label) in fields {
            guard let value = received[key] else { continue }
            if let data = value as? Data {
                print("\(label)=<data \(data.count) bytes>")
            } else {
                print("\(label)=\(quoteValue(value))")
            }
        }
    }

    private func quoteValue(_ value: Any) -> String {
        let text = String(describing: value)
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        return "\"\(text)\""
    }
}

private extension String {
    func splitLines() -> [String] {
        components(separatedBy: .newlines)
    }
}

let args = CommandLine.arguments
var config = ProbeConfig()

if let depthIndex = args.firstIndex(of: "--depth"),
   args.indices.contains(depthIndex + 1),
   let depth = Int(args[depthIndex + 1]) {
    config.maxDepth = depth
}

if let childrenIndex = args.firstIndex(of: "--children"),
   args.indices.contains(childrenIndex + 1),
   let maxChildren = Int(args[childrenIndex + 1]) {
    config.maxChildrenPerNode = maxChildren
}

if let bundleIndex = args.firstIndex(of: "--bundle-id"),
   args.indices.contains(bundleIndex + 1) {
    config.bundleIdentifier = args[bundleIndex + 1]
}

if let nameIndex = args.firstIndex(of: "--app-name"),
   args.indices.contains(nameIndex + 1) {
    config.appName = args[nameIndex + 1]
}

if args.contains("--summary-only") {
    config.includeFullTree = false
}

if args.contains("--system-extras") {
    config.includeSystemExtras = true
}

if args.contains("--open-now-playing") {
    config.includeSystemExtras = true
    config.openNowPlayingPopover = true
}

if args.contains("--media-remote") {
    config.includeMediaRemote = true
}

if args.contains("--prompt-accessibility") {
    config.promptForAccessibility = true
}

if args.contains("--no-system-extras") {
    config.includeSystemExtras = false
}

if args.contains("--no-ax") {
    config.includeAX = false
}

if args.contains("--no-cg") {
    config.includeCGWindows = false
}

if args.contains("--no-ipc") {
    config.includeRuntimeIPC = false
}

if args.contains("--no-static-asar") {
    config.includeStaticAsar = false
}

if args.contains("--ipc-only") {
    config.includeFullTree = false
    config.includeAX = false
    config.includeCGWindows = false
    config.includeSystemExtras = false
    config.includeStaticAsar = false
}

if args.contains("--static-asar-only") {
    config.includeFullTree = false
    config.includeAX = false
    config.includeCGWindows = false
    config.includeSystemExtras = false
    config.includeRuntimeIPC = false
}

AXProbe(config: config).run()
