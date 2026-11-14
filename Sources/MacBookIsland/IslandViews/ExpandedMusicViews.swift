import AppKit
import SwiftUI

// Expanded music panel, frontend redesign D2
// (Docs/design/FRONTEND_REDESIGN_2026-11.md section 4.3). Three rows inside a
// fixed 560pt surface:
//   1. artwork · title / artist / source · transport · more menu
//   2. lyric row (only when the user's "显示歌词" setting is on)
//   3. elapsed · progress · remaining
// The size depends only on the lyric setting, never on whether the current
// song has lyrics, so late or missing lyrics no longer resize the panel.

struct ExpandedMusic: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MusicInfoRow(model: model)
                .frame(height: ExpandedMusicLayout.infoRowHeight)
                .padding(.top, ExpandedMusicLayout.topInset)

            if model.isMusicLyricsEnabled {
                MusicLyricRow(model: model)
                    .frame(height: ExpandedMusicLayout.lyricRowHeight, alignment: .topLeading)
                    .padding(.top, ExpandedMusicLayout.infoToLyricSpacing)
            }

            MusicProgressRow(model: model)
                .frame(height: ExpandedMusicLayout.progressRowHeight)
                .padding(.top, ExpandedMusicLayout.toProgressSpacing)

            Spacer(minLength: 0)
        }
        .frame(width: ExpandedMusicLayout.contentWidth, alignment: .topLeading)
    }
}

/// Soft color from the artwork behind the cover, the only colored area on
/// the black surface. Hidden when Increase Contrast is on.
struct MusicAmbientGlow: View {
    let accent: Color
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if contrast != .increased {
            RadialGradient(
                colors: [accent.opacity(IslandTheme.Surface.musicGlowOpacity), .clear],
                center: UnitPoint(x: 0.08, y: 0.36),
                startRadius: 0,
                endRadius: IslandTheme.Surface.musicGlowRadius
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct MusicInfoRow: View {
    @ObservedObject var model: IslandModel
    @StateObject private var titleClock = MarqueeClock()

    private var sourceLine: String {
        let name = MusicSourceDisplayName.name(for: model.music.track.sourceBundleIdentifier)
        let controlsUnavailable = !model.music.canPlayPause
            && !model.canRecoverCurrentMusicControlPermission
        if controlsUnavailable, let reason = model.music.controlUnavailableReason, !reason.isEmpty {
            return name.isEmpty ? reason : "\(name) · \(reason)"
        }
        return name
    }

    var body: some View {
        HStack(alignment: .center, spacing: ExpandedMusicLayout.artworkToDetailsSpacing) {
            AlbumArt(track: model.music.track, size: ExpandedMusicLayout.artworkSize)

            VStack(alignment: .leading, spacing: 1) {
                MarqueeText(
                    text: model.music.track.title,
                    font: IslandTheme.Typeface.musicTitle,
                    color: .white.opacity(IslandTheme.Ink.musicTitle),
                    lineHeight: 20,
                    clock: titleClock
                )
                .frame(height: 20)
                Text(model.music.track.artist)
                    .font(IslandTheme.Typeface.musicArtist)
                    .foregroundStyle(.white.opacity(IslandTheme.Ink.musicArtist))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !sourceLine.isEmpty {
                    Text(sourceLine)
                        .font(IslandTheme.Typeface.musicSource)
                        .foregroundStyle(.white.opacity(IslandTheme.Ink.musicSource))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .onChange(of: model.music.track.title) { _, _ in
                titleClock.restart()
            }

            MusicTransportControls(model: model)
                .frame(width: ExpandedMusicLayout.transportWidth, alignment: .trailing)

            MusicMoreMenu(model: model)
        }
    }
}

private struct MusicTransportControls: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        if model.shouldPresentMusicControlRecovery {
            Button {
                model.recoverCurrentMusicControl()
            } label: {
                HStack(spacing: 6) {
                    if model.isRecoveringMusicControl {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.black)
                    }
                    Text(model.isRecoveringMusicControl ? "连接中" : "重启并连接")
                        .font(IslandTheme.Typeface.recoveryLabel)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
            .disabled(model.isRecoveringMusicControl)
            .help("重启并连接汽水音乐播放控制")
            .accessibilityIdentifier("topislet.music.recover")
        } else {
            HStack(spacing: ExpandedMusicLayout.transportSpacing) {
                ControlButton(icon: "backward.fill", size: ExpandedMusicLayout.skipButtonSize) {
                    model.previousTrack()
                }
                .disabled(!model.music.canPreviousTrack && !model.canRecoverCurrentMusicControlPermission)
                .help("上一首")
                .accessibilityLabel("上一首")
                .accessibilityIdentifier("topislet.music.previous")

                ControlButton(
                    icon: model.music.playbackStateKnown && model.music.isPlaying
                        ? "pause.fill" : "play.fill",
                    prominent: true,
                    size: ExpandedMusicLayout.playButtonSize
                ) {
                    model.playPause()
                }
                .disabled(!model.music.canPlayPause && !model.canRecoverCurrentMusicControlPermission)
                .help(model.music.playbackStateKnown
                    ? (model.music.isPlaying ? "暂停" : "播放")
                    : "播放 / 暂停")
                .accessibilityLabel(model.music.playbackStateKnown
                    ? (model.music.isPlaying ? "暂停" : "播放") : "切换播放")
                .accessibilityIdentifier("topislet.music.playPause")

                ControlButton(icon: "forward.fill", size: ExpandedMusicLayout.skipButtonSize) {
                    model.nextTrack()
                }
                .disabled(!model.music.canNextTrack && !model.canRecoverCurrentMusicControlPermission)
                .help("下一首")
                .accessibilityLabel("下一首")
                .accessibilityIdentifier("topislet.music.next")
            }
        }
    }
}

/// Replaces the four corner buttons (lyrics, expansion mode, collapse,
/// minimize) with one menu. Clicking outside still collapses the island
/// except in the pinned mode, where "收起" in this menu does it.
private struct MusicMoreMenu: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        Menu {
            Toggle("显示歌词", isOn: Binding(
                get: { model.isMusicLyricsEnabled },
                set: { enabled in
                    if enabled != model.isMusicLyricsEnabled { model.toggleMusicLyrics() }
                }
            ))
            Picker("展开方式", selection: Binding(
                get: { model.appSettings.musicExpansionMode },
                set: { model.notePresentationInteraction(); model.appSettings.musicExpansionMode = $0 }
            )) {
                ForEach(MusicExpansionMode.allCases) { expansion in
                    Text(expansion.title).tag(expansion)
                }
            }
            Divider()
            Button("收起") { model.collapseExpandedPresentation() }
            Button("最小化") { model.requestIslandMode(.collapsed, bypassCooldown: true) }
        } label: {
            Image(systemName: model.appSettings.musicExpansionMode == .pinned ? "pin.fill" : "ellipsis")
                .font(IslandTheme.Typeface.windowButton)
                .foregroundStyle(.white.opacity(IslandTheme.Ink.windowButton))
                .frame(width: ExpandedMusicLayout.moreButtonSize, height: ExpandedMusicLayout.moreButtonSize)
                .background(Circle().fill(Color.white.opacity(IslandTheme.Fill.quietButton)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("更多")
        .accessibilityLabel("更多音乐选项")
        .accessibilityIdentifier("topislet.music.more.menu")
        .simultaneousGesture(TapGesture().onEnded { model.notePresentationInteraction() })
    }
}

private struct MusicLyricRow: View {
    @ObservedObject var model: IslandModel
    @StateObject private var lyricClock = MarqueeClock()

    private var lyricPairs: (current: LyricPair, next: LyricPair) {
        MusicLyricPresentation.sourceCurrentAndNextPairs(
            lines: model.music.track.lyrics,
            index: model.music.lyricIndex,
            pairMixedLanguageLines: !model.music.track.lyricsAreDesktopSnapshot
        )
    }

    private var hasLyrics: Bool {
        MusicLyricPresentation.hasDisplayableLines(model.music.track.lyrics)
    }

    var body: some View {
        let pairs = lyricPairs
        // The second line shows the translation when there is one, otherwise
        // the next line; the row height never changes.
        let secondLine = !pairs.current.translation.isEmpty
            ? (text: pairs.current.translation, opacity: IslandTheme.Ink.lyricTranslation)
            : (pairs.next.primary != pairs.current.primary
                ? (text: pairs.next.primary, opacity: IslandTheme.Ink.lyricNext)
                : (text: "", opacity: IslandTheme.Ink.lyricNext))

        HStack(alignment: .top, spacing: ExpandedMusicLayout.lyricBarSpacing) {
            Capsule()
                .fill(model.musicAccentColor.opacity(hasLyrics ? IslandTheme.Accent.lyricBar : 0.4))
                .frame(width: 3, height: 22)
                .padding(.top, 2)

            if hasLyrics {
                VStack(alignment: .leading, spacing: 0) {
                    currentLine(pairs.current.primary)
                        .frame(height: ExpandedMusicLayout.lyricLineHeight)
                    if !secondLine.text.isEmpty {
                        MarqueeText(
                            text: secondLine.text,
                            font: IslandTheme.Typeface.lyricNext,
                            color: .white.opacity(secondLine.opacity),
                            lineHeight: 18,
                            clock: lyricClock
                        )
                        .frame(height: 18)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText(pairs))
            } else {
                Text(MusicLyricPresentation.emptyStateText(
                    lines: model.music.track.lyrics,
                    lyricsEnabled: model.isMusicLyricsEnabled
                ))
                .font(IslandTheme.Typeface.musicStatus)
                .foregroundStyle(.white.opacity(IslandTheme.Ink.musicStatus))
                .frame(height: ExpandedMusicLayout.lyricLineHeight)
            }
        }
        .frame(width: ExpandedMusicLayout.contentWidth, alignment: .topLeading)
        .clipped()
        // One reading surface stays mounted; rapid AX and seek updates must
        // not composite old and new sentences in the same viewport.
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .onChange(of: pairs.current) { _, _ in
            lyricClock.restart()
        }
    }

    @ViewBuilder
    private func currentLine(_ text: String) -> some View {
        if let elapsedTime = model.music.elapsedTime, !model.music.track.timedWords.isEmpty {
            KaraokeLyricText(
                text: text,
                font: IslandTheme.Typeface.lyricCurrent,
                highlightedColor: .white.opacity(IslandTheme.Ink.lyricHighlighted),
                unhighlightedColor: .white.opacity(IslandTheme.Ink.lyricUnhighlighted),
                lineHeight: ExpandedMusicLayout.lyricLineHeight,
                clock: lyricClock,
                isPlaying: model.music.isPlaying,
                words: model.music.track.timedWords,
                elapsedTime: elapsedTime,
                sampledAt: model.musicTimelineSampledAt
            )
        } else {
            MarqueeText(
                text: text,
                font: IslandTheme.Typeface.lyricCurrent,
                color: .white.opacity(IslandTheme.Ink.lyricHighlighted),
                lineHeight: ExpandedMusicLayout.lyricLineHeight,
                clock: lyricClock
            )
        }
    }

    private func accessibilityText(_ pairs: (current: LyricPair, next: LyricPair)) -> String {
        let prefix = model.music.track.lyricsAreDesktopSnapshot ? "桌面歌词" : "当前歌词"
        var text = "\(prefix)：\(pairs.current.primary)"
        if !pairs.current.translation.isEmpty { text += "，\(pairs.current.translation)" }
        if !pairs.next.primary.isEmpty { text += "，下一句：\(pairs.next.primary)" }
        return text
    }
}

private struct MusicProgressRow: View {
    @ObservedObject var model: IslandModel
    @State private var scrubPreviewProgress: Double?

    private var canSeek: Bool {
        model.music.canSeek
            || (model.music.track.sourceBundleIdentifier == "com.soda.music"
                && model.music.hasCurrentTrack
                && (model.music.duration ?? 0) > 0)
    }

    var body: some View {
        let times = playbackElapsedAndRemainingText(model.music, progressOverride: scrubPreviewProgress)
        HStack(spacing: ExpandedMusicLayout.timelineToTimeSpacing) {
            Text(times.elapsed)
                .frame(width: ExpandedMusicLayout.timeWidth, alignment: .leading)
            ProgressPill(
                progress: model.music.progress,
                width: ExpandedMusicLayout.timelineWidth,
                accentColor: model.musicAccentColor,
                prominent: false,
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
                onSeek: canSeek ? { progress, interaction in
                    await model.seekMusic(to: progress, interaction: interaction)
                } : nil
            )
            .frame(width: ExpandedMusicLayout.timelineWidth)
            .help(model.music.canSeek ? "拖动调整播放进度" : "当前歌曲暂不支持进度拖动")
            Text(times.remaining)
                .frame(width: ExpandedMusicLayout.timeWidth, alignment: .trailing)
        }
        .font(IslandTheme.Typeface.timeReadout)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .foregroundStyle(.white.opacity(IslandTheme.Ink.timeReadout))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(playbackPositionText(model.music, progressOverride: scrubPreviewProgress))
        .onDisappear {
            model.setMusicScrubbing(false)
        }
    }
}

enum MusicSourceDisplayName {
    static func name(for bundleIdentifier: String?) -> String {
        switch MusicSourceID(bundleIdentifier: bundleIdentifier) {
        case .qishui: return "汽水音乐"
        case .neteaseMusic: return "网易云音乐"
        case .appleMusic: return "Apple Music"
        case nil: return ""
        }
    }
}

/// Elapsed time and the negative remaining time, for the two ends of the
/// progress row. "--:--" on both ends when the duration is unknown.
func playbackElapsedAndRemainingText(
    _ music: MusicState,
    progressOverride: Double? = nil
) -> (elapsed: String, remaining: String) {
    guard let duration = music.duration, duration > 0 else { return ("--:--", "--:--") }
    let elapsed = progressOverride.map { duration * min(max($0, 0), 1) }
        ?? music.elapsedTime
        ?? (duration * min(max(music.progress, 0), 1))
    let clamped = min(max(elapsed, 0), duration)
    return (mediaTimeText(clamped), "-" + mediaTimeText(duration - clamped))
}
