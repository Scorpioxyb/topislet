import Foundation

/// What an asynchronous Qishui read was issued against: the source, the target
/// process, the published playback identity and the session generations.
///
/// A read captures a token when it starts and may write its result only if
/// `admits` passes when it finishes. This collects the identity, PID and
/// generation checks that each async path used to repeat inline; it does not
/// relax any of them. Observation state and source selection stay at the call
/// sites, because `selectedSource()` has side effects and must be called where
/// it always was. See Docs/engineering/COORDINATOR_SPLIT_STEP4.md (step 4.8).
struct PublishedTrackToken: Equatable, Sendable {
    let source: MusicSourceID
    let processIdentifier: pid_t
    /// The verified MediaRemote identity when the read was issued, if any.
    let identity: QishuiLyricIdentity?
    let controlGeneration: Int
    let seekGeneration: UInt64

    /// True when a finished read may still write its result:
    /// - no control command and no seek started since the read was issued;
    /// - the result belongs to the requested process, which is still running;
    /// - the playback identity did not change, or the result already
    ///   describes the new identity (`QishuiIdentityRefreshPolicy.accepts`).
    func admits(
        resultProcessIdentifier: pid_t?,
        resultTitle: String?,
        resultArtist: String?,
        currentControlGeneration: Int,
        currentSeekGeneration: UInt64,
        currentIdentity: QishuiLyricIdentity?,
        isProcessRunning: (pid_t) -> Bool = { QishuiProcessLocator.isRunning(processIdentifier: $0) }
    ) -> Bool {
        guard currentControlGeneration == controlGeneration,
              currentSeekGeneration == seekGeneration,
              resultProcessIdentifier == processIdentifier,
              isProcessRunning(processIdentifier) else { return false }
        let result: QishuiLyricIdentity?
        if let resultTitle, let resultArtist {
            result = QishuiLyricIdentity(
                processIdentifier: processIdentifier, title: resultTitle, artist: resultArtist
            )
        } else {
            result = nil
        }
        return QishuiIdentityRefreshPolicy.accepts(
            requested: identity, current: currentIdentity, result: result
        )
    }
}
