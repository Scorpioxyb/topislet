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
