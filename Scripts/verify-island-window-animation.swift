#!/usr/bin/env swift

import CoreGraphics
import Foundation

private let ownerName = "顶屿"
private let hoverPersistenceDuration: TimeInterval = 12
private let maximumHoverResponseDuration: TimeInterval = 0.12

private struct WindowSample {
    let frame: CGRect
    let windowCount: Int
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
    return WindowSample(frame: frame, windowCount: windows.count)
}

private func postMouseMove(to point: CGPoint) {
    CGWarpMouseCursorPosition(point)
    CGAssociateMouseAndMouseCursorPosition(1)
    let event = CGEvent(
        mouseEventSource: nil,
        mouseType: .mouseMoved,
        mouseCursorPosition: point,
        mouseButton: .left
    )
    event?.post(tap: .cghidEventTap)
}

private func sampleFrames(duration: TimeInterval) throws -> [WindowSample] {
    let startedAt = Date()
    var samples: [WindowSample] = []
    while Date().timeIntervalSince(startedAt) < duration {
        samples.append(try currentSample())
        usleep(5_000)
    }
    return samples
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
        throw VerificationError.failed(
            "动画水平中心漂移 \(String(format: "%.2f", maximumCenterError))pt"
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

private func verifyStableWindowSize(
    _ samples: [WindowSample],
    expectedSize: CGSize
) throws {
    guard samples.allSatisfy({ sample in
        abs(sample.frame.width - expectedSize.width) <= 0.75
            && abs(sample.frame.height - expectedSize.height) <= 0.75
    }) else {
        throw VerificationError.failed("悬停保持期间窗口尺寸发生变化")
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
    let responseDuration = Double(firstChangedIndex) * 0.005
    guard responseDuration <= maximumHoverResponseDuration else {
        throw VerificationError.failed(
            "悬停展开响应过慢：\(Int(responseDuration * 1_000))ms"
        )
    }
    return responseDuration
}

private func run() throws {
    let originalPointer = CGEvent(source: nil)?.location ?? .zero
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
    let expansion = try sampleFrames(duration: 0.5)
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
    try verifyWindowSizeInterpolation(
        expansion,
        from: initial.frame.size,
        to: expanded.frame.size
    )

    let hoverPersistence = try sampleFrames(duration: hoverPersistenceDuration)
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
    let collapse = try sampleFrames(duration: 0.75)
    let collapsed = try currentSample()
    try verifyAnchoring(
        collapse,
        expectedCenterX: expectedCenterX,
        expectedTop: expectedTop
    )
    try verifyWindowSizeInterpolation(
        collapse,
        from: expanded.frame.size,
        to: collapsed.frame.size
    )

    guard abs(collapsed.frame.width - initial.frame.width) <= 0.75,
          abs(collapsed.frame.height - initial.frame.height) <= 0.75 else {
        throw VerificationError.failed("收回后窗口尺寸没有恢复")
    }

    print("顶屿单窗口动画验证通过")
    print("窗口数量: 1")
    print("紧凑尺寸: \(Int(initial.frame.width))x\(Int(initial.frame.height))")
    print("展开尺寸: \(Int(expanded.frame.width))x\(Int(expanded.frame.height))")
    print("悬停响应: \(Int(hoverResponseDuration * 1_000))ms")
    print("悬停保持: \(String(format: "%.1f", hoverPersistenceDuration))s")
}

do {
    try run()
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
