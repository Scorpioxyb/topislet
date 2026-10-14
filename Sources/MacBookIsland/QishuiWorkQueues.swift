import Dispatch

/// Keep potentially slow, read-only metadata traversal out of the semantic
/// control lane. Controls remain serialized with their availability probes.
final class QishuiWorkQueues: @unchecked Sendable {
    let controls = DispatchQueue(label: "MacBookIsland.QishuiSemanticControl", qos: .userInitiated)
    let metadata = DispatchQueue(label: "MacBookIsland.QishuiMetadata", qos: .utility)
    private let metadataAdapter = QishuiAdapter()

    func metadataSnapshot(preferredTitle: String? = nil, preferredArtist: String? = nil) -> QishuiDirectSnapshot {
        dispatchPrecondition(condition: .onQueue(metadata))
        return metadataAdapter.snapshot(preferredTitle: preferredTitle, preferredArtist: preferredArtist)
    }
}
