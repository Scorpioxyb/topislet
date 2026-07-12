import Foundation

struct QishuiTargetedControlResult: Sendable {
    let didSend: Bool
    let diagnostic: String
}

final class QishuiTargetedMediaController: Sendable {
    private struct HelperPaths {
        let script: URL
        let framework: URL
    }

    static let perlExecutablePath = "/usr/bin/perl"
    static let processTimeout: TimeInterval = 2.0

    private let bundleIdentifier = "com.soda.music"

    func post(_ command: MusicControlCommand) -> QishuiTargetedControlResult {
        guard FileManager.default.isExecutableFile(atPath: Self.perlExecutablePath) else {
            return QishuiTargetedControlResult(
                didSend: false,
                diagnostic: "系统 Perl 不可用，未启动汽水 client 定向控制。"
            )
        }
        guard let paths = helperPaths() else {
            return QishuiTargetedControlResult(
                didSend: false,
                diagnostic: "汽水 client 定向控制资源不完整。"
            )
        }

        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: Self.perlExecutablePath)
        process.arguments = Self.commandArguments(
            script: paths.script,
            framework: paths.framework,
            bundleIdentifier: bundleIdentifier,
            command: command
        )
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            return QishuiTargetedControlResult(
                didSend: false,
                diagnostic: "汽水 client 定向控制启动失败：\(error.localizedDescription)"
            )
        }

        let deadline = Date().addingTimeInterval(Self.processTimeout)
        while process.isRunning, Date() < deadline {
            usleep(5_000)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            return QishuiTargetedControlResult(
                didSend: false,
                diagnostic: "汽水 client 定向控制超时，未向其他媒体源发送命令。"
            )
        }

        process.waitUntilExit()
        let standardOutput = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let standardError = String(
            data: error.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let didSend = Self.didSend(
            terminationStatus: process.terminationStatus,
            standardOutput: standardOutput
        )
        return QishuiTargetedControlResult(
            didSend: didSend,
            diagnostic: didSend
                ? "已将\(command.label)直接发送给汽水音乐 MediaRemote client。"
                : "汽水 client 定向控制不可用：\(standardError.trimmingCharacters(in: .whitespacesAndNewlines))"
        )
    }

    static func commandArguments(
        script: URL,
        framework: URL,
        bundleIdentifier: String,
        command: MusicControlCommand
    ) -> [String] {
        [
            script.path,
            framework.path,
            "send-client",
            bundleIdentifier,
            String(command.targetedMediaRemoteCommandID)
        ]
    }

    static func didSend(terminationStatus: Int32, standardOutput: String) -> Bool {
        terminationStatus == 0 && standardOutput.contains("targetedControlSent=true")
    }

    private func helperPaths() -> HelperPaths? {
        let fileManager = FileManager.default
        let roots = [
            Bundle.main.resourceURL?.appendingPathComponent("MediaRemoteAdapter"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Vendor/MediaRemoteAdapter")
        ].compactMap { $0 }

        for root in roots {
            let script = root.appendingPathComponent("mediaremote-adapter.pl")
            let framework = root.appendingPathComponent("MediaRemoteAdapter.framework")
            if fileManager.fileExists(atPath: script.path),
               fileManager.fileExists(atPath: framework.path) {
                return HelperPaths(script: script, framework: framework)
            }
        }
        return nil
    }
}
