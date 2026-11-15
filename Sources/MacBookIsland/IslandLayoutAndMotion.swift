import AppKit
import ApplicationServices
import Combine
import Darwin
import EventKit
import ImageIO
import QuartzCore
import SwiftUI

enum IslandWindowLayout {
    static func size(
        for mode: IslandMode,
        collapsedWidth: CGFloat,
        compactWidth: CGFloat,
        expandedWidth: CGFloat,
        expandedHeight: CGFloat,
        topBandHeight: CGFloat
    ) -> NSSize {
        switch mode {
        case .collapsed:
            return NSSize(width: collapsedWidth, height: topBandHeight)
        case .compact:
            return NSSize(width: compactWidth, height: topBandHeight)
        case .expanded:
            return NSSize(width: expandedWidth, height: expandedHeight)
        }
    }

    static func frame(
        for size: NSSize,
        in screenFrame: NSRect,
        yOffset: CGFloat,
        anchorX: CGFloat? = nil,
        alignTopToWindowServer: Bool = false
    ) -> NSRect {
        let resolvedAnchorX = anchorX ?? screenFrame.midX
        let proposedTop = screenFrame.maxY - yOffset
        let top = alignTopToWindowServer ? proposedTop.rounded(.up) : proposedTop
        return NSRect(
            x: resolvedAnchorX - size.width / 2,
            y: top - size.height,
            width: size.width,
            height: size.height
        )
    }

    static func acceptsAnimationCompletion(
        completedAnimationID: Int,
        currentAnimationID: Int,
        targetMode: IslandMode,
        currentMode: IslandMode
    ) -> Bool {
        completedAnimationID == currentAnimationID && targetMode == currentMode
    }
}

struct IslandAnimationCompletionGate {
    private(set) var currentAnimationID = 0
    private var completedAnimationID: Int?

    mutating func beginAnimation() -> Int {
        currentAnimationID &+= 1
        completedAnimationID = nil
        return currentAnimationID
    }

    mutating func claimCompletion(
        animationID: Int,
        targetMode: IslandMode,
        currentMode: IslandMode
    ) -> Bool {
        guard completedAnimationID != animationID,
              IslandWindowLayout.acceptsAnimationCompletion(
                completedAnimationID: animationID,
                currentAnimationID: currentAnimationID,
                targetMode: targetMode,
                currentMode: currentMode
              ) else {
            return false
        }
        completedAnimationID = animationID
        return true
    }
}

struct IslandInteractionRegions: Equatable {
    let header: NSRect
    let body: NSRect?
    let bridge: NSRect?

    static func make(
        panelFrame: NSRect,
        mode: IslandMode,
        headerWidth: CGFloat,
        topBandHeight: CGFloat,
        expandedBodyHeight: CGFloat,
        expandedPanelTopGap: CGFloat
    ) -> IslandInteractionRegions {
        let header = NSRect(
            x: panelFrame.midX - headerWidth / 2,
            y: panelFrame.maxY - topBandHeight,
            width: headerWidth,
            height: topBandHeight
        )
        guard mode == .expanded else {
            return IslandInteractionRegions(header: header, body: nil, bridge: nil)
        }

        let body = NSRect(
            x: panelFrame.minX,
            y: panelFrame.minY,
            width: panelFrame.width,
            height: expandedBodyHeight
        )
        let bridgeHeight = max(
            0,
            min(expandedPanelTopGap, header.minY - body.maxY)
        )
        let bridge = bridgeHeight > 0
            ? NSRect(
                x: header.minX,
                y: body.maxY,
                width: header.width,
                height: bridgeHeight
            )
            : nil
        return IslandInteractionRegions(header: header, body: body, bridge: bridge)
    }

    func contains(_ point: CGPoint, tolerance: CGFloat = 0) -> Bool {
        let expandedHeader = header.insetBy(dx: -tolerance, dy: -tolerance)
        let expandedBody = body?.insetBy(dx: -tolerance, dy: -tolerance)
        let expandedBridge = bridge?.insetBy(dx: -tolerance, dy: -tolerance)
        return expandedHeader.contains(point)
            || expandedBody?.contains(point) == true
            || expandedBridge?.contains(point) == true
    }
}

enum IslandMotion {
    static func duration(for mode: IslandMode) -> TimeInterval {
        mode == .expanded ? 0.24 : 0.18
    }

    static func frameDuration(
        for mode: IslandMode,
        reduceMotion: Bool
    ) -> TimeInterval {
        reduceMotion ? 0 : duration(for: mode)
    }

    static func timingControlPoints(for mode: IslandMode) -> (Double, Double, Double, Double) {
        mode == .expanded ? (0.20, 0.85, 0.25, 1.0) : (0.40, 0.0, 0.20, 1.0)
    }

    static func geometryAnimation(
        for mode: IslandMode,
        reduceMotion: Bool
    ) -> Animation? {
        guard !reduceMotion else { return nil }
        let points = timingControlPoints(for: mode)
        return .timingCurve(points.0, points.1, points.2, points.3, duration: duration(for: mode))
    }

    static func featureContentAnimation(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? 0.04 : 0.10)
    }
}

enum ExpandedMusicLayout {
    // The lyric mode gives the reading surface the larger share of the
    // expanded island. Controls stay in a stable left rail so the lyric
    // viewport can grow without reflowing the playback buttons.
    static let controlContentWidth: CGFloat = 204
    static let controlOnlyContentWidth: CGFloat = controlContentWidth + controlToLyricSpacing + detailsWidth
    static let controlSurfacePadding: CGFloat = 0
    // The lyric state is intentionally wider than the control-only state.
    // This keeps the cover/controls rail stable and gives the lyric viewport
    // enough room to scroll long lines without shrinking the type.
    static let contentWidth: CGFloat = controlContentWidth + controlToLyricSpacing + lyricColumnWidth
    static let artworkSize: CGFloat = 76
    static let artworkToDetailsSpacing: CGFloat = 10
    static let detailsWidth: CGFloat = 248
    static let lyricColumnWidth: CGFloat = 446
    static let controlToLyricSpacing: CGFloat = 12
    static let timelineWidth: CGFloat = 164
    static let timelineToTimeSpacing: CGFloat = 10
    static let timeWidth: CGFloat = 74
    /// Leading inset of lyric text and the progress bar: accent bar (3) plus
    /// its gap (9), so text and timeline start on one vertical line.
    static let lyricTextInset: CGFloat = 12
    static let lyricTimelineWidth: CGFloat =
        lyricColumnWidth - lyricTextInset - timelineToTimeSpacing - timeWidth
    static let controlRailWidth: CGFloat = timelineWidth
    static let modeButtonsWidth: CGFloat = 56
    static let titleToModeButtonsSpacing: CGFloat = 12
    static let titleWidth: CGFloat = detailsWidth
        - modeButtonsWidth
        - titleToModeButtonsSpacing

    static var controlColumnWidth: CGFloat {
        controlContentWidth + controlSurfacePadding * 2
    }
}

enum IslandDisplayRefreshPolicy {
    static let stabilizationDelaysNanoseconds: [UInt64] = [
        150_000_000,
        500_000_000
    ]
}
