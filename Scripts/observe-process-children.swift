#!/usr/bin/env swift
// Read-only companion to the 5-second resource monitor. Does not alter its gates.
import Darwin
import Foundation

struct ChildObservation: Codable {
    let pid: pid_t
    let executableName: String
    let firstSeenSeconds: Double
    var lastSeenSeconds: Double
    var observedSamples: Int
}
struct ChildSummary: Codable {
    let parentPID: pid_t
    let durationSeconds: Double
    let requestedIntervalSeconds: Double
    let maximumActualSampleGapSeconds: Double
    let sampleCount: Int
    let baselinePIDs: [pid_t]
    let finalPIDs: [pid_t]
    let parentAliveAtEnd: Bool
    let maximumSampledCountGrowthSeconds: Double
    let transientChildren: [ChildObservation]
    let limitation: String
}
func fail(_ message: String) -> Never { fputs(message + "\n", stderr); exit(1) }
let args = CommandLine.arguments
// Positional arguments deliberately require an explicit target and output.
guard args.count == 5, let parent = pid_t(args[1]), parent > 0,
      let duration = Double(args[2]), duration.isFinite, duration > 0,
      let interval = Double(args[3]), interval.isFinite, interval >= 0.05, interval <= 1 else {
    fail("usage: observe-process-children.swift PID DURATION_SECONDS INTERVAL_SECONDS OUTPUT_JSON")
}
func alive() -> Bool {
    var info = proc_taskinfo()
    return proc_pidinfo(parent, PROC_PIDTASKINFO, 0, &info,
                        Int32(MemoryLayout<proc_taskinfo>.size)) == MemoryLayout<proc_taskinfo>.size
}
func childPIDs() -> Set<pid_t> {
    var buffer = [pid_t](repeating: 0, count: 1024)
    let count = buffer.withUnsafeMutableBytes { proc_listchildpids(parent, $0.baseAddress, Int32($0.count)) }
    guard count >= 0, count < buffer.count else { fail("child PID inventory failed or exceeded capacity") }
    return Set(buffer.prefix(Int(count)))
}
func executableName(_ pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let count = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
    guard count > 0 else { return "unavailable" }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    // Only basename: no process arguments, media URLs, credentials or user paths.
    return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self)).lastPathComponent
}
let output = URL(fileURLWithPath: args[4])
let csv = output.deletingPathExtension().appendingPathExtension("csv")
guard !FileManager.default.fileExists(atPath: output.path),
      !FileManager.default.fileExists(atPath: csv.path) else { fail("refusing to overwrite existing observations") }
guard alive() else { fail("target parent unavailable") }
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
FileManager.default.createFile(atPath: csv.path, contents: Data("elapsed_seconds,actual_gap_seconds,parent_alive,child_count,child_pids\n".utf8))
let handle = try FileHandle(forWritingTo: csv)
try handle.seekToEnd()
defer { try? handle.close() }
let baseline = childPIDs()
let start = ProcessInfo.processInfo.systemUptime
var previousTime = start
var previousHadGrowth = false
var growthStart: Double?
var maxGrowth = 0.0
var maxGap = 0.0
var samples = 0
var seen: [pid_t: ChildObservation] = [:]
var final = baseline
var parentAlive = true
while true {
    let sampleTime = ProcessInfo.processInfo.systemUptime
    let elapsed = sampleTime - start
    let gap = samples == 0 ? 0 : sampleTime - previousTime
    maxGap = max(maxGap, gap)
    parentAlive = alive()
    final = parentAlive ? childPIDs() : []
    for pid in final.subtracting(baseline) {
        if var record = seen[pid] {
            record.lastSeenSeconds = elapsed
            record.observedSamples += 1
            seen[pid] = record
        } else {
            seen[pid] = ChildObservation(pid: pid, executableName: executableName(pid),
                                         firstSeenSeconds: elapsed, lastSeenSeconds: elapsed, observedSamples: 1)
        }
    }
    if final.count > baseline.count {
        if !previousHadGrowth { growthStart = elapsed }
        maxGrowth = max(maxGrowth, elapsed - (growthStart ?? elapsed))
        previousHadGrowth = true
    } else {
        previousHadGrowth = false
        growthStart = nil
    }
    let row = String(format: "%.6f,%.6f,%@,%d,%@\n", elapsed, gap,
                     parentAlive ? "true" : "false", final.count,
                     final.sorted().map(String.init).joined(separator: "|"))
    try handle.write(contentsOf: Data(row.utf8))
    samples += 1
    previousTime = sampleTime
    if !parentAlive || elapsed >= duration { break }
    let remaining = duration - (ProcessInfo.processInfo.systemUptime - start)
    if remaining > 0 { Thread.sleep(forTimeInterval: min(interval, remaining)) }
}
let summary = ChildSummary(parentPID: parent, durationSeconds: ProcessInfo.processInfo.systemUptime - start,
                           requestedIntervalSeconds: interval, maximumActualSampleGapSeconds: maxGap,
                           sampleCount: samples, baselinePIDs: baseline.sorted(), finalPIDs: final.sorted(),
                           parentAliveAtEnd: parentAlive, maximumSampledCountGrowthSeconds: maxGrowth,
                           transientChildren: seen.values.sorted { $0.firstSeenSeconds < $1.firstSeenSeconds },
                           limitation: "Sampled evidence only; gaps can hide short children. PID reuse is not distinguished. Baseline children and other time intervals are not validated. Does not replace resource or continuous-play gates.")
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(summary).write(to: output, options: .atomic)
print("child observation complete: samples=\(samples), maximumActualGap=\(maxGap)s, parentAlive=\(parentAlive)")
