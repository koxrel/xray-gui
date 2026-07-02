import Testing
import Foundation
@testable import XrayGUICore

@Suite("Subscription Server Reconcile")
struct ServerReconcileTests {

    /// Store rooted at a throwaway temp directory — never the user's live data.
    private func makeStore() -> Store {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xray-reconcile-tests-\(UUID().uuidString)", isDirectory: true)
        return Store(directory: dir)
    }

    private func parsed(_ name: String, address: String, uuid: String, port: Int = 443) -> ServerConfig {
        ServerConfig(name: name, address: address, port: port, uuid: uuid)
    }

    @Test("Reconciling identical content preserves server ids, isActive, and latency")
    func preservesIdentity() {
        let store = makeStore()
        var data = StoreData()
        let subId = "sub-1"
        let first = store.reconcileServersForSubscription(
            &data, subscriptionId: subId,
            servers: [parsed("A", address: "a.com", uuid: "1"), parsed("B", address: "b.com", uuid: "2")]
        )
        store.setActiveServer(&data, id: first[0])
        store.setServerLatency(&data, id: first[0], latency: 42)

        // Same endpoints, but A was renamed in the panel.
        let second = store.reconcileServersForSubscription(
            &data, subscriptionId: subId,
            servers: [parsed("A renamed", address: "a.com", uuid: "1"), parsed("B", address: "b.com", uuid: "2")]
        )

        #expect(second == first)                 // ids and order preserved
        #expect(data.servers.count == 2)
        let a = data.servers.first { $0.id == first[0] }
        #expect(a?.isActive == true)             // isActive preserved across update
        #expect(a?.latency == 42)                // latency preserved
        #expect(a?.name == "A renamed")          // mutable name refreshed
        #expect(data.settings.activeServerId == first[0])
    }

    @Test("Reconcile adds new servers and removes vanished ones, keeping unchanged ids")
    func addsAndRemoves() {
        let store = makeStore()
        var data = StoreData()
        let subId = "sub-1"
        let first = store.reconcileServersForSubscription(
            &data, subscriptionId: subId,
            servers: [parsed("A", address: "a.com", uuid: "1"), parsed("B", address: "b.com", uuid: "2")]
        )

        // B drops out, A stays, C is new.
        let second = store.reconcileServersForSubscription(
            &data, subscriptionId: subId,
            servers: [parsed("A", address: "a.com", uuid: "1"), parsed("C", address: "c.com", uuid: "3")]
        )

        #expect(data.servers.count == 2)
        #expect(second[0] == first[0])                       // A kept its id
        #expect(!data.servers.contains { $0.uuid == "2" })   // B removed
        #expect(data.servers.contains { $0.uuid == "3" })    // C added
    }

    @Test("Reconcile clears activeServerId only when the active server vanishes")
    func clearsActiveOnlyWhenRemoved() {
        let store = makeStore()
        var data = StoreData()
        let subId = "sub-1"
        let ids = store.reconcileServersForSubscription(
            &data, subscriptionId: subId, servers: [parsed("A", address: "a.com", uuid: "1")]
        )
        store.setActiveServer(&data, id: ids[0])

        // Update no longer contains A -> active reference is dropped.
        _ = store.reconcileServersForSubscription(
            &data, subscriptionId: subId, servers: [parsed("B", address: "b.com", uuid: "2")]
        )
        #expect(data.settings.activeServerId == nil)
    }

    @Test("Reconcile leaves other subscriptions' servers untouched")
    func isolatesSubscriptions() {
        let store = makeStore()
        var data = StoreData()
        let other = store.reconcileServersForSubscription(
            &data, subscriptionId: "sub-other", servers: [parsed("X", address: "x.com", uuid: "9")]
        )
        _ = store.reconcileServersForSubscription(
            &data, subscriptionId: "sub-1", servers: [parsed("A", address: "a.com", uuid: "1")]
        )
        // Completely replace sub-1's content.
        _ = store.reconcileServersForSubscription(
            &data, subscriptionId: "sub-1", servers: [parsed("A2", address: "a2.com", uuid: "1b")]
        )
        #expect(data.servers.contains { $0.id == other[0] })  // sub-other survived
    }

    @MainActor
    @Test("loadData re-links orphaned tunnels to current servers by name")
    func healsOrphanedTunnelsOnLoad() {
        // Server now has a fresh id; the persisted tunnel still points at a stale id
        // but its cached serverName matches.
        let server = ServerConfig(id: "new-id", name: "Tokyo", address: "tk.com", port: 443, uuid: "u1", subscriptionId: "sub-1")
        let orphan = Tunnel(id: "t1", serverId: "OLD-DEAD-ID", serverName: "Tokyo",
                            httpPort: 8080, socksPort: 1080, running: false, startedAt: nil)
        let store = MockStore(data: StoreData(servers: [server], tunnels: [orphan]))
        let coordinator = ProxyCoordinator(store: store, xrayManager: MockXrayManager(), proxyManager: MockProxyManager())

        coordinator.loadData()

        #expect(coordinator.tunnels.first?.serverId == "new-id")
        #expect(coordinator.tunnels.first?.serverName == "Tokyo")
    }

    @MainActor
    @Test("loadData leaves a tunnel orphaned when no server name matches")
    func leavesUnmatchedOrphanUntouched() {
        let server = ServerConfig(id: "new-id", name: "Tokyo", address: "tk.com", port: 443, uuid: "u1", subscriptionId: "sub-1")
        let orphan = Tunnel(id: "t1", serverId: "OLD-DEAD-ID", serverName: "Berlin",
                            httpPort: 8080, socksPort: 1080, running: false, startedAt: nil)
        let store = MockStore(data: StoreData(servers: [server], tunnels: [orphan]))
        let coordinator = ProxyCoordinator(store: store, xrayManager: MockXrayManager(), proxyManager: MockProxyManager())

        coordinator.loadData()

        #expect(coordinator.tunnels.first?.serverId == "OLD-DEAD-ID")  // unchanged, surfaces clear error on start
    }
}
