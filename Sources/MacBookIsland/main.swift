import AppKit
import ApplicationServices
import Combine
import QuartzCore
import SwiftUI

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
        print("progress=\(track.progress)")
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

enum IslandFeature: String, CaseIterable, Hashable {
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

    var label: String {
        switch self {
        case .music:
            return "音乐"
        case .timer:
            return "计时"
        case .notification:
            return "提醒"
        }
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

@MainActor
final class IslandModel: ObservableObject {
    @Published var mode: IslandMode = .collapsed
    @Published var activeFeature: IslandFeature = .music
    @Published var notchWidth: CGFloat = 185
    @Published var topBandHeight: CGFloat = 33
    let appSettings = AppSettings()
    let layout = LayoutCalibrationSettings()
    @Published var music: MusicState
    @Published var musicSourceStatus = MusicSourceStatus(
        sourceName: "汽水音乐",
        availability: .preview,
        headline: "等待汽水音乐真实数据",
        detail: "当前不显示假歌曲；主线正在直接读取汽水音乐本地状态，系统播放信息仅保留为手动诊断。",
        checkedAt: Date()
    )
    @Published var timerState = TimerState(duration: 25 * 60, remaining: 25 * 60, isRunning: false)
    @Published var notification = IslandNotification(
        title: "灵动岛原型已就绪",
        body: "音乐、计时器和提醒已经可以在顶部区域切换。",
        source: "MacBook Island",
        count: 1
    )
    @Published var isVisible = true

    private let musicAdapter = MusicAdapterCoordinator()
    private var ticker: Timer?
    private var musicRefreshBurstTask: Task<Void, Never>?
    private var layoutCancellable: AnyCancellable?
    private var lastTimerUpdateAt: Date?
    private var lastIslandModeTapAt: Date = .distantPast
    private var lastDirectControlAt: Date = .distantPast
    private var lastMusicProgressPublishAt: Date = .distantPast
    private let islandModeTapCooldown: TimeInterval = 0.72
    private let directControlSuppressionWindow: TimeInterval = 0.28
    private let musicProgressPublishInterval: TimeInterval = 0.85

    var collapsedWingWidth: CGFloat { 40 }
    var compactWingWidth: CGFloat { 126 }
    var expandedHeaderWingWidth: CGFloat { 48 }
    var expandedWingWidth: CGFloat { 178 }

    var collapsedWidth: CGFloat {
        notchWidth + collapsedWingWidth * 2
    }

    var compactWidth: CGFloat {
        notchWidth + compactWingWidth * 2
    }

    var expandedWidth: CGFloat {
        max(notchWidth + expandedWingWidth * 2, 540)
    }

    var expandedHeight: CGFloat {
        max(216, 256 + CGFloat(layout.expandedHeightAdjustment))
    }

    var expandedHeaderWidth: CGFloat {
        notchWidth + expandedHeaderWingWidth * 2
    }

    var expandedPanelTopGap: CGFloat {
        8
    }

    var expandedBodyHeight: CGFloat {
        max(184, expandedHeight - topBandHeight - expandedPanelTopGap)
    }

    init() {
        isVisible = appSettings.showIslandOnLaunch
        music = musicAdapter.initialState
        musicSourceStatus = musicAdapter.refreshSourceStatus(allowSynchronousRefresh: true)
        musicAdapter.startRealtimeObservation { [weak self] music, status in
            self?.applyMusicUpdate(music, status: status)
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
        activeFeature = feature
        mode = newMode
    }

    func toggleCollapsed() {
        requestIslandMode(mode == .collapsed ? .compact : .collapsed)
    }

    func toggleExpanded() {
        requestIslandMode(mode == .expanded ? .compact : .expanded)
    }

    func requestIslandMode(_ targetMode: IslandMode, bypassCooldown: Bool = false) {
        let now = Date()
        if !bypassCooldown {
            guard now.timeIntervalSince(lastDirectControlAt) > directControlSuppressionWindow else { return }
            guard now.timeIntervalSince(lastIslandModeTapAt) > islandModeTapCooldown else { return }
        }
        guard mode != targetMode else { return }
        lastIslandModeTapAt = now
        mode = targetMode
    }

    private func noteDirectControlInteraction() {
        lastDirectControlAt = Date()
    }

    func playPause() {
        noteDirectControlInteraction()
        let previousSignature = musicSignature(music)
        activeFeature = .music
        let outcome = musicAdapter.performControl(.playPause)
        musicSourceStatus = outcome.status
        if outcome.didSendCommand {
            music = musicAdapter.currentState()
            startMusicControlRefreshBurst(previousSignature: previousSignature, requireTrackChange: false)
        } else if outcome.shouldAdvancePreview {
            music = musicAdapter.playPause(music)
        }
        if mode == .collapsed {
            mode = .compact
        }
    }

    func nextTrack() {
        noteDirectControlInteraction()
        let previousSignature = musicSignature(music)
        let outcome = musicAdapter.performControl(.nextTrack)
        musicSourceStatus = outcome.status
        if outcome.didSendCommand {
            musicAdapter.invalidateQishuiCache()
            startMusicControlRefreshBurst(previousSignature: previousSignature, requireTrackChange: true)
        } else if outcome.shouldAdvancePreview {
            music = musicAdapter.nextTrack()
        }
        activeFeature = .music
        if mode == .collapsed {
            mode = .compact
        }
    }

    func previousTrack() {
        noteDirectControlInteraction()
        let previousSignature = musicSignature(music)
        let outcome = musicAdapter.performControl(.previousTrack)
        musicSourceStatus = outcome.status
        if outcome.didSendCommand {
            musicAdapter.invalidateQishuiCache()
            startMusicControlRefreshBurst(previousSignature: previousSignature, requireTrackChange: true)
        } else if outcome.shouldAdvancePreview {
            music = musicAdapter.previousTrack()
        }
        activeFeature = .music
        if mode == .collapsed {
            mode = .compact
        }
    }

    func showMusicSourceStatus() {
        musicSourceStatus = musicAdapter.refreshSourceStatus()
        music = musicAdapter.currentState()
    }

    func showAccessibilityStatus() {
        let trusted = AXIsProcessTrusted()
        let path = Bundle.main.bundlePath
        triggerNotification(
            title: trusted ? "辅助功能已授权" : "辅助功能未授权",
            body: trusted
                ? "当前运行的 MacBook Island 已通过系统辅助功能检查。"
                : "当前运行路径：\(path)。请在辅助功能中勾选这个 App；如果已有旧项，先删除旧项再添加当前 App。"
        )
    }

    func forceRefreshNowPlaying() {
        activeFeature = .music
        mode = .expanded
        let result = musicAdapter.forceRefreshNowPlaying()
        music = result.music
        musicSourceStatus = result.status
    }

    func seekMusic(to progress: Double) {
        noteDirectControlInteraction()
        activeFeature = .music
        let previousSignature = musicSignature(music)
        let result = musicAdapter.seek(to: progress)
        music = result.music
        musicSourceStatus = result.status
        startMusicControlRefreshBurst(previousSignature: previousSignature, requireTrackChange: false)
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        musicRefreshBurstTask?.cancel()
        musicRefreshBurstTask = nil
        musicAdapter.stopRealtimeObservation()
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

    func triggerNotification(title: String = "新的提醒", body: String = "这是一条来自灵动岛的低打扰提醒。") {
        notification = IslandNotification(
            title: title,
            body: body,
            source: "MacBook Island",
            count: min(notification.count + 1, 9)
        )
        activeFeature = .notification
        mode = .compact
    }

    func dismissNotification() {
        noteDirectControlInteraction()
        notification.count = 0
        activeFeature = .music
        mode = .compact
    }

    func snoozeNotification() {
        noteDirectControlInteraction()
        notification = IslandNotification(
            title: "稍后提醒",
            body: "已安排在稍后再次提示。",
            source: "MacBook Island",
            count: 1
        )
        activeFeature = .notification
        mode = .compact
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
        applyMusicUpdate(mediaUpdate.music, status: mediaUpdate.sourceStatus)

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
            triggerNotification(title: "时间到", body: "计时器已经结束。")
        }
    }

    private func startMusicControlRefreshBurst(previousSignature: String, requireTrackChange: Bool) {
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
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    let update = self.musicAdapter.refreshControlFollowUp()
                    self.applyMusicUpdate(update.music, status: update.status, forceMusic: true)
                    if self.shouldStopMusicControlRefreshBurst(
                        music: update.music,
                        status: update.status,
                        previousSignature: previousSignature,
                        requireTrackChange: requireTrackChange
                    ) {
                        self.musicRefreshBurstTask?.cancel()
                    }
                }
            }
        }
    }

    private func applyMusicUpdate(
        _ newMusic: MusicState,
        status newStatus: MusicSourceStatus?,
        forceMusic: Bool = false
    ) {
        if forceMusic || shouldPublishMusicUpdate(newMusic) {
            music = newMusic
        }

        if let newStatus,
           shouldPublishMusicStatus(newStatus) {
            musicSourceStatus = newStatus
        }
    }

    private func shouldPublishMusicUpdate(_ newMusic: MusicState) -> Bool {
        if newMusic.track != music.track
            || newMusic.isPlaying != music.isPlaying
            || newMusic.lyricIndex != music.lyricIndex
            || newMusic.duration != music.duration
            || newMusic.canSeek != music.canSeek
            || newMusic.isPlaybackPending != music.isPlaybackPending {
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
        guard status.availability == .qishuiDetectedAXLimited,
              !music.isPlaybackPending,
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
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = IslandModel()
    private var panel: IslandPanel?
    private var expandedPanel: IslandPanel?
    private var statusItem: NSStatusItem?
    private var calibrationWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private var outsideMouseMonitor: Any?
    private var outsideEventTap: CFMachPort?
    private var outsideEventTapRunLoopSource: CFRunLoopSource?
    private var panelAnimationID = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        updateScreenMetrics()
        createPanel()
        createStatusItem()
        observeModel()
        observeScreenChanges()
        observeOutsideClicks()
        updatePanelVisibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.presentOpenFeedback(shouldShowSettings: false)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentOpenFeedback(shouldShowSettings: true)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        if let outsideMouseMonitor {
            NSEvent.removeMonitor(outsideMouseMonitor)
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
    }

    private func createPanel() {
        let size = panelSize(for: model.mode)
        let panel = makeIslandPanel(size: size, level: .statusBar)

        let root = IslandRootView(model: model)
        let host = NSHostingView(rootView: root)
        configureIslandHostingView(host, size: size)
        panel.contentView = host

        let expandedSize = expandedPanelSize()
        let expandedPanel = makeIslandPanel(size: expandedSize, level: .floating)
        let expandedRoot = ExpandedIslandBodyPanel(model: model)
        let expandedHost = NSHostingView(rootView: expandedRoot)
        configureIslandHostingView(expandedHost, size: expandedSize)
        expandedPanel.contentView = expandedHost

        self.panel = panel
        self.expandedPanel = expandedPanel
        repositionPanel(animated: false)
        panel.orderFrontRegardless()
        expandedPanel.orderOut(nil)
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
        panel.ignoresMouseEvents = false
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isExcludedFromWindowsMenu = true
        return panel
    }

    private func configureIslandHostingView(_ hostingView: NSView, size: NSSize) {
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        hostingView.layer?.masksToBounds = false
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "MacBook Island") {
            image.isTemplate = true
            item.button?.image = image
            item.button?.imagePosition = .imageOnly
        } else {
            item.button?.title = "岛"
        }
        item.button?.toolTip = "MacBook Island"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示 / 隐藏灵动岛", action: #selector(toggleVisibility), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "音乐", action: #selector(showMusic), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "计时器", action: #selector(showTimer), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "触发提醒示例", action: #selector(triggerNotification), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "汽水适配状态", action: #selector(showMusicSourceStatus), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "辅助功能自检", action: #selector(showAccessibilityStatus), keyEquivalent: "a"))
        menu.addItem(NSMenuItem(title: "实验：打开系统播放诊断", action: #selector(forceRefreshNowPlaying), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "设置...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "校准布局...", action: #selector(showCalibration), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func observeModel() {
        model.$mode
            .sink { [weak self] _ in self?.repositionPanel(animated: true) }
            .store(in: &cancellables)

        model.$isVisible
            .sink { [weak self] _ in self?.updatePanelVisibility() }
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
            Task { @MainActor in
                self?.collapseExpandedIslandIfClickIsOutside()
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
        let headerFrame = panel.frame.insetBy(dx: -2, dy: -2)
        let bodyFrame = expandedPanel?.isVisible == true
            ? expandedPanel?.frame.insetBy(dx: -2, dy: -2)
            : nil
        guard !headerFrame.contains(clickPoint),
              bodyFrame?.contains(clickPoint) != true else { return }
        model.mode = .compact
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
        model.notchWidth = max(120, min(notchWidth, 240))
        model.topBandHeight = max(30, min(calibratedTopHeight, 42))
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
        switch mode {
        case .collapsed:
            return NSSize(width: model.collapsedWidth, height: model.topBandHeight)
        case .compact:
            return NSSize(width: model.compactWidth, height: model.topBandHeight)
        case .expanded:
            return NSSize(width: model.compactWidth, height: model.topBandHeight)
        }
    }

    private func expandedPanelSize() -> NSSize {
        NSSize(width: model.expandedWidth, height: model.expandedBodyHeight)
    }

    private func repositionPanel(animated: Bool) {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let size = panelSize(for: model.mode)
        let frame = panelFrame(for: size, on: screen)
        let bodySize = expandedPanelSize()
        let bodyFrame = expandedPanelFrame(for: bodySize, on: screen)

        guard animated else {
            panelAnimationID += 1
            panel.disableScreenUpdatesUntilFlush()
            panel.setFrame(frame, display: true)
            panel.contentView?.frame = NSRect(origin: .zero, size: size)

            expandedPanel?.disableScreenUpdatesUntilFlush()
            expandedPanel?.setFrame(bodyFrame, display: true)
            expandedPanel?.contentView?.frame = NSRect(origin: .zero, size: bodySize)
            expandedPanel?.alphaValue = 1
            updatePanelVisibility()
            return
        }

        panelAnimationID += 1
        let animationID = panelAnimationID

        if model.isVisible {
            panel.orderFrontRegardless()
            if model.mode == .expanded, let expandedPanel {
                if !expandedPanel.isVisible {
                    expandedPanel.alphaValue = 0
                }
                expandedPanel.orderFrontRegardless()
            }
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)

            if let expandedPanel,
               model.mode == .expanded || expandedPanel.isVisible {
                expandedPanel.animator().setFrame(bodyFrame, display: true)
                expandedPanel.animator().alphaValue = model.mode == .expanded ? 1 : 0
            }
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard self?.panelAnimationID == animationID else { return }
                self?.finishAnimatedReposition()
            }
        }
    }

    private func finishAnimatedReposition() {
        let size = panelSize(for: model.mode)
        panel?.contentView?.frame = NSRect(origin: .zero, size: size)

        let bodySize = expandedPanelSize()
        expandedPanel?.contentView?.frame = NSRect(origin: .zero, size: bodySize)
        expandedPanel?.alphaValue = 1
        updatePanelVisibility()
    }

    private func snapPanelToCurrentMode() {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let size = panelSize(for: model.mode)
        let frame = panelFrame(for: size, on: screen)
        let bodySize = expandedPanelSize()
        let bodyFrame = expandedPanelFrame(for: bodySize, on: screen)
        panel.setFrame(frame, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)

        expandedPanel?.setFrame(bodyFrame, display: true)
        expandedPanel?.contentView?.frame = NSRect(origin: .zero, size: bodySize)
        updatePanelVisibility()
    }

    private func panelFrame(for size: NSSize, on screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - CGFloat(model.layout.islandYOffset),
            width: size.width,
            height: size.height
        )
    }

    private func expandedPanelFrame(for size: NSSize, on screen: NSScreen) -> NSRect {
        let headerMinY = screen.frame.maxY - model.topBandHeight - CGFloat(model.layout.islandYOffset)
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: headerMinY - model.expandedPanelTopGap - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func updatePanelVisibility() {
        guard let panel else { return }
        if model.isVisible {
            panel.orderFrontRegardless()
            if model.mode == .expanded {
                expandedPanel?.orderFrontRegardless()
            } else {
                expandedPanel?.orderOut(nil)
            }
        } else {
            panel.orderOut(nil)
            expandedPanel?.orderOut(nil)
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
        model.showFeature(.timer)
    }

    @objc private func triggerNotification() {
        model.isVisible = true
        model.triggerNotification()
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
            window.title = "MacBook 灵动岛设置"
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
        model.activeFeature = .music
        if model.mode == .collapsed {
            model.mode = .compact
        }
        repositionPanel(animated: true)
        if shouldShowSettings {
            showSettings()
        }
    }

    @objc private func showCalibration() {
        model.isVisible = true
        model.mode = .expanded
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
            window.title = "灵动岛布局校准"
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

            MusicSettingsPane(model: model)
                .tabItem {
                    Label("音乐", systemImage: "music.note")
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
                Toggle("启动后显示灵动岛", isOn: $settings.showIslandOnLaunch)

                Toggle("点击外部自动收起展开面板", isOn: $settings.autoCollapseExpandedIsland)

                Toggle("当前显示灵动岛", isOn: $model.isVisible)
            }

            Section {
                Picker("默认功能", selection: $model.activeFeature) {
                    ForEach(IslandFeature.allCases, id: \.rawValue) { feature in
                        Label(feature.label, systemImage: feature.iconName)
                            .tag(feature)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button("折叠") {
                        model.isVisible = true
                        model.mode = .compact
                    }

                    Button("展开预览") {
                        model.isVisible = true
                        model.mode = .expanded
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

    var body: some View {
        Form {
            Section {
                LabeledContent("当前歌曲", value: "\(model.music.track.title) - \(model.music.track.artist)")
                LabeledContent("同步来源", value: model.musicSourceStatus.sourceName)
                LabeledContent("播放进度", value: playbackPositionText(model.music))
                LabeledContent("封面状态", value: model.music.track.artworkData == nil && model.music.track.artworkURL == nil ? "补充中" : "已获取")
            }

            Section {
                Button("立即刷新汽水状态") {
                    model.showMusicSourceStatus()
                }

                Button("重新读取当前播放") {
                    model.forceRefreshNowPlaying()
                }
            }

            Section {
                Text(model.musicSourceStatus.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                    Text("MacBook 灵动岛")
                        .font(.system(size: 20, weight: .semibold))
                    Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("当前版本是本地原型，音乐同步优先使用汽水音乐的实时播放源；发布前仍需要处理签名、公证和系统更新兼容性。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct IslandRootView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        Group {
            switch model.mode {
            case .collapsed:
                CollapsedIsland(model: model)
            case .compact:
                CompactIsland(model: model)
            case .expanded:
                ExpandedIsland(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.14), value: model.activeFeature)
    }
}

struct IslandShell<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    var fillOpacity: Double = 0.98
    var strokeOpacity: Double = 0.10
    var shadowOpacity: Double = 0
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: width, height: height)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(fillOpacity))
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(strokeOpacity), lineWidth: 0.65)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowOpacity > 0 ? 14 : 0, x: 0, y: shadowOpacity > 0 ? 8 : 0)
    }
}

struct CollapsedIsland: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        IslandShell(width: model.collapsedWidth, height: model.topBandHeight, cornerRadius: model.topBandHeight / 2) {
            ZStack {
                HStack(spacing: 0) {
                    Image(systemName: model.activeFeature.iconName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: model.collapsedWingWidth, height: model.topBandHeight)

                    Color.clear
                        .frame(width: model.notchWidth, height: model.topBandHeight)

                    StatusDot(isActive: model.music.isPlaying || model.timerState.isRunning)
                        .frame(width: model.collapsedWingWidth, height: model.topBandHeight)
                }

                NotchCore(width: model.notchWidth, height: model.topBandHeight)
                    .allowsHitTesting(false)
            }
        }
        .onTapGesture {
            model.requestIslandMode(.compact)
        }
    }
}

struct CompactIsland: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        IslandShell(width: model.compactWidth, height: model.topBandHeight, cornerRadius: model.topBandHeight / 2) {
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
                NotchCore(width: model.notchWidth, height: model.topBandHeight)
                    .allowsHitTesting(false)
            }
        }
        .onTapGesture {
            model.requestIslandMode(.expanded)
        }
    }
}

struct ExpandedIsland: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        IslandShell(width: model.expandedHeaderWidth, height: model.topBandHeight, cornerRadius: model.topBandHeight / 2) {
            ZStack {
                HStack(spacing: 0) {
                    Image(systemName: model.activeFeature.iconName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: model.expandedHeaderWingWidth, height: model.topBandHeight)

                    Color.clear
                        .frame(width: model.notchWidth, height: model.topBandHeight)

                    StatusDot(isActive: model.music.isPlaying || model.timerState.isRunning)
                        .frame(width: model.expandedHeaderWingWidth, height: model.topBandHeight)
                }

                NotchCore(width: model.notchWidth, height: model.topBandHeight)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct ExpandedIslandBodyPanel: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        IslandShell(width: model.expandedWidth, height: model.expandedBodyHeight, cornerRadius: 29, fillOpacity: 0.96, strokeOpacity: 0.08, shadowOpacity: 0) {
            VStack(spacing: 12) {
                HStack(alignment: .center) {
                    FeatureTabs(model: model)
                    Spacer(minLength: 12)
                    WindowModeButtons(model: model)
                }
                .frame(height: 28)

                Group {
                    switch model.activeFeature {
                    case .music:
                        ExpandedMusic(model: model)
                    case .timer:
                        ExpandedTimer(model: model)
                    case .notification:
                        ExpandedNotification(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }
}

struct ExpandedTopControls: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        ZStack(alignment: .top) {
            FeatureTabs(model: model)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, CGFloat(model.layout.leftControlsXOffset))
                .offset(y: CGFloat(model.layout.leftControlsYOffset))

            WindowModeButtons(model: model)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, CGFloat(model.layout.rightControlsXOffset))
                .offset(y: CGFloat(model.layout.rightControlsYOffset))
        }
        .padding(.top, CGFloat(model.layout.expandedTopControlsTopOffset))
        .frame(width: model.expandedWidth, alignment: .top)
    }
}

struct FeatureTabs: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 5) {
            ForEach(IslandFeature.allCases, id: \.rawValue) { feature in
                Button {
                    model.activeFeature = feature
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: feature.iconName)
                        Text(feature.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(model.activeFeature == feature ? Color.black : Color.white.opacity(0.72))
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(
                        Capsule()
                            .fill(model.activeFeature == feature ? Color.white : Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .help(feature.label)
            }
        }
    }
}

struct WindowModeButtons: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.requestIslandMode(.compact, bypassCooldown: true)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 28, height: 28)
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
                    .frame(width: 28, height: 28)
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

                ControlButton(icon: model.music.isPlaying ? "pause.fill" : "play.fill", pending: model.music.isPlaybackPending, size: 27) {
                    model.playPause()
                }
                .help(model.music.isPlaying ? "暂停" : "播放")
            }
            .padding(.trailing, 10)
            .frame(width: model.compactWingWidth, height: model.topBandHeight, alignment: .trailing)
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

            Color.clear
                .frame(width: model.notchWidth, height: model.topBandHeight)

            ControlButton(icon: model.timerState.isRunning ? "pause.fill" : "play.fill", size: 27) {
                model.toggleTimer()
            }
            .help(model.timerState.isRunning ? "暂停计时" : "开始计时")
            .padding(.trailing, 10)
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

            Color.clear
                .frame(width: model.notchWidth, height: model.topBandHeight)

            ControlButton(icon: "xmark", size: 27) {
                model.dismissNotification()
            }
            .help("关闭提醒")
            .padding(.trailing, 10)
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
        HStack(spacing: 16) {
            AlbumArt(track: model.music.track, size: 82)

            VStack(alignment: .leading, spacing: 10) {
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

                HStack(spacing: 10) {
                    ProgressPill(
                        progress: model.music.progress,
                        width: 224,
                        onSeek: model.music.canSeek ? { progress in
                            model.seekMusic(to: progress)
                        } : nil
                    )
                    .help(model.music.canSeek ? "拖动调整播放进度" : "当前歌曲暂不支持进度拖动")

                    Text(playbackPositionText(model.music))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.52))
                        .frame(width: 74, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(currentLyric)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.9))
                    Text(nextLyric)
                        .font(.system(size: 12, weight: .regular))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.38))
                }
                .frame(height: 36, alignment: .topLeading)

                HStack(spacing: 12) {
                    ControlButton(icon: "backward.fill") {
                        model.previousTrack()
                    }
                    .help("上一首")

                    ControlButton(icon: model.music.isPlaying ? "pause.fill" : "play.fill", prominent: true, pending: model.music.isPlaybackPending) {
                        model.playPause()
                    }
                    .help(model.music.isPlaying ? "暂停" : "播放")

                    ControlButton(icon: "forward.fill") {
                        model.nextTrack()
                    }
                    .help("下一首")

                    Spacer()
                }
            }
        }
    }
}

struct ExpandedTimer: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: model.timerState.progress)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(timeText(model.timerState.remaining))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 8) {
                    Text(model.timerState.isRunning ? "专注计时中" : "计时器已暂停")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("结束后会切换为顶部提醒。")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.54))
                    ProgressPill(progress: model.timerState.progress, width: 226)
                }

                Spacer()
            }

            HStack(spacing: 12) {
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

                Spacer()
            }
        }
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
                TextButton(title: "完成", systemName: "checkmark") {
                    model.dismissNotification()
                }
                TextButton(title: "稍后", systemName: "clock") {
                    model.snoozeNotification()
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

struct NotchCore: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color.black.opacity(0.98))
            .frame(width: width, height: height)
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

struct ControlButton: View {
    let icon: String
    var prominent = false
    var pending = false
    var size: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: prominent ? 13 : 12, weight: .bold))
                .foregroundStyle(prominent ? Color.black : Color.white.opacity(0.86))
                .frame(width: prominent ? 34 : size, height: prominent ? 34 : size)
                .background(
                    Circle()
                        .fill(prominent ? Color.white : Color.white.opacity(0.1))
                )
                .overlay {
                    if pending {
                        Circle()
                            .trim(from: 0.08, to: 0.82)
                            .stroke(
                                prominent ? Color.black.opacity(0.42) : Color.white.opacity(0.46),
                                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .padding(2)
                    }
                }
        }
        .buttonStyle(.plain)
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
    var onSeek: ((Double) -> Void)? = nil

    @State private var dragProgress: Double?
    @State private var isDragging = false

    private var displayedProgress: Double {
        min(max(dragProgress ?? progress, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width, 1)
            let knobSize: CGFloat = onSeek == nil ? 0 : (isDragging ? 12 : 9)
            let progressWidth = max(6, availableWidth * displayedProgress)
            let knobX = min(max(0, progressWidth - knobSize / 2), availableWidth - knobSize)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.13))
                    .frame(height: isDragging ? 5 : 4)
                    .frame(maxHeight: .infinity, alignment: .center)

                Capsule()
                    .fill(Color.white.opacity(isDragging ? 0.96 : 0.88))
                    .frame(width: progressWidth, height: isDragging ? 5 : 4)
                    .frame(maxHeight: .infinity, alignment: .center)

                if onSeek != nil {
                    Circle()
                        .fill(Color.white)
                        .frame(width: knobSize, height: knobSize)
                        .shadow(color: Color.black.opacity(isDragging ? 0.42 : 0.28), radius: isDragging ? 5 : 3, x: 0, y: 1)
                        .offset(x: knobX)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .animation(.spring(response: 0.18, dampingFraction: 0.75), value: isDragging)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard onSeek != nil else { return }
                        isDragging = true
                        dragProgress = min(max(value.location.x / availableWidth, 0), 1)
                    }
                    .onEnded { value in
                        guard let onSeek else { return }
                        let targetProgress = min(max(value.location.x / availableWidth, 0), 1)
                        dragProgress = targetProgress
                        isDragging = false
                        onSeek(targetProgress)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                            if let pending = dragProgress,
                               abs(pending - progress) > 0.025 {
                                dragProgress = nil
                            }
                        }
                    }
            )
        }
        .frame(width: width, height: onSeek == nil ? 4 : 22)
        .onChange(of: progress) { _, newProgress in
            guard let pending = dragProgress else { return }
            if abs(pending - newProgress) < 0.025 {
                dragProgress = nil
            }
        }
    }
}

struct StatusDot: View {
    let isActive: Bool

    var body: some View {
        Circle()
            .fill(isActive ? Color.green : Color.white.opacity(0.35))
            .frame(width: 7, height: 7)
            .shadow(color: isActive ? Color.green.opacity(0.6) : .clear, radius: 5)
    }
}

func timeText(_ seconds: Int) -> String {
    let minutes = max(seconds, 0) / 60
    let secs = max(seconds, 0) % 60
    return String(format: "%02d:%02d", minutes, secs)
}

func playbackPositionText(_ music: MusicState) -> String {
    guard let duration = music.duration, duration > 0 else { return "--:--" }
    let elapsed = music.elapsedTime ?? (duration * min(max(music.progress, 0), 1))
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
app.delegate = appDelegate
app.run()
