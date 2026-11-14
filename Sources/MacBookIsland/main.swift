import AppKit
import ApplicationServices
import Combine
import Darwin
import EventKit
import ImageIO
import QuartzCore
import SwiftUI

let islandEventNotificationName = Notification.Name("io.github.scorpioxyb.topislet.event")

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
        let snapshot = reader.read(identity: identity,
            includeIntroCredits: CommandLine.arguments.contains("--intro-credits"))
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

private let appDelegate = AppDelegate()
let app = NSApplication.shared
private let terminationSignalBridge = AppTerminationSignalBridge()
app.delegate = appDelegate
app.run()
