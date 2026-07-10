import Foundation

struct QishuiTargetedControlResult: Sendable {
    let didSend: Bool
    let diagnostic: String
}

final class QishuiTargetedMediaController: Sendable {
    private struct HelperPaths {
        let script: URL
        let frameworkBinary: URL
    }

    private let bundleIdentifier = "com.soda.music"
    private let timeout: TimeInterval = 0.6

    func post(_ command: MusicControlCommand) -> QishuiTargetedControlResult {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
            return QishuiTargetedControlResult(
                didSend: false,
                diagnostic: "系统 Python 不可用，未启动汽水 client 定向控制。"
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
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            paths.script.path,
            paths.frameworkBinary.path,
            bundleIdentifier,
            String(command.targetedMediaRemoteCommandID)
        ]
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

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            usleep(5_000)
        }
        if process.isRunning {
            process.terminate()
            return QishuiTargetedControlResult(
                didSend: false,
                diagnostic: "汽水 client 定向控制超时，未把命令转发给系统当前媒体源。"
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
        let didSend = process.terminationStatus == 0
            && standardOutput.contains("targetedControlSent=true")
        return QishuiTargetedControlResult(
            didSend: didSend,
            diagnostic: didSend
                ? "已将\(command.label)直接发送给汽水音乐 MediaRemote client。"
                : "汽水 client 定向控制不可用：\(standardError.trimmingCharacters(in: .whitespacesAndNewlines))"
        )
    }

    private func helperPaths() -> HelperPaths? {
        let fileManager = FileManager.default
        let roots = [
            Bundle.main.resourceURL?.appendingPathComponent("MediaRemoteAdapter"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Vendor/MediaRemoteAdapter")
        ].compactMap { $0 }

        for root in roots {
            let script = root.appendingPathComponent("qishui-targeted-control.py")
            let frameworkBinary = root
                .appendingPathComponent("MediaRemoteAdapter.framework")
                .appendingPathComponent("Versions/A/MediaRemoteAdapter")
            if fileManager.fileExists(atPath: script.path),
               fileManager.fileExists(atPath: frameworkBinary.path) {
                return HelperPaths(script: script, frameworkBinary: frameworkBinary)
            }
        }
        return nil
    }
}
