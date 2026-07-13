import Foundation

struct MusicTrackIdentity: Hashable, Sendable {
    let providerIdentifier: String?
    let fallbackSignature: String
}

struct MusicTrackSnapshot: Equatable, Sendable {
    let identity: MusicTrackIdentity
    let title: String
    let artist: String?
    let album: String?
    let artworkData: Data?
    let lyrics: [String]
}

enum MusicPlaybackState: Equatable, Sendable {
    case playing
    case paused
    case stopped
    case unknown
}

struct MusicTimelineSnapshot: Equatable, Sendable {
    let elapsedTime: TimeInterval
    let duration: TimeInterval
    let playbackRate: Double
    let observedAt: Date
}

enum MusicAppAvailability: Equatable, Sendable {
    case ready
    case notRunning
    case degraded(reason: String)
    case permissionRequired(permission: String)
    case unavailable(reason: String)
}

enum MusicDataMechanism: Hashable, Sendable {
    case applicationClient
    case semanticAccessibility
    case appleEvent
}

struct MusicSnapshotProvenance: Equatable, Sendable {
    let bundleIdentifier: String
    let mechanisms: Set<MusicDataMechanism>
}

struct MusicAppSnapshot: Equatable, Sendable {
    let descriptor: MusicAppDescriptor
    let instance: MusicAppInstance?
    let availability: MusicAppAvailability
    let track: MusicTrackSnapshot?
    let playbackState: MusicPlaybackState
    let timeline: MusicTimelineSnapshot?
    let controls: MusicControlCapabilities
    let revision: UInt64
    let provenance: MusicSnapshotProvenance
    let checkedAt: Date
    let diagnostic: String
}
