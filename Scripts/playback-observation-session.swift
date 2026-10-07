import AppKit
import CoreGraphics
import Foundation

// Read-only session/process identity probe; no AX traversal or window titles.
let session = CGSessionCopyCurrentDictionary() as? [String: Any]
let apps = NSWorkspace.shared.runningApplications
func identities(_ bundle: String) -> [[String: Any]] {
    apps.filter { $0.bundleIdentifier == bundle }.map {
        ["pid": Int($0.processIdentifier),
         "launchUnixTime": $0.launchDate?.timeIntervalSince1970 as Any? ?? NSNull()]
    }
}
let result: [String: Any] = [
    "sessionKnown": session != nil,
    "locked": session?["CGSSessionScreenIsLocked"] as? Bool ?? false,
    "frontIsLoginWindow": NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.loginwindow",
    "islandProcesses": identities("io.github.scorpioxyb.topislet"),
    "sourceProcesses": identities("com.soda.music")
]
print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: .sortedKeys), as: UTF8.self))
