import AppKit
import Foundation

@MainActor
final class AlbumArtworkImageCache {
    static let shared = AlbumArtworkImageCache()

    private struct Entry {
        let data: Data
        let image: NSImage
    }

    private let capacity: Int
    private let decoder: (Data) -> NSImage?
    private var entries: [Entry] = []

    init(
        capacity: Int = 12,
        decoder: @escaping (Data) -> NSImage? = { NSImage(data: $0) }
    ) {
        self.capacity = max(capacity, 1)
        self.decoder = decoder
    }

    func image(for data: Data) -> NSImage? {
        if let index = entries.firstIndex(where: { $0.data == data }) {
            if index == 0 {
                return entries[0].image
            }
            let entry = entries.remove(at: index)
            entries.insert(entry, at: 0)
            return entry.image
        }
        guard let image = decoder(data) else { return nil }
        entries.insert(Entry(data: data, image: image), at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
        return image
    }

    var cachedImageCount: Int {
        entries.count
    }
}
