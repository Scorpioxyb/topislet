import AppKit
import ApplicationServices
import Combine
import Darwin
import EventKit
import ImageIO
import QuartzCore
import SwiftUI

final class IslandPanel: NSPanel {
    var onLeftMouseDown: ((NSEvent) -> Void)?
    var frameAnimationTarget: CGRect?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // animator() is an Objective-C forwarding proxy, not an IslandPanel.
    // Swift direct dispatch would access our stored properties on that proxy.
    @objc dynamic override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        guard let target = frameAnimationTarget else {
            super.setFrame(frameRect, display: flag)
            return
        }
        let anchored = IslandAnimationFrame.anchored(frameRect, to: target)
        super.setFrame(anchored, display: flag)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            onLeftMouseDown?(event)
            if !isKeyWindow { makeKey() }
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
    private var screenRefreshTask: Task<Void, Never>?
    private var accessibilityDisplayObserver: NSObjectProtocol?
    private var outsideMouseMonitor: Any?
    private var hoverGlobalMouseMonitor: Any?
    private var hoverLocalMouseMonitor: Any?
    private var outsideEventTap: CFMachPort?
    private var outsideEventTapRunLoopSource: CFRunLoopSource?
    private var panelAnimationGate = IslandAnimationCompletionGate()
    private var targetDisplayIdentity: String?
    private var stableDisplayIdentityCache: [UInt32: String] = [:]
    private var activeDisplayGeometry: IslandDisplayGeometry?
    private var hoverEnterTask: Task<Void, Never>?
    private var hoverExitTask: Task<Void, Never>?
    private var isPointerInsideHoverZone = false
    private var didExpandFromHover = false
    private var hoverReturnMode: IslandMode?
    private var hoverGeneration = 0
    private var hoverExpectedModeChange: IslandMode?
    private var hoverPointerCoalescer = LatestEventCoalescer<CGPoint>()
    private var hoverDeliveryWorkItem: DispatchWorkItem?
    private var panelFrameAnimationTarget: CGRect?
    private var panelFrameAnimationID: Int?
    private var fullScreenSuppressionTimer: Timer?
    private var fullScreenWorkspaceObservers: [NSObjectProtocol] = []
    private var isSuppressedByFullScreen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let path = PreviewSnapshot.outputPath(
            arguments: CommandLine.arguments,
            isPreview: model.isPreviewPresentation
        ) {
            let succeeded = PreviewSnapshot.render(model: model, to: path)
            exit(succeeded ? 0 : 1)
        }
        #endif
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
        observeAccessibilityDisplayOptions()
        observeOutsideClicks()
        observeIslandHover()
        observeFullScreenChanges()
        updatePanelVisibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.presentOpenFeedback(shouldShowSettings: false)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard !model.isPreviewPresentation else { return }
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
        stopPanelFrameAnimation()
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
        screenRefreshTask?.cancel()
        screenRefreshTask = nil
        fullScreenSuppressionTimer?.invalidate()
        fullScreenSuppressionTimer = nil
        for observer in fullScreenWorkspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        fullScreenWorkspaceObservers.removeAll()
        if let accessibilityDisplayObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityDisplayObserver)
        }
        hoverEnterTask?.cancel()
        hoverExitTask?.cancel()
        hoverDeliveryWorkItem?.cancel()
        hoverDeliveryWorkItem = nil
        hoverPointerCoalescer.cancel()
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

        let root = IslandRootView(
            model: model,
            onOpenSettings: { [weak self] in self?.showSettings() },
            onQuit: { [weak self] in self?.quit() }
        )
        let host = IslandHostingView(rootView: root)
        configureIslandHostingView(host, size: size)
        panel.contentView = host
        panel.delegate = self
        panel.onLeftMouseDown = { [weak self, weak panel] event in
            guard let self, let panel,
                  model.mode == .expanded,
                  model.isVisible,
                  interactionRegions(for: panel.frame, mode: model.mode).contains(
                    panel.convertPoint(toScreen: event.locationInWindow), tolerance: 0
                  ) else { return }
            model.notePresentationInteraction()
        }

        self.panel = panel
        refreshFullScreenSuppression()
        repositionPanel(animated: false)
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
        panel.collectionBehavior = IslandPanelCollectionPolicy.behavior
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
        item.button?.image = BrandIdentity.menuBarImage()
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "顶屿"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示 / 隐藏顶屿", action: #selector(toggleVisibility), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "显示汽水音乐", action: #selector(showMusic), keyEquivalent: ""))
        let timerItem = NSMenuItem(title: "开始专注计时", action: nil, keyEquivalent: "")
        let timerMenu = NSMenu(title: "开始专注计时")
        for preset in FocusTimerPreset.allCases {
            let presetItem = NSMenuItem(
                title: preset.title,
                action: #selector(startTimerPreset(_:)),
                keyEquivalent: ""
            )
            presetItem.tag = preset.rawValue
            timerMenu.addItem(presetItem)
        }
        timerItem.submenu = timerMenu
        menu.addItem(timerItem)
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
        model.appSettings.$musicExpansionMode
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.cancelHoverPresentation()
                self?.invalidateHoverSampleAfterStateChange()
            }
            .store(in: &cancellables)
        model.appSettings.$showMusicLyrics
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                // Size from committed settings, not @Published's willSet value.
                DispatchQueue.main.async {
                    guard let self, self.model.activeFeature == .music else { return }
                    self.repositionPanel(animated: false, targetMode: self.model.mode)
                }
            }
            .store(in: &cancellables)
        model.presentationInteraction
            .sink { [weak self] in self?.handlePresentationInteraction() }
            .store(in: &cancellables)
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
                guard let self, model.mode == .expanded || model.mode == .compact else { return }
                repositionPanel(animated: true, targetMode: model.mode)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            model.$activeFeature.removeDuplicates(),
            model.$music.map(\.hasCurrentTrack).removeDuplicates()
        )
        .map { feature, hasTrack in
            IslandCollapsedLayout.wingWidth(feature: feature, hasCurrentMusicTrack: hasTrack)
        }
        .removeDuplicates()
        .dropFirst()
        .sink { [weak self] _ in
            // @Published is willSet: size from the committed activity state.
            DispatchQueue.main.async {
                guard let self, self.model.mode == .collapsed else { return }
                self.repositionPanel(animated: true, targetMode: .collapsed)
            }
        }
        .store(in: &cancellables)

        Publishers.CombineLatest(
            model.$music.map { $0.controlRecoveryAction != nil }.removeDuplicates(),
            model.$isRecoveringMusicControl.removeDuplicates()
        )
        .map { hasAction, isRecovering in
            MusicControlRecoveryPolicy.shouldPresentRecovery(
                isRecovering: isRecovering, hasRecoveryAction: hasAction
            )
        }
        .removeDuplicates()
        .dropFirst()
        .sink { [weak self] _ in
            // Published values arrive before their storage changes. Resize
            // from the committed model so the recovery row is not clipped.
            DispatchQueue.main.async {
                guard let self, self.model.mode == .expanded,
                      self.model.activeFeature == .activityCenter else { return }
                self.repositionPanel(animated: true)
            }
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
            IslandExpansionPolicy.allowsExpansion(
                activeFeature: feature,
                hasCurrentMusicTrack: hasCurrentTrack,
                hasPendingNotification: hasPendingNotification
            )
        }
        .removeDuplicates()
        .dropFirst()
        .sink { [weak self] _ in
            // Availability and feature changes are state updates, not pointer
            // movement. Re-reading NSEvent.mouseLocation here used to make a
            // lyric arrival or track switch expand the island even when the
            // user had not moved the mouse. Leave hover transitions to the
            // actual mouseMoved monitors below.
            self?.invalidateHoverSampleAfterStateChange()
        }
        .store(in: &cancellables)

        model.$music
            .map { music in
                MusicLyricPresentation.state(
                    lines: music.track.lyrics,
                    index: music.lyricIndex,
                    pairMixedLanguageLines: !music.track.lyricsAreDesktopSnapshot
                )
            }
            .removeDuplicates()
            .sink { [weak self] _ in
                // @Published emits from willSet. Defer until the committed
                // model value is visible so compactWidth/expandedHeight and
                // their SwiftUI content cannot observe different lyric states
                // during the same tick.
                DispatchQueue.main.async {
                    guard let self,
                          (self.model.mode == .compact || self.model.mode == .expanded),
                          self.model.activeFeature == .music else { return }
                    // Lyric availability changes both the compact width and the
                    // expanded body height. Apply the committed geometry after
                    // SwiftUI observes the same state, otherwise an arriving
                    // lyric shelf can be rendered below the old no-lyrics frame.
                    let mode = self.model.mode
                    self.repositionPanel(animated: false, targetMode: mode)
                }
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
                self?.handleScreenParametersChange()
            }
        }
    }

    private func observeFullScreenChanges() {
        refreshFullScreenSuppression()
        fullScreenSuppressionTimer = Timer.scheduledTimer(
            withTimeInterval: 0.15,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFullScreenSuppression()
            }
        }
        let applicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFullScreenSuppression()
            }
        }
        let activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFullScreenSuppression()
            }
        }
        fullScreenWorkspaceObservers = [applicationObserver, activeSpaceObserver]
    }

    @discardableResult
    private func synchronizeFullScreenSuppression() -> Bool {
        if model.isPreviewPresentation {
            let changed = isSuppressedByFullScreen
            isSuppressedByFullScreen = false
            return changed
        }
        guard let screen = targetScreen() else { return false }
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let hasCoveringWindow = IslandFullScreenWindowDetector.hasCoveringWindow(
            on: screen,
            excludingProcessIdentifier: ProcessInfo.processInfo.processIdentifier
        )
        let shouldSuppress = IslandFullScreenSuppressionPolicy.shouldSuppress(
            frontmostIsTopIslet: frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
            hasCoveringWindow: hasCoveringWindow
        )
        let changed = shouldSuppress != isSuppressedByFullScreen
        isSuppressedByFullScreen = shouldSuppress
        return changed
    }

    private func refreshFullScreenSuppression() {
        if synchronizeFullScreenSuppression() { updatePanelVisibility() }
    }

    private func handleScreenParametersChange() {
        screenRefreshTask?.cancel()
        stableDisplayIdentityCache.removeAll()
        refreshDisplayTopology()
        screenRefreshTask = Task { @MainActor [weak self] in
            for delay in IslandDisplayRefreshPolicy.stabilizationDelaysNanoseconds {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                self.refreshDisplayTopology()
            }
        }
    }

    private func refreshDisplayTopology() {
        _ = panelAnimationGate.beginAnimation()
        stopPanelFrameAnimation()
        updateScreenMetrics()
        repositionPanel(animated: false)
        updateIslandHover(at: NSEvent.mouseLocation)
    }

    private func observeAccessibilityDisplayOptions() {
        model.refreshAccessibilityDisplayOptions()
        accessibilityDisplayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.model.refreshAccessibilityDisplayOptions()
                self.repositionPanel(animated: false)
            }
        }
    }

    private func observeOutsideClicks() {
        outsideMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            let clickPoint = event.cgEvent.map {
                IslandOutsideClickLocation(
                    windowServerPoint: $0.location,
                    primaryDisplayHeight: CGDisplayBounds(CGMainDisplayID()).height
                ).appKitPoint
            } ?? NSEvent.mouseLocation
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
                let clickPoint = IslandOutsideClickLocation(
                    windowServerPoint: event.location,
                    primaryDisplayHeight: CGDisplayBounds(CGMainDisplayID()).height
                ).appKitPoint
                Task { @MainActor in
                    appDelegate.collapseExpandedIslandIfClickIsOutside(appKitLocation: clickPoint)
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
            MainActor.assumeIsolated {
                self?.enqueueIslandHover(at: point)
            }
        }
        hoverLocalMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            let point = NSEvent.mouseLocation
            MainActor.assumeIsolated {
                self?.enqueueIslandHover(at: point)
            }
            return event
        }
    }

    private func enqueueIslandHover(at point: CGPoint) {
        guard hoverPointerCoalescer.submit(point) else { return }
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hoverDeliveryWorkItem = nil
                guard let latestPoint = self.hoverPointerCoalescer.consume() else { return }
                self.updateIslandHover(at: latestPoint)
            }
        }
        hoverDeliveryWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(8),
            execute: workItem
        )
    }

    private func updateIslandHover(at point: CGPoint) {
        guard MusicInteractionPolicy.allowsHover(
            feature: model.activeFeature, expansion: model.appSettings.musicExpansionMode
        ) else { return }
        let isInside = model.canExpandIsland && isInsideIslandHoverZone(point)
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
                try? await Task.sleep(nanoseconds: 30_000_000)
                guard !Task.isCancelled,
                      let self,
                      hoverGeneration == generation,
                      isPointerInsideHoverZone,
                      model.canExpandIsland,
                      MusicInteractionPolicy.allowsHover(
                        feature: model.activeFeature, expansion: model.appSettings.musicExpansionMode
                      ),
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

    private func invalidateHoverSampleAfterStateChange() {
        hoverGeneration += 1
        hoverEnterTask?.cancel()
        hoverEnterTask = nil
        hoverExitTask?.cancel()
        hoverExitTask = nil
        // Force the next real mouseMoved event to establish a fresh boundary
        // crossing. Do not synthesize a crossing from a stale mouse location.
        isPointerInsideHoverZone = false
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
        cancelHoverPresentation()
    }

    private func handlePresentationInteraction() {
        guard !MusicInteractionPolicy.interactionEndsHoverPresentation(
            feature: model.activeFeature, expansion: model.appSettings.musicExpansionMode
        ) else {
            cancelHoverPresentation()
            return
        }
        // Hover-expanded music stays hover-owned after a click: drop a leave
        // already in flight, and treat the pointer as on the panel (it just
        // clicked there) so the next move off it collapses as usual, even if
        // the click resized the panel out from under the pointer.
        guard didExpandFromHover else { return }
        hoverGeneration += 1
        hoverExitTask?.cancel()
        hoverExitTask = nil
        isPointerInsideHoverZone = true
    }

    private func cancelHoverPresentation() {
        guard didExpandFromHover || hoverEnterTask != nil || hoverExitTask != nil else {
            return
        }
        hoverExpectedModeChange = nil
        hoverGeneration += 1
        hoverEnterTask?.cancel()
        hoverEnterTask = nil
        hoverExitTask?.cancel()
        hoverExitTask = nil
        didExpandFromHover = false
        hoverReturnMode = nil
    }

    private func collapseExpandedIslandIfClickIsOutside(appKitLocation clickPoint: CGPoint) {
        guard model.mode == .expanded, model.isVisible, let panel else { return }
        guard model.appSettings.autoCollapseExpandedIsland,
              MusicInteractionPolicy.allowsOutsideCollapse(
                feature: model.activeFeature, expansion: model.appSettings.musicExpansionMode
              ) else { return }
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
        model.collapseExpandedPresentation()
    }

    private func updateScreenMetrics() {
        guard let screen = targetScreen() else { return }

        model.layout.useDisplay(
            name: screen.localizedName,
            identity: calibrationDisplayIdentity(for: screen),
            legacyIdentities: [legacyCalibrationDisplayIdentity(for: screen)],
            legacyIdentityPrefixes: [legacyCalibrationDisplayIdentityPrefix(for: screen)]
        )

        let geometry = displayGeometry(for: screen)
        activeDisplayGeometry = geometry
        let nextNotchWidth = geometry.notchWidth
        let nextTopBandHeight = geometry.topBandHeight
        if abs(model.notchWidth - nextNotchWidth) > 0.25 {
            model.notchWidth = nextNotchWidth
        }
        if abs(model.topBandHeight - nextTopBandHeight) > 0.25 {
            model.topBandHeight = nextTopBandHeight
        }
        if model.hasCameraHousing != geometry.hasCameraHousing {
            model.hasCameraHousing = geometry.hasCameraHousing
        }
    }

    private func displayGeometry(for screen: NSScreen) -> IslandDisplayGeometry {
        IslandDisplayGeometry.resolve(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
            backingScaleFactor: screen.backingScaleFactor,
            notchHeightAdjustment: CGFloat(model.layout.notchHeightAdjustment)
        )
    }

    private func calibrationDisplayIdentity(for screen: NSScreen) -> String {
        IslandDisplayIdentity.calibrationIdentifier(
            stableIdentifier: stableDisplayIdentity(for: screen),
            frame: screen.frame,
            scale: screen.backingScaleFactor
        )
    }

    private func legacyCalibrationDisplayIdentity(for screen: NSScreen) -> String {
        let screenNumber = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber
        let frame = screen.frame
        return [
            screen.localizedName,
            "\(Int(frame.width))x\(Int(frame.height))",
            "scale\(screen.backingScaleFactor)",
            "id\(screenNumber?.stringValue ?? "unknown")"
        ].joined(separator: "-")
    }

    private func legacyCalibrationDisplayIdentityPrefix(for screen: NSScreen) -> String {
        let frame = screen.frame
        return [
            screen.localizedName,
            "\(Int(frame.width))x\(Int(frame.height))",
            "scale\(screen.backingScaleFactor)",
            "id"
        ].joined(separator: "-")
    }

    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            targetDisplayIdentity = nil
            activeDisplayGeometry = nil
            return nil
        }

        if let targetDisplayIdentity,
           let boundScreen = screens.first(where: {
               stableDisplayIdentity(for: $0) == targetDisplayIdentity
           }) {
            return boundScreen
        }

        let mainIdentity = NSScreen.main.map(stableDisplayIdentity(for:))
        let candidates = screens.map { screen in
            let identity = stableDisplayIdentity(for: screen)
            return IslandDisplayCandidate(
                identity: identity,
                hasCameraHousing: displayGeometry(for: screen).hasCameraHousing,
                isMain: identity == mainIdentity
            )
        }
        guard let selectedIdentity = IslandDisplaySelectionPolicy.selectIdentity(
            boundIdentity: targetDisplayIdentity,
            candidates: candidates
        ), let selectedScreen = screens.first(where: {
            stableDisplayIdentity(for: $0) == selectedIdentity
        }) else {
            return nil
        }

        targetDisplayIdentity = selectedIdentity
        return selectedScreen
    }

    private func stableDisplayIdentity(for screen: NSScreen) -> String {
        let displayID = (screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber)?.uint32Value
        if let displayID, let cachedIdentity = stableDisplayIdentityCache[displayID] {
            return cachedIdentity
        }
        let identity = IslandDisplayIdentity.stableIdentifier(
            displayID: displayID,
            physicalUUID: displayID.flatMap(IslandDisplayIdentity.physicalUUID(for:)),
            displayName: screen.localizedName,
            frame: screen.frame
        )
        if let displayID {
            stableDisplayIdentityCache[displayID] = identity
        }
        return identity
    }

    private func panelSize(for mode: IslandMode) -> NSSize {
        let size = IslandWindowLayout.size(
            for: mode,
            collapsedWidth: model.collapsedWidth,
            compactWidth: model.compactWidth,
            expandedWidth: model.expandedWidth,
            expandedHeight: model.expandedHeight,
            topBandHeight: model.topBandHeight
        )
        return NSSize(width: size.width.rounded(), height: size.height.rounded())
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
            headerWidth = model.usesUnifiedMusicExpandedSurface
                ? model.expandedWidth
                : model.expandedHeaderWidth
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
        guard let screen = targetScreen() else { return }

        let mode = targetMode ?? model.mode
        let size = panelSize(for: mode)
        let frame = panelFrame(for: size, on: screen)
        if mode == .expanded {
            model.pointerWasOverExpandedTarget = frame.contains(NSEvent.mouseLocation)
        }

        let animationDuration = IslandMotion.frameDuration(
            for: mode,
            reduceMotion: model.reduceMotionEnabled
        )
        stopPanelFrameAnimation()
        // A media/layout change can arrive before the periodic fullscreen
        // check. Recheck before any presentation, including animation start.
        synchronizeFullScreenSuppression()
        guard animated, animationDuration > 0,
              model.isVisible, !isSuppressedByFullScreen else {
            _ = panelAnimationGate.beginAnimation()
            panel.setFrame(frame, display: true)
            panel.contentView?.frame = NSRect(origin: .zero, size: size)
            updatePanelVisibility()
            return
        }

        let animationID = panelAnimationGate.beginAnimation()
        guard panel.frame != frame else { return }

        if model.isVisible, !isSuppressedByFullScreen {
            panel.orderFrontRegardless()
        }

        panelFrameAnimationTarget = frame
        panelFrameAnimationID = animationID
        panel.frameAnimationTarget = frame
        let points = IslandMotion.timingControlPoints(for: mode)
        IslandWindowFrameAnimation.install(on: panel, duration: animationDuration, controlPoints: points)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: Float(points.0), Float(points.1), Float(points.2), Float(points.3)
            )
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.panelFrameAnimationID == animationID,
                      self.panelAnimationGate.claimCompletion(
                        animationID: animationID, targetMode: mode, currentMode: self.model.mode
                      ) else { return }
                // AppKit has submitted the endpoint. Do not snap or retime it.
                self.panel?.frameAnimationTarget = nil
                if let panel = self.panel { IslandWindowFrameAnimation.remove(from: panel) }
                self.panelFrameAnimationTarget = nil
                self.panelFrameAnimationID = nil
            }
        }
    }

    private func stopPanelFrameAnimation() {
        // Freeze an interrupted animator at its currently observed frame.
        // This replaces its pending frame action before the next generation.
        if panelFrameAnimationTarget != nil, let panel {
            let current = panel.frame
            panel.frameAnimationTarget = nil
            IslandWindowFrameAnimation.remove(from: panel)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().setFrame(current, display: false)
            }
        }
        panelFrameAnimationTarget = nil
        panelFrameAnimationID = nil
    }

    private func panelFrame(for size: NSSize, on screen: NSScreen) -> NSRect {
        let geometry: IslandDisplayGeometry
        if let activeDisplayGeometry,
           activeDisplayGeometry.screenFrame == screen.frame {
            geometry = activeDisplayGeometry
        } else {
            geometry = displayGeometry(for: screen)
        }
        return IslandWindowLayout.frame(
            for: size,
            in: screen.frame,
            yOffset: CGFloat(model.layout.islandYOffset),
            anchorX: geometry.islandAnchorX,
            alignTopToWindowServer: true
        )
    }

    private func updatePanelVisibility() {
        guard let panel else { return }
        // Never reveal using a stale timer snapshot after a covering window
        // appeared. This read changes neither focus nor the source player.
        if model.isVisible { synchronizeFullScreenSuppression() }
        if model.isVisible, !isSuppressedByFullScreen {
            panel.orderFrontRegardless()
        } else {
            // Invalidate the old owner before submitting hidden geometry.
            if let target = panelFrameAnimationTarget {
                _ = panelAnimationGate.beginAnimation()
                stopPanelFrameAnimation()
                panel.setFrame(target, display: false)
                panel.contentView?.frame = NSRect(origin: .zero, size: target.size)
            }
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

    @objc private func startTimerPreset(_ sender: NSMenuItem) {
        model.isVisible = true
        model.startTimer(minutes: sender.tag)
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
        if model.mode == .collapsed,
           shouldShowSettings,
           !CommandLine.arguments.contains("--preview-feature"),
           !CommandLine.arguments.contains("--preview-mode") {
            model.handleCollapsedIslandTap()
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
final class AppTerminationSignalBridge {
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
