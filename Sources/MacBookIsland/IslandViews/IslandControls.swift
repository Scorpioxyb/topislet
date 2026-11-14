import AppKit
import ApplicationServices
import Combine
import Darwin
import EventKit
import ImageIO
import QuartzCore
import SwiftUI

func cleanIslandLyricLines(_ lines: [String]) -> [String] {
    MusicLyricPresentation.clean(lines)
}

struct AlbumArt: View {
    let track: MusicTrack
    let size: CGFloat

    var body: some View {
        ZStack {
            if let artworkData = track.artworkData,
               let image = AlbumArtworkImageCache.shared.image(for: artworkData) {
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
                    colors: track.hasArtwork ? track.palette : [Color.white.opacity(IslandTheme.Fill.artworkFallbackTop), Color.white.opacity(IslandTheme.Fill.artworkFallbackBottom)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(IslandTheme.Fill.artworkGlyphBackdrop))
                        .frame(width: size * 0.55, height: size * 0.55)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.28, weight: .semibold))
                        .foregroundStyle(.white.opacity(IslandTheme.Ink.artworkGlyph))
                }
            }
    }
}

@MainActor
final class MusicSourceIconCache {
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
                    .font(IslandTheme.Typeface.badgeGlyph)
                    .foregroundStyle(.white.opacity(IslandTheme.Ink.controlGlyph))
                    .frame(width: size, height: size)
                    .background(
                        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                            .fill(Color.black.opacity(IslandTheme.Surface.badgeBackdrop))
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
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        prominent
                            ? Color.white
                            : Color.white.opacity(isHovering ? IslandTheme.Fill.buttonHover : IslandTheme.Fill.button)
                    )

                Image(systemName: icon)
                    .font(.system(size: prominent ? 13 : 12, weight: .bold))
                    .foregroundStyle(prominent ? Color.black : Color.white.opacity(IslandTheme.Ink.controlGlyph))
                    .id(icon)
                    .transition(iconTransition)
            }
            .frame(width: prominent ? max(size, 34) : size, height: prominent ? max(size, 34) : size)
        }
        .buttonStyle(IslandControlButtonStyle())
        .opacity(isEnabled ? 1 : IslandTheme.Ink.disabledControl)
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.08)
                : prominent
                    ? .easeOut(duration: 0.1)
                    : .interactiveSpring(response: 0.2, dampingFraction: 0.86),
            value: icon
        )
    }

    private var iconTransition: AnyTransition {
        guard !reduceMotion, !prominent else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.76)),
            removal: .opacity.combined(with: .scale(scale: 1.08))
        )
    }

}

private struct IslandControlButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .brightness(configuration.isPressed ? 0.1 : 0)
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
                    .font(IslandTheme.Typeface.textButtonIcon)
                Text(title)
                    .font(IslandTheme.Typeface.textButtonLabel)
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
    var accentColor: Color = .white
    var prominent = false
    var onPreviewChanged: ((Double?) -> Void)? = nil
    var onSeek: ((Double, MusicSeekInteraction) async -> Bool)? = nil

    @State private var dragProgress: Double?
    @State private var isDragging = false
    @State private var isPointerDown = false
    @State private var isHovering = false
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
                    .fill(Color.white.opacity(prominent ? IslandTheme.Fill.progressTrackProminent : IslandTheme.Fill.progressTrack))
                    .frame(height: prominent ? 6 : 4)
                    .frame(maxHeight: .infinity, alignment: .center)

                Capsule()
                    .fill(accentColor.opacity(isDragging ? 1 : IslandTheme.Accent.progressFill))
                    .frame(width: progressWidth, height: prominent ? 6 : 4)
                    .frame(maxHeight: .infinity, alignment: .center)

                if onSeek != nil {
                    Circle()
                        .fill(accentColor)
                        .frame(width: knobSize, height: knobSize)
                        .scaleEffect(isDragging ? 1.25 : 1)
                        .shadow(color: Color.black.opacity(isDragging ? 0.42 : 0.28), radius: isDragging ? 5 : 3, x: 0, y: 1)
                        .opacity(isHovering || isPointerDown || isDragging ? 1 : 0)
                        .animation(.easeOut(duration: 0.1), value: isHovering)
                        .animation(.easeOut(duration: 0.12), value: isDragging)
                        .offset(x: knobX)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .animation(
                dragProgress == nil && !isPointerDown && !isDragging
                    ? .linear(duration: 0.4)
                    : nil,
                value: displayedProgress
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
            .overlay {
                if onSeek != nil {
                    Slider(
                        value: Binding(
                            get: { displayedProgress },
                            set: { value in
                                dragProgress = min(max(value, 0), 1)
                                isDragging = true
                                onPreviewChanged?(dragProgress)
                            }
                        ),
                        in: 0...1,
                        onEditingChanged: { editing in
                            if editing {
                                isPointerDown = true
                                seekGeneration += 1
                            } else {
                                let target = dragProgress ?? displayedProgress
                                isPointerDown = false
                                isDragging = false
                                submitSeek(to: target, interaction: .drag)
                            }
                        }
                    )
                    .labelsHidden()
                    .accessibilityLabel("播放进度")
                    .opacity(0.02)
                    .frame(width: availableWidth, height: 24)
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard onSeek != nil else { return }
                        if !isPointerDown {
                            isPointerDown = true
                            seekGeneration += 1
                        }
                        let target = min(max(value.location.x / availableWidth, 0), 1)
                        dragProgress = target
                        isDragging = abs(value.translation.width) >= 3
                        onPreviewChanged?(target)
                    }
                    .onEnded { value in
                        guard onSeek != nil else { return }
                        let target = min(max(value.location.x / availableWidth, 0), 1)
                        let interaction: MusicSeekInteraction = isDragging ? .drag : .click
                        dragProgress = target
                        isPointerDown = false
                        isDragging = false
                        submitSeek(to: target, interaction: interaction)
                    }
            )
        }
        .frame(width: width, height: onSeek == nil ? 4 : 24)
        .onDisappear {
            isPointerDown = false
            isDragging = false
            isHovering = false
            dragProgress = nil
        }
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
