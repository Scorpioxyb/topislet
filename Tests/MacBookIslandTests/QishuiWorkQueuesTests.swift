import Dispatch
import Foundation
import Testing
@testable import MacBookIsland

@Test("汽水元数据扫描挂起期间，语义播放控制仍能执行")
func qishuiMetadataCannotBlockSemanticControls() async throws {
    let queues = QishuiWorkQueues()
    let releaseMetadata = DispatchSemaphore(value: 0)
    let controlRan = DispatchSemaphore(value: 0)
    await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
        queues.metadata.async {
            started.resume()
            // Bounded even on a failing test, so no worker leaks indefinitely.
            _ = releaseMetadata.wait(timeout: .now() + 3)
        }
    }
    queues.controls.async { controlRan.signal() }
    let result = await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            continuation.resume(returning: controlRan.wait(timeout: .now() + 1))
        }
    }
    releaseMetadata.signal()
    #expect(result == .success)
    await withCheckedContinuation { (drained: CheckedContinuation<Void, Never>) in
        queues.metadata.async { drained.resume() }
    }
}
