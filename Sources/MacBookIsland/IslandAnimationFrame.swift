import Foundation

enum IslandAnimationFrame {
    /// Round dimensions before calculating origin so WindowServer cannot round
    /// fractional height and origin independently and move the anchored top.
    static func anchored(_ proposed: CGRect, to target: CGRect) -> CGRect {
        let width = proposed.width.rounded()
        let height = proposed.height.rounded()
        return CGRect(x: target.midX - width / 2,
                      y: target.maxY - height, width: width, height: height)
    }
}
