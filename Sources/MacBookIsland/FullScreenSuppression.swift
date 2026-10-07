import AppKit
import CoreGraphics
import Foundation

enum IslandFullScreenSuppressionPolicy {
    static func shouldSuppress(
        frontmostIsTopIslet _: Bool,
        hasCoveringWindow: Bool
    ) -> Bool {
        // A settings/menu activation must not reveal the island over a player.
        // The detector already excludes our own windows; this only suppresses
        // the island panel and leaves the settings window usable.
        hasCoveringWindow
    }

    static func coversDisplay(
        windowFrame: CGRect,
        displayFrame: CGRect,
        coverage: CGFloat = 0.97
    ) -> Bool {
        guard displayFrame.width > 0, displayFrame.height > 0 else { return false }
        let intersection = windowFrame.intersection(displayFrame)
        guard !intersection.isNull else { return false }
        return intersection.width >= displayFrame.width * coverage
            && intersection.height >= displayFrame.height * coverage
    }

    /// WindowServer uses a top-left origin; AppKit uses a bottom-left origin.
    static func windowServerFrame(
        for appKitFrame: CGRect,
        primaryDisplayHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: appKitFrame.minX,
            y: primaryDisplayHeight - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }

    /// Fullscreen players can leave the menu bar/notch strip visible, but
    /// must cover the Dock area that ordinary maximized windows leave free.
    static func coversPlayerDisplay(
        windowFrame: CGRect,
        displayFrame: CGRect,
        menuBarHeight: CGFloat,
        edgeTolerance: CGFloat = 1
    ) -> Bool {
        let topInset = max(0, min(menuBarHeight, displayFrame.height))
        let contentFrame = CGRect(
            x: displayFrame.minX,
            y: displayFrame.minY + topInset,
            width: displayFrame.width,
            height: displayFrame.height - topInset
        )
        return coversDisplay(windowFrame: windowFrame, displayFrame: contentFrame)
            && windowFrame.minX <= contentFrame.minX + edgeTolerance
            && windowFrame.maxX >= contentFrame.maxX - edgeTolerance
            && windowFrame.minY <= contentFrame.minY + edgeTolerance
            && windowFrame.maxY >= contentFrame.maxY - edgeTolerance
    }
}

enum IslandPanelCollectionPolicy {
    static let behavior: NSWindow.CollectionBehavior = [
        .stationary,
        .ignoresCycle
    ]
}

enum IslandFullScreenWindowDetector {
    static func hasCoveringWindow(
        on screen: NSScreen,
        excludingProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
    ) -> Bool {
        guard let rawWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        let displayFrame = IslandFullScreenSuppressionPolicy.windowServerFrame(
            for: screen.frame,
            primaryDisplayHeight: NSScreen.screens.first?.frame.height ?? screen.frame.height
        )
        let menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)

        return rawWindows.contains { window in
            guard let ownerProcessIdentifier = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerProcessIdentifier != excludingProcessIdentifier,
                  let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0,
                  let isOnScreen = window[kCGWindowIsOnscreen as String] as? Bool,
                  isOnScreen,
                  let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
                  alpha > 0.01,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let windowFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else {
                return false
            }

            return IslandFullScreenSuppressionPolicy.coversDisplay(
                windowFrame: windowFrame,
                displayFrame: displayFrame
            ) || IslandFullScreenSuppressionPolicy.coversPlayerDisplay(
                windowFrame: windowFrame,
                displayFrame: displayFrame,
                menuBarHeight: menuBarHeight
            )
        }
    }
}
