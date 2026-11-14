import AppKit
import ApplicationServices
import Combine
import Darwin
import EventKit
import ImageIO
import QuartzCore
import SwiftUI

struct ExpandedMusic: View {
    @ObservedObject var model: IslandModel

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

    private var showsLyrics: Bool {
        model.isMusicLyricsEnabled && hasLyrics
    }

    var body: some View {
        // Keep the transport and progress row mounted when late lyrics arrive
        // or become unavailable. Only the reading surface changes identity.
        HStack(spacing: ExpandedMusicLayout.controlToLyricSpacing) {
            LyricMusicLeftRail(model: model)
                .offset(y: -model.topBandHeight / (showsLyrics ? 2 : 4))
            VStack(alignment: .leading, spacing: showsLyrics ? 8 : 12) {
                if showsLyrics {
                    LyricsShelf(
                        current: lyricPairs.current,
                        next: lyricPairs.next,
                        isDesktopSnapshot: model.music.track.lyricsAreDesktopSnapshot,
                        accent: model.musicAccentColor,
                        isPlaying: model.music.isPlaying,
                        timedWords: model.music.track.timedWords,
                        elapsedTime: model.music.elapsedTime,
                        sampledAt: model.musicTimelineSampledAt
                    )
                    .offset(y: 14)
                } else {
                    HStack(spacing: 7) {
                        Image(systemName: "waveform")
                            .font(IslandTheme.Typeface.musicPlaceholderIcon)
                            .foregroundStyle(.white.opacity(IslandTheme.Ink.musicPlaceholderIcon))
                            .accessibilityHidden(true)
                        Text(MusicLyricPresentation.emptyStateText(
                            lines: model.music.track.lyrics,
                            lyricsEnabled: model.isMusicLyricsEnabled
                        ))
                            .font(IslandTheme.Typeface.musicStatus)
                            .foregroundStyle(.white.opacity(IslandTheme.Ink.musicStatus))
                    }
                    .accessibilityElement(children: .combine)
                }
                MusicProgressRow(
                    model: model,
                    timelineWidth: showsLyrics
                        ? ExpandedMusicLayout.lyricTimelineWidth : ExpandedMusicLayout.timelineWidth,
                    prominent: showsLyrics
                )
                .offset(y: showsLyrics ? -6 : 0)
            }
            .frame(width: showsLyrics
                ? ExpandedMusicLayout.lyricColumnWidth : ExpandedMusicLayout.detailsWidth,
                alignment: .leading)
        }
        .frame(width: showsLyrics
            ? ExpandedMusicLayout.contentWidth : ExpandedMusicLayout.controlOnlyContentWidth,
            height: showsLyrics
                ? MusicExpandedLayout.lyricsBodyHeight : MusicExpandedLayout.noLyricsBodyHeight)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.white.opacity(IslandTheme.Fill.musicColumnDivider))
                .frame(width: 1, height: showsLyrics ? 110 : 82)
                .offset(x: ExpandedMusicLayout.controlContentWidth + ExpandedMusicLayout.controlToLyricSpacing / 2)
                .allowsHitTesting(false)
        }
    }
}

/// Artwork-colored glow behind the cover on the black music surface
/// (redesign direction A). Hidden when the user asks for more contrast.
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

private struct MusicTransportControls: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(spacing: 13) {
                if model.shouldPresentMusicControlRecovery {
                    Button {
                        model.recoverCurrentMusicControl()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text(model.isRecoveringMusicControl ? "连接中" : "恢复控制")
                                .font(IslandTheme.Typeface.recoveryLabel)
                        }
                        .foregroundStyle(.white)
                        .frame(width: 104, height: 48)
                        .background(.white.opacity(IslandTheme.Fill.chip), in: RoundedRectangle(cornerRadius: IslandTheme.Radius.recoveryButton))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isRecoveringMusicControl)
                    .help("重启并连接汽水音乐播放控制")
                } else {
                    HStack(spacing: 6) {
                        ControlButton(icon: "backward.fill", size: 29) {
                            model.previousTrack()
                        }
                        .disabled(!model.music.canPreviousTrack && !model.canRecoverCurrentMusicControlPermission)
                        .help("上一首")
                        .accessibilityLabel("上一首")
                        .accessibilityIdentifier("topislet.music.previous")

                        ControlButton(
                            icon: model.music.playbackStateKnown && model.music.isPlaying
                                ? "pause.fill" : "play.fill",
                            prominent: true
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

                        ControlButton(icon: "forward.fill", size: 29) {
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
}

private struct LyricMusicLeftRail: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(alignment: .center, spacing: ExpandedMusicLayout.artworkToDetailsSpacing) {
            AlbumArt(track: model.music.track, size: ExpandedMusicLayout.artworkSize)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.music.track.title)
                        .font(IslandTheme.Typeface.musicTitle)
                        .foregroundStyle(.white.opacity(IslandTheme.Ink.musicTitle))
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Text(model.music.track.artist)
                        .font(IslandTheme.Typeface.musicArtist)
                        .foregroundStyle(.white.opacity(IslandTheme.Ink.musicArtist))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(width: 118, alignment: .leading)

                MusicTransportControls(model: model)
                    .frame(width: 110, alignment: .leading)
            }
            .frame(width: 118, alignment: .leading)
        }
        .frame(width: ExpandedMusicLayout.controlContentWidth, alignment: .leading)
    }
}

private struct LyricsShelf: View {
    let current: LyricPair
    let next: LyricPair
    let isDesktopSnapshot: Bool
    let accent: Color
    let isPlaying: Bool
    let timedWords: [QishuiTimedWord]
    let elapsedTime: TimeInterval?
    let sampledAt: Date
    @StateObject private var lyricClock = MarqueeClock()

    var body: some View {
        // Keep one reading surface mounted. Replacing the entire two-line
        // card with an offset transition composites old and new sentences
        // into the same viewport during rapid AX/seek updates.
        lyricLines
            .frame(width: ExpandedMusicLayout.lyricColumnWidth, height: 100, alignment: .topLeading)
            .clipped()
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isDesktopSnapshot
            ? "桌面歌词：\(current.primary)\(current.translation.isEmpty ? "" : "，\(current.translation)")\(next.primary.isEmpty ? "" : "，下一句：\(next.primary)")"
            : "当前歌词：\(current.primary)\(current.translation.isEmpty ? "" : "，\(current.translation)")\(next.primary.isEmpty ? "" : "，下一句：\(next.primary)")")
        .onChange(of: current) { _, _ in
            lyricClock.restart()
        }
    }

    private var lyricLines: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 9) {
                Capsule()
                    .fill(accent.opacity(IslandTheme.Accent.lyricBar))
                    .frame(width: 3, height: 28)
                if let elapsedTime, !timedWords.isEmpty {
                    KaraokeLyricText(
                        text: current.primary,
                        font: IslandTheme.Typeface.lyricCurrent,
                        highlightedColor: .white.opacity(IslandTheme.Ink.lyricHighlighted),
                        unhighlightedColor: .white.opacity(IslandTheme.Ink.lyricUnhighlighted),
                        lineHeight: 29,
                        clock: lyricClock,
                        isPlaying: isPlaying,
                        words: timedWords,
                        elapsedTime: elapsedTime,
                        sampledAt: sampledAt
                    )
                } else {
                    MarqueeText(
                        text: current.primary,
                        font: IslandTheme.Typeface.lyricCurrent,
                        color: .white.opacity(IslandTheme.Ink.lyricHighlighted),
                        lineHeight: 29,
                        clock: lyricClock
                    )
                }
            }

            if !current.translation.isEmpty {
                MarqueeText(
                    text: current.translation,
                    font: IslandTheme.Typeface.lyricTranslation,
                    color: .white.opacity(IslandTheme.Ink.lyricTranslation),
                    lineHeight: 19,
                    clock: lyricClock
                )
                .padding(.leading, 12)
            }

            if !next.primary.isEmpty && next.primary != current.primary {
                MarqueeText(
                    text: next.primary,
                    font: IslandTheme.Typeface.lyricNext,
                    color: .white.opacity(IslandTheme.Ink.lyricNext),
                    lineHeight: 21,
                    clock: lyricClock
                )
                .padding(.leading, 12)
            }

        }
        .frame(width: ExpandedMusicLayout.lyricColumnWidth, alignment: .leading)
    }
}

private struct MusicProgressRow: View {
    @ObservedObject var model: IslandModel
    let timelineWidth: CGFloat
    let prominent: Bool
    @State private var scrubPreviewProgress: Double?

    init(model: IslandModel, timelineWidth: CGFloat = ExpandedMusicLayout.timelineWidth, prominent: Bool = false) {
        _model = ObservedObject(wrappedValue: model)
        self.timelineWidth = timelineWidth
        self.prominent = prominent
    }

    var body: some View {
        HStack(spacing: ExpandedMusicLayout.timelineToTimeSpacing) {
            ProgressPill(
                progress: model.music.progress,
                width: timelineWidth,
                accentColor: model.musicAccentColor,
                prominent: prominent,
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
                onSeek: (model.music.canSeek
                    || (model.music.track.sourceBundleIdentifier == "com.soda.music"
                        && model.music.hasCurrentTrack
                        && (model.music.duration ?? 0) > 0)) ? { progress, interaction in
                    await model.seekMusic(to: progress, interaction: interaction)
                } : nil
            )
            .help(model.music.canSeek ? "拖动调整播放进度" : "当前歌曲暂不支持进度拖动")

            Text(playbackPositionText(model.music, progressOverride: scrubPreviewProgress))
                .font(IslandTheme.Typeface.timeReadout)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .foregroundStyle(.white.opacity(IslandTheme.Ink.timeReadout))
                .frame(width: ExpandedMusicLayout.timeWidth, alignment: .leading)
        }
        .padding(.horizontal, prominent ? 11 : 0)
        .frame(height: prominent ? 30 : nil)
        .background {
            if prominent {
                RoundedRectangle(cornerRadius: IslandTheme.Radius.progressPill)
                    .fill(.white.opacity(IslandTheme.Fill.progressPill))
            }
        }
        .onDisappear {
            model.setMusicScrubbing(false)
        }
    }
}
