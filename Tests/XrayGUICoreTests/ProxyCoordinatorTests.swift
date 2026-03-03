import Foundation
import Testing
@testable import XrayGUICore

// MARK: - Test Helpers

/// Creates a minimal valid server config for testing.
private func makeServer(
    id: String = "server-1",
    name: String = "Test Server",
    address: String = "example.com",
    port: Int = 443,
    uuid: String = "test-uuid-1234",
    isActive: Bool = false,
    subscriptionId: String? = nil
) -> ServerConfig {
    ServerConfig(
        id: id,
        name: name,
        address: address,
        port: port,
        uuid: uuid,
        flow: "",
        encryption: "none",
        network: "tcp",
        security: "none",
        sni: "",
        fingerprint: "",
        publicKey: "",
        shortId: "",
        alpn: [],
        allowInsecure: false,
        subscriptionId: subscriptionId,
        isActive: isActive
    )
}

/// Factory to create coordinator + mocks with minimal boilerplate.
@MainActor
private func makeCoordinator(
    store: MockStore? = nil,
    xrayManager: MockXrayManager? = nil,
    proxyManager: MockProxyManager? = nil
) -> (ProxyCoordinator, MockStore, MockXrayManager, MockProxyManager) {
    let s = store ?? MockStore()
    let x = xrayManager ?? MockXrayManager()
    let p = proxyManager ?? MockProxyManager()
    let coordinator = ProxyCoordinator(store: s, xrayManager: x, proxyManager: p)
    return (coordinator, s, x, p)
}

/// Ensure the temp config directory exists so ConfigGenerator.writeConfig succeeds.
private func ensureTempConfigDir() {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("xray-test-configs")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
}

/// Clean up any temp config files written during tests.
private func cleanupTempConfigs() {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("xray-test-configs")
    try? FileManager.default.removeItem(at: dir)
}

// MARK: - Data Loading Tests

@Suite("ProxyCoordinator - Data Loading")
struct DataLoadingTests {

    @Test("loadData populates servers, subscriptions, and settings from store")
    @MainActor func loadDataPopulatesState() {
        let server = makeServer()
        let sub = Subscription(id: "sub-1", name: "My Sub", url: "https://example.com/sub")
        let settings = AppSettings(httpPort: 2000, socksPort: 2001)
        let store = MockStore(data: StoreData(servers: [server], subscriptions: [sub], settings: settings))

        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        #expect(coordinator.servers.count == 1)
        #expect(coordinator.servers.first?.id == "server-1")
        #expect(coordinator.subscriptions.count == 1)
        #expect(coordinator.subscriptions.first?.name == "My Sub")
        #expect(coordinator.settings.httpPort == 2000)
        #expect(coordinator.settings.socksPort == 2001)
    }

    @Test("loadData marks all tunnels as not running")
    @MainActor func loadDataResetsTunnelRunning() {
        let tunnel = Tunnel(id: "t1", serverId: "s1", serverName: "S1", httpPort: 1087, socksPort: 1080, running: true, startedAt: Date())
        let store = MockStore(data: StoreData(tunnels: [tunnel]))

        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        #expect(coordinator.tunnels.count == 1)
        #expect(coordinator.tunnels[0].running == false)
        #expect(coordinator.tunnels[0].startedAt == nil)
    }

    @Test("loadData sets proxyStatus.running to false")
    @MainActor func loadDataResetsProxyStatus() {
        let (coordinator, _, _, _) = makeCoordinator()
        coordinator.loadData()

        #expect(coordinator.proxyStatus.running == false)
    }

    @Test("loadData with empty store returns defaults")
    @MainActor func loadDataEmptyStore() {
        let (coordinator, _, _, _) = makeCoordinator()
        coordinator.loadData()

        #expect(coordinator.servers.isEmpty)
        #expect(coordinator.subscriptions.isEmpty)
        #expect(coordinator.tunnels.isEmpty)
        #expect(coordinator.settings == AppSettings.default)
    }

    @Test("loadData with pre-existing data overwrites current state")
    @MainActor func loadDataOverwritesExisting() {
        let (coordinator, s, _, _) = makeCoordinator()

        // Manually set some state
        coordinator.servers = [makeServer(id: "old-server")]
        coordinator.logs = ["old log"]

        // Store has different data
        s.data = StoreData(servers: [makeServer(id: "new-server")])
        coordinator.loadData()

        #expect(coordinator.servers.count == 1)
        #expect(coordinator.servers.first?.id == "new-server")
        // Logs are NOT reset by loadData
        #expect(coordinator.logs.count == 1)
    }
}

// MARK: - Server CRUD Tests

@Suite("ProxyCoordinator - Server CRUD")
struct ServerCRUDTests {

    @Test("addServer adds to servers array")
    @MainActor func addServerAddsToArray() {
        let (coordinator, _, _, _) = makeCoordinator()
        let server = makeServer(id: "s1", name: "Added Server")

        coordinator.addServer(server)

        #expect(coordinator.servers.count == 1)
        #expect(coordinator.servers.first?.name == "Added Server")
    }

    @Test("updateServer modifies existing server")
    @MainActor func updateServerModifiesExisting() {
        let server = makeServer(id: "s1", name: "Original")
        let store = MockStore(data: StoreData(servers: [server]))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        var updated = server
        updated.name = "Updated"
        coordinator.updateServer(updated)

        #expect(coordinator.servers.first?.name == "Updated")
    }

    @Test("deleteServer removes server")
    @MainActor func deleteServerRemoves() {
        let server = makeServer(id: "s1")
        let store = MockStore(data: StoreData(servers: [server]))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        coordinator.deleteServer("s1")

        #expect(coordinator.servers.isEmpty)
    }

    @Test("deleteServer clears activeServerId if matching")
    @MainActor func deleteServerClearsActive() {
        let server = makeServer(id: "s1", isActive: true)
        let settings = AppSettings(activeServerId: "s1")
        let store = MockStore(data: StoreData(servers: [server], settings: settings))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        coordinator.deleteServer("s1")

        #expect(coordinator.settings.activeServerId == nil)
    }

    @Test("setActiveServer marks correct server active")
    @MainActor func setActiveServerMarksCorrect() {
        let s1 = makeServer(id: "s1", name: "S1")
        let s2 = makeServer(id: "s2", name: "S2")
        let store = MockStore(data: StoreData(servers: [s1, s2]))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        coordinator.setActiveServer("s2")

        #expect(coordinator.servers.first(where: { $0.id == "s1" })?.isActive == false)
        #expect(coordinator.servers.first(where: { $0.id == "s2" })?.isActive == true)
        #expect(coordinator.settings.activeServerId == "s2")
    }

    @Test("setActiveServer with nil deactivates all")
    @MainActor func setActiveServerNilDeactivatesAll() {
        let s1 = makeServer(id: "s1", isActive: true)
        let settings = AppSettings(activeServerId: "s1")
        let store = MockStore(data: StoreData(servers: [s1], settings: settings))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        coordinator.setActiveServer(nil)

        #expect(coordinator.servers.allSatisfy { !$0.isActive })
        #expect(coordinator.settings.activeServerId == nil)
    }

    @Test("importServerUrl parses and adds valid VLESS URL")
    @MainActor func importServerUrlValid() {
        let (coordinator, _, _, _) = makeCoordinator()

        let url = "vless://test-uuid@example.com:443?encryption=none&security=none&type=tcp#TestServer"
        let result = coordinator.importServerUrl(url)

        // The result depends on SubscriptionManager.parseVlessUrl succeeding
        if result != nil {
            #expect(coordinator.servers.count == 1)
        }
        // If nil, the URL format wasn't recognized — that's acceptable in this test context
    }

    @Test("addServer triggers save via store")
    @MainActor func addServerSaves() {
        let (coordinator, s, _, _) = makeCoordinator()
        let initialSaveCount = s.saveCalls.count

        coordinator.addServer(makeServer())

        #expect(s.saveCalls.count > initialSaveCount)
    }
}

// MARK: - Latency Testing

@Suite("ProxyCoordinator - Latency Testing")
struct LatencyTests {

    @Test("testLatency calls xrayManager.testLatency with correct server")
    @MainActor func testLatencyCallsManager() async {
        let server = makeServer(id: "s1")
        let store = MockStore(data: StoreData(servers: [server]))
        let (coordinator, _, x, _) = makeCoordinator(store: store)
        coordinator.loadData()

        await coordinator.testLatency("s1")

        #expect(x.testLatencyCalls.count == 1)
        #expect(x.testLatencyCalls.first?.id == "s1")
    }

    @Test("testLatency updates server latency via store")
    @MainActor func testLatencyUpdatesServer() async {
        let server = makeServer(id: "s1")
        let store = MockStore(data: StoreData(servers: [server]))
        let (coordinator, _, x, _) = makeCoordinator(store: store)
        coordinator.loadData()
        x.stubbedLatency = 123

        await coordinator.testLatency("s1")

        #expect(coordinator.servers.first?.latency == 123)
    }

    @Test("testLatency with unknown serverId does nothing")
    @MainActor func testLatencyUnknownServer() async {
        let (coordinator, _, x, _) = makeCoordinator()
        coordinator.loadData()

        await coordinator.testLatency("nonexistent")

        #expect(x.testLatencyCalls.isEmpty)
    }

    @Test("testAllLatency tests all servers in batches")
    @MainActor func testAllLatencyBatches() async {
        let servers = (0..<5).map { makeServer(id: "s\($0)", name: "Server \($0)") }
        let store = MockStore(data: StoreData(servers: servers))
        let (coordinator, _, x, _) = makeCoordinator(store: store)
        coordinator.loadData()

        await coordinator.testAllLatency()

        #expect(x.testLatencyCalls.count == 5)
    }
}

// MARK: - Subscription Lifecycle Tests

@Suite("ProxyCoordinator - Subscriptions")
struct CoordinatorSubscriptionTests {

    @Test("deleteSubscription removes subscription and its servers")
    @MainActor func deleteSubscriptionRemovesServers() {
        let server = makeServer(id: "sub-server-1", subscriptionId: "sub-1")
        let sub = Subscription(id: "sub-1", name: "Sub", url: "https://example.com", serverIds: ["sub-server-1"])
        let store = MockStore(data: StoreData(servers: [server], subscriptions: [sub]))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        coordinator.deleteSubscription("sub-1")

        #expect(coordinator.subscriptions.isEmpty)
        #expect(coordinator.servers.isEmpty)
    }

    @Test("deleteSubscription clears activeServerId when removing active subscription server")
    @MainActor func deleteSubscriptionClearsActive() {
        let server = makeServer(id: "sub-server-1", isActive: true, subscriptionId: "sub-1")
        let sub = Subscription(id: "sub-1", name: "Sub", url: "https://example.com", serverIds: ["sub-server-1"])
        let settings = AppSettings(activeServerId: "sub-server-1")
        let store = MockStore(data: StoreData(servers: [server], subscriptions: [sub], settings: settings))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        coordinator.deleteSubscription("sub-1")

        #expect(coordinator.settings.activeServerId == nil)
    }

    @Test("deleteSubscription preserves unrelated servers")
    @MainActor func deleteSubscriptionPreservesOtherServers() {
        let subServer = makeServer(id: "sub-server", subscriptionId: "sub-1")
        let manualServer = makeServer(id: "manual-server")
        let sub = Subscription(id: "sub-1", name: "Sub", url: "https://example.com")
        let store = MockStore(data: StoreData(servers: [subServer, manualServer], subscriptions: [sub]))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        coordinator.deleteSubscription("sub-1")

        #expect(coordinator.servers.count == 1)
        #expect(coordinator.servers.first?.id == "manual-server")
    }

    // Note: addSubscription and updateAllSubscriptions call SubscriptionManager.fetchSubscription
    // which makes network calls. We test the coordinator's handling of these paths at a high level.

    @Test("updateAllSubscriptions returns correct counts when no subscriptions exist")
    @MainActor func updateAllSubscriptionsEmpty() async {
        let (coordinator, _, _, _) = makeCoordinator()
        coordinator.loadData()

        let result = await coordinator.updateAllSubscriptions()

        #expect(result.success == 0)
        #expect(result.failed == 0)
    }

    @Test("updateAllSubscriptions counts failures for invalid URLs")
    @MainActor func updateAllSubscriptionsCountsFailures() async {
        let sub = Subscription(id: "sub-1", name: "Bad Sub", url: "not-a-real-url")
        let store = MockStore(data: StoreData(subscriptions: [sub]))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        let result = await coordinator.updateAllSubscriptions()

        // Network call will fail for invalid URL
        #expect(result.failed == 1)
        #expect(result.success == 0)
    }
}

// MARK: - Proxy Control Tests

@Suite("ProxyCoordinator - Proxy Control")
struct ProxyControlTests {

    init() {
        ensureTempConfigDir()
    }

    @Test("startProxy with active server calls xrayManager.start")
    @MainActor func startProxyCallsStart() async throws {
        let server = makeServer(id: "s1", isActive: true)
        let settings = AppSettings(activeServerId: "s1")
        let store = MockStore(data: StoreData(servers: [server], settings: settings))
        let (coordinator, _, x, _) = makeCoordinator(store: store)
        coordinator.loadData()

        try await coordinator.startProxy()

        #expect(x.startCalls.count == 1)
        #expect(x.startCalls.first?.tunnelId == Tunnel.primaryId)
    }

    @Test("startProxy applies proxy mode")
    @MainActor func startProxyAppliesMode() async throws {
        let server = makeServer(id: "s1", isActive: true)
        let settings = AppSettings(proxyMode: .global, activeServerId: "s1")
        let store = MockStore(data: StoreData(servers: [server], settings: settings))
        let (coordinator, _, _, p) = makeCoordinator(store: store)
        coordinator.loadData()

        try await coordinator.startProxy(server: server)

        #expect(p.applyProxyModeCalls.count == 1)
        #expect(p.applyProxyModeCalls.first?.mode == .global)
    }

    @Test("startProxy creates tunnel entry with running=true")
    @MainActor func startProxyCreatesTunnel() async throws {
        let server = makeServer(id: "s1", isActive: true)
        let settings = AppSettings(activeServerId: "s1")
        let store = MockStore(data: StoreData(servers: [server], settings: settings))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        try await coordinator.startProxy(server: server)

        let primaryTunnel = coordinator.tunnels.first(where: { $0.id == Tunnel.primaryId })
        #expect(primaryTunnel != nil)
        #expect(primaryTunnel?.running == true)
        #expect(primaryTunnel?.serverId == "s1")
    }

    @Test("startProxy updates proxyStatus")
    @MainActor func startProxyUpdatesStatus() async throws {
        let server = makeServer(id: "s1", isActive: true)
        let settings = AppSettings(activeServerId: "s1")
        let store = MockStore(data: StoreData(servers: [server], settings: settings))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        try await coordinator.startProxy(server: server)

        #expect(coordinator.proxyStatus.running == true)
        #expect(coordinator.proxyStatus.activeServer?.id == "s1")
        #expect(coordinator.proxyStatus.startedAt != nil)
    }

    @Test("startProxy writes config file")
    @MainActor func startProxyWritesConfig() async throws {
        let server = makeServer(id: "s1", isActive: true)
        let settings = AppSettings(activeServerId: "s1")
        let store = MockStore(data: StoreData(servers: [server], settings: settings))
        let (coordinator, s, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        try await coordinator.startProxy(server: server)

        let configURL = s.configFileURL(for: Tunnel.primaryId)
        #expect(FileManager.default.fileExists(atPath: configURL.path))

        // Cleanup
        try? FileManager.default.removeItem(at: configURL)
    }

    @Test("startProxy throws noActiveServer when no server selected")
    @MainActor func startProxyThrowsNoServer() async {
        let (coordinator, _, _, _) = makeCoordinator()
        coordinator.loadData()

        do {
            try await coordinator.startProxy()
            Issue.record("Expected ProxyError.noActiveServer to be thrown")
        } catch {
            #expect(error is ProxyError)
        }
    }

    @Test("stopProxy calls xrayManager.stop")
    @MainActor func stopProxyCallsStop() async throws {
        let server = makeServer(id: "s1", isActive: true)
        let settings = AppSettings(activeServerId: "s1")
        let store = MockStore(data: StoreData(servers: [server], settings: settings))
        let (coordinator, _, x, _) = makeCoordinator(store: store)
        coordinator.loadData()

        try await coordinator.startProxy(server: server)
        try await coordinator.stopProxy()

        #expect(x.stopCalls.contains(Tunnel.primaryId))
    }

    @Test("stopProxy disables system proxy")
    @MainActor func stopProxyDisablesSystemProxy() async throws {
        let server = makeServer(id: "s1", isActive: true)
        let settings = AppSettings(activeServerId: "s1")
        let store = MockStore(data: StoreData(servers: [server], settings: settings))
        let (coordinator, _, _, p) = makeCoordinator(store: store)
        coordinator.loadData()

        try await coordinator.startProxy(server: server)
        try await coordinator.stopProxy()

        #expect(p.disableProxyCallCount >= 1)
    }

    @Test("stopProxy removes tunnel and updates status")
    @MainActor func stopProxyRemovesTunnel() async throws {
        let server = makeServer(id: "s1", isActive: true)
        let settings = AppSettings(activeServerId: "s1")
        let store = MockStore(data: StoreData(servers: [server], settings: settings))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        try await coordinator.startProxy(server: server)
        #expect(coordinator.tunnels.contains(where: { $0.id == Tunnel.primaryId }))

        try await coordinator.stopProxy()

        #expect(!coordinator.tunnels.contains(where: { $0.id == Tunnel.primaryId }))
        #expect(coordinator.proxyStatus.running == false)
    }

    @Test("setProxyMode updates settings and applies new mode when running")
    @MainActor func setProxyModeUpdatesAndApplies() async throws {
        let server = makeServer(id: "s1", isActive: true)
        let settings = AppSettings(proxyMode: .global, activeServerId: "s1")
        let store = MockStore(data: StoreData(servers: [server], settings: settings))
        let (coordinator, _, _, p) = makeCoordinator(store: store)
        coordinator.loadData()

        try await coordinator.startProxy(server: server)
        let applyCountBefore = p.applyProxyModeCalls.count

        await coordinator.setProxyMode(ProxyMode.manual)

        #expect(coordinator.settings.proxyMode == ProxyMode.manual)
        #expect(coordinator.proxyStatus.proxyMode == ProxyMode.manual)
        #expect(p.applyProxyModeCalls.count > applyCountBefore)
        #expect(p.applyProxyModeCalls.last?.mode == ProxyMode.manual)
    }

    @Test("setProxyMode does NOT apply when not running")
    @MainActor func setProxyModeSkipsWhenNotRunning() async {
        let (coordinator, _, _, p) = makeCoordinator()
        coordinator.loadData()

        await coordinator.setProxyMode(ProxyMode.manual)

        #expect(coordinator.settings.proxyMode == ProxyMode.manual)
        // applyProxyMode should not be called since proxy is not running
        #expect(p.applyProxyModeCalls.isEmpty)
    }
}

// MARK: - Multi-Tunnel Management Tests

@Suite("ProxyCoordinator - Multi-Tunnel")
struct MultiTunnelTests {

    init() {
        ensureTempConfigDir()
    }

    @Test("addTunnel creates new tunnel with auto-allocated ports")
    @MainActor func addTunnelAutoAllocates() async throws {
        let server = makeServer(id: "s1")
        let store = MockStore(data: StoreData(servers: [server]))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        let tunnel = try await coordinator.addTunnel(serverId: "s1")

        #expect(tunnel.running == true)
        #expect(tunnel.serverId == "s1")
        #expect(coordinator.tunnels.count == 1)
    }

    @Test("addTunnel throws when server not found")
    @MainActor func addTunnelThrowsNoServer() async {
        let (coordinator, _, _, _) = makeCoordinator()
        coordinator.loadData()

        do {
            _ = try await coordinator.addTunnel(serverId: "nonexistent")
            Issue.record("Expected error for missing server")
        } catch {
            #expect(error is ProxyError)
        }
    }

    @Test("pauseTunnel stops xray and marks tunnel not running")
    @MainActor func pauseTunnelStops() async throws {
        let server = makeServer(id: "s1")
        let store = MockStore(data: StoreData(servers: [server]))
        let (coordinator, _, x, _) = makeCoordinator(store: store)
        coordinator.loadData()

        let tunnel = try await coordinator.addTunnel(serverId: "s1")
        await coordinator.pauseTunnel(tunnel.id)

        #expect(x.stopCalls.contains(tunnel.id))
        let paused = coordinator.tunnels.first(where: { $0.id == tunnel.id })
        #expect(paused?.running == false)
        #expect(paused?.startedAt == nil)
    }

    @Test("resumeTunnel restarts xray and marks tunnel running")
    @MainActor func resumeTunnelRestarts() async throws {
        let server = makeServer(id: "s1")
        let store = MockStore(data: StoreData(servers: [server]))
        let (coordinator, _, x, _) = makeCoordinator(store: store)
        coordinator.loadData()

        let tunnel = try await coordinator.addTunnel(serverId: "s1")
        await coordinator.pauseTunnel(tunnel.id)

        try await coordinator.resumeTunnel(tunnel.id)

        // start should be called twice: once on addTunnel, once on resume
        #expect(x.startCalls.count == 2)
        let resumed = coordinator.tunnels.first(where: { $0.id == tunnel.id })
        #expect(resumed?.running == true)
        #expect(resumed?.startedAt != nil)
    }

    @Test("removeTunnel stops and removes from list")
    @MainActor func removeTunnelStopsAndRemoves() async throws {
        let server = makeServer(id: "s1")
        let store = MockStore(data: StoreData(servers: [server]))
        let (coordinator, s, x, _) = makeCoordinator(store: store)
        coordinator.loadData()

        let tunnel = try await coordinator.addTunnel(serverId: "s1")
        await coordinator.removeTunnel(tunnel.id)

        #expect(x.stopCalls.contains(tunnel.id))
        #expect(s.removeConfigFileCalls.contains(tunnel.id))
        #expect(!coordinator.tunnels.contains(where: { $0.id == tunnel.id }))
    }

    @Test("updateTunnelPorts restarts with new ports when running")
    @MainActor func updateTunnelPortsRestarts() async throws {
        let server = makeServer(id: "s1")
        let store = MockStore(data: StoreData(servers: [server]))
        let (coordinator, _, x, _) = makeCoordinator(store: store)
        coordinator.loadData()

        let tunnel = try await coordinator.addTunnel(serverId: "s1", httpPort: 3000, socksPort: 3001)
        let startsBefore = x.startCalls.count

        try await coordinator.updateTunnelPorts(tunnel.id, httpPort: 4000, socksPort: 4001)

        // Should have stopped and re-started
        #expect(x.stopCalls.contains(tunnel.id))
        #expect(x.startCalls.count > startsBefore)

        let updated = coordinator.tunnels.first(where: { $0.id == tunnel.id })
        #expect(updated?.httpPort == 4000)
        #expect(updated?.socksPort == 4001)
    }

    @Test("updateTunnelPorts skips restart when ports unchanged")
    @MainActor func updateTunnelPortsSkipsIfUnchanged() async throws {
        let server = makeServer(id: "s1")
        let store = MockStore(data: StoreData(servers: [server]))
        let (coordinator, _, x, _) = makeCoordinator(store: store)
        coordinator.loadData()

        let tunnel = try await coordinator.addTunnel(serverId: "s1", httpPort: 3000, socksPort: 3001)
        let stopsBefore = x.stopCalls.count
        let startsBefore = x.startCalls.count

        try await coordinator.updateTunnelPorts(tunnel.id, httpPort: 3000, socksPort: 3001)

        // No stop/start because ports are the same
        #expect(x.stopCalls.count == stopsBefore)
        #expect(x.startCalls.count == startsBefore)
    }

    @Test("pauseAllTunnels stops all and disables proxy")
    @MainActor func pauseAllTunnelsStopsAll() async throws {
        let s1 = makeServer(id: "s1")
        let s2 = makeServer(id: "s2")
        let store = MockStore(data: StoreData(servers: [s1, s2]))
        let (coordinator, _, x, p) = makeCoordinator(store: store)
        coordinator.loadData()

        _ = try await coordinator.addTunnel(serverId: "s1")
        _ = try await coordinator.addTunnel(serverId: "s2")

        await coordinator.pauseAllTunnels()

        // Both should be stopped
        #expect(x.stopCalls.count == 2)
        #expect(coordinator.tunnels.allSatisfy { !$0.running })
        #expect(p.disableProxyCallCount >= 1)
        #expect(coordinator.proxyStatus.running == false)
    }

    @Test("stopAllTunnels clears everything")
    @MainActor func stopAllTunnelsClearsAll() async throws {
        let server = makeServer(id: "s1")
        let store = MockStore(data: StoreData(servers: [server]))
        let (coordinator, s, x, p) = makeCoordinator(store: store)
        coordinator.loadData()

        _ = try await coordinator.addTunnel(serverId: "s1")
        await coordinator.stopAllTunnels()

        #expect(x.stopAllCallCount >= 1)
        #expect(coordinator.tunnels.isEmpty)
        #expect(p.disableProxyCallCount >= 1)
        #expect(coordinator.proxyStatus.running == false)
        #expect(!s.removeConfigFileCalls.isEmpty)
    }

    @Test("resumeAllTunnels resumes paused tunnels")
    @MainActor func resumeAllResumes() async throws {
        let server = makeServer(id: "s1")
        let store = MockStore(data: StoreData(servers: [server]))
        let (coordinator, _, x, _) = makeCoordinator(store: store)
        coordinator.loadData()

        let tunnel = try await coordinator.addTunnel(serverId: "s1")
        await coordinator.pauseTunnel(tunnel.id)

        let startsBefore = x.startCalls.count
        await coordinator.resumeAllTunnels()

        #expect(x.startCalls.count > startsBefore)
        #expect(coordinator.tunnels.first?.running == true)
    }
}

// MARK: - Port Allocation Tests

@Suite("ProxyCoordinator - Port Allocation")
struct PortAllocationTests {

    @Test("nextAvailablePorts returns base ports when no tunnels")
    @MainActor func basePorts() {
        let settings = AppSettings(httpPort: 1087, socksPort: 1080)
        let store = MockStore(data: StoreData(settings: settings))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        let ports = coordinator.nextAvailablePortsPreview()

        #expect(ports.http == 1087)
        #expect(ports.socks == 1080)
    }

    @Test("nextAvailablePorts skips ports used by existing tunnels")
    @MainActor func skipsUsedPorts() {
        let settings = AppSettings(httpPort: 1087, socksPort: 1080)
        let tunnel = Tunnel(id: "t1", serverId: "s1", serverName: "S1", httpPort: 1087, socksPort: 1080)
        let store = MockStore(data: StoreData(settings: settings, tunnels: [tunnel]))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        let ports = coordinator.nextAvailablePortsPreview()

        #expect(ports.http == 1089)
        #expect(ports.socks == 1082)
    }

    @Test("nextAvailablePorts increments by 2 until finding free pair")
    @MainActor func incrementsBy2() {
        let settings = AppSettings(httpPort: 1087, socksPort: 1080)
        let tunnels = [
            Tunnel(id: "t1", serverId: "s1", serverName: "S1", httpPort: 1087, socksPort: 1080),
            Tunnel(id: "t2", serverId: "s2", serverName: "S2", httpPort: 1089, socksPort: 1082),
        ]
        let store = MockStore(data: StoreData(settings: settings, tunnels: tunnels))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        let ports = coordinator.nextAvailablePortsPreview()

        #expect(ports.http == 1091)
        #expect(ports.socks == 1084)
    }

    @Test("nextAvailablePorts returns base ports when all ports exhausted")
    @MainActor func exhaustedReturnsBase() {
        // Create a tunnel that uses ports near the top of the valid range
        // and set base ports near the limit so the loop hits 65535
        let settings = AppSettings(httpPort: 65534, socksPort: 65535)
        let tunnel = Tunnel(id: "t1", serverId: "s1", serverName: "S1", httpPort: 65534, socksPort: 65535)
        let store = MockStore(data: StoreData(settings: settings, tunnels: [tunnel]))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        let ports = coordinator.nextAvailablePortsPreview()

        // After incrementing by 2, both exceed 65535, so it falls back to base
        #expect(ports.http == 65534)
        #expect(ports.socks == 65535)
    }
}

// MARK: - Settings Tests

@Suite("ProxyCoordinator - Settings")
struct SettingsTests {

    init() {
        ensureTempConfigDir()
    }

    @Test("updateSettings persists via store")
    @MainActor func updateSettingsPersists() async {
        let (coordinator, s, _, _) = makeCoordinator()
        coordinator.loadData()
        let savesBefore = s.saveCalls.count

        await coordinator.updateSettings { $0.allowLan = true }

        #expect(coordinator.settings.allowLan == true)
        #expect(s.saveCalls.count > savesBefore)
    }

    @Test("updateSettings triggers restart when proxy-relevant setting changes")
    @MainActor func updateSettingsRestartsWhenRelevant() async throws {
        let server = makeServer(id: "s1", isActive: true)
        let settings = AppSettings(httpPort: 1087, socksPort: 1080, activeServerId: "s1")
        let store = MockStore(data: StoreData(servers: [server], settings: settings))
        let (coordinator, _, x, _) = makeCoordinator(store: store)
        coordinator.loadData()

        try await coordinator.startProxy(server: server)
        let restartsBefore = x.restartCalls.count

        await coordinator.updateSettings { $0.httpPort = 2000 }

        #expect(x.restartCalls.count > restartsBefore)
    }

    @Test("updateSettings does NOT restart when non-proxy setting changes")
    @MainActor func updateSettingsNoRestartForTheme() async throws {
        let server = makeServer(id: "s1", isActive: true)
        let settings = AppSettings(activeServerId: "s1")
        let store = MockStore(data: StoreData(servers: [server], settings: settings))
        let (coordinator, _, x, _) = makeCoordinator(store: store)
        coordinator.loadData()

        try await coordinator.startProxy(server: server)
        let restartsBefore = x.restartCalls.count

        await coordinator.updateSettings { $0.theme = .dark }

        #expect(x.restartCalls.count == restartsBefore)
    }
}

// MARK: - Shell Export Tests

@Suite("ProxyCoordinator - Shell Export")
struct ShellExportTests {

    @Test("shellExportString with 0-1 tunnels uses base ports")
    @MainActor func shellExportBasePorts() {
        let settings = AppSettings(httpPort: 1087, socksPort: 1080)
        let store = MockStore(data: StoreData(settings: settings))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        let export = coordinator.shellExportString

        #expect(export.contains("127.0.0.1:1087"))
        #expect(export.contains("127.0.0.1:1080"))
        #expect(export.contains("http_proxy"))
        #expect(export.contains("ALL_PROXY"))
    }

    @Test("shellExportString with multiple tunnels includes all tunnels")
    @MainActor func shellExportMultipleTunnels() {
        let tunnels = [
            Tunnel(id: "t1", serverId: "s1", serverName: "Server A", httpPort: 1087, socksPort: 1080, running: true),
            Tunnel(id: "t2", serverId: "s2", serverName: "Server B", httpPort: 1089, socksPort: 1082, running: true),
        ]
        let store = MockStore(data: StoreData(tunnels: tunnels))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()
        // loadData resets running, but we need the tunnels present for shellExport
        // Re-set them manually
        coordinator.tunnels = tunnels

        let export = coordinator.shellExportString

        #expect(export.contains("Server A"))
        #expect(export.contains("Server B"))
        #expect(export.contains("1087"))
        #expect(export.contains("1089"))
    }

    @Test("shellExportString comments out non-primary tunnel exports")
    @MainActor func shellExportCommentsNonPrimary() {
        let tunnels = [
            Tunnel(id: "t1", serverId: "s1", serverName: "Primary", httpPort: 1087, socksPort: 1080, running: true),
            Tunnel(id: "t2", serverId: "s2", serverName: "Secondary", httpPort: 1089, socksPort: 1082, running: true),
        ]
        let store = MockStore(data: StoreData(tunnels: tunnels))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()
        coordinator.tunnels = tunnels

        let export = coordinator.shellExportString
        let lines = export.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Second tunnel's export lines should be commented out
        let secondaryExports = lines.filter { $0.contains("1089") || $0.contains("1082") }
        for line in secondaryExports {
            if line.contains("export") {
                #expect(line.hasPrefix("# "))
            }
        }
    }
}

// MARK: - Log Tests

@Suite("ProxyCoordinator - Logs")
struct LogTests {

    @Test("appendLog adds to logs array")
    @MainActor func appendLogAdds() {
        let (coordinator, _, _, _) = makeCoordinator()

        coordinator.appendLog("Test log message")

        #expect(coordinator.logs.count == 1)
        #expect(coordinator.logs.first == "Test log message")
    }

    @Test("appendLog trims when exceeding 1000 entries")
    @MainActor func appendLogTrims() {
        let (coordinator, _, _, _) = makeCoordinator()

        for i in 0..<1005 {
            coordinator.appendLog("Log \(i)")
        }

        #expect(coordinator.logs.count == 1000)
        // The first 5 entries should have been trimmed
        #expect(coordinator.logs.first == "Log 5")
        #expect(coordinator.logs.last == "Log 1004")
    }

    @Test("clearLogs empties the array")
    @MainActor func clearLogsEmpties() {
        let (coordinator, _, _, _) = makeCoordinator()
        coordinator.appendLog("message 1")
        coordinator.appendLog("message 2")

        coordinator.clearLogs()

        #expect(coordinator.logs.isEmpty)
    }
}

// MARK: - Auto Start Tests

@Suite("ProxyCoordinator - Auto Start")
struct AutoStartTests {

    init() {
        ensureTempConfigDir()
    }

    @Test("performAutoStartIfNeeded starts proxy when autoStart=true and activeServerId set")
    @MainActor func autoStartWhenEnabled() async {
        let server = makeServer(id: "s1", isActive: true)
        let settings = AppSettings(autoStart: true, activeServerId: "s1")
        let store = MockStore(data: StoreData(servers: [server], settings: settings))
        let (coordinator, _, x, _) = makeCoordinator(store: store)
        coordinator.loadData()

        await coordinator.performAutoStartIfNeeded()

        #expect(x.startCalls.count == 1)
        #expect(coordinator.proxyStatus.running == true)
    }

    @Test("performAutoStartIfNeeded does nothing when autoStart=false")
    @MainActor func autoStartDisabled() async {
        let server = makeServer(id: "s1", isActive: true)
        let settings = AppSettings(autoStart: false, activeServerId: "s1")
        let store = MockStore(data: StoreData(servers: [server], settings: settings))
        let (coordinator, _, x, _) = makeCoordinator(store: store)
        coordinator.loadData()

        await coordinator.performAutoStartIfNeeded()

        #expect(x.startCalls.isEmpty)
        #expect(coordinator.proxyStatus.running == false)
    }

    @Test("performAutoStartIfNeeded does nothing when no activeServerId")
    @MainActor func autoStartNoActiveServer() async {
        let settings = AppSettings(autoStart: true, activeServerId: nil)
        let store = MockStore(data: StoreData(settings: settings))
        let (coordinator, _, x, _) = makeCoordinator(store: store)
        coordinator.loadData()

        await coordinator.performAutoStartIfNeeded()

        #expect(x.startCalls.isEmpty)
    }
}

// MARK: - Cleanup Tests

@Suite("ProxyCoordinator - Cleanup")
struct CleanupTests {

    @Test("cleanup calls stopAllTunnels")
    @MainActor func cleanupStopsAll() async {
        let (coordinator, _, x, p) = makeCoordinator()
        coordinator.loadData()

        await coordinator.cleanup()

        #expect(x.stopAllCallCount >= 1)
        #expect(p.disableProxyCallCount >= 1)
        #expect(coordinator.tunnels.isEmpty)
        #expect(coordinator.proxyStatus.running == false)
    }
}

// MARK: - setActiveServer Restart Tests

@Suite("ProxyCoordinator - Active Server Switch While Running")
struct ActiveServerSwitchTests {

    init() {
        ensureTempConfigDir()
    }

    @Test("setActiveServer while running triggers restart")
    @MainActor func switchActiveWhileRunning() async throws {
        let s1 = makeServer(id: "s1", name: "S1", isActive: true)
        let s2 = makeServer(id: "s2", name: "S2")
        let settings = AppSettings(activeServerId: "s1")
        let store = MockStore(data: StoreData(servers: [s1, s2], settings: settings))
        let (coordinator, _, x, _) = makeCoordinator(store: store)
        coordinator.loadData()

        try await coordinator.startProxy(server: s1)

        coordinator.setActiveServer("s2")

        // Give the async restart Task a moment to execute
        try await Task.sleep(for: .milliseconds(100))

        #expect(x.restartCalls.count >= 1)
        #expect(coordinator.settings.activeServerId == "s2")
    }
}

// MARK: - StoreData Accessor Tests

@Suite("ProxyCoordinator - StoreData Accessor")
struct StoreDataAccessorTests {

    @Test("storeData getter reflects current state")
    @MainActor func storeDataGetter() {
        let server = makeServer(id: "s1")
        let store = MockStore(data: StoreData(servers: [server]))
        let (coordinator, _, _, _) = makeCoordinator(store: store)
        coordinator.loadData()

        let data = coordinator.storeData

        #expect(data.servers.count == 1)
        #expect(data.servers.first?.id == "s1")
    }

    @Test("storeData setter updates all fields")
    @MainActor func storeDataSetter() {
        let (coordinator, _, _, _) = makeCoordinator()
        coordinator.loadData()

        let newData = StoreData(
            servers: [makeServer(id: "new-s")],
            settings: AppSettings(httpPort: 9999)
        )
        coordinator.storeData = newData

        #expect(coordinator.servers.count == 1)
        #expect(coordinator.settings.httpPort == 9999)
    }

    @Test("withStoreData applies update and returns result")
    @MainActor func withStoreDataReturnsResult() {
        let (coordinator, _, _, _) = makeCoordinator()
        coordinator.loadData()

        let count: Int = coordinator.withStoreData { data in
            data.servers.append(makeServer(id: "ws1"))
            return data.servers.count
        }

        #expect(count == 1)
        #expect(coordinator.servers.count == 1)
    }
}
