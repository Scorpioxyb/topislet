import AppKit

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
