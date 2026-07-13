import Foundation

struct MusicAppDescriptor: Hashable, Identifiable, Sendable {
    let bundleIdentifier: String
    let displayName: String

    var id: String { bundleIdentifier }
}

struct MusicAppInstance: Hashable, Sendable {
    let app: MusicAppDescriptor
    let processIdentifier: pid_t
    let launchedAt: Date?
}

enum MusicSnapshotRefresh: Sendable {
    case cached
    case metadata
    case timeline
}

@MainActor
protocol MusicAppAdapter: AnyObject {
    var descriptor: MusicAppDescriptor { get }

    func start(
        onInvalidation: @escaping @MainActor @Sendable () -> Void
    )
    func stop()
    func snapshot(refresh: MusicSnapshotRefresh) async -> MusicAppSnapshot
    func perform(_ request: MusicControlRequest) async -> MusicControlResult
}

enum MusicAdapterImplementationStatus: String, Equatable, Sendable {
    case active
    case experimental
    case planned

    var displayName: String {
        switch self {
        case .active:
            return "已适配"
        case .experimental:
            return "实验适配"
        case .planned:
            return "计划接入"
        }
    }
}

enum MusicAdapterCapability: String, CaseIterable, Hashable, Sendable {
    case metadata
    case artwork
    case playbackState
    case progress
    case lyrics
    case playPause
    case previousTrack
    case nextTrack
    case absoluteSeek

    var displayName: String {
        switch self {
        case .metadata:
            return "歌曲信息"
        case .artwork:
            return "封面"
        case .playbackState:
            return "播放状态"
        case .progress:
            return "进度"
        case .lyrics:
            return "歌词"
        case .playPause:
            return "播放暂停"
        case .previousTrack:
            return "上一首"
        case .nextTrack:
            return "下一首"
        case .absoluteSeek:
            return "进度跳转"
        }
    }
}

struct MusicAdapterRegistration: Identifiable, Equatable, Sendable {
    let descriptor: MusicAppDescriptor
    let implementationStatus: MusicAdapterImplementationStatus
    let capabilities: Set<MusicAdapterCapability>

    var id: String { descriptor.id }

    var capabilitySummary: String {
        guard !capabilities.isEmpty else { return "尚未启用" }
        return MusicAdapterCapability.allCases
            .filter(capabilities.contains)
            .map(\.displayName)
            .joined(separator: "、")
    }
}

enum MusicAdapterRegistry {
    static let qishui = MusicAdapterRegistration(
        descriptor: MusicAppDescriptor(
            bundleIdentifier: "com.soda.music",
            displayName: "汽水音乐"
        ),
        implementationStatus: .active,
        capabilities: [
            .metadata,
            .artwork,
            .playbackState,
            .progress,
            .lyrics,
            .playPause,
            .previousTrack,
            .nextTrack
        ]
    )

    static let appleMusic = MusicAdapterRegistration(
        descriptor: MusicAppDescriptor(
            bundleIdentifier: "com.apple.Music",
            displayName: "Apple Music"
        ),
        implementationStatus: .experimental,
        capabilities: [
            .metadata,
            .artwork,
            .playbackState,
            .progress,
            .playPause,
            .previousTrack,
            .nextTrack,
            .absoluteSeek
        ]
    )

    static let registrations = [qishui, appleMusic]

    static var activeRegistrations: [MusicAdapterRegistration] {
        registrations.filter { $0.implementationStatus == .active }
    }

    static var experimentalRegistrations: [MusicAdapterRegistration] {
        registrations.filter { $0.implementationStatus == .experimental }
    }

    static func registration(
        forBundleIdentifier bundleIdentifier: String
    ) -> MusicAdapterRegistration? {
        registrations.first { $0.descriptor.bundleIdentifier == bundleIdentifier }
    }
}
