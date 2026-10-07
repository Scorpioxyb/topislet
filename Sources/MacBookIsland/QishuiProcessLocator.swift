import AppKit
import ApplicationServices

enum QishuiProcessSelectionPolicy {
    static func preferredProcessIdentifier(
        verifiedMediaRemoteProcessIdentifier: pid_t?,
        directSnapshotProcessIdentifier: pid_t?,
        runningProcessIdentifiers: Set<pid_t>
    ) -> pid_t? {
        if let verifiedMediaRemoteProcessIdentifier,
           runningProcessIdentifiers.contains(verifiedMediaRemoteProcessIdentifier) {
            return verifiedMediaRemoteProcessIdentifier
        }
        if let directSnapshotProcessIdentifier,
           runningProcessIdentifiers.contains(directSnapshotProcessIdentifier) {
            return directSnapshotProcessIdentifier
        }
        guard runningProcessIdentifiers.count == 1 else { return nil }
        return runningProcessIdentifiers.first
    }
}

enum QishuiProcessLocator {
    static let bundleIdentifier = "com.soda.music"

    static func runningApplications() -> [NSRunningApplication] {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
    }

    static func application(
        preferredProcessIdentifier: pid_t? = nil,
        requirePreferredProcessIdentifier: Bool = false
    ) -> NSRunningApplication? {
        if let preferredProcessIdentifier,
           let application = NSRunningApplication(
               processIdentifier: preferredProcessIdentifier
           ),
           !application.isTerminated,
           application.bundleIdentifier == bundleIdentifier {
            return application
        }
        if requirePreferredProcessIdentifier { return nil }
        return runningApplications().first
    }

    static func isRunning(processIdentifier: pid_t? = nil) -> Bool {
        application(
            preferredProcessIdentifier: processIdentifier,
            requirePreferredProcessIdentifier: processIdentifier != nil
        ) != nil
    }
}

enum QishuiWindowRecovery {
    /// Request Chromium renderer accessibility when the user explicitly relaunches
    /// Qishui. This bootstraps its AX tree; it does not guarantee that a minimized
    /// renderer will retain or recreate nodes after accessibility is disabled.
    /// Keep control discovery and health checks even for processes using this flag.
    static let rendererAccessibilityArgument = "--force-renderer-accessibility"

    static func revealMainWindow(
        for application: NSRunningApplication?
    ) -> Bool {
        guard let application,
              !application.isTerminated else {
            return false
        }

        application.unhide()
        application.activate(options: [.activateAllWindows])

        let axApplication = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(axApplication, 0.2)
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApplication,
            kAXWindowsAttribute as CFString,
            &rawWindows
        ) == .success,
        let windows = rawWindows as? [AXUIElement],
        !windows.isEmpty else {
            return false
        }

        var didRevealWindow = false
        for window in windows {
            AXUIElementSetMessagingTimeout(window, 0.2)
            let unminimizeResult = AXUIElementSetAttributeValue(
                window,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            )
            let raiseResult = AXUIElementPerformAction(
                window,
                kAXRaiseAction as CFString
            )
            didRevealWindow = didRevealWindow
                || unminimizeResult == .success
                || raiseResult == .success
        }

        return didRevealWindow
    }

    @MainActor
    static func relaunchWithRendererAccessibility(
        applicationURL: URL,
        runningApplication: NSRunningApplication?
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        if let runningApplication, !runningApplication.isTerminated {
            guard runningApplication.terminate() else {
                return false
            }

            for _ in 0..<40 {
                guard !Task.isCancelled else { return false }
                if runningApplication.isTerminated {
                    break
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard runningApplication.isTerminated else {
                return false
            }
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [rendererAccessibilityArgument]
        configuration.activates = true
        configuration.addsToRecentItems = false

        // Launch Services can briefly return -600 immediately after the old
        // Electron process exits.  Retry a few times instead of making the
        // user press the recovery button again.
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard !Task.isCancelled else { return false }

            let didLaunch = await withCheckedContinuation { continuation in
                NSWorkspace.shared.openApplication(
                    at: applicationURL,
                    configuration: configuration
                ) { application, error in
                    continuation.resume(
                        returning: application != nil && error == nil
                    )
                }
            }
            if didLaunch { return true }
        }

        return false
    }
}
