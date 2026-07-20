import AppKit
import Testing
@testable import MacBookIsland

@MainActor
@Test("相同封面数据只解码一次")
func albumArtworkCacheDecodesIdenticalDataOnce() throws {
    var decodeCount = 0
    let expectedImage = NSImage(size: NSSize(width: 10, height: 10))
    let cache = AlbumArtworkImageCache(capacity: 2) { _ in
        decodeCount += 1
        return expectedImage
    }

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
    let cache = AlbumArtworkImageCache(capacity: 2) { data in
        decodedValues.append(data.first ?? 0)
        return NSImage(size: NSSize(width: 10, height: 10))
    }

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
    let cache = AlbumArtworkImageCache(capacity: 2) { _ in
        decodeCount += 1
        return nil
    }

    #expect(cache.image(for: Data([9])) == nil)
    #expect(cache.image(for: Data([9])) == nil)
    #expect(decodeCount == 2)
    #expect(cache.cachedImageCount == 0)
}
