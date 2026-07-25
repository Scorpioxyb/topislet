#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

private let ownerName = "顶屿"
private let hoverPersistenceDuration: TimeInterval = 12
private let maximumHoverResponseDuration: TimeInterval = 0.12
private let maximumHoverExitStartDuration: TimeInterval = 0.65
private let sampleInterval: TimeInterval = 0.005

private struct WindowSample {
    let frame: CGRect
    let windowCount: Int
    let pointerLocation: CGPoint
}

private enum VerificationError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message):
            return message
        }
    }
}

private func appWindows() -> [CGRect] {
    let rows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] ?? []
    return rows.compactMap { row in
        guard row[kCGWindowOwnerName as String] as? String == ownerName,
              let bounds = row[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else {
            return nil
        }
        return frame
    }
}

private func currentSample() throws -> WindowSample {
    let windows = appWindows()
    guard let frame = windows.first else {
        throw VerificationError.failed("顶屿窗口未运行")
    }
    return WindowSample(
        frame: frame,
        windowCount: windows.count,
        pointerLocation: CGEvent(source: nil)?.location ?? .zero
    )
}

private func postMouseMove(to point: CGPoint) {
    CGWarpMouseCursorPosition(point)
    let event = CGEvent(
        mouseEventSource: nil,
        mouseType: .mouseMoved,
        mouseCursorPosition: point,
        mouseButton: .left
    )
    event?.post(tap: .cghidEventTap)
}

private func sampleFrames(
    duration: TimeInterval,
    keepingPointerAt pinnedPointer: CGPoint? = nil
) throws -> [WindowSample] {
    let startedAt = Date()
    var samples: [WindowSample] = []
    while Date().timeIntervalSince(startedAt) < duration {
        var sample = try currentSample()
        if let pinnedPointer,
           hypot(
               sample.pointerLocation.x - pinnedPointer.x,
               sample.pointerLocation.y - pinnedPointer.y
           ) > 1 {
            postMouseMove(to: pinnedPointer)
            usleep(1_000)
            sample = try currentSample()
        }
        samples.append(sample)
        usleep(useconds_t(sampleInterval * 1_000_000))
    }
    return samples
}

private func waitForWindowShrink(
    from initialSize: CGSize,
    timeout: TimeInterval,
    keepingPointerAt pinnedPointer: CGPoint
) throws -> (sample: WindowSample, elapsed: TimeInterval) {
    let startedAt = Date()
    while Date().timeIntervalSince(startedAt) < timeout {
        var sample = try currentSample()
        if hypot(
            sample.pointerLocation.x - pinnedPointer.x,
            sample.pointerLocation.y - pinnedPointer.y
        ) > 1 {
            postMouseMove(to: pinnedPointer)
            usleep(1_000)
            sample = try currentSample()
        }
        if sample.frame.width < initialSize.width - 0.75
            && sample.frame.height < initialSize.height - 0.75 {
            return (sample, Date().timeIntervalSince(startedAt))
        }
        usleep(useconds_t(sampleInterval * 1_000_000))
    }
    throw VerificationError.failed(
        "移出后 \(Int(timeout * 1_000))ms 内未进入收回动画"
    )
}

private func verifyAnchoring(
    _ samples: [WindowSample],
    expectedCenterX: CGFloat,
    expectedTop: CGFloat
) throws {
    guard samples.allSatisfy({ $0.windowCount == 1 }) else {
        throw VerificationError.failed("动画期间检测到多个顶屿窗口")
    }
    let maximumCenterError = samples.map {
        abs($0.frame.midX - expectedCenterX)
    }.max() ?? .infinity
    let maximumTopError = samples.map {
        abs($0.frame.minY - expectedTop)
    }.max() ?? .infinity
    guard maximumCenterError <= 0.75 else {
        let centers = samples.map(\.frame.midX)
        let minimumCenter = centers.min() ?? .nan
        let maximumCenter = centers.max() ?? .nan
        let worstSample = samples.max { lhs, rhs in
            abs(lhs.frame.midX - expectedCenterX) < abs(rhs.frame.midX - expectedCenterX)
        }
        let worstSize = worstSample?.frame.size ?? .zero
        throw VerificationError.failed(
            "动画水平中心漂移 \(String(format: "%.2f", maximumCenterError))pt；"
                + "预期 \(String(format: "%.2f", expectedCenterX))，"
                + "范围 \(String(format: "%.2f", minimumCenter))..."
                + "\(String(format: "%.2f", maximumCenter))，"
                + "最差尺寸 \(Int(worstSize.width))x\(Int(worstSize.height))"
        )
    }
    guard maximumTopError <= 0.75 else {
        throw VerificationError.failed(
            "动画顶边漂移 \(String(format: "%.2f", maximumTopError))pt"
        )
    }
}

private func verifyWindowSizeInterpolation(
    _ samples: [WindowSample],
    from startSize: CGSize,
    to endSize: CGSize
) throws {
    let minimumWidth = min(startSize.width, endSize.width) - 0.75
    let maximumWidth = max(startSize.width, endSize.width) + 0.75
    let minimumHeight = min(startSize.height, endSize.height) - 0.75
    let maximumHeight = max(startSize.height, endSize.height) + 0.75
    guard samples.allSatisfy({ sample in
        minimumWidth...maximumWidth ~= sample.frame.width
            && minimumHeight...maximumHeight ~= sample.frame.height
    }) else {
        throw VerificationError.failed("窗口动画尺寸越过起点或终点")
    }

    let hasIntermediateFrame = samples.contains { sample in
        let differsFromStart = abs(sample.frame.width - startSize.width) > 0.75
            || abs(sample.frame.height - startSize.height) > 0.75
        let differsFromEnd = abs(sample.frame.width - endSize.width) > 0.75
            || abs(sample.frame.height - endSize.height) > 0.75
        return differsFromStart && differsFromEnd
    }
    guard hasIntermediateFrame else {
        throw VerificationError.failed("窗口没有连续插值，仍在瞬时切换尺寸")
    }
}

private func verifyImmediateWindowSizeTransition(
    _ samples: [WindowSample],
    from startSize: CGSize,
    to endSize: CGSize
) throws {
    let hasUnexpectedIntermediateFrame = samples.contains { sample in
        let matchesStart = abs(sample.frame.width - startSize.width) <= 0.75
            && abs(sample.frame.height - startSize.height) <= 0.75
        let matchesEnd = abs(sample.frame.width - endSize.width) <= 0.75
            && abs(sample.frame.height - endSize.height) <= 0.75
        return !matchesStart && !matchesEnd
    }
    guard !hasUnexpectedIntermediateFrame else {
        throw VerificationError.failed(
            "开启减少动态效果后仍检测到窗口几何插值"
        )
    }
}

private func verifyStableWindowSize(
    _ samples: [WindowSample],
    expectedSize: CGSize
) throws {
    guard samples.allSatisfy({ sample in
        abs(sample.frame.width - expectedSize.width) <= 0.75
            && abs(sample.frame.height - expectedSize.height) <= 0.75
    }) else {
        let firstMismatchIndex = samples.firstIndex { sample in
            abs(sample.frame.width - expectedSize.width) > 0.75
                || abs(sample.frame.height - expectedSize.height) > 0.75
        } ?? 0
        let firstMismatch = samples[firstMismatchIndex].frame.size
        let mismatchPointer = samples[firstMismatchIndex].pointerLocation
        let widths = samples.map(\.frame.width)
        let heights = samples.map(\.frame.height)
        throw VerificationError.failed(
            "悬停保持期间窗口尺寸发生变化；"
                + "首次 \(Int(Double(firstMismatchIndex) * sampleInterval * 1_000))ms "
                + "尺寸 \(Int(firstMismatch.width))x\(Int(firstMismatch.height))，"
                + "鼠标 \(Int(mismatchPointer.x)),\(Int(mismatchPointer.y))，"
                + "范围 \(Int(widths.min() ?? 0))...\(Int(widths.max() ?? 0))x"
                + "\(Int(heights.min() ?? 0))...\(Int(heights.max() ?? 0))"
        )
    }
}

private func verifyWindowSizesStayBounded(
    _ samples: [WindowSample],
    between firstSize: CGSize,
    and secondSize: CGSize
) throws {
    let minimumWidth = min(firstSize.width, secondSize.width) - 0.75
    let maximumWidth = max(firstSize.width, secondSize.width) + 0.75
    let minimumHeight = min(firstSize.height, secondSize.height) - 0.75
    let maximumHeight = max(firstSize.height, secondSize.height) + 0.75
    guard samples.allSatisfy({ sample in
        minimumWidth...maximumWidth ~= sample.frame.width
            && minimumHeight...maximumHeight ~= sample.frame.height
    }) else {
        throw VerificationError.failed("反向动画尺寸越过紧凑态或展开态边界")
    }
}

private func verifyHoverResponse(
    _ samples: [WindowSample],
    initialSize: CGSize
) throws -> TimeInterval {
    guard let firstChangedIndex = samples.firstIndex(where: { sample in
        abs(sample.frame.width - initialSize.width) > 0.75
            || abs(sample.frame.height - initialSize.height) > 0.75
    }) else {
        throw VerificationError.failed("悬停后岛没有开始展开")
    }
    let responseDuration = Double(firstChangedIndex) * sampleInterval
    guard responseDuration <= maximumHoverResponseDuration else {
        throw VerificationError.failed(
            "悬停展开响应过慢：\(Int(responseDuration * 1_000))ms"
        )
    }
    return responseDuration
}

private func run() throws {
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let originalPointer = CGEvent(source: nil)?.location ?? .zero
    CGAssociateMouseAndMouseCursorPosition(0)
    defer {
        postMouseMove(to: originalPointer)
        CGWarpMouseCursorPosition(originalPointer)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    var initial = try currentSample()
    let outsidePoint = CGPoint(
        x: initial.frame.midX,
        y: initial.frame.maxY + 240
    )
    postMouseMove(to: outsidePoint)
    usleep(750_000)
    initial = try currentSample()

    let expectedCenterX = initial.frame.midX
    let expectedTop = initial.frame.minY
    let insidePoint = CGPoint(
        x: initial.frame.midX,
        y: initial.frame.minY + min(16, initial.frame.height / 2)
    )
    postMouseMove(to: insidePoint)
    let expansion = try sampleFrames(
        duration: 0.5,
        keepingPointerAt: insidePoint
    )
    let expanded = try currentSample()

    guard expanded.frame.width > initial.frame.width,
          expanded.frame.height > initial.frame.height else {
        throw VerificationError.failed("岛没有展开；请先播放已适配的音乐后重试")
    }
    try verifyAnchoring(
        expansion,
        expectedCenterX: expectedCenterX,
        expectedTop: expectedTop
    )
    let hoverResponseDuration = try verifyHoverResponse(
        expansion,
        initialSize: initial.frame.size
    )
    if reduceMotion {
        try verifyImmediateWindowSizeTransition(
            expansion,
            from: initial.frame.size,
            to: expanded.frame.size
        )
    } else {
        try verifyWindowSizeInterpolation(
            expansion,
            from: initial.frame.size,
            to: expanded.frame.size
        )
    }

    let hoverPersistence = try sampleFrames(
        duration: hoverPersistenceDuration,
        keepingPointerAt: insidePoint
    )
    try verifyAnchoring(
        hoverPersistence,
        expectedCenterX: expectedCenterX,
        expectedTop: expectedTop
    )
    try verifyStableWindowSize(
        hoverPersistence,
        expectedSize: expanded.frame.size
    )

    postMouseMove(to: outsidePoint)
    let (reversalStart, hoverExitStartDuration) = try waitForWindowShrink(
        from: expanded.frame.size,
        timeout: maximumHoverExitStartDuration,
        keepingPointerAt: outsidePoint
    )
    guard reversalStart.frame.width < expanded.frame.width - 0.75,
          reversalStart.frame.height < expanded.frame.height - 0.75 else {
        throw VerificationError.failed("未进入收回动画，无法验证反向切换")
    }
    postMouseMove(to: insidePoint)
    let reversal = try sampleFrames(
        duration: 0.5,
        keepingPointerAt: insidePoint
    )
    let reexpanded = try currentSample()
    try verifyAnchoring(
        reversal,
        expectedCenterX: expectedCenterX,
        expectedTop: expectedTop
    )
    try verifyWindowSizesStayBounded(
        reversal,
        between: initial.frame.size,
        and: expanded.frame.size
    )
    guard abs(reexpanded.frame.width - expanded.frame.width) <= 0.75,
          abs(reexpanded.frame.height - expanded.frame.height) <= 0.75 else {
        throw VerificationError.failed("收回途中重新进入后没有恢复展开态")
    }

    postMouseMove(to: outsidePoint)
    let collapse = try sampleFrames(
        duration: 0.75,
        keepingPointerAt: outsidePoint
    )
    let collapsed = try currentSample()
    try verifyAnchoring(
        collapse,
        expectedCenterX: expectedCenterX,
        expectedTop: expectedTop
    )
    if reduceMotion {
        try verifyImmediateWindowSizeTransition(
            collapse,
            from: expanded.frame.size,
            to: collapsed.frame.size
        )
    } else {
        try verifyWindowSizeInterpolation(
            collapse,
            from: expanded.frame.size,
            to: collapsed.frame.size
        )
    }

    guard abs(collapsed.frame.width - initial.frame.width) <= 0.75,
          abs(collapsed.frame.height - initial.frame.height) <= 0.75 else {
        throw VerificationError.failed("收回后窗口尺寸没有恢复")
    }

    print("顶屿单窗口动画验证通过")
    print("减少动态效果: \(reduceMotion ? "开启" : "关闭")")
    print("窗口数量: 1")
    print("紧凑尺寸: \(Int(initial.frame.width))x\(Int(initial.frame.height))")
    print("展开尺寸: \(Int(expanded.frame.width))x\(Int(expanded.frame.height))")
    print("悬停响应: \(Int(hoverResponseDuration * 1_000))ms")
    print("移出收回响应: \(Int(hoverExitStartDuration * 1_000))ms")
    print("悬停保持: \(String(format: "%.1f", hoverPersistenceDuration))s")
    print("反向切换: 收回途中重新进入通过")
}

do {
    try run()
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
