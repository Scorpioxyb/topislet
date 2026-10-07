import AppKit
import QuartzCore
import Foundation

// Compile with IslandAnimationFrame.swift and IslandWindowFrameAnimation.swift.
// A new JSON output path is required. --production-curve uses product sizes;
// --explicit uses the production factory; --flush is a retained experiment.

@MainActor final class ProbePanel: NSPanel {
    var frameAnimationDuration: TimeInterval = 0
    var frameAnimationTarget: CGRect?
    var writes: [[String: Double]] = []
    var resizeTimeCalls: [[String: Double]] = []
    var start = ProcessInfo.processInfo.systemUptime
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval {
        resizeTimeCalls.append(["elapsed": ProcessInfo.processInfo.systemUptime - start,
                                "duration": frameAnimationDuration])
        return frameAnimationDuration
    }
    @objc dynamic override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        let anchored = frameAnimationTarget.map { IslandAnimationFrame.anchored(frameRect, to: $0) } ?? frameRect
        writes.append(["elapsed": ProcessInfo.processInfo.systemUptime - start,
                       "width": anchored.width, "height": anchored.height,
                       "proposedWidth": frameRect.width, "proposedHeight": frameRect.height,
                       "center": anchored.midX, "top": anchored.maxY])
        super.setFrame(anchored, display: flag)
    }
}

@MainActor final class Probe: NSObject, NSApplicationDelegate {
    var panel: ProbePanel!
    var samples: [[String: Double]] = []
    var timer: Timer?
    var completions: [Double] = []
    var started = 0.0
    var interruptionAt: Double?
    var requestedDuration = 0.24
    func applicationDidFinishLaunching(_ notification: Notification) {
        let collapse = CommandLine.arguments.contains("--collapse")
        let productionCurve = CommandLine.arguments.contains("--production-curve")
        let initialSize = collapse ? NSSize(width: 460, height: 191)
            : productionCurve ? NSSize(width: 377, height: 35) : NSSize(width: 200, height: 32)
        let targetSize = collapse ? NSSize(width: 377, height: 35)
            : productionCurve ? NSSize(width: 460, height: 191) : NSSize(width: 440, height: 180)
        requestedDuration = collapse ? 0.18 : 0.24
        panel = ProbePanel(contentRect: NSRect(x: -9900 - initialSize.width / 2,
                           y: -9968 - initialSize.height, width: initialSize.width, height: initialSize.height),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Intentionally never order, activate, or synthesize input. This is an
        // isolated AppKit driver probe, not rendered product acceptance.
        let target = NSRect(x: -9900 - targetSize.width / 2, y: -9968 - targetSize.height,
                            width: targetSize.width, height: targetSize.height)
        panel.frameAnimationTarget = target
        panel.frameAnimationDuration = requestedDuration
        if CommandLine.arguments.contains("--flush") { CATransaction.flush() }
        started = ProcessInfo.processInfo.systemUptime
        panel.start = started
        if CommandLine.arguments.contains("--explicit") {
            IslandWindowFrameAnimation.install(on: panel, duration: requestedDuration,
                controlPoints: collapse ? (0.4, 0, 0.2, 1) : (0.2, 0.85, 0.25, 1))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.002, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let frame = self.panel.frame
                self.samples.append(["elapsed": ProcessInfo.processInfo.systemUptime - self.started,
                    "width": frame.width,"height":frame.height,"center":frame.midX,"top":frame.maxY])
            }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = requestedDuration
            context.timingFunction = productionCurve
                ? collapse ? CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
                    : CAMediaTimingFunction(controlPoints: 0.2, 0.85, 0.25, 1)
                : CAMediaTimingFunction(controlPoints: 0.2, 0, 0.2, 1)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.completions.append(ProcessInfo.processInfo.systemUptime - self.started)
            }
        }
        if CommandLine.arguments.contains("--reverse") || CommandLine.arguments.contains("--hide") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [self] in
                self.interruptionAt = ProcessInfo.processInfo.systemUptime - self.started
                let current = self.panel.frame
                self.panel.frameAnimationTarget = nil
                IslandWindowFrameAnimation.remove(from: self.panel)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    self.panel.frameAnimationDuration = 0
                    self.panel.animator().setFrame(current, display: false)
                }
                if CommandLine.arguments.contains("--hide") {
                    self.panel.setFrame(target, display: false)
                    self.panel.orderOut(nil)
                    return
                }
                let collapsed = NSRect(x: -10000, y: -10000, width: 200, height: 32)
                self.panel.frameAnimationTarget = collapsed
                self.panel.frameAnimationDuration = 0.18
                if CommandLine.arguments.contains("--explicit") {
                    IslandWindowFrameAnimation.install(on: self.panel, duration: 0.18,
                        controlPoints: (0.4, 0, 0.2, 1))
                }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0.2, 1)
                    context.allowsImplicitAnimation = true
                    self.panel.animator().setFrame(collapsed, display: true)
                } completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.completions.append(ProcessInfo.processInfo.systemUptime - self.started)
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.finish() }
    }
    func finish() {
        timer?.invalidate()
        let record: [String: Any] = ["visible": panel.isVisible,"completionTimes":completions,
            "setFrameWrites":panel.writes,"samples":samples,
            "resizeTimeCalls":panel.resizeTimeCalls,"requestedDuration":requestedDuration,
            "productionCurve":CommandLine.arguments.contains("--production-curve"),
            "interruptionAt": interruptionAt as Any? ?? NSNull(),
            "mode": CommandLine.arguments.contains("--hide") ? "hide" : CommandLine.arguments.contains("--reverse") ? "reverse" : CommandLine.arguments.contains("--collapse") ? "collapse" : "expand",
            "limitation":"Invisible isolated AppKit driver; cannot prove WindowServer geometry, rendered timing, interruption, or installed product behavior."]
        let data = try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        guard !FileManager.default.fileExists(atPath: url.path) else { exit(2) }
        try! data.write(to: url)
        exit(0)
    }
}
@main struct Entry {
    @MainActor static func main() {
        guard CommandLine.arguments.count >= 2,
              !FileManager.default.fileExists(atPath: CommandLine.arguments[1]),
              Set(CommandLine.arguments.dropFirst(2)).isSubset(of: ["--reverse", "--hide", "--collapse", "--production-curve", "--explicit", "--flush"]),
              CommandLine.arguments.filter({ ["--hide", "--reverse", "--collapse"].contains($0) }).count <= 1 else {
            fputs("Usage: frame-driver NEW_OUTPUT.json [--reverse | --hide | --collapse] [--production-curve] [--explicit] [--flush]\n", stderr)
            exit(2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let delegate = Probe()
        app.delegate = delegate
        app.run()
    }
}
