import AppKit
import Testing
@testable import MacBookIsland

@Test("封面主色从下采样图像提取")
func artworkAccentExtractionUsesValidArtworkData() throws {
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1_024,
            pixelsHigh: 1_024,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    )
    let bitmapData = try #require(bitmap.bitmapData)
    for row in 0..<bitmap.pixelsHigh {
        for column in 0..<bitmap.pixelsWide {
            let offset = row * bitmap.bytesPerRow + column * 4
            bitmapData[offset] = 230
            bitmapData[offset + 1] = 51
            bitmapData[offset + 2] = 26
            bitmapData[offset + 3] = 255
        }
    }
    let data = try #require(bitmap.representation(using: .png, properties: [:]))

    let accent = try #require(artworkAccentComponents(from: data))

    #expect(accent.red > accent.green)
    #expect(accent.green > accent.blue)
}

@Test("无效封面不能生成主色")
func artworkAccentExtractionRejectsInvalidData() {
    #expect(artworkAccentComponents(from: Data([0, 1, 2])) == nil)
}

@Test("深色封面强调色在黑底上保持清晰")
func artworkAccentExtractionRaisesDarkColorContrast() throws {
    let data = try solidArtworkData(red: 8, green: 20, blue: 118)

    let accent = try #require(artworkAccentComponents(from: data))

    #expect(accent.blue > accent.red)
    #expect(accent.blue > accent.green)
    #expect(accent.relativeLuminance >= 0.20)
}

@Test("灰阶封面保持中性强调色")
func artworkAccentExtractionKeepsNeutralArtworkNeutral() throws {
    let data = try solidArtworkData(red: 104, green: 104, blue: 104)

    let accent = try #require(artworkAccentComponents(from: data))

    #expect(abs(accent.red - accent.green) < 0.01)
    #expect(abs(accent.green - accent.blue) < 0.01)
    #expect(accent.relativeLuminance >= 0.20)
    #expect(accent.relativeLuminance <= 0.521)
}

@Test("高亮封面强调色在黑底上不过曝")
func artworkAccentExtractionCapsBrightColorGlare() throws {
    let data = try solidArtworkData(red: 252, green: 238, blue: 28)

    let accent = try #require(artworkAccentComponents(from: data))

    #expect(accent.red > accent.blue)
    #expect(accent.green > accent.blue)
    #expect(accent.relativeLuminance <= 0.521)
}

@Test("切歌封面稍晚到达时保持上一强调色而不闪白")
func artworkAccentTransitionDelaysFallbackForCurrentTrack() {
    #expect(
        ArtworkAccentTransitionPolicy.shouldDelayNeutralFallback(
            hasCurrentTrack: true
        )
    )
    #expect(
        !ArtworkAccentTransitionPolicy.shouldDelayNeutralFallback(
            hasCurrentTrack: false
        )
    )
}

private func solidArtworkData(red: UInt8, green: UInt8, blue: UInt8) throws -> Data {
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 96,
            pixelsHigh: 96,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    )
    let bitmapData = try #require(bitmap.bitmapData)
    for row in 0..<bitmap.pixelsHigh {
        for column in 0..<bitmap.pixelsWide {
            let offset = row * bitmap.bytesPerRow + column * 4
            bitmapData[offset] = red
            bitmapData[offset + 1] = green
            bitmapData[offset + 2] = blue
            bitmapData[offset + 3] = 255
        }
    }
    return try #require(bitmap.representation(using: .png, properties: [:]))
}
