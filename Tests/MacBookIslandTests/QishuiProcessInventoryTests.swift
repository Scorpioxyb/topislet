import Testing
@testable import MacBookIsland

private struct InventoryApplication: Equatable {
    let pid: Int32
    var bundle: String = "com.soda.music"
    var terminated = false
}

private func resolveInventory(
    bundle: [InventoryApplication],
    workspace: [InventoryApplication]
) -> [InventoryApplication] {
    QishuiProcessLocator.resolveApplications(
        bundleApplications: bundle,
        workspaceApplications: { workspace },
        isEligible: { !$0.terminated && $0.bundle == "com.soda.music" }
    )
}

@Test("bundle清单暂态为空时，独立工作区清单中的同一汽水实例仍有效")
func emptyBundleInventoryCannotEraseLiveWorkspaceInstance() {
    let current = InventoryApplication(pid: 123)
    let resolved = resolveInventory(bundle: [], workspace: [current])
    #expect(resolved == [current])
    #expect(QishuiPlaybackInstancePolicy.acceptsSnapshot(
        snapshotProcessIdentifier: 123,
        runningProcessIdentifiers: Set(resolved.map(\.pid))
    ))
}

@Test("bundle清单只有已退出实例时仍可发现新实例，旧快照保持拒绝")
func terminatedBundleEntryDoesNotHideLiveReplacement() {
    let old = InventoryApplication(pid: 123, terminated: true)
    let current = InventoryApplication(pid: 124)
    let resolved = resolveInventory(bundle: [old], workspace: [current])
    #expect(resolved == [current])
    #expect(!QishuiPlaybackInstancePolicy.acceptsSnapshot(
        snapshotProcessIdentifier: 123,
        runningProcessIdentifiers: Set(resolved.map(\.pid))
    ))
}

@Test("工作区补证不接纳无关应用或已退出实例，真正空清单仍为空")
func inventoryFallbackDoesNotInventRunningInstances() {
    #expect(resolveInventory(bundle: [], workspace: [
        InventoryApplication(pid: 99, bundle: "other.player"),
        InventoryApplication(pid: 123, terminated: true)
    ]).isEmpty)
    #expect(resolveInventory(bundle: [], workspace: []).isEmpty)
}

@Test("正常bundle清单不触发工作区补证")
func healthyBundleInventoryAvoidsAdditionalEnumeration() {
    let current = InventoryApplication(pid: 123)
    let resolved = QishuiProcessLocator.resolveApplications(
        bundleApplications: [current],
        workspaceApplications: {
            Issue.record("正常清单不应额外枚举工作区")
            return []
        },
        isEligible: { !$0.terminated && $0.bundle == "com.soda.music" }
    )
    #expect(resolved == [current])
}
