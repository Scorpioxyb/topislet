struct IslandDisplayCandidate: Equatable {
    let identity: String
    let hasCameraHousing: Bool
    let isMain: Bool
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
