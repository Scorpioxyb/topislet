import AppKit
import ApplicationServices
import Combine
import CoreImage
import Darwin
import EventKit
import QuartzCore
import SwiftUI

private let islandEventNotificationName = Notification.Name("io.github.scorpioxyb.topislet.event")

if CommandLine.arguments.contains("--music-adapters") {
    for registration in MusicAdapterRegistry.registrations {
        let capabilities = MusicAdapterCapability.allCases
            .filter(registration.capabilities.contains)
            .map(\.rawValue)
            .joined(separator: ",")
        print("adapter=\(registration.descriptor.bundleIdentifier)")
        print("name=\(registration.descriptor.displayName)")
        print("status=\(registration.implementationStatus.rawValue)")
        print("capabilities=\(capabilities)")
        print("")
    }
    exit(0)
}

if CommandLine.arguments.contains("--apple-music-status") {
    let adapter = AppleMusicAppAdapter()
    Task { @MainActor in
        let startedAt = Date()
        var snapshot = await adapter.snapshot(refresh: .metadata)
        let metadataLatencyMilliseconds = Int(
            Date().timeIntervalSince(startedAt) * 1_000
        )
        if snapshot.track != nil,
           snapshot.track?.artworkData == nil {
            for _ in 0..<50 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                let cachedSnapshot = await adapter.snapshot(refresh: .cached)
                if cachedSnapshot.track?.artworkData != nil {
                    snapshot = cachedSnapshot
                    break
                }
            }
        }
        let availability: String
        switch snapshot.availability {
        case .ready:
            availability = "ready"
        case .notRunning:
            availability = "notRunning"
        case let .degraded(reason):
            availability = "degraded:\(reason)"
        case let .permissionRequired(permission):
            availability = "permissionRequired:\(permission)"
        case let .unavailable(reason):
            availability = "unavailable:\(reason)"
        }
        let snapshotProcessIdentifier = snapshot.instance?.processIdentifier.description ?? "nil"
        print("appleMusicRunning=\(AppleMusicAppAdapter.isRunning)")
        print("appleMusicSnapshotPID=\(snapshotProcessIdentifier)")
        print("appleMusicRunningPIDs=\(NSRunningApplication.runningApplications(withBundleIdentifier: MusicAdapterRegistry.appleMusic.descriptor.bundleIdentifier).map(\.processIdentifier))")
        print("availability=\(availability)")
        print("track=\(snapshot.track?.title ?? "nil")")
        print("artworkDataBytes=\(snapshot.track?.artworkData?.count ?? 0)")
        print("metadataLatencyMilliseconds=\(metadataLatencyMilliseconds)")
        print("artworkLatencyMilliseconds=\(Int(Date().timeIntervalSince(startedAt) * 1_000))")
        print("diagnostic=\(snapshot.diagnostic)")
        exit(0)
    }
    RunLoop.main.run()
}

if CommandLine.arguments.contains("--apple-music-request-access") {
    let permissionApp = NSApplication.shared
    permissionApp.setActivationPolicy(.regular)
    permissionApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.async {
        let access = AppleMusicAppAdapter.automationAccess(prompt: true)
        print("automationAccess=\(access.diagnosticCode)")
        exit(access == .allowed ? 0 : 2)
    }
    permissionApp.run()
}

if let eventIndex = CommandLine.arguments.firstIndex(of: "--post-event") {
    guard CommandLine.arguments.indices.contains(eventIndex + 2) else {
        print("usage: MacBookIsland --post-event TITLE BODY [SOURCE]")
        exit(64)
    }
    let source = CommandLine.arguments.indices.contains(eventIndex + 3)
        ? CommandLine.arguments[eventIndex + 3]
        : "顶屿"
    DistributedNotificationCenter.default().postNotificationName(
        islandEventNotificationName,
        object: nil,
        userInfo: [
            "title": CommandLine.arguments[eventIndex + 1],
            "body": CommandLine.arguments[eventIndex + 2],
            "source": source
        ],
        deliverImmediately: true
    )
    print("eventPosted=true")
    exit(0)
}

if CommandLine.arguments.contains("--eventkit-status") {
    let calendar = EventKitAccessState(EKEventStore.authorizationStatus(for: .event))
    let reminders = EventKitAccessState(EKEventStore.authorizationStatus(for: .reminder))
    print("calendarAccess=\(calendar.rawValue)")
    print("remindersAccess=\(reminders.rawValue)")
    exit(0)
}

if CommandLine.arguments.contains("--ax-check") {
    print("accessibilityTrusted=\(AXIsProcessTrusted())")
    exit(AXIsProcessTrusted() ? 0 : 2)
}

func printQishuiSnapshot(_ snapshot: QishuiDirectSnapshot) {
    print("qishuiRunning=\(snapshot.isRunning)")
    print("pid=\(snapshot.processIdentifier.map(String.init) ?? "nil")")
    print("supportRoot=\(snapshot.supportRoot.path)")
    print("desktopLyricsEnabled=\(snapshot.desktopLyricsEnabled.map(String.init) ?? "unknown")")
    print("queueCacheTrackCount=\(snapshot.queueCacheTrackCount)")
    if let track = snapshot.currentTrack {
        print("currentTrack=\(track.title) - \(track.artist)")
        print("isPlaying=\(track.isPlaying.map(String.init) ?? "unknown")")
        let progressText = track.progress.map { String($0) } ?? "unavailable"
        print("progress=\(progressText)")
        print("artworkURL=\(track.artworkURL?.absoluteString ?? "nil")")
        print("lyricsCount=\(track.lyrics.count)")
        if !track.lyrics.isEmpty {
            print("lyricsPreview=\(track.lyrics.prefix(3).joined(separator: " / "))")
        }
        print("source=\(track.sourceName)")
    } else {
        print("currentTrack=nil")
    }
    print("diagnostic=\(snapshot.diagnostic)")
}

func printMediaRemoteSnapshot(_ snapshot: MediaRemoteNowPlayingSnapshot) {
    print("mediaRemoteAvailable=\(snapshot.isAvailable)")
    print("verifiedQishuiSource=\(snapshot.isVerifiedQishuiSource)")
    if let track = snapshot.currentTrack {
        print("currentTrack=\(track.title) - \(track.artist)")
        print("album=\(track.album ?? "nil")")
        print("isPlaying=\(track.isPlaying.map(String.init) ?? "unknown")")
        print("progress=\(track.progress)")
        print("elapsedTime=\(track.elapsedTime.map { String($0) } ?? "nil")")
        print("duration=\(track.duration.map { String($0) } ?? "nil")")
        print("artworkDataBytes=\(track.artworkData?.count ?? 0)")
        print("sourceBundleIdentifier=\(track.sourceBundleIdentifier ?? "nil")")
        print("sourceProcessIdentifier=\(track.sourceProcessIdentifier.map(String.init) ?? "nil")")
        print("source=\(track.sourceName)")
    } else {
        print("currentTrack=nil")
    }
    print("diagnostic=\(snapshot.diagnostic)")
}

func command(named rawValue: String) -> MusicControlCommand? {
    switch rawValue.lowercased() {
    case "playpause", "toggle", "play-pause", "play_pause":
        return .playPause
    case "next", "nexttrack", "next-track", "next_track":
        return .nextTrack
    case "previous", "prev", "previoustrack", "previous-track", "previous_track":
        return .previousTrack
    default:
        return nil
    }
}

if CommandLine.arguments.contains("--mediaremote-status") {
    let source = MediaRemoteNowPlayingSource()
    printMediaRemoteSnapshot(source.snapshot())
    exit(0)
}

if CommandLine.arguments.contains("--adapter-status") {
    let source = MediaRemoteAdapterStreamSource()
    printMediaRemoteSnapshot(source.refreshOnce())
    exit(0)
}

if CommandLine.arguments.contains("--qishui-control-diagnostic") {
    print(QishuiSemanticAXController().diagnostic())
    exit(0)
}

if let adapterWatchIndex = CommandLine.arguments.firstIndex(of: "--adapter-watch") {
    let seconds = CommandLine.arguments.indices.contains(adapterWatchIndex + 1)
        ? (TimeInterval(CommandLine.arguments[adapterWatchIndex + 1]) ?? 5)
        : 5
    let source = MediaRemoteAdapterStreamSource()
    source.start {
        print("EVENT \(ISO8601DateFormatter().string(from: Date()))")
        if let snapshot = source.snapshot() {
            printMediaRemoteSnapshot(snapshot)
        }
        fflush(stdout)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(max(seconds, 1)))
    source.stop()
    exit(0)
}

if let semanticControlIndex = CommandLine.arguments.firstIndex(of: "--qishui-semantic-control") {
    let rawCommand = CommandLine.arguments.indices.contains(semanticControlIndex + 1)
        ? CommandLine.arguments[semanticControlIndex + 1]
        : "playPause"
    guard let controlCommand = command(named: rawCommand) else {
        print("error=unsupported_control_command")
        print("supported=playPause,next,previous")
        exit(64)
    }

    let source = MediaRemoteAdapterStreamSource()
    print("BEFORE")
    printMediaRemoteSnapshot(source.refreshOnce())
    let result = QishuiSemanticAXController().press(controlCommand)
    print("semanticQishuiControlSent=\(result.didPress)")
    print("diagnostic=\(result.diagnostic)")
    usleep(220_000)
    print("AFTER")
    printMediaRemoteSnapshot(source.refreshOnce())
    exit(result.didPress ? 0 : 2)
}

if let watchIndex = CommandLine.arguments.firstIndex(of: "--mediaremote-watch") {
    let seconds = CommandLine.arguments.indices.contains(watchIndex + 1)
        ? (TimeInterval(CommandLine.arguments[watchIndex + 1]) ?? 20)
        : 20
    let source = MediaRemoteNowPlayingSource()
    source.start {
        print("EVENT \(ISO8601DateFormatter().string(from: Date()))")
        printMediaRemoteSnapshot(source.snapshot())
        fflush(stdout)
    }
    print("INITIAL \(ISO8601DateFormatter().string(from: Date()))")
    printMediaRemoteSnapshot(source.snapshot())
    RunLoop.current.run(until: Date().addingTimeInterval(max(seconds, 1)))
    exit(0)
}

if let repeatIndex = CommandLine.arguments.firstIndex(of: "--qishui-status-repeat") {
    let count = CommandLine.arguments.indices.contains(repeatIndex + 1)
        ? (Int(CommandLine.arguments[repeatIndex + 1]) ?? 3)
        : 3
    let adapter = QishuiAdapter()
    var lastSnapshot: QishuiDirectSnapshot?
    for index in 1...max(count, 1) {
        print("READ[\(index)]")
        let snapshot = adapter.snapshot()
        printQishuiSnapshot(snapshot)
        lastSnapshot = snapshot
        if index < count {
            usleep(120_000)
        }
    }
    exit(lastSnapshot?.isRunning == true ? 0 : 2)
}

if CommandLine.arguments.contains("--qishui-status") {
    let adapterSnapshot = MediaRemoteAdapterStreamSource().refreshOnce()
    print("PRIMARY_MEDIA_SOURCE")
    printMediaRemoteSnapshot(adapterSnapshot)
    print("")
    print("AX_FALLBACK_SOURCE")
    let snapshot = QishuiAdapter().snapshot()
    printQishuiSnapshot(snapshot)
    exit(adapterSnapshot.currentTrack != nil || snapshot.isRunning ? 0 : 2)
}

enum IslandMode: String {
    case collapsed
    case compact
    case expanded
}

enum IslandWindowLayout {
    static func size(
        for mode: IslandMode,
        collapsedWidth: CGFloat,
        compactWidth: CGFloat,
        expandedWidth: CGFloat,
        expandedHeight: CGFloat,
        topBandHeight: CGFloat
    ) -> NSSize {
        switch mode {
        case .collapsed:
            return NSSize(width: collapsedWidth, height: topBandHeight)
        case .compact:
            return NSSize(width: compactWidth, height: topBandHeight)
        case .expanded:
            return NSSize(width: expandedWidth, height: expandedHeight)
        }
    }

    static func frame(
        for size: NSSize,
        in screenFrame: NSRect,
        yOffset: CGFloat
    ) -> NSRect {
        NSRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height - yOffset,
            width: size.width,
            height: size.height
        )
    }

    static func acceptsAnimationCompletion(
        completedAnimationID: Int,
        currentAnimationID: Int,
        targetMode: IslandMode,
        currentMode: IslandMode
    ) -> Bool {
        completedAnimationID == currentAnimationID && targetMode == currentMode
    }
}

struct IslandAnimationCompletionGate {
    private(set) var currentAnimationID = 0
    private var completedAnimationID: Int?

    mutating func beginAnimation() -> Int {
        currentAnimationID &+= 1
        completedAnimationID = nil
        return currentAnimationID
    }

    mutating func claimCompletion(
        animationID: Int,
        targetMode: IslandMode,
        currentMode: IslandMode
    ) -> Bool {
        guard completedAnimationID != animationID,
              IslandWindowLayout.acceptsAnimationCompletion(
                completedAnimationID: animationID,
                currentAnimationID: currentAnimationID,
                targetMode: targetMode,
                currentMode: currentMode
              ) else {
            return false
        }
        completedAnimationID = animationID
        return true
    }
}

struct IslandInteractionRegions: Equatable {
    let header: NSRect
    let body: NSRect?
    let bridge: NSRect?

    static func make(
        panelFrame: NSRect,
        mode: IslandMode,
        headerWidth: CGFloat,
        topBandHeight: CGFloat,
        expandedBodyHeight: CGFloat,
        expandedPanelTopGap: CGFloat
    ) -> IslandInteractionRegions {
        let header = NSRect(
            x: panelFrame.midX - headerWidth / 2,
            y: panelFrame.maxY - topBandHeight,
            width: headerWidth,
            height: topBandHeight
        )
        guard mode == .expanded else {
            return IslandInteractionRegions(header: header, body: nil, bridge: nil)
        }

        let body = NSRect(
            x: panelFrame.minX,
            y: panelFrame.minY,
            width: panelFrame.width,
            height: expandedBodyHeight
        )
        let bridgeHeight = max(
            0,
            min(expandedPanelTopGap, header.minY - body.maxY)
        )
        let bridge = bridgeHeight > 0
            ? NSRect(
                x: header.minX,
                y: body.maxY,
                width: header.width,
                height: bridgeHeight
            )
            : nil
        return IslandInteractionRegions(header: header, body: body, bridge: bridge)
    }

    func contains(_ point: CGPoint, tolerance: CGFloat = 0) -> Bool {
        let expandedHeader = header.insetBy(dx: -tolerance, dy: -tolerance)
        let expandedBody = body?.insetBy(dx: -tolerance, dy: -tolerance)
        let expandedBridge = bridge?.insetBy(dx: -tolerance, dy: -tolerance)
        return expandedHeader.contains(point)
            || expandedBody?.contains(point) == true
            || expandedBridge?.contains(point) == true
    }
}

private enum IslandMotion {
    static func duration(for mode: IslandMode) -> TimeInterval {
        mode == .expanded ? 0.24 : 0.18
    }

    static func timingFunction(for mode: IslandMode) -> CAMediaTimingFunction {
        if mode == .expanded {
            return CAMediaTimingFunction(controlPoints: 0.25, 0.10, 0.25, 1.0)
        }
        return CAMediaTimingFunction(controlPoints: 0.40, 0.0, 0.20, 1.0)
    }

    static func geometryAnimation(for mode: IslandMode) -> Animation {
        if mode == .expanded {
            return .timingCurve(0.25, 0.10, 0.25, 1.0, duration: duration(for: mode))
        }
        return .timingCurve(0.40, 0.0, 0.20, 1.0, duration: duration(for: mode))
    }

    static func headerContentAnimation(for mode: IslandMode) -> Animation {
        .easeOut(duration: mode == .expanded ? 0.07 : 0.055)
    }

    static func bodyContentAnimation(for mode: IslandMode) -> Animation {
        if mode == .expanded {
            return .easeOut(duration: 0.12).delay(0.055)
        }
        return .easeOut(duration: 0.06)
    }
}

enum IslandFeature: String, Hashable {
    case music
    case timer
    case notification

    var iconName: String {
        switch self {
        case .music:
            return "music.note"
        case .timer:
            return "timer"
        case .notification:
            return "bell"
        }
    }

}

enum IslandHoverExpansionPolicy {
    static func allowsExpansion(
        activeFeature: IslandFeature,
        hasCurrentMusicTrack: Bool,
        hasPendingNotification: Bool
    ) -> Bool {
        switch activeFeature {
        case .music:
            return hasCurrentMusicTrack
        case .timer:
            return true
        case .notification:
            return hasPendingNotification
        }
    }
}

enum MusicPresentationTransitionPolicy {
    static func shouldPromoteToCompact(
        activeFeature: IslandFeature,
        currentMode: IslandMode,
        isArmed: Bool,
        hadCurrentTrack: Bool,
        hasCurrentTrack: Bool,
        hasPendingNotification: Bool
    ) -> Bool {
        activeFeature == .music
            && currentMode == .collapsed
            && isArmed
            && !hadCurrentTrack
            && hasCurrentTrack
            && !hasPendingNotification
    }

    static func shouldDisarmForUserRequest(_ targetMode: IslandMode) -> Bool {
        targetMode == .collapsed
    }

    static func shouldArmAfterSourceExit(
        currentMode: IslandMode,
        isUserExpanded: Bool
    ) -> Bool {
        currentMode == .compact
            || (currentMode == .expanded && !isUserExpanded)
    }
}

struct MusicTrack: Equatable {
    let title: String
    let artist: String
    let palette: [Color]
    let lyrics: [String]
    let hasArtwork: Bool
    let artworkData: Data?
    let artworkURL: URL?
    let sourceBundleIdentifier: String?
}

struct MusicState: Equatable {
    var track: MusicTrack
    var isPlaying: Bool
    var progress: Double
    var lyricIndex: Int
    var elapsedTime: TimeInterval? = nil
    var duration: TimeInterval? = nil
    var canSeek: Bool = false
    var isPlaybackPending: Bool = false
    var hasCurrentTrack: Bool
}

enum MusicUpdatePolicy {
    static func shouldIgnoreUntrustedProgressReset(
        current: MusicState,
        candidate: MusicState,
        sourceAvailability: MusicSourceAvailability?
    ) -> Bool {
        if sourceAvailability == .qishuiNotRunning {
            return false
        }
        guard current.track.sourceBundleIdentifier
            == candidate.track.sourceBundleIdentifier else {
            return false
        }
        guard candidate.hasCurrentTrack else {
            return false
        }
        guard current.duration != nil,
              current.elapsedTime != nil,
              current.progress > 0.01 else {
            return false
        }

        let candidateHasTrustedTiming = candidate.duration != nil
            && candidate.elapsedTime != nil
        guard !candidateHasTrustedTiming,
              candidate.progress <= 0.0001,
              !candidate.canSeek else {
            return false
        }

        return !candidate.track.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }
}

struct TimerState: Equatable {
    var duration: Int
    var remaining: Int
    var isRunning: Bool

    var progress: Double {
        guard duration > 0 else { return 0 }
        return Double(duration - remaining) / Double(duration)
    }
}

struct IslandNotification: Equatable {
    var title: String
    var body: String
    var source: String
    var count: Int
}

private enum IslandEventPriority: Int {
    case normal
    case urgent
}

private struct PendingIslandEvent: Equatable {
    var title: String
    var body: String
    var source: String
    let priority: IslandEventPriority
    let autoDismiss: Bool
    var count: Int
    let mergeIdentifier: String?
    var sourceBundleIdentifier: String?
}

private struct PendingMusicSeek {
    let trackSignature: String
    let targetProgress: Double
    let issuedAt: Date
    let isPlaying: Bool
    let expiresAt: Date
    var matchingSince: Date?
}

private struct ArtworkAccentComponents: Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

private let artworkColorContext = CIContext(options: [.cacheIntermediates: false])
private let artworkColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

private func artworkAccentComponents(from data: Data) -> ArtworkAccentComponents? {
    guard let image = CIImage(data: data),
          !image.extent.isEmpty,
          let filter = CIFilter(name: "CIAreaAverage") else { return nil }
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(CIVector(cgRect: image.extent), forKey: kCIInputExtentKey)
    guard let outputImage = filter.outputImage else { return nil }

    var pixel = [UInt8](repeating: 0, count: 4)
    pixel.withUnsafeMutableBytes { bytes in
        guard let baseAddress = bytes.baseAddress else { return }
        artworkColorContext.render(
            outputImage,
            toBitmap: baseAddress,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: artworkColorSpace
        )
    }
    guard pixel[3] > 20 else { return nil }
    return normalizedArtworkAccent(
        red: Double(pixel[0]) / 255,
        green: Double(pixel[1]) / 255,
        blue: Double(pixel[2]) / 255
    )
}

private func normalizedArtworkAccent(
    red: Double,
    green: Double,
    blue: Double
) -> ArtworkAccentComponents {
    let maximum = max(red, green, blue)
    let minimum = min(red, green, blue)
    let delta = maximum - minimum
    guard maximum > 0, delta / maximum >= 0.12 else {
        return ArtworkAccentComponents(red: 0.86, green: 0.86, blue: 0.86)
    }

    var hue: Double
    if maximum == red {
        hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
    } else if maximum == green {
        hue = ((blue - red) / delta) + 2
    } else {
        hue = ((red - green) / delta) + 4
    }
    hue /= 6
    if hue < 0 { hue += 1 }

    var saturation = min(max(delta / maximum, 0.45), 0.82)
    if (0.06...0.13).contains(hue) || (0.22...0.45).contains(hue) {
        saturation = min(saturation, 0.40)
    }
    let brightness = min(max(maximum, 0.72), 0.96)
    return rgbComponents(hue: hue, saturation: saturation, brightness: brightness)
}

private func rgbComponents(
    hue: Double,
    saturation: Double,
    brightness: Double
) -> ArtworkAccentComponents {
    let scaledHue = hue * 6
    let sector = Int(floor(scaledHue)) % 6
    let fraction = scaledHue - floor(scaledHue)
    let p = brightness * (1 - saturation)
    let q = brightness * (1 - fraction * saturation)
    let t = brightness * (1 - (1 - fraction) * saturation)
    switch sector {
    case 0: return ArtworkAccentComponents(red: brightness, green: t, blue: p)
    case 1: return ArtworkAccentComponents(red: q, green: brightness, blue: p)
    case 2: return ArtworkAccentComponents(red: p, green: brightness, blue: t)
    case 3: return ArtworkAccentComponents(red: p, green: q, blue: brightness)
    case 4: return ArtworkAccentComponents(red: t, green: p, blue: brightness)
    default: return ArtworkAccentComponents(red: brightness, green: p, blue: q)
    }
}

@MainActor
final class IslandModel: ObservableObject {
    @Published var mode: IslandMode = .collapsed
    @Published var activeFeature: IslandFeature = .music
    @Published var notchWidth: CGFloat = 185
    @Published var topBandHeight: CGFloat = 33
    let appSettings = AppSettings()
    let layout = LayoutCalibrationSettings()
    @Published var music: MusicState
    @Published var musicAccentColor = Color.white
    @Published var pendingTrackControl: MusicControlCommand?
    @Published private(set) var trackControlFeedbackGeneration: UInt64 = 0
    @Published private(set) var playPauseFeedbackGeneration: UInt64 = 0
    @Published var musicSourceStatus = MusicSourceStatus(
        sourceName: "汽水音乐",
        availability: .preview,
        headline: "等待汽水音乐真实数据",
        detail: "当前不显示假歌曲；主线正在直接读取汽水音乐本地状态，系统播放信息仅保留为手动诊断。",
        checkedAt: Date()
    )
    @Published private(set) var qishuiIsRunning = false
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var appleMusicAutomationAccess: AppleMusicAutomationAccess = .unavailable(status: -1)
    @Published private(set) var appleMusicIsRunning = false
    @Published private(set) var appleMusicSnapshotAvailability: MusicAppAvailability?
    @Published private(set) var appleMusicConnectionStatus = "尚未检查"
    @Published private(set) var appleMusicAvailableControls = "无"
    @Published private(set) var appleMusicResponseLatencyMilliseconds: Int?
    @Published var timerState = TimerState(duration: 25 * 60, remaining: 25 * 60, isRunning: false)
    @Published var notification = IslandNotification(
        title: "",
        body: "",
        source: "顶屿",
        count: 0
    )
    @Published var eventKitStatus = EventKitActivityStatus.current
    @Published var isVisible = true

    private let musicAdapter = MusicAdapterCoordinator()
    private let eventKitSource = EventKitActivitySource()
    private var ticker: Timer?
    private var musicRefreshBurstTask: Task<Void, Never>?
    private var musicAccentTask: Task<Void, Never>?
    private var musicAccentIdentity = ""
    private var musicAccentGeneration = 0
    private var trackControlFeedbackTask: Task<Void, Never>?
    private var pendingTrackControlBaselineSignature: String?
    private var pendingTrackControlGeneration: UInt64?
    private var pendingTrackControlChainCount = 0
    private var layoutCancellable: AnyCancellable?
    private var appleMusicSettingsCancellable: AnyCancellable?
    private var eventKitSettingsCancellable: AnyCancellable?
    private var appleMusicObservedProcessIdentifier: pid_t?
    private var appleMusicSettingsRequestGeneration: UInt64 = 0
    private var lastTimerUpdateAt: Date?
    private var lastIslandModeTapAt: Date = .distantPast
    private var lastDirectControlAt: Date = .distantPast
    private var lastMusicProgressPublishAt: Date = .distantPast
    private var autoCompactOnNextMusicTrack = true
    private var isUserExpandedMusicPresentation = false
    private var musicSeekRequestID = 0
    private var pendingMusicSeek: PendingMusicSeek?
    private var isMusicScrubbing = false
    private var notificationPresentationTask: Task<Void, Never>?
    private var notificationReturnFeature: IslandFeature?
    private var notificationReturnMode: IslandMode?
    private var notificationPresentedMode: IslandMode?
    private var activeIslandEvent: PendingIslandEvent?
    private var pendingIslandEvents: [PendingIslandEvent] = []
    private var shouldResumeInterruptedNormalEvent = false
    private var notificationGeneration = 0
    private let islandModeTapCooldown: TimeInterval = 0.08
    private let directControlSuppressionWindow: TimeInterval = 0.06
    private let musicProgressPublishInterval: TimeInterval = 0.45

    var collapsedWingWidth: CGFloat { 30 }
    var compactWingWidth: CGFloat { 96 }
    var expandedHeaderWingWidth: CGFloat { 34 }
    var hasPendingNotification: Bool {
        activeIslandEvent != nil || !pendingIslandEvents.isEmpty
    }

    var canExpandOnHover: Bool {
        IslandHoverExpansionPolicy.allowsExpansion(
            activeFeature: activeFeature,
            hasCurrentMusicTrack: music.hasCurrentTrack,
            hasPendingNotification: hasPendingNotification
        )
    }

    var collapsedWidth: CGFloat {
        notchWidth + collapsedWingWidth * 2
    }

    var compactWidth: CGFloat {
        notchWidth + compactWingWidth * 2
    }

    var expandedWidth: CGFloat {
        switch activeFeature {
        case .music:
            return max(notchWidth + 160, 460)
        case .timer, .notification:
            return max(notchWidth + 140, 420)
        }
    }

    var expandedHeight: CGFloat {
        topBandHeight + expandedPanelTopGap + expandedBodyHeight
    }

    var expandedHeaderWidth: CGFloat {
        notchWidth + expandedHeaderWingWidth * 2
    }

    var currentHeaderWidth: CGFloat {
        switch mode {
        case .collapsed:
            return collapsedWidth
        case .compact:
            return compactWidth
        case .expanded:
            return expandedHeaderWidth
        }
    }

    var statusWaveIsActive: Bool {
        switch activeFeature {
        case .music:
            return music.isPlaying
        case .timer:
            return timerState.isRunning
        case .notification:
            return false
        }
    }

    var statusWaveColor: Color {
        activeFeature == .music ? musicAccentColor : .white
    }

    var expandedPanelTopGap: CGFloat {
        8
    }

    var expandedBodyHeight: CGFloat {
        let baseHeight: CGFloat
        switch activeFeature {
        case .music:
            baseHeight = music.track.lyrics.isEmpty ? 148 : 178
        case .timer:
            baseHeight = 146
        case .notification:
            baseHeight = 156
        }
        return max(112, baseHeight + CGFloat(layout.expandedHeightAdjustment))
    }

    init() {
        isVisible = appSettings.showIslandOnLaunch
        musicAdapter.setAppleMusicEnabled(appSettings.appleMusicEnabled)
        music = musicAdapter.initialState
        pendingTrackControl = nil
        refreshMusicIntegrationStatus()
        if let previewModeIndex = CommandLine.arguments.firstIndex(of: "--preview-mode"),
           CommandLine.arguments.indices.contains(previewModeIndex + 1),
           let previewMode = IslandMode(rawValue: CommandLine.arguments[previewModeIndex + 1]) {
            mode = previewMode
        }
        if let previewFeatureIndex = CommandLine.arguments.firstIndex(of: "--preview-feature"),
           CommandLine.arguments.indices.contains(previewFeatureIndex + 1),
           let previewFeature = IslandFeature(rawValue: CommandLine.arguments[previewFeatureIndex + 1]) {
            activeFeature = previewFeature
        }
        musicSourceStatus = musicAdapter.refreshSourceStatus(allowSynchronousRefresh: true)
        musicAdapter.startRealtimeObservation { [weak self] music, status in
            self?.applyMusicUpdate(music, status: status)
        }
        eventKitSource.start(
            calendarEnabled: appSettings.calendarEventsEnabled,
            remindersEnabled: appSettings.remindersEnabled,
            onEvent: { [weak self] event in
                self?.receiveEventKitEvent(event)
            },
            onCancel: { [weak self] identifier in
                self?.cancelNotification(mergeIdentifier: identifier)
            },
            onStatus: { [weak self] status in
                self?.eventKitStatus = status
            }
        )
        eventKitSettingsCancellable = Publishers.CombineLatest(
            appSettings.$calendarEventsEnabled,
            appSettings.$remindersEnabled
        )
        .dropFirst()
        .sink { [weak self] calendarEnabled, remindersEnabled in
            self?.eventKitSource.update(
                calendarEnabled: calendarEnabled,
                remindersEnabled: remindersEnabled
            )
        }
        appleMusicSettingsCancellable = appSettings.$appleMusicEnabled
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                self.musicAdapter.setAppleMusicEnabled(enabled)
                self.refreshMusicIntegrationStatus()
                guard enabled,
                      self.appleMusicIsRunning,
                      self.appleMusicAutomationAccess == .allowed else { return }
                Task { [weak self] in
                    await self?.refreshAppleMusicSnapshot()
                }
            }
        layoutCancellable = layout.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        startTicker()
    }

    func toggleVisibility() {
        isVisible.toggle()
    }

    func showFeature(_ feature: IslandFeature, mode newMode: IslandMode = .expanded) {
        if activeFeature == .notification, feature != .notification {
            clearNotificationPresentation()
        }
        if feature == .music {
            isUserExpandedMusicPresentation = newMode == .expanded
            if MusicPresentationTransitionPolicy.shouldDisarmForUserRequest(newMode) {
                autoCompactOnNextMusicTrack = false
            }
        }
        activeFeature = feature
        mode = newMode
    }

    func toggleCollapsed() {
        requestIslandMode(mode == .collapsed ? .compact : .collapsed)
    }

    func toggleExpanded() {
        requestIslandMode(mode == .expanded ? .compact : .expanded)
    }

    func requestIslandMode(
        _ targetMode: IslandMode,
        bypassCooldown: Bool = false,
        userInitiated: Bool = true
    ) {
        let now = Date()
        if !bypassCooldown {
            guard now.timeIntervalSince(lastDirectControlAt) > directControlSuppressionWindow else { return }
            guard now.timeIntervalSince(lastIslandModeTapAt) > islandModeTapCooldown else { return }
        }
        if userInitiated, activeFeature == .music {
            isUserExpandedMusicPresentation = targetMode == .expanded
            if MusicPresentationTransitionPolicy.shouldDisarmForUserRequest(targetMode) {
                autoCompactOnNextMusicTrack = false
            }
        }
        guard mode != targetMode else { return }
        lastIslandModeTapAt = now
        mode = targetMode
    }

    private func refreshDisplayedMusicFromAdapter() {
        let update = musicAdapter.refreshPlaybackPositionNow()
        applyMusicUpdate(update.music, status: update.status, forceMusic: true)
    }

    private func noteDirectControlInteraction() {
        lastDirectControlAt = Date()
    }

    private func beginTrackControlFeedback(
        _ command: MusicControlCommand,
        baselineSignature: String
    ) -> UInt64 {
        trackControlFeedbackGeneration &+= 1
        let generation = trackControlFeedbackGeneration
        pendingTrackControlChainCount = pendingTrackControl == nil
            ? 1
            : pendingTrackControlChainCount + 1
        pendingTrackControl = command
        pendingTrackControlBaselineSignature = baselineSignature
        pendingTrackControlGeneration = generation
        trackControlFeedbackTask?.cancel()
        let feedbackDuration: UInt64 = pendingTrackControlChainCount > 1
            ? 520_000_000
            : 1_200_000_000
        trackControlFeedbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: feedbackDuration)
            guard !Task.isCancelled, let self,
                  pendingTrackControl == command,
                  pendingTrackControlGeneration == generation else { return }
            finishTrackControlFeedback(command, generation: generation)
        }
        return generation
    }

    private func finishTrackControlFeedback(
        _ command: MusicControlCommand,
        generation: UInt64? = nil
    ) {
        guard pendingTrackControl == command else { return }
        if let generation {
            guard pendingTrackControlGeneration == generation else { return }
        }
        pendingTrackControl = nil
        pendingTrackControlBaselineSignature = nil
        pendingTrackControlGeneration = nil
        pendingTrackControlChainCount = 0
        trackControlFeedbackTask?.cancel()
        trackControlFeedbackTask = nil
    }

    func playPause() {
        noteDirectControlInteraction()
        playPauseFeedbackGeneration &+= 1
        let previousSignature = musicSignature(music)
        let displayedSourceBundleIdentifier = music.track.sourceBundleIdentifier
        activeFeature = .music
        if mode == .collapsed {
            mode = .compact
        }
        Task { [weak self] in
            guard let self else { return }
            let outcome = await musicAdapter.performControl(
                .playPause,
                displayedSourceBundleIdentifier: displayedSourceBundleIdentifier
            )
            guard music.track.sourceBundleIdentifier
                == displayedSourceBundleIdentifier else { return }
            musicSourceStatus = outcome.status
            if outcome.didSendCommand {
                applyMusicUpdate(musicAdapter.currentState(), status: outcome.status, forceMusic: true)
                startMusicControlRefreshBurst(previousSignature: previousSignature, requireTrackChange: false)
            } else if outcome.shouldAdvancePreview {
                applyMusicUpdate(musicAdapter.playPause(music), status: outcome.status, forceMusic: true)
            }
        }
    }

    func nextTrack() {
        noteDirectControlInteraction()
        pendingMusicSeek = nil
        let previousSignature = musicSignature(music)
        let displayedSourceBundleIdentifier = music.track.sourceBundleIdentifier
        let feedbackGeneration = beginTrackControlFeedback(
            .nextTrack,
            baselineSignature: previousSignature
        )
        activeFeature = .music
        if mode == .collapsed {
            mode = .compact
        }
        Task { [weak self] in
            guard let self else { return }
            let outcome = await musicAdapter.performControl(
                .nextTrack,
                displayedSourceBundleIdentifier: displayedSourceBundleIdentifier
            )
            guard music.track.sourceBundleIdentifier
                == displayedSourceBundleIdentifier else {
                finishTrackControlFeedback(.nextTrack, generation: feedbackGeneration)
                return
            }
            musicSourceStatus = outcome.status
            if outcome.didSendCommand {
                if displayedSourceBundleIdentifier
                    == MusicAdapterRegistry.qishui.descriptor.bundleIdentifier {
                    musicAdapter.invalidateQishuiCache()
                }
                startMusicControlRefreshBurst(
                    previousSignature: previousSignature,
                    requireTrackChange: true,
                    trackControlGeneration: feedbackGeneration
                )
            } else {
                finishTrackControlFeedback(.nextTrack, generation: feedbackGeneration)
                if outcome.shouldAdvancePreview {
                    applyMusicUpdate(musicAdapter.nextTrack(), status: outcome.status, forceMusic: true)
                }
            }
        }
    }

    func previousTrack() {
        noteDirectControlInteraction()
        pendingMusicSeek = nil
        let previousSignature = musicSignature(music)
        let displayedSourceBundleIdentifier = music.track.sourceBundleIdentifier
        let feedbackGeneration = beginTrackControlFeedback(
            .previousTrack,
            baselineSignature: previousSignature
        )
        activeFeature = .music
        if mode == .collapsed {
            mode = .compact
        }
        Task { [weak self] in
            guard let self else { return }
            let outcome = await musicAdapter.performControl(
                .previousTrack,
                displayedSourceBundleIdentifier: displayedSourceBundleIdentifier
            )
            guard music.track.sourceBundleIdentifier
                == displayedSourceBundleIdentifier else {
                finishTrackControlFeedback(.previousTrack, generation: feedbackGeneration)
                return
            }
            musicSourceStatus = outcome.status
            if outcome.didSendCommand {
                if displayedSourceBundleIdentifier
                    == MusicAdapterRegistry.qishui.descriptor.bundleIdentifier {
                    musicAdapter.invalidateQishuiCache()
                }
                startMusicControlRefreshBurst(
                    previousSignature: previousSignature,
                    requireTrackChange: true,
                    trackControlGeneration: feedbackGeneration
                )
            } else {
                finishTrackControlFeedback(.previousTrack, generation: feedbackGeneration)
                if outcome.shouldAdvancePreview {
                    applyMusicUpdate(musicAdapter.previousTrack(), status: outcome.status, forceMusic: true)
                }
            }
        }
    }

    func showMusicSourceStatus() {
        let update = musicAdapter.refreshPlaybackPositionNow()
        applyMusicUpdate(update.music, status: update.status, forceMusic: true)
    }

    func showAccessibilityStatus() {
        let trusted = AXIsProcessTrusted()
        let path = Bundle.main.bundlePath
        triggerNotification(
            title: trusted ? "辅助功能已授权" : "辅助功能未授权",
            body: trusted
                ? "当前运行的顶屿已通过系统辅助功能检查。"
                : "当前运行路径：\(path)。请在辅助功能中勾选这个 App；如果已有旧项，先删除旧项再添加当前 App。"
        )
    }

    func refreshMusicIntegrationStatus() {
        qishuiIsRunning = !NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicAdapterRegistry.qishui.descriptor.bundleIdentifier
        ).isEmpty
        accessibilityTrusted = AXIsProcessTrusted()
        refreshAppleMusicStatus()
    }

    func refreshAppleMusicStatus() {
        guard appSettings.appleMusicEnabled else {
            appleMusicIsRunning = false
            appleMusicAutomationAccess = .targetNotRunning
            appleMusicObservedProcessIdentifier = nil
            resetAppleMusicConnection(status: "已关闭")
            return
        }

        let runningApplication = NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicAdapterRegistry.appleMusic.descriptor.bundleIdentifier
        ).first
        let processIdentifier = runningApplication?.processIdentifier
        if processIdentifier != appleMusicObservedProcessIdentifier {
            appleMusicObservedProcessIdentifier = processIdentifier
            resetAppleMusicConnection(status: processIdentifier == nil ? "未运行" : "等待同步")
        }
        appleMusicIsRunning = runningApplication != nil
        let previousAutomationAccess = appleMusicAutomationAccess
        let currentAutomationAccess: AppleMusicAutomationAccess = appleMusicIsRunning
            ? AppleMusicAppAdapter.automationAccess(prompt: false)
            : .targetNotRunning
        appleMusicAutomationAccess = currentAutomationAccess
        if appleMusicIsRunning,
           previousAutomationAccess == .allowed,
           currentAutomationAccess != .allowed {
            musicAdapter.invalidateAppleMusicAccess()
        }

        guard appleMusicIsRunning else {
            resetAppleMusicConnection(status: "未运行")
            return
        }
        guard appleMusicAutomationAccess == .allowed else {
            resetAppleMusicConnection(status: appleMusicAutomationAccess.displayName)
            return
        }
        if appleMusicSnapshotAvailability == nil {
            appleMusicConnectionStatus = "已授权，等待同步"
        }
    }

    func requestAppleMusicAutomationAccess() {
        guard appSettings.appleMusicEnabled,
              AppleMusicAppAdapter.isRunning else {
            refreshAppleMusicStatus()
            return
        }
        appleMusicAutomationAccess = AppleMusicAppAdapter.automationAccess(prompt: true)
        appleMusicIsRunning = AppleMusicAppAdapter.isRunning
        if appleMusicAutomationAccess == .allowed {
            Task { [weak self] in
                await self?.refreshAppleMusicSnapshot()
            }
        } else {
            resetAppleMusicConnection(status: appleMusicAutomationAccess.displayName)
        }
    }

    func refreshAppleMusicSnapshot() async {
        refreshAppleMusicStatus()
        guard appSettings.appleMusicEnabled else {
            resetAppleMusicConnection(status: "已关闭")
            return
        }
        guard appleMusicIsRunning else {
            resetAppleMusicConnection(status: "未运行")
            return
        }
        guard appleMusicAutomationAccess == .allowed else {
            resetAppleMusicConnection(status: appleMusicAutomationAccess.displayName)
            return
        }

        appleMusicSettingsRequestGeneration &+= 1
        let requestGeneration = appleMusicSettingsRequestGeneration
        let expectedProcessIdentifier = appleMusicObservedProcessIdentifier
        let requestStartedAt = Date()
        guard let snapshot = await musicAdapter.appleMusicSnapshotForSettings() else {
            refreshAppleMusicStatus()
            if appSettings.appleMusicEnabled,
               appleMusicIsRunning,
               appleMusicAutomationAccess == .allowed {
                appleMusicConnectionStatus = "连接超时"
            }
            return
        }
        let currentApplication = NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicAdapterRegistry.appleMusic.descriptor.bundleIdentifier
        ).first
        let currentAccess = currentApplication.map { _ in
            AppleMusicAppAdapter.automationAccess(prompt: false)
        } ?? .targetNotRunning
        guard requestGeneration == appleMusicSettingsRequestGeneration,
              appSettings.appleMusicEnabled,
              currentApplication?.processIdentifier == expectedProcessIdentifier,
              snapshot.instance?.processIdentifier == expectedProcessIdentifier,
              currentAccess == .allowed else {
            refreshAppleMusicStatus()
            return
        }
        appleMusicResponseLatencyMilliseconds = max(
            0,
            Int((Date().timeIntervalSince(requestStartedAt) * 1_000).rounded())
        )
        appleMusicSnapshotAvailability = snapshot.availability
        appleMusicObservedProcessIdentifier = snapshot.instance?.processIdentifier
        switch snapshot.availability {
        case .ready:
            appleMusicConnectionStatus = "连接正常"
        case .notRunning:
            appleMusicConnectionStatus = "未运行"
        case let .degraded(reason):
            appleMusicConnectionStatus = "读取失败：\(reason)"
        case let .permissionRequired(permission):
            appleMusicConnectionStatus = "需要权限：\(permission)"
        case let .unavailable(reason):
            appleMusicConnectionStatus = "不可用：\(reason)"
        }

        appleMusicAvailableControls = [
            snapshot.controls.supports(.playPause) ? "播放暂停" : nil,
            snapshot.controls.supports(.previousTrack) ? "上一首" : nil,
            snapshot.controls.supports(.nextTrack) ? "下一首" : nil,
            snapshot.controls.supports(.absoluteSeek) ? "进度跳转" : nil
        ]
        .compactMap { $0 }
        .joined(separator: "、")
        if appleMusicAvailableControls.isEmpty {
            appleMusicAvailableControls = "无"
        }
    }

    private func resetAppleMusicConnection(status: String) {
        appleMusicSettingsRequestGeneration &+= 1
        appleMusicSnapshotAvailability = nil
        appleMusicConnectionStatus = status
        appleMusicAvailableControls = "无"
        appleMusicResponseLatencyMilliseconds = nil
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func openAppleMusicAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func forceRefreshNowPlaying() {
        activeFeature = .music
        requestIslandMode(.expanded, bypassCooldown: true)
        let result = musicAdapter.forceRefreshNowPlaying()
        applyMusicUpdate(result.music, status: result.status, forceMusic: true)
    }

    func seekMusic(
        to progress: Double,
        interaction: MusicSeekInteraction
    ) async -> Bool {
        noteDirectControlInteraction()
        activeFeature = .music
        musicSeekRequestID += 1
        let requestID = musicSeekRequestID
        let previousSignature = musicSignature(music)
        let displayedSourceBundleIdentifier = music.track.sourceBundleIdentifier
        let result = await musicAdapter.seek(
            to: progress,
            interaction: interaction,
            displayedSourceBundleIdentifier: displayedSourceBundleIdentifier
        )
        guard requestID == musicSeekRequestID else { return true }
        guard music.track.sourceBundleIdentifier
            == displayedSourceBundleIdentifier else { return true }
        let didSeek = result.status.availability == .qishuiControlSent
            || result.status.availability == .appleMusicControlSent
        pendingMusicSeek = nil
        applyMusicUpdate(result.music, status: result.status, forceMusic: true)
        if didSeek {
            pendingMusicSeek = PendingMusicSeek(
                trackSignature: musicSignature(result.music),
                targetProgress: min(max(progress, 0), 1),
                issuedAt: Date(),
                isPlaying: result.music.isPlaying,
                expiresAt: Date().addingTimeInterval(3.5),
                matchingSince: nil
            )
            startMusicControlRefreshBurst(previousSignature: previousSignature, requireTrackChange: false)
        }
        return didSeek
    }

    func setMusicScrubbing(_ isScrubbing: Bool) {
        guard isMusicScrubbing != isScrubbing else { return }
        isMusicScrubbing = isScrubbing
        if isScrubbing {
            musicRefreshBurstTask?.cancel()
            musicRefreshBurstTask = nil
        } else {
            presentNextEventIfPossible()
        }
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        musicRefreshBurstTask?.cancel()
        musicRefreshBurstTask = nil
        musicAccentTask?.cancel()
        musicAccentTask = nil
        trackControlFeedbackTask?.cancel()
        trackControlFeedbackTask = nil
        notificationPresentationTask?.cancel()
        notificationPresentationTask = nil
        musicAdapter.stopRealtimeObservation()
        eventKitSettingsCancellable?.cancel()
        eventKitSettingsCancellable = nil
        eventKitSource.stop()
    }

    func startTimer() {
        noteDirectControlInteraction()
        if timerState.remaining <= 0 {
            timerState = TimerState(duration: 25 * 60, remaining: 25 * 60, isRunning: false)
        }
        timerState.isRunning = true
        lastTimerUpdateAt = Date()
        activeFeature = .timer
        if mode == .collapsed {
            mode = .compact
        }
    }

    func toggleTimer() {
        noteDirectControlInteraction()
        activeFeature = .timer
        timerState.isRunning.toggle()
        lastTimerUpdateAt = timerState.isRunning ? Date() : nil
        if mode == .collapsed {
            mode = .compact
        }
    }

    func resetTimer() {
        noteDirectControlInteraction()
        timerState = TimerState(duration: 25 * 60, remaining: 25 * 60, isRunning: false)
        lastTimerUpdateAt = nil
        activeFeature = .timer
    }

    func addMinute() {
        noteDirectControlInteraction()
        timerState.duration += 60
        timerState.remaining += 60
        activeFeature = .timer
    }

    func triggerNotification(
        title: String = "新的提醒",
        body: String = "这是一条来自顶屿的低打扰提醒。",
        source: String = "顶屿",
        interruptsExpanded: Bool = false,
        autoDismiss: Bool = true,
        mergeIdentifier: String? = nil,
        sourceBundleIdentifier: String? = nil
    ) {
        let event = PendingIslandEvent(
            title: title,
            body: body,
            source: source,
            priority: interruptsExpanded ? .urgent : .normal,
            autoDismiss: autoDismiss,
            count: 1,
            mergeIdentifier: mergeIdentifier,
            sourceBundleIdentifier: sourceBundleIdentifier
        )

        if event.priority == .normal, mergeNormalEventIfPossible(event) {
            return
        }

        if event.priority == .urgent,
           let activeEvent = activeIslandEvent,
           activeEvent.priority == .normal {
            if let presentedMode = notificationPresentedMode,
               mode != presentedMode {
                notificationReturnMode = mode
            }
            pendingIslandEvents.insert(activeEvent, at: 0)
            shouldResumeInterruptedNormalEvent = true
            activeIslandEvent = nil
            cancelNotificationDismissTask()
        }

        enqueue(event)
        updateNotificationDisplay()
        presentNextEventIfPossible()
    }

    func showPendingNotification() {
        guard hasPendingNotification else { return }
        presentNextEventIfPossible(force: true)
    }

    func dismissNotification() {
        noteDirectControlInteraction()
        completeActiveEvent()
    }

    var canOpenActiveEventSource: Bool {
        guard let bundleIdentifier = activeIslandEvent?.sourceBundleIdentifier else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    func openActiveEventSource() {
        guard let bundleIdentifier = activeIslandEvent?.sourceBundleIdentifier,
              let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
              ) else { return }
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
        dismissNotification()
    }

    func requestCalendarAccess() async {
        let granted = await eventKitSource.requestCalendarAccess()
        appSettings.calendarEventsEnabled = granted
    }

    func requestRemindersAccess() async {
        let granted = await eventKitSource.requestRemindersAccess()
        appSettings.remindersEnabled = granted
    }

    func refreshEventKitNow() async {
        await eventKitSource.refreshNow()
    }

    func openEventKitPrivacySettings(for entityType: EKEntityType) {
        let anchor = entityType == .event ? "Privacy_Calendars" : "Privacy_Reminders"
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func receiveEventKitEvent(_ event: EventKitIslandEvent) {
        triggerNotification(
            title: event.title,
            body: event.body,
            source: event.source,
            mergeIdentifier: event.identifier,
            sourceBundleIdentifier: event.sourceBundleIdentifier
        )
    }

    private func cancelNotification(mergeIdentifier: String) {
        pendingIslandEvents.removeAll { $0.mergeIdentifier == mergeIdentifier }
        if activeIslandEvent?.mergeIdentifier == mergeIdentifier {
            completeActiveEvent()
        } else {
            updateNotificationDisplay()
        }
    }

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        let mediaUpdate = musicAdapter.tick(music)
        if isMusicScrubbing {
            if let status = mediaUpdate.sourceStatus,
               shouldPublishMusicStatus(status) {
                musicSourceStatus = status
            }
        } else {
            applyMusicUpdate(mediaUpdate.music, status: mediaUpdate.sourceStatus)
        }
        presentNextEventIfPossible()

        guard timerState.isRunning else {
            lastTimerUpdateAt = nil
            return
        }

        let now = Date()
        let previous = lastTimerUpdateAt ?? now
        let elapsedWholeSeconds = Int(now.timeIntervalSince(previous))
        guard elapsedWholeSeconds > 0 else { return }

        lastTimerUpdateAt = previous.addingTimeInterval(TimeInterval(elapsedWholeSeconds))
        timerState.remaining = max(timerState.remaining - elapsedWholeSeconds, 0)
        if timerState.remaining == 0 {
            timerState.isRunning = false
            lastTimerUpdateAt = nil
            triggerNotification(
                title: "时间到",
                body: "计时器已经结束。",
                source: "计时器",
                interruptsExpanded: true,
                autoDismiss: false
            )
        }
    }

    private var blocksInteractiveEventPresentation: Bool {
        isMusicScrubbing
            || pendingMusicSeek != nil
            || music.isPlaybackPending
            || pendingTrackControl != nil
    }

    private func mergeNormalEventIfPossible(_ event: PendingIslandEvent) -> Bool {
        if var activeEvent = activeIslandEvent,
           activeEvent.priority == .normal,
           canMerge(activeEvent, event) {
            activeEvent.title = event.title
            activeEvent.body = event.body
            activeEvent.source = event.source
            activeEvent.sourceBundleIdentifier = event.sourceBundleIdentifier
            activeEvent.count = min(activeEvent.count + 1, 9)
            activeIslandEvent = activeEvent
            updateNotificationDisplay()
            scheduleActiveEventDismissIfNeeded()
            return true
        }

        guard let index = pendingIslandEvents.lastIndex(where: {
            $0.priority == .normal && canMerge($0, event)
        }) else {
            return false
        }
        pendingIslandEvents[index].title = event.title
        pendingIslandEvents[index].body = event.body
        pendingIslandEvents[index].source = event.source
        pendingIslandEvents[index].sourceBundleIdentifier = event.sourceBundleIdentifier
        pendingIslandEvents[index].count = min(pendingIslandEvents[index].count + 1, 9)
        updateNotificationDisplay()
        return true
    }

    private func canMerge(_ lhs: PendingIslandEvent, _ rhs: PendingIslandEvent) -> Bool {
        if lhs.mergeIdentifier != nil || rhs.mergeIdentifier != nil {
            return lhs.mergeIdentifier != nil && lhs.mergeIdentifier == rhs.mergeIdentifier
        }
        return lhs.source == rhs.source
    }

    private func enqueue(_ event: PendingIslandEvent) {
        if event.priority == .urgent,
           let firstNormalIndex = pendingIslandEvents.firstIndex(where: { $0.priority == .normal }) {
            pendingIslandEvents.insert(event, at: firstNormalIndex)
        } else {
            pendingIslandEvents.append(event)
        }
    }

    private func presentNextEventIfPossible(force: Bool = false) {
        guard activeIslandEvent == nil,
              let nextEvent = pendingIslandEvents.first else {
            updateNotificationDisplay()
            return
        }

        let isBlocked = blocksInteractiveEventPresentation
            || (nextEvent.priority == .normal && mode == .expanded)
        guard force || !isBlocked else {
            updateNotificationDisplay()
            return
        }

        activeIslandEvent = pendingIslandEvents.removeFirst()
        if activeIslandEvent?.priority == .normal,
           shouldResumeInterruptedNormalEvent {
            shouldResumeInterruptedNormalEvent = false
        }
        if activeFeature != .notification {
            notificationReturnFeature = activeFeature
            notificationReturnMode = mode
        }
        activeFeature = .notification
        if mode == .collapsed {
            mode = .compact
        }
        notificationPresentedMode = mode
        updateNotificationDisplay()
        scheduleActiveEventDismissIfNeeded()
    }

    private func scheduleActiveEventDismissIfNeeded() {
        cancelNotificationDismissTask()
        guard activeIslandEvent?.autoDismiss == true else { return }
        notificationGeneration += 1
        let generation = notificationGeneration
        notificationPresentationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled,
                  let self,
                  generation == notificationGeneration,
                  activeIslandEvent?.autoDismiss == true else { return }
            completeActiveEvent()
        }
    }

    private func completeActiveEvent() {
        guard activeIslandEvent != nil else { return }
        activeIslandEvent = nil
        cancelNotificationDismissTask()

        let returnFeature = notificationReturnFeature
        let returnMode = notificationReturnMode
        let presentedMode = notificationPresentedMode
        let latestMode = mode
        notificationReturnFeature = nil
        notificationReturnMode = nil
        notificationPresentedMode = nil

        if returnFeature == .timer, timerState.isRunning {
            activeFeature = .timer
        } else {
            activeFeature = .music
        }
        if latestMode == presentedMode, let returnMode {
            mode = returnMode
        }
        updateNotificationDisplay()
        let shouldForceResume = shouldResumeInterruptedNormalEvent
            && pendingIslandEvents.first?.priority == .normal
        presentNextEventIfPossible(force: shouldForceResume)
    }

    private func updateNotificationDisplay() {
        let event = activeIslandEvent ?? pendingIslandEvents.first
        let count = min(
            (activeIslandEvent?.count ?? 0)
                + pendingIslandEvents.reduce(0) { $0 + $1.count },
            9
        )
        notification = IslandNotification(
            title: event?.title ?? "",
            body: event?.body ?? "",
            source: event?.source ?? "顶屿",
            count: count
        )
    }

    private func cancelNotificationDismissTask() {
        notificationGeneration += 1
        notificationPresentationTask?.cancel()
        notificationPresentationTask = nil
    }

    private func clearNotificationPresentation() {
        activeIslandEvent = nil
        pendingIslandEvents.removeAll()
        shouldResumeInterruptedNormalEvent = false
        cancelNotificationDismissTask()
        notificationReturnFeature = nil
        notificationReturnMode = nil
        notificationPresentedMode = nil
        updateNotificationDisplay()
    }

    private func startMusicControlRefreshBurst(
        previousSignature: String,
        requireTrackChange: Bool,
        trackControlGeneration: UInt64? = nil
    ) {
        if let trackControlGeneration,
           pendingTrackControlGeneration != trackControlGeneration {
            return
        }
        musicRefreshBurstTask?.cancel()
        let intervalsInNanoseconds: [UInt64] = [
            80_000_000,
            120_000_000,
            160_000_000,
            220_000_000,
            300_000_000,
            420_000_000,
            600_000_000,
            800_000_000,
            1_100_000_000
        ]

        musicRefreshBurstTask = Task { [weak self] in
            for interval in intervalsInNanoseconds {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                if let trackControlGeneration,
                   self.pendingTrackControlGeneration != trackControlGeneration {
                    return
                }
                let update = await self.musicAdapter.refreshControlFollowUp(
                    forcePositionRefresh: requireTrackChange
                )
                guard !Task.isCancelled else { return }
                self.applyMusicUpdate(
                    update.music,
                    status: update.status,
                    forceMusic: true,
                    trackControlConfirmationGeneration: trackControlGeneration
                )
                if self.shouldStopMusicControlRefreshBurst(
                    music: update.music,
                    status: update.status,
                    previousSignature: previousSignature,
                    requireTrackChange: requireTrackChange
                ) {
                    if let trackControlGeneration,
                       self.pendingTrackControlGeneration == trackControlGeneration {
                        continue
                    }
                    self.musicRefreshBurstTask?.cancel()
                }
            }
        }
    }

    private func applyMusicUpdate(
        _ newMusic: MusicState,
        status newStatus: MusicSourceStatus?,
        forceMusic: Bool = false,
        trackControlConfirmationGeneration: UInt64? = nil
    ) {
        if newStatus?.availability == .qishuiNotRunning {
            resetMusicPresentationAfterSourceExit()
        }
        if isMusicScrubbing, !forceMusic {
            if let newStatus,
               shouldPublishMusicStatus(newStatus) {
                musicSourceStatus = newStatus
            }
            return
        }

        let reconciledMusic = reconcilePendingSeek(newMusic)
        let becameAvailable = !music.hasCurrentTrack
            && reconciledMusic.hasCurrentTrack
        let shouldPromoteToCompact = MusicPresentationTransitionPolicy
            .shouldPromoteToCompact(
                activeFeature: activeFeature,
                currentMode: mode,
                isArmed: autoCompactOnNextMusicTrack,
                hadCurrentTrack: music.hasCurrentTrack,
                hasCurrentTrack: reconciledMusic.hasCurrentTrack,
                hasPendingNotification: hasPendingNotification
            )
        if MusicUpdatePolicy.shouldIgnoreUntrustedProgressReset(
            current: music,
            candidate: reconciledMusic,
            sourceAvailability: newStatus?.availability
        ) {
            var timelinePreservingUpdate = music
            timelinePreservingUpdate.isPlaying = reconciledMusic.isPlaying
            timelinePreservingUpdate.isPlaybackPending = reconciledMusic.isPlaybackPending
            timelinePreservingUpdate.hasCurrentTrack = reconciledMusic.hasCurrentTrack
            if timelinePreservingUpdate != music {
                music = timelinePreservingUpdate
            }
            if let newStatus,
               shouldPublishMusicStatus(newStatus) {
                musicSourceStatus = newStatus
            }
            return
        }

        if forceMusic || shouldPublishMusicUpdate(reconciledMusic) {
            music = reconciledMusic
            if becameAvailable {
                autoCompactOnNextMusicTrack = false
            }
            if shouldPromoteToCompact {
                isUserExpandedMusicPresentation = false
                mode = .compact
            }
            refreshMusicAccent(for: reconciledMusic.track)
            confirmTrackControlFeedbackIfNeeded(
                with: reconciledMusic,
                generation: trackControlConfirmationGeneration
            )
        }

        if let newStatus,
           shouldPublishMusicStatus(newStatus) {
            musicSourceStatus = newStatus
        }
    }

    private func resetMusicPresentationAfterSourceExit() {
        musicRefreshBurstTask?.cancel()
        musicRefreshBurstTask = nil
        trackControlFeedbackTask?.cancel()
        trackControlFeedbackTask = nil
        pendingTrackControl = nil
        pendingTrackControlBaselineSignature = nil
        pendingTrackControlGeneration = nil
        pendingTrackControlChainCount = 0
        pendingMusicSeek = nil
        musicSeekRequestID += 1
        isMusicScrubbing = false
        if activeFeature == .music,
           !hasPendingNotification,
           MusicPresentationTransitionPolicy.shouldArmAfterSourceExit(
            currentMode: mode,
            isUserExpanded: isUserExpandedMusicPresentation
           ) {
            autoCompactOnNextMusicTrack = true
            isUserExpandedMusicPresentation = false
            mode = .collapsed
        }
    }

    private func confirmTrackControlFeedbackIfNeeded(
        with music: MusicState,
        generation: UInt64?
    ) {
        guard let generation,
              pendingTrackControlGeneration == generation,
              pendingTrackControlChainCount == 1,
              let pendingTrackControl,
              let baseline = pendingTrackControlBaselineSignature else { return }

        let signature = musicSignature(music)
        guard signature != baseline else { return }
        finishTrackControlFeedback(pendingTrackControl, generation: generation)
    }

    private func refreshMusicAccent(for track: MusicTrack) {
        let identity = artworkAccentIdentity(for: track)
        guard identity != musicAccentIdentity else { return }
        musicAccentIdentity = identity
        musicAccentGeneration += 1
        let generation = musicAccentGeneration
        musicAccentTask?.cancel()

        let inlineData = track.artworkData
        let artworkURL = track.artworkURL
        guard inlineData != nil || artworkURL != nil else {
            withAnimation(.easeInOut(duration: 0.20)) {
                musicAccentColor = .white
            }
            musicAccentTask = nil
            return
        }

        musicAccentTask = Task { [weak self] in
            let data: Data?
            if let inlineData {
                data = inlineData
            } else if let artworkURL {
                data = try? await URLSession.shared.data(from: artworkURL).0
            } else {
                data = nil
            }
            guard !Task.isCancelled, let data else { return }
            let components = await Task.detached(priority: .utility) {
                artworkAccentComponents(from: data)
            }.value
            guard !Task.isCancelled,
                  let self,
                  generation == musicAccentGeneration,
                  identity == musicAccentIdentity,
                  let components else { return }
            withAnimation(.easeInOut(duration: 0.20)) {
                musicAccentColor = Color(
                    red: components.red,
                    green: components.green,
                    blue: components.blue
                )
            }
            musicAccentTask = nil
        }
    }

    private func artworkAccentIdentity(for track: MusicTrack) -> String {
        let artworkKey: String
        if let artworkData = track.artworkData {
            let prefix = artworkData.prefix(16)
                .map { String(format: "%02x", $0) }
                .joined()
            artworkKey = "data:\(artworkData.count):\(prefix)"
        } else if let artworkURL = track.artworkURL {
            artworkKey = "url:\(artworkURL.absoluteString)"
        } else {
            artworkKey = "none"
        }
        return "\(track.title)\u{1f}\(track.artist)\u{1f}\(artworkKey)"
    }

    private func reconcilePendingSeek(_ newMusic: MusicState) -> MusicState {
        guard var pendingSeek = pendingMusicSeek else { return newMusic }
        guard Date() < pendingSeek.expiresAt,
              musicSignature(newMusic) == pendingSeek.trackSignature else {
            pendingMusicSeek = nil
            return newMusic
        }

        let duration = newMusic.duration ?? music.duration
        let elapsedSinceSeek = pendingSeek.isPlaying ? Date().timeIntervalSince(pendingSeek.issuedAt) : 0
        let expectedProgress = duration.map {
            min(max(pendingSeek.targetProgress + elapsedSinceSeek / max($0, 1), 0), 1)
        } ?? pendingSeek.targetProgress
        let tolerance = duration.map { max(0.75 / max($0, 1), 0.002) } ?? 0.01
        let now = Date()
        if abs(newMusic.progress - expectedProgress) <= tolerance {
            if let matchingSince = pendingSeek.matchingSince,
               now.timeIntervalSince(matchingSince) >= 0.35 {
                pendingMusicSeek = nil
                return newMusic
            }
            pendingSeek.matchingSince = pendingSeek.matchingSince ?? now
        } else {
            pendingSeek.matchingSince = nil
        }
        pendingMusicSeek = pendingSeek

        var heldMusic = newMusic
        heldMusic.progress = expectedProgress
        if let duration, duration > 0 {
            heldMusic.duration = duration
            heldMusic.elapsedTime = duration * expectedProgress
        }
        return heldMusic
    }

    private func shouldPublishMusicUpdate(_ newMusic: MusicState) -> Bool {
        if hasTrackDisplayChange(newMusic.track, music.track)
            || newMusic.isPlaying != music.isPlaying
            || newMusic.lyricIndex != music.lyricIndex
            || newMusic.duration != music.duration
            || newMusic.canSeek != music.canSeek
            || newMusic.isPlaybackPending != music.isPlaybackPending
            || newMusic.hasCurrentTrack != music.hasCurrentTrack {
            lastMusicProgressPublishAt = Date()
            return true
        }

        let oldSecond = music.elapsedTime.map { Int($0.rounded(.down)) }
        let newSecond = newMusic.elapsedTime.map { Int($0.rounded(.down)) }
        let progressDelta = abs(newMusic.progress - music.progress)
        let now = Date()
        guard oldSecond != newSecond || progressDelta >= 0.006 else {
            return false
        }
        guard now.timeIntervalSince(lastMusicProgressPublishAt) >= musicProgressPublishInterval else {
            return false
        }
        lastMusicProgressPublishAt = now
        return true
    }

    private func hasTrackDisplayChange(_ lhs: MusicTrack, _ rhs: MusicTrack) -> Bool {
        lhs.title != rhs.title
            || lhs.artist != rhs.artist
            || lhs.lyrics != rhs.lyrics
            || lhs.hasArtwork != rhs.hasArtwork
            || lhs.artworkData != rhs.artworkData
            || lhs.artworkURL != rhs.artworkURL
            || lhs.sourceBundleIdentifier != rhs.sourceBundleIdentifier
    }

    private func shouldPublishMusicStatus(_ newStatus: MusicSourceStatus) -> Bool {
        newStatus.sourceName != musicSourceStatus.sourceName
            || newStatus.availability != musicSourceStatus.availability
            || newStatus.headline != musicSourceStatus.headline
            || newStatus.detail != musicSourceStatus.detail
    }

    private func shouldStopMusicControlRefreshBurst(
        music: MusicState,
        status: MusicSourceStatus,
        previousSignature: String,
        requireTrackChange: Bool
    ) -> Bool {
        _ = status
        guard !music.isPlaybackPending,
              music.track.title != "汽水音乐" else {
            return false
        }

        if requireTrackChange {
            let didChangeTrack = musicSignature(music) != previousSignature
            if !didChangeTrack {
                musicAdapter.invalidateQishuiCache()
            }
            return didChangeTrack
        }
        return true
    }

    private func musicSignature(_ music: MusicState) -> String {
        "\(music.track.title)\u{1f}\(music.track.artist)"
    }

}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }
}

final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = IslandModel()
    private var panel: IslandPanel?
    private var statusItem: NSStatusItem?
    private var calibrationWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private var outsideMouseMonitor: Any?
    private var hoverGlobalMouseMonitor: Any?
    private var hoverLocalMouseMonitor: Any?
    private var outsideEventTap: CFMachPort?
    private var outsideEventTapRunLoopSource: CFRunLoopSource?
    private var panelAnimationGate = IslandAnimationCompletionGate()
    private var hoverEnterTask: Task<Void, Never>?
    private var hoverExitTask: Task<Void, Never>?
    private var isPointerInsideHoverZone = false
    private var didExpandFromHover = false
    private var hoverReturnMode: IslandMode?
    private var hoverGeneration = 0
    private var hoverExpectedModeChange: IslandMode?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(receiveIslandEvent(_:)),
            name: islandEventNotificationName,
            object: nil
        )
        updateScreenMetrics()
        createPanel()
        createStatusItem()
        observeModel()
        observeScreenChanges()
        observeOutsideClicks()
        observeIslandHover()
        updatePanelVisibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.presentOpenFeedback(shouldShowSettings: false)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshMusicIntegrationStatus()
        Task {
            await model.refreshEventKitNow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentOpenFeedback(shouldShowSettings: true)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: islandEventNotificationName,
            object: nil
        )
        if let outsideMouseMonitor {
            NSEvent.removeMonitor(outsideMouseMonitor)
        }
        if let hoverGlobalMouseMonitor {
            NSEvent.removeMonitor(hoverGlobalMouseMonitor)
        }
        if let hoverLocalMouseMonitor {
            NSEvent.removeMonitor(hoverLocalMouseMonitor)
        }
        if let outsideEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), outsideEventTapRunLoopSource, .commonModes)
        }
        if let outsideEventTap {
            CFMachPortInvalidate(outsideEventTap)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        hoverEnterTask?.cancel()
        hoverExitTask?.cancel()
    }

    @objc private func receiveIslandEvent(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let rawTitle = userInfo["title"] as? String,
              let rawBody = userInfo["body"] as? String else { return }
        let title = String(rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !title.isEmpty else { return }
        let body = String(rawBody.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        let rawSource = userInfo["source"] as? String ?? "顶屿"
        let source = String(rawSource.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        model.triggerNotification(
            title: title,
            body: body,
            source: source.isEmpty ? "顶屿" : source
        )
    }

    private func createPanel() {
        let size = panelSize(for: model.mode)
        let panel = makeIslandPanel(size: size, level: .statusBar)

        let root = IslandRootView(model: model)
        let host = IslandHostingView(rootView: root)
        configureIslandHostingView(host, size: size)
        panel.contentView = host

        self.panel = panel
        repositionPanel(animated: false)
        panel.orderFrontRegardless()
    }

    private func makeIslandPanel(size: NSSize, level: NSWindow.Level) -> IslandPanel {
        let panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isExcludedFromWindowsMenu = true
        return panel
    }

    private func configureIslandHostingView<Content: View>(
        _ hostingView: NSHostingView<Content>,
        size: NSSize
    ) {
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        hostingView.layer?.masksToBounds = true
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "顶屿") {
            image.isTemplate = true
            item.button?.image = image
            item.button?.imagePosition = .imageOnly
        } else {
            item.button?.title = "屿"
        }
        item.button?.toolTip = "顶屿"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示 / 隐藏顶屿", action: #selector(toggleVisibility), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "显示汽水音乐", action: #selector(showMusic), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "启动 25 分钟计时", action: #selector(showTimer), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "汽水适配状态", action: #selector(showMusicSourceStatus), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "辅助功能自检", action: #selector(showAccessibilityStatus), keyEquivalent: "a"))
        menu.addItem(NSMenuItem(title: "实验：打开系统播放诊断", action: #selector(forceRefreshNowPlaying), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "设置...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "校准布局...", action: #selector(showCalibration), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出顶屿", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func observeModel() {
        model.$mode
            .sink { [weak self] mode in
                guard let self else { return }
                handleObservedModeChange(mode)
                repositionPanel(animated: true, targetMode: mode)
            }
            .store(in: &cancellables)

        model.$isVisible
            .sink { [weak self] _ in self?.updatePanelVisibility() }
            .store(in: &cancellables)

        model.$activeFeature
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, model.mode == .expanded else { return }
                repositionPanel(animated: true)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            model.$activeFeature.removeDuplicates(),
            model.$music
                .map(\.hasCurrentTrack)
                .removeDuplicates(),
            model.$notification
                .map { $0.count > 0 }
                .removeDuplicates()
        )
        .map { feature, hasCurrentTrack, hasPendingNotification in
            IslandHoverExpansionPolicy.allowsExpansion(
                activeFeature: feature,
                hasCurrentMusicTrack: hasCurrentTrack,
                hasPendingNotification: hasPendingNotification
            )
        }
        .removeDuplicates()
        .dropFirst()
        .sink { [weak self] _ in
            self?.updateIslandHover(at: NSEvent.mouseLocation)
        }
        .store(in: &cancellables)

        model.layout.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateScreenMetrics()
                    self?.repositionPanel(animated: false)
                }
            }
            .store(in: &cancellables)
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateScreenMetrics()
                self?.repositionPanel(animated: false)
            }
        }
    }

    private func observeOutsideClicks() {
        outsideMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            let clickPoint = NSEvent.mouseLocation
            Task { @MainActor in
                self?.collapseExpandedIslandIfClickIsOutside(appKitLocation: clickPoint)
            }
        }

        let eventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, _, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
                let location = event.location
                Task { @MainActor in
                    appDelegate.collapseExpandedIslandIfClickIsOutside(cgEventLocation: location)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            return
        }

        outsideEventTap = eventTap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        outsideEventTapRunLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func observeIslandHover() {
        hoverGlobalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor in
                self?.updateIslandHover(at: point)
            }
        }
        hoverLocalMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            let point = NSEvent.mouseLocation
            Task { @MainActor in
                self?.updateIslandHover(at: point)
            }
            return event
        }
    }

    private func updateIslandHover(at point: CGPoint) {
        let isInside = model.canExpandOnHover && isInsideIslandHoverZone(point)
        guard isInside != isPointerInsideHoverZone else { return }
        isPointerInsideHoverZone = isInside
        hoverGeneration += 1
        let generation = hoverGeneration

        if isInside {
            hoverExitTask?.cancel()
            hoverExitTask = nil
            guard model.mode != .expanded else { return }
            let returnMode: IslandMode = model.mode == .collapsed ? .collapsed : .compact
            hoverEnterTask?.cancel()
            hoverEnterTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 45_000_000)
                guard !Task.isCancelled,
                      let self,
                      hoverGeneration == generation,
                      isPointerInsideHoverZone,
                      model.canExpandOnHover,
                      model.mode != .expanded else { return }
                didExpandFromHover = true
                hoverReturnMode = returnMode
                hoverExpectedModeChange = .expanded
                model.requestIslandMode(
                    .expanded,
                    bypassCooldown: true,
                    userInitiated: false
                )
                hoverEnterTask = nil
            }
            return
        }

        hoverEnterTask?.cancel()
        hoverEnterTask = nil
        guard didExpandFromHover else { return }
        hoverExitTask?.cancel()
        hoverExitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled,
                  let self,
                  hoverGeneration == generation,
                  model.mode == .expanded,
                  !isPointerInsideHoverZone else { return }
            didExpandFromHover = false
            let returnMode = hoverReturnMode ?? .compact
            hoverReturnMode = nil
            hoverExpectedModeChange = returnMode
            model.requestIslandMode(
                returnMode,
                bypassCooldown: true,
                userInitiated: false
            )
            hoverExitTask = nil
        }
    }

    private func isInsideIslandHoverZone(_ point: CGPoint) -> Bool {
        guard model.isVisible, let panel, panel.isVisible else { return false }
        if model.mode == .compact,
           model.activeFeature != .music {
            let compactControlZone = CGRect(
                x: panel.frame.maxX - 40,
                y: panel.frame.minY,
                width: 40,
                height: panel.frame.height
            ).insetBy(dx: -3, dy: -3)
            if compactControlZone.contains(point) {
                return false
            }
        }
        return interactionRegions(for: panel.frame, mode: model.mode)
            .contains(point, tolerance: 3)
    }

    private func handleObservedModeChange(_ mode: IslandMode) {
        if hoverExpectedModeChange == mode {
            hoverExpectedModeChange = nil
            return
        }
        hoverExpectedModeChange = nil
        guard didExpandFromHover || hoverEnterTask != nil || hoverExitTask != nil else {
            return
        }
        hoverGeneration += 1
        hoverEnterTask?.cancel()
        hoverEnterTask = nil
        hoverExitTask?.cancel()
        hoverExitTask = nil
        didExpandFromHover = false
        hoverReturnMode = nil
    }

    private func collapseExpandedIslandIfClickIsOutside() {
        collapseExpandedIslandIfClickIsOutside(appKitLocation: NSEvent.mouseLocation)
    }

    private func collapseExpandedIslandIfClickIsOutside(cgEventLocation: CGPoint) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            collapseExpandedIslandIfClickIsOutside()
            return
        }
        let appKitLocation = CGPoint(
            x: cgEventLocation.x,
            y: screen.frame.maxY - cgEventLocation.y
        )
        collapseExpandedIslandIfClickIsOutside(appKitLocation: appKitLocation)
    }

    private func collapseExpandedIslandIfClickIsOutside(appKitLocation clickPoint: CGPoint) {
        guard model.mode == .expanded, model.isVisible, let panel else { return }
        guard model.appSettings.autoCollapseExpandedIsland else { return }
        if let calibrationWindow,
           calibrationWindow.isVisible,
           calibrationWindow.frame.contains(clickPoint) {
            return
        }
        if let settingsWindow,
           settingsWindow.isVisible,
           settingsWindow.frame.contains(clickPoint) {
            return
        }
        let regions = interactionRegions(for: panel.frame, mode: model.mode)
        guard !regions.contains(clickPoint, tolerance: 2) else { return }
        model.requestIslandMode(.compact, bypassCooldown: true)
    }

    private func updateScreenMetrics() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        model.layout.useDisplay(name: screen.localizedName, identity: calibrationDisplayIdentity(for: screen))

        var topHeight = max(screen.safeAreaInsets.top, 32)
        var notchWidth: CGFloat = 160

        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            notchWidth = right.minX - left.maxX
            topHeight = max(topHeight, left.height, right.height)
        }

        let calibratedTopHeight = topHeight + CGFloat(model.layout.notchHeightAdjustment)
        let nextNotchWidth = max(120, min(notchWidth, 240))
        let nextTopBandHeight = max(30, min(calibratedTopHeight, 42))
        if abs(model.notchWidth - nextNotchWidth) > 0.25 {
            model.notchWidth = nextNotchWidth
        }
        if abs(model.topBandHeight - nextTopBandHeight) > 0.25 {
            model.topBandHeight = nextTopBandHeight
        }
    }

    private func calibrationDisplayIdentity(for screen: NSScreen) -> String {
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let frame = screen.frame
        return [
            screen.localizedName,
            "\(Int(frame.width))x\(Int(frame.height))",
            "scale\(screen.backingScaleFactor)",
            "id\(screenNumber?.stringValue ?? "unknown")"
        ].joined(separator: "-")
    }

    private func panelSize(for mode: IslandMode) -> NSSize {
        IslandWindowLayout.size(
            for: mode,
            collapsedWidth: model.collapsedWidth,
            compactWidth: model.compactWidth,
            expandedWidth: model.expandedWidth,
            expandedHeight: model.expandedHeight,
            topBandHeight: model.topBandHeight
        )
    }

    private func interactionRegions(
        for panelFrame: NSRect,
        mode: IslandMode
    ) -> IslandInteractionRegions {
        let headerWidth: CGFloat
        switch mode {
        case .collapsed:
            headerWidth = model.collapsedWidth
        case .compact:
            headerWidth = model.compactWidth
        case .expanded:
            headerWidth = model.expandedHeaderWidth
        }
        return IslandInteractionRegions.make(
            panelFrame: panelFrame,
            mode: mode,
            headerWidth: headerWidth,
            topBandHeight: model.topBandHeight,
            expandedBodyHeight: model.expandedBodyHeight,
            expandedPanelTopGap: model.expandedPanelTopGap
        )
    }

    private func repositionPanel(
        animated: Bool,
        targetMode: IslandMode? = nil
    ) {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let mode = targetMode ?? model.mode
        let size = panelSize(for: mode)
        let frame = panelFrame(for: size, on: screen)

        guard animated else {
            _ = panelAnimationGate.beginAnimation()
            panel.setFrame(frame, display: true)
            panel.contentView?.frame = NSRect(origin: .zero, size: size)
            updatePanelVisibility()
            return
        }

        let animationID = panelAnimationGate.beginAnimation()
        let animationDuration = IslandMotion.duration(for: mode)

        if model.isVisible {
            panel.orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = IslandMotion.timingFunction(for: mode)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.finishAnimatedReposition(
                    animationID: animationID,
                    targetMode: mode,
                    frame: frame,
                    size: size
                )
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration + 0.05) { [weak self] in
            guard let self else { return }
            finishAnimatedReposition(
                animationID: animationID,
                targetMode: mode,
                frame: frame,
                size: size
            )
        }
    }

    private func finishAnimatedReposition(
        animationID: Int,
        targetMode: IslandMode,
        frame: NSRect,
        size: NSSize
    ) {
        guard panelAnimationGate.claimCompletion(
            animationID: animationID,
            targetMode: targetMode,
            currentMode: model.mode
        ) else { return }
        panel?.setFrame(frame, display: true)
        panel?.contentView?.frame = NSRect(origin: .zero, size: size)
    }

    private func panelFrame(for size: NSSize, on screen: NSScreen) -> NSRect {
        IslandWindowLayout.frame(
            for: size,
            in: screen.frame,
            yOffset: CGFloat(model.layout.islandYOffset)
        )
    }

    private func updatePanelVisibility() {
        guard let panel else { return }
        if model.isVisible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    @objc private func toggleVisibility() {
        model.toggleVisibility()
    }

    @objc private func showMusic() {
        model.isVisible = true
        model.showFeature(.music)
    }

    @objc private func showTimer() {
        model.isVisible = true
        model.startTimer()
    }

    @objc private func forceRefreshNowPlaying() {
        model.isVisible = true
        model.forceRefreshNowPlaying()
    }

    @objc private func showAccessibilityStatus() {
        model.isVisible = true
        model.showAccessibilityStatus()
    }

    @objc private func showMusicSourceStatus() {
        model.showMusicSourceStatus()
        showSettings()
    }

    @objc private func showSettings() {
        let window: NSWindow
        if let existingWindow = settingsWindow {
            window = existingWindow
        } else {
            let rootView = IslandSettingsView(model: model)
            let hostingView = NSHostingView(rootView: rootView)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "顶屿设置"
            window.contentView = hostingView
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace]
            settingsWindow = window
        }

        if !window.isVisible {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func presentOpenFeedback(shouldShowSettings: Bool) {
        model.isVisible = true
        if !CommandLine.arguments.contains("--preview-feature") {
            model.activeFeature = .music
        }
        if model.mode == .collapsed,
           !CommandLine.arguments.contains("--preview-mode") {
            model.requestIslandMode(.compact, bypassCooldown: true)
        }
        repositionPanel(animated: true)
        if shouldShowSettings {
            showSettings()
        }
    }

    @objc private func showCalibration() {
        model.isVisible = true
        model.requestIslandMode(.expanded, bypassCooldown: true)
        repositionPanel(animated: false)

        let window: NSWindow
        if let existingWindow = calibrationWindow {
            window = existingWindow
        } else {
            let rootView = LayoutCalibrationView(model: model, settings: model.layout)
            let hostingView = NSHostingView(rootView: rootView)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 620),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "顶屿布局校准"
            window.contentView = hostingView
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace]
            calibrationWindow = window
        }

        if !window.isVisible {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@MainActor
private final class AppTerminationSignalBridge {
    private var sources: [DispatchSourceSignal] = []

    init() {
        for signalNumber in [SIGINT, SIGTERM] {
            Darwin.signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(
                signal: signalNumber,
                queue: .main
            )
            source.setEventHandler {
                NSApp.terminate(nil)
            }
            source.resume()
            sources.append(source)
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            settingsWindow?.contentView = nil
            settingsWindow = nil
        } else if window === calibrationWindow {
            calibrationWindow?.contentView = nil
            calibrationWindow = nil
        }
    }
}

struct IslandSettingsView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        TabView {
            GeneralSettingsPane(model: model, settings: model.appSettings)
                .tabItem {
                    Label("常规", systemImage: "switch.2")
                }

            MusicSettingsPane(model: model, settings: model.appSettings)
                .tabItem {
                    Label("音乐", systemImage: "music.note")
                }

            EventKitSettingsPane(model: model, settings: model.appSettings)
                .tabItem {
                    Label("日程", systemImage: "calendar.badge.clock")
                }

            LayoutCalibrationView(model: model, settings: model.layout)
                .tabItem {
                    Label("布局", systemImage: "rectangle.and.hand.point.up.left")
                }

            AboutSettingsPane()
                .tabItem {
                    Label("关于", systemImage: "app.badge")
                }
        }
        .padding(10)
        .frame(width: 520, height: 620)
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("启动后显示顶屿", isOn: $settings.showIslandOnLaunch)

                Toggle("点击外部自动收起展开面板", isOn: $settings.autoCollapseExpandedIsland)

                Toggle("当前显示顶屿", isOn: $model.isVisible)
            }

            Section {
                LabeledContent(
                    "音乐控制",
                    value: model.music.track.sourceBundleIdentifier == "com.apple.Music"
                        ? "Apple Event 定向"
                        : "汽水语义控件定向"
                )

                Text("控制只发送给当前选中的已适配音乐应用；不切换前台 App、不移动鼠标，也不发送全局媒体键。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("显示音乐诊断信息", isOn: $settings.showMusicDiagnostics)
            } header: {
                Text("控制与诊断")
            }

            Section {
                LabeledContent("默认主活动", value: "前台音乐应用优先")

                Text("计时器和提醒只在事件发生时临时出现，不再作为顶屿里的固定入口。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                HStack {
                    Button("折叠") {
                        model.isVisible = true
                        model.requestIslandMode(.compact, bypassCooldown: true)
                    }

                    Button("展开预览") {
                        model.isVisible = true
                        model.requestIslandMode(.expanded, bypassCooldown: true)
                    }

                    Button("隐藏") {
                        model.isVisible = false
                    }
                }
            }

            Section {
                HStack {
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }

                    Button("打开应用程序文件夹") {
                        NSWorkspace.shared.open(Bundle.main.bundleURL.deletingLastPathComponent())
                    }
                }

                Text(Bundle.main.bundlePath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }
}

private struct MusicSettingsPane: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var settings: AppSettings
    @State private var isCheckingAppleMusic = false

    private var appleMusicLatencyText: String {
        guard let milliseconds = model.appleMusicResponseLatencyMilliseconds else {
            return "--"
        }
        return "\(milliseconds) ms"
    }

    private var artworkStatusText: String {
        if model.music.track.artworkData != nil || model.music.track.artworkURL != nil {
            return "已获取"
        }
        switch model.musicSourceStatus.availability {
        case .qishuiNotRunning, .preview:
            return "无当前封面"
        default:
            return "等待获取"
        }
    }

    private var diagnosticText: String {
        [
            "track=\(model.music.track.title) - \(model.music.track.artist)",
            "source=\(model.musicSourceStatus.sourceName)",
            "availability=\(model.musicSourceStatus.availability.rawValue)",
            "isPlaying=\(model.music.isPlaying)",
            "progress=\(String(format: "%.6f", model.music.progress))",
            "elapsedTime=\(model.music.elapsedTime.map { String(format: "%.3f", $0) } ?? "nil")",
            "duration=\(model.music.duration.map { String(format: "%.3f", $0) } ?? "nil")",
            "canSeek=\(model.music.canSeek)",
            "pending=\(model.music.isPlaybackPending)",
            "artworkBytes=\(model.music.track.artworkData?.count ?? 0)",
            "artworkURL=\(model.music.track.artworkURL?.absoluteString ?? "nil")",
            "checkedAt=\(model.musicSourceStatus.checkedAt.ISO8601Format())",
            "detail=\(model.musicSourceStatus.detail)"
        ].joined(separator: "\n")
    }

    var body: some View {
        Form {
            Section("音乐应用") {
                ForEach(MusicAdapterRegistry.registrations) { registration in
                    MusicAdapterSettingsRow(registration: registration, model: model)
                }
            }

            Section("汽水音乐控制") {
                LabeledContent("应用状态", value: model.qishuiIsRunning ? "运行中" : "未运行")
                LabeledContent(
                    "辅助功能",
                    value: model.accessibilityTrusted ? "已授权" : "控制待授权"
                )
                if !model.accessibilityTrusted {
                    Button {
                        model.openAccessibilitySettings()
                    } label: {
                        Label("打开辅助功能设置", systemImage: "gear")
                    }
                }
            }

            Section("Apple Music Alpha 支持") {
                Toggle("启用 Apple Music 适配", isOn: $settings.appleMusicEnabled)

                if settings.appleMusicEnabled {
                    LabeledContent(
                        "运行状态",
                        value: model.appleMusicIsRunning ? "运行中" : "未运行"
                    )
                    LabeledContent(
                        "自动化权限",
                        value: model.appleMusicAutomationAccess.displayName
                    )
                    LabeledContent("连接状态", value: model.appleMusicConnectionStatus)
                    LabeledContent("响应耗时", value: appleMusicLatencyText)
                    LabeledContent("可用控制", value: model.appleMusicAvailableControls)

                    HStack {
                        switch model.appleMusicAutomationAccess {
                        case .denied:
                            Button {
                                model.openAppleMusicAutomationSettings()
                            } label: {
                                Label("打开自动化设置", systemImage: "gear")
                            }
                        case .consentRequired:
                            Button {
                                model.requestAppleMusicAutomationAccess()
                            } label: {
                                Label("请求授权", systemImage: "lock.open")
                            }
                        case .allowed, .targetNotRunning, .unavailable:
                            EmptyView()
                        }

                        Button {
                            isCheckingAppleMusic = true
                            Task {
                                await model.refreshAppleMusicSnapshot()
                                isCheckingAppleMusic = false
                            }
                        } label: {
                            Label("刷新连接", systemImage: "arrow.clockwise")
                        }
                        .disabled(
                            isCheckingAppleMusic
                                || !model.appleMusicIsRunning
                                || model.appleMusicAutomationAccess != .allowed
                        )
                    }

                    if !model.appleMusicIsRunning {
                        Text("请先打开 Apple Music；顶屿不会主动启动它。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Text("电台未提供封面时，仅向 Apple 公共搜索发送当前歌名与歌手。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("当前活动") {
                LabeledContent("当前歌曲", value: "\(model.music.track.title) - \(model.music.track.artist)")
                LabeledContent("同步来源", value: model.musicSourceStatus.sourceName)
                LabeledContent("同步状态", value: model.musicSourceStatus.compactLabel)
                LabeledContent("最近更新", value: musicStatusAgeText(model.musicSourceStatus.checkedAt))
                LabeledContent("播放进度", value: playbackPositionText(model.music))
                LabeledContent("封面状态", value: artworkStatusText)
                LabeledContent(
                    "控制策略",
                    value: model.music.track.sourceBundleIdentifier == "com.apple.Music"
                        ? "Apple Event 定向"
                        : "汽水唯一语义 AX"
                )
                Button {
                    model.showMusicSourceStatus()
                } label: {
                    Label("刷新当前活动", systemImage: "arrow.clockwise")
                }
            }

            if settings.showMusicDiagnostics {
                Section {
                    LabeledContent("最近检查", value: model.musicSourceStatus.checkedAt.formatted(date: .omitted, time: .standard))
                    LabeledContent("UI Progress", value: String(format: "%.4f", model.music.progress))
                    LabeledContent("UI Elapsed", value: model.music.elapsedTime.map(mediaTimeText) ?? "nil")
                    LabeledContent("UI Duration", value: model.music.duration.map(mediaTimeText) ?? "nil")
                    LabeledContent("Can Seek", value: model.music.canSeek ? "true" : "false")
                    LabeledContent("Pending", value: model.music.isPlaybackPending ? "true" : "false")
                    LabeledContent("Artwork Bytes", value: String(model.music.track.artworkData?.count ?? 0))
                    Text(model.musicSourceStatus.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("复制诊断信息") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(diagnosticText, forType: .string)
                    }
                } header: {
                    Text("诊断")
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .task {
            model.refreshMusicIntegrationStatus()
            guard settings.appleMusicEnabled,
                  model.appleMusicIsRunning,
                  model.appleMusicAutomationAccess == .allowed else { return }
            isCheckingAppleMusic = true
            await model.refreshAppleMusicSnapshot()
            isCheckingAppleMusic = false
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didLaunchApplicationNotification
        )) { _ in
            model.refreshMusicIntegrationStatus()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didTerminateApplicationNotification
        )) { _ in
            model.refreshMusicIntegrationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            model.refreshMusicIntegrationStatus()
        }
    }
}

private struct MusicAdapterSettingsRow: View {
    let registration: MusicAdapterRegistration
    @ObservedObject var model: IslandModel

    private var supportColor: Color {
        switch registration.implementationStatus {
        case .active:
            return .green
        case .alpha:
            return .orange
        case .planned:
            return .secondary
        }
    }

    private var runtime: MusicAdapterRuntimePresentation {
        if registration.descriptor.bundleIdentifier
            == MusicAdapterRegistry.qishui.descriptor.bundleIdentifier {
            return MusicAdapterRuntimePresenter.qishui(
                isRunning: model.qishuiIsRunning,
                accessibilityTrusted: model.accessibilityTrusted
            )
        }
        return MusicAdapterRuntimePresenter.appleMusic(
            isEnabled: model.appSettings.appleMusicEnabled,
            isRunning: model.appleMusicIsRunning,
            automationAccess: model.appleMusicAutomationAccess,
            snapshotAvailability: model.appleMusicSnapshotAvailability
        )
    }

    private var runtimeColor: Color {
        switch runtime.level {
        case .connected:
            return .green
        case .limited:
            return .blue
        case .actionRequired:
            return .orange
        case .inactive:
            return .secondary
        case .error:
            return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = MusicSourceIconCache.shared.icon(
                    for: registration.descriptor.bundleIdentifier
                ) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(registration.descriptor.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(registration.capabilitySummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(runtime.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 5) {
                Text(registration.implementationStatus.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(supportColor)
                HStack(spacing: 5) {
                    Circle()
                        .fill(runtimeColor)
                        .frame(width: 6, height: 6)
                    Text(runtime.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(runtimeColor)
                }
            }
        }
        .frame(minHeight: 52)
    }
}

private func musicStatusAgeText(_ date: Date) -> String {
    let age = max(Date().timeIntervalSince(date), 0)
    if age < 1 {
        return "刚刚"
    }
    if age < 60 {
        return "\(Int(age)) 秒前"
    }
    return date.formatted(date: .omitted, time: .standard)
}

private struct EventKitSettingsPane: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var settings: AppSettings
    @State private var isRequestingCalendar = false
    @State private var isRequestingReminders = false
    @State private var isRefreshing = false

    private var canRefresh: Bool {
        (settings.calendarEventsEnabled && model.eventKitStatus.calendarAccess.canRead)
            || (settings.remindersEnabled && model.eventKitStatus.remindersAccess.canRead)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("权限", value: model.eventKitStatus.calendarAccess.displayName)

                if model.eventKitStatus.calendarAccess.canRead {
                    Toggle("在岛中显示临近日程", isOn: $settings.calendarEventsEnabled)
                } else if model.eventKitStatus.calendarAccess == .notDetermined {
                    Button("允许访问日历") {
                        isRequestingCalendar = true
                        Task {
                            await model.requestCalendarAccess()
                            isRequestingCalendar = false
                        }
                    }
                    .disabled(isRequestingCalendar)
                } else {
                    Button("打开日历隐私设置") {
                        model.openEventKitPrivacySettings(for: .event)
                    }
                }

                Text("读取所有日历来源中未来 10 分钟内的定时日程；全天日程默认忽略。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } header: {
                Text("日历")
            }

            Section {
                LabeledContent("权限", value: model.eventKitStatus.remindersAccess.displayName)

                if model.eventKitStatus.remindersAccess.canRead {
                    Toggle("在岛中显示到期提醒", isOn: $settings.remindersEnabled)
                } else if model.eventKitStatus.remindersAccess == .notDetermined {
                    Button("允许访问提醒事项") {
                        isRequestingReminders = true
                        Task {
                            await model.requestRemindersAccess()
                            isRequestingReminders = false
                        }
                    }
                    .disabled(isRequestingReminders)
                } else {
                    Button("打开提醒事项隐私设置") {
                        model.openEventKitPrivacySettings(for: .reminder)
                    }
                }

                Text("读取所有提醒清单中刚到期且具有具体时间的提醒，不补发大量历史逾期事项。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } header: {
                Text("提醒事项")
            }

            Section {
                Button("立即检查") {
                    isRefreshing = true
                    Task {
                        await model.refreshEventKitNow()
                        isRefreshing = false
                    }
                }
                .disabled(!canRefresh || isRefreshing)

                if let checkedAt = model.eventKitStatus.lastRefreshAt {
                    LabeledContent(
                        "最近检查",
                        value: checkedAt.formatted(date: .omitted, time: .standard)
                    )
                }

                Text(model.eventKitStatus.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("状态")
            }

            Section {
                Text("授权仅用于读取日程和提醒事项，并把临近或到期事件送入顶屿。不会读取其他 App 的系统通知，也不会修改你的日历和提醒事项。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("隐私")
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }
}

private struct AboutSettingsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "capsule.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 4) {
                    Text("顶屿")
                        .font(.system(size: 20, weight: .semibold))
                    Text("TopIslet")
                        .foregroundStyle(.secondary)
                    Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("当前版本以汽水音乐为默认主活动；计时器和提醒只在事件发生时临时接管。发布前仍需要处理签名、公证和系统更新兼容性。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("源代码许可证：GPL-3.0-only")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct IslandRootView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                ExpandedIslandBodyPanel(model: model)
                    .offset(y: model.topBandHeight + model.expandedPanelTopGap)

                IslandShell(
                    width: model.currentHeaderWidth,
                    height: model.topBandHeight,
                    cornerRadius: model.topBandHeight / 2,
                    fillOpacity: 1,
                    strokeOpacity: 0,
                    attachesToTop: true
                ) {
                    Color.clear
                }
                .animation(IslandMotion.geometryAnimation(for: model.mode), value: model.mode)

                ZStack {
                    CollapsedIsland(model: model)
                        .opacity(model.mode == .collapsed ? 1 : 0)
                        .allowsHitTesting(model.mode == .collapsed)
                        .accessibilityHidden(model.mode != .collapsed)

                    CompactIsland(model: model)
                        .opacity(model.mode == .compact ? 1 : 0)
                        .allowsHitTesting(model.mode == .compact)
                        .accessibilityHidden(model.mode != .compact)

                    ExpandedIsland(model: model)
                        .opacity(model.mode == .expanded ? 1 : 0)
                        .allowsHitTesting(model.mode == .expanded)
                        .accessibilityHidden(model.mode != .expanded)
                }
                .frame(width: model.currentHeaderWidth, height: model.topBandHeight)
                .animation(IslandMotion.geometryAnimation(for: model.mode), value: model.mode)
                .animation(IslandMotion.headerContentAnimation(for: model.mode), value: model.mode)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.14), value: model.activeFeature)
    }
}

struct IslandShell<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    var fillOpacity: Double = 0.995
    var strokeOpacity: Double = 0.03
    var shadowOpacity: Double = 0
    var attachesToTop = false
    @ViewBuilder var content: Content

    var body: some View {
        let shape = IslandShellShape(
            cornerRadius: cornerRadius,
            attachesToTop: attachesToTop
        )
        content
            .frame(width: width, height: height)
            .background(
                ZStack {
                    shape
                        .fill(Color.black.opacity(fillOpacity))
                    shape
                        .stroke(Color.white.opacity(strokeOpacity), lineWidth: 0.65)
                }
            )
            .clipShape(shape)
            .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowOpacity > 0 ? 14 : 0, x: 0, y: shadowOpacity > 0 ? 8 : 0)
    }
}

private struct IslandShellShape: Shape {
    let cornerRadius: CGFloat
    let attachesToTop: Bool

    func path(in rect: CGRect) -> Path {
        guard attachesToTop else {
            return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .path(in: rect)
        }
        let radius = min(cornerRadius, rect.width / 2, rect.height)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
            path.closeSubpath()
        }
    }
}

struct CollapsedIsland: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        IslandShell(
            width: model.collapsedWidth,
            height: model.topBandHeight,
            cornerRadius: model.topBandHeight / 2,
            fillOpacity: 0,
            strokeOpacity: 0,
            attachesToTop: true
        ) {
            ZStack {
                HStack(spacing: 0) {
                    Image(systemName: model.activeFeature.iconName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: model.collapsedWingWidth, height: model.topBandHeight)

                    Color.clear
                        .frame(width: model.notchWidth, height: model.topBandHeight)

                    StatusDot(
                        isActive: model.statusWaveIsActive,
                        accentColor: model.statusWaveColor
                    )
                        .frame(width: model.collapsedWingWidth, height: model.topBandHeight)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.requestIslandMode(.compact)
        }
    }
}

struct CompactIsland: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        IslandShell(
            width: model.compactWidth,
            height: model.topBandHeight,
            cornerRadius: model.topBandHeight / 2,
            fillOpacity: 0,
            strokeOpacity: 0,
            attachesToTop: true
        ) {
            ZStack {
                Group {
                    switch model.activeFeature {
                    case .music:
                        CompactMusic(model: model)
                    case .timer:
                        CompactTimer(model: model)
                    case .notification:
                        CompactNotification(model: model)
                    }
                }
            }
        }
    }
}

struct ExpandedIsland: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        IslandShell(
            width: model.expandedHeaderWidth,
            height: model.topBandHeight,
            cornerRadius: model.topBandHeight / 2,
            fillOpacity: 0,
            strokeOpacity: 0,
            attachesToTop: true
        ) {
            ZStack {
                HStack(spacing: 0) {
                    Image(systemName: model.activeFeature.iconName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: model.expandedHeaderWingWidth, height: model.topBandHeight)

                    Color.clear
                        .frame(width: model.notchWidth, height: model.topBandHeight)

                    StatusDot(
                        isActive: model.statusWaveIsActive,
                        accentColor: model.statusWaveColor
                    )
                        .frame(width: model.expandedHeaderWingWidth, height: model.topBandHeight)
                }
            }
        }
    }
}

struct ExpandedIslandBodyPanel: View {
    @ObservedObject var model: IslandModel

    private var shellScaleX: CGFloat {
        guard model.mode != .expanded else { return 1 }
        let targetWidth = model.mode == .collapsed ? model.collapsedWidth : model.compactWidth
        return targetWidth / model.expandedWidth
    }

    private var shellScaleY: CGFloat {
        model.mode == .expanded ? 1 : 0.025
    }

    var body: some View {
        ZStack(alignment: .top) {
            IslandShell(
                width: model.expandedWidth,
                height: model.expandedBodyHeight,
                cornerRadius: 24,
                fillOpacity: 0.99,
                strokeOpacity: 0.03,
                shadowOpacity: 0
            ) {
                Color.clear
            }
            .scaleEffect(x: shellScaleX, y: shellScaleY, anchor: .top)
            .animation(IslandMotion.geometryAnimation(for: model.mode), value: model.mode)

            ZStack(alignment: .topTrailing) {
                switch model.activeFeature {
                case .music:
                    ExpandedMusic(model: model)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 12)

                case .timer, .notification:
                    VStack(spacing: 8) {
                        HStack(alignment: .center) {
                            if model.hasPendingNotification, model.activeFeature != .notification {
                                Button {
                                    model.showPendingNotification()
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "bell.fill")
                                        Text(model.notification.count > 1 ? "\(model.notification.count) 条提醒" : "提醒")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .foregroundStyle(.white.opacity(0.78))
                                    .padding(.horizontal, 8)
                                    .frame(height: 24)
                                    .background(Capsule().fill(Color.white.opacity(0.08)))
                                }
                                .buttonStyle(.plain)
                                .help("查看提醒")
                            }
                            Spacer(minLength: 12)
                            WindowModeButtons(model: model)
                        }
                        .frame(height: 24)

                        Group {
                            if model.activeFeature == .timer {
                                ExpandedTimer(model: model)
                            } else {
                                ExpandedNotification(model: model)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                }

                if model.activeFeature == .music {
                    WindowModeButtons(model: model)
                        .padding(.top, 10)
                        .padding(.trailing, 16)
                }
            }
            .frame(width: model.expandedWidth, height: model.expandedBodyHeight)
            .opacity(model.mode == .expanded ? 1 : 0)
            .animation(IslandMotion.bodyContentAnimation(for: model.mode), value: model.mode)
            .mask {
                Rectangle()
                    .scaleEffect(x: shellScaleX, y: shellScaleY, anchor: .top)
                    .animation(IslandMotion.geometryAnimation(for: model.mode), value: model.mode)
            }
            .allowsHitTesting(model.mode == .expanded)
        }
        .frame(width: model.expandedWidth, height: model.expandedBodyHeight)
    }
}

struct WindowModeButtons: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.requestIslandMode(.compact, bypassCooldown: true)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("收起")

            Button {
                model.requestIslandMode(.collapsed, bypassCooldown: true)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("最小化")
        }
    }
}

struct CompactMusic: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                AlbumArt(track: model.music.track, size: 25)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.music.track.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                    Text(model.music.track.artist)
                        .font(.system(size: 10, weight: .regular))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            .padding(.leading, 10)
            .frame(width: model.compactWingWidth, height: model.topBandHeight, alignment: .leading)

            Color.clear
                .frame(width: model.notchWidth, height: model.topBandHeight)

            HStack(spacing: 9) {
                ProgressPill(progress: model.music.progress, width: 54)

                StatusDot(
                    isActive: model.statusWaveIsActive,
                    accentColor: model.statusWaveColor
                )
                .frame(width: 10, height: 10)
            }
            .padding(.trailing, 10)
            .frame(width: model.compactWingWidth, height: model.topBandHeight, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.requestIslandMode(.expanded)
        }
    }
}

struct CompactTimer: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 25, height: 25)
                    .background(Circle().fill(Color.white.opacity(0.08)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(timeText(model.timerState.remaining))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    ProgressPill(progress: model.timerState.progress, width: 96)
                }
            }
            .padding(.leading, 10)
            .frame(width: model.compactWingWidth, height: model.topBandHeight, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                model.requestIslandMode(.expanded)
            }

            Color.clear
                .frame(width: model.notchWidth, height: model.topBandHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.requestIslandMode(.expanded)
                }

            ZStack(alignment: .trailing) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.requestIslandMode(.expanded)
                    }

                ControlButton(icon: model.timerState.isRunning ? "pause.fill" : "play.fill", size: 27) {
                    model.toggleTimer()
                }
                .help(model.timerState.isRunning ? "暂停计时" : "开始计时")
                .padding(.trailing, 10)
            }
            .frame(width: model.compactWingWidth, height: model.topBandHeight, alignment: .trailing)
        }
    }
}

struct CompactNotification: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 25, height: 25)
                        .background(Circle().fill(Color.white.opacity(0.1)))

                    if model.notification.count > 1 {
                        Text("\(model.notification.count)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 13, height: 13)
                            .background(Circle().fill(Color.white))
                            .offset(x: 4, y: -4)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.notification.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                    Text(model.notification.body)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            .padding(.leading, 10)
            .frame(width: model.compactWingWidth, height: model.topBandHeight, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                model.requestIslandMode(.expanded)
            }

            Color.clear
                .frame(width: model.notchWidth, height: model.topBandHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.requestIslandMode(.expanded)
                }

            ZStack(alignment: .trailing) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.requestIslandMode(.expanded)
                    }

                ControlButton(icon: "xmark", size: 27) {
                    model.dismissNotification()
                }
                .help("关闭提醒")
                .padding(.trailing, 10)
            }
            .frame(width: model.compactWingWidth, height: model.topBandHeight, alignment: .trailing)
        }
    }
}

struct ExpandedMusic: View {
    @ObservedObject var model: IslandModel

    var displayLyrics: [String] {
        cleanIslandLyricLines(model.music.track.lyrics)
    }

    var currentLyric: String {
        let lyrics = displayLyrics
        guard lyrics.indices.contains(model.music.lyricIndex) else { return "" }
        return lyrics[model.music.lyricIndex]
    }

    var nextLyric: String {
        let lyrics = displayLyrics
        guard lyrics.count > 1 else { return "" }
        return lyrics[(model.music.lyricIndex + 1) % lyrics.count]
    }

    var body: some View {
        HStack(spacing: 12) {
            AlbumArt(track: model.music.track, size: 88)

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.music.track.title)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                    Text(model.music.track.artist)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.58))
                }
                .padding(.trailing, 72)
                .frame(maxWidth: .infinity, alignment: .leading)

                MusicProgressRow(model: model)

                if !displayLyrics.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentLyric)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.9))
                        Text(nextLyric)
                            .font(.system(size: 11, weight: .regular))
                            .lineLimit(1)
                            .foregroundStyle(.white.opacity(0.38))
                    }
                    .frame(height: 30, alignment: .topLeading)
                }

                HStack(spacing: 12) {
                    ControlButton(
                        icon: "backward.fill",
                        feedbackToken: model.pendingTrackControl == .previousTrack
                            ? model.trackControlFeedbackGeneration
                            : 0
                    ) {
                        model.previousTrack()
                    }
                    .help("上一首")

                    ControlButton(
                        icon: model.music.isPlaying ? "pause.fill" : "play.fill",
                        prominent: true,
                        feedbackToken: model.playPauseFeedbackGeneration
                    ) {
                        model.playPause()
                    }
                    .help(model.music.isPlaying ? "暂停" : "播放")

                    ControlButton(
                        icon: "forward.fill",
                        feedbackToken: model.pendingTrackControl == .nextTrack
                            ? model.trackControlFeedbackGeneration
                            : 0
                    ) {
                        model.nextTrack()
                    }
                    .help("下一首")
                }
                .frame(width: 224, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 308, alignment: .leading)
        }
        .frame(width: 408, alignment: .center)
        .offset(x: 2)
    }
}

private struct MusicProgressRow: View {
    @ObservedObject var model: IslandModel
    @State private var scrubPreviewProgress: Double?

    var body: some View {
        HStack(spacing: 10) {
            ProgressPill(
                progress: model.music.progress,
                width: 224,
                onPreviewChanged: { progress in
                    model.setMusicScrubbing(progress != nil)
                    guard let progress else {
                        scrubPreviewProgress = nil
                        return
                    }

                    if let duration = model.music.duration, duration > 0,
                       let currentPreview = scrubPreviewProgress,
                       Int(currentPreview * duration) == Int(progress * duration) {
                        return
                    }
                    scrubPreviewProgress = progress
                },
                onSeek: model.music.canSeek ? { progress, interaction in
                    await model.seekMusic(to: progress, interaction: interaction)
                } : nil
            )
            .help(model.music.canSeek ? "拖动调整播放进度" : "当前歌曲暂不支持进度拖动")

            Text(playbackPositionText(model.music, progressOverride: scrubPreviewProgress))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .foregroundStyle(.white.opacity(0.52))
                .frame(width: 74, alignment: .leading)
        }
        .onDisappear {
            model.setMusicScrubbing(false)
        }
    }
}

struct ExpandedTimer: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: model.timerState.progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(timeText(model.timerState.remaining))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 7) {
                Text(model.timerState.isRunning ? "专注计时中" : "计时器已暂停")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                ProgressPill(progress: model.timerState.progress, width: 232)
                HStack(spacing: 10) {
                    ControlButton(icon: model.timerState.isRunning ? "pause.fill" : "play.fill", prominent: true) {
                        model.toggleTimer()
                    }
                    .help(model.timerState.isRunning ? "暂停" : "开始")

                    ControlButton(icon: "arrow.counterclockwise") {
                        model.resetTimer()
                    }
                    .help("重置")

                    ControlButton(icon: "plus") {
                        model.addMinute()
                    }
                    .help("加 1 分钟")
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: 232, alignment: .leading)

        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct ExpandedNotification: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Color.white.opacity(0.1)))

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.notification.source)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                    Text(model.notification.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(model.notification.body)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer()
            }

            HStack(spacing: 12) {
                if model.canOpenActiveEventSource {
                    TextButton(title: "打开", systemName: "arrow.up.forward.app") {
                        model.openActiveEventSource()
                    }
                }
                TextButton(title: "关闭", systemName: "xmark") {
                    model.dismissNotification()
                }
                Spacer()
            }
        }
    }
}

func cleanIslandLyricLines(_ lines: [String]) -> [String] {
    let diagnosticTokens = [
        "MediaRemote",
        "Adapter",
        "来源：",
        "播放态：",
        "已发送",
        "已请求",
        "实时同步",
        "同步来源",
        "辅助功能",
        "控制中心",
        "手动诊断",
        "适配器",
        "PID "
    ]

    return lines
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { line in
            guard !line.isEmpty else { return false }
            return !diagnosticTokens.contains { line.localizedCaseInsensitiveContains($0) }
        }
}

struct AlbumArt: View {
    let track: MusicTrack
    let size: CGFloat

    var body: some View {
        ZStack {
            if let artworkData = track.artworkData,
               let image = NSImage(data: artworkData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let artworkURL = track.artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackArtwork
                    }
                }
            } else {
                fallbackArtwork
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if size >= 60 {
                MusicSourceBadge(bundleIdentifier: track.sourceBundleIdentifier, size: 18)
                    .offset(x: 3, y: 3)
            }
        }
    }

    private var fallbackArtwork: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: track.hasArtwork ? track.palette : [Color.white.opacity(0.13), Color.white.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: size * 0.55, height: size * 0.55)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                }
            }
    }
}

@MainActor
private final class MusicSourceIconCache {
    static let shared = MusicSourceIconCache()

    private var icons: [String: NSImage] = [:]
    private var missingBundleIdentifiers: Set<String> = []

    func icon(for bundleIdentifier: String) -> NSImage? {
        if let cached = icons[bundleIdentifier] {
            return cached
        }
        if missingBundleIdentifiers.contains(bundleIdentifier) {
            return nil
        }
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            missingBundleIdentifiers.insert(bundleIdentifier)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        icons[bundleIdentifier] = icon
        return icon
    }
}

private struct MusicSourceBadge: View {
    let bundleIdentifier: String?
    let size: CGFloat

    private var applicationIcon: NSImage? {
        guard let bundleIdentifier else { return nil }
        return MusicSourceIconCache.shared.icon(for: bundleIdentifier)
    }

    var body: some View {
        Group {
            if let applicationIcon {
                Image(nsImage: applicationIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size + 2, height: size + 2)
                    .frame(width: size, height: size)
                    .clipShape(
                        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    )
                    .compositingGroup()
                    .transition(.opacity)
            } else if bundleIdentifier != nil {
                Image(systemName: "music.note")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: size, height: size)
                    .background(
                        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                            .fill(Color.black.opacity(0.9))
                    )
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.14), value: bundleIdentifier)
    }
}

struct ControlButton: View {
    let icon: String
    var prominent = false
    var size: CGFloat = 30
    var feedbackToken: UInt64 = 0
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var feedbackPulse = false
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        prominent
                            ? Color.white
                            : Color.white.opacity(feedbackPulse ? 0.24 : 0.1)
                    )

                Image(systemName: icon)
                    .font(.system(size: prominent ? 13 : 12, weight: .bold))
                    .foregroundStyle(prominent ? Color.black : Color.white.opacity(0.9))
                    .scaleEffect(
                        feedbackPulse && !reduceMotion && !prominent ? 1.1 : 1
                    )
                    .id(icon)
                    .transition(iconTransition)
            }
            .frame(width: prominent ? 34 : size, height: prominent ? 34 : size)
            .scaleEffect(
                feedbackPulse && prominent && !reduceMotion ? 0.96 : 1
            )
        }
        .buttonStyle(IslandControlButtonStyle())
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.08)
                : prominent
                    ? .easeOut(duration: 0.1)
                    : .interactiveSpring(response: 0.2, dampingFraction: 0.86),
            value: icon
        )
        .onChange(of: feedbackToken) { _, token in
            guard token > 0 else { return }
            triggerFeedbackPulse(token: token)
        }
        .onDisappear {
            feedbackTask?.cancel()
            feedbackTask = nil
            feedbackPulse = false
        }
    }

    private var iconTransition: AnyTransition {
        guard !reduceMotion, !prominent else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.76)),
            removal: .opacity.combined(with: .scale(scale: 1.08))
        )
    }

    private func triggerFeedbackPulse(token: UInt64) {
        feedbackTask?.cancel()
        feedbackPulse = false
        withAnimation(.easeOut(duration: reduceMotion ? 0.05 : 0.08)) {
            feedbackPulse = true
        }

        feedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: reduceMotion ? 90_000_000 : 120_000_000)
            guard !Task.isCancelled, token == feedbackToken else { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0.08 : 0.14)) {
                feedbackPulse = false
            }
        }
    }
}

private struct IslandControlButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.06)
                    : .interactiveSpring(response: 0.16, dampingFraction: 0.9),
                value: configuration.isPressed
            )
    }
}

struct TextButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(Capsule().fill(Color.white))
        }
        .buttonStyle(.plain)
    }
}

struct ProgressPill: View {
    let progress: Double
    let width: CGFloat
    var onPreviewChanged: ((Double?) -> Void)? = nil
    var onSeek: ((Double, MusicSeekInteraction) async -> Bool)? = nil

    @State private var dragProgress: Double?
    @State private var isDragging = false
    @State private var seekGeneration = 0

    private var displayedProgress: Double {
        min(max(dragProgress ?? progress, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width, 1)
            let knobSize: CGFloat = onSeek == nil ? 0 : 9
            let progressWidth = availableWidth * displayedProgress
            let knobTravelWidth = max(availableWidth - knobSize, 0)
            let knobX = knobTravelWidth * displayedProgress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.13))
                    .frame(height: 4)
                    .frame(maxHeight: .infinity, alignment: .center)

                Capsule()
                    .fill(Color.white.opacity(isDragging ? 0.96 : 0.88))
                    .frame(width: progressWidth, height: 4)
                    .frame(maxHeight: .infinity, alignment: .center)

                if onSeek != nil {
                    Circle()
                        .fill(Color.white)
                        .frame(width: knobSize, height: knobSize)
                        .scaleEffect(isDragging ? 1.25 : 1)
                        .shadow(color: Color.black.opacity(isDragging ? 0.42 : 0.28), radius: isDragging ? 5 : 3, x: 0, y: 1)
                        .animation(.easeOut(duration: 0.12), value: isDragging)
                        .offset(x: knobX)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .exclusively(before: DragGesture(minimumDistance: 3))
                    .onChanged { value in
                        guard case let .second(drag) = value,
                              onSeek != nil else { return }
                        if !isDragging {
                            seekGeneration += 1
                        }
                        isDragging = true
                        dragProgress = min(max(drag.location.x / availableWidth, 0), 1)
                        onPreviewChanged?(dragProgress)
                    }
                    .onEnded { value in
                        switch value {
                        case let .first(tap):
                            guard onSeek != nil else { return }
                            seekGeneration += 1
                            isDragging = false
                            let targetProgress = min(max(tap.location.x / availableWidth, 0), 1)
                            dragProgress = targetProgress
                            onPreviewChanged?(targetProgress)
                            submitSeek(to: targetProgress, interaction: .click)
                        case let .second(drag):
                            let targetProgress = min(max(drag.location.x / availableWidth, 0), 1)
                            dragProgress = targetProgress
                            isDragging = false
                            guard onSeek != nil else {
                                dragProgress = nil
                                onPreviewChanged?(nil)
                                return
                            }
                            submitSeek(to: targetProgress, interaction: .drag)
                        }
                    }
            )
        }
        .frame(width: width, height: onSeek == nil ? 4 : 22)
    }

    private func submitSeek(to targetProgress: Double, interaction: MusicSeekInteraction) {
        guard let onSeek else { return }
        let generation = seekGeneration
        Task { @MainActor in
            let didSeek = await onSeek(targetProgress, interaction)
            guard generation == seekGeneration else { return }
            if didSeek {
                dragProgress = nil
                onPreviewChanged?(nil)
            } else {
                withAnimation(.easeOut(duration: 0.14)) {
                    dragProgress = nil
                }
                onPreviewChanged?(nil)
            }
        }
    }
}

struct StatusDot: View {
    let isActive: Bool
    let accentColor: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        StatusWaveformLayerView(
            isActive: isActive,
            accentColor: accentColor,
            reduceMotion: reduceMotion
        )
        .frame(width: 10, height: 10)
    }
}

private struct StatusWaveformLayerView: NSViewRepresentable {
    let isActive: Bool
    let accentColor: Color
    let reduceMotion: Bool

    func makeNSView(context: Context) -> StatusWaveformNSView {
        StatusWaveformNSView()
    }

    func updateNSView(_ nsView: StatusWaveformNSView, context: Context) {
        nsView.update(
            isActive: isActive,
            accentColor: NSColor(accentColor),
            reduceMotion: reduceMotion
        )
    }
}

private final class StatusWaveformNSView: NSView {
    private let bars = [CALayer(), CALayer(), CALayer()]
    private let activeOpacities: [CGFloat] = [1.0, 0.82, 0.68]
    private let inactiveOpacities: [CGFloat] = [0.40, 0.34, 0.30]
    private let animatedHeights: [[CGFloat]] = [
        [3, 7, 5, 8, 3],
        [7, 4, 8, 5, 7],
        [5, 8, 3, 6, 5]
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        for bar in bars {
            bar.bounds = CGRect(x: 0, y: 0, width: 1.8, height: 3)
            bar.cornerRadius = 0.9
            bar.cornerCurve = .continuous
            bar.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            layer?.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        let centerY = bounds.midY
        for (index, bar) in bars.enumerated() {
            bar.position = CGPoint(x: 1.2 + CGFloat(index) * 3.3, y: centerY)
        }
    }

    func update(isActive: Bool, accentColor: NSColor, reduceMotion: Bool) {
        let resolvedAccent = accentColor.usingColorSpace(.sRGB) ?? .white
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.20)
        for (index, bar) in bars.enumerated() {
            let opacity = isActive ? activeOpacities[index] : inactiveOpacities[index]
            let color = resolvedAccent.withAlphaComponent(opacity)
            bar.backgroundColor = color.cgColor
        }
        CATransaction.commit()

        if isActive, !reduceMotion {
            startAnimationsIfNeeded()
        } else {
            let heights: [CGFloat] = isActive ? [4, 7, 5] : [3, 3, 3]
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (index, bar) in bars.enumerated() {
                bar.removeAnimation(forKey: "waveHeight")
                bar.bounds.size.height = heights[index]
            }
            CATransaction.commit()
        }
    }

    private func startAnimationsIfNeeded() {
        for (index, bar) in bars.enumerated() {
            guard bar.animation(forKey: "waveHeight") == nil else { continue }
            let animation = CAKeyframeAnimation(keyPath: "bounds.size.height")
            animation.values = animatedHeights[index]
            animation.keyTimes = [0, 0.25, 0.5, 0.75, 1]
            animation.duration = 0.76
            animation.repeatCount = .infinity
            animation.calculationMode = .cubic
            animation.isRemovedOnCompletion = false
            bar.add(animation, forKey: "waveHeight")
        }
    }
}

func timeText(_ seconds: Int) -> String {
    let minutes = max(seconds, 0) / 60
    let secs = max(seconds, 0) % 60
    return String(format: "%02d:%02d", minutes, secs)
}

func playbackPositionText(_ music: MusicState, progressOverride: Double? = nil) -> String {
    guard let duration = music.duration, duration > 0 else { return "--:--" }
    let elapsed = progressOverride.map { duration * min(max($0, 0), 1) }
        ?? music.elapsedTime
        ?? (duration * min(max(music.progress, 0), 1))
    return "\(mediaTimeText(elapsed)) / \(mediaTimeText(duration))"
}

func mediaTimeText(_ seconds: TimeInterval) -> String {
    let totalSeconds = max(Int(seconds.rounded()), 0)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}

private let appDelegate = AppDelegate()
let app = NSApplication.shared
private let terminationSignalBridge = AppTerminationSignalBridge()
app.delegate = appDelegate
app.run()
