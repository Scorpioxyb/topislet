import AppKit
import ApplicationServices
import Combine
import Darwin
import EventKit
import ImageIO
import QuartzCore
import SwiftUI

private struct MarqueeTextWidthKey: PreferenceKey {
    static let defaultValue = MarqueeTextMeasurement(text: "", width: 0)

    static func reduce(value: inout MarqueeTextMeasurement, nextValue: () -> MarqueeTextMeasurement) {
        value = nextValue()
    }
}

final class MarqueeClock: ObservableObject {
    @Published private(set) var start = Date()

    func restart() {
        start = Date()
    }
}

private struct MarqueeLine: View {
    let text: String
    let font: Font
    let color: Color
    let offset: CGFloat
    let lineHeight: CGFloat
    var alignment: Alignment = .leading

    var body: some View {
        Text(text)
        .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            // Preserve intrinsic width for horizontal scrolling while letting
            // the taller line box center the full glyph run inside the safe
            // band. A font-sized vertical frame clips ascenders and descenders.
            .fixedSize(horizontal: true, vertical: true)
            .offset(x: -offset)
            .frame(
                maxWidth: .infinity,
                minHeight: lineHeight,
                maxHeight: lineHeight,
                alignment: alignment
            )
    }
}

struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let lineHeight: CGFloat
    var clock: MarqueeClock? = nil
    /// Center the line while it fits; see `MarqueeTextLayoutPolicy.centersLine`.
    var centered = false
    @State private var measurement: MarqueeTextMeasurement?
    @State private var animationStart = Date()

    var body: some View {
        GeometryReader { proxy in
            let baseDate = clock?.start ?? animationStart
            let overflow = MarqueeTextLayoutPolicy.overflow(
                for: text,
                measurement: measurement,
                viewportWidth: proxy.size.width
            )
            TimelineView(
                .animation(minimumInterval: 1.0 / 30.0, paused: overflow <= 0 || text.isEmpty)
            ) { (context: TimelineViewDefaultContext) in
                let offset = MusicMarqueeTimeline.offset(
                    elapsed: context.date.timeIntervalSince(baseDate),
                    overflow: overflow,
                    speed: MusicMarqueeTimeline.speed(for: overflow)
                )
                MarqueeLine(
                    text: text,
                    font: font,
                    color: color,
                    offset: offset,
                    lineHeight: lineHeight,
                    alignment: MarqueeTextLayoutPolicy.centersLine(
                        overflow: overflow, prefersCentered: centered
                    ) ? .center : .leading
                )
            }
            // Constrain TimelineView to the measured column: its fixed-size
            // text must not expand the clipping viewport past the capsule.
            .frame(width: proxy.size.width, height: lineHeight, alignment: .leading)
            .clipped()
            .mask {
                // Fade only the trailing edge. Fading the leading 6% made the
                // first glyph look clipped at the resting position, which is
                // especially obvious for short bilingual lyric pairs.
                // Fade the trailing edge only when the line is too wide and
                // scrolls; a line that fits must keep its last glyph solid.
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: overflow > 0 ? 0.96 : 1),
                        .init(color: overflow > 0 ? .clear : .black, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .background(
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
                    .background(
                        GeometryReader { measured in
                            Color.clear.preference(
                                key: MarqueeTextWidthKey.self,
                                value: MarqueeTextMeasurement(text: text, width: measured.size.width)
                            )
                        }
                    )
                    .hidden()
            )
        }
        .frame(height: lineHeight)
        .onPreferenceChange(MarqueeTextWidthKey.self) { nextMeasurement in
            if measurement != nextMeasurement {
                measurement = nextMeasurement
                if clock == nil {
                    animationStart = Date()
                }
            }
        }
        .onChange(of: text) { _, _ in
            measurement = nil
            if clock == nil {
                animationStart = Date()
            }
        }
        .onAppear {
            if clock == nil {
                animationStart = Date()
            }
        }
    }

}

private struct KaraokeLyricWidthKey: PreferenceKey {
    static let defaultValue: MarqueeTextMeasurement? = nil

    static func reduce(value: inout MarqueeTextMeasurement?, nextValue: () -> MarqueeTextMeasurement?) {
        value = nextValue() ?? value
    }
}

/// Renders a verified active lyric as a normal karaoke line: characters that
/// have been reached use the strong color, while the remaining characters stay
/// visible but quiet. Qishui currently exposes active rows, not LRC/word
/// timestamps, so the reveal is deliberately an honest visual estimate and
/// resets whenever the source advances to another active row.
struct KaraokeLyricText: View {
    let text: String
    let font: Font
    let highlightedColor: Color
    let unhighlightedColor: Color
    let lineHeight: CGFloat
    let clock: MarqueeClock
    let isPlaying: Bool
    let words: [QishuiTimedWord]
    let elapsedTime: TimeInterval
    let sampledAt: Date
    /// Center the line while it fits; see `MarqueeTextLayoutPolicy.centersLine`.
    var centered = false
    @State private var measurement: MarqueeTextMeasurement?

    var body: some View {
        GeometryReader { proxy in
            let baseDate = clock.start
            let overflow = MarqueeTextLayoutPolicy.overflow(
                for: text,
                measurement: measurement,
                viewportWidth: proxy.size.width
            )
            let glyphs: [(String, TimeInterval)] = words.flatMap { word in
                let characters = Array(word.text)
                return characters.enumerated().map { index, character in
                    let fraction = Double(index) / Double(max(characters.count, 1))
                    return (String(character), word.start + (word.end - word.start) * fraction)
                }
            }
            TimelineView(
                .animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying || text.isEmpty)
            ) { (context: TimelineViewDefaultContext) in
                let elapsed = max(context.date.timeIntervalSince(baseDate), 0)
                let position = elapsedTime + (isPlaying ? max(context.date.timeIntervalSince(sampledAt), 0) : 0)
                let offset = MusicMarqueeTimeline.offset(
                    elapsed: elapsed,
                    overflow: overflow,
                    speed: MusicMarqueeTimeline.speed(for: overflow)
                )
                let reached = glyphs.firstIndex { $0.1 > position } ?? glyphs.count
                let sung = glyphs[..<reached].map(\.0).joined()
                let upcoming = glyphs[reached...].map(\.0).joined()
                (Text(sung).foregroundColor(highlightedColor)
                    + Text(upcoming).foregroundColor(unhighlightedColor))
                .font(font)
                .fixedSize(horizontal: true, vertical: true)
                .offset(x: -offset)
                .frame(
                    maxWidth: .infinity, minHeight: lineHeight, maxHeight: lineHeight,
                    alignment: MarqueeTextLayoutPolicy.centersLine(
                        overflow: overflow, prefersCentered: centered
                    ) ? .center : .leading
                )
            }
            .frame(width: proxy.size.width, height: lineHeight, alignment: .leading)
            .clipped()
            .mask {
                // Fade the trailing edge only when the line is too wide and
                // scrolls; a line that fits must keep its last glyph solid.
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: overflow > 0 ? 0.96 : 1),
                        .init(color: overflow > 0 ? .clear : .black, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .background(
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
                    .background(
                        GeometryReader { measured in
                            Color.clear.preference(
                                key: KaraokeLyricWidthKey.self,
                                value: MarqueeTextMeasurement(text: text, width: measured.size.width)
                            )
                        }
                    )
                    .hidden()
            )
        }
        .frame(height: lineHeight)
        .onPreferenceChange(KaraokeLyricWidthKey.self) { nextMeasurement in
            if measurement != nextMeasurement {
                measurement = nextMeasurement
            }
        }
    }
}
