import CoreGraphics

enum IslandAnimationFrame {
    /// Round dimensions before calculating origin so WindowServer cannot round
    /// fractional height and origin independently and move the anchored top.
    ///
    /// The width keeps the target width's parity. WindowServer places windows on
    /// whole points, so an intermediate width of the other parity would put the
    /// centred origin on a half point, get rounded, and shift the content by half
    /// a point on every other frame: a visible one-pixel shake of the pill while
    /// the panel collapses. With matching parity every frame shares the target
    /// origin's fractional part, so the centre never moves.
    static func anchored(_ proposed: CGRect, to target: CGRect) -> CGRect {
        let width = parityMatchedWidth(proposed.width, targetWidth: target.width)
        let height = proposed.height.rounded()
        return CGRect(x: target.midX - width / 2,
                      y: target.maxY - height, width: width, height: height)
    }

    /// Nearest whole width with the target width's parity, rounded toward the
    /// target so it never overshoots the target or undershoots the proposal.
    static func parityMatchedWidth(_ proposed: CGFloat, targetWidth: CGFloat) -> CGFloat {
        let target = targetWidth.rounded()
        let halfSteps = ((proposed.rounded() - target) / 2).rounded(.towardZero)
        return target + halfSteps * 2
    }
}
