import AppKit
import ApplicationServices
import Combine
import Darwin
import EventKit
import ImageIO
import QuartzCore
import SwiftUI

struct MusicTrack: Equatable {
    let title: String
    let artist: String
    let palette: [Color]
    let lyrics: [String]
    let hasArtwork: Bool
    let artworkData: Data?
    let artworkURL: URL?
    let sourceBundleIdentifier: String?
    var lyricsAreDesktopSnapshot: Bool = false
    var timedWords: [QishuiTimedWord] = []
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
    var canPlayPause: Bool = true
    var canPreviousTrack: Bool = true
    var canNextTrack: Bool = true
    var controlUnavailableReason: String? = nil
    var controlRecoveryAction: MusicControlRecoveryAction? = nil
    var hasCurrentTrack: Bool
    // Some direct adapters can provide a track before they can prove play/pause.
    // Keep that distinction so the UI never presents a guessed one-way action.
    var playbackStateKnown: Bool = true
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

enum FocusTimerPreset: Int, CaseIterable, Identifiable {
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case twentyFiveMinutes = 25
    case fortyFiveMinutes = 45

    var id: Int { rawValue }
    var title: String { "\(rawValue) 分钟" }
    var compactTitle: String { "\(rawValue) 分" }
    var durationSeconds: Int { rawValue * 60 }
}

struct IslandNotification: Equatable {
    var title: String
    var body: String
    var source: String
    var count: Int
}

enum IslandEventPriority: Int {
    case normal
    case urgent
}

struct PendingIslandEvent: Equatable {
    var title: String
    var body: String
    var source: String
    let priority: IslandEventPriority
    let autoDismiss: Bool
    var count: Int
    let mergeIdentifier: String?
    var sourceBundleIdentifier: String?
}

struct PendingMusicSeek {
    let trackSignature: String
    let sourceBundleIdentifier: String?
    let targetProgress: Double
    let requestedAt: Date
    let issuedAt: Date
    let isPlaying: Bool
    let expiresAt: Date
    var matchingSince: Date?
}

struct ArtworkAccentComponents: Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var relativeLuminance: Double {
        func linearized(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return linearized(red) * 0.2126
            + linearized(green) * 0.7152
            + linearized(blue) * 0.0722
    }
}

enum ArtworkAccentTransitionPolicy {
    static let missingArtworkGraceNanoseconds: UInt64 = 650_000_000

    static func shouldDelayNeutralFallback(hasCurrentTrack: Bool) -> Bool {
        hasCurrentTrack
    }
}

func artworkAccentComponents(from data: Data) -> ArtworkAccentComponents? {
    let sourceOptions = [
        kCGImageSourceShouldCache: false
    ] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
        return nil
    }
    let thumbnailOptions = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: 32,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true
    ] as CFDictionary
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
        return nil
    }

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let width = thumbnail.width
    let height = thumbnail.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
        guard let baseAddress = bytes.baseAddress,
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
              ) else { return false }
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard rendered else { return nil }

    var redTotal = 0.0
    var greenTotal = 0.0
    var blueTotal = 0.0
    var sampleCount = 0
    var hueCounts = [Int](repeating: 0, count: 12)
    var hueRed = [Double](repeating: 0, count: 12)
    var hueGreen = [Double](repeating: 0, count: 12)
    var hueBlue = [Double](repeating: 0, count: 12)
    var chromaticCount = 0
    for offset in stride(from: 0, to: pixels.count, by: 4) {
        let alpha = Double(pixels[offset + 3])
        guard alpha > 20 else { continue }
        let unpremultiply = 255 / alpha
        let red = min(Double(pixels[offset]) * unpremultiply, 255) / 255
        let green = min(Double(pixels[offset + 1]) * unpremultiply, 255) / 255
        let blue = min(Double(pixels[offset + 2]) * unpremultiply, 255) / 255
        redTotal += red
        greenTotal += green
        blueTotal += blue
        sampleCount += 1
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        guard maximum > 0.18, delta / maximum > 0.22 else { continue }
        let hue: Double
        if maximum == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            hue = ((blue - red) / delta) + 2
        } else {
            hue = ((red - green) / delta) + 4
        }
        let unitHue = (hue / 6 + 1).truncatingRemainder(dividingBy: 1)
        let bin = min(Int(unitHue * 12), 11)
        hueCounts[bin] += 1
        hueRed[bin] += red
        hueGreen[bin] += green
        hueBlue[bin] += blue
        chromaticCount += 1
    }
    guard sampleCount > 0 else { return nil }
    if let peak = hueCounts.indices.max(by: { hueCounts[$0] < hueCounts[$1] }),
       chromaticCount >= sampleCount / 8,
       hueCounts[peak] >= max(chromaticCount / 4, sampleCount / 12) {
        let neighbors = [(peak + 11) % 12, peak, (peak + 1) % 12]
        let count = neighbors.reduce(0) { $0 + hueCounts[$1] }
        if count > 0 {
            return normalizedArtworkAccent(
                red: neighbors.reduce(0) { $0 + hueRed[$1] } / Double(count),
                green: neighbors.reduce(0) { $0 + hueGreen[$1] } / Double(count),
                blue: neighbors.reduce(0) { $0 + hueBlue[$1] } / Double(count)
            )
        }
    }
    return normalizedArtworkAccent(
        red: redTotal / Double(sampleCount),
        green: greenTotal / Double(sampleCount),
        blue: blueTotal / Double(sampleCount)
    )
}

private func normalizedArtworkAccent(
    red: Double,
    green: Double,
    blue: Double
) -> ArtworkAccentComponents {
    let maximum = max(red, green, blue)
    let minimum = min(red, green, blue)
    let delta = maximum - minimum
    guard maximum > 0, delta / maximum >= 0.12 else {
        return artworkAccentWithBlackBackgroundContrast(
            ArtworkAccentComponents(red: 0.86, green: 0.86, blue: 0.86)
        )
    }

    var hue: Double
    if maximum == red {
        hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
    } else if maximum == green {
        hue = ((blue - red) / delta) + 2
    } else {
        hue = ((red - green) / delta) + 4
    }
    hue /= 6
    if hue < 0 { hue += 1 }

    var saturation = min(max(delta / maximum, 0.25), 0.70)
    if (0.06...0.13).contains(hue) || (0.22...0.45).contains(hue) {
        saturation = min(saturation, 0.40)
    }
    let brightness = min(max(maximum, 0.63), 0.90)
    return artworkAccentWithBlackBackgroundContrast(
        rgbComponents(hue: hue, saturation: saturation, brightness: brightness)
    )
}

private func artworkAccentWithBlackBackgroundContrast(
    _ accent: ArtworkAccentComponents
) -> ArtworkAccentComponents {
    if accent.relativeLuminance > 0.52 {
        var lower = 0.0
        var upper = 1.0
        var result = accent
        for _ in 0..<14 {
            let scale = (lower + upper) / 2
            let candidate = ArtworkAccentComponents(
                red: accent.red * scale,
                green: accent.green * scale,
                blue: accent.blue * scale
            )
            if candidate.relativeLuminance > 0.52 {
                upper = scale
            } else {
                result = candidate
                lower = scale
            }
        }
        return result
    }
    guard accent.relativeLuminance < 0.20 else { return accent }
    var lower = 0.0
    var upper = 1.0
    var result = accent
    for _ in 0..<14 {
        let amount = (lower + upper) / 2
        let candidate = ArtworkAccentComponents(
            red: accent.red + (1 - accent.red) * amount,
            green: accent.green + (1 - accent.green) * amount,
            blue: accent.blue + (1 - accent.blue) * amount
        )
        if candidate.relativeLuminance >= 0.20 {
            result = candidate
            upper = amount
        } else {
            lower = amount
        }
    }
    return result
}

private func rgbComponents(
    hue: Double,
    saturation: Double,
    brightness: Double
) -> ArtworkAccentComponents {
    let scaledHue = hue * 6
    let sector = Int(floor(scaledHue)) % 6
    let fraction = scaledHue - floor(scaledHue)
    let p = brightness * (1 - saturation)
    let q = brightness * (1 - fraction * saturation)
    let t = brightness * (1 - (1 - fraction) * saturation)
    switch sector {
    case 0: return ArtworkAccentComponents(red: brightness, green: t, blue: p)
    case 1: return ArtworkAccentComponents(red: q, green: brightness, blue: p)
    case 2: return ArtworkAccentComponents(red: p, green: brightness, blue: t)
    case 3: return ArtworkAccentComponents(red: p, green: q, blue: brightness)
    case 4: return ArtworkAccentComponents(red: t, green: p, blue: brightness)
    default: return ArtworkAccentComponents(red: brightness, green: p, blue: q)
    }
}
