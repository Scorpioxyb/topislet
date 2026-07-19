import AppKit

struct IslandDisplayGeometry: Equatable {
    static let syntheticNotchWidth: CGFloat = 160
    static let syntheticTopBandHeight: CGFloat = 32

    let screenFrame: NSRect
    let backingScaleFactor: CGFloat
    let safeAreaTop: CGFloat
    let cameraHousingFrame: NSRect?
    let islandAnchorX: CGFloat
    let notchWidth: CGFloat
    let topBandHeight: CGFloat

    var hasCameraHousing: Bool {
        cameraHousingFrame != nil
    }

    static func resolve(
        screenFrame: NSRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftArea: NSRect?,
        auxiliaryTopRightArea: NSRect?,
        backingScaleFactor: CGFloat,
        notchHeightAdjustment: CGFloat
    ) -> IslandDisplayGeometry {
        let scale = max(backingScaleFactor, 1)
        let cameraHousingFrame = validatedCameraHousingFrame(
            screenFrame: screenFrame,
            safeAreaTop: safeAreaTop,
            auxiliaryTopLeftArea: auxiliaryTopLeftArea,
            auxiliaryTopRightArea: auxiliaryTopRightArea,
            scale: scale
        )
        let systemTopHeight: CGFloat
        if let cameraHousingFrame {
            systemTopHeight = max(safeAreaTop, cameraHousingFrame.height)
        } else {
            systemTopHeight = max(safeAreaTop, syntheticTopBandHeight)
        }
        let adjustedTopHeight = min(max(systemTopHeight + notchHeightAdjustment, 30), 52)
        let pixelAlignedTopHeight = ceil(adjustedTopHeight * scale) / scale

        return IslandDisplayGeometry(
            screenFrame: screenFrame,
            backingScaleFactor: scale,
            safeAreaTop: safeAreaTop,
            cameraHousingFrame: cameraHousingFrame,
            islandAnchorX: cameraHousingFrame?.midX ?? screenFrame.midX,
            notchWidth: cameraHousingFrame?.width ?? syntheticNotchWidth,
            topBandHeight: pixelAlignedTopHeight
        )
    }

    private static func validatedCameraHousingFrame(
        screenFrame: NSRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftArea: NSRect?,
        auxiliaryTopRightArea: NSRect?,
        scale: CGFloat
    ) -> NSRect? {
        guard let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea,
              !left.isEmpty,
              !right.isEmpty else {
            return nil
        }

        let tolerance = max(2 / scale, 0.5)
        let gapWidth = right.minX - left.maxX
        let maximumPlausibleWidth = min(360, screenFrame.width * 0.35)
        let topHeight = max(safeAreaTop, left.height, right.height)
        guard gapWidth >= 96,
              gapWidth <= maximumPlausibleWidth,
              topHeight >= 20,
              topHeight <= 64,
              abs(left.maxY - screenFrame.maxY) <= tolerance,
              abs(right.maxY - screenFrame.maxY) <= tolerance,
              left.minX >= screenFrame.minX - tolerance,
              right.maxX <= screenFrame.maxX + tolerance,
              left.maxX <= screenFrame.midX + tolerance,
              right.minX >= screenFrame.midX - tolerance else {
            return nil
        }

        return NSRect(
            x: left.maxX,
            y: screenFrame.maxY - topHeight,
            width: gapWidth,
            height: topHeight
        )
    }
}
