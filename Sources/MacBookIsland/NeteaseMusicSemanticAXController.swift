import AppKit
import ApplicationServices
import Foundation

struct NeteaseMusicSemanticAXControlResult: Sendable {
    let didPress: Bool
    let diagnostic: String
}

final class NeteaseMusicSemanticAXController: @unchecked Sendable {
    private let bundleIdentifier = "com.netease.163music"
    private let lock = NSLock()

    func perform(
        _ action: MusicControlAction,
        processIdentifier expectedProcessIdentifier: pid_t
    ) -> NeteaseMusicSemanticAXControlResult {
        lock.lock()
        defer { lock.unlock() }

        guard AXIsProcessTrusted() else {
            return result(false, "顶屿需要辅助功能权限才能控制网易云音乐。")
        }
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first(where: {
            !$0.isTerminated && $0.processIdentifier == expectedProcessIdentifier
        }) else {
            return result(false, "岛当前显示的网易云音乐进程已失效，未发送控制。")
        }

        let application = AXUIElementCreateApplication(app.processIdentifier)
        guard let menuBar = elementAttribute(application, kAXMenuBarAttribute) else {
            return result(false, "网易云音乐原生菜单暂不可读，未发送控制。")
        }
        let controlMenus = descendants(of: menuBar, maximumNodeCount: 600).filter {
            role($0) == kAXMenuBarItemRole as String
                && Self.controlMenuTitles.contains(normalizedTitle($0))
        }
        guard controlMenus.count == 1, let controlMenu = controlMenus.first else {
            return result(
                false,
                controlMenus.isEmpty
                    ? "未找到网易云音乐唯一的“控制”菜单，未发送控制。"
                    : "发现多个网易云音乐“控制”菜单，为避免误操作未发送控制。"
            )
        }

        let acceptedTitles = Self.acceptedTitles(for: action)
        let candidates = descendants(of: controlMenu, maximumNodeCount: 160).filter {
            role($0) == kAXMenuItemRole as String
                && acceptedTitles.contains(normalizedTitle($0))
                && isEnabled($0)
        }
        guard candidates.count == 1, let target = candidates.first else {
            return result(
                false,
                candidates.isEmpty
                    ? "网易云音乐“控制”菜单中没有匹配当前状态的目标项，未发送控制。"
                    : "网易云音乐控制目标不唯一，为避免误操作未发送控制。"
            )
        }
        let error = AXUIElementPerformAction(target, kAXPressAction as CFString)
        guard error == .success else {
            return result(false, "网易云音乐原生控制拒绝操作（AXError \(error.rawValue)）。")
        }
        return result(true, "已通过网易云音乐 PID 内原生“控制”菜单执行操作。")
    }

    private static let controlMenuTitles: Set<String> = [
        "控制", "control", "controls", "playback"
    ]

    private static func acceptedTitles(for action: MusicControlAction) -> Set<String> {
        switch action {
        case .playPause:
            return ["播放", "暂停", "play", "pause", "play/pause", "播放/暂停"]
        case .play:
            return ["播放", "play"]
        case .pause:
            return ["暂停", "pause"]
        case .previousTrack:
            return ["上一个", "上一首", "previous", "previous track"]
        case .nextTrack:
            return ["下一个", "下一首", "next", "next track"]
        case .seekNormalized:
            return []
        }
    }

    private func descendants(
        of root: AXUIElement,
        maximumNodeCount: Int
    ) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var queue = [root]
        var visited = Set<CFHashCode>()
        while !queue.isEmpty, result.count < maximumNodeCount {
            let element = queue.removeFirst()
            let identity = CFHash(element)
            guard visited.insert(identity).inserted else { continue }
            result.append(element)
            queue.append(contentsOf: elementArrayAttribute(element, kAXChildrenAttribute))
        }
        return result
    }

    private func normalizedTitle(_ element: AXUIElement) -> String {
        (stringAttribute(element, kAXTitleAttribute) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .lowercased()
    }

    private func role(_ element: AXUIElement) -> String? {
        stringAttribute(element, kAXRoleAttribute)
    }

    private func isEnabled(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            kAXEnabledAttribute as CFString,
            &value
        )
        guard error == .success else { return true }
        return (value as? NSNumber)?.boolValue ?? true
    }

    private func stringAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else { return nil }
        return value as? String
    }

    private func elementAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else { return nil }
        return (value as! AXUIElement?)
    }

    private func elementArrayAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private func result(
        _ didPress: Bool,
        _ diagnostic: String
    ) -> NeteaseMusicSemanticAXControlResult {
        NeteaseMusicSemanticAXControlResult(
            didPress: didPress,
            diagnostic: diagnostic
        )
    }
}
