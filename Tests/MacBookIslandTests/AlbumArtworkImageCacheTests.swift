import AppKit
import Testing
@testable import MacBookIsland

@MainActor
@Test("相同封面数据只解码一次")
func albumArtworkCacheDecodesIdenticalDataOnce() throws {
    var decodeCount = 0
    let expectedImage = NSImage(size: NSSize(width: 10, height: 10))
    let cache = AlbumArtworkImageCache(capacity: 2, decoder: { _ in
        decodeCount += 1
        return expectedImage
    })

    let first = try #require(cache.image(for: Data([1, 2, 3])))
    let second = try #require(cache.image(for: Data([1, 2, 3])))

    #expect(first === expectedImage)
    #expect(second === expectedImage)
    #expect(decodeCount == 1)
    #expect(cache.cachedImageCount == 1)
}

@MainActor
@Test("封面缓存按最近使用顺序淘汰")
func albumArtworkCacheEvictsLeastRecentlyUsedImage() {
    var decodedValues: [UInt8] = []
    let cache = AlbumArtworkImageCache(capacity: 2, decoder: { data in
        decodedValues.append(data.first ?? 0)
        return NSImage(size: NSSize(width: 10, height: 10))
    })

    _ = cache.image(for: Data([1]))
    _ = cache.image(for: Data([2]))
    _ = cache.image(for: Data([1]))
    _ = cache.image(for: Data([3]))
    _ = cache.image(for: Data([2]))

    #expect(decodedValues == [1, 2, 3, 2])
    #expect(cache.cachedImageCount == 2)
}

@MainActor
@Test("无效封面不会污染缓存")
func albumArtworkCacheDoesNotStoreDecodeFailures() {
    var decodeCount = 0
    let cache = AlbumArtworkImageCache(capacity: 2, decoder: { _ in
        decodeCount += 1
        return nil
    })

    #expect(cache.image(for: Data([9])) == nil)
    #expect(cache.image(for: Data([9])) == nil)
    #expect(decodeCount == 2)
    #expect(cache.cachedImageCount == 0)
}

@MainActor
@Test("封面缓存同时受解码内存预算约束")
func albumArtworkCacheEvictsImagesBeyondDecodedCostBudget() {
    var decodedValues: [UInt8] = []
    let cache = AlbumArtworkImageCache(
        capacity: 10,
        maximumTotalCostBytes: 800,
        costCalculator: { _ in 400 }
    ) { data in
        decodedValues.append(data.first ?? 0)
        return NSImage(size: NSSize(width: 10, height: 10))
    }

    _ = cache.image(for: Data([1]))
    _ = cache.image(for: Data([2]))
    _ = cache.image(for: Data([3]))
    _ = cache.image(for: Data([1]))

    #expect(decodedValues == [1, 2, 3, 1])
    #expect(cache.cachedImageCount == 2)
    #expect(cache.cachedTotalCostBytes == 800)
}

@MainActor
@Test("单张封面超过总预算时只显示不缓存")
func albumArtworkCacheDoesNotRetainOversizedDecodedImage() {
    var decodeCount = 0
    let cache = AlbumArtworkImageCache(
        capacity: 2,
        maximumTotalCostBytes: 100,
        costCalculator: { _ in 400 }
    ) { _ in
        decodeCount += 1
        return NSImage(size: NSSize(width: 10, height: 10))
    }

    _ = cache.image(for: Data([1]))
    _ = cache.image(for: Data([1]))

    #expect(decodeCount == 2)
    #expect(cache.cachedImageCount == 0)
    #expect(cache.cachedTotalCostBytes == 0)
}

@MainActor
@Test("大封面在进入缓存前下采样到 256 像素")
func albumArtworkCacheDownsamplesLargeArtwork() throws {
    let bitmap = try #require(
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1_024,
            pixelsHigh: 512,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    )
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    let cache = AlbumArtworkImageCache()

    let image = try #require(cache.image(for: data))
    let largestWidth = image.representations.map(\.pixelsWide).max() ?? 0
    let largestHeight = image.representations.map(\.pixelsHigh).max() ?? 0

    #expect(largestWidth <= 256)
    #expect(largestHeight <= 256)
    #expect(max(largestWidth, largestHeight) == 256)
}

@MainActor
@Test("封面缓存可在媒体来源退出时显式清空")
func albumArtworkCacheCanRemoveAllImages() {
    let cache = AlbumArtworkImageCache(capacity: 2, decoder: { _ in
        NSImage(size: NSSize(width: 10, height: 10))
    })

    _ = cache.image(for: Data([1]))
    _ = cache.image(for: Data([2]))
    cache.removeAll()

    #expect(cache.cachedImageCount == 0)
    #expect(cache.cachedTotalCostBytes == 0)
}
