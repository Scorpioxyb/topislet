import Foundation
import MusicUsageDiagnostics

private struct Configuration {
    let last: String
    let inputURL: URL?
    let outputURL: URL

    static func parse(_ arguments: [String]) throws -> Configuration {
        var last = "24h"
        var inputPath: String?
        var outputPath: String?
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            guard index + 1 < arguments.count else {
                throw AnalyzerError.invalidArgument("\(argument) 缺少值")
            }
            let value = arguments[index + 1]
            switch argument {
            case "--last": last = value
            case "--input": inputPath = value
            case "--output": outputPath = value
            default: throw AnalyzerError.invalidArgument("未知参数：\(argument)")
            }
            index += 2
        }
        guard last.range(of: #"^[1-9][0-9]*[smhd]$"#, options: .regularExpression) != nil else {
            throw AnalyzerError.invalidArgument("--last 仅支持 30m、24h、7d 等格式")
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let date = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let defaultOutput = ".build/qa/topislet-daily-usage-\(date).json"
        return Configuration(
            last: last,
            inputURL: inputPath.map { absoluteURL(path: $0, relativeTo: root) },
            outputURL: absoluteURL(path: outputPath ?? defaultOutput, relativeTo: root)
        )
    }

    private static func absoluteURL(path: String, relativeTo root: URL) -> URL {
        path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : root.appendingPathComponent(path)
    }
}

private enum AnalyzerError: Error, CustomStringConvertible {
    case invalidArgument(String)
    case logCommandFailed(Int32, String)
    case invalidLogPayload

    var description: String {
        switch self {
        case let .invalidArgument(message): return message
        case let .logCommandFailed(status, message):
            return "系统日志读取失败（\(status)）：\(message)"
        case .invalidLogPayload: return "系统日志不是预期的 JSON 数组"
        }
    }
}

private struct UnifiedLogEntry: Decodable {
    let timestamp: String
    let eventMessage: String?
}

private let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZZZZZ"
    return formatter
}()

private func readUnifiedLog(last: String) throws -> Data {
    let process = Process()
    let output = Pipe()
    let errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    process.arguments = [
        "show", "--style", "json", "--last", last,
        "--predicate", "subsystem == \"io.github.scorpioxyb.topislet\""
    ]
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(
            data: errors.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? "unknown"
        throw AnalyzerError.logCommandFailed(process.terminationStatus, message)
    }
    return data
}

private func records(from data: Data) throws -> [TimestampedMusicUsageEvent] {
    let entries = try JSONDecoder().decode([UnifiedLogEntry].self, from: data)
    return entries.compactMap { entry in
        guard let timestamp = timestampFormatter.date(from: entry.timestamp),
              let eventMessage = entry.eventMessage,
              let event = MusicUsageEvent.parse(eventMessage) else {
            return nil
        }
        return TimestampedMusicUsageEvent(timestamp: timestamp, event: event)
    }
}

private func run() throws {
    let configuration = try Configuration.parse(CommandLine.arguments)
    let data = try configuration.inputURL.map { try Data(contentsOf: $0) }
        ?? readUnifiedLog(last: configuration.last)
    let report = MusicUsageDailyAnalyzer.analyze(try records(from: data))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let reportData = try encoder.encode(report)
    try FileManager.default.createDirectory(
        at: configuration.outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try reportData.write(to: configuration.outputURL, options: .atomic)
    let anomalyText = report.anomalies.isEmpty
        ? "无异常"
        : report.anomalies.joined(separator: ", ")
    print(
        "日常日志：\(report.structuredEventCount) 个结构化事件；"
        + "控制 \(report.controls.accepted)/\(report.controls.total)；"
        + "seek \(report.seeks.accepted)/\(report.seeks.total)；\(anomalyText)"
    )
    print("报告：\(configuration.outputURL.path)")
}

do {
    try run()
} catch {
    fputs("error: \(error)\n", stderr)
    exit(2)
}
