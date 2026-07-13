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

enum MusicControlAction: Sendable {
    case playPause
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
