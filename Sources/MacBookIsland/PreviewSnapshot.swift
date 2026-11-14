#if DEBUG
import AppKit
import SwiftUI

/// Debug-only visual QA: renders the island for the current preview state to
/// a PNG and quits, without opening a window or starting any music source.
/// Only honored together with the existing preview flags, which already keep
/// the live adapters stopped, e.g.
///   .build/debug/MacBookIsland --preview-lyrics --preview-mode expanded \
///       --render-snapshot /tmp/island.png
@MainActor
enum PreviewSnapshot {
    static func outputPath(arguments: [String], isPreview: Bool) -> String? {
        guard isPreview,
              let index = arguments.firstIndex(of: "--render-snapshot"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func render(model: IslandModel, to path: String) -> Bool {
        let expanded = model.mode == .expanded
        let width = expanded ? max(model.expandedWidth, model.expandedHeaderWidth) : model.currentHeaderWidth
        let height = expanded ? model.expandedHeight : model.topBandHeight
        let content = IslandRootView(model: model, onOpenSettings: {}, onQuit: {})
            .frame(width: width, height: height)
            .padding(24)
            .background(Color(white: 0.62))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return false }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
#endif
