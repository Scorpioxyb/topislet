import Foundation

enum MusicControlKind: Hashable, Sendable {
    case playPause
    case previousTrack
    case nextTrack
    case absoluteSeek
}

enum MusicControlMechanism: Equatable, Sendable {
    case semanticAccessibility
    case appleEvent
}

enum MusicControlRecoveryAction: Equatable, Sendable {
    case reopenQishuiWindow
}

enum MusicControlRecoveryTrigger: Equatable, Sendable {
    case userInitiated
    case backgroundStatusRefresh
}

enum MusicControlRecoveryPolicy {
    static func acceptsVerification(
        requestedGeneration: UInt64,
        currentGeneration: UInt64,
        requestedProcess: Int32,
        currentProcess: Int32?,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled
            && requestedGeneration == currentGeneration
            && requestedProcess == currentProcess
    }

    static func needsHealthCheck(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= 2
    }

    static func shouldPresentRecovery(
        isRecovering: Bool,
        hasRecoveryAction: Bool
    ) -> Bool {
        isRecovering || hasRecoveryAction
    }

    enum RefreshDisposition: Equatable {
        case keepWaiting
        case verified
        case clearInactiveFeedback
        case unchanged
    }

    static func refreshDisposition(
        isRecovering: Bool,
        awaitingVerification: Bool,
        qishuiAvailability: QishuiControlAvailability,
        hasRecoveryAction: Bool
    ) -> RefreshDisposition {
        if isRecovering {
            return awaitingVerification && hasVerifiedQishuiControls(qishuiAvailability)
                ? .verified : .keepWaiting
        }
        return hasRecoveryAction ? .unchanged : .clearInactiveFeedback
    }

    static func hasVerifiedQishuiControls(_ availability: QishuiControlAvailability) -> Bool {
        availability == .available
    }

    static func action(
        sourceBundleIdentifier: String?,
        qishuiAvailability: QishuiControlAvailability
    ) -> MusicControlRecoveryAction? {
        guard sourceBundleIdentifier == QishuiProcessLocator.bundleIdentifier else {
            return nil
        }
        guard qishuiAvailability == .windowClosed
                || qishuiAvailability == .controlTreeUnavailable
                || qishuiAvailability == .unknown else { return nil }
        return .reopenQishuiWindow
    }

    static func shouldOpenApplication(for trigger: MusicControlRecoveryTrigger) -> Bool {
        trigger == .userInitiated
    }
}

enum MusicControlCapability: Equatable, Sendable {
    case unavailable(reason: String)
    case ready(
        target: MusicAppInstance,
        mechanism: MusicControlMechanism,
        verifiedAt: Date
    )
}

struct MusicControlCapabilities: Equatable, Sendable {
    let values: [MusicControlKind: MusicControlCapability]

    static let none = MusicControlCapabilities(values: [:])

    func supports(_ kind: MusicControlKind) -> Bool {
        guard case .ready = values[kind] else { return false }
        return true
    }
}

enum MusicControlAction: Sendable, Equatable {
    case playPause
    case play
    case pause
    case previousTrack
    case nextTrack
    case seekNormalized(Double)
}

struct MusicControlRequest: Sendable {
    let id: UInt64
    let target: MusicAppInstance
    let expectedTrack: MusicTrackIdentity?
    let action: MusicControlAction
}

enum MusicControlDisposition: Equatable, Sendable {
    case accepted
    case rejected
    case failed
}

struct MusicControlResult: Equatable, Sendable {
    let requestID: UInt64
    let disposition: MusicControlDisposition
    let diagnostic: String
}
