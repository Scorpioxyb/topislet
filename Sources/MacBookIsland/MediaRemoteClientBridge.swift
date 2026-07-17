import AppKit
import Darwin
import Foundation

enum MediaRemoteClientBridgeError: Error, Equatable {
    case invalidJSON
    case unexpectedBundleIdentifier
    case invalidProcessIdentifier
    case staleProcessIdentifier
    case missingTitle
}

struct MediaRemoteClientPayload: Equatable, Sendable {
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let contentItemIdentifier: String?
    let title: String
    let artist: String?
    let album: String?
    let artworkData: Data?
    let elapsedTime: TimeInterval?
    let duration: TimeInterval?
    let playbackRate: Double?
    let isPlaying: Bool?
    let observedAt: Date

    var stableTrackSignature: String {
        [
            descriptiveTrackSignature,
            duration.map { String(format: "%.3f", $0) } ?? ""
        ].joined(separator: "\u{1f}")
    }

    var descriptiveTrackSignature: String {
        [title, artist ?? "", album ?? ""].joined(separator: "\u{1f}")
    }

    var transitionFingerprint: MediaRemoteClientTransitionFingerprint {
        MediaRemoteClientTransitionFingerprint(
            stableTrackSignature: stableTrackSignature,
            artworkData: artworkData
        )
    }
}

struct MediaRemoteClientTransitionFingerprint: Equatable, Sendable {
    let stableTrackSignature: String
    let artworkData: Data?
}

private final class MediaRemoteClientOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func store(_ value: Data) {
        lock.lock()
        data = value
        lock.unlock()
    }

    func value() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

@MainActor
final class MediaRemoteClientBridge {
    typealias PayloadHandler = @MainActor @Sendable (MediaRemoteClientPayload) -> Void
    typealias FailureHandler = @MainActor @Sendable (String) -> Void

    private let bundleIdentifier: String
    private let runningProcessIdentifiersProvider: @Sendable () -> Set<pid_t>
    private var process: Process?
    private var outputBuffer = Data()
    private var generation: UInt64 = 0
    private var isStarted = false
    private var restartTask: Task<Void, Never>?
    private var payloadHandler: PayloadHandler?
    private var failureHandler: FailureHandler?

    init(
        bundleIdentifier: String,
        runningProcessIdentifiersProvider: @escaping @Sendable () -> Set<pid_t>
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.runningProcessIdentifiersProvider = runningProcessIdentifiersProvider
    }

    func start(
        onPayload: @escaping PayloadHandler,
        onFailure: @escaping FailureHandler
    ) {
        payloadHandler = onPayload
        failureHandler = onFailure
        isStarted = true
        startProcessIfNeeded()
    }

    func stop() {
        isStarted = false
        generation &+= 1
        restartTask?.cancel()
        restartTask = nil
        outputBuffer.removeAll()
        payloadHandler = nil
        failureHandler = nil
        guard let process else { return }
        if let pipe = process.standardOutput as? Pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        process.terminationHandler = nil
        if process.isRunning {
            process.terminate()
        }
        self.process = nil
    }

    func readOnce(includeArtwork: Bool) async -> MediaRemoteClientPayload? {
        guard let paths = adapterPaths() else { return nil }
        let expectedProcessIdentifiers = runningProcessIdentifiersProvider()
        guard !expectedProcessIdentifiers.isEmpty else { return nil }
        let bundleIdentifier = bundleIdentifier
        let data = await Task.detached(priority: .userInitiated) {
            Self.runGetData(
                script: paths.script,
                framework: paths.framework,
                bundleIdentifier: bundleIdentifier,
                includeArtwork: includeArtwork
            )
        }.value
        guard let data else { return nil }
        let currentProcessIdentifiers = runningProcessIdentifiersProvider()
        guard !currentProcessIdentifiers.isEmpty else { return nil }
        return try? Self.decode(
            data,
            expectedBundleIdentifier: bundleIdentifier,
            runningProcessIdentifiers: expectedProcessIdentifiers
                .intersection(currentProcessIdentifiers),
            observedAt: Date()
        )
    }

    nonisolated static func decode(
        _ data: Data,
        expectedBundleIdentifier: String,
        runningProcessIdentifiers: Set<pid_t>,
        observedAt: Date
    ) throws -> MediaRemoteClientPayload {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any] else {
            throw MediaRemoteClientBridgeError.invalidJSON
        }
        guard stringValue(payload["bundleIdentifier"]) == expectedBundleIdentifier else {
            throw MediaRemoteClientBridgeError.unexpectedBundleIdentifier
        }
        guard let processIdentifier = pidValue(payload["processIdentifier"]) else {
            throw MediaRemoteClientBridgeError.invalidProcessIdentifier
        }
        guard runningProcessIdentifiers.contains(processIdentifier) else {
            throw MediaRemoteClientBridgeError.staleProcessIdentifier
        }
        guard let title = stringValue(payload["title"])?.trimmedNonEmpty else {
            throw MediaRemoteClientBridgeError.missingTitle
        }

        let duration = nonnegativeDouble(payload["duration"])
        let playbackRate = finiteDouble(payload["playbackRate"])
        let isPlaying = boolValue(payload["playing"])
            ?? playbackRate.map { $0 > 0.01 }
        let elapsedTime = resolvedElapsedTime(
            payload,
            duration: duration,
            playbackRate: playbackRate,
            observedAt: observedAt
        )
        return MediaRemoteClientPayload(
            bundleIdentifier: expectedBundleIdentifier,
            processIdentifier: processIdentifier,
            contentItemIdentifier: stringValue(payload["contentItemIdentifier"]),
            title: title,
            artist: stringValue(payload["artist"])?.trimmedNonEmpty,
            album: stringValue(payload["album"])?.trimmedNonEmpty,
            artworkData: dataValue(payload["artworkData"]),
            elapsedTime: elapsedTime,
            duration: duration,
            playbackRate: playbackRate,
            isPlaying: isPlaying,
            observedAt: observedAt
        )
    }

    private func startProcessIfNeeded() {
        guard isStarted, process == nil else { return }
        guard let paths = adapterPaths() else {
            failureHandler?("MediaRemote Adapter 资源未找到。")
            scheduleRestart()
            return
        }

        generation &+= 1
        let processGeneration = generation
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            paths.script.path,
            paths.framework.path,
            "stream-client",
            bundleIdentifier,
            "--debounce=35",
            "--no-diff",
            "--no-artwork"
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self, weak process] in
                guard let self,
                      let process,
                      self.isStarted,
                      self.generation == processGeneration,
                      self.process === process else { return }
                self.consume(data)
            }
        }
        process.terminationHandler = { [weak self, weak process] _ in
            Task { @MainActor [weak self, weak process] in
                guard let self,
                      let process,
                      self.generation == processGeneration,
                      self.process === process else { return }
                output.fileHandleForReading.readabilityHandler = nil
                process.terminationHandler = nil
                self.process = nil
                self.outputBuffer.removeAll()
                if self.isStarted {
                    self.failureHandler?("网易云专属状态流已中断，正在重连。")
                    self.scheduleRestart()
                }
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            failureHandler?("网易云专属状态流启动失败：\(error.localizedDescription)")
            scheduleRestart()
        }
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newlineIndex = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newlineIndex]
            outputBuffer.removeSubrange(...newlineIndex)
            guard !line.isEmpty else { continue }
            let runningProcessIdentifiers = runningProcessIdentifiersProvider()
            guard let payload = try? Self.decode(
                Data(line),
                expectedBundleIdentifier: bundleIdentifier,
                runningProcessIdentifiers: runningProcessIdentifiers,
                observedAt: Date()
            ) else { continue }
            payloadHandler?(payload)
        }
    }

    private func scheduleRestart() {
        guard isStarted, restartTask == nil else { return }
        restartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let self, self.isStarted else { return }
            self.restartTask = nil
            self.startProcessIfNeeded()
        }
    }

    private func adapterPaths() -> (script: URL, framework: URL)? {
        let candidates: [URL] = [
            Bundle.main.resourceURL?.appendingPathComponent("MediaRemoteAdapter"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Vendor/MediaRemoteAdapter"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Vendor/MediaRemoteAdapter")
        ].compactMap { $0 }

        for root in candidates {
            let script = root.appendingPathComponent("mediaremote-adapter.pl")
            let framework = root.appendingPathComponent("MediaRemoteAdapter.framework")
            if FileManager.default.fileExists(atPath: script.path),
               FileManager.default.fileExists(atPath: framework.path) {
                return (script, framework)
            }
        }
        return nil
    }

    nonisolated private static func runGetData(
        script: URL,
        framework: URL,
        bundleIdentifier: String,
        includeArtwork: Bool
    ) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            script.path,
            framework.path,
            "get-client",
            bundleIdentifier,
            "--now"
        ] + (includeArtwork ? [] : ["--no-artwork"])
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let outputBuffer = MediaRemoteClientOutputBuffer()
            let outputFinished = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .utility).async {
                outputBuffer.store(output.fileHandleForReading.readDataToEndOfFile())
                outputFinished.signal()
            }
            let deadline = Date().addingTimeInterval(includeArtwork ? 1.0 : 0.7)
            while process.isRunning, Date() < deadline {
                usleep(10_000)
            }
            if process.isRunning {
                process.terminate()
                let terminationDeadline = Date().addingTimeInterval(0.2)
                while process.isRunning, Date() < terminationDeadline {
                    usleep(10_000)
                }
                if process.isRunning {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                }
            }
            guard !process.isRunning else { return nil }
            _ = outputFinished.wait(timeout: .now() + 0.4)
            guard process.terminationStatus == 0 else { return nil }
            return outputBuffer.value()
        } catch {
            return nil
        }
    }

    nonisolated private static func resolvedElapsedTime(
        _ payload: [String: Any],
        duration: TimeInterval?,
        playbackRate: Double?,
        observedAt: Date
    ) -> TimeInterval? {
        var elapsed = nonnegativeDouble(payload["elapsedTimeNow"])
            ?? nonnegativeDouble(payload["elapsedTime"])
        if payload["elapsedTimeNow"] == nil,
           let baseElapsed = elapsed,
           let timestampText = stringValue(payload["timestamp"]),
           let timestamp = ISO8601DateFormatter().date(from: timestampText),
           let playbackRate,
           playbackRate > 0 {
            elapsed = baseElapsed + max(observedAt.timeIntervalSince(timestamp), 0) * playbackRate
        }
        guard let elapsed else { return nil }
        if let duration, duration > 0 {
            return min(max(elapsed, 0), duration)
        }
        return max(elapsed, 0)
    }

    nonisolated private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    nonisolated private static func pidValue(_ value: Any?) -> pid_t? {
        if let value = value as? NSNumber, value.int32Value > 0 {
            return value.int32Value
        }
        if let value = value as? Int, value > 0 {
            return pid_t(value)
        }
        return nil
    }

    nonisolated private static func finiteDouble(_ value: Any?) -> Double? {
        let candidate: Double?
        if let value = value as? NSNumber {
            candidate = value.doubleValue
        } else {
            candidate = value as? Double
        }
        guard let candidate, candidate.isFinite else { return nil }
        return candidate
    }

    nonisolated private static func nonnegativeDouble(_ value: Any?) -> Double? {
        guard let value = finiteDouble(value), value >= 0 else { return nil }
        return value
    }

    nonisolated private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    nonisolated private static func dataValue(_ value: Any?) -> Data? {
        if let value = value as? Data { return value }
        guard let value = value as? String else { return nil }
        return Data(base64Encoded: value)
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
