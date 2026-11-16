import AppKit
import CoreImage
import ApplicationServices
import Combine
import Darwin
import EventKit
import ImageIO
import QuartzCore
import SwiftUI

struct ExpandedMusic: View {
    @ObservedObject var model: IslandModel
    /// Controls replace the resting progress hairline while the pointer is
    /// over the panel (direction C).
    let isPointerOver: Bool

    private var lyricPairs: (current: LyricPair, next: LyricPair) {
        MusicLyricPresentation.sourceCurrentAndNextPairs(
            lines: model.music.track.lyrics,
            index: model.music.lyricIndex,
            pairMixedLanguageLines: !model.music.track.lyricsAreDesktopSnapshot
        )
    }

    private var showsLyrics: Bool {
        model.isMusicLyricsEnabled && MusicLyricPresentation.hasDisplayableLines(model.music.track.lyrics)
    }

    private var showsControls: Bool {
        MusicExpandedChrome.showsControls(
            isPointerOver: isPointerOver,
            needsRecovery: model.shouldPresentMusicControlRecovery,
            voiceOverEnabled: NSWorkspace.shared.isVoiceOverEnabled
        )
    }

    var body: some View {
        // One fixed composition: cover on the left, a single reading column on
        // the right. The panel keeps its size whether or not lyrics exist, so
        // late or missing lyrics never resize the window.
        HStack(alignment: .top, spacing: ExpandedMusicLayout.artworkToColumnSpacing) {
            AlbumArt(
                track: model.music.track,
                size: ExpandedMusicLayout.artworkSize,
                cornerRadius: ExpandedMusicLayout.artworkCornerRadius,
                showsSourceBadge: false
            )
            .shadow(color: .black.opacity(IslandTheme.Surface.musicCoverShadowOpacity), radius: 15, x: 0, y: 12)

            ZStack(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    if showsLyrics {
                        MusicMetaLine(track: model.music.track)
                        LyricsShelf(
                            current: lyricPairs.current,
                            next: lyricPairs.next,
                            hidesNextBehindControls: showsControls,
                            isDesktopSnapshot: model.music.track.lyricsAreDesktopSnapshot,
                            isPlaying: model.music.isPlaying,
                            timedWords: model.music.track.timedWords,
                            elapsedTime: model.music.elapsedTime,
                            sampledAt: model.musicTimelineSampledAt
                        )
                        .padding(.top, 10)
                    } else {
                        MusicTitleBlock(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                ZStack(alignment: .leading) {
                    // Bottom of the row: centered, it would sit under the
                    // next lyric line like an underline.
                    MusicProgressHairline(progress: model.music.progress, accent: model.musicAccentColor)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .opacity(showsControls ? 0 : 1)
                        .accessibilityHidden(true)
                    MusicControlRow(model: model)
                        .opacity(showsControls ? 1 : 0)
                        .allowsHitTesting(showsControls)
                }
                .frame(height: ExpandedMusicLayout.controlRowHeight)
                .animation(.easeOut(duration: 0.16), value: showsControls)
            }
            .frame(width: ExpandedMusicLayout.columnWidth)
        }
        .padding(.leading, ExpandedMusicLayout.leadingInset)
        .padding(.top, ExpandedMusicLayout.topInset)
        .padding(.bottom, ExpandedMusicLayout.bottomInset)
        .frame(width: ExpandedMusicLayout.panelWidth, height: MusicExpandedLayout.bodyHeight(), alignment: .topLeading)
    }
}

enum ExpandedMusicPointerPolicy {
    /// Expand animation (0.24s) plus margin. Hover reports inside it are held
    /// and the latest one applied when it ends.
    static let openingGraceSeconds: Double = 0.32

    static func appliesHoverChange(secondsSinceOpen: Double) -> Bool {
        secondsSinceOpen >= openingGraceSeconds
    }
}

enum MusicExpandedChrome {
    /// Controls show on hover, and stay up when they carry a recovery action
    /// or when VoiceOver is reading the panel.
    static func showsControls(isPointerOver: Bool, needsRecovery: Bool, voiceOverEnabled: Bool) -> Bool {
        isPointerOver || needsRecovery || voiceOverEnabled
    }

    static func sourceName(bundleIdentifier: String?) -> String? {
        switch bundleIdentifier {
        case "com.soda.music": "汽水音乐"
        case "com.apple.Music": "Apple Music"
        case "com.netease.163music": "网易云音乐"
        default: nil
        }
    }
}

/// Artwork-colored glow behind the cover, used when the track has no
/// artwork image to wash the panel with. Hidden when the user asks for more
/// contrast.
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

/// The cover, blurred and spread from the left edge of the black panel
/// (direction C). The camera band stays pure black so the panel still reads
/// as part of the notch. Reduce Transparency and Increase Contrast fall back
/// to plain black.
struct MusicArtworkWash: View {
    let track: MusicTrack
    let accent: Color
    let topBandHeight: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    private var wash: some View {
        if let artworkData = track.artworkData,
           let washed = MusicArtworkWashCache.shared.image(for: artworkData) {
            Image(nsImage: washed)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: IslandTheme.Surface.musicWashSize.width,
                       height: IslandTheme.Surface.musicWashSize.height)
                .clipped()
                .opacity(IslandTheme.Surface.musicWashOpacity)
                .mask {
                    LinearGradient(
                        stops: [.init(color: .black, location: 0.25), .init(color: .clear, location: 0.92)],
                        startPoint: .leading, endPoint: .trailing
                    )
                }
                .offset(x: IslandTheme.Surface.musicWashOffset.width,
                        y: IslandTheme.Surface.musicWashOffset.height)
        } else {
            MusicAmbientGlow(accent: accent)
        }
    }

    var body: some View {
        if contrast == .increased || reduceTransparency {
            Color.clear
        } else {
            // Overlays, not a ZStack: the 300pt-tall wash must not size the
            // view, or the shell would center it and push the band off-top.
            Color.clear
                .overlay(alignment: .topLeading) { wash }
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0), location: 0),
                            .init(color: .black.opacity(0.25), location: 0.40),
                            .init(color: .black, location: 0.78)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                }
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        Color.black.frame(height: topBandHeight)
                        LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 26)
                    }
                }
                .clipped()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Blurred, saturated, low-resolution copy of the current cover. One entry:
/// the panel only ever shows the current track.
@MainActor
final class MusicArtworkWashCache {
    static let shared = MusicArtworkWashCache()
    private static let context = CIContext(options: [.useSoftwareRenderer: false])
    private var entry: (key: Data, image: NSImage?)?

    func image(for data: Data) -> NSImage? {
        if let entry, entry.key == data { return entry.image }
        let image = Self.render(data)
        entry = (data, image)
        return image
    }

    private static func render(_ data: Data) -> NSImage? {
        guard let source = CIImage(data: data), source.extent.width > 0, source.extent.height > 0 else { return nil }
        let scale = 64 / max(source.extent.width, source.extent.height)
        let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = small.extent
        let blurred = small.clampedToExtent()
            .applyingGaussianBlur(sigma: 5)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.35])
            .cropped(to: extent)
        guard let cgImage = context.createCGImage(blurred, from: extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: extent.width, height: extent.height))
    }
}

private struct MusicMetaLine: View {
    let track: MusicTrack

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(track.title)
                .font(IslandTheme.Typeface.musicTitle)
                .foregroundStyle(.white.opacity(IslandTheme.Ink.musicTitle))
                .layoutPriority(1)
            Text(track.artist)
                .font(IslandTheme.Typeface.musicArtist)
                .foregroundStyle(.white.opacity(IslandTheme.Ink.musicArtist))
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(height: 18, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Without lyrics the title takes the lyric's place, so the panel keeps its
/// shape.
private struct MusicTitleBlock: View {
    @ObservedObject var model: IslandModel

    private var statusLine: String? {
        let lines = model.music.track.lyrics
        if model.isMusicLyricsEnabled && MusicLyricPresentation.isConfirmedInstrumental(lines) {
            return MusicLyricPresentation.emptyStateText(lines: lines, lyricsEnabled: true)
        }
        return MusicExpandedChrome.sourceName(bundleIdentifier: model.music.track.sourceBundleIdentifier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.music.track.title)
                .font(IslandTheme.Typeface.musicStageTitle)
                .foregroundStyle(.white.opacity(IslandTheme.Ink.musicTitle))
                .minimumScaleFactor(LyricFitPolicy.minimumScale)
                .frame(height: 32, alignment: .leading)
                .padding(.top, 6)
            Text(model.music.track.artist)
                .font(IslandTheme.Typeface.musicStageArtist)
                .foregroundStyle(.white.opacity(IslandTheme.Ink.musicArtist))
                .frame(height: 21, alignment: .leading)
                .padding(.top, 2)
            if let statusLine {
                Text(statusLine)
                    .font(IslandTheme.Typeface.musicStatus)
                    .foregroundStyle(.white.opacity(IslandTheme.Ink.musicStatus))
                    .padding(.top, 8)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .accessibilityElement(children: .combine)
    }
}

private struct MusicControlRow: View {
    @ObservedObject var model: IslandModel
    @State private var scrubPreviewProgress: Double?

    private var times: (elapsed: String, remaining: String) {
        playbackElapsedAndRemainingText(model.music, progressOverride: scrubPreviewProgress)
    }

    var body: some View {
        HStack(spacing: 12) {
            transport
            Text(times.elapsed)
                .font(IslandTheme.Typeface.timeReadout)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(IslandTheme.Ink.timeReadout))
                .fixedSize()
            ProgressPill(
                progress: model.music.progress,
                width: nil,
                accentColor: model.musicAccentColor,
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
            .frame(maxWidth: .infinity)
            .frame(height: ExpandedMusicLayout.controlRowHeight)
            .help(model.music.canSeek ? "拖动调整播放进度" : "当前歌曲暂不支持进度拖动")
            Text(times.remaining)
                .font(IslandTheme.Typeface.timeReadout)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(IslandTheme.Ink.timeReadout))
                .fixedSize()
        }
        .frame(height: ExpandedMusicLayout.controlRowHeight)
        .onDisappear {
            model.setMusicScrubbing(false)
        }
    }

    @ViewBuilder
    private var transport: some View {
        if model.shouldPresentMusicControlRecovery {
            Button {
                model.recoverCurrentMusicControl()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text(model.isRecoveringMusicControl ? "连接中" : "恢复控制")
                }
                .font(IslandTheme.Typeface.recoveryLabel)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(Color.white.opacity(IslandTheme.Fill.button)))
            }
            .buttonStyle(.plain)
            .disabled(model.isRecoveringMusicControl)
            .help("重启并连接汽水音乐播放控制")
        } else {
            HStack(spacing: 4) {
                ControlButton(icon: "backward.fill", size: 28) {
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
                    size: 30,
                    minimumProminentSize: 30
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

                ControlButton(icon: "forward.fill", size: 28) {
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

/// Resting progress: a 2pt line in the cover's accent.
private struct MusicProgressHairline: View {
    let progress: Double
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(IslandTheme.Fill.progressHairlineTrack))
                Capsule().fill(accent.opacity(IslandTheme.Accent.progressFill))
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: 2)
        .animation(.linear(duration: 0.4), value: progress)
    }
}

private struct LyricsShelf: View {
    let current: LyricPair
    let next: LyricPair
    let hidesNextBehindControls: Bool
    let isDesktopSnapshot: Bool
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
            .frame(width: ExpandedMusicLayout.columnWidth, alignment: .topLeading)
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

    /// Current line shrinks (down to 85%) before it has to scroll.
    private var currentLineSize: CGFloat {
        let base = IslandTheme.Typeface.lyricCurrentSize
        let natural = NSAttributedString(
            string: current.primary,
            attributes: [.font: NSFont.systemFont(ofSize: base, weight: .semibold)]
        ).size().width
        return LyricFitPolicy.pointSize(
            naturalWidth: natural,
            availableWidth: ExpandedMusicLayout.columnWidth,
            base: base
        )
    }

    /// With a translation the next line sits where the controls appear, so
    /// it steps aside while they are up.
    private var showsNext: Bool {
        !next.primary.isEmpty && next.primary != current.primary
    }

    private var nextOpacity: Double {
        hidesNextBehindControls && !current.translation.isEmpty ? 0 : 1
    }

    private var lyricLines: some View {
        VStack(alignment: .leading, spacing: 0) {
            let currentFont = IslandTheme.Typeface.lyricCurrent(size: currentLineSize)
            Group {
                if let elapsedTime, !timedWords.isEmpty {
                    KaraokeLyricText(
                        text: current.primary,
                        font: currentFont,
                        highlightedColor: .white.opacity(IslandTheme.Ink.lyricHighlighted),
                        unhighlightedColor: .white.opacity(IslandTheme.Ink.lyricUnhighlighted),
                        lineHeight: 32,
                        clock: lyricClock,
                        isPlaying: isPlaying,
                        words: timedWords,
                        elapsedTime: elapsedTime,
                        sampledAt: sampledAt
                    )
                } else {
                    MarqueeText(
                        text: current.primary,
                        font: currentFont,
                        color: .white.opacity(IslandTheme.Ink.lyricHighlighted),
                        lineHeight: 32,
                        clock: lyricClock
                    )
                }
            }
            .frame(height: 32)

            if !current.translation.isEmpty {
                MarqueeText(
                    text: current.translation,
                    font: IslandTheme.Typeface.lyricTranslation,
                    color: .white.opacity(IslandTheme.Ink.lyricTranslation),
                    lineHeight: 20,
                    clock: lyricClock
                )
                .frame(height: 20)
                .padding(.top, 4)
            }

            if showsNext {
                MarqueeText(
                    text: next.primary,
                    font: IslandTheme.Typeface.lyricNext,
                    color: .white.opacity(IslandTheme.Ink.lyricNext),
                    lineHeight: 21,
                    clock: lyricClock
                )
                .frame(height: 21)
                .padding(.top, 2)
                .opacity(nextOpacity)
                .animation(.easeOut(duration: 0.16), value: nextOpacity)
            }
        }
    }
}
