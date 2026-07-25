import ApplicationServices
import CoreGraphics
import Foundation

struct IslandDisplayCandidate: Equatable {
    let identity: String
    let hasCameraHousing: Bool
    let isMain: Bool
}

enum IslandDisplayIdentity {
    static func stableIdentifier(
        displayID: UInt32?,
        physicalUUID: String?,
        displayName: String,
        frame: CGRect
    ) -> String {
        if let physicalUUID {
            let normalizedUUID = physicalUUID
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !normalizedUUID.isEmpty {
                return "display-\(normalizedUUID)"
            }
        }
        if let displayID {
            return "display-id-\(displayID)"
        }
        return "\(displayName)-\(Int(frame.width))x\(Int(frame.height))"
    }

    static func physicalUUID(for displayID: UInt32) -> String? {
        guard let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(
            CGDirectDisplayID(displayID)
        ) else {
            return nil
        }
        let uuid = unmanagedUUID.takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func calibrationIdentifier(
        stableIdentifier: String,
        frame: CGRect,
        scale: CGFloat
    ) -> String {
        [
            stableIdentifier,
            "\(Int(frame.width))x\(Int(frame.height))",
            "scale\(scale)"
        ].joined(separator: "-")
    }
}

enum IslandDisplaySelectionPolicy {
    static func selectIdentity(
        boundIdentity: String?,
        candidates: [IslandDisplayCandidate]
    ) -> String? {
        if let boundIdentity,
           candidates.contains(where: { $0.identity == boundIdentity }) {
            return boundIdentity
        }

        if let cameraDisplay = candidates.first(where: \.hasCameraHousing) {
            return cameraDisplay.identity
        }

        if let mainDisplay = candidates.first(where: \.isMain) {
            return mainDisplay.identity
        }

        return candidates.first?.identity
    }
}
