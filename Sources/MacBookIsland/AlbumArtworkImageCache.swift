import AppKit
import CryptoKit
import Foundation
import ImageIO

@MainActor
final class AlbumArtworkImageCache {
    static let shared = AlbumArtworkImageCache()

    private static let maximumPixelSize = 256
    private static let defaultMaximumTotalCostBytes = 1 * 1024 * 1024

    private struct Entry {
        let key: Data
        let image: NSImage
        let decodedCostBytes: Int
    }

    private let capacity: Int
    private let maximumTotalCostBytes: Int
    private let costCalculator: @MainActor (NSImage) -> Int
    private let decoder: @MainActor (Data) -> NSImage?
    private var entries: [Entry] = []
    private(set) var cachedTotalCostBytes = 0

    init(
        capacity: Int = 4,
        maximumTotalCostBytes: Int = AlbumArtworkImageCache.defaultMaximumTotalCostBytes,
        costCalculator: @escaping @MainActor (NSImage) -> Int = AlbumArtworkImageCache.estimatedDecodedCostBytes,
        decoder: @escaping @MainActor (Data) -> NSImage? = AlbumArtworkImageCache.decodeDownsampledArtwork
    ) {
        self.capacity = max(capacity, 1)
        self.maximumTotalCostBytes = max(maximumTotalCostBytes, 1)
        self.costCalculator = costCalculator
        self.decoder = decoder
    }

    func image(for data: Data) -> NSImage? {
        let key = Data(SHA256.hash(data: data))
        if let index = entries.firstIndex(where: { $0.key == key }) {
            if index == 0 {
                return entries[0].image
            }
            let entry = entries.remove(at: index)
            entries.insert(entry, at: 0)
            return entry.image
        }

        guard let image = autoreleasepool(invoking: { decoder(data) }) else { return nil }
        let decodedCostBytes = max(costCalculator(image), 1)

        // An image larger than the whole cache budget can still be displayed once,
        // but retaining it would immediately evict every useful cached thumbnail.
        guard decodedCostBytes <= maximumTotalCostBytes else { return image }

        entries.insert(
            Entry(key: key, image: image, decodedCostBytes: decodedCostBytes),
            at: 0
        )
        cachedTotalCostBytes += decodedCostBytes
        evictIfNeeded()
        return image
    }

    func removeAll() {
        entries.removeAll(keepingCapacity: false)
        cachedTotalCostBytes = 0
    }

    private func evictIfNeeded() {
        while entries.count > capacity || cachedTotalCostBytes > maximumTotalCostBytes {
            let removed = entries.removeLast()
            cachedTotalCostBytes -= removed.decodedCostBytes
        }
    }

    var cachedImageCount: Int {
        entries.count
    }

    private static func decodeDownsampledArtwork(_ data: Data) -> NSImage? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        let representation = NSBitmapImageRep(cgImage: thumbnail)
        let image = NSImage(size: NSSize(width: thumbnail.width, height: thumbnail.height))
        image.addRepresentation(representation)
        return image
    }

    private static func estimatedDecodedCostBytes(_ image: NSImage) -> Int {
        let pixelSize = image.representations.reduce((width: 0, height: 0)) { result, representation in
            (
                width: max(result.width, representation.pixelsWide),
                height: max(result.height, representation.pixelsHigh)
            )
        }
        let width = max(pixelSize.width, Int(image.size.width.rounded(.up)), 1)
        let height = max(pixelSize.height, Int(image.size.height.rounded(.up)), 1)

        let (pixelCount, overflowed) = width.multipliedReportingOverflow(by: height)
        guard !overflowed else { return .max }
        let (byteCount, byteOverflowed) = pixelCount.multipliedReportingOverflow(by: 4)
        return byteOverflowed ? .max : byteCount
    }
}
