#!/usr/bin/env swift

import CoreGraphics
import Darwin
import Foundation

private struct Configuration {
    let pid: Int32
    let duration: TimeInterval
    let interval: TimeInterval
    let outputURL: URL

    static func parse(arguments: [String]) throws -> Configuration {
        var pid: Int32?
        var duration: TimeInterval = 7_200
        var interval: TimeInterval = 5
        var outputPath = ".build/qa/topislet-long-run-summary.json"
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            guard index + 1 < arguments.count else {
                throw MonitorError.invalidArgument("\(argument) 缺少值")
            }
            let value = arguments[index + 1]
            switch argument {
            case "--pid":
                pid = Int32(value)
            case "--duration":
                duration = TimeInterval(value) ?? 0
            case "--interval":
                interval = TimeInterval(value) ?? 0
            case "--output":
                outputPath = value
            default:
                throw MonitorError.invalidArgument("未知参数：\(argument)")
            }
            index += 2
        }

        guard let pid, pid > 0 else {
            throw MonitorError.invalidArgument("必须提供有效的 --pid")
        }
        guard duration > 0 else {
            throw MonitorError.invalidArgument("--duration 必须大于 0")
        }
        guard interval >= 1 else {
            throw MonitorError.invalidArgument("--interval 必须至少为 1 秒")
        }

        let outputURL: URL
        if outputPath.hasPrefix("/") {
            outputURL = URL(fileURLWithPath: outputPath)
        } else {
            outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(outputPath)
        }
        return Configuration(
            pid: pid,
            duration: duration,
            interval: interval,
            outputURL: outputURL
        )
    }
}

private enum MonitorError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case processUnavailable(Int32)

    var description: String {
        switch self {
        case let .invalidArgument(message):
            return message
        case let .processUnavailable(pid):
            return "无法读取目标进程 PID \(pid)"
        }
    }
}

private struct MonitorSummary: Codable {
    let schemaVersion: Int
    let pid: Int32
    let startedAt: String
    var updatedAt: String
    var completedAt: String?
    let expectedDurationSeconds: Double
    let sampleIntervalSeconds: Double
    var observedDurationSeconds: Double
    var completed: Bool
    var processAlive: Bool
    var sampleCount: Int
    var cpuSampleCount: Int
    var averageCPUPercent: Double?
    var p95CPUPercent: Double?
    var maximumCPUPercent: Double?
    var maximumSustainedCPUAbove5Seconds: Double
    var baselineRSSBytes: UInt64?
    var finalRSSBytes: UInt64?
    var minimumRSSBytes: UInt64?
    var maximumRSSBytes: UInt64?
    var finalRSSGrowthPercent: Double?
    var maximumRSSGrowthPercent: Double?
    var baselineThreadCount: Int?
    var finalThreadCount: Int?
    var minimumThreadCount: Int?
    var maximumThreadCount: Int?
    var maximumSustainedThreadGrowthSeconds: Double
    var baselineChildCount: Int?
    var finalChildCount: Int?
    var minimumChildCount: Int?
    var maximumChildCount: Int?
    var maximumSustainedChildGrowthSeconds: Double
    var baselineWindowCount: Int?
    var finalWindowCount: Int?
    var minimumWindowCount: Int?
    var maximumWindowCount: Int?
    var violations: [String]
}

private struct TaskSnapshot {
    let totalCPUTimeNanoseconds: UInt64
    let residentBytes: UInt64
    let threadCount: Int
}

private let iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private func timestamp(_ date: Date) -> String {
    iso8601Formatter.string(from: date)
}

private func taskSnapshot(pid: Int32) -> TaskSnapshot? {
    var info = proc_taskinfo()
    let expectedSize = Int32(MemoryLayout<proc_taskinfo>.size)
    let result = proc_pidinfo(
        pid,
        PROC_PIDTASKINFO,
        0,
        &info,
        expectedSize
    )
    guard result == expectedSize else { return nil }
    return TaskSnapshot(
        totalCPUTimeNanoseconds: info.pti_total_user + info.pti_total_system,
        residentBytes: info.pti_resident_size,
        threadCount: Int(info.pti_threadnum)
    )
}

private func directChildPIDs(pid: Int32) -> [pid_t] {
    var children = [pid_t](repeating: 0, count: 128)
    let count = children.withUnsafeMutableBytes { buffer in
        proc_listchildpids(pid, buffer.baseAddress, Int32(buffer.count))
    }
    guard count > 0 else { return [] }
    return Array(children.prefix(min(Int(count), children.count))).sorted()
}

private func onScreenWindowCount(pid: Int32) -> Int {
    let rows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] ?? []
    return rows.reduce(into: 0) { count, row in
        let ownerPID = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        if ownerPID == pid {
            count += 1
        }
    }
}

private func percentile(_ values: [Double], fraction: Double) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let rawIndex = Int(ceil(Double(sorted.count) * fraction)) - 1
    return sorted[min(max(rawIndex, 0), sorted.count - 1)]
}

private func growthPercent(current: UInt64?, baseline: UInt64?) -> Double? {
    guard let current, let baseline, baseline > 0 else { return nil }
    return (Double(current) - Double(baseline)) / Double(baseline) * 100
}

private func writeSummary(_ summary: MonitorSummary, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(summary)
    try data.write(to: url, options: .atomic)
}

private func csvLine(
    date: Date,
    elapsed: TimeInterval,
    cpuPercent: Double?,
    snapshot: TaskSnapshot,
    children: [pid_t],
    windowCount: Int
) -> String {
    [
        timestamp(date),
        String(format: "%.3f", elapsed),
        cpuPercent.map { String(format: "%.4f", $0) } ?? "",
        String(snapshot.residentBytes),
        String(snapshot.threadCount),
        String(children.count),
        children.map(String.init).joined(separator: "|"),
        String(windowCount),
    ].joined(separator: ",") + "\n"
}

private func append(_ text: String, to handle: FileHandle) throws {
    guard let data = text.data(using: .utf8) else { return }
    try handle.write(contentsOf: data)
}

private func run(configuration: Configuration) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(
        at: configuration.outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let samplesURL = configuration.outputURL
        .deletingPathExtension()
        .appendingPathExtension("csv")
    fileManager.createFile(atPath: samplesURL.path, contents: nil)
    let samplesHandle = try FileHandle(forWritingTo: samplesURL)
    defer { try? samplesHandle.close() }
    try append(
        "timestamp,elapsed_seconds,cpu_percent,rss_bytes,thread_count,child_count,child_pids,window_count\n",
        to: samplesHandle
    )

    let startedAt = Date()
    let deadline = startedAt.addingTimeInterval(configuration.duration)
    guard let initialSnapshot = taskSnapshot(pid: configuration.pid) else {
        throw MonitorError.processUnavailable(configuration.pid)
    }
    let initialChildren = directChildPIDs(pid: configuration.pid)
    let initialWindowCount = onScreenWindowCount(pid: configuration.pid)

    var summary = MonitorSummary(
        schemaVersion: 1,
        pid: configuration.pid,
        startedAt: timestamp(startedAt),
        updatedAt: timestamp(startedAt),
        completedAt: nil,
        expectedDurationSeconds: configuration.duration,
        sampleIntervalSeconds: configuration.interval,
        observedDurationSeconds: 0,
        completed: false,
        processAlive: true,
        sampleCount: 0,
        cpuSampleCount: 0,
        averageCPUPercent: nil,
        p95CPUPercent: nil,
        maximumCPUPercent: nil,
        maximumSustainedCPUAbove5Seconds: 0,
        baselineRSSBytes: initialSnapshot.residentBytes,
        finalRSSBytes: initialSnapshot.residentBytes,
        minimumRSSBytes: initialSnapshot.residentBytes,
        maximumRSSBytes: initialSnapshot.residentBytes,
        finalRSSGrowthPercent: 0,
        maximumRSSGrowthPercent: 0,
        baselineThreadCount: initialSnapshot.threadCount,
        finalThreadCount: initialSnapshot.threadCount,
        minimumThreadCount: initialSnapshot.threadCount,
        maximumThreadCount: initialSnapshot.threadCount,
        maximumSustainedThreadGrowthSeconds: 0,
        baselineChildCount: initialChildren.count,
        finalChildCount: initialChildren.count,
        minimumChildCount: initialChildren.count,
        maximumChildCount: initialChildren.count,
        maximumSustainedChildGrowthSeconds: 0,
        baselineWindowCount: initialWindowCount,
        finalWindowCount: initialWindowCount,
        minimumWindowCount: initialWindowCount,
        maximumWindowCount: initialWindowCount,
        violations: []
    )

    var previousSnapshot = initialSnapshot
    var previousDate = startedAt
    var cpuSamples: [Double] = []
    var currentHighCPUSeconds: TimeInterval = 0
    var currentThreadGrowthSeconds: TimeInterval = 0
    var currentChildGrowthSeconds: TimeInterval = 0

    while true {
        let sampleDate = Date()
        let elapsed = sampleDate.timeIntervalSince(startedAt)
        guard let snapshot = taskSnapshot(pid: configuration.pid) else {
            summary.processAlive = false
            summary.observedDurationSeconds = elapsed
            summary.updatedAt = timestamp(sampleDate)
            summary.violations.append("目标进程在长稳期间退出")
            break
        }

        let wallDelta = sampleDate.timeIntervalSince(previousDate)
        let taskDelta = snapshot.totalCPUTimeNanoseconds >= previousSnapshot.totalCPUTimeNanoseconds
            ? snapshot.totalCPUTimeNanoseconds - previousSnapshot.totalCPUTimeNanoseconds
            : 0
        let cpuPercent: Double?
        if summary.sampleCount == 0 || wallDelta <= 0 {
            cpuPercent = nil
        } else {
            cpuPercent = Double(taskDelta) / 1_000_000_000 / wallDelta * 100
        }
        let children = directChildPIDs(pid: configuration.pid)
        let windowCount = onScreenWindowCount(pid: configuration.pid)
        try append(
            csvLine(
                date: sampleDate,
                elapsed: elapsed,
                cpuPercent: cpuPercent,
                snapshot: snapshot,
                children: children,
                windowCount: windowCount
            ),
            to: samplesHandle
        )

        summary.sampleCount += 1
        summary.observedDurationSeconds = elapsed
        summary.updatedAt = timestamp(sampleDate)
        summary.finalRSSBytes = snapshot.residentBytes
        summary.minimumRSSBytes = min(summary.minimumRSSBytes ?? snapshot.residentBytes, snapshot.residentBytes)
        summary.maximumRSSBytes = max(summary.maximumRSSBytes ?? snapshot.residentBytes, snapshot.residentBytes)
        summary.finalRSSGrowthPercent = growthPercent(
            current: snapshot.residentBytes,
            baseline: summary.baselineRSSBytes
        )
        summary.maximumRSSGrowthPercent = growthPercent(
            current: summary.maximumRSSBytes,
            baseline: summary.baselineRSSBytes
        )
        summary.finalThreadCount = snapshot.threadCount
        summary.minimumThreadCount = min(summary.minimumThreadCount ?? snapshot.threadCount, snapshot.threadCount)
        summary.maximumThreadCount = max(summary.maximumThreadCount ?? snapshot.threadCount, snapshot.threadCount)
        summary.finalChildCount = children.count
        summary.minimumChildCount = min(summary.minimumChildCount ?? children.count, children.count)
        summary.maximumChildCount = max(summary.maximumChildCount ?? children.count, children.count)
        summary.finalWindowCount = windowCount
        summary.minimumWindowCount = min(summary.minimumWindowCount ?? windowCount, windowCount)
        summary.maximumWindowCount = max(summary.maximumWindowCount ?? windowCount, windowCount)

        if let cpuPercent {
            cpuSamples.append(cpuPercent)
            summary.cpuSampleCount = cpuSamples.count
            summary.averageCPUPercent = cpuSamples.reduce(0, +) / Double(cpuSamples.count)
            summary.p95CPUPercent = percentile(cpuSamples, fraction: 0.95)
            summary.maximumCPUPercent = cpuSamples.max()
            if cpuPercent > 5 {
                currentHighCPUSeconds += wallDelta
                summary.maximumSustainedCPUAbove5Seconds = max(
                    summary.maximumSustainedCPUAbove5Seconds,
                    currentHighCPUSeconds
                )
            } else {
                currentHighCPUSeconds = 0
            }
        }
        if summary.sampleCount > 1,
           let baseline = summary.baselineThreadCount,
           snapshot.threadCount > baseline + 2 {
            currentThreadGrowthSeconds += wallDelta
            summary.maximumSustainedThreadGrowthSeconds = max(
                summary.maximumSustainedThreadGrowthSeconds,
                currentThreadGrowthSeconds
            )
        } else {
            currentThreadGrowthSeconds = 0
        }
        if summary.sampleCount > 1,
           let baseline = summary.baselineChildCount,
           children.count > baseline {
            currentChildGrowthSeconds += wallDelta
            summary.maximumSustainedChildGrowthSeconds = max(
                summary.maximumSustainedChildGrowthSeconds,
                currentChildGrowthSeconds
            )
        } else {
            currentChildGrowthSeconds = 0
        }

        try writeSummary(summary, to: configuration.outputURL)
        previousSnapshot = snapshot
        previousDate = sampleDate

        if sampleDate >= deadline { break }
        Thread.sleep(
            forTimeInterval: min(
                configuration.interval,
                max(0, deadline.timeIntervalSinceNow)
            )
        )
    }

    let finishedAt = Date()
    summary.observedDurationSeconds = finishedAt.timeIntervalSince(startedAt)
    summary.updatedAt = timestamp(finishedAt)
    summary.completedAt = timestamp(finishedAt)
    summary.completed = summary.processAlive

    if let growth = summary.finalRSSGrowthPercent, growth > 15 {
        summary.violations.append(
            String(format: "两小时 RSS 增长 %.2f%%，超过 15%% 门槛", growth)
        )
    }
    if summary.maximumSustainedCPUAbove5Seconds >= 30 {
        summary.violations.append("CPU 连续至少 30 秒高于 5%")
    }
    if summary.maximumSustainedThreadGrowthSeconds >= 60 {
        summary.violations.append("线程数连续至少 60 秒高于基线 2 个以上")
    }
    if summary.maximumSustainedChildGrowthSeconds >= 30 {
        summary.violations.append("直接子进程数连续至少 30 秒高于基线")
    }
    if let maximum = summary.maximumWindowCount, maximum > 1 {
        summary.violations.append("检测到多个顶屿窗口，最大值 \(maximum)")
    }
    if summary.finalWindowCount == 0 {
        summary.violations.append("结束时没有可见顶屿窗口")
    }

    try writeSummary(summary, to: configuration.outputURL)
    print("summary=\(configuration.outputURL.path)")
    print("samples=\(samplesURL.path)")
    print("duration=\(String(format: "%.1f", summary.observedDurationSeconds))s")
    print("samples=\(summary.sampleCount)")
    print("violations=\(summary.violations.count)")
}

do {
    let configuration = try Configuration.parse(arguments: CommandLine.arguments)
    try run(configuration: configuration)
} catch {
    fputs("长稳监测失败：\(error)\n", stderr)
    exit(1)
}
