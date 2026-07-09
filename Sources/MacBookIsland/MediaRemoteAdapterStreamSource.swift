import AppKit
import Foundation

@MainActor
final class MediaRemoteAdapterStreamSource {
    typealias ChangeHandler = @MainActor @Sendable () -> Void

    private let qishuiBundleIdentifier = "com.soda.music"
    private var process: Process?
    private var outputBuffer = Data()
    private var mergedPayload: [String: Any] = [:]
    private var latestSnapshot: MediaRemoteNowPlayingSnapshot?
    private var latestRawSnapshot: MediaRemoteNowPlayingSnapshot?
    private var lastVerifiedQishuiSnapshot: MediaRemoteNowPlayingSnapshot?
    private var latestSignature: String?
    private var artworkCache: [String: Data] = [:]
    private var artworkCacheOrder: [String] = []
    private var artworkFetchInFlight = false
    private var pendingArtworkRequestLookupKey: String?
    private var lastArtworkRequestLookupKey: String?
    private var lastArtworkRequestAt: Date?
    private var lastRestartAt: Date?
    private let lastVerifiedQishuiSnapshotTTL: TimeInterval = 5 * 60
    private var isStopping = false
    private var changeHandler: ChangeHandler?

    func start(onChange: @escaping ChangeHandler) {
        guard process == nil else { return }
        isStopping = false
        changeHandler = onChange
        guard let paths = adapterPaths() else {
            let snapshot = MediaRemoteNowPlayingSnapshot(
                isAvailable: false,
                isVerifiedQishuiSource: false,
                currentTrack: nil,
                diagnostic: "MediaRemote Adapter 资源未找到；已降级到普通 MediaRemote/AX。",
                checkedAt: Date()
            )
            latestRawSnapshot = snapshot
            latestSnapshot = snapshot
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            paths.script.path,
            paths.framework.path,
            "stream",
            "--debounce=80",
            "--no-diff",
            "--no-artwork"
        ]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.consume(data, onChange: onChange)
            }
        }

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.process = nil
                self.outputBuffer.removeAll()
                if !self.isStopping {
                    self.scheduleRestart(onChange: onChange)
                }
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            latestSnapshot = MediaRemoteNowPlayingSnapshot(
                isAvailable: false,
                isVerifiedQishuiSource: false,
                currentTrack: nil,
                diagnostic: "MediaRemote Adapter 启动失败：\(error.localizedDescription)。",
                checkedAt: Date()
            )
        }
    }

    func snapshot() -> MediaRemoteNowPlayingSnapshot? {
        if !mergedPayload.isEmpty {
            let rawSnapshot = snapshot(
                from: mergedPayload,
                existingArtwork: reusableArtwork(for: mergedPayload)
            )
            return remember(snapshot: rawSnapshot)
        }
        return latestSnapshot
    }

    func hasCurrentVerifiedQishuiSource() -> Bool {
        guard let snapshot = latestRawSnapshot ?? latestSnapshot else { return false }
        return snapshot.isVerifiedQishuiSource
    }

    func refreshOnce() -> MediaRemoteNowPlayingSnapshot {
        guard let paths = adapterPaths(),
              let payload = Self.runGet(script: paths.script, framework: paths.framework, includeArtwork: true) else {
            let snapshot = MediaRemoteNowPlayingSnapshot(
                isAvailable: false,
                isVerifiedQishuiSource: false,
                currentTrack: nil,
                diagnostic: "MediaRemote Adapter 单次读取失败。",
                checkedAt: Date()
            )
            latestRawSnapshot = snapshot
            latestSnapshot = snapshot
            return snapshot
        }

        let rawSnapshot = snapshot(from: payload, existingArtwork: nil)
        return remember(snapshot: rawSnapshot)
    }

    func refreshPlaybackPosition() -> MediaRemoteNowPlayingSnapshot? {
        guard let paths = adapterPaths(),
              let payload = Self.runGet(script: paths.script, framework: paths.framework, includeArtwork: false) else {
            return nil
        }

        mergedPayload.merge(payload) { _, new in new }
        let rawSnapshot = snapshot(from: payload, existingArtwork: reusableArtwork(for: payload))
        let effectiveSnapshot = remember(snapshot: rawSnapshot)
        if let track = rawSnapshot.currentTrack {
            let signature = trackSignature(track)
            let didChangeTrack = signature != latestSignature
            latestSignature = signature
            requestFreshMetadataIfNeeded(for: track, didChangeTrack: didChangeTrack, onChange: changeHandler)
        }
        return effectiveSnapshot
    }

    func seek(to elapsedTime: TimeInterval) -> Bool {
        guard let paths = adapterPaths() else { return false }
        let positionMicros = max(Int64((elapsedTime * 1_000_000).rounded()), 0)
        return Self.runCommand(
            script: paths.script,
            framework: paths.framework,
            arguments: ["seek", "\(positionMicros)"]
        )
    }

    func stop() {
        isStopping = true
        changeHandler = nil
        if let pipe = process?.standardOutput as? Pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        process?.terminationHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        outputBuffer.removeAll()
    }

    private func consume(_ data: Data, onChange: @escaping ChangeHandler) {
        outputBuffer.append(data)

        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let lineData = outputBuffer.prefix(upTo: newline)
            outputBuffer.removeSubrange(...newline)
            guard !lineData.isEmpty else { continue }
            handleLine(Data(lineData), onChange: onChange)
        }
    }

    private func handleLine(_ lineData: Data, onChange: @escaping ChangeHandler) {
        guard let object = try? JSONSerialization.jsonObject(with: lineData),
              let envelope = object as? [String: Any],
              envelope["type"] as? String == "data",
              let payload = envelope["payload"] as? [String: Any] else {
            return
        }

        let isDiff = boolValue(envelope["diff"]) ?? false
        if isDiff {
            for (key, value) in payload {
                if value is NSNull {
                    mergedPayload.removeValue(forKey: key)
                } else {
                    mergedPayload[key] = value
                }
            }
        } else {
            mergedPayload = payload
        }

        let rawSnapshot = snapshot(from: mergedPayload, existingArtwork: reusableArtwork(for: mergedPayload))
        let effectiveSnapshot = remember(snapshot: rawSnapshot)
        if let track = rawSnapshot.currentTrack {
            let signature = trackSignature(track)
            let didChangeTrack = signature != latestSignature
            latestSignature = signature
            requestFreshMetadataIfNeeded(for: track, didChangeTrack: didChangeTrack, onChange: onChange)
        }
        onChange()
        _ = effectiveSnapshot
    }

    private func remember(snapshot rawSnapshot: MediaRemoteNowPlayingSnapshot) -> MediaRemoteNowPlayingSnapshot {
        latestRawSnapshot = rawSnapshot

        if rawSnapshot.isVerifiedQishuiSource, rawSnapshot.currentTrack != nil {
            lastVerifiedQishuiSnapshot = rawSnapshot
            latestSnapshot = rawSnapshot
            return rawSnapshot
        }

        if let cachedSnapshot = recentQishuiSnapshot(whileCurrentSourceIs: rawSnapshot) {
            latestSnapshot = cachedSnapshot
            return cachedSnapshot
        }

        latestSnapshot = rawSnapshot
        return rawSnapshot
    }

    private func recentQishuiSnapshot(
        whileCurrentSourceIs rawSnapshot: MediaRemoteNowPlayingSnapshot
    ) -> MediaRemoteNowPlayingSnapshot? {
        guard let cachedSnapshot = lastVerifiedQishuiSnapshot,
              let cachedTrack = cachedSnapshot.currentTrack else {
            return nil
        }

        let now = Date()
        guard now.timeIntervalSince(cachedSnapshot.checkedAt) <= lastVerifiedQishuiSnapshotTTL else {
            lastVerifiedQishuiSnapshot = nil
            return nil
        }

        guard NSRunningApplication.runningApplications(withBundleIdentifier: qishuiBundleIdentifier).isEmpty == false else {
            lastVerifiedQishuiSnapshot = nil
            return nil
        }

        let track = cachedDisplayTrack(from: cachedTrack, cachedAt: cachedSnapshot.checkedAt, now: now)
        return MediaRemoteNowPlayingSnapshot(
            isAvailable: true,
            isVerifiedQishuiSource: true,
            currentTrack: track,
            diagnostic: "\(rawSnapshot.diagnostic) 已保持最近一次汽水音乐可信状态用于显示；控制会走汽水聚焦兜底，进度按最近可信播放态本地推进。",
            checkedAt: now
        )
    }

    private func cachedDisplayTrack(
        from track: MediaRemoteNowPlayingTrack,
        cachedAt: Date,
        now: Date
    ) -> MediaRemoteNowPlayingTrack {
        let elapsed: TimeInterval?
        let progress: Double
        if track.isPlaying == true,
           let cachedElapsed = track.elapsedTime,
           let duration = track.duration,
           duration > 0 {
            let liveElapsed = min(max(cachedElapsed + now.timeIntervalSince(cachedAt), 0), duration)
            elapsed = liveElapsed
            progress = min(max(liveElapsed / duration, 0), 1)
        } else {
            elapsed = track.elapsedTime
            progress = track.progress
        }

        return MediaRemoteNowPlayingTrack(
            title: track.title,
            artist: track.artist,
            album: track.album,
            artworkData: track.artworkData,
            isPlaying: track.isPlaying,
            progress: progress,
            elapsedTime: elapsed,
            duration: track.duration,
            sourceBundleIdentifier: track.sourceBundleIdentifier,
            sourceProcessIdentifier: track.sourceProcessIdentifier,
            sourceName: "MediaRemote Adapter Stream (recent Qishui)"
        )
    }

    private func snapshot(from payload: [String: Any], existingArtwork: Data?) -> MediaRemoteNowPlayingSnapshot {
        let checkedAt = Date()
        guard !payload.isEmpty else {
            return MediaRemoteNowPlayingSnapshot(
                isAvailable: true,
                isVerifiedQishuiSource: false,
                currentTrack: nil,
                diagnostic: "MediaRemote Adapter 暂无播放数据。",
                checkedAt: checkedAt
            )
        }

        let bundleID = stringValue(payload["bundleIdentifier"])
        let pid = pidValue(payload["processIdentifier"])
        let verified = bundleID == qishuiBundleIdentifier || isQishuiPID(pid)
        guard verified else {
            let source = bundleID ?? pid.map { "pid \($0)" } ?? "unknown"
            return MediaRemoteNowPlayingSnapshot(
                isAvailable: true,
                isVerifiedQishuiSource: false,
                currentTrack: nil,
                diagnostic: "MediaRemote Adapter 当前来源不是汽水音乐：\(source)。",
                checkedAt: checkedAt
            )
        }

        guard let title = stringValue(payload["title"])?.adapterTrimmedNonEmpty else {
            return MediaRemoteNowPlayingSnapshot(
                isAvailable: true,
                isVerifiedQishuiSource: true,
                currentTrack: nil,
                diagnostic: "MediaRemote Adapter 已确认汽水来源，但未给出歌名。",
                checkedAt: checkedAt
            )
        }

        let duration = doubleValue(payload["duration"])
        let elapsed = doubleValue(payload["elapsedTimeNow"])
            ?? currentElapsedTime(from: payload)
            ?? doubleValue(payload["elapsedTime"])
        let progress: Double
        if let elapsed, let duration, duration > 0 {
            progress = min(max(elapsed / duration, 0), 1)
        } else {
            progress = 0
        }

        let payloadSignature = [
            bundleID ?? "",
            title,
            stringValue(payload["artist"])?.adapterTrimmedNonEmpty ?? "汽水音乐",
            stringValue(payload["album"])?.adapterTrimmedNonEmpty ?? ""
        ].joined(separator: "\u{1f}")
        let artworkData = dataValue(payload["artworkData"]) ?? existingArtwork ?? artworkCache[payloadSignature]
        if let artworkData {
            rememberArtwork(artworkData, for: payloadSignature)
        }
        let track = MediaRemoteNowPlayingTrack(
            title: title,
            artist: stringValue(payload["artist"])?.adapterTrimmedNonEmpty ?? "汽水音乐",
            album: stringValue(payload["album"])?.adapterTrimmedNonEmpty,
            artworkData: artworkData,
            isPlaying: boolValue(payload["playing"]) ?? doubleValue(payload["playbackRate"]).map { $0 > 0.01 },
            progress: progress,
            elapsedTime: elapsed,
            duration: duration,
            sourceBundleIdentifier: bundleID,
            sourceProcessIdentifier: pid,
            sourceName: "MediaRemote Adapter Stream"
        )

        return MediaRemoteNowPlayingSnapshot(
            isAvailable: true,
            isVerifiedQishuiSource: true,
            currentTrack: track,
            diagnostic: "已通过 MediaRemote Adapter 实时读取汽水音乐；来源 \(bundleID ?? "pid \(pid ?? 0)")，封面 \(artworkData.map { "\($0.count) bytes" } ?? "补充中")。",
            checkedAt: checkedAt
        )
    }

    private func requestFreshMetadataIfNeeded(
        for track: MediaRemoteNowPlayingTrack?,
        didChangeTrack: Bool,
        onChange: ChangeHandler?
    ) {
        guard let track else { return }
        let needsArtist = track.artist == "汽水音乐"
        let needsArtwork = track.artworkData == nil
        guard didChangeTrack || needsArtist || needsArtwork else { return }
        requestFreshMetadata(for: track, onChange: onChange, force: didChangeTrack)
    }

    private func requestFreshMetadata(
        for track: MediaRemoteNowPlayingTrack,
        onChange: ChangeHandler?,
        force: Bool = false
    ) {
        guard let onChange, let paths = adapterPaths() else { return }
        let lookupKey = trackLookupKey(track)
        if artworkFetchInFlight {
            pendingArtworkRequestLookupKey = lookupKey
            return
        }

        let now = Date()
        if !force,
           lastArtworkRequestLookupKey == lookupKey,
           let lastArtworkRequestAt,
           now.timeIntervalSince(lastArtworkRequestAt) < 0.35 {
            return
        }
        lastArtworkRequestLookupKey = lookupKey
        lastArtworkRequestAt = now
        artworkFetchInFlight = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let payload = Self.runGet(script: paths.script, framework: paths.framework, includeArtwork: true)
            Task { @MainActor in
                guard let self else { return }
                self.artworkFetchInFlight = false
                guard let payload else {
                    self.requestPendingFreshMetadataIfNeeded(onChange: onChange, completedLookupKey: nil)
                    return
                }
                let nextSnapshot = self.snapshot(
                    from: payload,
                    existingArtwork: nil
                )
                guard let nextTrack = nextSnapshot.currentTrack else {
                    _ = self.remember(snapshot: nextSnapshot)
                    self.requestPendingFreshMetadataIfNeeded(onChange: onChange, completedLookupKey: nil)
                    return
                }
                let currentTrack = self.latestSnapshot?.currentTrack
                guard currentTrack.map({ self.metadataResponse(nextTrack, matches: $0) }) ?? true else {
                    self.requestPendingFreshMetadataIfNeeded(onChange: onChange, completedLookupKey: self.trackLookupKey(nextTrack))
                    return
                }
                let responseLookupKey = self.trackLookupKey(nextTrack)
                self.mergedPayload.merge(payload) { _, new in new }
                _ = self.remember(snapshot: nextSnapshot)
                onChange()
                self.requestPendingFreshMetadataIfNeeded(onChange: onChange, completedLookupKey: responseLookupKey)
            }
        }
    }

    private func requestPendingFreshMetadataIfNeeded(onChange: ChangeHandler?, completedLookupKey: String?) {
        guard let pendingLookupKey = pendingArtworkRequestLookupKey else { return }
        pendingArtworkRequestLookupKey = nil

        guard pendingLookupKey != completedLookupKey,
              let track = latestSnapshot?.currentTrack else {
            return
        }
        requestFreshMetadata(for: track, onChange: onChange, force: true)
    }

    nonisolated private static func runGet(
        script: URL,
        framework: URL,
        includeArtwork: Bool
    ) -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        var arguments = [
            script.path,
            framework.path,
            "get",
            "--now"
        ]
        if !includeArtwork {
            arguments.append("--no-artwork")
        }
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let payload = object as? [String: Any] else {
                return nil
            }
            return payload
        } catch {
            return nil
        }
    }

    nonisolated private static func runCommand(script: URL, framework: URL, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            script.path,
            framework.path
        ] + arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func currentElapsedTime(from payload: [String: Any]) -> Double? {
        guard let elapsed = doubleValue(payload["elapsedTime"]) else { return nil }
        guard let timestampText = stringValue(payload["timestamp"]),
              let timestamp = ISO8601DateFormatter().date(from: timestampText) else {
            return elapsed
        }
        let playbackRate = doubleValue(payload["playbackRate"]) ?? 0
        guard playbackRate >= 0 else { return elapsed }
        return elapsed + Date().timeIntervalSince(timestamp) * playbackRate
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

    private func isQishuiPID(_ pid: pid_t?) -> Bool {
        guard let pid,
              let app = NSRunningApplication(processIdentifier: pid) else {
            return false
        }
        return app.bundleIdentifier == qishuiBundleIdentifier
            || app.executableURL?.path.hasPrefix("/Applications/汽水音乐.app/") == true
            || app.bundleURL?.path.hasPrefix("/Applications/汽水音乐.app/") == true
    }

    private func scheduleRestart(onChange: @escaping ChangeHandler) {
        let now = Date()
        guard lastRestartAt.map({ now.timeIntervalSince($0) > 2 }) ?? true else { return }
        lastRestartAt = now
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.start(onChange: onChange)
        }
    }

    private func trackSignature(_ track: MediaRemoteNowPlayingTrack) -> String {
        [
            track.sourceBundleIdentifier ?? "",
            track.title,
            track.artist,
            track.album ?? ""
        ].joined(separator: "\u{1f}")
    }

    private func trackLookupKey(_ track: MediaRemoteNowPlayingTrack) -> String {
        [
            track.sourceBundleIdentifier ?? track.sourceProcessIdentifier.map { "pid:\($0)" } ?? "",
            track.title
        ].joined(separator: "\u{1f}")
    }

    private func metadataResponse(
        _ response: MediaRemoteNowPlayingTrack,
        matches current: MediaRemoteNowPlayingTrack
    ) -> Bool {
        guard (response.sourceBundleIdentifier ?? "") == (current.sourceBundleIdentifier ?? ""),
              response.title == current.title else {
            return false
        }

        let currentArtist = current.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let responseArtist = response.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentArtist != "汽水音乐",
           responseArtist != "汽水音乐",
           currentArtist != responseArtist {
            return false
        }

        if let currentAlbum = current.album?.trimmingCharacters(in: .whitespacesAndNewlines),
           let responseAlbum = response.album?.trimmingCharacters(in: .whitespacesAndNewlines),
           !currentAlbum.isEmpty,
           !responseAlbum.isEmpty,
           currentAlbum != responseAlbum {
            return false
        }

        return true
    }

    private func reusableArtwork(for payload: [String: Any]) -> Data? {
        guard let latestTrack = latestSnapshot?.currentTrack,
              payloadSignature(payload) == trackSignature(latestTrack) else {
            guard let signature = payloadSignature(payload) else { return nil }
            return artworkCache[signature]
        }
        return latestTrack.artworkData ?? artworkCache[trackSignature(latestTrack)]
    }

    private func payloadSignature(_ payload: [String: Any]) -> String? {
        guard let title = stringValue(payload["title"])?.adapterTrimmedNonEmpty else { return nil }
        return [
            stringValue(payload["bundleIdentifier"]) ?? "",
            title,
            stringValue(payload["artist"])?.adapterTrimmedNonEmpty ?? "汽水音乐",
            stringValue(payload["album"])?.adapterTrimmedNonEmpty ?? ""
        ].joined(separator: "\u{1f}")
    }

    private func rememberArtwork(_ data: Data, for signature: String) {
        artworkCache[signature] = data
        artworkCacheOrder.removeAll { $0 == signature }
        artworkCacheOrder.append(signature)
        while artworkCacheOrder.count > 24 {
            let removed = artworkCacheOrder.removeFirst()
            artworkCache.removeValue(forKey: removed)
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            if value == "true" || value == "1" { return true }
            if value == "false" || value == "0" { return false }
        }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Float { return Double(value) }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func pidValue(_ value: Any?) -> pid_t? {
        guard let intValue = doubleValue(value).map(Int32.init), intValue > 0 else { return nil }
        return pid_t(intValue)
    }

    private func dataValue(_ value: Any?) -> Data? {
        if let value = value as? Data { return value }
        guard let string = value as? String else { return nil }
        return Data(base64Encoded: string)
    }
}

private extension String {
    var adapterTrimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
