import AppKit
import Foundation

/// Qishui (汽水音乐) state and collaborators owned apart from the coordinator.
///
/// Coordinator split step 4.3 moves only the stored properties here; the coordinator
/// still runs all logic and reads them as `qishui.x`. Later steps move the logic.
/// See Docs/engineering/COORDINATOR_SPLIT_STEP4.md.
@MainActor
final class QishuiMusicAdapter {
    let qishuiAdapter = QishuiAdapter()
    let qishuiAXChangeMonitor = QishuiAXChangeMonitor()
    let qishuiSemanticAXController = QishuiSemanticAXController()
    let qishuiWorkQueues = QishuiWorkQueues()
    let mediaRemoteAdapterStreamSource = MediaRemoteAdapterStreamSource()
    let nowPlayingBridge = NowPlayingAXBridge()
    var latestQishuiSnapshot: QishuiDirectSnapshot?
    var qishuiIdentityRefreshInFlight = false
    var qishuiIdentityRefreshGeneration: UInt64 = 0
    var lastQishuiTransitionIdentityRequested: QishuiLyricIdentity?
    var lastQishuiIdentityRefreshAt = Date.distantPast
    var qishuiLifecycleMetadataTask: Task<Void, Never>?
    var latestQishuiControlAvailability: QishuiControlAvailability = .unknown
    var latestMediaRemoteSnapshot: MediaRemoteNowPlayingSnapshot?
    var lastSourceRefreshAt: Date?
    var lastPlaybackPositionRefreshAt: Date?
    var controlGeneration = 0
    var qishuiControlAvailabilityGeneration: UInt64 = 0
    var qishuiControlAvailabilityRefreshInFlight = false
    var qishuiControlAvailabilityRefreshQueued = false
    var lastQishuiControlHealthCheckAt: Date?
    var qishuiControlAvailabilityRetryAttempt = 0
    var qishuiControlAvailabilityRetryTask: Task<Void, Never>?
    var lastTrackControlStartedAt: Date?
    let playback = PlaybackOperationTracker()
    var qishuiInference = QishuiPlaybackInference()
    var playbackPositionRefreshInFlight = false
    var qishuiLifecycleObservers: [NSObjectProtocol] = []
}
