import Foundation

enum QishuiPlaybackInstancePolicy {
    static func acceptsSnapshot(
        snapshotProcessIdentifier: Int32?,
        runningProcessIdentifiers: Set<Int32>
    ) -> Bool {
        guard let snapshotProcessIdentifier else { return false }
        return runningProcessIdentifiers.contains(snapshotProcessIdentifier)
    }
}
