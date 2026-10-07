import AppKit
import ApplicationServices
import Combine
import Darwin
import EventKit
import ImageIO
import QuartzCore
import SwiftUI

private let islandEventNotificationName = Notification.Name("io.github.scorpioxyb.topislet.event")

if CommandLine.arguments.contains("--login-item-status") {
    Task { @MainActor in
        let settings = LoginItemSettings()
        print("loginItemStatus=\(settings.status.diagnosticCode)")
        print("loginItemRequested=\(settings.isRequested)")
        exit(0)
    }
    RunLoop.main.run()
}

if let loginItemIndex = CommandLine.arguments.firstIndex(of: "--login-item-set") {
    guard CommandLine.arguments.indices.contains(loginItemIndex + 1) else {
        print("usage: MacBookIsland --login-item-set on|off")
        exit(64)
    }
    let requestedValue = CommandLine.arguments[loginItemIndex + 1].lowercased()
    guard ["on", "off"].contains(requestedValue) else {
        print("error=unsupported_login_item_value")
        print("supported=on,off")
        exit(64)
    }
    Task { @MainActor in
        let settings = LoginItemSettings()
        settings.setEnabled(requestedValue == "on")
        print("loginItemStatus=\(settings.status.diagnosticCode)")
        print("loginItemRequested=\(settings.isRequested)")
        print("error=\(settings.errorMessage ?? "nil")")
        let succeeded = requestedValue == "on"
            ? settings.isRequested
            : settings.status == .disabled
        exit(succeeded ? 0 : 2)
    }
    RunLoop.main.run()
}

if CommandLine.arguments.contains("--music-adapters") {
    for registration in MusicAdapterRegistry.registrations {
        let capabilities = MusicAdapterCapability.allCases
            .filter(registration.capabilities.contains)
            .map(\.rawValue)
            .joined(separator: ",")
        print("adapter=\(registration.descriptor.bundleIdentifier)")
        print("name=\(registration.descriptor.displayName)")
        print("status=\(registration.implementationStatus.rawValue)")
        print("capabilities=\(capabilities)")
        print("")
    }
    exit(0)
}

if CommandLine.arguments.contains("--apple-music-status") {
    let transitionTimeline = AppleMusicTransitionTimeline()
    let adapter = AppleMusicAppAdapter(
        transitionTimeline: transitionTimeline
    )
    Task { @MainActor in
        let startedAt = Date()
        transitionTimeline.notePlayerInfo(
            candidateSignature: nil,
            detail: "source=apple-music-status"
        )
        var snapshot = await adapter.snapshot(refresh: .metadata)
        let metadataLatencyMilliseconds = Int(
            Date().timeIntervalSince(startedAt) * 1_000
        )
        var artworkLatencyMilliseconds: Int?
        if snapshot.track?.artworkData != nil {
            artworkLatencyMilliseconds = metadataLatencyMilliseconds
        } else if snapshot.track?.artist?.isEmpty == false {
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                let cachedSnapshot = await adapter.snapshot(refresh: .cached)
                if cachedSnapshot.track?.artworkData != nil {
                    snapshot = cachedSnapshot
                    artworkLatencyMilliseconds = Int(
                        Date().timeIntervalSince(startedAt) * 1_000
                    )
                    break
                }
            }
        }
        let availability: String
        switch snapshot.availability {
        case .ready:
            availability = "ready"
        case .notRunning:
            availability = "notRunning"
        case let .degraded(reason):
            availability = "degraded:\(reason)"
        case let .permissionRequired(permission):
            availability = "permissionRequired:\(permission)"
        case let .unavailable(reason):
            availability = "unavailable:\(reason)"
        }
        let snapshotProcessIdentifier = snapshot.instance?.processIdentifier.description ?? "nil"
        print("appleMusicRunning=\(AppleMusicAppAdapter.isRunning)")
        print("appleMusicSnapshotPID=\(snapshotProcessIdentifier)")
        print("appleMusicRunningPIDs=\(NSRunningApplication.runningApplications(withBundleIdentifier: MusicAdapterRegistry.appleMusic.descriptor.bundleIdentifier).map(\.processIdentifier))")
        print("availability=\(availability)")
        print("track=\(snapshot.track?.title ?? "nil")")
        print("artworkDataBytes=\(snapshot.track?.artworkData?.count ?? 0)")
        print("metadataLatencyMilliseconds=\(metadataLatencyMilliseconds)")
        print("artworkLatencyMilliseconds=\(artworkLatencyMilliseconds.map(String.init) ?? "unavailable")")
        print("diagnosticDurationMilliseconds=\(Int(Date().timeIntervalSince(startedAt) * 1_000))")
        print("diagnostic=\(snapshot.diagnostic)")
        print("transitionTimelineBegin")
        print(transitionTimeline.latestReport())
        print("transitionTimelineEnd")
        exit(0)
    }
    RunLoop.main.run()
}

if CommandLine.arguments.contains("--apple-music-request-access") {
    let permissionApp = NSApplication.shared
    permissionApp.setActivationPolicy(.regular)
    permissionApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.async {
        let access = AppleMusicAppAdapter.automationAccess(prompt: true)
        print("automationAccess=\(access.diagnosticCode)")
        exit(access == .allowed ? 0 : 2)
    }
    permissionApp.run()
}

if let eventIndex = CommandLine.arguments.firstIndex(of: "--post-event") {
    guard CommandLine.arguments.indices.contains(eventIndex + 2) else {
        print("usage: MacBookIsland --post-event TITLE BODY [SOURCE]")
        exit(64)
    }
    let source = CommandLine.arguments.indices.contains(eventIndex + 3)
        ? CommandLine.arguments[eventIndex + 3]
        : "顶屿"
    DistributedNotificationCenter.default().postNotificationName(
        islandEventNotificationName,
        object: nil,
        userInfo: [
            "title": CommandLine.arguments[eventIndex + 1],
            "body": CommandLine.arguments[eventIndex + 2],
            "source": source
        ],
        deliverImmediately: true
    )
    print("eventPosted=true")
    exit(0)
}

if CommandLine.arguments.contains("--eventkit-status") {
    let calendar = EventKitAccessState(EKEventStore.authorizationStatus(for: .event))
    let reminders = EventKitAccessState(EKEventStore.authorizationStatus(for: .reminder))
    print("calendarAccess=\(calendar.rawValue)")
    print("remindersAccess=\(reminders.rawValue)")
    exit(0)
}

if CommandLine.arguments.contains("--ax-check") {
    print("accessibilityTrusted=\(AXIsProcessTrusted())")
    exit(AXIsProcessTrusted() ? 0 : 2)
}

if CommandLine.arguments.contains("--display-geometry") {
    for (index, screen) in NSScreen.screens.enumerated() {
        let displayID = (screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber)?.uint32Value
        let physicalUUID = displayID.flatMap(IslandDisplayIdentity.physicalUUID(for:))
        let stableIdentity = IslandDisplayIdentity.stableIdentifier(
            displayID: displayID,
            physicalUUID: physicalUUID,
            displayName: screen.localizedName,
            frame: screen.frame
        )
        let geometry = IslandDisplayGeometry.resolve(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
            backingScaleFactor: screen.backingScaleFactor,
            notchHeightAdjustment: 1
        )
        print("displayIndex=\(index)")
        print("name=\(screen.localizedName)")
        print("displayID=\(displayID.map(String.init) ?? "nil")")
        print("displayUUID=\(physicalUUID ?? "nil")")
        print("stableIdentity=\(stableIdentity)")
        print("frame=\(NSStringFromRect(screen.frame))")
        print("scale=\(screen.backingScaleFactor)")
        print("safeAreaTop=\(screen.safeAreaInsets.top)")
        print("hasCameraHousing=\(geometry.hasCameraHousing)")
        print("cameraHousingFrame=\(geometry.cameraHousingFrame.map(NSStringFromRect) ?? "nil")")
        print("islandAnchorX=\(geometry.islandAnchorX)")
        print("notchWidth=\(geometry.notchWidth)")
        print("topBandHeight=\(geometry.topBandHeight)")
        print("")
    }
    exit(0)
}

if CommandLine.arguments.contains("--fullscreen-status") {
    for (index, screen) in NSScreen.screens.enumerated() {
        let windowServerFrame = IslandFullScreenSuppressionPolicy.windowServerFrame(
            for: screen.frame,
            primaryDisplayHeight: NSScreen.screens.first?.frame.height ?? screen.frame.height
        )
        print("displayIndex=\(index)")
        print("appKitFrame=\(NSStringFromRect(screen.frame))")
        print("windowServerFrame=\(NSStringFromRect(windowServerFrame))")
        print("hasCoveringWindow=\(IslandFullScreenWindowDetector.hasCoveringWindow(on: screen))")
    }
    exit(0)
}

func printQishuiSnapshot(_ snapshot: QishuiDirectSnapshot) {
    print("qishuiRunning=\(snapshot.isRunning)")
    print("pid=\(snapshot.processIdentifier.map(String.init) ?? "nil")")
    print("supportRoot=\(snapshot.supportRoot.path)")
    print("desktopLyricsEnabled=\(snapshot.desktopLyricsEnabled.map(String.init) ?? "unknown")")
    print("queueCacheTrackCount=\(snapshot.queueCacheTrackCount)")
    if let track = snapshot.currentTrack {
        print("currentTrack=\(track.title) - \(track.artist)")
        print("isPlaying=\(track.isPlaying.map(String.init) ?? "unknown")")
        let progressText = track.progress.map { String($0) } ?? "unavailable"
        print("progress=\(progressText)")
        print("artworkURL=\(track.artworkURL?.absoluteString ?? "nil")")
        print("lyricsCount=\(track.lyrics.count)")
        if !track.lyrics.isEmpty {
            print("lyricsPreview=\(track.lyrics.prefix(3).joined(separator: " / "))")
        }
        print("source=\(track.sourceName)")
    } else {
        print("currentTrack=nil")
    }
    print("diagnostic=\(snapshot.diagnostic)")
}

func printMediaRemoteSnapshot(_ snapshot: MediaRemoteNowPlayingSnapshot) {
    print("mediaRemoteAvailable=\(snapshot.isAvailable)")
    print("verifiedQishuiSource=\(snapshot.isVerifiedQishuiSource)")
    if let track = snapshot.currentTrack {
        print("currentTrack=\(track.title) - \(track.artist)")
        print("album=\(track.album ?? "nil")")
        print("isPlaying=\(track.isPlaying.map(String.init) ?? "unknown")")
        print("progress=\(track.progress)")
        print("elapsedTime=\(track.elapsedTime.map { String($0) } ?? "nil")")
        print("duration=\(track.duration.map { String($0) } ?? "nil")")
        print("artworkDataBytes=\(track.artworkData?.count ?? 0)")
        print("sourceBundleIdentifier=\(track.sourceBundleIdentifier ?? "nil")")
        print("sourceProcessIdentifier=\(track.sourceProcessIdentifier.map(String.init) ?? "nil")")
        print("source=\(track.sourceName)")
    } else {
        print("currentTrack=nil")
    }
    print("diagnostic=\(snapshot.diagnostic)")
}

func command(named rawValue: String) -> MusicControlCommand? {
    switch rawValue.lowercased() {
    case "playpause", "toggle", "play-pause", "play_pause":
        return .playPause
    case "next", "nexttrack", "next-track", "next_track":
        return .nextTrack
    case "previous", "prev", "previoustrack", "previous-track", "previous_track":
        return .previousTrack
    default:
        return nil
    }
}

if CommandLine.arguments.contains("--mediaremote-status") {
    let source = MediaRemoteNowPlayingSource()
    printMediaRemoteSnapshot(source.snapshot())
    exit(0)
}

if CommandLine.arguments.contains("--adapter-status") {
    let source = MediaRemoteAdapterStreamSource()
    printMediaRemoteSnapshot(source.refreshOnce())
    exit(0)
}

if CommandLine.arguments.contains("--qishui-control-diagnostic") {
    print(QishuiSemanticAXController().diagnostic())
    exit(0)
}

if CommandLine.arguments.contains("--qishui-control-availability") {
    let processIdentifier = QishuiProcessLocator.application()?.processIdentifier
    let availability = QishuiSemanticAXController().controlAvailability(
        processIdentifier: processIdentifier
    )
    print("controlAvailability=\(availability.rawValue)")
    print("allowsControl=\(availability.allowsControl)")
    print("reason=\(availability.unavailableReason ?? "nil")")
    exit(availability == .available ? 0 : 2)
}

if let adapterWatchIndex = CommandLine.arguments.firstIndex(of: "--adapter-watch") {
    let seconds = CommandLine.arguments.indices.contains(adapterWatchIndex + 1)
        ? (TimeInterval(CommandLine.arguments[adapterWatchIndex + 1]) ?? 5)
        : 5
    let source = MediaRemoteAdapterStreamSource()
    source.start {
        print("EVENT \(ISO8601DateFormatter().string(from: Date()))")
        if let snapshot = source.snapshot() {
            printMediaRemoteSnapshot(snapshot)
        }
        fflush(stdout)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(max(seconds, 1)))
    source.stop()
    exit(0)
}

if let gateIndex = CommandLine.arguments.firstIndex(of: "--qishui-transition-gate") {
    let requestedCount = CommandLine.arguments.indices.contains(gateIndex + 1)
        ? (Int(CommandLine.arguments[gateIndex + 1]) ?? 5)
        : 5
    let sampleCount = min(max(requestedCount, 1), 50)

    Task { @MainActor in
        let coordinator = MusicAdapterCoordinator()
        coordinator.setAppleMusicEnabled(false)
        var latestState = coordinator.initialState
        coordinator.startRealtimeObservation { state, _ in
            latestState = state
        }

        let initialDeadline = Date().addingTimeInterval(8)
        while Date() < initialDeadline {
            let isReady = latestState.hasCurrentTrack
                && latestState.track.sourceBundleIdentifier == "com.soda.music"
                && latestState.duration != nil
                && (latestState.track.hasArtwork || latestState.track.artworkData != nil)
                && latestState.canNextTrack
            if isReady { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        guard latestState.hasCurrentTrack,
              latestState.track.sourceBundleIdentifier == "com.soda.music",
              latestState.canNextTrack else {
            print("gate=failed")
            print("reason=qishui_state_or_control_unavailable")
            print("has_track=\(latestState.hasCurrentTrack ? 1 : 0)")
            print("source_matches=\(latestState.track.sourceBundleIdentifier == "com.soda.music" ? 1 : 0)")
            print("has_duration=\(latestState.duration == nil ? 0 : 1)")
            print("has_artwork=\((latestState.track.hasArtwork || latestState.track.artworkData != nil) ? 1 : 0)")
            print("can_next=\(latestState.canNextTrack ? 1 : 0)")
            coordinator.stopRealtimeObservation()
            exit(2)
        }

        var latencies: [Int] = []
        var rejectedCount = 0
        var incompleteCount = 0
        for sample in 1...sampleCount {
            let baselineTitle = latestState.track.title
            let baselineArtist = latestState.track.artist
            let issuedAt = Date()
            let outcome = await coordinator.performControl(
                .nextTrack,
                displayedSourceBundleIdentifier: "com.soda.music"
            )
            let controlMilliseconds = max(
                Int(Date().timeIntervalSince(issuedAt) * 1_000),
                0
            )
            guard outcome.didSendCommand else {
                rejectedCount += 1
                print("sample=\(sample) accepted=0 control_ms=\(controlMilliseconds)")
                continue
            }

            let convergenceDeadline = Date().addingTimeInterval(3)
            var didConverge = false
            while Date() < convergenceDeadline {
                let didChangeTrack = latestState.track.title != baselineTitle
                    || latestState.track.artist != baselineArtist
                let hasArtwork = latestState.track.hasArtwork
                    || latestState.track.artworkData != nil
                if latestState.hasCurrentTrack,
                   latestState.track.sourceBundleIdentifier == "com.soda.music",
                   didChangeTrack,
                   !latestState.track.artist.isEmpty,
                   latestState.duration != nil,
                   hasArtwork {
                    didConverge = true
                    break
                }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }

            let latencyMilliseconds = max(
                Int(Date().timeIntervalSince(issuedAt) * 1_000),
                0
            )
            let hasArtwork = latestState.track.hasArtwork
                || latestState.track.artworkData != nil
            if didConverge {
                latencies.append(latencyMilliseconds)
            } else {
                incompleteCount += 1
            }
            print(
                "sample=\(sample) accepted=1 converged=\(didConverge ? 1 : 0) "
                    + "control_ms=\(controlMilliseconds) latency_ms=\(latencyMilliseconds) "
                    + "has_artist=\(latestState.track.artist.isEmpty ? 0 : 1) "
                    + "has_artwork=\(hasArtwork ? 1 : 0) "
                    + "has_duration=\(latestState.duration == nil ? 0 : 1)"
            )
            fflush(stdout)
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        let sorted = latencies.sorted()
        func percentile(_ fraction: Double) -> Int? {
            guard !sorted.isEmpty else { return nil }
            let index = min(
                max(Int(ceil(Double(sorted.count) * fraction)) - 1, 0),
                sorted.count - 1
            )
            return sorted[index]
        }
        print("gate=complete")
        print("samples=\(sampleCount)")
        print("converged=\(latencies.count)")
        print("rejected=\(rejectedCount)")
        print("incomplete=\(incompleteCount)")
        print("p50_ms=\(percentile(0.50).map(String.init) ?? "nil")")
        print("p95_ms=\(percentile(0.95).map(String.init) ?? "nil")")
        print("max_ms=\(sorted.last.map(String.init) ?? "nil")")
        coordinator.stopRealtimeObservation()
        let passed = rejectedCount == 0
            && incompleteCount == 0
            && latencies.count == sampleCount
            && (percentile(0.95) ?? .max) <= 500
        exit(passed ? 0 : 2)
    }
    RunLoop.main.run()
}

if let semanticControlIndex = CommandLine.arguments.firstIndex(of: "--qishui-semantic-control") {
    let rawCommand = CommandLine.arguments.indices.contains(semanticControlIndex + 1)
        ? CommandLine.arguments[semanticControlIndex + 1]
        : "playPause"
    guard let controlCommand = command(named: rawCommand) else {
        print("error=unsupported_control_command")
        print("supported=playPause,next,previous")
        exit(64)
    }

    let source = MediaRemoteAdapterStreamSource()
    print("BEFORE")
    printMediaRemoteSnapshot(source.refreshOnce())
    let result = QishuiSemanticAXController().press(controlCommand)
    print("semanticQishuiControlSent=\(result.didPress)")
    print("diagnostic=\(result.diagnostic)")
    usleep(220_000)
    print("AFTER")
    printMediaRemoteSnapshot(source.refreshOnce())
    exit(result.didPress ? 0 : 2)
}

if CommandLine.arguments.contains("--netease-music-status") {
    let adapter = NeteaseMusicAppAdapter()
    Task { @MainActor in
        let startedAt = Date()
        let snapshot = await adapter.snapshot(refresh: .metadata)
        let availability: String
        switch snapshot.availability {
        case .ready:
            availability = "ready"
        case .notRunning:
            availability = "notRunning"
        case let .degraded(reason):
            availability = "degraded:\(reason)"
        case let .permissionRequired(permission):
            availability = "permissionRequired:\(permission)"
        case let .unavailable(reason):
            availability = "unavailable:\(reason)"
        }
        print("neteaseMusicSnapshotPID=\(snapshot.instance?.processIdentifier.description ?? "nil")")
        print("neteaseMusicRunningPIDs=\(NSRunningApplication.runningApplications(withBundleIdentifier: MusicAdapterRegistry.neteaseMusic.descriptor.bundleIdentifier).map(\.processIdentifier))")
        print("availability=\(availability)")
        print("track=\(snapshot.track?.title ?? "nil")")
        print("artist=\(snapshot.track?.artist ?? "nil")")
        print("artworkDataBytes=\(snapshot.track?.artworkData?.count ?? 0)")
        print("elapsedTime=\(snapshot.timeline?.elapsedTime.description ?? "nil")")
        print("duration=\(snapshot.timeline?.duration.description ?? "nil")")
        print("playbackState=\(snapshot.playbackState)")
        print("playPause=\(snapshot.controls.supports(.playPause))")
        print("previousTrack=\(snapshot.controls.supports(.previousTrack))")
        print("nextTrack=\(snapshot.controls.supports(.nextTrack))")
        print("latencyMilliseconds=\(Int(Date().timeIntervalSince(startedAt) * 1_000))")
        print("diagnostic=\(snapshot.diagnostic)")
        exit(0)
    }
    RunLoop.main.run()
}

if let controlIndex = CommandLine.arguments.firstIndex(of: "--netease-music-semantic-control") {
    let rawCommand = CommandLine.arguments.indices.contains(controlIndex + 1)
        ? CommandLine.arguments[controlIndex + 1]
        : "playPause"
    guard let musicCommand = command(named: rawCommand) else {
        print("error=unsupported_control_command")
        print("supported=playPause,next,previous")
        exit(64)
    }
    guard let processIdentifier = NSRunningApplication.runningApplications(
        withBundleIdentifier: MusicAdapterRegistry.neteaseMusic.descriptor.bundleIdentifier
    ).first(where: { !$0.isTerminated })?.processIdentifier else {
        print("didPress=false")
        print("diagnostic=网易云音乐当前未运行。")
        exit(2)
    }
    let action: MusicControlAction
    switch musicCommand {
    case .playPause:
        action = .playPause
    case .previousTrack:
        action = .previousTrack
    case .nextTrack:
        action = .nextTrack
    }
    let result = NeteaseMusicSemanticAXController().perform(
        action,
        processIdentifier: processIdentifier
    )
    print("targetPID=\(processIdentifier)")
    print("didPress=\(result.didPress)")
    print("diagnostic=\(result.diagnostic)")
    exit(result.didPress ? 0 : 2)
}

if let controlIndex = CommandLine.arguments.firstIndex(of: "--netease-music-adapter-control") {
    let rawCommand = CommandLine.arguments.indices.contains(controlIndex + 1)
        ? CommandLine.arguments[controlIndex + 1]
        : "playPause"
    guard let musicCommand = command(named: rawCommand) else {
        print("error=unsupported_control_command")
        print("supported=playPause,next,previous")
        exit(64)
    }
    let adapter = NeteaseMusicAppAdapter()
    Task { @MainActor in
        adapter.start { _ in }
        let baseline = await adapter.snapshot(refresh: .metadata)
        guard let instance = baseline.instance,
              let track = baseline.track else {
            print("error=netease_snapshot_unavailable")
            print("diagnostic=\(baseline.diagnostic)")
            adapter.stop()
            exit(2)
        }
        let action: MusicControlAction
        switch musicCommand {
        case .playPause:
            action = .playPause
        case .previousTrack:
            action = .previousTrack
        case .nextTrack:
            action = .nextTrack
        }
        let startedAt = Date()
        let result = await adapter.perform(MusicControlRequest(
            id: 1,
            target: instance,
            expectedTrack: track.identity,
            action: action
        ))
        print("controlDisposition=\(result.disposition)")
        print("controlDiagnostic=\(result.diagnostic)")
        var lastFingerprint = ""
        for _ in 0..<35 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            let snapshot = await adapter.snapshot(refresh: .cached)
            let fingerprint = [
                snapshot.track?.title ?? "nil",
                snapshot.track?.artist ?? "nil",
                snapshot.track?.artworkData?.count.description ?? "0",
                snapshot.timeline?.duration.description ?? "nil",
                String(describing: snapshot.playbackState)
            ].joined(separator: "\u{1f}")
            guard fingerprint != lastFingerprint else { continue }
            lastFingerprint = fingerprint
            print("t=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))")
            print("track=\(snapshot.track?.title ?? "nil")")
            print("artist=\(snapshot.track?.artist ?? "nil")")
            print("artworkDataBytes=\(snapshot.track?.artworkData?.count ?? 0)")
            print("duration=\(snapshot.timeline?.duration.description ?? "nil")")
            print("playbackState=\(snapshot.playbackState)")
            fflush(stdout)
        }
        adapter.stop()
        exit(result.disposition == .accepted ? 0 : 2)
    }
    RunLoop.main.run()
}

if let watchIndex = CommandLine.arguments.firstIndex(of: "--mediaremote-watch") {
    let seconds = CommandLine.arguments.indices.contains(watchIndex + 1)
        ? (TimeInterval(CommandLine.arguments[watchIndex + 1]) ?? 20)
        : 20
    let source = MediaRemoteNowPlayingSource()
    source.start {
        print("EVENT \(ISO8601DateFormatter().string(from: Date()))")
        printMediaRemoteSnapshot(source.snapshot())
        fflush(stdout)
    }
    print("INITIAL \(ISO8601DateFormatter().string(from: Date()))")
    printMediaRemoteSnapshot(source.snapshot())
    RunLoop.current.run(until: Date().addingTimeInterval(max(seconds, 1)))
    exit(0)
}

if let repeatIndex = CommandLine.arguments.firstIndex(of: "--qishui-status-repeat") {
    let count = CommandLine.arguments.indices.contains(repeatIndex + 1)
        ? (Int(CommandLine.arguments[repeatIndex + 1]) ?? 3)
        : 3
    let adapter = QishuiAdapter()
    var lastSnapshot: QishuiDirectSnapshot?
    for index in 1...max(count, 1) {
        print("READ[\(index)]")
        let snapshot = adapter.snapshot()
        printQishuiSnapshot(snapshot)
        lastSnapshot = snapshot
        if index < count {
            usleep(120_000)
        }
    }
    exit(lastSnapshot?.isRunning == true ? 0 : 2)
}

if CommandLine.arguments.contains("--qishui-status") {
    let adapterSnapshot = MediaRemoteAdapterStreamSource().refreshOnce()
    print("PRIMARY_MEDIA_SOURCE")
    printMediaRemoteSnapshot(adapterSnapshot)
    print("")
    print("AX_FALLBACK_SOURCE")
    let snapshot = QishuiAdapter().snapshot()
    printQishuiSnapshot(snapshot)
    exit(adapterSnapshot.currentTrack != nil || snapshot.isRunning ? 0 : 2)
}

if CommandLine.arguments.contains("--qishui-lyric-status") {
    let mediaSnapshot = MediaRemoteAdapterStreamSource().refreshOnce()
    guard let track = mediaSnapshot.currentTrack,
          let processIdentifier = track.sourceProcessIdentifier else {
        print("QISHUI_LYRIC_STATUS unavailable=1")
        exit(2)
    }
    let identity = QishuiLyricIdentity(
        processIdentifier: processIdentifier,
        title: track.title,
        artist: track.artist
    )
    let reader = QishuiLyricReader()
    print("QISHUI_LYRIC_STATUS title=\(track.title) artist=\(track.artist) pid=\(processIdentifier)")
    for index in 1...6 {
        let snapshot = reader.read(identity: identity)
        print("READ[\(index)] desktop=\(snapshot.isDesktopSnapshot) lines=\(snapshot.lines)")
        if index < 6 { usleep(300_000) }
    }
    exit(0)
}

if CommandLine.arguments.contains("--qishui-timed-lyrics-status") {
    let snapshot = MediaRemoteAdapterStreamSource().refreshOnce()
    let probeArguments = CommandLine.arguments
    let probeIndex = probeArguments.firstIndex(of: "--qishui-timed-lyrics-status")!
    let override = probeArguments.indices.contains(probeIndex + 3)
        ? (title: probeArguments[probeIndex + 1],
           artist: probeArguments[probeIndex + 2],
           duration: Double(probeArguments[probeIndex + 3]))
        : nil
    guard let track = snapshot.currentTrack,
          let duration = override?.duration ?? track.duration else {
        print("TIMED_LYRICS_STATUS unavailable=1")
        exit(2)
    }
    let title = override?.title ?? track.title
    let artist = override?.artist ?? track.artist
    Task {
        print("TIMED_LYRICS_TRACK title=\(title) artist=\(artist) duration=\(duration)")
        let lines = await QishuiTimedLyricSource().fetch(
            title: title, artist: artist, duration: duration
        )
        var activeWords = 0
        var activeRange = "nil"
        if override == nil, let pid = track.sourceProcessIdentifier, !lines.isEmpty {
            let reader = QishuiLyricReader()
            let identity = QishuiLyricIdentity(processIdentifier: pid, title: title, artist: artist)
            _ = reader.read(identity: identity)
            let active = reader.read(identity: identity)
            if let current = active.lines.first {
                let matched = QishuiTimedLyricParser.words(for: current, at: track.elapsedTime, in: lines)
                activeWords = matched.count
                if let first = matched.first, let last = matched.last {
                    activeRange = String(format: "%.2f...%.2f", first.start, last.end)
                }
            }
        }
        if activeWords == 0,
           let elapsed = track.elapsedTime,
           let active = QishuiTimedLyricParser.activeLine(
               at: elapsed, in: lines, trackDuration: duration
           ),
           let first = active.current.words.first,
           let last = active.current.words.last {
            activeWords = active.current.words.count
            activeRange = String(format: "%.2f...%.2f", first.start, last.end)
        }
        print("TIMED_LYRICS_STATUS lines=\(lines.count) words=\(lines.reduce(0) { $0 + $1.words.count }) activeWords=\(activeWords) activeRange=\(activeRange) elapsed=\(track.elapsedTime.map { String(format: "%.2f", $0) } ?? "nil")")
        exit(lines.isEmpty ? 2 : 0)
    }
    dispatchMain()
}

if CommandLine.arguments.contains("--adapter-lyrics-status") {
    Task { @MainActor in
        let coordinator = MusicAdapterCoordinator()
        coordinator.setAppleMusicEnabled(false)
        coordinator.setQishuiTimedLyricsEnabled(true)
        var latest = coordinator.initialState
        var latestStatus: MusicSourceStatus?
        coordinator.startRealtimeObservation { state, status in
            latest = state
            latestStatus = status
        }
        for _ in 0..<16 {
            let result = coordinator.tick(latest)
            latest = result.music
            latestStatus = result.sourceStatus
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        let state = latest
        print("ADAPTER_LYRICS_STATUS title=\(state.track.title) artist=\(state.track.artist) source=\(state.track.sourceBundleIdentifier ?? "nil") lyrics=\(state.track.lyrics) index=\(state.lyricIndex) canSeek=\(state.canSeek) elapsed=\(state.elapsedTime.map(String.init(describing:)) ?? "nil") availability=\(latestStatus?.availability.rawValue ?? "nil") detail=\(latestStatus?.detail ?? "nil")")
        coordinator.stopRealtimeObservation()
        exit(state.track.lyrics.isEmpty ? 2 : 0)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(5))
    exit(2)
}

enum IslandMode: String {
    case collapsed
    case compact
    case expanded
}

enum IslandWindowLayout {
    static func size(
        for mode: IslandMode,
        collapsedWidth: CGFloat,
        compactWidth: CGFloat,
        expandedWidth: CGFloat,
        expandedHeight: CGFloat,
        topBandHeight: CGFloat
    ) -> NSSize {
        switch mode {
        case .collapsed:
            return NSSize(width: collapsedWidth, height: topBandHeight)
        case .compact:
            return NSSize(width: compactWidth, height: topBandHeight)
        case .expanded:
            return NSSize(width: expandedWidth, height: expandedHeight)
        }
    }

    static func frame(
        for size: NSSize,
        in screenFrame: NSRect,
        yOffset: CGFloat,
        anchorX: CGFloat? = nil,
        alignTopToWindowServer: Bool = false
    ) -> NSRect {
        let resolvedAnchorX = anchorX ?? screenFrame.midX
        let proposedTop = screenFrame.maxY - yOffset
        let top = alignTopToWindowServer ? proposedTop.rounded(.up) : proposedTop
        return NSRect(
            x: resolvedAnchorX - size.width / 2,
            y: top - size.height,
            width: size.width,
            height: size.height
        )
    }

    static func acceptsAnimationCompletion(
        completedAnimationID: Int,
        currentAnimationID: Int,
        targetMode: IslandMode,
        currentMode: IslandMode
    ) -> Bool {
        completedAnimationID == currentAnimationID && targetMode == currentMode
    }
}

struct IslandAnimationCompletionGate {
    private(set) var currentAnimationID = 0
    private var completedAnimationID: Int?

    mutating func beginAnimation() -> Int {
        currentAnimationID &+= 1
        completedAnimationID = nil
        return currentAnimationID
    }

    mutating func claimCompletion(
        animationID: Int,
        targetMode: IslandMode,
        currentMode: IslandMode
    ) -> Bool {
        guard completedAnimationID != animationID,
              IslandWindowLayout.acceptsAnimationCompletion(
                completedAnimationID: animationID,
                currentAnimationID: currentAnimationID,
                targetMode: targetMode,
                currentMode: currentMode
              ) else {
            return false
        }
        completedAnimationID = animationID
        return true
    }
}

struct IslandInteractionRegions: Equatable {
    let header: NSRect
    let body: NSRect?
    let bridge: NSRect?

    static func make(
        panelFrame: NSRect,
        mode: IslandMode,
        headerWidth: CGFloat,
        topBandHeight: CGFloat,
        expandedBodyHeight: CGFloat,
        expandedPanelTopGap: CGFloat
    ) -> IslandInteractionRegions {
        let header = NSRect(
            x: panelFrame.midX - headerWidth / 2,
            y: panelFrame.maxY - topBandHeight,
            width: headerWidth,
            height: topBandHeight
        )
        guard mode == .expanded else {
            return IslandInteractionRegions(header: header, body: nil, bridge: nil)
        }

        let body = NSRect(
            x: panelFrame.minX,
            y: panelFrame.minY,
            width: panelFrame.width,
            height: expandedBodyHeight
        )
        let bridgeHeight = max(
            0,
            min(expandedPanelTopGap, header.minY - body.maxY)
        )
        let bridge = bridgeHeight > 0
            ? NSRect(
                x: header.minX,
                y: body.maxY,
                width: header.width,
                height: bridgeHeight
            )
            : nil
        return IslandInteractionRegions(header: header, body: body, bridge: bridge)
    }

    func contains(_ point: CGPoint, tolerance: CGFloat = 0) -> Bool {
        let expandedHeader = header.insetBy(dx: -tolerance, dy: -tolerance)
        let expandedBody = body?.insetBy(dx: -tolerance, dy: -tolerance)
        let expandedBridge = bridge?.insetBy(dx: -tolerance, dy: -tolerance)
        return expandedHeader.contains(point)
            || expandedBody?.contains(point) == true
            || expandedBridge?.contains(point) == true
    }
}

enum IslandMotion {
    static func duration(for mode: IslandMode) -> TimeInterval {
        mode == .expanded ? 0.24 : 0.18
    }

    static func frameDuration(
        for mode: IslandMode,
        reduceMotion: Bool
    ) -> TimeInterval {
        reduceMotion ? 0 : duration(for: mode)
    }

    static func timingControlPoints(for mode: IslandMode) -> (Double, Double, Double, Double) {
        mode == .expanded ? (0.20, 0.85, 0.25, 1.0) : (0.40, 0.0, 0.20, 1.0)
    }

    static func geometryAnimation(
        for mode: IslandMode,
        reduceMotion: Bool
    ) -> Animation? {
        guard !reduceMotion else { return nil }
        let points = timingControlPoints(for: mode)
        return .timingCurve(points.0, points.1, points.2, points.3, duration: duration(for: mode))
    }

    static func featureContentAnimation(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? 0.04 : 0.10)
    }
}

enum ExpandedMusicLayout {
    // The lyric mode gives the reading surface the larger share of the
    // expanded island. Controls stay in a stable left rail so the lyric
    // viewport can grow without reflowing the playback buttons.
    static let controlContentWidth: CGFloat = 204
    static let controlOnlyContentWidth: CGFloat = controlContentWidth + controlToLyricSpacing + detailsWidth
    static let controlSurfacePadding: CGFloat = 0
    // The lyric state is intentionally wider than the control-only state.
    // This keeps the cover/controls rail stable and gives the lyric viewport
    // enough room to scroll long lines without shrinking the type.
    static let contentWidth: CGFloat = controlContentWidth + controlToLyricSpacing + lyricColumnWidth
    static let artworkSize: CGFloat = 76
    static let artworkToDetailsSpacing: CGFloat = 10
    static let detailsWidth: CGFloat = 248
    static let lyricColumnWidth: CGFloat = 446
    static let controlToLyricSpacing: CGFloat = 12
    static let timelineWidth: CGFloat = 164
    static let timelineToTimeSpacing: CGFloat = 10
    static let timeWidth: CGFloat = 74
    static let lyricTimelineWidth: CGFloat = 306
    static let controlRailWidth: CGFloat = timelineWidth
    static let modeButtonsWidth: CGFloat = 56
    static let titleToModeButtonsSpacing: CGFloat = 12
    static let titleWidth: CGFloat = detailsWidth
        - modeButtonsWidth
        - titleToModeButtonsSpacing

    static var controlColumnWidth: CGFloat {
        controlContentWidth + controlSurfacePadding * 2
    }
}

enum IslandDisplayRefreshPolicy {
    static let stabilizationDelaysNanoseconds: [UInt64] = [
        150_000_000,
        500_000_000
    ]
}

enum IslandFeature: String, Hashable {
    case activityCenter
    case music
    case timer
    case notification

    var iconName: String {
        switch self {
        case .activityCenter:
            return "square.grid.2x2.fill"
        case .music:
            return "music.note"
        case .timer:
            return "timer"
        case .notification:
            return "bell"
        }
    }

}

enum IslandExpansionPolicy {
    static func allowsExpansion(
        activeFeature: IslandFeature,
        hasCurrentMusicTrack: Bool,
        hasPendingNotification: Bool
    ) -> Bool {
        switch activeFeature {
        case .activityCenter:
            return false
        case .music:
            return hasCurrentMusicTrack
        case .timer:
            return true
        case .notification:
            return hasPendingNotification
        }
    }
}

struct IslandPresentationDestination: Equatable {
    let feature: IslandFeature
    let mode: IslandMode
}

enum CollapsedIslandTapPolicy {
    static func destination(
        activeFeature: IslandFeature,
        hasCurrentMusicTrack: Bool,
        musicControlsAvailable: Bool = true,
        hasPendingNotification: Bool
    ) -> IslandPresentationDestination {
        let canPresentMusic = hasCurrentMusicTrack && musicControlsAvailable
        switch activeFeature {
        case .activityCenter:
            return canPresentMusic
                ? IslandPresentationDestination(feature: .music, mode: .compact)
                : IslandPresentationDestination(feature: .activityCenter, mode: .expanded)
        case .music:
            return canPresentMusic
                ? IslandPresentationDestination(feature: .music, mode: .compact)
                : IslandPresentationDestination(feature: .activityCenter, mode: .expanded)
        case .timer:
            return IslandPresentationDestination(feature: .timer, mode: .compact)
        case .notification:
            return hasPendingNotification
                ? IslandPresentationDestination(feature: .notification, mode: .compact)
                : IslandPresentationDestination(feature: .activityCenter, mode: .expanded)
        }
    }
}

enum MusicActivityPresentationPolicy {
    static func controlsAvailable(
        canPlayPause: Bool,
        canPreviousTrack: Bool,
        canNextTrack: Bool
    ) -> Bool {
        canPlayPause || canPreviousTrack || canNextTrack
    }
}

enum MusicActivityTakeoverPolicy {
    static func shouldTakeOver(
        activeFeature: IslandFeature,
        becameAvailable: Bool,
        timerIsRunning: Bool,
        hasPendingNotification: Bool
    ) -> Bool {
        activeFeature == .activityCenter
            && becameAvailable
            && !timerIsRunning
            && !hasPendingNotification
    }
}

enum MusicPresentationTransitionPolicy {
    static func shouldPromoteToCompact(
        activeFeature: IslandFeature,
        currentMode: IslandMode,
        isArmed: Bool,
        hadCurrentTrack: Bool,
        hasCurrentTrack: Bool,
        hasPendingNotification: Bool
    ) -> Bool {
        activeFeature == .music
            && currentMode == .collapsed
            && isArmed
            && !hadCurrentTrack
            && hasCurrentTrack
            && !hasPendingNotification
    }

    static func shouldDisarmForUserRequest(_ targetMode: IslandMode) -> Bool {
        targetMode == .collapsed
    }

    static func shouldResetToDefaultAfterAllSourcesExit(
        currentMode: IslandMode
    ) -> Bool {
        currentMode != .collapsed
    }
}

struct MusicTrack: Equatable {
    let title: String
    let artist: String
    let palette: [Color]
    let lyrics: [String]
    let hasArtwork: Bool
    let artworkData: Data?
    let artworkURL: URL?
    let sourceBundleIdentifier: String?
    var lyricsAreDesktopSnapshot: Bool = false
    var timedWords: [QishuiTimedWord] = []
}

struct MusicState: Equatable {
    var track: MusicTrack
    var isPlaying: Bool
    var progress: Double
    var lyricIndex: Int
    var elapsedTime: TimeInterval? = nil
    var duration: TimeInterval? = nil
    var canSeek: Bool = false
    var isPlaybackPending: Bool = false
    var canPlayPause: Bool = true
    var canPreviousTrack: Bool = true
    var canNextTrack: Bool = true
    var controlUnavailableReason: String? = nil
    var controlRecoveryAction: MusicControlRecoveryAction? = nil
    var hasCurrentTrack: Bool
    // Some direct adapters can provide a track before they can prove play/pause.
    // Keep that distinction so the UI never presents a guessed one-way action.
    var playbackStateKnown: Bool = true
}

enum MusicUpdatePolicy {
    static func didChangeSource(current: MusicState, candidate: MusicState) -> Bool {
        current.track.sourceBundleIdentifier
            != candidate.track.sourceBundleIdentifier
    }

    static func shouldIgnoreUntrustedProgressReset(
        current: MusicState,
        candidate: MusicState,
        sourceAvailability: MusicSourceAvailability?
    ) -> Bool {
        if sourceAvailability == .qishuiNotRunning {
            return false
        }
        guard current.track.sourceBundleIdentifier
            == candidate.track.sourceBundleIdentifier else {
            return false
        }
        guard candidate.hasCurrentTrack else {
            return false
        }
        guard current.duration != nil,
              current.elapsedTime != nil,
              current.progress > 0.01 else {
            return false
        }

        let candidateHasTrustedTiming = candidate.duration != nil
            && candidate.elapsedTime != nil
        guard !candidateHasTrustedTiming,
              candidate.progress <= 0.0001,
              !candidate.canSeek else {
            return false
        }

        return !candidate.track.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }
}

struct TimerState: Equatable {
    var duration: Int
    var remaining: Int
    var isRunning: Bool

    var progress: Double {
        guard duration > 0 else { return 0 }
        return Double(duration - remaining) / Double(duration)
    }
}

enum FocusTimerPreset: Int, CaseIterable, Identifiable {
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case twentyFiveMinutes = 25
    case fortyFiveMinutes = 45

    var id: Int { rawValue }
    var title: String { "\(rawValue) 分钟" }
    var compactTitle: String { "\(rawValue) 分" }
    var durationSeconds: Int { rawValue * 60 }
}

enum IslandActivityReturnPolicy {
    static func featureAfterNotification(
        returnFeature: IslandFeature?,
        timerIsRunning: Bool,
        hasCurrentMusicTrack: Bool
    ) -> IslandFeature {
        if returnFeature == .timer, timerIsRunning {
            return .timer
        }
        return hasCurrentMusicTrack ? .music : .activityCenter
    }
}

struct IslandNotification: Equatable {
    var title: String
    var body: String
    var source: String
    var count: Int
}

private enum IslandEventPriority: Int {
    case normal
    case urgent
}

private struct PendingIslandEvent: Equatable {
    var title: String
    var body: String
    var source: String
    let priority: IslandEventPriority
    let autoDismiss: Bool
    var count: Int
    let mergeIdentifier: String?
    var sourceBundleIdentifier: String?
}

private struct PendingMusicSeek {
    let trackSignature: String
    let sourceBundleIdentifier: String?
    let targetProgress: Double
    let requestedAt: Date
    let issuedAt: Date
    let isPlaying: Bool
    let expiresAt: Date
    var matchingSince: Date?
}

struct ArtworkAccentComponents: Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var relativeLuminance: Double {
        func linearized(_ component: Double) -> Double {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return linearized(red) * 0.2126
            + linearized(green) * 0.7152
            + linearized(blue) * 0.0722
    }
}

enum ArtworkAccentTransitionPolicy {
    static let missingArtworkGraceNanoseconds: UInt64 = 650_000_000

    static func shouldDelayNeutralFallback(hasCurrentTrack: Bool) -> Bool {
        hasCurrentTrack
    }
}

func artworkAccentComponents(from data: Data) -> ArtworkAccentComponents? {
    let sourceOptions = [
        kCGImageSourceShouldCache: false
    ] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
        return nil
    }
    let thumbnailOptions = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: 32,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true
    ] as CFDictionary
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
        return nil
    }

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let width = thumbnail.width
    let height = thumbnail.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
        guard let baseAddress = bytes.baseAddress,
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
              ) else { return false }
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard rendered else { return nil }

    var redTotal = 0.0
    var greenTotal = 0.0
    var blueTotal = 0.0
    var sampleCount = 0
    var hueCounts = [Int](repeating: 0, count: 12)
    var hueRed = [Double](repeating: 0, count: 12)
    var hueGreen = [Double](repeating: 0, count: 12)
    var hueBlue = [Double](repeating: 0, count: 12)
    var chromaticCount = 0
    for offset in stride(from: 0, to: pixels.count, by: 4) {
        let alpha = Double(pixels[offset + 3])
        guard alpha > 20 else { continue }
        let unpremultiply = 255 / alpha
        let red = min(Double(pixels[offset]) * unpremultiply, 255) / 255
        let green = min(Double(pixels[offset + 1]) * unpremultiply, 255) / 255
        let blue = min(Double(pixels[offset + 2]) * unpremultiply, 255) / 255
        redTotal += red
        greenTotal += green
        blueTotal += blue
        sampleCount += 1
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        guard maximum > 0.18, delta / maximum > 0.22 else { continue }
        let hue: Double
        if maximum == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            hue = ((blue - red) / delta) + 2
        } else {
            hue = ((red - green) / delta) + 4
        }
        let unitHue = (hue / 6 + 1).truncatingRemainder(dividingBy: 1)
        let bin = min(Int(unitHue * 12), 11)
        hueCounts[bin] += 1
        hueRed[bin] += red
        hueGreen[bin] += green
        hueBlue[bin] += blue
        chromaticCount += 1
    }
    guard sampleCount > 0 else { return nil }
    if let peak = hueCounts.indices.max(by: { hueCounts[$0] < hueCounts[$1] }),
       chromaticCount >= sampleCount / 8,
       hueCounts[peak] >= max(chromaticCount / 4, sampleCount / 12) {
        let neighbors = [(peak + 11) % 12, peak, (peak + 1) % 12]
        let count = neighbors.reduce(0) { $0 + hueCounts[$1] }
        if count > 0 {
            return normalizedArtworkAccent(
                red: neighbors.reduce(0) { $0 + hueRed[$1] } / Double(count),
                green: neighbors.reduce(0) { $0 + hueGreen[$1] } / Double(count),
                blue: neighbors.reduce(0) { $0 + hueBlue[$1] } / Double(count)
            )
        }
    }
    return normalizedArtworkAccent(
        red: redTotal / Double(sampleCount),
        green: greenTotal / Double(sampleCount),
        blue: blueTotal / Double(sampleCount)
    )
}

private func normalizedArtworkAccent(
    red: Double,
    green: Double,
    blue: Double
) -> ArtworkAccentComponents {
    let maximum = max(red, green, blue)
    let minimum = min(red, green, blue)
    let delta = maximum - minimum
    guard maximum > 0, delta / maximum >= 0.12 else {
        return artworkAccentWithBlackBackgroundContrast(
            ArtworkAccentComponents(red: 0.86, green: 0.86, blue: 0.86)
        )
    }

    var hue: Double
    if maximum == red {
        hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
    } else if maximum == green {
        hue = ((blue - red) / delta) + 2
    } else {
        hue = ((red - green) / delta) + 4
    }
    hue /= 6
    if hue < 0 { hue += 1 }

    var saturation = min(max(delta / maximum, 0.25), 0.70)
    if (0.06...0.13).contains(hue) || (0.22...0.45).contains(hue) {
        saturation = min(saturation, 0.40)
    }
    let brightness = min(max(maximum, 0.63), 0.90)
    return artworkAccentWithBlackBackgroundContrast(
        rgbComponents(hue: hue, saturation: saturation, brightness: brightness)
    )
}

private func artworkAccentWithBlackBackgroundContrast(
    _ accent: ArtworkAccentComponents
) -> ArtworkAccentComponents {
    if accent.relativeLuminance > 0.52 {
        var lower = 0.0
        var upper = 1.0
        var result = accent
        for _ in 0..<14 {
            let scale = (lower + upper) / 2
            let candidate = ArtworkAccentComponents(
                red: accent.red * scale,
                green: accent.green * scale,
                blue: accent.blue * scale
            )
            if candidate.relativeLuminance > 0.52 {
                upper = scale
            } else {
                result = candidate
                lower = scale
            }
        }
        return result
    }
    guard accent.relativeLuminance < 0.20 else { return accent }
    var lower = 0.0
    var upper = 1.0
    var result = accent
    for _ in 0..<14 {
        let amount = (lower + upper) / 2
        let candidate = ArtworkAccentComponents(
            red: accent.red + (1 - accent.red) * amount,
            green: accent.green + (1 - accent.green) * amount,
            blue: accent.blue + (1 - accent.blue) * amount
        )
        if candidate.relativeLuminance >= 0.20 {
            result = candidate
            upper = amount
        } else {
            lower = amount
        }
    }
    return result
}

private func rgbComponents(
    hue: Double,
    saturation: Double,
    brightness: Double
) -> ArtworkAccentComponents {
    let scaledHue = hue * 6
    let sector = Int(floor(scaledHue)) % 6
    let fraction = scaledHue - floor(scaledHue)
    let p = brightness * (1 - saturation)
    let q = brightness * (1 - fraction * saturation)
    let t = brightness * (1 - (1 - fraction) * saturation)
    switch sector {
    case 0: return ArtworkAccentComponents(red: brightness, green: t, blue: p)
    case 1: return ArtworkAccentComponents(red: q, green: brightness, blue: p)
    case 2: return ArtworkAccentComponents(red: p, green: brightness, blue: t)
    case 3: return ArtworkAccentComponents(red: p, green: q, blue: brightness)
    case 4: return ArtworkAccentComponents(red: t, green: p, blue: brightness)
    default: return ArtworkAccentComponents(red: brightness, green: p, blue: q)
    }
}

@MainActor
final class IslandModel: ObservableObject {
    let isPreviewPresentation: Bool
    // Interaction ownership is independent of mode changes: pressing a control
    // in a hover-expanded panel must also cancel the pending hover return.
    let presentationInteraction = PassthroughSubject<Void, Never>()
    @Published var mode: IslandMode = .collapsed
    @Published var activeFeature: IslandFeature = .activityCenter
    @Published var notchWidth: CGFloat = 185
    @Published var topBandHeight: CGFloat = 33
    @Published var hasCameraHousing = true
    let appSettings = AppSettings()
    let loginItemSettings = LoginItemSettings()
    let layout = LayoutCalibrationSettings()
    @Published var music: MusicState
    @Published var musicAccentColor = Color.white
    @Published var pendingTrackControl: MusicControlCommand?
    @Published private(set) var trackControlFeedbackGeneration: UInt64 = 0
    @Published private(set) var playPauseFeedbackGeneration: UInt64 = 0
    @Published private(set) var isRecoveringMusicControl = false
    @Published private(set) var musicControlRecoveryNeedsUserAction = false
    @Published private(set) var latestMusicControlRecoverySummary = "未触发"
    @Published var musicSourceStatus = MusicSourceStatus(
        sourceName: "汽水音乐",
        availability: .preview,
        headline: "等待汽水音乐真实数据",
        detail: "当前不显示假歌曲；主线正在直接读取汽水音乐本地状态，系统播放信息仅保留为手动诊断。",
        checkedAt: Date()
    )
    @Published private(set) var qishuiIsRunning = false
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var neteaseMusicIsRunning = false
    @Published private(set) var neteaseMusicSnapshotAvailability: MusicAppAvailability?
    @Published private(set) var neteaseMusicConnectionStatus = "尚未检查"
    @Published private(set) var neteaseMusicAvailableControls = "无"
    @Published private(set) var appleMusicAutomationAccess: AppleMusicAutomationAccess = .unavailable(status: -1)
    @Published private(set) var appleMusicIsRunning = false
    @Published private(set) var appleMusicSnapshotAvailability: MusicAppAvailability?
    @Published private(set) var appleMusicConnectionStatus = "尚未检查"
    @Published private(set) var appleMusicAvailableControls = "无"
    @Published private(set) var appleMusicResponseLatencyMilliseconds: Int?
    @Published var timerState = TimerState(duration: 25 * 60, remaining: 25 * 60, isRunning: false)
    var musicTimelineSampledAt = Date()
    @Published var notification = IslandNotification(
        title: "",
        body: "",
        source: "顶屿",
        count: 0
    )
    @Published var eventKitStatus = EventKitActivityStatus.current
    @Published var isVisible = true
    @Published private(set) var reduceMotionEnabled = NSWorkspace.shared
        .accessibilityDisplayShouldReduceMotion

    var appleMusicTransitionDiagnostic: String {
        musicAdapter.appleMusicTransitionReport()
    }

    var latestAppleMusicTransitionDiagnostic: String {
        musicAdapter.latestAppleMusicTransitionReport()
    }

    private let musicAdapter = MusicAdapterCoordinator()
    private let eventKitSource = EventKitActivitySource()
    private var ticker: Timer?
    private var musicRefreshBurstTask: Task<Void, Never>?
    private var musicControlRecoveryTask: Task<Void, Never>?
    private var musicControlRecoveryAwaitingVerification = false
    private var musicAccentTask: Task<Void, Never>?
    private var musicAccentIdentity = ""
    private var musicAccentGeneration = 0
    private var trackControlFeedbackTask: Task<Void, Never>?
    private var pendingTrackControlBaselineSignature: String?
    private var pendingTrackControlGeneration: UInt64?
    private var pendingTrackControlChainCount = 0
    private var layoutCancellable: AnyCancellable?
    private var appleMusicSettingsCancellable: AnyCancellable?
    private var musicLyricsSettingsCancellable: AnyCancellable?
    private var eventKitSettingsCancellable: AnyCancellable?
    private var appleMusicObservedProcessIdentifier: pid_t?
    private var appleMusicSettingsRequestGeneration: UInt64 = 0
    private var neteaseMusicObservedProcessIdentifier: pid_t?
    private var neteaseMusicSettingsRequestGeneration: UInt64 = 0
    private var lastTimerUpdateAt: Date?
    private var lastIslandModeTapAt: Date = .distantPast
    private var lastDirectControlAt: Date = .distantPast
    private var lastMusicProgressPublishAt: Date = .distantPast
    private var autoCompactOnNextMusicTrack = true
    private var isUserExpandedMusicPresentation = false
    private var musicSeekRequestID = 0
    private var pendingMusicSeek: PendingMusicSeek?
    private var isMusicScrubbing = false
    private var notificationPresentationTask: Task<Void, Never>?
    private var notificationReturnFeature: IslandFeature?
    private var notificationReturnMode: IslandMode?
    private var notificationPresentedMode: IslandMode?
    private var activeIslandEvent: PendingIslandEvent?
    private var pendingIslandEvents: [PendingIslandEvent] = []
    private var shouldResumeInterruptedNormalEvent = false
    private var notificationGeneration = 0
    private let islandModeTapCooldown: TimeInterval = 0.08
    private let directControlSuppressionWindow: TimeInterval = 0.06
    private let musicProgressPublishInterval: TimeInterval = 0.45

    // Keep the music glyph and activity waveform clear of the camera housing
    // while returning a little more menu-bar space to the system on both sides.
    var collapsedWingWidth: CGFloat { 22 }
    var compactWingWidth: CGFloat {
        MusicCompactLayout.standardWingWidth
    }
    var compactLeadingWingWidth: CGFloat {
        MusicCompactLayout.standardWingWidth
    }
    var compactTrailingWingWidth: CGFloat {
        MusicCompactLayout.standardWingWidth
    }
    var expandedHeaderWingWidth: CGFloat { 34 }

    private var hasCurrentDisplayableLyric: Bool {
        guard activeFeature == .music else { return false }
        return MusicLyricPresentation.state(
            lines: music.track.lyrics,
            index: music.lyricIndex,
            pairMixedLanguageLines: !music.track.lyricsAreDesktopSnapshot
        ).isAvailable
    }

    var isMusicLyricsEnabled: Bool {
        CommandLine.arguments.contains("--preview-lyrics") || appSettings.showMusicLyrics
    }
    var hasPendingNotification: Bool {
        activeIslandEvent != nil || !pendingIslandEvents.isEmpty
    }

    var canExpandIsland: Bool {
        IslandExpansionPolicy.allowsExpansion(
            activeFeature: activeFeature,
            hasCurrentMusicTrack: music.hasCurrentTrack,
            hasPendingNotification: hasPendingNotification
        )
    }

    var canRecoverCurrentMusicControlPermission: Bool {
        MusicControlPermissionRecoveryPolicy.allowsRecovery(
            sourceBundleIdentifier: music.track.sourceBundleIdentifier,
            accessibilityTrusted: accessibilityTrusted
        )
    }

    var shouldPresentMusicControlRecovery: Bool {
        MusicControlRecoveryPolicy.shouldPresentRecovery(
            isRecovering: isRecoveringMusicControl,
            hasRecoveryAction: music.controlRecoveryAction != nil
        )
    }

    var musicControlsAvailable: Bool {
        MusicActivityPresentationPolicy.controlsAvailable(
            canPlayPause: music.canPlayPause,
            canPreviousTrack: music.canPreviousTrack,
            canNextTrack: music.canNextTrack
        )
    }

    var collapsedWidth: CGFloat {
        notchWidth + collapsedWingWidth * 2
    }

    var compactWidth: CGFloat {
        MusicCompactLayout.compactWidth(
            notchWidth: notchWidth,
            hasCurrentLyric: false
        )
    }

    var expandedWidth: CGFloat {
        switch activeFeature {
        case .activityCenter:
            return max(notchWidth + 140, 420)
        case .music:
            let lyricWidth = isMusicLyricsEnabled && hasCurrentDisplayableLyric
                ? ExpandedMusicLayout.contentWidth + 32
                : ExpandedMusicLayout.controlOnlyContentWidth + 32
            return max(notchWidth + 160, lyricWidth)
        case .timer, .notification:
            return max(notchWidth + 140, 420)
        }
    }

    var expandedHeight: CGFloat {
        // Music expansion is a single surface. The old control-only branch
        // reserved a separate notch header above the player body, which made
        // the app render as two stacked black islands. Keep the header for
        // non-music expanded features, but let every expanded music state
        // own the full window with one capsule.
        if activeFeature == .music {
            return expandedBodyHeight
        }
        return topBandHeight + expandedPanelTopGap + expandedBodyHeight
    }

    var expandedHeaderWidth: CGFloat {
        notchWidth + expandedHeaderWingWidth * 2
    }

    var currentHeaderWidth: CGFloat {
        switch mode {
        case .collapsed:
            return collapsedWidth
        case .compact:
            return compactWidth
        case .expanded:
            return activeFeature == .music ? expandedWidth : expandedHeaderWidth
        }
    }

    var statusWaveIsActive: Bool {
        switch activeFeature {
        case .activityCenter:
            return false
        case .music:
            return music.isPlaying
        case .timer:
            return timerState.isRunning
        case .notification:
            return false
        }
    }

    var statusWaveColor: Color {
        activeFeature == .music ? musicAccentColor : .white
    }

    var expandedPanelTopGap: CGFloat {
        (activeFeature == .music || isLyricExpandedPresentation) ? 0 : 8
    }

    /// Expanded music uses one horizontal capsule for both the control-only
    /// and lyric presentations. This is independent of lyric availability:
    /// a track without lyrics must not reintroduce the detached notch header.
    var usesUnifiedMusicExpandedSurface: Bool {
        mode == .expanded && activeFeature == .music
    }

    var isLyricExpandedPresentation: Bool {
        mode == .expanded && activeFeature == .music
            && isMusicLyricsEnabled
            && hasCurrentDisplayableLyric
    }

    var expandedBodyHeight: CGFloat {
        switch activeFeature {
        case .activityCenter:
            return max(112, (shouldPresentMusicControlRecovery ? 210 : 168)
                + CGFloat(layout.expandedHeightAdjustment))
        case .music:
            // Keep the height policy shared with the lyric-width/state
            // transaction. When lyrics arrive after expansion, the AppKit
            // observer uses this same value to grow the window before the
            // shelf is painted, avoiding a clipped bottom edge.
            return topBandHeight + MusicExpandedLayout.bodyHeight(
                lines: isMusicLyricsEnabled ? music.track.lyrics : [],
                heightAdjustment: CGFloat(layout.expandedHeightAdjustment)
            )
        case .timer:
            return max(112, 146 + CGFloat(layout.expandedHeightAdjustment))
        case .notification:
            return max(112, 156 + CGFloat(layout.expandedHeightAdjustment))
        }
    }

    init() {
        let arguments = CommandLine.arguments
        isPreviewPresentation = arguments.contains("--preview-mode")
            || arguments.contains("--preview-feature")
            || arguments.contains("--preview-lyrics")
            || arguments.contains("--preview-no-lyrics")
        isVisible = isPreviewPresentation || appSettings.showIslandOnLaunch
        musicAdapter.setAppleMusicEnabled(appSettings.appleMusicEnabled)
        musicAdapter.setQishuiTimedLyricsEnabled(appSettings.showMusicLyrics)
        music = musicAdapter.initialState
        activeFeature = music.hasCurrentTrack ? .music : .activityCenter
        pendingTrackControl = nil
        if arguments.contains("--preview-lyrics") || arguments.contains("--preview-no-lyrics") {
            // Explicit visual QA fixture. It is only admitted when the
            // caller opts into preview mode and never enters the live adapter.
            let previewArtwork: Data? = {
                guard let index = arguments.firstIndex(of: "--preview-artwork"),
                      arguments.indices.contains(index + 1) else { return nil }
                return try? Data(contentsOf: URL(fileURLWithPath: arguments[index + 1]))
            }()
            let previewLyrics = arguments.contains("--preview-short-lyrics")
                ? ["Can you see it", "你是否能够看清", "Every weekend in the rave"]
                : ["Pull me through the night, I am still awake",
                   "把我带过漫长的夜，我还没有睡去",
                   "Every little heartbeat finds a way to break",
                   "每一次心跳都在寻找出口"]
            music = MusicState(
                track: MusicTrack(
                    title: arguments.contains("--preview-short-lyrics") ? "Can you see it" : "Pull Me Through The Night",
                    artist: "Matisse / Sadko, James French",
                    palette: [Color(red: 0.18, green: 0.30, blue: 0.36), Color(red: 0.05, green: 0.10, blue: 0.13)],
                    lyrics: arguments.contains("--preview-no-lyrics") ? [] : previewLyrics,
                    hasArtwork: previewArtwork != nil,
                    artworkData: previewArtwork,
                    artworkURL: nil,
                    sourceBundleIdentifier: "preview.topislet",
                    lyricsAreDesktopSnapshot: false
                ),
                isPlaying: true,
                progress: 0.42,
                lyricIndex: 0,
                elapsedTime: 96,
                duration: 228,
                canSeek: true,
                canPlayPause: true,
                canPreviousTrack: true,
                canNextTrack: true,
                hasCurrentTrack: true,
                playbackStateKnown: true
            )
            activeFeature = .music
        }
        if let previewModeIndex = arguments.firstIndex(of: "--preview-mode"),
           arguments.indices.contains(previewModeIndex + 1),
           let previewMode = IslandMode(rawValue: arguments[previewModeIndex + 1]) {
            mode = previewMode
        }
        if let previewFeatureIndex = arguments.firstIndex(of: "--preview-feature"),
           arguments.indices.contains(previewFeatureIndex + 1),
           let previewFeature = IslandFeature(rawValue: arguments[previewFeatureIndex + 1]) {
            activeFeature = previewFeature
        }
        layoutCancellable = layout.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        startTicker()
        guard !isPreviewPresentation else { return }

        refreshMusicIntegrationStatus()
        musicSourceStatus = musicAdapter.refreshSourceStatus(allowSynchronousRefresh: true)
        musicAdapter.startRealtimeObservation { [weak self] music, status in
            self?.applyMusicUpdate(music, status: status)
        }
        eventKitSource.start(
            calendarEnabled: appSettings.calendarEventsEnabled,
            remindersEnabled: appSettings.remindersEnabled,
            onEvent: { [weak self] event in
                self?.receiveEventKitEvent(event)
            },
            onCancel: { [weak self] identifier in
                self?.cancelNotification(mergeIdentifier: identifier)
            },
            onStatus: { [weak self] status in
                self?.eventKitStatus = status
            }
        )
        eventKitSettingsCancellable = Publishers.CombineLatest(
            appSettings.$calendarEventsEnabled,
            appSettings.$remindersEnabled
        )
        .dropFirst()
        .sink { [weak self] calendarEnabled, remindersEnabled in
            self?.eventKitSource.update(
                calendarEnabled: calendarEnabled,
                remindersEnabled: remindersEnabled
            )
        }
        appleMusicSettingsCancellable = appSettings.$appleMusicEnabled
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                self.musicAdapter.setAppleMusicEnabled(enabled)
                self.refreshMusicIntegrationStatus()
                guard enabled,
                      self.appleMusicIsRunning,
                      self.appleMusicAutomationAccess == .allowed else { return }
                Task { [weak self] in
                    await self?.refreshAppleMusicSnapshot()
                }
            }

        musicLyricsSettingsCancellable = appSettings.$showMusicLyrics
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                self.musicAdapter.setQishuiTimedLyricsEnabled(enabled)
                guard self.activeFeature == .music else { return }
                if enabled, self.music.hasCurrentTrack {
                    self.requestIslandMode(.expanded, bypassCooldown: true, userInitiated: false)
                } else if !enabled, self.mode == .expanded {
                    self.requestIslandMode(.compact, bypassCooldown: true, userInitiated: false)
                }
            }
    }

    func toggleVisibility() {
        isVisible.toggle()
    }

    func showFeature(_ feature: IslandFeature, mode newMode: IslandMode = .expanded) {
        if activeFeature == .notification, feature != .notification {
            clearNotificationPresentation()
        }
        if feature == .music {
            isUserExpandedMusicPresentation = newMode == .expanded
            if MusicPresentationTransitionPolicy.shouldDisarmForUserRequest(newMode) {
                autoCompactOnNextMusicTrack = false
            }
        }
        activeFeature = feature
        mode = newMode
    }

    func toggleCollapsed() {
        requestIslandMode(mode == .collapsed ? .compact : .collapsed)
    }

    func toggleExpanded() {
        requestIslandMode(mode == .expanded ? .compact : .expanded)
    }

    func handleCollapsedIslandTap() {
        let destination = CollapsedIslandTapPolicy.destination(
            activeFeature: activeFeature,
            hasCurrentMusicTrack: music.hasCurrentTrack,
            musicControlsAvailable: musicControlsAvailable,
            hasPendingNotification: hasPendingNotification
        )
        showFeature(destination.feature, mode: destination.mode)
    }

    func collapseExpandedPresentation() {
        requestIslandMode(
            activeFeature == .activityCenter ? .collapsed : .compact,
            bypassCooldown: true
        )
    }

    func requestIslandMode(
        _ targetMode: IslandMode,
        bypassCooldown: Bool = false,
        userInitiated: Bool = true
    ) {
        if userInitiated { notePresentationInteraction() }
        let now = Date()
        if !bypassCooldown {
            guard now.timeIntervalSince(lastDirectControlAt) > directControlSuppressionWindow else { return }
            guard now.timeIntervalSince(lastIslandModeTapAt) > islandModeTapCooldown else { return }
        }
        if userInitiated, activeFeature == .music {
            isUserExpandedMusicPresentation = targetMode == .expanded
            if MusicPresentationTransitionPolicy.shouldDisarmForUserRequest(targetMode) {
                autoCompactOnNextMusicTrack = false
            }
        }
        guard mode != targetMode else { return }
        lastIslandModeTapAt = now
        mode = targetMode
    }

    private func refreshDisplayedMusicFromAdapter() {
        let update = musicAdapter.refreshPlaybackPositionNow()
        applyMusicUpdate(update.music, status: update.status, forceMusic: true)
    }

    private func noteDirectControlInteraction() {
        notePresentationInteraction()
        lastDirectControlAt = Date()
    }

    func notePresentationInteraction() {
        if activeFeature == .music, mode == .expanded {
            isUserExpandedMusicPresentation = true
            autoCompactOnNextMusicTrack = false
        }
        presentationInteraction.send()
    }

    private func beginTrackControlFeedback(
        _ command: MusicControlCommand,
        baselineSignature: String
    ) -> UInt64 {
        trackControlFeedbackGeneration &+= 1
        let generation = trackControlFeedbackGeneration
        pendingTrackControlChainCount = pendingTrackControl == nil
            ? 1
            : pendingTrackControlChainCount + 1
        pendingTrackControl = command
        pendingTrackControlBaselineSignature = baselineSignature
        pendingTrackControlGeneration = generation
        trackControlFeedbackTask?.cancel()
        let feedbackDuration: UInt64 = pendingTrackControlChainCount > 1
            ? 520_000_000
            : 1_200_000_000
        trackControlFeedbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: feedbackDuration)
            guard !Task.isCancelled, let self,
                  pendingTrackControl == command,
                  pendingTrackControlGeneration == generation else { return }
            finishTrackControlFeedback(command, generation: generation)
        }
        return generation
    }

    private func finishTrackControlFeedback(
        _ command: MusicControlCommand,
        generation: UInt64? = nil
    ) {
        guard pendingTrackControl == command else { return }
        if let generation {
            guard pendingTrackControlGeneration == generation else { return }
        }
        pendingTrackControl = nil
        pendingTrackControlBaselineSignature = nil
        pendingTrackControlGeneration = nil
        pendingTrackControlChainCount = 0
        trackControlFeedbackTask?.cancel()
        trackControlFeedbackTask = nil
    }

    func playPause() {
        guard music.canPlayPause else {
            requestCurrentMusicControlPermissionIfNeeded()
            return
        }
        noteDirectControlInteraction()
        playPauseFeedbackGeneration &+= 1
        let previousSignature = musicSignature(music)
        let displayedSourceBundleIdentifier = music.track.sourceBundleIdentifier
        activeFeature = .music
        if mode == .collapsed {
            mode = .compact
        }
        Task { [weak self] in
            guard let self else { return }
            let outcome = await musicAdapter.performControl(
                .playPause,
                displayedSourceBundleIdentifier: displayedSourceBundleIdentifier
            )
            guard music.track.sourceBundleIdentifier
                == displayedSourceBundleIdentifier else { return }
            musicSourceStatus = outcome.status
            if !outcome.didSendCommand, music.controlRecoveryAction != nil {
                musicControlRecoveryNeedsUserAction = true
            }
            if outcome.didSendCommand {
                applyMusicUpdate(musicAdapter.currentState(), status: outcome.status, forceMusic: true)
                startMusicControlRefreshBurst(previousSignature: previousSignature, requireTrackChange: false)
            } else if outcome.shouldAdvancePreview {
                applyMusicUpdate(musicAdapter.playPause(music), status: outcome.status, forceMusic: true)
            }
        }
    }

    func recoverCurrentMusicControl() {
        guard music.controlRecoveryAction == .reopenQishuiWindow,
              MusicControlRecoveryPolicy.shouldOpenApplication(for: .userInitiated) else { return }
        latestMusicControlRecoverySummary = "用户触发连接：\(music.controlUnavailableReason ?? "原因未知")"
        reopenQishuiWindow()
    }

    func nextTrack() {
        guard music.canNextTrack else {
            requestCurrentMusicControlPermissionIfNeeded()
            return
        }
        noteDirectControlInteraction()
        cancelPendingMusicSeek(reason: .superseded)
        let previousSignature = musicSignature(music)
        let displayedSourceBundleIdentifier = music.track.sourceBundleIdentifier
        let feedbackGeneration = beginTrackControlFeedback(
            .nextTrack,
            baselineSignature: previousSignature
        )
        activeFeature = .music
        if mode == .collapsed {
            mode = .compact
        }
        Task { [weak self] in
            guard let self else { return }
            let outcome = await musicAdapter.performControl(
                .nextTrack,
                displayedSourceBundleIdentifier: displayedSourceBundleIdentifier
            )
            guard music.track.sourceBundleIdentifier
                == displayedSourceBundleIdentifier else {
                finishTrackControlFeedback(.nextTrack, generation: feedbackGeneration)
                return
            }
            musicSourceStatus = outcome.status
            if !outcome.didSendCommand, music.controlRecoveryAction != nil {
                musicControlRecoveryNeedsUserAction = true
            }
            if outcome.didSendCommand {
                if displayedSourceBundleIdentifier
                    == MusicAdapterRegistry.qishui.descriptor.bundleIdentifier {
                    musicAdapter.invalidateQishuiCache()
                }
                startMusicControlRefreshBurst(
                    previousSignature: previousSignature,
                    requireTrackChange: true,
                    trackControlGeneration: feedbackGeneration
                )
            } else {
                finishTrackControlFeedback(.nextTrack, generation: feedbackGeneration)
                if outcome.shouldAdvancePreview {
                    applyMusicUpdate(musicAdapter.nextTrack(), status: outcome.status, forceMusic: true)
                }
            }
        }
    }

    func previousTrack() {
        guard music.canPreviousTrack else {
            requestCurrentMusicControlPermissionIfNeeded()
            return
        }
        noteDirectControlInteraction()
        cancelPendingMusicSeek(reason: .superseded)
        let previousSignature = musicSignature(music)
        let displayedSourceBundleIdentifier = music.track.sourceBundleIdentifier
        let feedbackGeneration = beginTrackControlFeedback(
            .previousTrack,
            baselineSignature: previousSignature
        )
        activeFeature = .music
        if mode == .collapsed {
            mode = .compact
        }
        Task { [weak self] in
            guard let self else { return }
            let outcome = await musicAdapter.performControl(
                .previousTrack,
                displayedSourceBundleIdentifier: displayedSourceBundleIdentifier
            )
            guard music.track.sourceBundleIdentifier
                == displayedSourceBundleIdentifier else {
                finishTrackControlFeedback(.previousTrack, generation: feedbackGeneration)
                return
            }
            musicSourceStatus = outcome.status
            if !outcome.didSendCommand, music.controlRecoveryAction != nil {
                musicControlRecoveryNeedsUserAction = true
            }
            if outcome.didSendCommand {
                if displayedSourceBundleIdentifier
                    == MusicAdapterRegistry.qishui.descriptor.bundleIdentifier {
                    musicAdapter.invalidateQishuiCache()
                }
                startMusicControlRefreshBurst(
                    previousSignature: previousSignature,
                    requireTrackChange: true,
                    trackControlGeneration: feedbackGeneration
                )
            } else {
                finishTrackControlFeedback(.previousTrack, generation: feedbackGeneration)
                if outcome.shouldAdvancePreview {
                    applyMusicUpdate(musicAdapter.previousTrack(), status: outcome.status, forceMusic: true)
                }
            }
        }
    }

    func showMusicSourceStatus() {
        let update = musicAdapter.refreshPlaybackPositionNow()
        applyMusicUpdate(update.music, status: update.status, forceMusic: true)
    }

    func showAccessibilityStatus() {
        let trusted = AXIsProcessTrusted()
        let path = Bundle.main.bundlePath
        triggerNotification(
            title: trusted ? "辅助功能已授权" : "辅助功能未授权",
            body: trusted
                ? "当前运行的顶屿已通过系统辅助功能检查。"
                : "当前运行路径：\(path)。请在辅助功能中勾选这个 App；如果已有旧项，先删除旧项再添加当前 App。"
        )
    }

    func refreshMusicIntegrationStatus() {
        qishuiIsRunning = !NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicAdapterRegistry.qishui.descriptor.bundleIdentifier
        ).isEmpty
        accessibilityTrusted = AXIsProcessTrusted()
        refreshNeteaseMusicStatus()
        refreshAppleMusicStatus()
    }

    func refreshAccessibilityDisplayOptions() {
        reduceMotionEnabled = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func refreshNeteaseMusicStatus() {
        let runningApplication = NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicAdapterRegistry.neteaseMusic.descriptor.bundleIdentifier
        ).first
        let processIdentifier = runningApplication?.processIdentifier
        if processIdentifier != neteaseMusicObservedProcessIdentifier {
            neteaseMusicObservedProcessIdentifier = processIdentifier
            resetNeteaseMusicConnection(
                status: processIdentifier == nil ? "未运行" : "等待同步"
            )
        }
        neteaseMusicIsRunning = runningApplication != nil
        if !neteaseMusicIsRunning {
            resetNeteaseMusicConnection(status: "未运行")
        }
    }

    func refreshNeteaseMusicSnapshot() async {
        refreshNeteaseMusicStatus()
        guard neteaseMusicIsRunning else { return }
        neteaseMusicSettingsRequestGeneration &+= 1
        let generation = neteaseMusicSettingsRequestGeneration
        let expectedProcessIdentifier = neteaseMusicObservedProcessIdentifier
        guard let snapshot = await musicAdapter.neteaseMusicSnapshotForSettings() else {
            guard generation == neteaseMusicSettingsRequestGeneration else { return }
            neteaseMusicConnectionStatus = "连接超时"
            return
        }
        let currentProcessIdentifier = NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicAdapterRegistry.neteaseMusic.descriptor.bundleIdentifier
        ).first?.processIdentifier
        guard generation == neteaseMusicSettingsRequestGeneration,
              currentProcessIdentifier == expectedProcessIdentifier,
              snapshot.instance?.processIdentifier == expectedProcessIdentifier else {
            refreshNeteaseMusicStatus()
            return
        }
        neteaseMusicSnapshotAvailability = snapshot.availability
        switch snapshot.availability {
        case .ready:
            neteaseMusicConnectionStatus = "连接正常"
        case .notRunning:
            neteaseMusicConnectionStatus = "未运行"
        case let .degraded(reason):
            neteaseMusicConnectionStatus = "读取失败：\(reason)"
        case let .permissionRequired(permission):
            neteaseMusicConnectionStatus = "需要权限：\(permission)"
        case let .unavailable(reason):
            neteaseMusicConnectionStatus = "不可用：\(reason)"
        }
        neteaseMusicAvailableControls = [
            snapshot.controls.supports(.playPause) ? "播放暂停" : nil,
            snapshot.controls.supports(.previousTrack) ? "上一首" : nil,
            snapshot.controls.supports(.nextTrack) ? "下一首" : nil
        ]
        .compactMap { $0 }
        .joined(separator: "、")
        if neteaseMusicAvailableControls.isEmpty {
            neteaseMusicAvailableControls = accessibilityTrusted ? "无" : "等待辅助功能授权"
        }
    }

    private func resetNeteaseMusicConnection(status: String) {
        neteaseMusicSettingsRequestGeneration &+= 1
        neteaseMusicSnapshotAvailability = nil
        neteaseMusicConnectionStatus = status
        neteaseMusicAvailableControls = "无"
    }

    func refreshAppleMusicStatus() {
        guard appSettings.appleMusicEnabled else {
            appleMusicIsRunning = false
            appleMusicAutomationAccess = .targetNotRunning
            appleMusicObservedProcessIdentifier = nil
            resetAppleMusicConnection(status: "已关闭")
            return
        }

        let runningApplication = NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicAdapterRegistry.appleMusic.descriptor.bundleIdentifier
        ).first
        let processIdentifier = runningApplication?.processIdentifier
        if processIdentifier != appleMusicObservedProcessIdentifier {
            appleMusicObservedProcessIdentifier = processIdentifier
            resetAppleMusicConnection(status: processIdentifier == nil ? "未运行" : "等待同步")
        }
        appleMusicIsRunning = runningApplication != nil
        let previousAutomationAccess = appleMusicAutomationAccess
        let currentAutomationAccess: AppleMusicAutomationAccess = appleMusicIsRunning
            ? AppleMusicAppAdapter.automationAccess(prompt: false)
            : .targetNotRunning
        appleMusicAutomationAccess = currentAutomationAccess
        if appleMusicIsRunning,
           previousAutomationAccess == .allowed,
           currentAutomationAccess != .allowed {
            musicAdapter.invalidateAppleMusicAccess()
        }

        guard appleMusicIsRunning else {
            resetAppleMusicConnection(status: "未运行")
            return
        }
        guard appleMusicAutomationAccess == .allowed else {
            resetAppleMusicConnection(status: appleMusicAutomationAccess.displayName)
            return
        }
        if appleMusicSnapshotAvailability == nil {
            appleMusicConnectionStatus = "已授权，等待同步"
        }
    }

    func requestAppleMusicAutomationAccess() {
        guard appSettings.appleMusicEnabled,
              AppleMusicAppAdapter.isRunning else {
            refreshAppleMusicStatus()
            return
        }
        appleMusicAutomationAccess = AppleMusicAppAdapter.automationAccess(prompt: true)
        appleMusicIsRunning = AppleMusicAppAdapter.isRunning
        if appleMusicAutomationAccess == .allowed {
            Task { [weak self] in
                await self?.refreshAppleMusicSnapshot()
            }
        } else {
            resetAppleMusicConnection(status: appleMusicAutomationAccess.displayName)
        }
    }

    func refreshAppleMusicSnapshot() async {
        refreshAppleMusicStatus()
        guard appSettings.appleMusicEnabled else {
            resetAppleMusicConnection(status: "已关闭")
            return
        }
        guard appleMusicIsRunning else {
            resetAppleMusicConnection(status: "未运行")
            return
        }
        guard appleMusicAutomationAccess == .allowed else {
            resetAppleMusicConnection(status: appleMusicAutomationAccess.displayName)
            return
        }

        appleMusicSettingsRequestGeneration &+= 1
        let requestGeneration = appleMusicSettingsRequestGeneration
        let expectedProcessIdentifier = appleMusicObservedProcessIdentifier
        let requestStartedAt = Date()
        guard let snapshot = await musicAdapter.appleMusicSnapshotForSettings() else {
            refreshAppleMusicStatus()
            if appSettings.appleMusicEnabled,
               appleMusicIsRunning,
               appleMusicAutomationAccess == .allowed {
                appleMusicConnectionStatus = "连接超时"
            }
            return
        }
        let currentApplication = NSRunningApplication.runningApplications(
            withBundleIdentifier: MusicAdapterRegistry.appleMusic.descriptor.bundleIdentifier
        ).first
        let currentAccess = currentApplication.map { _ in
            AppleMusicAppAdapter.automationAccess(prompt: false)
        } ?? .targetNotRunning
        guard requestGeneration == appleMusicSettingsRequestGeneration,
              appSettings.appleMusicEnabled,
              currentApplication?.processIdentifier == expectedProcessIdentifier,
              snapshot.instance?.processIdentifier == expectedProcessIdentifier,
              currentAccess == .allowed else {
            refreshAppleMusicStatus()
            return
        }
        appleMusicResponseLatencyMilliseconds = max(
            0,
            Int((Date().timeIntervalSince(requestStartedAt) * 1_000).rounded())
        )
        appleMusicSnapshotAvailability = snapshot.availability
        appleMusicObservedProcessIdentifier = snapshot.instance?.processIdentifier
        switch snapshot.availability {
        case .ready:
            appleMusicConnectionStatus = "连接正常"
        case .notRunning:
            appleMusicConnectionStatus = "未运行"
        case let .degraded(reason):
            appleMusicConnectionStatus = "读取失败：\(reason)"
        case let .permissionRequired(permission):
            appleMusicConnectionStatus = "需要权限：\(permission)"
        case let .unavailable(reason):
            appleMusicConnectionStatus = "不可用：\(reason)"
        }

        appleMusicAvailableControls = [
            snapshot.controls.supports(.playPause) ? "播放暂停" : nil,
            snapshot.controls.supports(.previousTrack) ? "上一首" : nil,
            snapshot.controls.supports(.nextTrack) ? "下一首" : nil,
            snapshot.controls.supports(.absoluteSeek) ? "进度跳转" : nil
        ]
        .compactMap { $0 }
        .joined(separator: "、")
        if appleMusicAvailableControls.isEmpty {
            appleMusicAvailableControls = "无"
        }
    }

    private func resetAppleMusicConnection(status: String) {
        appleMusicSettingsRequestGeneration &+= 1
        appleMusicSnapshotAvailability = nil
        appleMusicConnectionStatus = status
        appleMusicAvailableControls = "无"
        appleMusicResponseLatencyMilliseconds = nil
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func requestCurrentMusicControlPermissionIfNeeded() {
        guard canRecoverCurrentMusicControlPermission else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        if !accessibilityTrusted {
            openAccessibilitySettings()
        }
    }

    func openAppleMusicAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func forceRefreshNowPlaying() {
        activeFeature = .music
        requestIslandMode(.expanded, bypassCooldown: true)
        let result = musicAdapter.forceRefreshNowPlaying()
        applyMusicUpdate(result.music, status: result.status, forceMusic: true)
    }

    func seekMusic(
        to progress: Double,
        interaction: MusicSeekInteraction
    ) async -> Bool {
        noteDirectControlInteraction()
        activeFeature = .music
        musicSeekRequestID += 1
        let requestID = musicSeekRequestID
        let previousSignature = musicSignature(music)
        let displayedSourceBundleIdentifier = music.track.sourceBundleIdentifier
        let requestedAt = Date()
        let result = await musicAdapter.seek(
            to: progress,
            interaction: interaction,
            displayedSourceBundleIdentifier: displayedSourceBundleIdentifier
        )
        let didSeek = result.status.availability == .qishuiControlSent
            || result.status.availability == .appleMusicControlSent
        guard requestID == musicSeekRequestID else {
            if didSeek {
                let currentSourceBundleIdentifier = music.track.sourceBundleIdentifier
                let reason: MusicSeekCancellationReason
                if currentSourceBundleIdentifier == displayedSourceBundleIdentifier {
                    reason = .superseded
                } else if currentSourceBundleIdentifier == nil {
                    reason = .sourceExited
                } else {
                    reason = .sourceChanged
                }
                musicAdapter.noteSeekCancelled(
                    sourceBundleIdentifier: displayedSourceBundleIdentifier,
                    requestedAt: requestedAt,
                    targetProgress: progress,
                    reason: reason
                )
            }
            return true
        }
        guard music.track.sourceBundleIdentifier
            == displayedSourceBundleIdentifier else {
            if didSeek {
                musicAdapter.noteSeekCancelled(
                    sourceBundleIdentifier: displayedSourceBundleIdentifier,
                    requestedAt: requestedAt,
                    targetProgress: progress,
                    reason: music.track.sourceBundleIdentifier == nil
                        ? .sourceExited
                        : .sourceChanged
                )
            }
            return true
        }
        cancelPendingMusicSeek(reason: .superseded)
        applyMusicUpdate(result.music, status: result.status, forceMusic: true)
        if didSeek {
            pendingMusicSeek = PendingMusicSeek(
                trackSignature: musicSignature(result.music),
                sourceBundleIdentifier: displayedSourceBundleIdentifier,
                targetProgress: min(max(progress, 0), 1),
                requestedAt: requestedAt,
                issuedAt: Date(),
                isPlaying: result.music.isPlaying,
                expiresAt: Date().addingTimeInterval(3.5),
                matchingSince: nil
            )
            startMusicControlRefreshBurst(previousSignature: previousSignature, requireTrackChange: false)
        }
        return didSeek
    }

    func setMusicScrubbing(_ isScrubbing: Bool) {
        guard isMusicScrubbing != isScrubbing else { return }
        isMusicScrubbing = isScrubbing
        if isScrubbing {
            musicRefreshBurstTask?.cancel()
            musicRefreshBurstTask = nil
        } else {
            presentNextEventIfPossible()
        }
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        musicControlRecoveryTask?.cancel()
        musicControlRecoveryTask = nil
        isRecoveringMusicControl = false
        musicControlRecoveryAwaitingVerification = false
        cancelPendingMusicSeek(reason: .stateReset)
        musicRefreshBurstTask?.cancel()
        musicRefreshBurstTask = nil
        musicAccentTask?.cancel()
        musicAccentTask = nil
        trackControlFeedbackTask?.cancel()
        trackControlFeedbackTask = nil
        notificationPresentationTask?.cancel()
        notificationPresentationTask = nil
        musicAdapter.stopRealtimeObservation()
        eventKitSettingsCancellable?.cancel()
        eventKitSettingsCancellable = nil
        eventKitSource.stop()
    }

    func startTimer(minutes: Int) {
        noteDirectControlInteraction()
        if activeFeature == .notification {
            clearNotificationPresentation()
        }
        let preset = FocusTimerPreset(rawValue: minutes) ?? .twentyFiveMinutes
        timerState = TimerState(
            duration: preset.durationSeconds,
            remaining: preset.durationSeconds,
            isRunning: true
        )
        lastTimerUpdateAt = Date()
        activeFeature = .timer
        if mode == .collapsed {
            mode = .compact
        }
    }

    func toggleTimer() {
        noteDirectControlInteraction()
        activeFeature = .timer
        timerState.isRunning.toggle()
        lastTimerUpdateAt = timerState.isRunning ? Date() : nil
        if mode == .collapsed {
            mode = .compact
        }
    }

    func resetTimer() {
        noteDirectControlInteraction()
        timerState = TimerState(duration: 25 * 60, remaining: 25 * 60, isRunning: false)
        lastTimerUpdateAt = nil
        activeFeature = .timer
    }

    func addMinute() {
        noteDirectControlInteraction()
        timerState.duration += 60
        timerState.remaining += 60
        activeFeature = .timer
    }

    func triggerNotification(
        title: String = "新的提醒",
        body: String = "这是一条来自顶屿的低打扰提醒。",
        source: String = "顶屿",
        interruptsExpanded: Bool = false,
        autoDismiss: Bool = true,
        mergeIdentifier: String? = nil,
        sourceBundleIdentifier: String? = nil
    ) {
        let event = PendingIslandEvent(
            title: title,
            body: body,
            source: source,
            priority: interruptsExpanded ? .urgent : .normal,
            autoDismiss: autoDismiss,
            count: 1,
            mergeIdentifier: mergeIdentifier,
            sourceBundleIdentifier: sourceBundleIdentifier
        )

        if event.priority == .normal, mergeNormalEventIfPossible(event) {
            return
        }

        if event.priority == .urgent,
           let activeEvent = activeIslandEvent,
           activeEvent.priority == .normal {
            if let presentedMode = notificationPresentedMode,
               mode != presentedMode {
                notificationReturnMode = mode
            }
            pendingIslandEvents.insert(activeEvent, at: 0)
            shouldResumeInterruptedNormalEvent = true
            activeIslandEvent = nil
            cancelNotificationDismissTask()
        }

        enqueue(event)
        updateNotificationDisplay()
        presentNextEventIfPossible()
    }

    func showPendingNotification() {
        guard hasPendingNotification else { return }
        presentNextEventIfPossible(force: true)
    }

    func dismissNotification() {
        noteDirectControlInteraction()
        completeActiveEvent()
    }

    var canOpenActiveEventSource: Bool {
        guard let bundleIdentifier = activeIslandEvent?.sourceBundleIdentifier else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    func openActiveEventSource() {
        guard let bundleIdentifier = activeIslandEvent?.sourceBundleIdentifier,
              let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
              ) else { return }
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
        dismissNotification()
    }

    func requestCalendarAccess() async {
        let granted = await eventKitSource.requestCalendarAccess()
        appSettings.calendarEventsEnabled = granted
    }

    func requestRemindersAccess() async {
        let granted = await eventKitSource.requestRemindersAccess()
        appSettings.remindersEnabled = granted
    }

    func refreshEventKitNow() async {
        await eventKitSource.refreshNow()
    }

    func openEventKitPrivacySettings(for entityType: EKEntityType) {
        let anchor = entityType == .event ? "Privacy_Calendars" : "Privacy_Reminders"
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func receiveEventKitEvent(_ event: EventKitIslandEvent) {
        triggerNotification(
            title: event.title,
            body: event.body,
            source: event.source,
            mergeIdentifier: event.identifier,
            sourceBundleIdentifier: event.sourceBundleIdentifier
        )
    }

    private func cancelNotification(mergeIdentifier: String) {
        pendingIslandEvents.removeAll { $0.mergeIdentifier == mergeIdentifier }
        if activeIslandEvent?.mergeIdentifier == mergeIdentifier {
            completeActiveEvent()
        } else {
            updateNotificationDisplay()
        }
    }

    private func startTicker() {
        // Lyric AX snapshots are admitted every 180ms. Publishing on the same
        // cadence avoids making a fresh active line wait for a second 500ms
        // tick; the adapter's source and playback refreshes retain their own
        // longer throttles.
        ticker = Timer.scheduledTimer(
            withTimeInterval: MusicPresentationTimingPolicy.mediaPublicationInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func tick() {
        if !isPreviewPresentation {
            let trusted = AXIsProcessTrusted()
            if trusted != accessibilityTrusted {
                accessibilityTrusted = trusted
            }
            let mediaUpdate = musicAdapter.tick(music)
            if isMusicScrubbing {
                if let status = mediaUpdate.sourceStatus,
                   shouldPublishMusicStatus(status) {
                    musicSourceStatus = status
                }
            } else {
                applyMusicUpdate(mediaUpdate.music, status: mediaUpdate.sourceStatus)
            }
            updateMusicControlRecovery()
            presentNextEventIfPossible()
        }

        guard timerState.isRunning else {
            lastTimerUpdateAt = nil
            return
        }

        let now = Date()
        let previous = lastTimerUpdateAt ?? now
        let elapsedWholeSeconds = Int(now.timeIntervalSince(previous))
        guard elapsedWholeSeconds > 0 else { return }

        lastTimerUpdateAt = previous.addingTimeInterval(TimeInterval(elapsedWholeSeconds))
        timerState.remaining = max(timerState.remaining - elapsedWholeSeconds, 0)
        if timerState.remaining == 0 {
            timerState.isRunning = false
            lastTimerUpdateAt = nil
            triggerNotification(
                title: "时间到",
                body: "计时器已经结束。",
                source: "计时器",
                interruptsExpanded: true,
                autoDismiss: false
            )
        }
    }

    private func updateMusicControlRecovery() {
        // A missing UI action is not proof that Qishui's controls recovered.
        switch MusicControlRecoveryPolicy.refreshDisposition(
            isRecovering: isRecoveringMusicControl,
            awaitingVerification: musicControlRecoveryAwaitingVerification,
            qishuiAvailability: musicAdapter.qishuiControlAvailability,
            hasRecoveryAction: music.controlRecoveryAction != nil
        ) {
        case .keepWaiting, .unchanged:
            return
        case .verified:
            latestMusicControlRecoverySummary = "控件已恢复"
        case .clearInactiveFeedback:
            break
        }
        isRecoveringMusicControl = false
        musicControlRecoveryAwaitingVerification = false
        musicControlRecoveryNeedsUserAction = false
        musicControlRecoveryTask?.cancel()
        musicControlRecoveryTask = nil
    }

    private func reopenQishuiWindow() {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: QishuiProcessLocator.bundleIdentifier
        ) else {
            musicControlRecoveryNeedsUserAction = true
            return
        }

        musicControlRecoveryTask?.cancel()
        isRecoveringMusicControl = true
        musicControlRecoveryAwaitingVerification = false
        musicControlRecoveryNeedsUserAction = false
        musicAdapter.resetQishuiControlVerificationForRecovery()
        let runningApplication = QishuiProcessLocator.application()

        // Qishui is Electron.  A normal Dock/open request cannot turn on its
        // renderer accessibility tree for an already-running process, so the
        // user-initiated recovery action performs a scoped relaunch with the
        // supported Chromium accessibility switch.  This is deliberately not
        // part of background polling: playback is interrupted only when the
        // user explicitly asks to connect the three top controls.
        musicControlRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let didLaunch = await QishuiWindowRecovery
                .relaunchWithRendererAccessibility(
                    applicationURL: applicationURL,
                    runningApplication: runningApplication
                )
            guard !Task.isCancelled else { return }
            guard didLaunch else {
                self.isRecoveringMusicControl = false
                self.musicControlRecoveryNeedsUserAction = true
                self.latestMusicControlRecoverySummary = "汽水未能以可控模式重新启动，请手动打开汽水后再试"
                return
            }
            self.musicAdapter.resetQishuiControlVerificationForRecovery()
            self.musicControlRecoveryAwaitingVerification = true
            _ = QishuiWindowRecovery.revealMainWindow(
                for: QishuiProcessLocator.application()
            )
            self.scheduleQishuiControlAvailabilityRefreshAfterRecovery()
        }
    }

    private func scheduleQishuiControlAvailabilityRefreshAfterRecovery() {
        musicControlRecoveryTask = Task { @MainActor [weak self] in
            // AX content can appear after the app has finished activating.  A
            // single delayed probe was too early for Qishui, so keep the
            // recovery window short but tolerant of several activation passes.
            let checkpoints: [UInt64] = [
                350_000_000,
                400_000_000,
                500_000_000,
                650_000_000,
                900_000_000,
                1_200_000_000
            ]
            for delay in checkpoints {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled, let self,
                      self.isRecoveringMusicControl else {
                    return
                }

                _ = QishuiWindowRecovery.revealMainWindow(
                    for: QishuiProcessLocator.application()
                )
                self.musicAdapter.invalidateQishuiCache()
                await self.musicAdapter.verifyQishuiControlsAfterRecovery()
                guard !Task.isCancelled, self.isRecoveringMusicControl else { return }
                let update = self.musicAdapter.refreshPlaybackPositionNow()
                self.applyMusicUpdate(update.music, status: update.status, forceMusic: true)
                self.updateMusicControlRecovery()

                if !self.isRecoveringMusicControl { return }
            }

            guard !Task.isCancelled, let self,
                  self.isRecoveringMusicControl else { return }
            self.isRecoveringMusicControl = false
            self.musicControlRecoveryAwaitingVerification = false
            self.musicControlRecoveryNeedsUserAction = true
            self.latestMusicControlRecoverySummary = "汽水仍未提供可用控件，请确认汽水窗口已打开后再试"
        }
    }

    private var blocksInteractiveEventPresentation: Bool {
        isMusicScrubbing
            || pendingMusicSeek != nil
            || music.isPlaybackPending
            || pendingTrackControl != nil
    }

    private func mergeNormalEventIfPossible(_ event: PendingIslandEvent) -> Bool {
        if var activeEvent = activeIslandEvent,
           activeEvent.priority == .normal,
           canMerge(activeEvent, event) {
            activeEvent.title = event.title
            activeEvent.body = event.body
            activeEvent.source = event.source
            activeEvent.sourceBundleIdentifier = event.sourceBundleIdentifier
            activeEvent.count = min(activeEvent.count + 1, 9)
            activeIslandEvent = activeEvent
            updateNotificationDisplay()
            scheduleActiveEventDismissIfNeeded()
            return true
        }

        guard let index = pendingIslandEvents.lastIndex(where: {
            $0.priority == .normal && canMerge($0, event)
        }) else {
            return false
        }
        pendingIslandEvents[index].title = event.title
        pendingIslandEvents[index].body = event.body
        pendingIslandEvents[index].source = event.source
        pendingIslandEvents[index].sourceBundleIdentifier = event.sourceBundleIdentifier
        pendingIslandEvents[index].count = min(pendingIslandEvents[index].count + 1, 9)
        updateNotificationDisplay()
        return true
    }

    private func canMerge(_ lhs: PendingIslandEvent, _ rhs: PendingIslandEvent) -> Bool {
        if lhs.mergeIdentifier != nil || rhs.mergeIdentifier != nil {
            return lhs.mergeIdentifier != nil && lhs.mergeIdentifier == rhs.mergeIdentifier
        }
        return lhs.source == rhs.source
    }

    private func enqueue(_ event: PendingIslandEvent) {
        if event.priority == .urgent,
           let firstNormalIndex = pendingIslandEvents.firstIndex(where: { $0.priority == .normal }) {
            pendingIslandEvents.insert(event, at: firstNormalIndex)
        } else {
            pendingIslandEvents.append(event)
        }
    }

    private func presentNextEventIfPossible(force: Bool = false) {
        guard activeIslandEvent == nil,
              let nextEvent = pendingIslandEvents.first else {
            updateNotificationDisplay()
            return
        }

        let isBlocked = blocksInteractiveEventPresentation
            || (nextEvent.priority == .normal && mode == .expanded)
        guard force || !isBlocked else {
            updateNotificationDisplay()
            return
        }

        activeIslandEvent = pendingIslandEvents.removeFirst()
        if activeIslandEvent?.priority == .normal,
           shouldResumeInterruptedNormalEvent {
            shouldResumeInterruptedNormalEvent = false
        }
        if activeFeature != .notification {
            notificationReturnFeature = activeFeature
            notificationReturnMode = mode
        }
        activeFeature = .notification
        if mode == .collapsed {
            mode = .compact
        }
        notificationPresentedMode = mode
        updateNotificationDisplay()
        scheduleActiveEventDismissIfNeeded()
    }

    private func scheduleActiveEventDismissIfNeeded() {
        cancelNotificationDismissTask()
        guard activeIslandEvent?.autoDismiss == true else { return }
        notificationGeneration += 1
        let generation = notificationGeneration
        notificationPresentationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled,
                  let self,
                  generation == notificationGeneration,
                  activeIslandEvent?.autoDismiss == true else { return }
            completeActiveEvent()
        }
    }

    private func completeActiveEvent() {
        guard activeIslandEvent != nil else { return }
        activeIslandEvent = nil
        cancelNotificationDismissTask()

        let returnFeature = notificationReturnFeature
        let returnMode = notificationReturnMode
        let presentedMode = notificationPresentedMode
        let latestMode = mode
        notificationReturnFeature = nil
        notificationReturnMode = nil
        notificationPresentedMode = nil

        let resolvedFeature = IslandActivityReturnPolicy.featureAfterNotification(
            returnFeature: returnFeature,
            timerIsRunning: timerState.isRunning,
            hasCurrentMusicTrack: music.hasCurrentTrack
        )
        activeFeature = resolvedFeature
        if latestMode == presentedMode {
            if resolvedFeature == .music, returnFeature != .music {
                mode = .compact
            } else if let returnMode {
                mode = returnMode
            }
        }
        updateNotificationDisplay()
        let shouldForceResume = shouldResumeInterruptedNormalEvent
            && pendingIslandEvents.first?.priority == .normal
        presentNextEventIfPossible(force: shouldForceResume)
    }

    private func updateNotificationDisplay() {
        let event = activeIslandEvent ?? pendingIslandEvents.first
        let count = min(
            (activeIslandEvent?.count ?? 0)
                + pendingIslandEvents.reduce(0) { $0 + $1.count },
            9
        )
        notification = IslandNotification(
            title: event?.title ?? "",
            body: event?.body ?? "",
            source: event?.source ?? "顶屿",
            count: count
        )
    }

    private func cancelNotificationDismissTask() {
        notificationGeneration += 1
        notificationPresentationTask?.cancel()
        notificationPresentationTask = nil
    }

    private func clearNotificationPresentation() {
        activeIslandEvent = nil
        pendingIslandEvents.removeAll()
        shouldResumeInterruptedNormalEvent = false
        cancelNotificationDismissTask()
        notificationReturnFeature = nil
        notificationReturnMode = nil
        notificationPresentedMode = nil
        updateNotificationDisplay()
    }

    private func startMusicControlRefreshBurst(
        previousSignature: String,
        requireTrackChange: Bool,
        trackControlGeneration: UInt64? = nil
    ) {
        if let trackControlGeneration,
           pendingTrackControlGeneration != trackControlGeneration {
            return
        }
        musicRefreshBurstTask?.cancel()
        let intervalsInNanoseconds: [UInt64] = [
            80_000_000,
            120_000_000,
            160_000_000,
            220_000_000,
            300_000_000,
            420_000_000,
            600_000_000,
            800_000_000,
            1_100_000_000
        ]

        musicRefreshBurstTask = Task { [weak self] in
            for interval in intervalsInNanoseconds {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                if let trackControlGeneration,
                   self.pendingTrackControlGeneration != trackControlGeneration {
                    return
                }
                let update = await self.musicAdapter.refreshControlFollowUp(
                    forcePositionRefresh: requireTrackChange
                )
                guard !Task.isCancelled else { return }
                self.applyMusicUpdate(
                    update.music,
                    status: update.status,
                    forceMusic: true,
                    trackControlConfirmationGeneration: trackControlGeneration
                )
                if self.shouldStopMusicControlRefreshBurst(
                    music: update.music,
                    status: update.status,
                    previousSignature: previousSignature,
                    requireTrackChange: requireTrackChange
                ) {
                    if let trackControlGeneration,
                       self.pendingTrackControlGeneration == trackControlGeneration {
                        continue
                    }
                    self.musicRefreshBurstTask?.cancel()
                }
            }
        }
    }

    private func applyMusicUpdate(
        _ newMusic: MusicState,
        status newStatus: MusicSourceStatus?,
        forceMusic: Bool = false,
        trackControlConfirmationGeneration: UInt64? = nil
    ) {
        if newStatus?.availability == .qishuiNotRunning {
            resetMusicPresentationAfterSourceExit()
        } else if MusicUpdatePolicy.didChangeSource(current: music, candidate: newMusic) {
            resetPendingMusicControlPresentation(
                seekCancellationReason: newMusic.track.sourceBundleIdentifier == nil
                    ? .sourceExited
                    : .sourceChanged
            )
        }
        if isMusicScrubbing, !forceMusic {
            if let newStatus,
               shouldPublishMusicStatus(newStatus) {
                musicSourceStatus = newStatus
            }
            return
        }

        let reconciledMusic = reconcilePendingSeek(newMusic)
        let becameAvailable = !music.hasCurrentTrack
            && reconciledMusic.hasCurrentTrack
        let shouldTakeOverWithMusic = MusicActivityTakeoverPolicy.shouldTakeOver(
            activeFeature: activeFeature,
            becameAvailable: becameAvailable,
            timerIsRunning: timerState.isRunning,
            hasPendingNotification: hasPendingNotification
        )
        let shouldPromoteToCompact = MusicPresentationTransitionPolicy
            .shouldPromoteToCompact(
                activeFeature: activeFeature,
                currentMode: mode,
                isArmed: autoCompactOnNextMusicTrack,
                hadCurrentTrack: music.hasCurrentTrack,
                hasCurrentTrack: reconciledMusic.hasCurrentTrack,
                hasPendingNotification: hasPendingNotification
            )
        if MusicUpdatePolicy.shouldIgnoreUntrustedProgressReset(
            current: music,
            candidate: reconciledMusic,
            sourceAvailability: newStatus?.availability
        ) {
            var timelinePreservingUpdate = music
            timelinePreservingUpdate.isPlaying = reconciledMusic.isPlaying
            timelinePreservingUpdate.isPlaybackPending = reconciledMusic.isPlaybackPending
            timelinePreservingUpdate.canPlayPause = reconciledMusic.canPlayPause
            timelinePreservingUpdate.canPreviousTrack = reconciledMusic.canPreviousTrack
            timelinePreservingUpdate.canNextTrack = reconciledMusic.canNextTrack
            timelinePreservingUpdate.controlUnavailableReason = reconciledMusic.controlUnavailableReason
            timelinePreservingUpdate.controlRecoveryAction = reconciledMusic.controlRecoveryAction
            timelinePreservingUpdate.hasCurrentTrack = reconciledMusic.hasCurrentTrack
            if timelinePreservingUpdate != music {
                musicTimelineSampledAt = Date()
                music = timelinePreservingUpdate
                musicAdapter.noteMusicUIPublished(timelinePreservingUpdate)
            }
            if let newStatus,
               shouldPublishMusicStatus(newStatus) {
                musicSourceStatus = newStatus
            }
            return
        }

        if forceMusic || shouldPublishMusicUpdate(reconciledMusic) {
            // A lyric snapshot can arrive on its own after MediaRemote has
            // already published the track. Promote that snapshot to the same
            // music presentation transaction so the width listener cannot see
            // the old 377pt layout with new lyric text.
            musicTimelineSampledAt = Date()
            music = reconciledMusic
            musicAdapter.noteMusicUIPublished(reconciledMusic)
            if !reconciledMusic.hasCurrentTrack {
                AlbumArtworkImageCache.shared.removeAll()
            }
            if becameAvailable {
                autoCompactOnNextMusicTrack = false
            }
            if shouldTakeOverWithMusic {
                activeFeature = .music
                isUserExpandedMusicPresentation = false
                mode = .compact
            } else if isMusicLyricsEnabled,
                      activeFeature == .music,
                      appSettings.autoExpandMusicLyrics,
                      MusicLyricPresentation.hasDisplayableLines(reconciledMusic.track.lyrics) {
                // Only promote after a complete lyric snapshot arrives. A
                // title-only transition must remain in the normal control
                // card; the next lyric publication will re-run this branch.
                isUserExpandedMusicPresentation = true
                mode = .expanded
            } else if shouldPromoteToCompact {
                isUserExpandedMusicPresentation = false
                mode = .compact
            }
            refreshMusicAccent(
                for: reconciledMusic.track,
                hasCurrentTrack: reconciledMusic.hasCurrentTrack
            )
            confirmTrackControlFeedbackIfNeeded(
                with: reconciledMusic,
                generation: trackControlConfirmationGeneration
            )
        }

        if let newStatus,
           shouldPublishMusicStatus(newStatus) {
            musicSourceStatus = newStatus
        }
    }

    private func resetMusicPresentationAfterSourceExit() {
        resetPendingMusicControlPresentation(seekCancellationReason: .sourceExited)
        if activeFeature == .music,
           !hasPendingNotification {
            let shouldCollapse = MusicPresentationTransitionPolicy
                .shouldResetToDefaultAfterAllSourcesExit(currentMode: mode)
            autoCompactOnNextMusicTrack = true
            isUserExpandedMusicPresentation = false
            activeFeature = .activityCenter
            if shouldCollapse {
                mode = .collapsed
            }
        }
    }

    private func resetPendingMusicControlPresentation(
        seekCancellationReason: MusicSeekCancellationReason
    ) {
        musicRefreshBurstTask?.cancel()
        musicRefreshBurstTask = nil
        trackControlFeedbackTask?.cancel()
        trackControlFeedbackTask = nil
        pendingTrackControl = nil
        pendingTrackControlBaselineSignature = nil
        pendingTrackControlGeneration = nil
        pendingTrackControlChainCount = 0
        cancelPendingMusicSeek(reason: seekCancellationReason)
        musicSeekRequestID += 1
        isMusicScrubbing = false
    }

    private func cancelPendingMusicSeek(reason: MusicSeekCancellationReason) {
        guard let pendingSeek = pendingMusicSeek else { return }
        musicAdapter.noteSeekCancelled(
            sourceBundleIdentifier: pendingSeek.sourceBundleIdentifier,
            requestedAt: pendingSeek.requestedAt,
            targetProgress: pendingSeek.targetProgress,
            reason: reason
        )
        pendingMusicSeek = nil
    }

    private func confirmTrackControlFeedbackIfNeeded(
        with music: MusicState,
        generation: UInt64?
    ) {
        guard let generation,
              pendingTrackControlGeneration == generation,
              pendingTrackControlChainCount == 1,
              let pendingTrackControl,
              let baseline = pendingTrackControlBaselineSignature else { return }

        let signature = musicSignature(music)
        guard signature != baseline else { return }
        finishTrackControlFeedback(pendingTrackControl, generation: generation)
    }

    private func refreshMusicAccent(
        for track: MusicTrack,
        hasCurrentTrack: Bool
    ) {
        let identity = "\(hasCurrentTrack ? "active" : "inactive")\u{1f}"
            + artworkAccentIdentity(for: track)
        guard identity != musicAccentIdentity else { return }
        musicAccentIdentity = identity
        musicAccentGeneration += 1
        let generation = musicAccentGeneration
        musicAccentTask?.cancel()

        let inlineData = track.artworkData
        let artworkURL = track.artworkURL
        guard inlineData != nil || artworkURL != nil else {
            guard ArtworkAccentTransitionPolicy.shouldDelayNeutralFallback(
                hasCurrentTrack: hasCurrentTrack
            ) else {
                withAnimation(.easeInOut(duration: 0.20)) {
                    musicAccentColor = .white
                }
                musicAccentTask = nil
                return
            }
            let fallbackColor = Color(white: 0.74)
            let graceNanoseconds = ArtworkAccentTransitionPolicy
                .missingArtworkGraceNanoseconds
            musicAccentTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: graceNanoseconds)
                guard !Task.isCancelled,
                      let self,
                      generation == musicAccentGeneration,
                      identity == musicAccentIdentity else { return }
                withAnimation(.easeInOut(duration: 0.24)) {
                    musicAccentColor = fallbackColor
                }
                musicAccentTask = nil
            }
            return
        }

        musicAccentTask = Task { [weak self] in
            let data: Data?
            if let inlineData {
                data = inlineData
            } else if let artworkURL {
                data = try? await URLSession.shared.data(from: artworkURL).0
            } else {
                data = nil
            }
            guard !Task.isCancelled, let data else { return }
            let components = await Task.detached(priority: .utility) {
                artworkAccentComponents(from: data)
            }.value
            guard !Task.isCancelled,
                  let self,
                  generation == musicAccentGeneration,
                  identity == musicAccentIdentity else { return }
            guard let components else {
                withAnimation(.easeInOut(duration: 0.24)) {
                    musicAccentColor = Color(white: 0.74)
                }
                musicAccentTask = nil
                return
            }
            withAnimation(.easeInOut(duration: 0.20)) {
                musicAccentColor = Color(
                    red: components.red,
                    green: components.green,
                    blue: components.blue
                )
            }
            musicAccentTask = nil
        }
    }

    private func artworkAccentIdentity(for track: MusicTrack) -> String {
        let artworkKey: String
        if let artworkData = track.artworkData {
            let prefix = artworkData.prefix(16)
                .map { String(format: "%02x", $0) }
                .joined()
            artworkKey = "data:\(artworkData.count):\(prefix)"
        } else if let artworkURL = track.artworkURL {
            artworkKey = "url:\(artworkURL.absoluteString)"
        } else {
            artworkKey = "none"
        }
        return "\(track.title)\u{1f}\(track.artist)\u{1f}\(artworkKey)"
    }

    private func reconcilePendingSeek(_ newMusic: MusicState) -> MusicState {
        guard var pendingSeek = pendingMusicSeek else { return newMusic }
        let now = Date()
        guard now < pendingSeek.expiresAt else {
            musicAdapter.noteSeekConfirmationTimeout(
                sourceBundleIdentifier: pendingSeek.sourceBundleIdentifier,
                requestedAt: pendingSeek.requestedAt,
                targetProgress: pendingSeek.targetProgress
            )
            pendingMusicSeek = nil
            return newMusic
        }
        guard musicSignature(newMusic) == pendingSeek.trackSignature else {
            cancelPendingMusicSeek(reason: .trackChanged)
            return newMusic
        }

        let duration = newMusic.duration ?? music.duration
        let elapsedSinceSeek = pendingSeek.isPlaying ? Date().timeIntervalSince(pendingSeek.issuedAt) : 0
        let expectedProgress = duration.map {
            min(max(pendingSeek.targetProgress + elapsedSinceSeek / max($0, 1), 0), 1)
        } ?? pendingSeek.targetProgress
        let tolerance = duration.map { max(0.75 / max($0, 1), 0.002) } ?? 0.01
        if abs(newMusic.progress - expectedProgress) <= tolerance {
            if let matchingSince = pendingSeek.matchingSince,
               now.timeIntervalSince(matchingSince) >= 0.35 {
                musicAdapter.noteSeekConfirmed(
                    sourceBundleIdentifier: pendingSeek.sourceBundleIdentifier,
                    requestedAt: pendingSeek.requestedAt,
                    targetProgress: pendingSeek.targetProgress,
                    observedProgress: newMusic.progress
                )
                pendingMusicSeek = nil
                return newMusic
            }
            pendingSeek.matchingSince = pendingSeek.matchingSince ?? now
        } else {
            pendingSeek.matchingSince = nil
        }
        pendingMusicSeek = pendingSeek

        var heldMusic = newMusic
        heldMusic.progress = expectedProgress
        if let duration, duration > 0 {
            heldMusic.duration = duration
            heldMusic.elapsedTime = duration * expectedProgress
        }
        return heldMusic
    }

    private func shouldPublishMusicUpdate(_ newMusic: MusicState) -> Bool {
        if hasTrackDisplayChange(newMusic.track, music.track)
            || newMusic.isPlaying != music.isPlaying
            || newMusic.lyricIndex != music.lyricIndex
            || newMusic.duration != music.duration
            || newMusic.canSeek != music.canSeek
            || newMusic.isPlaybackPending != music.isPlaybackPending
            || newMusic.canPlayPause != music.canPlayPause
            || newMusic.canPreviousTrack != music.canPreviousTrack
            || newMusic.canNextTrack != music.canNextTrack
            || newMusic.controlUnavailableReason != music.controlUnavailableReason
            || newMusic.controlRecoveryAction != music.controlRecoveryAction
            || newMusic.hasCurrentTrack != music.hasCurrentTrack {
            lastMusicProgressPublishAt = Date()
            return true
        }

        let oldSecond = music.elapsedTime.map { Int($0.rounded(.down)) }
        let newSecond = newMusic.elapsedTime.map { Int($0.rounded(.down)) }
        let progressDelta = abs(newMusic.progress - music.progress)
        let now = Date()
        guard oldSecond != newSecond || progressDelta >= 0.006 else {
            return false
        }
        guard now.timeIntervalSince(lastMusicProgressPublishAt) >= musicProgressPublishInterval else {
            return false
        }
        lastMusicProgressPublishAt = now
        return true
    }

    private func hasTrackDisplayChange(_ lhs: MusicTrack, _ rhs: MusicTrack) -> Bool {
        lhs.title != rhs.title
            || lhs.artist != rhs.artist
            || lhs.lyrics != rhs.lyrics
            || lhs.timedWords != rhs.timedWords
            || lhs.hasArtwork != rhs.hasArtwork
            || lhs.artworkData != rhs.artworkData
            || lhs.artworkURL != rhs.artworkURL
            || lhs.sourceBundleIdentifier != rhs.sourceBundleIdentifier
    }

    private func shouldPublishMusicStatus(_ newStatus: MusicSourceStatus) -> Bool {
        newStatus.sourceName != musicSourceStatus.sourceName
            || newStatus.availability != musicSourceStatus.availability
            || newStatus.headline != musicSourceStatus.headline
            || newStatus.detail != musicSourceStatus.detail
    }

    private func shouldStopMusicControlRefreshBurst(
        music: MusicState,
        status: MusicSourceStatus,
        previousSignature: String,
        requireTrackChange: Bool
    ) -> Bool {
        _ = status
        guard !music.isPlaybackPending,
              music.track.title != "汽水音乐" else {
            return false
        }

        if requireTrackChange {
            let didChangeTrack = musicSignature(music) != previousSignature
            if !didChangeTrack {
                musicAdapter.invalidateQishuiCache()
            }
            return didChangeTrack
        }
        return true
    }

    private func musicSignature(_ music: MusicState) -> String {
        "\(music.track.title)\u{1f}\(music.track.artist)"
    }

}

final class IslandPanel: NSPanel {
    var onLeftMouseDown: ((NSEvent) -> Void)?
    var frameAnimationTarget: CGRect?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // animator() is an Objective-C forwarding proxy, not an IslandPanel.
    // Swift direct dispatch would access our stored properties on that proxy.
    @objc dynamic override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        guard let target = frameAnimationTarget else {
            super.setFrame(frameRect, display: flag)
            return
        }
        let anchored = IslandAnimationFrame.anchored(frameRect, to: target)
        super.setFrame(anchored, display: flag)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            onLeftMouseDown?(event)
            if !isKeyWindow { makeKey() }
        }
        super.sendEvent(event)
    }
}

final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = IslandModel()
    private var panel: IslandPanel?
    private var statusItem: NSStatusItem?
    private var calibrationWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private var screenRefreshTask: Task<Void, Never>?
    private var accessibilityDisplayObserver: NSObjectProtocol?
    private var outsideMouseMonitor: Any?
    private var hoverGlobalMouseMonitor: Any?
    private var hoverLocalMouseMonitor: Any?
    private var outsideEventTap: CFMachPort?
    private var outsideEventTapRunLoopSource: CFRunLoopSource?
    private var panelAnimationGate = IslandAnimationCompletionGate()
    private var targetDisplayIdentity: String?
    private var stableDisplayIdentityCache: [UInt32: String] = [:]
    private var activeDisplayGeometry: IslandDisplayGeometry?
    private var hoverEnterTask: Task<Void, Never>?
    private var hoverExitTask: Task<Void, Never>?
    private var isPointerInsideHoverZone = false
    private var didExpandFromHover = false
    private var hoverReturnMode: IslandMode?
    private var hoverGeneration = 0
    private var hoverExpectedModeChange: IslandMode?
    private var hoverPointerCoalescer = LatestEventCoalescer<CGPoint>()
    private var hoverDeliveryWorkItem: DispatchWorkItem?
    private var panelFrameAnimationTarget: CGRect?
    private var panelFrameAnimationID: Int?
    private var fullScreenSuppressionTimer: Timer?
    private var fullScreenWorkspaceObservers: [NSObjectProtocol] = []
    private var isSuppressedByFullScreen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(receiveIslandEvent(_:)),
            name: islandEventNotificationName,
            object: nil
        )
        updateScreenMetrics()
        createPanel()
        createStatusItem()
        observeModel()
        observeScreenChanges()
        observeAccessibilityDisplayOptions()
        observeOutsideClicks()
        observeIslandHover()
        observeFullScreenChanges()
        updatePanelVisibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.presentOpenFeedback(shouldShowSettings: false)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard !model.isPreviewPresentation else { return }
        model.refreshMusicIntegrationStatus()
        Task {
            await model.refreshEventKitNow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentOpenFeedback(shouldShowSettings: true)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopPanelFrameAnimation()
        model.stop()
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: islandEventNotificationName,
            object: nil
        )
        if let outsideMouseMonitor {
            NSEvent.removeMonitor(outsideMouseMonitor)
        }
        if let hoverGlobalMouseMonitor {
            NSEvent.removeMonitor(hoverGlobalMouseMonitor)
        }
        if let hoverLocalMouseMonitor {
            NSEvent.removeMonitor(hoverLocalMouseMonitor)
        }
        if let outsideEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), outsideEventTapRunLoopSource, .commonModes)
        }
        if let outsideEventTap {
            CFMachPortInvalidate(outsideEventTap)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenRefreshTask?.cancel()
        screenRefreshTask = nil
        fullScreenSuppressionTimer?.invalidate()
        fullScreenSuppressionTimer = nil
        for observer in fullScreenWorkspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        fullScreenWorkspaceObservers.removeAll()
        if let accessibilityDisplayObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityDisplayObserver)
        }
        hoverEnterTask?.cancel()
        hoverExitTask?.cancel()
        hoverDeliveryWorkItem?.cancel()
        hoverDeliveryWorkItem = nil
        hoverPointerCoalescer.cancel()
    }

    @objc private func receiveIslandEvent(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let rawTitle = userInfo["title"] as? String,
              let rawBody = userInfo["body"] as? String else { return }
        let title = String(rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !title.isEmpty else { return }
        let body = String(rawBody.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        let rawSource = userInfo["source"] as? String ?? "顶屿"
        let source = String(rawSource.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        model.triggerNotification(
            title: title,
            body: body,
            source: source.isEmpty ? "顶屿" : source
        )
    }

    private func createPanel() {
        let size = panelSize(for: model.mode)
        let panel = makeIslandPanel(size: size, level: .statusBar)

        let root = IslandRootView(
            model: model,
            onOpenSettings: { [weak self] in self?.showSettings() },
            onQuit: { [weak self] in self?.quit() }
        )
        let host = IslandHostingView(rootView: root)
        configureIslandHostingView(host, size: size)
        panel.contentView = host
        panel.delegate = self
        panel.onLeftMouseDown = { [weak self, weak panel] event in
            guard let self, let panel,
                  model.mode == .expanded,
                  model.isVisible,
                  interactionRegions(for: panel.frame, mode: model.mode).contains(
                    panel.convertPoint(toScreen: event.locationInWindow), tolerance: 0
                  ) else { return }
            model.notePresentationInteraction()
        }

        self.panel = panel
        refreshFullScreenSuppression()
        repositionPanel(animated: false)
    }

    private func makeIslandPanel(size: NSSize, level: NSWindow.Level) -> IslandPanel {
        let panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.level = level
        panel.collectionBehavior = IslandPanelCollectionPolicy.behavior
        panel.isExcludedFromWindowsMenu = true
        return panel
    }

    private func configureIslandHostingView<Content: View>(
        _ hostingView: NSHostingView<Content>,
        size: NSSize
    ) {
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        hostingView.layer?.masksToBounds = true
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = BrandIdentity.menuBarImage()
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "顶屿"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示 / 隐藏顶屿", action: #selector(toggleVisibility), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "显示汽水音乐", action: #selector(showMusic), keyEquivalent: ""))
        let timerItem = NSMenuItem(title: "开始专注计时", action: nil, keyEquivalent: "")
        let timerMenu = NSMenu(title: "开始专注计时")
        for preset in FocusTimerPreset.allCases {
            let presetItem = NSMenuItem(
                title: preset.title,
                action: #selector(startTimerPreset(_:)),
                keyEquivalent: ""
            )
            presetItem.tag = preset.rawValue
            timerMenu.addItem(presetItem)
        }
        timerItem.submenu = timerMenu
        menu.addItem(timerItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "汽水适配状态", action: #selector(showMusicSourceStatus), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "辅助功能自检", action: #selector(showAccessibilityStatus), keyEquivalent: "a"))
        menu.addItem(NSMenuItem(title: "实验：打开系统播放诊断", action: #selector(forceRefreshNowPlaying), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "设置...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "校准布局...", action: #selector(showCalibration), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出顶屿", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func observeModel() {
        model.presentationInteraction
            .sink { [weak self] in self?.cancelHoverPresentation() }
            .store(in: &cancellables)
        model.$mode
            .sink { [weak self] mode in
                guard let self else { return }
                handleObservedModeChange(mode)
                repositionPanel(animated: true, targetMode: mode)
            }
            .store(in: &cancellables)

        model.$isVisible
            .sink { [weak self] _ in self?.updatePanelVisibility() }
            .store(in: &cancellables)

        model.$activeFeature
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, model.mode == .expanded || model.mode == .compact else { return }
                repositionPanel(animated: true, targetMode: model.mode)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            model.$music.map { $0.controlRecoveryAction != nil }.removeDuplicates(),
            model.$isRecoveringMusicControl.removeDuplicates()
        )
        .map { hasAction, isRecovering in
            MusicControlRecoveryPolicy.shouldPresentRecovery(
                isRecovering: isRecovering, hasRecoveryAction: hasAction
            )
        }
        .removeDuplicates()
        .dropFirst()
        .sink { [weak self] _ in
            // Published values arrive before their storage changes. Resize
            // from the committed model so the recovery row is not clipped.
            DispatchQueue.main.async {
                guard let self, self.model.mode == .expanded,
                      self.model.activeFeature == .activityCenter else { return }
                self.repositionPanel(animated: true)
            }
        }
        .store(in: &cancellables)

        Publishers.CombineLatest3(
            model.$activeFeature.removeDuplicates(),
            model.$music
                .map(\.hasCurrentTrack)
                .removeDuplicates(),
            model.$notification
                .map { $0.count > 0 }
                .removeDuplicates()
        )
        .map { feature, hasCurrentTrack, hasPendingNotification in
            IslandExpansionPolicy.allowsExpansion(
                activeFeature: feature,
                hasCurrentMusicTrack: hasCurrentTrack,
                hasPendingNotification: hasPendingNotification
            )
        }
        .removeDuplicates()
        .dropFirst()
        .sink { [weak self] _ in
            // Availability and feature changes are state updates, not pointer
            // movement. Re-reading NSEvent.mouseLocation here used to make a
            // lyric arrival or track switch expand the island even when the
            // user had not moved the mouse. Leave hover transitions to the
            // actual mouseMoved monitors below.
            self?.invalidateHoverSampleAfterStateChange()
        }
        .store(in: &cancellables)

        model.$music
            .map { music in
                MusicLyricPresentation.state(
                    lines: music.track.lyrics,
                    index: music.lyricIndex,
                    pairMixedLanguageLines: !music.track.lyricsAreDesktopSnapshot
                )
            }
            .removeDuplicates()
            .sink { [weak self] _ in
                // @Published emits from willSet. Defer until the committed
                // model value is visible so compactWidth/expandedHeight and
                // their SwiftUI content cannot observe different lyric states
                // during the same tick.
                DispatchQueue.main.async {
                    guard let self,
                          (self.model.mode == .compact || self.model.mode == .expanded),
                          self.model.activeFeature == .music else { return }
                    // Lyric availability changes both the compact width and the
                    // expanded body height. Apply the committed geometry after
                    // SwiftUI observes the same state, otherwise an arriving
                    // lyric shelf can be rendered below the old no-lyrics frame.
                    let mode = self.model.mode
                    self.repositionPanel(animated: false, targetMode: mode)
                }
            }
            .store(in: &cancellables)

        model.layout.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateScreenMetrics()
                    self?.repositionPanel(animated: false)
                }
            }
            .store(in: &cancellables)
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenParametersChange()
            }
        }
    }

    private func observeFullScreenChanges() {
        refreshFullScreenSuppression()
        fullScreenSuppressionTimer = Timer.scheduledTimer(
            withTimeInterval: 0.15,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFullScreenSuppression()
            }
        }
        let applicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFullScreenSuppression()
            }
        }
        let activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshFullScreenSuppression()
            }
        }
        fullScreenWorkspaceObservers = [applicationObserver, activeSpaceObserver]
    }

    @discardableResult
    private func synchronizeFullScreenSuppression() -> Bool {
        if model.isPreviewPresentation {
            let changed = isSuppressedByFullScreen
            isSuppressedByFullScreen = false
            return changed
        }
        guard let screen = targetScreen() else { return false }
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let hasCoveringWindow = IslandFullScreenWindowDetector.hasCoveringWindow(
            on: screen,
            excludingProcessIdentifier: ProcessInfo.processInfo.processIdentifier
        )
        let shouldSuppress = IslandFullScreenSuppressionPolicy.shouldSuppress(
            frontmostIsTopIslet: frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
            hasCoveringWindow: hasCoveringWindow
        )
        let changed = shouldSuppress != isSuppressedByFullScreen
        isSuppressedByFullScreen = shouldSuppress
        return changed
    }

    private func refreshFullScreenSuppression() {
        if synchronizeFullScreenSuppression() { updatePanelVisibility() }
    }

    private func handleScreenParametersChange() {
        screenRefreshTask?.cancel()
        stableDisplayIdentityCache.removeAll()
        refreshDisplayTopology()
        screenRefreshTask = Task { @MainActor [weak self] in
            for delay in IslandDisplayRefreshPolicy.stabilizationDelaysNanoseconds {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                self.refreshDisplayTopology()
            }
        }
    }

    private func refreshDisplayTopology() {
        _ = panelAnimationGate.beginAnimation()
        stopPanelFrameAnimation()
        updateScreenMetrics()
        repositionPanel(animated: false)
        updateIslandHover(at: NSEvent.mouseLocation)
    }

    private func observeAccessibilityDisplayOptions() {
        model.refreshAccessibilityDisplayOptions()
        accessibilityDisplayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.model.refreshAccessibilityDisplayOptions()
                self.repositionPanel(animated: false)
            }
        }
    }

    private func observeOutsideClicks() {
        outsideMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            let clickPoint = NSEvent.mouseLocation
            Task { @MainActor in
                self?.collapseExpandedIslandIfClickIsOutside(appKitLocation: clickPoint)
            }
        }

        let eventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, _, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
                Task { @MainActor in
                    appDelegate.collapseExpandedIslandIfClickIsOutside()
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            return
        }

        outsideEventTap = eventTap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        outsideEventTapRunLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func observeIslandHover() {
        hoverGlobalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            let point = NSEvent.mouseLocation
            MainActor.assumeIsolated {
                self?.enqueueIslandHover(at: point)
            }
        }
        hoverLocalMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            let point = NSEvent.mouseLocation
            MainActor.assumeIsolated {
                self?.enqueueIslandHover(at: point)
            }
            return event
        }
    }

    private func enqueueIslandHover(at point: CGPoint) {
        guard hoverPointerCoalescer.submit(point) else { return }
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hoverDeliveryWorkItem = nil
                guard let latestPoint = self.hoverPointerCoalescer.consume() else { return }
                self.updateIslandHover(at: latestPoint)
            }
        }
        hoverDeliveryWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(8),
            execute: workItem
        )
    }

    private func updateIslandHover(at point: CGPoint) {
        let isInside = model.canExpandIsland && isInsideIslandHoverZone(point)
        guard isInside != isPointerInsideHoverZone else { return }
        isPointerInsideHoverZone = isInside
        hoverGeneration += 1
        let generation = hoverGeneration

        if isInside {
            hoverExitTask?.cancel()
            hoverExitTask = nil
            guard model.mode != .expanded else { return }
            let returnMode: IslandMode = model.mode == .collapsed ? .collapsed : .compact
            hoverEnterTask?.cancel()
            hoverEnterTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000)
                guard !Task.isCancelled,
                      let self,
                      hoverGeneration == generation,
                      isPointerInsideHoverZone,
                      model.canExpandIsland,
                      model.mode != .expanded else { return }
                didExpandFromHover = true
                hoverReturnMode = returnMode
                hoverExpectedModeChange = .expanded
                model.requestIslandMode(
                    .expanded,
                    bypassCooldown: true,
                    userInitiated: false
                )
                hoverEnterTask = nil
            }
            return
        }

        hoverEnterTask?.cancel()
        hoverEnterTask = nil
        guard didExpandFromHover else { return }
        hoverExitTask?.cancel()
        hoverExitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled,
                  let self,
                  hoverGeneration == generation,
                  model.mode == .expanded,
                  !isPointerInsideHoverZone else { return }
            didExpandFromHover = false
            let returnMode = hoverReturnMode ?? .compact
            hoverReturnMode = nil
            hoverExpectedModeChange = returnMode
            model.requestIslandMode(
                returnMode,
                bypassCooldown: true,
                userInitiated: false
            )
            hoverExitTask = nil
        }
    }

    private func invalidateHoverSampleAfterStateChange() {
        hoverGeneration += 1
        hoverEnterTask?.cancel()
        hoverEnterTask = nil
        hoverExitTask?.cancel()
        hoverExitTask = nil
        // Force the next real mouseMoved event to establish a fresh boundary
        // crossing. Do not synthesize a crossing from a stale mouse location.
        isPointerInsideHoverZone = false
    }

    private func isInsideIslandHoverZone(_ point: CGPoint) -> Bool {
        guard model.isVisible, let panel, panel.isVisible else { return false }
        if model.mode == .compact,
           model.activeFeature != .music {
            let compactControlZone = CGRect(
                x: panel.frame.maxX - 40,
                y: panel.frame.minY,
                width: 40,
                height: panel.frame.height
            ).insetBy(dx: -3, dy: -3)
            if compactControlZone.contains(point) {
                return false
            }
        }
        return interactionRegions(for: panel.frame, mode: model.mode)
            .contains(point, tolerance: 3)
    }

    private func handleObservedModeChange(_ mode: IslandMode) {
        if hoverExpectedModeChange == mode {
            hoverExpectedModeChange = nil
            return
        }
        hoverExpectedModeChange = nil
        cancelHoverPresentation()
    }

    private func cancelHoverPresentation() {
        guard didExpandFromHover || hoverEnterTask != nil || hoverExitTask != nil else {
            return
        }
        hoverExpectedModeChange = nil
        hoverGeneration += 1
        hoverEnterTask?.cancel()
        hoverEnterTask = nil
        hoverExitTask?.cancel()
        hoverExitTask = nil
        didExpandFromHover = false
        hoverReturnMode = nil
    }

    private func collapseExpandedIslandIfClickIsOutside() {
        collapseExpandedIslandIfClickIsOutside(appKitLocation: NSEvent.mouseLocation)
    }

    private func collapseExpandedIslandIfClickIsOutside(appKitLocation clickPoint: CGPoint) {
        guard model.mode == .expanded, model.isVisible, let panel else { return }
        guard model.appSettings.autoCollapseExpandedIsland else { return }
        if let calibrationWindow,
           calibrationWindow.isVisible,
           calibrationWindow.frame.contains(clickPoint) {
            return
        }
        if let settingsWindow,
           settingsWindow.isVisible,
           settingsWindow.frame.contains(clickPoint) {
            return
        }
        let regions = interactionRegions(for: panel.frame, mode: model.mode)
        guard !regions.contains(clickPoint, tolerance: 2) else { return }
        model.collapseExpandedPresentation()
    }

    private func updateScreenMetrics() {
        guard let screen = targetScreen() else { return }

        model.layout.useDisplay(
            name: screen.localizedName,
            identity: calibrationDisplayIdentity(for: screen),
            legacyIdentities: [legacyCalibrationDisplayIdentity(for: screen)],
            legacyIdentityPrefixes: [legacyCalibrationDisplayIdentityPrefix(for: screen)]
        )

        let geometry = displayGeometry(for: screen)
        activeDisplayGeometry = geometry
        let nextNotchWidth = geometry.notchWidth
        let nextTopBandHeight = geometry.topBandHeight
        if abs(model.notchWidth - nextNotchWidth) > 0.25 {
            model.notchWidth = nextNotchWidth
        }
        if abs(model.topBandHeight - nextTopBandHeight) > 0.25 {
            model.topBandHeight = nextTopBandHeight
        }
        if model.hasCameraHousing != geometry.hasCameraHousing {
            model.hasCameraHousing = geometry.hasCameraHousing
        }
    }

    private func displayGeometry(for screen: NSScreen) -> IslandDisplayGeometry {
        IslandDisplayGeometry.resolve(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
            backingScaleFactor: screen.backingScaleFactor,
            notchHeightAdjustment: CGFloat(model.layout.notchHeightAdjustment)
        )
    }

    private func calibrationDisplayIdentity(for screen: NSScreen) -> String {
        IslandDisplayIdentity.calibrationIdentifier(
            stableIdentifier: stableDisplayIdentity(for: screen),
            frame: screen.frame,
            scale: screen.backingScaleFactor
        )
    }

    private func legacyCalibrationDisplayIdentity(for screen: NSScreen) -> String {
        let screenNumber = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber
        let frame = screen.frame
        return [
            screen.localizedName,
            "\(Int(frame.width))x\(Int(frame.height))",
            "scale\(screen.backingScaleFactor)",
            "id\(screenNumber?.stringValue ?? "unknown")"
        ].joined(separator: "-")
    }

    private func legacyCalibrationDisplayIdentityPrefix(for screen: NSScreen) -> String {
        let frame = screen.frame
        return [
            screen.localizedName,
            "\(Int(frame.width))x\(Int(frame.height))",
            "scale\(screen.backingScaleFactor)",
            "id"
        ].joined(separator: "-")
    }

    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            targetDisplayIdentity = nil
            activeDisplayGeometry = nil
            return nil
        }

        if let targetDisplayIdentity,
           let boundScreen = screens.first(where: {
               stableDisplayIdentity(for: $0) == targetDisplayIdentity
           }) {
            return boundScreen
        }

        let mainIdentity = NSScreen.main.map(stableDisplayIdentity(for:))
        let candidates = screens.map { screen in
            let identity = stableDisplayIdentity(for: screen)
            return IslandDisplayCandidate(
                identity: identity,
                hasCameraHousing: displayGeometry(for: screen).hasCameraHousing,
                isMain: identity == mainIdentity
            )
        }
        guard let selectedIdentity = IslandDisplaySelectionPolicy.selectIdentity(
            boundIdentity: targetDisplayIdentity,
            candidates: candidates
        ), let selectedScreen = screens.first(where: {
            stableDisplayIdentity(for: $0) == selectedIdentity
        }) else {
            return nil
        }

        targetDisplayIdentity = selectedIdentity
        return selectedScreen
    }

    private func stableDisplayIdentity(for screen: NSScreen) -> String {
        let displayID = (screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber)?.uint32Value
        if let displayID, let cachedIdentity = stableDisplayIdentityCache[displayID] {
            return cachedIdentity
        }
        let identity = IslandDisplayIdentity.stableIdentifier(
            displayID: displayID,
            physicalUUID: displayID.flatMap(IslandDisplayIdentity.physicalUUID(for:)),
            displayName: screen.localizedName,
            frame: screen.frame
        )
        if let displayID {
            stableDisplayIdentityCache[displayID] = identity
        }
        return identity
    }

    private func panelSize(for mode: IslandMode) -> NSSize {
        let size = IslandWindowLayout.size(
            for: mode,
            collapsedWidth: model.collapsedWidth,
            compactWidth: model.compactWidth,
            expandedWidth: model.expandedWidth,
            expandedHeight: model.expandedHeight,
            topBandHeight: model.topBandHeight
        )
        return NSSize(width: size.width.rounded(), height: size.height.rounded())
    }

    private func interactionRegions(
        for panelFrame: NSRect,
        mode: IslandMode
    ) -> IslandInteractionRegions {
        let headerWidth: CGFloat
        switch mode {
        case .collapsed:
            headerWidth = model.collapsedWidth
        case .compact:
            headerWidth = model.compactWidth
        case .expanded:
            headerWidth = model.usesUnifiedMusicExpandedSurface
                ? model.expandedWidth
                : model.expandedHeaderWidth
        }
        return IslandInteractionRegions.make(
            panelFrame: panelFrame,
            mode: mode,
            headerWidth: headerWidth,
            topBandHeight: model.topBandHeight,
            expandedBodyHeight: model.expandedBodyHeight,
            expandedPanelTopGap: model.expandedPanelTopGap
        )
    }

    private func repositionPanel(
        animated: Bool,
        targetMode: IslandMode? = nil
    ) {
        guard let panel else { return }
        guard let screen = targetScreen() else { return }

        let mode = targetMode ?? model.mode
        let size = panelSize(for: mode)
        let frame = panelFrame(for: size, on: screen)

        let animationDuration = IslandMotion.frameDuration(
            for: mode,
            reduceMotion: model.reduceMotionEnabled
        )
        stopPanelFrameAnimation()
        // A media/layout change can arrive before the periodic fullscreen
        // check. Recheck before any presentation, including animation start.
        synchronizeFullScreenSuppression()
        guard animated, animationDuration > 0,
              model.isVisible, !isSuppressedByFullScreen else {
            _ = panelAnimationGate.beginAnimation()
            panel.setFrame(frame, display: true)
            panel.contentView?.frame = NSRect(origin: .zero, size: size)
            updatePanelVisibility()
            return
        }

        let animationID = panelAnimationGate.beginAnimation()
        guard panel.frame != frame else { return }

        if model.isVisible, !isSuppressedByFullScreen {
            panel.orderFrontRegardless()
        }

        panelFrameAnimationTarget = frame
        panelFrameAnimationID = animationID
        panel.frameAnimationTarget = frame
        let points = IslandMotion.timingControlPoints(for: mode)
        IslandWindowFrameAnimation.install(on: panel, duration: animationDuration, controlPoints: points)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: Float(points.0), Float(points.1), Float(points.2), Float(points.3)
            )
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.panelFrameAnimationID == animationID,
                      self.panelAnimationGate.claimCompletion(
                        animationID: animationID, targetMode: mode, currentMode: self.model.mode
                      ) else { return }
                // AppKit has submitted the endpoint. Do not snap or retime it.
                self.panel?.frameAnimationTarget = nil
                if let panel = self.panel { IslandWindowFrameAnimation.remove(from: panel) }
                self.panelFrameAnimationTarget = nil
                self.panelFrameAnimationID = nil
            }
        }
    }

    private func stopPanelFrameAnimation() {
        // Freeze an interrupted animator at its currently observed frame.
        // This replaces its pending frame action before the next generation.
        if panelFrameAnimationTarget != nil, let panel {
            let current = panel.frame
            panel.frameAnimationTarget = nil
            IslandWindowFrameAnimation.remove(from: panel)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                panel.animator().setFrame(current, display: false)
            }
        }
        panelFrameAnimationTarget = nil
        panelFrameAnimationID = nil
    }

    private func panelFrame(for size: NSSize, on screen: NSScreen) -> NSRect {
        let geometry: IslandDisplayGeometry
        if let activeDisplayGeometry,
           activeDisplayGeometry.screenFrame == screen.frame {
            geometry = activeDisplayGeometry
        } else {
            geometry = displayGeometry(for: screen)
        }
        return IslandWindowLayout.frame(
            for: size,
            in: screen.frame,
            yOffset: CGFloat(model.layout.islandYOffset),
            anchorX: geometry.islandAnchorX,
            alignTopToWindowServer: true
        )
    }

    private func updatePanelVisibility() {
        guard let panel else { return }
        // Never reveal using a stale timer snapshot after a covering window
        // appeared. This read changes neither focus nor the source player.
        if model.isVisible { synchronizeFullScreenSuppression() }
        if model.isVisible, !isSuppressedByFullScreen {
            panel.orderFrontRegardless()
        } else {
            // Invalidate the old owner before submitting hidden geometry.
            if let target = panelFrameAnimationTarget {
                _ = panelAnimationGate.beginAnimation()
                stopPanelFrameAnimation()
                panel.setFrame(target, display: false)
                panel.contentView?.frame = NSRect(origin: .zero, size: target.size)
            }
            panel.orderOut(nil)
        }
    }

    @objc private func toggleVisibility() {
        model.toggleVisibility()
    }

    @objc private func showMusic() {
        model.isVisible = true
        model.showFeature(.music)
    }

    @objc private func startTimerPreset(_ sender: NSMenuItem) {
        model.isVisible = true
        model.startTimer(minutes: sender.tag)
    }

    @objc private func forceRefreshNowPlaying() {
        model.isVisible = true
        model.forceRefreshNowPlaying()
    }

    @objc private func showAccessibilityStatus() {
        model.isVisible = true
        model.showAccessibilityStatus()
    }

    @objc private func showMusicSourceStatus() {
        model.showMusicSourceStatus()
        showSettings()
    }

    @objc private func showSettings() {
        let window: NSWindow
        if let existingWindow = settingsWindow {
            window = existingWindow
        } else {
            let rootView = IslandSettingsView(model: model)
            let hostingView = NSHostingView(rootView: rootView)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "顶屿设置"
            window.contentView = hostingView
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace]
            settingsWindow = window
        }

        if !window.isVisible {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func presentOpenFeedback(shouldShowSettings: Bool) {
        model.isVisible = true
        if model.mode == .collapsed,
           (model.music.hasCurrentTrack || shouldShowSettings),
           !CommandLine.arguments.contains("--preview-feature"),
           !CommandLine.arguments.contains("--preview-mode") {
            model.handleCollapsedIslandTap()
        }
        repositionPanel(animated: true)
        if shouldShowSettings {
            showSettings()
        }
    }

    @objc private func showCalibration() {
        model.isVisible = true
        model.requestIslandMode(.expanded, bypassCooldown: true)
        repositionPanel(animated: false)

        let window: NSWindow
        if let existingWindow = calibrationWindow {
            window = existingWindow
        } else {
            let rootView = LayoutCalibrationView(model: model, settings: model.layout)
            let hostingView = NSHostingView(rootView: rootView)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 620),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "顶屿布局校准"
            window.contentView = hostingView
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace]
            calibrationWindow = window
        }

        if !window.isVisible {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

@MainActor
private final class AppTerminationSignalBridge {
    private var sources: [DispatchSourceSignal] = []

    init() {
        for signalNumber in [SIGINT, SIGTERM] {
            Darwin.signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(
                signal: signalNumber,
                queue: .main
            )
            source.setEventHandler {
                NSApp.terminate(nil)
            }
            source.resume()
            sources.append(source)
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            settingsWindow?.contentView = nil
            settingsWindow = nil
        } else if window === calibrationWindow {
            calibrationWindow?.contentView = nil
            calibrationWindow = nil
        }
    }
}

struct IslandSettingsView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        TabView {
            GeneralSettingsPane(model: model, settings: model.appSettings)
                .tabItem {
                    Label("常规", systemImage: "switch.2")
                }

            MusicSettingsPane(model: model, settings: model.appSettings)
                .tabItem {
                    Label("音乐", systemImage: "music.note")
                }

            ActivitySettingsPane(model: model, settings: model.appSettings)
                .tabItem {
                    Label("活动", systemImage: "clock")
                }

            LayoutCalibrationView(model: model, settings: model.layout)
                .tabItem {
                    Label("布局", systemImage: "rectangle.and.hand.point.up.left")
                }

            AboutSettingsPane()
                .tabItem {
                    Label("关于", systemImage: "app.badge")
                }
        }
        .padding(10)
        .frame(width: 520, height: 620)
    }
}

private func musicControlStrategyText(_ bundleIdentifier: String?) -> String {
    switch bundleIdentifier {
    case MusicAdapterRegistry.appleMusic.descriptor.bundleIdentifier:
        return "Apple Event 定向"
    case MusicAdapterRegistry.neteaseMusic.descriptor.bundleIdentifier:
        return "网易云 PID 语义 AX"
    default:
        return "汽水唯一语义 AX"
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var settings: AppSettings
    @ObservedObject private var loginItemSettings: LoginItemSettings
    @State private var isConfirmingLayoutReset = false
    @State private var layoutResetStatus: String?
    @State private var isRefreshingPermissions = false

    init(model: IslandModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        loginItemSettings = model.loginItemSettings
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    "登录时自动启动顶屿",
                    isOn: Binding(
                        get: { loginItemSettings.isRequested },
                        set: { loginItemSettings.setEnabled($0) }
                    )
                )
                .disabled(
                    loginItemSettings.isUpdating
                        || loginItemSettings.status == .unavailable
                )

                LabeledContent(
                    "macOS 登录项",
                    value: loginItemSettings.status.title
                )

                if loginItemSettings.status == .requiresApproval {
                    Text("顶屿已经申请登录时启动，但需要你在 macOS“登录项”中允许。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("打开系统登录项设置") {
                        loginItemSettings.openSystemSettings()
                    }
                } else if loginItemSettings.status == .unavailable {
                    Text("请从“应用程序”文件夹运行已签名的顶屿.app，再设置登录时启动。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let errorMessage = loginItemSettings.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("启动后显示顶屿", isOn: $settings.showIslandOnLaunch)

                Toggle("点击外部自动收起展开面板", isOn: $settings.autoCollapseExpandedIsland)

                Toggle("当前显示顶屿", isOn: $model.isVisible)
            }

            Section {
                LabeledContent(
                    "音乐控制",
                    value: musicControlStrategyText(
                        model.music.track.sourceBundleIdentifier
                    )
                )

                Text("控制只发送给当前选中的已适配音乐应用；不切换前台 App、不移动鼠标，也不发送全局媒体键。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("显示音乐诊断信息", isOn: $settings.showMusicDiagnostics)
            } header: {
                Text("控制与诊断")
            }

            Section {
                LabeledContent(
                    "辅助功能",
                    value: model.accessibilityTrusted ? "已授权" : "待授权"
                )
                LabeledContent(
                    "Apple Music 自动化",
                    value: model.appleMusicAutomationAccess.displayName
                )
                LabeledContent(
                    "日历",
                    value: model.eventKitStatus.calendarAccess.displayName
                )
                LabeledContent(
                    "提醒事项",
                    value: model.eventKitStatus.remindersAccess.displayName
                )
                LabeledContent(
                    "减少动态效果",
                    value: model.reduceMotionEnabled ? "已开启" : "已关闭"
                )

                HStack {
                    Button("辅助功能设置") {
                        model.openAccessibilitySettings()
                    }

                    Button("自动化设置") {
                        model.openAppleMusicAutomationSettings()
                    }
                }

                HStack {
                    Button("日历权限") {
                        model.openEventKitPrivacySettings(for: .event)
                    }

                    Button("提醒事项权限") {
                        model.openEventKitPrivacySettings(for: .reminder)
                    }

                    Button("重新检查") {
                        isRefreshingPermissions = true
                        model.refreshMusicIntegrationStatus()
                        Task {
                            await model.refreshEventKitNow()
                            isRefreshingPermissions = false
                        }
                    }
                    .disabled(isRefreshingPermissions)
                }

                Divider()

                LabeledContent("布局配置", value: model.layout.currentDisplayName)

                Button("恢复当前屏幕默认布局") {
                    isConfirmingLayoutReset = true
                }

                if let layoutResetStatus {
                    Text(layoutResetStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Text("权限入口只打开 macOS 系统设置；顶屿不会替你更改授权。布局恢复只影响当前屏幕，不会修改音乐适配或登录项。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("维护与权限")
            }

            Section {
                LabeledContent("默认主活动", value: "前台音乐应用优先")

                Text("没有音乐时，点击空岛可打开快捷面板；音乐、运行中的计时器和提醒事件仍按优先级自动接管。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                HStack {
                    Button("折叠") {
                        model.isVisible = true
                        model.collapseExpandedPresentation()
                    }

                    Button("展开预览") {
                        model.isVisible = true
                        model.requestIslandMode(.expanded, bypassCooldown: true)
                    }

                    Button("隐藏") {
                        model.isVisible = false
                    }
                }
            }

            Section {
                HStack {
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }

                    Button("打开应用程序文件夹") {
                        NSWorkspace.shared.open(Bundle.main.bundleURL.deletingLastPathComponent())
                    }
                }

                Text(Bundle.main.bundlePath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .onAppear {
            loginItemSettings.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            loginItemSettings.refresh()
        }
        .confirmationDialog(
            "恢复当前屏幕的默认布局？",
            isPresented: $isConfirmingLayoutReset,
            titleVisibility: .visible
        ) {
            Button("恢复默认布局") {
                model.layout.resetToDefaults()
                layoutResetStatus = "已恢复 \(model.layout.currentDisplayName) 的默认布局。"
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("当前屏幕的手动位置、尺寸和控件偏移会恢复默认值。")
        }
    }
}

private struct MusicSettingsPane: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var settings: AppSettings
    @State private var isCheckingAppleMusic = false

    private var appleMusicLatencyText: String {
        guard let milliseconds = model.appleMusicResponseLatencyMilliseconds else {
            return "--"
        }
        return "\(milliseconds) ms"
    }

    private var artworkStatusText: String {
        if model.music.track.artworkData != nil || model.music.track.artworkURL != nil {
            return "已获取"
        }
        switch model.musicSourceStatus.availability {
        case .qishuiNotRunning, .preview:
            return "无当前封面"
        default:
            return "等待获取"
        }
    }

    private var availableControlText: String {
        let controls = [
            model.music.canPlayPause ? "播放暂停" : nil,
            model.music.canPreviousTrack ? "上一首" : nil,
            model.music.canNextTrack ? "下一首" : nil
        ].compactMap { $0 }
        return controls.isEmpty
            ? model.music.controlUnavailableReason ?? "不可用"
            : controls.joined(separator: "、")
    }

    private var controlStrategyText: String {
        musicControlStrategyText(model.music.track.sourceBundleIdentifier)
    }

    private var diagnosticText: String {
        [
            "track=\(model.music.track.title) - \(model.music.track.artist)",
            "source=\(model.musicSourceStatus.sourceName)",
            "availability=\(model.musicSourceStatus.availability.rawValue)",
            "isPlaying=\(model.music.isPlaying)",
            "progress=\(String(format: "%.6f", model.music.progress))",
            "elapsedTime=\(model.music.elapsedTime.map { String(format: "%.3f", $0) } ?? "nil")",
            "duration=\(model.music.duration.map { String(format: "%.3f", $0) } ?? "nil")",
            "canSeek=\(model.music.canSeek)",
            "canPlayPause=\(model.music.canPlayPause)",
            "canPreviousTrack=\(model.music.canPreviousTrack)",
            "canNextTrack=\(model.music.canNextTrack)",
            "controlUnavailableReason=\(model.music.controlUnavailableReason ?? "nil")",
            "controlRecovery=\(model.latestMusicControlRecoverySummary)",
            "pending=\(model.music.isPlaybackPending)",
            "artworkBytes=\(model.music.track.artworkData?.count ?? 0)",
            "artworkURL=\(model.music.track.artworkURL?.absoluteString ?? "nil")",
            "checkedAt=\(model.musicSourceStatus.checkedAt.ISO8601Format())",
            "detail=\(model.musicSourceStatus.detail)",
            "appleMusicTimeline:",
            model.appleMusicTransitionDiagnostic
        ].joined(separator: "\n")
    }

    var body: some View {
        Form {
            Section("音乐应用") {
                ForEach(MusicAdapterRegistry.registrations) { registration in
                    MusicAdapterSettingsRow(registration: registration, model: model)
                }
            }

            Section("汽水音乐控制") {
                LabeledContent("应用状态", value: model.qishuiIsRunning ? "运行中" : "未运行")
                LabeledContent(
                    "辅助功能",
                    value: model.accessibilityTrusted ? "已授权" : "控制待授权"
                )
                if !model.accessibilityTrusted {
                    Button {
                        model.openAccessibilitySettings()
                    } label: {
                        Label("打开辅助功能设置", systemImage: "gear")
                    }
                }
                Toggle("显示歌词", isOn: $settings.showMusicLyrics)
                Text("开启后，歌词查询会发送当前歌名和歌手，不上传账号或播放历史；关闭后清空本次运行的歌词时间轴缓存。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("歌词更新时自动展开", isOn: $settings.autoExpandMusicLyrics)
                Text("开启后，歌词快照到达时会自动进入左侧播放控制、右侧歌词阅读区；关闭后保持当前音乐态，仍可通过悬浮或点击手动展开。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("网易云音乐 Alpha 支持") {
                LabeledContent(
                    "运行状态",
                    value: model.neteaseMusicIsRunning ? "运行中" : "未运行"
                )
                LabeledContent(
                    "辅助功能",
                    value: model.accessibilityTrusted ? "已授权" : "控制待授权"
                )
                LabeledContent("连接状态", value: model.neteaseMusicConnectionStatus)
                LabeledContent("可用控制", value: model.neteaseMusicAvailableControls)
                HStack {
                    if !model.accessibilityTrusted {
                        Button {
                            model.openAccessibilitySettings()
                        } label: {
                            Label("打开辅助功能设置", systemImage: "gear")
                        }
                    }
                    Button {
                        Task {
                            await model.refreshNeteaseMusicSnapshot()
                        }
                    } label: {
                        Label("刷新连接", systemImage: "arrow.clockwise")
                    }
                    .disabled(!model.neteaseMusicIsRunning)
                }
                if !model.neteaseMusicIsRunning {
                    Text("请先打开网易云音乐；顶屿不会主动启动它。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Apple Music Alpha 支持") {
                Toggle("启用 Apple Music 适配", isOn: $settings.appleMusicEnabled)

                if settings.appleMusicEnabled {
                    LabeledContent(
                        "运行状态",
                        value: model.appleMusicIsRunning ? "运行中" : "未运行"
                    )
                    LabeledContent(
                        "自动化权限",
                        value: model.appleMusicAutomationAccess.displayName
                    )
                    LabeledContent("连接状态", value: model.appleMusicConnectionStatus)
                    LabeledContent("响应耗时", value: appleMusicLatencyText)
                    LabeledContent("可用控制", value: model.appleMusicAvailableControls)

                    HStack {
                        switch model.appleMusicAutomationAccess {
                        case .denied:
                            Button {
                                model.openAppleMusicAutomationSettings()
                            } label: {
                                Label("打开自动化设置", systemImage: "gear")
                            }
                        case .consentRequired:
                            Button {
                                model.requestAppleMusicAutomationAccess()
                            } label: {
                                Label("请求授权", systemImage: "lock.open")
                            }
                        case .allowed, .targetNotRunning, .unavailable:
                            EmptyView()
                        }

                        Button {
                            isCheckingAppleMusic = true
                            Task {
                                await model.refreshAppleMusicSnapshot()
                                isCheckingAppleMusic = false
                            }
                        } label: {
                            Label("刷新连接", systemImage: "arrow.clockwise")
                        }
                        .disabled(
                            isCheckingAppleMusic
                                || !model.appleMusicIsRunning
                                || model.appleMusicAutomationAccess != .allowed
                        )
                    }

                    if !model.appleMusicIsRunning {
                        Text("请先打开 Apple Music；顶屿不会主动启动它。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Text("电台未提供封面时，仅向 Apple 公共搜索发送当前歌名与歌手。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("当前活动") {
                LabeledContent("当前歌曲", value: "\(model.music.track.title) - \(model.music.track.artist)")
                LabeledContent("同步来源", value: model.musicSourceStatus.sourceName)
                LabeledContent("同步状态", value: model.musicSourceStatus.compactLabel)
                LabeledContent("最近更新", value: musicStatusAgeText(model.musicSourceStatus.checkedAt))
                LabeledContent("播放进度", value: playbackPositionText(model.music))
                LabeledContent("封面状态", value: artworkStatusText)
                LabeledContent("可用控制", value: availableControlText)
                LabeledContent(
                    "控制策略",
                    value: controlStrategyText
                )
                Button {
                    model.showMusicSourceStatus()
                } label: {
                    Label("刷新当前活动", systemImage: "arrow.clockwise")
                }
            }

            if settings.showMusicDiagnostics {
                Section {
                    LabeledContent("最近检查", value: model.musicSourceStatus.checkedAt.formatted(date: .omitted, time: .standard))
                    LabeledContent("UI Progress", value: String(format: "%.4f", model.music.progress))
                    LabeledContent("UI Elapsed", value: model.music.elapsedTime.map(mediaTimeText) ?? "nil")
                    LabeledContent("UI Duration", value: model.music.duration.map(mediaTimeText) ?? "nil")
                    LabeledContent("Can Seek", value: model.music.canSeek ? "true" : "false")
                    LabeledContent("Pending", value: model.music.isPlaybackPending ? "true" : "false")
                    LabeledContent("Artwork Bytes", value: String(model.music.track.artworkData?.count ?? 0))
                    Text(model.musicSourceStatus.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(model.latestAppleMusicTransitionDiagnostic)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    Button("复制诊断信息") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(diagnosticText, forType: .string)
                    }
                } header: {
                    Text("诊断")
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .task {
            model.refreshMusicIntegrationStatus()
            if model.neteaseMusicIsRunning {
                await model.refreshNeteaseMusicSnapshot()
            }
            guard settings.appleMusicEnabled,
                  model.appleMusicIsRunning,
                  model.appleMusicAutomationAccess == .allowed else { return }
            isCheckingAppleMusic = true
            await model.refreshAppleMusicSnapshot()
            isCheckingAppleMusic = false
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didLaunchApplicationNotification
        )) { _ in
            model.refreshMusicIntegrationStatus()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didTerminateApplicationNotification
        )) { _ in
            model.refreshMusicIntegrationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            model.refreshMusicIntegrationStatus()
        }
    }
}

private struct MusicAdapterSettingsRow: View {
    let registration: MusicAdapterRegistration
    @ObservedObject var model: IslandModel

    private var supportColor: Color {
        switch registration.implementationStatus {
        case .active:
            return .green
        case .alpha:
            return .orange
        case .planned:
            return .secondary
        }
    }

    private var runtime: MusicAdapterRuntimePresentation {
        if registration.descriptor.bundleIdentifier
            == MusicAdapterRegistry.qishui.descriptor.bundleIdentifier {
            return MusicAdapterRuntimePresenter.qishui(
                isRunning: model.qishuiIsRunning,
                accessibilityTrusted: model.accessibilityTrusted
            )
        }
        if registration.descriptor.bundleIdentifier
            == MusicAdapterRegistry.neteaseMusic.descriptor.bundleIdentifier {
            return MusicAdapterRuntimePresenter.neteaseMusic(
                isRunning: model.neteaseMusicIsRunning,
                accessibilityTrusted: model.accessibilityTrusted,
                snapshotAvailability: model.neteaseMusicSnapshotAvailability
            )
        }
        return MusicAdapterRuntimePresenter.appleMusic(
            isEnabled: model.appSettings.appleMusicEnabled,
            isRunning: model.appleMusicIsRunning,
            automationAccess: model.appleMusicAutomationAccess,
            snapshotAvailability: model.appleMusicSnapshotAvailability
        )
    }

    private var runtimeColor: Color {
        switch runtime.level {
        case .connected:
            return .green
        case .limited:
            return .blue
        case .actionRequired:
            return .orange
        case .inactive:
            return .secondary
        case .error:
            return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = MusicSourceIconCache.shared.icon(
                    for: registration.descriptor.bundleIdentifier
                ) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(registration.descriptor.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(registration.capabilitySummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(runtime.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 5) {
                Text(registration.implementationStatus.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(supportColor)
                HStack(spacing: 5) {
                    Circle()
                        .fill(runtimeColor)
                        .frame(width: 6, height: 6)
                    Text(runtime.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(runtimeColor)
                }
            }
        }
        .frame(minHeight: 52)
    }
}

private func musicStatusAgeText(_ date: Date) -> String {
    let age = max(Date().timeIntervalSince(date), 0)
    if age < 1 {
        return "刚刚"
    }
    if age < 60 {
        return "\(Int(age)) 秒前"
    }
    return date.formatted(date: .omitted, time: .standard)
}

private struct ActivitySettingsPane: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var settings: AppSettings
    @State private var selectedTimerPreset = FocusTimerPreset.twentyFiveMinutes
    @State private var isRequestingCalendar = false
    @State private var isRequestingReminders = false
    @State private var isRefreshing = false

    private var canRefresh: Bool {
        (settings.calendarEventsEnabled && model.eventKitStatus.calendarAccess.canRead)
            || (settings.remindersEnabled && model.eventKitStatus.remindersAccess.canRead)
    }

    var body: some View {
        Form {
            Section {
                Picker("专注时长", selection: $selectedTimerPreset) {
                    ForEach(FocusTimerPreset.allCases) { preset in
                        Text(preset.compactTitle).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button {
                        model.isVisible = true
                        model.startTimer(minutes: selectedTimerPreset.rawValue)
                    } label: {
                        Label("开始专注", systemImage: "play.fill")
                    }

                    if model.activeFeature == .timer {
                        Button {
                            model.isVisible = true
                            model.showFeature(.timer)
                        } label: {
                            Label("显示计时器", systemImage: "capsule")
                        }
                    }

                    Spacer()

                    if model.timerState.isRunning {
                        Text(timeText(model.timerState.remaining))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("专注计时")
            } footer: {
                Text("计时开始后自动接管顶屿；日程提醒短暂出现后，会返回正在进行的计时。")
            }

            Section {
                LabeledContent("权限", value: model.eventKitStatus.calendarAccess.displayName)

                if model.eventKitStatus.calendarAccess.canRead {
                    Toggle("在岛中显示临近日程", isOn: $settings.calendarEventsEnabled)
                } else if model.eventKitStatus.calendarAccess == .notDetermined {
                    Button("允许访问日历") {
                        isRequestingCalendar = true
                        Task {
                            await model.requestCalendarAccess()
                            isRequestingCalendar = false
                        }
                    }
                    .disabled(isRequestingCalendar)
                } else {
                    Button("打开日历隐私设置") {
                        model.openEventKitPrivacySettings(for: .event)
                    }
                }

                Text("读取所有日历来源中未来 10 分钟内的定时日程；全天日程默认忽略。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } header: {
                Text("日历")
            }

            Section {
                LabeledContent("权限", value: model.eventKitStatus.remindersAccess.displayName)

                if model.eventKitStatus.remindersAccess.canRead {
                    Toggle("在岛中显示到期提醒", isOn: $settings.remindersEnabled)
                } else if model.eventKitStatus.remindersAccess == .notDetermined {
                    Button("允许访问提醒事项") {
                        isRequestingReminders = true
                        Task {
                            await model.requestRemindersAccess()
                            isRequestingReminders = false
                        }
                    }
                    .disabled(isRequestingReminders)
                } else {
                    Button("打开提醒事项隐私设置") {
                        model.openEventKitPrivacySettings(for: .reminder)
                    }
                }

                Text("读取所有提醒清单中刚到期且具有具体时间的提醒，不补发大量历史逾期事项。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } header: {
                Text("提醒事项")
            }

            Section {
                Button("立即检查") {
                    isRefreshing = true
                    Task {
                        await model.refreshEventKitNow()
                        isRefreshing = false
                    }
                }
                .disabled(!canRefresh || isRefreshing)

                if let checkedAt = model.eventKitStatus.lastRefreshAt {
                    LabeledContent(
                        "最近检查",
                        value: checkedAt.formatted(date: .omitted, time: .standard)
                    )
                }

                Text(model.eventKitStatus.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("状态")
            }

            Section {
                Text("授权仅用于读取日程和提醒事项，并把临近或到期事件送入顶屿。不会读取其他 App 的系统通知，也不会修改你的日历和提醒事项。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("隐私")
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }
}

private struct AboutSettingsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: BrandIdentity.applicationImage())
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 4) {
                    Text("顶屿")
                        .font(.system(size: 20, weight: .semibold))
                    Text("TopIslet")
                        .foregroundStyle(.secondary)
                    Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("当前版本以适配音乐为优先主活动；空岛可打开快捷面板，启动专注计时并管理日历与提醒事项。发布前仍需要处理签名、公证和系统更新兼容性。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("源代码许可证：GPL-3.0-only")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct IslandRootView: View {
    @ObservedObject var model: IslandModel
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                // The body is a separate AppKit-height surface. Keeping an
                // invisible copy mounted while compact/collapsed lets its
                // mask and stale lyric subtree participate in the same frame
                // transaction, which can leave a black band below the header.
                // Mount it only for the mode that owns that surface.
                if model.mode == .expanded {
                    ExpandedIslandBodyPanel(model: model)
                        .offset(y: model.usesUnifiedMusicExpandedSurface || model.isLyricExpandedPresentation
                            ? 0
                            : model.topBandHeight + model.expandedPanelTopGap)
                }

                if !model.isLyricExpandedPresentation && !model.usesUnifiedMusicExpandedSurface {
                    IslandShell(
                        width: model.currentHeaderWidth,
                        height: model.topBandHeight,
                        cornerRadius: model.topBandHeight / 2,
                        fillOpacity: 1,
                        strokeOpacity: 0,
                        attachesToTop: true
                    ) {
                        Color.clear
                    }
                }

                // Keep exactly one header tree alive for the current mode.
                // Stacking all three trees with opacity lets AppKit resize the
                // window before SwiftUI removes the old compact tree, which
                // leaves a two-line lyric/black-edge residue during collapse.
                Group {
                    switch model.mode {
                    case .collapsed:
                        CollapsedIsland(model: model)
                    case .compact:
                        CompactIsland(model: model)
                    case .expanded:
                        if model.isLyricExpandedPresentation || model.usesUnifiedMusicExpandedSurface {
                            Color.clear
                        } else {
                            ExpandedIsland(model: model)
                        }
                    }
                }
                .frame(width: model.currentHeaderWidth, height: model.topBandHeight)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contextMenu {
            Button("设置…", action: onOpenSettings)
            Divider()
            Button("退出顶屿", action: onQuit)
        }
        .animation(
            IslandMotion.featureContentAnimation(
                reduceMotion: model.reduceMotionEnabled
            ),
            value: model.activeFeature
        )
    }
}

struct IslandShell<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    var fillOpacity: Double = 0.995
    var strokeOpacity: Double = 0.03
    var shadowOpacity: Double = 0
    var attachesToTop = false
    @ViewBuilder var content: Content

    var body: some View {
        let shape = IslandShellShape(
            cornerRadius: cornerRadius,
            attachesToTop: attachesToTop
        )
        content
            .frame(width: width, height: height)
            .background(
                ZStack {
                    shape
                        .fill(Color.black.opacity(fillOpacity))
                    shape
                        .stroke(Color.white.opacity(strokeOpacity), lineWidth: 0.65)
                }
            )
            .clipShape(shape)
            .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowOpacity > 0 ? 14 : 0, x: 0, y: shadowOpacity > 0 ? 8 : 0)
    }
}

private struct IslandShellShape: Shape {
    let cornerRadius: CGFloat
    let attachesToTop: Bool

    func path(in rect: CGRect) -> Path {
        guard attachesToTop else {
            return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .path(in: rect)
        }
        let radius = min(cornerRadius, rect.width / 2, rect.height)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
            path.closeSubpath()
        }
    }
}

struct CollapsedIsland: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        IslandShell(
            width: model.collapsedWidth,
            height: model.topBandHeight,
            cornerRadius: model.topBandHeight / 2,
            fillOpacity: 0,
            strokeOpacity: 0,
            attachesToTop: true
        ) {
            ZStack {
                HStack(spacing: 0) {
                    Image(systemName: model.activeFeature.iconName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: model.collapsedWingWidth, height: model.topBandHeight)

                    Color.clear
                        .frame(width: model.notchWidth, height: model.topBandHeight)

                    StatusDot(
                        isActive: model.statusWaveIsActive,
                        accentColor: model.statusWaveColor
                    )
                        .frame(width: model.collapsedWingWidth, height: model.topBandHeight)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.handleCollapsedIslandTap()
        }
    }
}

struct CompactIsland: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        IslandShell(
            width: model.compactWidth,
            height: model.topBandHeight,
            cornerRadius: model.topBandHeight / 2,
            fillOpacity: 0,
            strokeOpacity: 0,
            attachesToTop: true
        ) {
            ZStack {
                Group {
                    switch model.activeFeature {
                    case .activityCenter:
                        Color.clear
                    case .music:
                        CompactMusic(model: model)
                    case .timer:
                        CompactTimer(model: model)
                    case .notification:
                        CompactNotification(model: model)
                    }
                }
            }
        }
    }
}

struct ExpandedIsland: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        IslandShell(
            width: model.expandedHeaderWidth,
            height: model.topBandHeight,
            cornerRadius: model.topBandHeight / 2,
            fillOpacity: 0,
            strokeOpacity: 0,
            attachesToTop: true
        ) {
            ZStack {
                HStack(spacing: 0) {
                    Image(systemName: model.activeFeature.iconName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: model.expandedHeaderWingWidth, height: model.topBandHeight)

                    Color.clear
                        .frame(width: model.notchWidth, height: model.topBandHeight)

                    StatusDot(
                        isActive: model.statusWaveIsActive,
                        accentColor: model.statusWaveColor
                    )
                        .frame(width: model.expandedHeaderWingWidth, height: model.topBandHeight)
                }
            }
        }
    }
}

struct ExpandedIslandBodyPanel: View {
    @ObservedObject var model: IslandModel

    private var shellScaleX: CGFloat {
        guard model.mode != .expanded else { return 1 }
        let targetWidth = model.mode == .collapsed ? model.collapsedWidth : model.compactWidth
        return targetWidth / model.expandedWidth
    }

    private var shellScaleY: CGFloat {
        model.mode == .expanded ? 1 : 0.025
    }

    var body: some View {
        ZStack(alignment: .top) {
            IslandShell(
                width: model.expandedWidth,
                height: model.expandedBodyHeight,
                cornerRadius: 24,
                // Both music states share the same translucent glass capsule.
                // The previous opaque shell plus inner material card was the
                // second visible box in the supplied screenshot.
                fillOpacity: model.activeFeature == .music ? 0 : 1,
                strokeOpacity: model.activeFeature == .music ? 0.12 : 0,
                shadowOpacity: model.activeFeature == .music ? 0.18 : 0
            ) {
                ZStack {
                    if model.activeFeature == .music {
                        MusicGlassBackground()
                        Color.black.opacity(0.30)
                    }
                }
            }
            .scaleEffect(x: shellScaleX, y: shellScaleY, anchor: .top)
            .opacity(model.mode == .expanded ? 1 : 0)

            ZStack(alignment: .topTrailing) {
                switch model.activeFeature {
                case .activityCenter:
                    ExpandedActivityCenter(model: model)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 12)

                case .music:
                    ExpandedMusic(model: model)
                        .padding(.horizontal, 16)
                        // Camera housing occupies the menu-bar band. Both
                        // columns start below it, inside the same capsule.
                        .padding(.top, model.topBandHeight)

                case .timer, .notification:
                    VStack(spacing: 8) {
                        HStack(alignment: .center) {
                            if model.hasPendingNotification, model.activeFeature != .notification {
                                Button {
                                    model.showPendingNotification()
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "bell.fill")
                                        Text(model.notification.count > 1 ? "\(model.notification.count) 条提醒" : "提醒")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .foregroundStyle(.white.opacity(0.78))
                                    .padding(.horizontal, 8)
                                    .frame(height: 24)
                                    .background(Capsule().fill(Color.white.opacity(0.08)))
                                }
                                .buttonStyle(.plain)
                                .help("查看提醒")
                            }
                            Spacer(minLength: 12)
                            WindowModeButtons(model: model)
                        }
                        .frame(height: 24)

                        Group {
                            if model.activeFeature == .timer {
                                ExpandedTimer(model: model)
                            } else {
                                ExpandedNotification(model: model)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                }

                if model.activeFeature == .music {
                    WindowModeButtons(model: model)
                        .padding(.top, 4)
                        .padding(.trailing, 16)
                }
            }
            .frame(width: model.expandedWidth, height: model.expandedBodyHeight)
            .opacity(model.mode == .expanded ? 1 : 0)
            .mask {
                Rectangle()
                    .scaleEffect(x: shellScaleX, y: shellScaleY, anchor: .top)
            }
            .allowsHitTesting(model.mode == .expanded)
        }
        .frame(width: model.expandedWidth, height: model.expandedBodyHeight)
    }
}

struct WindowModeButtons: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.collapseExpandedPresentation()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.68))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("收起")

            Button {
                model.requestIslandMode(.collapsed, bypassCooldown: true)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.68))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("最小化")
        }
    }
}

struct ExpandedActivityCenter: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("专注计时", systemImage: "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                Spacer(minLength: 12)
                Button {
                    model.requestIslandMode(.collapsed, bypassCooldown: true)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.68))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("收起快捷面板")
                .accessibilityLabel("收起快捷面板")
            }
            .frame(height: 28)

            HStack(spacing: 12) {
                ForEach(FocusTimerPreset.allCases) { preset in
                    Button {
                        model.startTimer(minutes: preset.rawValue)
                    } label: {
                        Text("\(preset.rawValue) 分")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.86))
                            .frame(width: 52, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.white.opacity(0.09))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("开始 \(preset.title)专注计时")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)

            if model.shouldPresentMusicControlRecovery {
                Divider().overlay(Color.white.opacity(0.08))

                HStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.isRecoveringMusicControl ? "正在连接播放控制" : "音乐控制暂不可用")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.86))
                        Text(model.isRecoveringMusicControl
                            ? "正在重新打开汽水音乐"
                            : (model.musicControlRecoveryNeedsUserAction
                                ? "连接未完成，可再次尝试"
                                : "不会自动打开汽水音乐"))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.white.opacity(0.48))
                    }

                    Spacer(minLength: 8)

                    Button {
                        model.recoverCurrentMusicControl()
                    } label: {
                        HStack(spacing: 5) {
                            if model.isRecoveringMusicControl {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(model.isRecoveringMusicControl ? "连接中" : "重启并连接")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isRecoveringMusicControl)
                    .help(model.isRecoveringMusicControl ? "正在连接汽水音乐播放控制" : "点击会重启一次汽水音乐并连接播放控制；不会自动打开汽水音乐")
                    .accessibilityLabel(model.isRecoveringMusicControl ? "正在连接汽水音乐播放控制" : "重启并连接汽水音乐播放控制")
                }
                .frame(height: 38)
            }

            Divider().overlay(Color.white.opacity(0.08))

            ActivityPermissionRow(
                model: model,
                title: "日历",
                icon: "calendar",
                entityType: .event
            )

            Divider().overlay(Color.white.opacity(0.08))

            ActivityPermissionRow(
                model: model,
                title: "提醒事项",
                icon: "checklist",
                entityType: .reminder
            )
        }
    }
}

private struct ActivityPermissionRow: View {
    @ObservedObject var model: IslandModel
    let title: String
    let icon: String
    let entityType: EKEntityType
    @State private var isRequesting = false

    private var access: EventKitAccessState {
        entityType == .event
            ? model.eventKitStatus.calendarAccess
            : model.eventKitStatus.remindersAccess
    }

    private var isEnabled: Binding<Bool> {
        Binding(
            get: {
                entityType == .event
                    ? model.appSettings.calendarEventsEnabled
                    : model.appSettings.remindersEnabled
            },
            set: { enabled in
                if entityType == .event {
                    model.appSettings.calendarEventsEnabled = enabled
                } else {
                    model.appSettings.remindersEnabled = enabled
                }
            }
        )
    }

    private var statusText: String {
        guard access.canRead else { return access.displayName }
        return isEnabled.wrappedValue ? "已开启" : "已关闭"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 18)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))

            Spacer(minLength: 10)

            Text(statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)

            if access.canRead {
                Toggle("", isOn: isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help(isEnabled.wrappedValue ? "关闭\(title)活动" : "开启\(title)活动")
            } else {
                Button {
                    if access == .notDetermined {
                        isRequesting = true
                        Task {
                            if entityType == .event {
                                await model.requestCalendarAccess()
                            } else {
                                await model.requestRemindersAccess()
                            }
                            isRequesting = false
                        }
                    } else {
                        model.openEventKitPrivacySettings(for: entityType)
                    }
                } label: {
                    Image(systemName: access == .notDetermined ? "arrow.right.circle.fill" : "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(isRequesting)
                .help(access == .notDetermined ? "请求\(title)访问" : "打开\(title)隐私设置")
            }
        }
        .frame(height: 38)
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static let defaultValue = MarqueeTextMeasurement(text: "", width: 0)

    static func reduce(value: inout MarqueeTextMeasurement, nextValue: () -> MarqueeTextMeasurement) {
        value = nextValue()
    }
}

private final class MarqueeClock: ObservableObject {
    @Published private(set) var start = Date()

    func restart() {
        start = Date()
    }
}

private struct MarqueeLine: View {
    let text: String
    let font: Font
    let color: Color
    let offset: CGFloat
    let lineHeight: CGFloat

    var body: some View {
        Text(text)
        .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            // Preserve intrinsic width for horizontal scrolling while letting
            // the taller line box center the full glyph run inside the safe
            // band. A font-sized vertical frame clips ascenders and descenders.
            .fixedSize(horizontal: true, vertical: true)
            .offset(x: -offset)
            .frame(
                maxWidth: .infinity,
                minHeight: lineHeight,
                maxHeight: lineHeight,
                alignment: .leading
            )
    }
}

private struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let lineHeight: CGFloat
    var clock: MarqueeClock? = nil
    @State private var measurement: MarqueeTextMeasurement?
    @State private var animationStart = Date()

    var body: some View {
        GeometryReader { proxy in
            let baseDate = clock?.start ?? animationStart
            let overflow = MarqueeTextLayoutPolicy.overflow(
                for: text,
                measurement: measurement,
                viewportWidth: proxy.size.width
            )
            TimelineView(
                .animation(minimumInterval: 1.0 / 30.0, paused: overflow <= 0 || text.isEmpty)
            ) { (context: TimelineViewDefaultContext) in
                let offset = MusicMarqueeTimeline.offset(
                    elapsed: context.date.timeIntervalSince(baseDate),
                    overflow: overflow,
                    speed: MusicMarqueeTimeline.speed(for: overflow)
                )
                MarqueeLine(
                    text: text,
                    font: font,
                    color: color,
                    offset: offset,
                    lineHeight: lineHeight
                )
            }
            // Constrain TimelineView to the measured column: its fixed-size
            // text must not expand the clipping viewport past the capsule.
            .frame(width: proxy.size.width, height: lineHeight, alignment: .leading)
            .clipped()
            .mask {
                // Fade only the trailing edge. Fading the leading 6% made the
                // first glyph look clipped at the resting position, which is
                // especially obvious for short bilingual lyric pairs.
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.96),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .background(
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
                    .background(
                        GeometryReader { measured in
                            Color.clear.preference(
                                key: MarqueeTextWidthKey.self,
                                value: MarqueeTextMeasurement(text: text, width: measured.size.width)
                            )
                        }
                    )
                    .hidden()
            )
        }
        .frame(height: lineHeight)
        .onPreferenceChange(MarqueeTextWidthKey.self) { nextMeasurement in
            if measurement != nextMeasurement {
                measurement = nextMeasurement
                if clock == nil {
                    animationStart = Date()
                }
            }
        }
        .onChange(of: text) { _, _ in
            measurement = nil
            if clock == nil {
                animationStart = Date()
            }
        }
        .onAppear {
            if clock == nil {
                animationStart = Date()
            }
        }
    }

}

private struct KaraokeLyricWidthKey: PreferenceKey {
    static let defaultValue: MarqueeTextMeasurement? = nil

    static func reduce(value: inout MarqueeTextMeasurement?, nextValue: () -> MarqueeTextMeasurement?) {
        value = nextValue() ?? value
    }
}

/// Renders a verified active lyric as a normal karaoke line: characters that
/// have been reached use the strong color, while the remaining characters stay
/// visible but quiet. Qishui currently exposes active rows, not LRC/word
/// timestamps, so the reveal is deliberately an honest visual estimate and
/// resets whenever the source advances to another active row.
private struct KaraokeLyricText: View {
    let text: String
    let font: Font
    let highlightedColor: Color
    let unhighlightedColor: Color
    let lineHeight: CGFloat
    let clock: MarqueeClock
    let isPlaying: Bool
    let words: [QishuiTimedWord]
    let elapsedTime: TimeInterval
    let sampledAt: Date
    @State private var measurement: MarqueeTextMeasurement?

    var body: some View {
        GeometryReader { proxy in
            let baseDate = clock.start
            let overflow = MarqueeTextLayoutPolicy.overflow(
                for: text,
                measurement: measurement,
                viewportWidth: proxy.size.width
            )
            let glyphs: [(String, TimeInterval)] = words.flatMap { word in
                let characters = Array(word.text)
                return characters.enumerated().map { index, character in
                    let fraction = Double(index) / Double(max(characters.count, 1))
                    return (String(character), word.start + (word.end - word.start) * fraction)
                }
            }
            TimelineView(
                .animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying || text.isEmpty)
            ) { (context: TimelineViewDefaultContext) in
                let elapsed = max(context.date.timeIntervalSince(baseDate), 0)
                let position = elapsedTime + (isPlaying ? max(context.date.timeIntervalSince(sampledAt), 0) : 0)
                let offset = MusicMarqueeTimeline.offset(
                    elapsed: elapsed,
                    overflow: overflow,
                    speed: MusicMarqueeTimeline.speed(for: overflow)
                )
                let reached = glyphs.firstIndex { $0.1 > position } ?? glyphs.count
                let sung = glyphs[..<reached].map(\.0).joined()
                let upcoming = glyphs[reached...].map(\.0).joined()
                (Text(sung).foregroundColor(highlightedColor)
                    + Text(upcoming).foregroundColor(unhighlightedColor))
                .font(font)
                .fixedSize(horizontal: true, vertical: true)
                .offset(x: -offset)
                .frame(maxWidth: .infinity, minHeight: lineHeight, maxHeight: lineHeight, alignment: .leading)
            }
            .frame(width: proxy.size.width, height: lineHeight, alignment: .leading)
            .clipped()
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.96),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .background(
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
                    .background(
                        GeometryReader { measured in
                            Color.clear.preference(
                                key: KaraokeLyricWidthKey.self,
                                value: MarqueeTextMeasurement(text: text, width: measured.size.width)
                            )
                        }
                    )
                    .hidden()
            )
        }
        .frame(height: lineHeight)
        .onPreferenceChange(KaraokeLyricWidthKey.self) { nextMeasurement in
            if measurement != nextMeasurement {
                measurement = nextMeasurement
            }
        }
    }
}

struct CompactMusic: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                AlbumArt(track: model.music.track, size: 25)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.music.track.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(.white)
                    Text(model.music.track.artist)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            .padding(.leading, 10)
            .frame(width: model.compactLeadingWingWidth, height: model.topBandHeight, alignment: .leading)

            Color.clear
                .frame(width: model.notchWidth, height: model.topBandHeight)

            HStack(spacing: 9) {
                ProgressPill(
                    progress: model.music.progress,
                    width: 54,
                    accentColor: model.musicAccentColor
                )

                StatusDot(
                    isActive: model.statusWaveIsActive,
                    accentColor: model.statusWaveColor
                )
                .frame(width: 10, height: 10)
            }
            .padding(.trailing, 10)
            .frame(width: model.compactTrailingWingWidth, height: model.topBandHeight, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.music.track.title)，\(model.music.track.artist)")
        .onTapGesture {
            model.requestIslandMode(.expanded)
        }
    }
}

struct CompactTimer: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 25, height: 25)
                    .background(Circle().fill(Color.white.opacity(0.08)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(timeText(model.timerState.remaining))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    ProgressPill(progress: model.timerState.progress, width: 96)
                }
            }
            .padding(.leading, 10)
            .frame(width: model.compactWingWidth, height: model.topBandHeight, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                model.requestIslandMode(.expanded)
            }

            Color.clear
                .frame(width: model.notchWidth, height: model.topBandHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.requestIslandMode(.expanded)
                }

            ZStack(alignment: .trailing) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.requestIslandMode(.expanded)
                    }

                ControlButton(icon: model.timerState.isRunning ? "pause.fill" : "play.fill", size: 27) {
                    model.toggleTimer()
                }
                .help(model.timerState.isRunning ? "暂停计时" : "开始计时")
                .padding(.trailing, 10)
            }
            .frame(width: model.compactWingWidth, height: model.topBandHeight, alignment: .trailing)
        }
    }
}

struct CompactNotification: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 25, height: 25)
                        .background(Circle().fill(Color.white.opacity(0.1)))

                    if model.notification.count > 1 {
                        Text("\(model.notification.count)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 13, height: 13)
                            .background(Circle().fill(Color.white))
                            .offset(x: 4, y: -4)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.notification.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                    Text(model.notification.body)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            .padding(.leading, 10)
            .frame(width: model.compactWingWidth, height: model.topBandHeight, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                model.requestIslandMode(.expanded)
            }

            Color.clear
                .frame(width: model.notchWidth, height: model.topBandHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    model.requestIslandMode(.expanded)
                }

            ZStack(alignment: .trailing) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.requestIslandMode(.expanded)
                    }

                ControlButton(icon: "xmark", size: 27) {
                    model.dismissNotification()
                }
                .help("关闭提醒")
                .padding(.trailing, 10)
            }
            .frame(width: model.compactWingWidth, height: model.topBandHeight, alignment: .trailing)
        }
    }
}

struct ExpandedMusic: View {
    @ObservedObject var model: IslandModel

    private var lyricPairs: (current: LyricPair, next: LyricPair) {
        MusicLyricPresentation.sourceCurrentAndNextPairs(
            lines: model.music.track.lyrics,
            index: model.music.lyricIndex,
            pairMixedLanguageLines: !model.music.track.lyricsAreDesktopSnapshot
        )
    }

    private var hasLyrics: Bool {
        MusicLyricPresentation.hasDisplayableLines(model.music.track.lyrics)
    }

    var body: some View {
        if model.isMusicLyricsEnabled && hasLyrics {
            LyricExpandedMusic(model: model, lyricPairs: lyricPairs)
        } else {
            ControlOnlyExpandedMusic(model: model)
        }
    }
}

private struct MusicGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct MusicTransportControls: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(spacing: 13) {
                if model.shouldPresentMusicControlRecovery {
                    Button {
                        model.recoverCurrentMusicControl()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text(model.isRecoveringMusicControl ? "连接中" : "恢复控制")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .frame(width: 104, height: 48)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isRecoveringMusicControl)
                    .help("重启并连接汽水音乐播放控制")
                } else {
                    HStack(spacing: 6) {
                        ControlButton(icon: "backward.fill", size: 29) {
                            model.previousTrack()
                        }
                        .disabled(!model.music.canPreviousTrack && !model.canRecoverCurrentMusicControlPermission)
                        .help("上一首")
                        .accessibilityLabel("上一首")
                        .accessibilityIdentifier("topislet.music.previous")

                        ControlButton(
                            icon: model.music.playbackStateKnown
                                ? (model.music.isPlaying ? "pause.fill" : "play.fill")
                                : "questionmark",
                            prominent: true
                        ) {
                            model.playPause()
                        }
                        .disabled(!model.music.canPlayPause && !model.canRecoverCurrentMusicControlPermission)
                        .help(model.music.playbackStateKnown
                            ? (model.music.isPlaying ? "暂停" : "播放")
                            : "正在确认播放状态，点击切换播放")
                        .accessibilityLabel(model.music.playbackStateKnown
                            ? (model.music.isPlaying ? "暂停" : "播放") : "切换播放")
                        .accessibilityIdentifier("topislet.music.playPause")

                        ControlButton(icon: "forward.fill", size: 29) {
                            model.nextTrack()
                        }
                        .disabled(!model.music.canNextTrack && !model.canRecoverCurrentMusicControlPermission)
                        .help("下一首")
                        .accessibilityLabel("下一首")
                        .accessibilityIdentifier("topislet.music.next")
                    }
                }

                if !model.music.playbackStateKnown {
                    Text("状态同步中")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
        }
    }
}

private struct LyricMusicLeftRail: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(alignment: .center, spacing: ExpandedMusicLayout.artworkToDetailsSpacing) {
            AlbumArt(track: model.music.track, size: ExpandedMusicLayout.artworkSize)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.music.track.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.96))
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Text(model.music.track.artist)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(width: 118, alignment: .leading)

                MusicTransportControls(model: model)
                    .frame(width: 110, alignment: .leading)
            }
            .frame(width: 118, alignment: .leading)
        }
        .frame(width: ExpandedMusicLayout.controlContentWidth, alignment: .leading)
    }
}

private struct ControlOnlyExpandedMusic: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: ExpandedMusicLayout.controlToLyricSpacing) {
            LyricMusicLeftRail(model: model)
                // This card is shorter than the lyric card. Keep the title's
                // second line clear of the top band when metadata wraps.
                .offset(y: -model.topBandHeight / 4)
            VStack(alignment: .leading, spacing: 12) {
                Text(model.isMusicLyricsEnabled
                    ? (MusicLyricPresentation.isConfirmedInstrumental(model.music.track.lyrics)
                        ? "纯音乐，请欣赏" : "歌词暂未读取到")
                    : "歌词显示已关闭")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                MusicProgressRow(model: model)
            }
            .frame(width: ExpandedMusicLayout.detailsWidth, alignment: .leading)
        }
        .frame(width: ExpandedMusicLayout.controlOnlyContentWidth,
               height: MusicExpandedLayout.noLyricsBodyHeight)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 1, height: 82)
                .offset(x: ExpandedMusicLayout.controlContentWidth + ExpandedMusicLayout.controlToLyricSpacing / 2)
                .allowsHitTesting(false)
        }
    }
}

private struct LyricExpandedMusic: View {
    @ObservedObject var model: IslandModel
    let lyricPairs: (current: LyricPair, next: LyricPair)

    var body: some View {
        HStack(spacing: ExpandedMusicLayout.controlToLyricSpacing) {
            LyricMusicLeftRail(model: model)
                .offset(y: -model.topBandHeight / 2)
            VStack(alignment: .leading, spacing: 8) {
                LyricsShelf(
                    current: lyricPairs.current,
                    next: lyricPairs.next,
                    isDesktopSnapshot: model.music.track.lyricsAreDesktopSnapshot,
                    accent: model.musicAccentColor,
                    isPlaying: model.music.isPlaying,
                    timedWords: model.music.track.timedWords,
                    elapsedTime: model.music.elapsedTime,
                    sampledAt: model.musicTimelineSampledAt
                )
                .offset(y: 14)
                MusicProgressRow(
                    model: model,
                    timelineWidth: ExpandedMusicLayout.lyricTimelineWidth,
                    prominent: true
                )
                .offset(y: -6)
            }
            .frame(width: ExpandedMusicLayout.lyricColumnWidth, alignment: .leading)
        }
        .frame(width: ExpandedMusicLayout.contentWidth,
               height: MusicExpandedLayout.lyricsBodyHeight)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 1, height: 110)
                .offset(x: ExpandedMusicLayout.controlContentWidth + ExpandedMusicLayout.controlToLyricSpacing / 2)
                .allowsHitTesting(false)
        }
    }
}

private struct LyricsShelf: View {
    let current: LyricPair
    let next: LyricPair
    let isDesktopSnapshot: Bool
    let accent: Color
    let isPlaying: Bool
    let timedWords: [QishuiTimedWord]
    let elapsedTime: TimeInterval?
    let sampledAt: Date
    @StateObject private var lyricClock = MarqueeClock()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            lyricLines
                .id(current.primary + "\u{1f}" + current.translation + "\u{1f}" + next.primary)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .offset(y: 14).combined(with: .opacity),
                    removal: .offset(y: -14).combined(with: .opacity)
                ))
        }
        .frame(width: ExpandedMusicLayout.lyricColumnWidth, height: 100, alignment: .topLeading)
        .clipped()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isDesktopSnapshot
            ? "桌面歌词：\(current.primary)\(current.translation.isEmpty ? "" : "，\(current.translation)")\(next.primary.isEmpty ? "" : "，下一句：\(next.primary)")"
            : "当前歌词：\(current.primary)\(current.translation.isEmpty ? "" : "，\(current.translation)")\(next.primary.isEmpty ? "" : "，下一句：\(next.primary)")")
        .onChange(of: current) { _, _ in
            lyricClock.restart()
        }
    }

    private var lyricLines: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 9) {
                Capsule()
                    .fill(accent.opacity(0.95))
                    .frame(width: 3, height: 28)
                if let elapsedTime, !timedWords.isEmpty {
                    KaraokeLyricText(
                        text: current.primary,
                        font: .system(size: 23, weight: .semibold),
                        highlightedColor: .white.opacity(0.98),
                        unhighlightedColor: .white.opacity(0.34),
                        lineHeight: 29,
                        clock: lyricClock,
                        isPlaying: isPlaying,
                        words: timedWords,
                        elapsedTime: elapsedTime,
                        sampledAt: sampledAt
                    )
                } else {
                    MarqueeText(
                        text: current.primary,
                        font: .system(size: 23, weight: .semibold),
                        color: .white.opacity(0.98),
                        lineHeight: 29,
                        clock: lyricClock
                    )
                }
            }

            if !current.translation.isEmpty {
                MarqueeText(
                    text: current.translation,
                    font: .system(size: 14, weight: .regular),
                    color: .white.opacity(0.62),
                    lineHeight: 19,
                    clock: lyricClock
                )
                .padding(.leading, 12)
            }

            if !next.primary.isEmpty && next.primary != current.primary {
                MarqueeText(
                    text: next.primary,
                    font: .system(size: 16, weight: .medium),
                    color: .white.opacity(0.38),
                    lineHeight: 21,
                    clock: lyricClock
                )
                .padding(.leading, 12)
            }

        }
        .frame(width: ExpandedMusicLayout.lyricColumnWidth, alignment: .leading)
    }
}

private struct MusicProgressRow: View {
    @ObservedObject var model: IslandModel
    let timelineWidth: CGFloat
    let prominent: Bool
    @State private var scrubPreviewProgress: Double?

    init(model: IslandModel, timelineWidth: CGFloat = ExpandedMusicLayout.timelineWidth, prominent: Bool = false) {
        _model = ObservedObject(wrappedValue: model)
        self.timelineWidth = timelineWidth
        self.prominent = prominent
    }

    var body: some View {
        HStack(spacing: ExpandedMusicLayout.timelineToTimeSpacing) {
            ProgressPill(
                progress: model.music.progress,
                width: timelineWidth,
                accentColor: model.musicAccentColor,
                prominent: prominent,
                onPreviewChanged: { progress in
                    model.setMusicScrubbing(progress != nil)
                    guard let progress else {
                        scrubPreviewProgress = nil
                        return
                    }

                    if let duration = model.music.duration, duration > 0,
                       let currentPreview = scrubPreviewProgress,
                       Int(currentPreview * duration) == Int(progress * duration) {
                        return
                    }
                    scrubPreviewProgress = progress
                },
                onSeek: (model.music.canSeek
                    || (model.music.track.sourceBundleIdentifier == "com.soda.music"
                        && model.music.hasCurrentTrack
                        && (model.music.duration ?? 0) > 0)) ? { progress, interaction in
                    await model.seekMusic(to: progress, interaction: interaction)
                } : nil
            )
            .help(model.music.canSeek ? "拖动调整播放进度" : "当前歌曲暂不支持进度拖动")

            Text(playbackPositionText(model.music, progressOverride: scrubPreviewProgress))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .foregroundStyle(.white.opacity(0.52))
                .frame(width: ExpandedMusicLayout.timeWidth, alignment: .leading)
        }
        .padding(.horizontal, prominent ? 11 : 0)
        .frame(height: prominent ? 30 : nil)
        .background {
            if prominent {
                RoundedRectangle(cornerRadius: 15)
                    .fill(.white.opacity(0.065))
            }
        }
        .onDisappear {
            model.setMusicScrubbing(false)
        }
    }
}

struct ExpandedTimer: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: model.timerState.progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(timeText(model.timerState.remaining))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 7) {
                Text(model.timerState.isRunning ? "专注计时中" : "计时器已暂停")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                ProgressPill(progress: model.timerState.progress, width: 232)
                HStack(spacing: 10) {
                    ControlButton(icon: model.timerState.isRunning ? "pause.fill" : "play.fill", prominent: true) {
                        model.toggleTimer()
                    }
                    .help(model.timerState.isRunning ? "暂停" : "开始")

                    ControlButton(icon: "arrow.counterclockwise") {
                        model.resetTimer()
                    }
                    .help("重置")

                    ControlButton(icon: "plus") {
                        model.addMinute()
                    }
                    .help("加 1 分钟")
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: 232, alignment: .leading)

        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct ExpandedNotification: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Color.white.opacity(0.1)))

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.notification.source)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                    Text(model.notification.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(model.notification.body)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer()
            }

            HStack(spacing: 12) {
                if model.canOpenActiveEventSource {
                    TextButton(title: "打开", systemName: "arrow.up.forward.app") {
                        model.openActiveEventSource()
                    }
                }
                TextButton(title: "关闭", systemName: "xmark") {
                    model.dismissNotification()
                }
                Spacer()
            }
        }
    }
}

func cleanIslandLyricLines(_ lines: [String]) -> [String] {
    MusicLyricPresentation.clean(lines)
}

struct AlbumArt: View {
    let track: MusicTrack
    let size: CGFloat

    var body: some View {
        ZStack {
            if let artworkData = track.artworkData,
               let image = AlbumArtworkImageCache.shared.image(for: artworkData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let artworkURL = track.artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackArtwork
                    }
                }
            } else {
                fallbackArtwork
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if size >= 60 {
                MusicSourceBadge(bundleIdentifier: track.sourceBundleIdentifier, size: 18)
                    .offset(x: 3, y: 3)
            }
        }
    }

    private var fallbackArtwork: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: track.hasArtwork ? track.palette : [Color.white.opacity(0.13), Color.white.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: size * 0.55, height: size * 0.55)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                }
            }
    }
}

@MainActor
private final class MusicSourceIconCache {
    static let shared = MusicSourceIconCache()

    private var icons: [String: NSImage] = [:]
    private var missingBundleIdentifiers: Set<String> = []

    func icon(for bundleIdentifier: String) -> NSImage? {
        if let cached = icons[bundleIdentifier] {
            return cached
        }
        if missingBundleIdentifiers.contains(bundleIdentifier) {
            return nil
        }
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            missingBundleIdentifiers.insert(bundleIdentifier)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        icons[bundleIdentifier] = icon
        return icon
    }
}

private struct MusicSourceBadge: View {
    let bundleIdentifier: String?
    let size: CGFloat

    private var applicationIcon: NSImage? {
        guard let bundleIdentifier else { return nil }
        return MusicSourceIconCache.shared.icon(for: bundleIdentifier)
    }

    var body: some View {
        Group {
            if let applicationIcon {
                Image(nsImage: applicationIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size + 2, height: size + 2)
                    .frame(width: size, height: size)
                    .clipShape(
                        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    )
                    .compositingGroup()
                    .transition(.opacity)
            } else if bundleIdentifier != nil {
                Image(systemName: "music.note")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: size, height: size)
                    .background(
                        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                            .fill(Color.black.opacity(0.9))
                    )
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.14), value: bundleIdentifier)
    }
}

struct ControlButton: View {
    let icon: String
    var prominent = false
    var size: CGFloat = 30
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        prominent
                            ? Color.white
                            : Color.white.opacity(isHovering ? 0.16 : 0.1)
                    )

                Image(systemName: icon)
                    .font(.system(size: prominent ? 13 : 12, weight: .bold))
                    .foregroundStyle(prominent ? Color.black : Color.white.opacity(0.9))
                    .id(icon)
                    .transition(iconTransition)
            }
            .frame(width: prominent ? 34 : size, height: prominent ? 34 : size)
        }
        .buttonStyle(IslandControlButtonStyle())
        .opacity(isEnabled ? 1 : 0.38)
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.08)
                : prominent
                    ? .easeOut(duration: 0.1)
                    : .interactiveSpring(response: 0.2, dampingFraction: 0.86),
            value: icon
        )
    }

    private var iconTransition: AnyTransition {
        guard !reduceMotion, !prominent else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.76)),
            removal: .opacity.combined(with: .scale(scale: 1.08))
        )
    }

}

private struct IslandControlButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .brightness(configuration.isPressed ? 0.1 : 0)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.06)
                    : .interactiveSpring(response: 0.16, dampingFraction: 0.9),
                value: configuration.isPressed
            )
    }
}

struct TextButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(Capsule().fill(Color.white))
        }
        .buttonStyle(.plain)
    }
}

struct ProgressPill: View {
    let progress: Double
    let width: CGFloat
    var accentColor: Color = .white
    var prominent = false
    var onPreviewChanged: ((Double?) -> Void)? = nil
    var onSeek: ((Double, MusicSeekInteraction) async -> Bool)? = nil

    @State private var dragProgress: Double?
    @State private var isDragging = false
    @State private var isPointerDown = false
    @State private var isHovering = false
    @State private var seekGeneration = 0

    private var displayedProgress: Double {
        min(max(dragProgress ?? progress, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width, 1)
            let knobSize: CGFloat = onSeek == nil ? 0 : 9
            let progressWidth = availableWidth * displayedProgress
            let knobTravelWidth = max(availableWidth - knobSize, 0)
            let knobX = knobTravelWidth * displayedProgress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(prominent ? 0.19 : 0.13))
                    .frame(height: prominent ? 6 : 4)
                    .frame(maxHeight: .infinity, alignment: .center)

                Capsule()
                    .fill(accentColor.opacity(isDragging ? 1 : 0.92))
                    .frame(width: progressWidth, height: prominent ? 6 : 4)
                    .frame(maxHeight: .infinity, alignment: .center)

                if onSeek != nil {
                    Circle()
                        .fill(accentColor)
                        .frame(width: knobSize, height: knobSize)
                        .scaleEffect(isDragging ? 1.25 : 1)
                        .shadow(color: Color.black.opacity(isDragging ? 0.42 : 0.28), radius: isDragging ? 5 : 3, x: 0, y: 1)
                        .opacity(isHovering || isPointerDown || isDragging ? 1 : 0)
                        .animation(.easeOut(duration: 0.1), value: isHovering)
                        .animation(.easeOut(duration: 0.12), value: isDragging)
                        .offset(x: knobX)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            }
            .animation(
                dragProgress == nil && !isPointerDown && !isDragging
                    ? .linear(duration: 0.4)
                    : nil,
                value: displayedProgress
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
            .overlay {
                if onSeek != nil {
                    Slider(
                        value: Binding(
                            get: { displayedProgress },
                            set: { value in
                                dragProgress = min(max(value, 0), 1)
                                isDragging = true
                                onPreviewChanged?(dragProgress)
                            }
                        ),
                        in: 0...1,
                        onEditingChanged: { editing in
                            if editing {
                                isPointerDown = true
                                seekGeneration += 1
                            } else {
                                let target = dragProgress ?? displayedProgress
                                isPointerDown = false
                                isDragging = false
                                submitSeek(to: target, interaction: .drag)
                            }
                        }
                    )
                    .labelsHidden()
                    .accessibilityLabel("播放进度")
                    .opacity(0.02)
                    .frame(width: availableWidth, height: 24)
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard onSeek != nil else { return }
                        if !isPointerDown {
                            isPointerDown = true
                            seekGeneration += 1
                        }
                        let target = min(max(value.location.x / availableWidth, 0), 1)
                        dragProgress = target
                        isDragging = abs(value.translation.width) >= 3
                        onPreviewChanged?(target)
                    }
                    .onEnded { value in
                        guard onSeek != nil else { return }
                        let target = min(max(value.location.x / availableWidth, 0), 1)
                        let interaction: MusicSeekInteraction = isDragging ? .drag : .click
                        dragProgress = target
                        isPointerDown = false
                        isDragging = false
                        submitSeek(to: target, interaction: interaction)
                    }
            )
        }
        .frame(width: width, height: onSeek == nil ? 4 : 24)
        .onDisappear {
            isPointerDown = false
            isDragging = false
            isHovering = false
            dragProgress = nil
        }
    }

    private func submitSeek(to targetProgress: Double, interaction: MusicSeekInteraction) {
        guard let onSeek else { return }
        let generation = seekGeneration
        Task { @MainActor in
            let didSeek = await onSeek(targetProgress, interaction)
            guard generation == seekGeneration else { return }
            if didSeek {
                dragProgress = nil
                onPreviewChanged?(nil)
            } else {
                withAnimation(.easeOut(duration: 0.14)) {
                    dragProgress = nil
                }
                onPreviewChanged?(nil)
            }
        }
    }
}

struct StatusDot: View {
    let isActive: Bool
    let accentColor: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        StatusWaveformLayerView(
            isActive: isActive,
            accentColor: accentColor,
            reduceMotion: reduceMotion
        )
        .frame(width: 10, height: 10)
    }
}

private struct StatusWaveformLayerView: NSViewRepresentable {
    let isActive: Bool
    let accentColor: Color
    let reduceMotion: Bool

    func makeNSView(context: Context) -> StatusWaveformNSView {
        StatusWaveformNSView()
    }

    func updateNSView(_ nsView: StatusWaveformNSView, context: Context) {
        nsView.update(
            isActive: isActive,
            accentColor: NSColor(accentColor),
            reduceMotion: reduceMotion
        )
    }
}

private final class StatusWaveformNSView: NSView {
    private let bars = [CALayer(), CALayer(), CALayer()]
    private let activeOpacities: [CGFloat] = [1.0, 0.82, 0.68]
    private let inactiveOpacities: [CGFloat] = [0.40, 0.34, 0.30]
    private let animatedHeights: [[CGFloat]] = [
        [3, 7, 5, 8, 3],
        [7, 4, 8, 5, 7],
        [5, 8, 3, 6, 5]
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        for bar in bars {
            bar.bounds = CGRect(x: 0, y: 0, width: 1.8, height: 3)
            bar.cornerRadius = 0.9
            bar.cornerCurve = .continuous
            bar.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            layer?.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        let centerY = bounds.midY
        for (index, bar) in bars.enumerated() {
            bar.position = CGPoint(x: 1.2 + CGFloat(index) * 3.3, y: centerY)
        }
    }

    func update(isActive: Bool, accentColor: NSColor, reduceMotion: Bool) {
        let resolvedAccent = accentColor.usingColorSpace(.sRGB) ?? .white
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.20)
        for (index, bar) in bars.enumerated() {
            let opacity = isActive ? activeOpacities[index] : inactiveOpacities[index]
            let color = resolvedAccent.withAlphaComponent(opacity)
            bar.backgroundColor = color.cgColor
        }
        CATransaction.commit()

        if isActive, !reduceMotion {
            startAnimationsIfNeeded()
        } else {
            let heights: [CGFloat] = isActive ? [4, 7, 5] : [3, 3, 3]
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (index, bar) in bars.enumerated() {
                bar.removeAnimation(forKey: "waveHeight")
                bar.bounds.size.height = heights[index]
            }
            CATransaction.commit()
        }
    }

    private func startAnimationsIfNeeded() {
        for (index, bar) in bars.enumerated() {
            guard bar.animation(forKey: "waveHeight") == nil else { continue }
            let animation = CAKeyframeAnimation(keyPath: "bounds.size.height")
            animation.values = animatedHeights[index]
            animation.keyTimes = [0, 0.25, 0.5, 0.75, 1]
            animation.duration = 0.76
            animation.repeatCount = .infinity
            animation.calculationMode = .cubic
            animation.isRemovedOnCompletion = false
            bar.add(animation, forKey: "waveHeight")
        }
    }
}

func timeText(_ seconds: Int) -> String {
    let minutes = max(seconds, 0) / 60
    let secs = max(seconds, 0) % 60
    return String(format: "%02d:%02d", minutes, secs)
}

func playbackPositionText(_ music: MusicState, progressOverride: Double? = nil) -> String {
    guard let duration = music.duration, duration > 0 else { return "--:--" }
    let elapsed = progressOverride.map { duration * min(max($0, 0), 1) }
        ?? music.elapsedTime
        ?? (duration * min(max(music.progress, 0), 1))
    return "\(mediaTimeText(elapsed)) / \(mediaTimeText(duration))"
}

func mediaTimeText(_ seconds: TimeInterval) -> String {
    let totalSeconds = max(Int(seconds.rounded()), 0)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}

private let appDelegate = AppDelegate()
let app = NSApplication.shared
private let terminationSignalBridge = AppTerminationSignalBridge()
app.delegate = appDelegate
app.run()
