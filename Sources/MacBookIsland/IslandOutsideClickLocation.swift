import CoreGraphics

/// Captured before dispatching a click to the main actor. The pointer may have
/// moved by the time the presentation decides whether this click was outside.
struct IslandOutsideClickLocation {
    let appKitPoint: CGPoint

    init(windowServerPoint: CGPoint, primaryDisplayHeight: CGFloat) {
        appKitPoint = CGPoint(
            x: windowServerPoint.x,
            y: primaryDisplayHeight - windowServerPoint.y
        )
    }
}
