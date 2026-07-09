import AppKit
import ApplicationServices
import Foundation

@MainActor
final class QishuiAXChangeMonitor {
    private let bundleIdentifier = "com.soda.music"
    private let axMessageTimeout: Float = 0.2
    private let debounceInterval: TimeInterval = 0.16
    private let reattachInterval: TimeInterval = 2.0
    private let maxObservedElements = 180
    private let maxObservationDepth = 6

    private var observer: AXObserver?
    private var observedElements: [AXUIElement] = []
    private var observedPID: pid_t?
    private var reattachTimer: Timer?
    private var debounceWorkItem: DispatchWorkItem?
    private var onChange: ((String) -> Void)?

    private let notifications = [
        "AXValueChanged",
        "AXTitleChanged",
        "AXFocusedUIElementChanged",
        "AXFocusedWindowChanged",
        "AXSelectedChildrenChanged",
        "AXSelectedRowsChanged",
        "AXLayoutChanged",
        "AXCreated",
        "AXUIElementDestroyed",
        "AXMoved",
        "AXResized"
    ]

    func start(onChange: @escaping (String) -> Void) {
        self.onChange = onChange
        refreshObservedTargets()
        reattachTimer?.invalidate()
        reattachTimer = Timer.scheduledTimer(withTimeInterval: reattachInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshObservedTargets(force: true)
            }
        }
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        reattachTimer?.invalidate()
        reattachTimer = nil
        tearDownObserver()
        onChange = nil
    }

    private func refreshObservedTargets(force: Bool = false) {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            tearDownObserver()
            return
        }

        if !force, observedPID == app.processIdentifier, observer != nil {
            return
        }

        tearDownObserver()

        var observerRef: AXObserver?
        let result = AXObserverCreate(app.processIdentifier, qishuiAXObserverCallback, &observerRef)
        guard result == .success, let observerRef else {
            return
        }

        observer = observerRef
        observedPID = app.processIdentifier
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, axMessageTimeout)
        let elements = observableElements(from: appElement)

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        for element in elements {
            for notification in notifications {
                AXObserverAddNotification(observerRef, element, notification as CFString, refcon)
            }
        }
        observedElements = elements

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observerRef),
            .commonModes
        )
    }

    private func tearDownObserver() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .commonModes
            )
        }
        observer = nil
        observedElements = []
        observedPID = nil
    }

    private func observableElements(from appElement: AXUIElement) -> [AXUIElement] {
        let attributes = [
            kAXFocusedWindowAttribute as String,
            "AXMainWindow",
            kAXWindowsAttribute as String,
            kAXFocusedUIElementAttribute as String,
            kAXChildrenAttribute as String
        ]

        var elements = [appElement]
        var seen = Set<CFHashCode>([CFHash(appElement)])

        @discardableResult
        func add(_ element: AXUIElement) -> Bool {
            AXUIElementSetMessagingTimeout(element, axMessageTimeout)
            let role = stringAttribute(element, kAXRoleAttribute as String)
            guard !isChromeRole(role) else { return false }
            let key = CFHash(element)
            guard !seen.contains(key), elements.count < maxObservedElements else { return false }
            seen.insert(key)
            elements.append(element)
            return true
        }

        for attribute in attributes {
            guard let value = copyAttribute(appElement, attribute) else { continue }
            if let array = value as? [Any] {
                for item in array where CFGetTypeID(item as CFTypeRef) == AXUIElementGetTypeID() {
                    add(item as! AXUIElement)
                }
            } else if CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() {
                add(value as! AXUIElement)
            }
        }

        var queue = elements.map { (element: $0, depth: 0) }
        var index = 0
        while index < queue.count, elements.count < maxObservedElements {
            let item = queue[index]
            if item.depth < maxObservationDepth {
                for child in observableChildren(of: item.element) {
                    if add(child) {
                        queue.append((child, item.depth + 1))
                    }
                }
            }
            index += 1
        }

        return elements
    }

    private func observableChildren(of element: AXUIElement) -> [AXUIElement] {
        let childAttributes = [
            kAXChildrenAttribute as String,
            "AXVisibleChildren",
            "AXChildrenInNavigationOrder",
            "AXContents",
            "AXRows",
            "AXColumns",
            "AXSections",
            "AXTitleUIElement",
            "AXLinkedUIElements"
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
        return children
    }

    fileprivate func handleAXNotification(_ notification: String) {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.onChange?(notification)
            }
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
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

    private func isChromeRole(_ role: String) -> Bool {
        role == kAXMenuBarRole as String
            || role == kAXMenuRole as String
            || role == kAXMenuItemRole as String
            || role == "AXMenuBarItem"
            || role.localizedCaseInsensitiveContains("menu")
    }
}

private let qishuiAXObserverCallback: AXObserverCallback = { _, _, notification, refcon in
    guard let refcon else { return }
    let notificationName = notification as String
    let monitor = Unmanaged<QishuiAXChangeMonitor>.fromOpaque(refcon).takeUnretainedValue()
    Task { @MainActor in
        monitor.handleAXNotification(notificationName)
    }
}
