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

enum MusicAdapterInvalidation: Sendable {
    case sourceChanged
    case cachedDataChanged
}

@MainActor
protocol MusicAppAdapter: AnyObject {
    var descriptor: MusicAppDescriptor { get }

    func start(
        onInvalidation: @escaping @MainActor @Sendable (
            MusicAdapterInvalidation
        ) -> Void
    )
    func stop()
    func snapshot(refresh: MusicSnapshotRefresh) async -> MusicAppSnapshot
    func perform(_ request: MusicControlRequest) async -> MusicControlResult
}

enum MusicAdapterImplementationStatus: String, Equatable, Sendable {
    case active
    case alpha
    case planned

    var displayName: String {
        switch self {
        case .active:
            return "主适配"
        case .alpha:
            return "Alpha 支持"
        case .planned:
            return "计划接入"
        }
    }
}

enum MusicAdapterRuntimeLevel: Equatable, Sendable {
    case connected
    case limited
    case actionRequired
    case inactive
    case error
}

struct MusicAdapterRuntimePresentation: Equatable, Sendable {
    let level: MusicAdapterRuntimeLevel
    let title: String
    let detail: String
}

enum MusicAdapterRuntimePresenter {
    static func qishui(
        isRunning: Bool,
        accessibilityTrusted: Bool
    ) -> MusicAdapterRuntimePresentation {
        guard isRunning else {
            return MusicAdapterRuntimePresentation(
                level: .inactive,
                title: "未运行",
                detail: "打开汽水音乐后自动连接"
            )
        }
        guard accessibilityTrusted else {
            return MusicAdapterRuntimePresentation(
                level: .actionRequired,
                title: "控制待授权",
                detail: "状态可同步，播放控制需要辅助功能"
            )
        }
        return MusicAdapterRuntimePresentation(
            level: .connected,
            title: "已连接",
            detail: "状态同步与定向控制可用"
        )
    }

    static func appleMusic(
        isEnabled: Bool,
        isRunning: Bool,
        automationAccess: AppleMusicAutomationAccess,
        snapshotAvailability: MusicAppAvailability?
    ) -> MusicAdapterRuntimePresentation {
        guard isEnabled else {
            return MusicAdapterRuntimePresentation(
                level: .inactive,
                title: "已关闭",
                detail: "可在音乐设置中重新启用"
            )
        }
        guard isRunning else {
            return MusicAdapterRuntimePresentation(
                level: .inactive,
                title: "未运行",
                detail: "打开 Apple Music 后自动连接"
            )
        }

        switch automationAccess {
        case .consentRequired:
            return MusicAdapterRuntimePresentation(
                level: .actionRequired,
                title: "待授权",
                detail: "需要自动化权限才能读取和控制"
            )
        case .denied:
            return MusicAdapterRuntimePresentation(
                level: .actionRequired,
                title: "权限已关闭",
                detail: "请在系统设置中允许自动化访问"
            )
        case let .unavailable(status):
            return MusicAdapterRuntimePresentation(
                level: .error,
                title: "权限检查失败",
                detail: "系统状态码 \(status)"
            )
        case .targetNotRunning:
            return MusicAdapterRuntimePresentation(
                level: .inactive,
                title: "未运行",
                detail: "打开 Apple Music 后自动连接"
            )
        case .allowed:
            break
        }

        switch snapshotAvailability {
        case .ready:
            return MusicAdapterRuntimePresentation(
                level: .connected,
                title: "已连接",
                detail: "歌曲、封面、进度与定向控制可用"
            )
        case .notRunning:
            return MusicAdapterRuntimePresentation(
                level: .inactive,
                title: "未运行",
                detail: "打开 Apple Music 后自动连接"
            )
        case let .degraded(reason):
            return MusicAdapterRuntimePresentation(
                level: .error,
                title: "连接异常",
                detail: reason
            )
        case let .permissionRequired(permission):
            return MusicAdapterRuntimePresentation(
                level: .actionRequired,
                title: "需要权限",
                detail: permission
            )
        case let .unavailable(reason):
            return MusicAdapterRuntimePresentation(
                level: .error,
                title: "当前不可用",
                detail: reason
            )
        case nil:
            return MusicAdapterRuntimePresentation(
                level: .limited,
                title: "已授权",
                detail: "等待首次播放状态"
            )
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
        implementationStatus: .alpha,
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

    static var alphaRegistrations: [MusicAdapterRegistration] {
        registrations.filter { $0.implementationStatus == .alpha }
    }

    static func registration(
        forBundleIdentifier bundleIdentifier: String
    ) -> MusicAdapterRegistration? {
        registrations.first { $0.descriptor.bundleIdentifier == bundleIdentifier }
    }
}
