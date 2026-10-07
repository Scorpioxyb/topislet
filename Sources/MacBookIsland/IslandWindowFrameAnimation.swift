import AppKit
import QuartzCore

@MainActor
enum IslandWindowFrameAnimation {
    static func install(
        on window: NSWindow,
        duration: TimeInterval,
        controlPoints: (Double, Double, Double, Double),
        startTime: TimeInterval = CACurrentMediaTime()
    ) {
        let animation = CABasicAnimation(keyPath: "frame")
        animation.duration = duration
        // Use the current media clock rather than an implicit transaction's
        // earlier begin time. AppKit still owns interpolation and completion.
        animation.beginTime = startTime
        animation.timingFunction = CAMediaTimingFunction(
            controlPoints: Float(controlPoints.0), Float(controlPoints.1),
            Float(controlPoints.2), Float(controlPoints.3)
        )
        window.animations["frame"] = animation
    }

    static func remove(from window: NSWindow) {
        // Preserve unrelated order/opacity animations. Remove this before
        // submitting a zero-duration replacement during cancellation.
        window.animations.removeValue(forKey: "frame")
    }
}
