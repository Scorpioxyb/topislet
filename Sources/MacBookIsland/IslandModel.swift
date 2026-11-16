import AppKit
import ApplicationServices
import Combine
import Darwin
import EventKit
import ImageIO
import QuartzCore
import SwiftUI

@MainActor
final class IslandModel: ObservableObject {
    let isPreviewPresentation: Bool
    // Interaction ownership is independent of mode changes: pressing a control
    // in a hover-expanded panel cancels a pending hover return. Whether it
    // also ends the hover presentation is MusicInteractionPolicy's call.
    let presentationInteraction = PassthroughSubject<Void, Never>()
    @Published var mode: IslandMode = .collapsed
    /// Whether the pointer was inside the expanded panel's target frame when the
    /// panel was last sized for expansion. Read once when the expanded body mounts,
    /// so it opens in the pointer-over state instead of flashing the resting one.
    /// Not published: changing it never re-renders.
    var pointerWasOverExpandedTarget = false
    @Published var activeFeature: IslandFeature = .activityCenter
    @Published var notchWidth: CGFloat = 185
    @Published var topBandHeight: CGFloat = 33
    @Published var hasCameraHousing = true
    let appSettings = AppSettings()
    let loginItemSettings = LoginItemSettings()
    let layout = LayoutCalibrationSettings()
    @Published var music: MusicState
    @Published var musicAccentColor = Color.white
    @Published var pendingTrackControl: MusicControlCommand?
    @Published private(set) var trackControlFeedbackGeneration: UInt64 = 0
    @Published private(set) var playPauseFeedbackGeneration: UInt64 = 0
    @Published private(set) var isRecoveringMusicControl = false
    @Published private(set) var musicControlRecoveryNeedsUserAction = false
    @Published private(set) var latestMusicControlRecoverySummary = "未触发"
    @Published var musicSourceStatus = MusicSourceStatus(
        sourceName: "汽水音乐",
        availability: .preview,
        headline: "等待汽水音乐真实数据",
        detail: "当前不显示假歌曲；主线正在直接读取汽水音乐本地状态，系统播放信息仅保留为手动诊断。",
        checkedAt: Date()
    )
    @Published private(set) var qishuiIsRunning = false
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var neteaseMusicIsRunning = false
    @Published private(set) var neteaseMusicSnapshotAvailability: MusicAppAvailability?
    @Published private(set) var neteaseMusicConnectionStatus = "尚未检查"
    @Published private(set) var neteaseMusicAvailableControls = "无"
    @Published private(set) var appleMusicAutomationAccess: AppleMusicAutomationAccess = .unavailable(status: -1)
    @Published private(set) var appleMusicIsRunning = false
    @Published private(set) var appleMusicSnapshotAvailability: MusicAppAvailability?
    @Published private(set) var appleMusicConnectionStatus = "尚未检查"
    @Published private(set) var appleMusicAvailableControls = "无"
    @Published private(set) var appleMusicResponseLatencyMilliseconds: Int?
    @Published var timerState = TimerState(duration: 25 * 60, remaining: 25 * 60, isRunning: false)
    var musicTimelineSampledAt = Date()
    @Published var notification = IslandNotification(
        title: "",
        body: "",
        source: "顶屿",
        count: 0
    )
    @Published var eventKitStatus = EventKitActivityStatus.current
    @Published var isVisible = true
    @Published private(set) var reduceMotionEnabled = NSWorkspace.shared
        .accessibilityDisplayShouldReduceMotion

    var appleMusicTransitionDiagnostic: String {
        musicAdapter.appleMusicTransitionReport()
    }

    var latestAppleMusicTransitionDiagnostic: String {
        musicAdapter.latestAppleMusicTransitionReport()
    }

    private let musicAdapter = MusicAdapterCoordinator()
    private let eventKitSource = EventKitActivitySource()
    private var ticker: Timer?
    private var musicRefreshBurstTask: Task<Void, Never>?
    private var musicControlRecoveryTask: Task<Void, Never>?
    private var musicControlRecoveryAwaitingVerification = false
    private var musicAccentTask: Task<Void, Never>?
    private var musicAccentIdentity = ""
    private var musicAccentGeneration = 0
    private var trackControlFeedbackTask: Task<Void, Never>?
    private var pendingTrackControlBaselineSignature: String?
    private var pendingTrackControlGeneration: UInt64?
    private var pendingTrackControlChainCount = 0
    private var layoutCancellable: AnyCancellable?
    private var appleMusicSettingsCancellable: AnyCancellable?
    private var appSettingsCancellable: AnyCancellable?
    private var musicExpansionSettingsCancellable: AnyCancellable?
    private var musicLyricsSettingsCancellable: AnyCancellable?
    private var eventKitSettingsCancellable: AnyCancellable?
    private var appleMusicObservedProcessIdentifier: pid_t?
    private var appleMusicSettingsRequestGeneration: UInt64 = 0
    private var neteaseMusicObservedProcessIdentifier: pid_t?
    private var neteaseMusicSettingsRequestGeneration: UInt64 = 0
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

    // Idle stays within the camera housing; a live activity owns two small wings.
    var collapsedWingWidth: CGFloat {
        IslandCollapsedLayout.wingWidth(
            feature: activeFeature, hasCurrentMusicTrack: music.hasCurrentTrack
        )
    }
    var compactWingWidth: CGFloat {
        MusicCompactLayout.standardWingWidth
    }
    var compactLeadingWingWidth: CGFloat {
        MusicCompactLayout.standardWingWidth
    }
    var compactTrailingWingWidth: CGFloat {
        MusicCompactLayout.standardWingWidth
    }
    var expandedHeaderWingWidth: CGFloat { 34 }

    private var hasCurrentDisplayableLyric: Bool {
        guard activeFeature == .music else { return false }
        return MusicLyricPresentation.state(
            lines: music.track.lyrics,
            index: music.lyricIndex,
            pairMixedLanguageLines: !music.track.lyricsAreDesktopSnapshot
        ).isAvailable
    }

    var isMusicLyricsEnabled: Bool {
        CommandLine.arguments.contains("--preview-lyrics") || appSettings.showMusicLyrics
    }
    var hasPendingNotification: Bool {
        activeIslandEvent != nil || !pendingIslandEvents.isEmpty
    }

    var canExpandIsland: Bool {
        IslandExpansionPolicy.allowsExpansion(
            activeFeature: activeFeature,
            hasCurrentMusicTrack: music.hasCurrentTrack,
            hasPendingNotification: hasPendingNotification
        )
    }

    var canRecoverCurrentMusicControlPermission: Bool {
        MusicControlPermissionRecoveryPolicy.allowsRecovery(
            sourceBundleIdentifier: music.track.sourceBundleIdentifier,
            accessibilityTrusted: accessibilityTrusted
        )
    }

    var shouldPresentMusicControlRecovery: Bool {
        MusicControlRecoveryPolicy.shouldPresentRecovery(
            isRecovering: isRecoveringMusicControl,
            hasRecoveryAction: music.controlRecoveryAction != nil
        )
    }

    var musicControlsAvailable: Bool {
        MusicActivityPresentationPolicy.controlsAvailable(
            canPlayPause: music.canPlayPause,
            canPreviousTrack: music.canPreviousTrack,
            canNextTrack: music.canNextTrack
        )
    }

    var collapsedWidth: CGFloat {
        notchWidth + collapsedWingWidth * 2
    }

    var compactWidth: CGFloat {
        MusicCompactLayout.compactWidth(
            notchWidth: notchWidth,
            hasCurrentLyric: false
        )
    }

    var expandedWidth: CGFloat {
        switch activeFeature {
        case .activityCenter:
            return max(notchWidth + 140, 420)
        case .music:
            return max(notchWidth + 160, ExpandedMusicLayout.panelWidth)
        case .timer, .notification:
            return max(notchWidth + 140, 420)
        }
    }

    var expandedHeight: CGFloat {
        // Music expansion is a single surface. The old control-only branch
        // reserved a separate notch header above the player body, which made
        // the app render as two stacked black islands. Keep the header for
        // non-music expanded features, but let every expanded music state
        // own the full window with one capsule.
        if activeFeature == .music {
            return expandedBodyHeight
        }
        return topBandHeight + expandedPanelTopGap + expandedBodyHeight
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
            return activeFeature == .music ? expandedWidth : expandedHeaderWidth
        }
    }

    var statusWaveIsActive: Bool {
        switch activeFeature {
        case .activityCenter:
            return false
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
        (activeFeature == .music || isLyricExpandedPresentation) ? 0 : 8
    }

    /// Expanded music uses one horizontal capsule for both the control-only
    /// and lyric presentations. This is independent of lyric availability:
    /// a track without lyrics must not reintroduce the detached notch header.
    var usesUnifiedMusicExpandedSurface: Bool {
        mode == .expanded && activeFeature == .music
    }

    var isLyricExpandedPresentation: Bool {
        mode == .expanded && activeFeature == .music
            && isMusicLyricsEnabled
            && hasCurrentDisplayableLyric
    }

    var expandedBodyHeight: CGFloat {
        switch activeFeature {
        case .activityCenter:
            return max(112, (shouldPresentMusicControlRecovery ? 210 : 168)
                + CGFloat(layout.expandedHeightAdjustment))
        case .music:
            // Fixed for every track and lyric state, so late lyrics never
            // resize the window under the pointer.
            return topBandHeight + MusicExpandedLayout.bodyHeight(
                heightAdjustment: CGFloat(layout.expandedHeightAdjustment)
            )
        case .timer:
            return max(112, 146 + CGFloat(layout.expandedHeightAdjustment))
        case .notification:
            return max(112, 156 + CGFloat(layout.expandedHeightAdjustment))
        }
    }

    init() {
        let arguments = CommandLine.arguments
        isPreviewPresentation = arguments.contains("--preview-mode")
            || arguments.contains("--preview-feature")
            || arguments.contains("--preview-lyrics")
            || arguments.contains("--preview-no-lyrics")
        isVisible = isPreviewPresentation || appSettings.showIslandOnLaunch
        musicAdapter.setAppleMusicEnabled(appSettings.appleMusicEnabled)
        musicAdapter.setQishuiTimedLyricsEnabled(appSettings.showMusicLyrics)
        music = musicAdapter.initialState
        activeFeature = music.hasCurrentTrack ? .music : .activityCenter
        pendingTrackControl = nil
        if arguments.contains("--preview-lyrics") || arguments.contains("--preview-no-lyrics") {
            // Explicit visual QA fixture. It is only admitted when the
            // caller opts into preview mode and never enters the live adapter.
            let previewArtwork: Data? = {
                guard let index = arguments.firstIndex(of: "--preview-artwork"),
                      arguments.indices.contains(index + 1) else { return nil }
                return try? Data(contentsOf: URL(fileURLWithPath: arguments[index + 1]))
            }()
            let previewLyrics = arguments.contains("--preview-short-lyrics")
                ? ["Can you see it", "你是否能够看清", "Every weekend in the rave"]
                : ["Pull me through the night, I am still awake",
                   "把我带过漫长的夜，我还没有睡去",
                   "Every little heartbeat finds a way to break",
                   "每一次心跳都在寻找出口"]
            music = MusicState(
                track: MusicTrack(
                    title: arguments.contains("--preview-short-lyrics") ? "Can you see it" : "Pull Me Through The Night",
                    artist: "Matisse / Sadko, James French",
                    palette: [Color(red: 0.18, green: 0.30, blue: 0.36), Color(red: 0.05, green: 0.10, blue: 0.13)],
                    lyrics: arguments.contains("--preview-no-lyrics") ? [] : previewLyrics,
                    hasArtwork: previewArtwork != nil,
                    artworkData: previewArtwork,
                    artworkURL: nil,
                    sourceBundleIdentifier: "preview.topislet",
                    lyricsAreDesktopSnapshot: false
                ),
                isPlaying: !arguments.contains("--preview-paused"),
                progress: 0.42,
                lyricIndex: 0,
                elapsedTime: 96,
                duration: 228,
                canSeek: true,
                canPlayPause: true,
                canPreviousTrack: true,
                canNextTrack: true,
                hasCurrentTrack: true,
                playbackStateKnown: !arguments.contains("--preview-unknown-playback")
            )
            activeFeature = .music
        }
        if let previewModeIndex = arguments.firstIndex(of: "--preview-mode"),
           arguments.indices.contains(previewModeIndex + 1),
           let previewMode = IslandMode(rawValue: arguments[previewModeIndex + 1]) {
            mode = previewMode
        }
        if let previewFeatureIndex = arguments.firstIndex(of: "--preview-feature"),
           arguments.indices.contains(previewFeatureIndex + 1),
           let previewFeature = IslandFeature(rawValue: arguments[previewFeatureIndex + 1]) {
            activeFeature = previewFeature
        }
        layoutCancellable = layout.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        appSettingsCancellable = appSettings.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        if !isPreviewPresentation { applyMusicExpansionPreference() }
        startTicker()
        guard !isPreviewPresentation else { return }

        refreshMusicIntegrationStatus()
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

        musicLyricsSettingsCancellable = appSettings.$showMusicLyrics
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                self.musicAdapter.setQishuiTimedLyricsEnabled(enabled)
                // Content preference never owns expansion/collapse.
            }
        musicExpansionSettingsCancellable = appSettings.$musicExpansionMode
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyMusicExpansionPreference() }
    }

    private func applyMusicExpansionPreference() {
        guard MusicInteractionPolicy.shouldOpenOnPreferenceChange(
            feature: activeFeature, hasTrack: music.hasCurrentTrack,
            expansion: appSettings.musicExpansionMode
        ) else { return }
        requestIslandMode(.expanded, bypassCooldown: true)
    }

    func toggleMusicLyrics() {
        notePresentationInteraction()
        appSettings.showMusicLyrics.toggle()
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

    func handleCollapsedIslandTap() {
        let destination = CollapsedIslandTapPolicy.destination(
            activeFeature: activeFeature,
            hasCurrentMusicTrack: music.hasCurrentTrack,
            musicControlsAvailable: musicControlsAvailable,
            hasPendingNotification: hasPendingNotification,
            musicExpansionMode: appSettings.musicExpansionMode
        )
        showFeature(destination.feature, mode: destination.mode)
    }

    func collapseExpandedPresentation() {
        requestIslandMode(
            activeFeature == .activityCenter ? .collapsed : .compact,
            bypassCooldown: true
        )
    }

    func requestIslandMode(
        _ targetMode: IslandMode,
        bypassCooldown: Bool = false,
        userInitiated: Bool = true
    ) {
        if userInitiated { notePresentationInteraction() }
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
        notePresentationInteraction()
        lastDirectControlAt = Date()
    }

    func notePresentationInteraction() {
        if activeFeature == .music, mode == .expanded {
            isUserExpandedMusicPresentation = true
            autoCompactOnNextMusicTrack = false
        }
        presentationInteraction.send()
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
        guard music.canPlayPause else {
            requestCurrentMusicControlPermissionIfNeeded()
            return
        }
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
            if !outcome.didSendCommand, music.controlRecoveryAction != nil {
                musicControlRecoveryNeedsUserAction = true
            }
            if outcome.didSendCommand {
                applyMusicUpdate(musicAdapter.currentState(), status: outcome.status, forceMusic: true)
                startMusicControlRefreshBurst(previousSignature: previousSignature, requireTrackChange: false)
            } else if outcome.shouldAdvancePreview {
                applyMusicUpdate(musicAdapter.playPause(music), status: outcome.status, forceMusic: true)
            }
        }
    }

    func recoverCurrentMusicControl() {
        guard music.controlRecoveryAction == .reopenQishuiWindow,
              MusicControlRecoveryPolicy.shouldOpenApplication(for: .userInitiated) else { return }
        latestMusicControlRecoverySummary = "用户触发连接：\(music.controlUnavailableReason ?? "原因未知")"
        reopenQishuiWindow()
    }

    func nextTrack() {
        guard music.canNextTrack else {
            requestCurrentMusicControlPermissionIfNeeded()
            return
        }
        noteDirectControlInteraction()
        cancelPendingMusicSeek(reason: .superseded)
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
            if !outcome.didSendCommand, music.controlRecoveryAction != nil {
                musicControlRecoveryNeedsUserAction = true
            }
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
        guard music.canPreviousTrack else {
            requestCurrentMusicControlPermissionIfNeeded()
            return
        }
        noteDirectControlInteraction()
        cancelPendingMusicSeek(reason: .superseded)
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
            if !outcome.didSendCommand, music.controlRecoveryAction != nil {
                musicControlRecoveryNeedsUserAction = true
            }
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
        refreshNeteaseMusicStatus()
        refreshAppleMusicStatus()
    }

    func refreshAccessibilityDisplayOptions() {
        reduceMotionEnabled = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func refreshNeteaseMusicStatus() {
        let runningApplication = NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicAdapterRegistry.neteaseMusic.descriptor.bundleIdentifier
        ).first
        let processIdentifier = runningApplication?.processIdentifier
        if processIdentifier != neteaseMusicObservedProcessIdentifier {
            neteaseMusicObservedProcessIdentifier = processIdentifier
            resetNeteaseMusicConnection(
                status: processIdentifier == nil ? "未运行" : "等待同步"
            )
        }
        neteaseMusicIsRunning = runningApplication != nil
        if !neteaseMusicIsRunning {
            resetNeteaseMusicConnection(status: "未运行")
        }
    }

    func refreshNeteaseMusicSnapshot() async {
        refreshNeteaseMusicStatus()
        guard neteaseMusicIsRunning else { return }
        neteaseMusicSettingsRequestGeneration &+= 1
        let generation = neteaseMusicSettingsRequestGeneration
        let expectedProcessIdentifier = neteaseMusicObservedProcessIdentifier
        guard let snapshot = await musicAdapter.neteaseMusicSnapshotForSettings() else {
            guard generation == neteaseMusicSettingsRequestGeneration else { return }
            neteaseMusicConnectionStatus = "连接超时"
            return
        }
        let currentProcessIdentifier = NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicAdapterRegistry.neteaseMusic.descriptor.bundleIdentifier
        ).first?.processIdentifier
        guard generation == neteaseMusicSettingsRequestGeneration,
              currentProcessIdentifier == expectedProcessIdentifier,
              snapshot.instance?.processIdentifier == expectedProcessIdentifier else {
            refreshNeteaseMusicStatus()
            return
        }
        neteaseMusicSnapshotAvailability = snapshot.availability
        switch snapshot.availability {
        case .ready:
            neteaseMusicConnectionStatus = "连接正常"
        case .notRunning:
            neteaseMusicConnectionStatus = "未运行"
        case let .degraded(reason):
            neteaseMusicConnectionStatus = "读取失败：\(reason)"
        case let .permissionRequired(permission):
            neteaseMusicConnectionStatus = "需要权限：\(permission)"
        case let .unavailable(reason):
            neteaseMusicConnectionStatus = "不可用：\(reason)"
        }
        neteaseMusicAvailableControls = [
            snapshot.controls.supports(.playPause) ? "播放暂停" : nil,
            snapshot.controls.supports(.previousTrack) ? "上一首" : nil,
            snapshot.controls.supports(.nextTrack) ? "下一首" : nil
        ]
        .compactMap { $0 }
        .joined(separator: "、")
        if neteaseMusicAvailableControls.isEmpty {
            neteaseMusicAvailableControls = accessibilityTrusted ? "无" : "等待辅助功能授权"
        }
    }

    private func resetNeteaseMusicConnection(status: String) {
        neteaseMusicSettingsRequestGeneration &+= 1
        neteaseMusicSnapshotAvailability = nil
        neteaseMusicConnectionStatus = status
        neteaseMusicAvailableControls = "无"
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

    private func requestCurrentMusicControlPermissionIfNeeded() {
        guard canRecoverCurrentMusicControlPermission else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        if !accessibilityTrusted {
            openAccessibilitySettings()
        }
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
        let requestedAt = Date()
        let result = await musicAdapter.seek(
            to: progress,
            interaction: interaction,
            displayedSourceBundleIdentifier: displayedSourceBundleIdentifier
        )
        let didSeek = result.status.availability == .qishuiControlSent
            || result.status.availability == .appleMusicControlSent
        guard requestID == musicSeekRequestID else {
            if didSeek {
                let currentSourceBundleIdentifier = music.track.sourceBundleIdentifier
                let reason: MusicSeekCancellationReason
                if currentSourceBundleIdentifier == displayedSourceBundleIdentifier {
                    reason = .superseded
                } else if currentSourceBundleIdentifier == nil {
                    reason = .sourceExited
                } else {
                    reason = .sourceChanged
                }
                musicAdapter.noteSeekCancelled(
                    sourceBundleIdentifier: displayedSourceBundleIdentifier,
                    requestedAt: requestedAt,
                    targetProgress: progress,
                    reason: reason
                )
            }
            return true
        }
        guard music.track.sourceBundleIdentifier
            == displayedSourceBundleIdentifier else {
            if didSeek {
                musicAdapter.noteSeekCancelled(
                    sourceBundleIdentifier: displayedSourceBundleIdentifier,
                    requestedAt: requestedAt,
                    targetProgress: progress,
                    reason: music.track.sourceBundleIdentifier == nil
                        ? .sourceExited
                        : .sourceChanged
                )
            }
            return true
        }
        cancelPendingMusicSeek(reason: .superseded)
        applyMusicUpdate(result.music, status: result.status, forceMusic: true)
        if didSeek {
            pendingMusicSeek = PendingMusicSeek(
                trackSignature: musicSignature(result.music),
                sourceBundleIdentifier: displayedSourceBundleIdentifier,
                targetProgress: min(max(progress, 0), 1),
                requestedAt: requestedAt,
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
        musicControlRecoveryTask?.cancel()
        musicControlRecoveryTask = nil
        isRecoveringMusicControl = false
        musicControlRecoveryAwaitingVerification = false
        cancelPendingMusicSeek(reason: .stateReset)
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

    func startTimer(minutes: Int) {
        noteDirectControlInteraction()
        if activeFeature == .notification {
            clearNotificationPresentation()
        }
        let preset = FocusTimerPreset(rawValue: minutes) ?? .twentyFiveMinutes
        timerState = TimerState(
            duration: preset.durationSeconds,
            remaining: preset.durationSeconds,
            isRunning: true
        )
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
        // Lyric AX snapshots are admitted every 180ms. Publishing on the same
        // cadence avoids making a fresh active line wait for a second 500ms
        // tick; the adapter's source and playback refreshes retain their own
        // longer throttles.
        ticker = Timer.scheduledTimer(
            withTimeInterval: MusicPresentationTimingPolicy.mediaPublicationInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func tick() {
        if !isPreviewPresentation {
            let trusted = AXIsProcessTrusted()
            if trusted != accessibilityTrusted {
                accessibilityTrusted = trusted
            }
            let mediaUpdate = musicAdapter.tick(music)
            if isMusicScrubbing {
                if let status = mediaUpdate.sourceStatus,
                   shouldPublishMusicStatus(status) {
                    musicSourceStatus = status
                }
            } else {
                applyMusicUpdate(mediaUpdate.music, status: mediaUpdate.sourceStatus)
            }
            updateMusicControlRecovery()
            presentNextEventIfPossible()
        }

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

    private func updateMusicControlRecovery() {
        // A missing UI action is not proof that Qishui's controls recovered.
        switch MusicControlRecoveryPolicy.refreshDisposition(
            isRecovering: isRecoveringMusicControl,
            awaitingVerification: musicControlRecoveryAwaitingVerification,
            qishuiAvailability: musicAdapter.qishuiControlAvailability,
            hasRecoveryAction: music.controlRecoveryAction != nil
        ) {
        case .keepWaiting, .unchanged:
            return
        case .verified:
            latestMusicControlRecoverySummary = "控件已恢复"
        case .clearInactiveFeedback:
            break
        }
        isRecoveringMusicControl = false
        musicControlRecoveryAwaitingVerification = false
        musicControlRecoveryNeedsUserAction = false
        musicControlRecoveryTask?.cancel()
        musicControlRecoveryTask = nil
    }

    private func reopenQishuiWindow() {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: QishuiProcessLocator.bundleIdentifier
        ) else {
            musicControlRecoveryNeedsUserAction = true
            return
        }

        musicControlRecoveryTask?.cancel()
        isRecoveringMusicControl = true
        musicControlRecoveryAwaitingVerification = false
        musicControlRecoveryNeedsUserAction = false
        musicAdapter.resetQishuiControlVerificationForRecovery()
        let runningApplication = QishuiProcessLocator.application()

        // Qishui is Electron.  A normal Dock/open request cannot turn on its
        // renderer accessibility tree for an already-running process, so the
        // user-initiated recovery action performs a scoped relaunch with the
        // supported Chromium accessibility switch.  This is deliberately not
        // part of background polling: playback is interrupted only when the
        // user explicitly asks to connect the three top controls.
        musicControlRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let didLaunch = await QishuiWindowRecovery
                .relaunchWithRendererAccessibility(
                    applicationURL: applicationURL,
                    runningApplication: runningApplication
                )
            guard !Task.isCancelled else { return }
            guard didLaunch else {
                self.isRecoveringMusicControl = false
                self.musicControlRecoveryNeedsUserAction = true
                self.latestMusicControlRecoverySummary = "汽水未能以可控模式重新启动，请手动打开汽水后再试"
                return
            }
            self.musicAdapter.resetQishuiControlVerificationForRecovery()
            self.musicControlRecoveryAwaitingVerification = true
            _ = QishuiWindowRecovery.revealMainWindow(
                for: QishuiProcessLocator.application()
            )
            self.scheduleQishuiControlAvailabilityRefreshAfterRecovery()
        }
    }

    private func scheduleQishuiControlAvailabilityRefreshAfterRecovery() {
        musicControlRecoveryTask = Task { @MainActor [weak self] in
            // AX content can appear after the app has finished activating.  A
            // single delayed probe was too early for Qishui, so keep the
            // recovery window short but tolerant of several activation passes.
            let checkpoints: [UInt64] = [
                350_000_000,
                400_000_000,
                500_000_000,
                650_000_000,
                900_000_000,
                1_200_000_000
            ]
            for delay in checkpoints {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled, let self,
                      self.isRecoveringMusicControl else {
                    return
                }

                _ = QishuiWindowRecovery.revealMainWindow(
                    for: QishuiProcessLocator.application()
                )
                self.musicAdapter.invalidateQishuiCache()
                await self.musicAdapter.verifyQishuiControlsAfterRecovery()
                guard !Task.isCancelled, self.isRecoveringMusicControl else { return }
                let update = self.musicAdapter.refreshPlaybackPositionNow()
                self.applyMusicUpdate(update.music, status: update.status, forceMusic: true)
                self.updateMusicControlRecovery()

                if !self.isRecoveringMusicControl { return }
            }

            guard !Task.isCancelled, let self,
                  self.isRecoveringMusicControl else { return }
            self.isRecoveringMusicControl = false
            self.musicControlRecoveryAwaitingVerification = false
            self.musicControlRecoveryNeedsUserAction = true
            self.latestMusicControlRecoverySummary = "汽水仍未提供可用控件，请确认汽水窗口已打开后再试"
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

        guard IslandActivityArbitrationPolicy.shouldPresentNotification(
            isUrgent: nextEvent.priority == .urgent,
            currentMode: mode,
            isInteractionBlocked: blocksInteractiveEventPresentation,
            explicitlyRequested: force
        ) else {
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

        let resolvedFeature = IslandActivityArbitrationPolicy.featureAfterNotification(
            returnFeature: returnFeature,
            returnMode: returnMode,
            timerIsRunning: timerState.isRunning,
            hasCurrentMusicTrack: music.hasCurrentTrack
        )
        activeFeature = resolvedFeature
        if latestMode == presentedMode {
            if resolvedFeature == .music, returnFeature != .music {
                mode = .compact
            } else if let returnMode {
                mode = returnMode
            }
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
        } else if MusicUpdatePolicy.didChangeSource(current: music, candidate: newMusic) {
            resetPendingMusicControlPresentation(
                seekCancellationReason: newMusic.track.sourceBundleIdentifier == nil
                    ? .sourceExited
                    : .sourceChanged
            )
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
        let shouldTakeOverWithMusic = IslandActivityArbitrationPolicy.shouldMusicTakeOver(
            activeFeature: activeFeature,
            currentMode: mode,
            becameAvailable: becameAvailable,
            timerIsRunning: timerState.isRunning,
            hasPendingNotification: hasPendingNotification,
            isInteractionBlocked: blocksInteractiveEventPresentation
        )
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
            let timelinePreservingUpdate = MusicUpdatePolicy.preservingTimeline(
                current: music, candidate: reconciledMusic
            )
            if timelinePreservingUpdate != music {
                musicTimelineSampledAt = Date()
                music = timelinePreservingUpdate
                musicAdapter.noteMusicUIPublished(timelinePreservingUpdate)
            }
            if let newStatus,
               shouldPublishMusicStatus(newStatus) {
                musicSourceStatus = newStatus
            }
            return
        }

        if forceMusic || shouldPublishMusicUpdate(reconciledMusic) {
            // A lyric snapshot can arrive on its own after MediaRemote has
            // already published the track. Promote that snapshot to the same
            // music presentation transaction so the width listener cannot see
            // the old 377pt layout with new lyric text.
            musicTimelineSampledAt = Date()
            music = reconciledMusic
            musicAdapter.noteMusicUIPublished(reconciledMusic)
            if !reconciledMusic.hasCurrentTrack {
                AlbumArtworkImageCache.shared.removeAll()
            }
            if becameAvailable {
                autoCompactOnNextMusicTrack = false
            }
            if shouldTakeOverWithMusic {
                activeFeature = .music
                isUserExpandedMusicPresentation = false
                mode = MusicInteractionPolicy.arrivalMode(
                    currentMode: mode, expansion: appSettings.musicExpansionMode
                )
                isUserExpandedMusicPresentation = mode == .expanded
            } else if shouldPromoteToCompact {
                isUserExpandedMusicPresentation = false
                mode = .compact
            }
            refreshMusicAccent(
                for: reconciledMusic.track,
                hasCurrentTrack: reconciledMusic.hasCurrentTrack
            )
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
        resetPendingMusicControlPresentation(seekCancellationReason: .sourceExited)
        if activeFeature == .music,
           !hasPendingNotification {
            let shouldCollapse = MusicPresentationTransitionPolicy
                .shouldResetToDefaultAfterAllSourcesExit(currentMode: mode)
            autoCompactOnNextMusicTrack = true
            isUserExpandedMusicPresentation = false
            activeFeature = .activityCenter
            if shouldCollapse {
                mode = .collapsed
            }
        }
    }

    private func resetPendingMusicControlPresentation(
        seekCancellationReason: MusicSeekCancellationReason
    ) {
        musicRefreshBurstTask?.cancel()
        musicRefreshBurstTask = nil
        trackControlFeedbackTask?.cancel()
        trackControlFeedbackTask = nil
        pendingTrackControl = nil
        pendingTrackControlBaselineSignature = nil
        pendingTrackControlGeneration = nil
        pendingTrackControlChainCount = 0
        cancelPendingMusicSeek(reason: seekCancellationReason)
        musicSeekRequestID += 1
        isMusicScrubbing = false
    }

    private func cancelPendingMusicSeek(reason: MusicSeekCancellationReason) {
        guard let pendingSeek = pendingMusicSeek else { return }
        musicAdapter.noteSeekCancelled(
            sourceBundleIdentifier: pendingSeek.sourceBundleIdentifier,
            requestedAt: pendingSeek.requestedAt,
            targetProgress: pendingSeek.targetProgress,
            reason: reason
        )
        pendingMusicSeek = nil
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

    private func refreshMusicAccent(
        for track: MusicTrack,
        hasCurrentTrack: Bool
    ) {
        let identity = "\(hasCurrentTrack ? "active" : "inactive")\u{1f}"
            + artworkAccentIdentity(for: track)
        guard identity != musicAccentIdentity else { return }
        musicAccentIdentity = identity
        musicAccentGeneration += 1
        let generation = musicAccentGeneration
        musicAccentTask?.cancel()

        let inlineData = track.artworkData
        let artworkURL = track.artworkURL
        guard inlineData != nil || artworkURL != nil else {
            guard ArtworkAccentTransitionPolicy.shouldDelayNeutralFallback(
                hasCurrentTrack: hasCurrentTrack
            ) else {
                withAnimation(.easeInOut(duration: 0.20)) {
                    musicAccentColor = .white
                }
                musicAccentTask = nil
                return
            }
            let fallbackColor = Color(white: 0.74)
            let graceNanoseconds = ArtworkAccentTransitionPolicy
                .missingArtworkGraceNanoseconds
            musicAccentTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: graceNanoseconds)
                guard !Task.isCancelled,
                      let self,
                      generation == musicAccentGeneration,
                      identity == musicAccentIdentity else { return }
                withAnimation(.easeInOut(duration: 0.24)) {
                    musicAccentColor = fallbackColor
                }
                musicAccentTask = nil
            }
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
                  identity == musicAccentIdentity else { return }
            guard let components else {
                withAnimation(.easeInOut(duration: 0.24)) {
                    musicAccentColor = Color(white: 0.74)
                }
                musicAccentTask = nil
                return
            }
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
        let now = Date()
        guard now < pendingSeek.expiresAt else {
            musicAdapter.noteSeekConfirmationTimeout(
                sourceBundleIdentifier: pendingSeek.sourceBundleIdentifier,
                requestedAt: pendingSeek.requestedAt,
                targetProgress: pendingSeek.targetProgress
            )
            pendingMusicSeek = nil
            return newMusic
        }
        guard musicSignature(newMusic) == pendingSeek.trackSignature else {
            cancelPendingMusicSeek(reason: .trackChanged)
            return newMusic
        }

        let duration = newMusic.duration ?? music.duration
        let elapsedSinceSeek = pendingSeek.isPlaying ? Date().timeIntervalSince(pendingSeek.issuedAt) : 0
        let expectedProgress = duration.map {
            min(max(pendingSeek.targetProgress + elapsedSinceSeek / max($0, 1), 0), 1)
        } ?? pendingSeek.targetProgress
        let tolerance = duration.map { max(0.75 / max($0, 1), 0.002) } ?? 0.01
        if abs(newMusic.progress - expectedProgress) <= tolerance {
            if let matchingSince = pendingSeek.matchingSince,
               now.timeIntervalSince(matchingSince) >= 0.35 {
                musicAdapter.noteSeekConfirmed(
                    sourceBundleIdentifier: pendingSeek.sourceBundleIdentifier,
                    requestedAt: pendingSeek.requestedAt,
                    targetProgress: pendingSeek.targetProgress,
                    observedProgress: newMusic.progress
                )
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
            || MusicUpdatePolicy.playbackPresentationChanged(current: music, candidate: newMusic)
            || newMusic.lyricIndex != music.lyricIndex
            || newMusic.duration != music.duration
            || newMusic.canSeek != music.canSeek
            || newMusic.isPlaybackPending != music.isPlaybackPending
            || newMusic.canPlayPause != music.canPlayPause
            || newMusic.canPreviousTrack != music.canPreviousTrack
            || newMusic.canNextTrack != music.canNextTrack
            || newMusic.controlUnavailableReason != music.controlUnavailableReason
            || newMusic.controlRecoveryAction != music.controlRecoveryAction
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
            || lhs.timedWords != rhs.timedWords
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
