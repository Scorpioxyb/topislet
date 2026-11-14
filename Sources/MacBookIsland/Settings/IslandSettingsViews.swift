import AppKit
import ApplicationServices
import Combine
import Darwin
import EventKit
import ImageIO
import QuartzCore
import SwiftUI

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

            ActivitySettingsPane(model: model, settings: model.appSettings)
                .tabItem {
                    Label("活动", systemImage: "clock")
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

private func musicControlStrategyText(_ bundleIdentifier: String?) -> String {
    switch bundleIdentifier {
    case MusicAdapterRegistry.appleMusic.descriptor.bundleIdentifier:
        return "Apple Event 定向"
    case MusicAdapterRegistry.neteaseMusic.descriptor.bundleIdentifier:
        return "网易云 PID 语义 AX"
    default:
        return "汽水唯一语义 AX"
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var settings: AppSettings
    @ObservedObject private var loginItemSettings: LoginItemSettings
    @State private var isConfirmingLayoutReset = false
    @State private var layoutResetStatus: String?
    @State private var isRefreshingPermissions = false

    init(model: IslandModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        loginItemSettings = model.loginItemSettings
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    "登录时自动启动顶屿",
                    isOn: Binding(
                        get: { loginItemSettings.isRequested },
                        set: { loginItemSettings.setEnabled($0) }
                    )
                )
                .disabled(
                    loginItemSettings.isUpdating
                        || loginItemSettings.status == .unavailable
                )

                LabeledContent(
                    "macOS 登录项",
                    value: loginItemSettings.status.title
                )

                if loginItemSettings.status == .requiresApproval {
                    Text("顶屿已经申请登录时启动，但需要你在 macOS“登录项”中允许。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("打开系统登录项设置") {
                        loginItemSettings.openSystemSettings()
                    }
                } else if loginItemSettings.status == .unavailable {
                    Text("请从“应用程序”文件夹运行已签名的顶屿.app，再设置登录时启动。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage = loginItemSettings.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("启动后显示顶屿", isOn: $settings.showIslandOnLaunch)

                Toggle("点击外部自动收起展开面板", isOn: $settings.autoCollapseExpandedIsland)

                Toggle("当前显示顶屿", isOn: $model.isVisible)
            }

            Section {
                LabeledContent(
                    "音乐控制",
                    value: musicControlStrategyText(
                        model.music.track.sourceBundleIdentifier
                    )
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
                LabeledContent(
                    "辅助功能",
                    value: model.accessibilityTrusted ? "已授权" : "待授权"
                )
                LabeledContent(
                    "Apple Music 自动化",
                    value: model.appleMusicAutomationAccess.displayName
                )
                LabeledContent(
                    "日历",
                    value: model.eventKitStatus.calendarAccess.displayName
                )
                LabeledContent(
                    "提醒事项",
                    value: model.eventKitStatus.remindersAccess.displayName
                )
                LabeledContent(
                    "减少动态效果",
                    value: model.reduceMotionEnabled ? "已开启" : "已关闭"
                )

                HStack {
                    Button("辅助功能设置") {
                        model.openAccessibilitySettings()
                    }

                    Button("自动化设置") {
                        model.openAppleMusicAutomationSettings()
                    }
                }

                HStack {
                    Button("日历权限") {
                        model.openEventKitPrivacySettings(for: .event)
                    }

                    Button("提醒事项权限") {
                        model.openEventKitPrivacySettings(for: .reminder)
                    }

                    Button("重新检查") {
                        isRefreshingPermissions = true
                        model.refreshMusicIntegrationStatus()
                        Task {
                            await model.refreshEventKitNow()
                            isRefreshingPermissions = false
                        }
                    }
                    .disabled(isRefreshingPermissions)
                }

                Divider()

                LabeledContent("布局配置", value: model.layout.currentDisplayName)

                Button("恢复当前屏幕默认布局") {
                    isConfirmingLayoutReset = true
                }

                if let layoutResetStatus {
                    Text(layoutResetStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Text("权限入口只打开 macOS 系统设置；顶屿不会替你更改授权。布局恢复只影响当前屏幕，不会修改音乐适配或登录项。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("维护与权限")
            }

            Section {
                LabeledContent("默认主活动", value: "前台音乐应用优先")

                Text("没有音乐时，点击空岛可打开快捷面板；音乐、运行中的计时器和提醒事件仍按优先级自动接管。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                HStack {
                    Button("折叠") {
                        model.isVisible = true
                        model.collapseExpandedPresentation()
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
        .onAppear {
            loginItemSettings.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            loginItemSettings.refresh()
        }
        .confirmationDialog(
            "恢复当前屏幕的默认布局？",
            isPresented: $isConfirmingLayoutReset,
            titleVisibility: .visible
        ) {
            Button("恢复默认布局") {
                model.layout.resetToDefaults()
                layoutResetStatus = "已恢复 \(model.layout.currentDisplayName) 的默认布局。"
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("当前屏幕的手动位置、尺寸和控件偏移会恢复默认值。")
        }
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

    private var availableControlText: String {
        let controls = [
            model.music.canPlayPause ? "播放暂停" : nil,
            model.music.canPreviousTrack ? "上一首" : nil,
            model.music.canNextTrack ? "下一首" : nil
        ].compactMap { $0 }
        return controls.isEmpty
            ? model.music.controlUnavailableReason ?? "不可用"
            : controls.joined(separator: "、")
    }

    private var controlStrategyText: String {
        musicControlStrategyText(model.music.track.sourceBundleIdentifier)
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
            "canPlayPause=\(model.music.canPlayPause)",
            "canPreviousTrack=\(model.music.canPreviousTrack)",
            "canNextTrack=\(model.music.canNextTrack)",
            "controlUnavailableReason=\(model.music.controlUnavailableReason ?? "nil")",
            "controlRecovery=\(model.latestMusicControlRecoverySummary)",
            "pending=\(model.music.isPlaybackPending)",
            "artworkBytes=\(model.music.track.artworkData?.count ?? 0)",
            "artworkURL=\(model.music.track.artworkURL?.absoluteString ?? "nil")",
            "checkedAt=\(model.musicSourceStatus.checkedAt.ISO8601Format())",
            "detail=\(model.musicSourceStatus.detail)",
            "appleMusicTimeline:",
            model.appleMusicTransitionDiagnostic
        ].joined(separator: "\n")
    }

    var body: some View {
        Form {
            Section("音乐应用") {
                ForEach(MusicAdapterRegistry.registrations) { registration in
                    MusicAdapterSettingsRow(registration: registration, model: model)
                }
            }

            Section("音乐面板") {
                Picker("展开方式", selection: $settings.musicExpansionMode) {
                    ForEach(MusicExpansionMode.allCases) { expansion in
                        Text(expansion.title).tag(expansion)
                    }
                }
                Text(settings.musicExpansionMode.explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("显示歌词", isOn: $settings.showMusicLyrics)
                Text("开启后，歌词查询会发送当前歌名和歌手，不上传账号或播放历史；关闭后清空本次运行的歌词时间轴缓存。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("歌词开关只改变阅读区，不会自动打开或收起面板。切换展开方式也不会改变全屏隐藏规则。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

            Section("网易云音乐 Alpha 支持") {
                LabeledContent(
                    "运行状态",
                    value: model.neteaseMusicIsRunning ? "运行中" : "未运行"
                )
                LabeledContent(
                    "辅助功能",
                    value: model.accessibilityTrusted ? "已授权" : "控制待授权"
                )
                LabeledContent("连接状态", value: model.neteaseMusicConnectionStatus)
                LabeledContent("可用控制", value: model.neteaseMusicAvailableControls)
                HStack {
                    if !model.accessibilityTrusted {
                        Button {
                            model.openAccessibilitySettings()
                        } label: {
                            Label("打开辅助功能设置", systemImage: "gear")
                        }
                    }
                    Button {
                        Task {
                            await model.refreshNeteaseMusicSnapshot()
                        }
                    } label: {
                        Label("刷新连接", systemImage: "arrow.clockwise")
                    }
                    .disabled(!model.neteaseMusicIsRunning)
                }
                if !model.neteaseMusicIsRunning {
                    Text("请先打开网易云音乐；顶屿不会主动启动它。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
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
                LabeledContent("可用控制", value: availableControlText)
                LabeledContent(
                    "控制策略",
                    value: controlStrategyText
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

                    Text(model.latestAppleMusicTransitionDiagnostic)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

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
            if model.neteaseMusicIsRunning {
                await model.refreshNeteaseMusicSnapshot()
            }
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
        if registration.descriptor.bundleIdentifier
            == MusicAdapterRegistry.neteaseMusic.descriptor.bundleIdentifier {
            return MusicAdapterRuntimePresenter.neteaseMusic(
                isRunning: model.neteaseMusicIsRunning,
                accessibilityTrusted: model.accessibilityTrusted,
                snapshotAvailability: model.neteaseMusicSnapshotAvailability
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

private struct ActivitySettingsPane: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var settings: AppSettings
    @State private var selectedTimerPreset = FocusTimerPreset.twentyFiveMinutes
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
                Picker("专注时长", selection: $selectedTimerPreset) {
                    ForEach(FocusTimerPreset.allCases) { preset in
                        Text(preset.compactTitle).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button {
                        model.isVisible = true
                        model.startTimer(minutes: selectedTimerPreset.rawValue)
                    } label: {
                        Label("开始专注", systemImage: "play.fill")
                    }

                    if model.activeFeature == .timer {
                        Button {
                            model.isVisible = true
                            model.showFeature(.timer)
                        } label: {
                            Label("显示计时器", systemImage: "capsule")
                        }
                    }

                    Spacer()

                    if model.timerState.isRunning {
                        Text(timeText(model.timerState.remaining))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("专注计时")
            } footer: {
                Text("计时开始后自动接管顶屿；日程提醒短暂出现后，会返回正在进行的计时。")
            }

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
                Image(nsImage: BrandIdentity.applicationImage())
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
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

            Text("当前版本以适配音乐为优先主活动；空岛可打开快捷面板，启动专注计时并管理日历与提醒事项。发布前仍需要处理签名、公证和系统更新兼容性。")
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
