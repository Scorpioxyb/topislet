import AppKit
import ApplicationServices
import Combine
import Darwin
import EventKit
import ImageIO
import QuartzCore
import SwiftUI

struct IslandRootView: View {
    @ObservedObject var model: IslandModel
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                // The body is a separate AppKit-height surface. Keeping an
                // invisible copy mounted while compact/collapsed lets its
                // mask and stale lyric subtree participate in the same frame
                // transaction, which can leave a black band below the header.
                // Mount it only for the mode that owns that surface.
                if model.mode == .expanded {
                    ExpandedIslandBodyPanel(model: model)
                        .offset(y: model.usesUnifiedMusicExpandedSurface || model.isLyricExpandedPresentation
                            ? 0
                            : model.topBandHeight + model.expandedPanelTopGap)
                }

                if !model.isLyricExpandedPresentation && !model.usesUnifiedMusicExpandedSurface {
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
                }

                // Keep exactly one header tree alive for the current mode.
                // Stacking all three trees with opacity lets AppKit resize the
                // window before SwiftUI removes the old compact tree, which
                // leaves a two-line lyric/black-edge residue during collapse.
                Group {
                    switch model.mode {
                    case .collapsed:
                        CollapsedIsland(model: model)
                    case .compact:
                        CompactIsland(model: model)
                    case .expanded:
                        if model.isLyricExpandedPresentation || model.usesUnifiedMusicExpandedSurface {
                            Color.clear
                        } else {
                            ExpandedIsland(model: model)
                        }
                    }
                }
                .frame(width: model.currentHeaderWidth, height: model.topBandHeight)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contextMenu {
            if model.music.hasCurrentTrack {
                Picker("音乐展开方式", selection: Binding(
                    get: { model.appSettings.musicExpansionMode },
                    set: { model.notePresentationInteraction(); model.appSettings.musicExpansionMode = $0 }
                )) {
                    ForEach(MusicExpansionMode.allCases) { expansion in
                        Text(expansion.title).tag(expansion)
                    }
                }
                Toggle("显示歌词", isOn: Binding(
                    get: { model.appSettings.showMusicLyrics },
                    set: { model.notePresentationInteraction(); model.appSettings.showMusicLyrics = $0 }
                ))
                Divider()
            }
            Button("设置…", action: onOpenSettings)
            Divider()
            Button("退出顶屿", action: onQuit)
        }
        .animation(
            IslandMotion.featureContentAnimation(
                reduceMotion: model.reduceMotionEnabled
            ),
            value: model.activeFeature
        )
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
                        .stroke(Color.white.opacity(strokeOpacity), lineWidth: IslandTheme.Surface.strokeWidth)
                }
            )
            .clipShape(shape)
            .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowOpacity > 0 ? IslandTheme.Surface.shadowRadius : 0, x: 0, y: shadowOpacity > 0 ? IslandTheme.Surface.shadowOffsetY : 0)
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
        return UnevenRoundedRectangle(
            bottomLeadingRadius: radius,
            bottomTrailingRadius: radius,
            style: .continuous
        )
        .path(in: rect)
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
                if model.collapsedWingWidth > 0 {
                    HStack(spacing: 0) {
                        Group {
                            if model.activeFeature == .music {
                                AlbumArt(track: model.music.track, size: IslandCollapsedLayout.artworkSize)
                            } else {
                                Image(systemName: model.activeFeature.iconName)
                                    .font(IslandTheme.Typeface.collapsedIcon)
                                    .foregroundStyle(.white.opacity(IslandTheme.Ink.headerIcon))
                            }
                        }
                        .frame(width: model.collapsedWingWidth, height: model.topBandHeight)

                        Color.clear
                            .frame(width: model.notchWidth, height: model.topBandHeight)

                        Group {
                            if model.activeFeature == .music,
                               model.music.playbackStateKnown,
                               !model.music.isPlaying {
                                Image(systemName: "pause.fill")
                                    .font(IslandTheme.Typeface.collapsedPauseGlyph)
                                    .foregroundStyle(.white.opacity(IslandTheme.Ink.collapsedPauseGlyph))
                            } else {
                                StatusDot(
                                    isActive: model.statusWaveIsActive,
                                    accentColor: model.statusWaveColor
                                )
                            }
                        }
                        .frame(width: model.collapsedWingWidth, height: model.topBandHeight)
                    }
                } else {
                    Color.clear
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.handleCollapsedIslandTap()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.activeFeature == .music && model.music.hasCurrentTrack
            ? "\(model.music.track.title)，\(model.music.track.artist)" : "顶屿")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.handleCollapsedIslandTap() }
        .help(model.activeFeature == .music && model.music.hasCurrentTrack
            ? "\(model.music.track.title) · \(model.music.track.artist)" : "打开活动中心")
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
                    case .activityCenter:
                        Color.clear
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
                        .font(IslandTheme.Typeface.expandedHeaderIcon)
                        .foregroundStyle(.white.opacity(IslandTheme.Ink.headerIcon))
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
    /// Expanded music shows its corner buttons only while the pointer is over
    /// the panel, so a resting panel is just artwork, title and lyrics.
    /// `--preview-pointer-over` renders the hover state in snapshots.
    @State private var isPointerOverBody: Bool
    /// Latest hover report, applied once the opening animation has settled.
    @State private var reportedPointerOver: Bool
    @State private var openedAt = Date()

    init(model: IslandModel) {
        self.model = model
        let initial = CommandLine.arguments.contains("--preview-pointer-over")
            || model.pointerWasOverExpandedTarget
        _isPointerOverBody = State(initialValue: initial)
        _reportedPointerOver = State(initialValue: initial)
    }

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
                // Expanded music is one black surface flush with the top of
                // the screen, an extension of the camera housing (redesign
                // direction A). Other features keep their detached body.
                cornerRadius: model.activeFeature == .music
                    ? IslandTheme.Surface.musicBodyCornerRadius
                    : IslandTheme.Surface.bodyCornerRadius,
                fillOpacity: 1,
                strokeOpacity: 0,
                attachesToTop: model.activeFeature == .music
            ) {
                if model.activeFeature == .music {
                    MusicArtworkWash(
                        track: model.music.track,
                        accent: model.musicAccentColor,
                        topBandHeight: model.topBandHeight
                    )
                } else {
                    Color.clear
                }
            }
            .scaleEffect(x: shellScaleX, y: shellScaleY, anchor: .top)
            .opacity(model.mode == .expanded ? 1 : 0)

            ZStack(alignment: .topTrailing) {
                switch model.activeFeature {
                case .activityCenter:
                    ExpandedActivityCenter(model: model)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 12)

                case .music:
                    ExpandedMusic(model: model, isPointerOver: isPointerOverBody)
                        // Camera housing occupies the menu-bar band; the
                        // cover and the reading column start below it.
                        .padding(.top, model.topBandHeight)
                        .frame(maxWidth: .infinity, alignment: .center)

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
                                            .font(IslandTheme.Typeface.chipLabel)
                                    }
                                    .foregroundStyle(.white.opacity(IslandTheme.Ink.pendingChip))
                                    .padding(.horizontal, 8)
                                    .frame(height: 24)
                                    .background(Capsule().fill(Color.white.opacity(IslandTheme.Fill.chip)))
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
                        .padding(.top, 4)
                        .padding(.trailing, 16)
                        .opacity(isPointerOverBody ? 1 : 0)
                        .animation(.easeOut(duration: 0.15), value: isPointerOverBody)
                }
            }
            .frame(width: model.expandedWidth, height: model.expandedBodyHeight)
            .opacity(model.mode == .expanded ? 1 : 0)
            .mask {
                Rectangle()
                    .scaleEffect(x: shellScaleX, y: shellScaleY, anchor: .top)
            }
            .allowsHitTesting(model.mode == .expanded)
        }
        .frame(width: model.expandedWidth, height: model.expandedBodyHeight)
        .onHover { hovering in
            reportedPointerOver = hovering
            // While the window is still growing, tracking areas can report the
            // pointer leaving and re-entering a panel it never left; that made
            // the resting hairline and the control row alternate on open.
            if ExpandedMusicPointerPolicy.appliesHoverChange(
                secondsSinceOpen: Date().timeIntervalSince(openedAt)
            ) {
                isPointerOverBody = hovering
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(ExpandedMusicPointerPolicy.openingGraceSeconds))
            if !Task.isCancelled { isPointerOverBody = reportedPointerOver }
        }
        .onChange(of: model.mode) { _, mode in
            if mode != .expanded { isPointerOverBody = false }
        }
    }
}

struct WindowModeButtons: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 8) {
            if model.activeFeature == .music {
                Button {
                    model.toggleMusicLyrics()
                } label: {
                    Image(systemName: "text.quote")
                        .font(IslandTheme.Typeface.windowButton)
                        .foregroundStyle(.white.opacity(model.isMusicLyricsEnabled ? IslandTheme.Ink.toggleOn : IslandTheme.Ink.toggleOff))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(model.isMusicLyricsEnabled ? IslandTheme.Fill.toggleOn : IslandTheme.Fill.quietButton)))
                }
                .buttonStyle(.plain)
                .help(model.isMusicLyricsEnabled ? "隐藏歌词" : "显示歌词")
                .accessibilityLabel(model.isMusicLyricsEnabled ? "隐藏歌词" : "显示歌词")
                .accessibilityIdentifier("topislet.music.lyrics.toggle")
                .accessibilityValue(model.isMusicLyricsEnabled ? "已开启" : "已关闭")

                Menu {
                    Picker("展开方式", selection: Binding(
                    get: { model.appSettings.musicExpansionMode },
                    set: { model.notePresentationInteraction(); model.appSettings.musicExpansionMode = $0 }
                )) {
                        ForEach(MusicExpansionMode.allCases) { expansion in
                            Text(expansion.title).tag(expansion)
                        }
                    }
                } label: {
                    Image(systemName: model.appSettings.musicExpansionMode == .pinned ? "pin.fill" : "ellipsis")
                        .font(IslandTheme.Typeface.windowButton)
                        .foregroundStyle(.white.opacity(IslandTheme.Ink.windowButton))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(IslandTheme.Fill.quietButton)))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("音乐展开方式")
                .accessibilityLabel("音乐展开方式")
                .accessibilityIdentifier("topislet.music.expansion.menu")
                .simultaneousGesture(TapGesture().onEnded { model.notePresentationInteraction() })
            }
            Button {
                model.collapseExpandedPresentation()
            } label: {
                Image(systemName: "chevron.up")
                    .font(IslandTheme.Typeface.windowButtonBold)
                    .foregroundStyle(.white.opacity(IslandTheme.Ink.windowButton))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(IslandTheme.Fill.quietButton)))
            }
            .buttonStyle(.plain)
            .help("收起")

            Button {
                model.requestIslandMode(.collapsed, bypassCooldown: true)
            } label: {
                Image(systemName: "minus")
                    .font(IslandTheme.Typeface.windowButtonBold)
                    .foregroundStyle(.white.opacity(IslandTheme.Ink.windowButton))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(IslandTheme.Fill.quietButton)))
            }
            .buttonStyle(.plain)
            .help("最小化")
        }
    }
}
