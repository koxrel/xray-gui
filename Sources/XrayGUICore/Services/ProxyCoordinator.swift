import Foundation
import Observation

public enum ProxyError: LocalizedError {
    case noActiveServer

    public var errorDescription: String? {
        switch self {
        case .noActiveServer: return "No active server selected"
        }
    }
}

@Observable
@MainActor
public final class ProxyCoordinator {
    // MARK: - Published State
    public var servers: [ServerConfig] = []
    public var subscriptions: [Subscription] = []
    public var settings: AppSettings = .default
    public var proxyStatus: ProxyStatus = ProxyStatus()
    public var tunnels: [Tunnel] = []
    public var tunnelStatistics: [TunnelStatisticsSnapshot] = []
    public var logs: [String] = []
    public var isLoading = false

    // MARK: - Services
    public let store: any Storing
    public let xrayManager: any XrayManaging
    public let proxyManager: any ProxyManaging
    private let statsClient: any TunnelStatsQuerying

    private let logBufferMax = 1000
    private let statsAPIBasePort = 10085
    private var tunnelStatsAPIPorts: [String: Int] = [:]

    public init(
        store: any Storing,
        xrayManager: any XrayManaging,
        proxyManager: any ProxyManaging,
        statsClient: any TunnelStatsQuerying = XrayStatsClient()
    ) {
        self.store = store
        self.xrayManager = xrayManager
        self.proxyManager = proxyManager
        self.statsClient = statsClient
    }

    public func setupLogCallback() {
        xrayManager.logCallback = { [weak self] line in
            Task { @MainActor in
                self?.appendLog(line)
            }
        }
    }

    // MARK: - Data Loading

    public func loadData() {
        let data = store.load()

        servers = data.servers
        subscriptions = data.subscriptions
        settings = data.settings
        tunnels = data.tunnels

        // Mark all persisted tunnels as not running (they need to be re-started)
        for i in tunnels.indices {
            tunnels[i].running = false
            tunnels[i].startedAt = nil
        }

        tunnelStatistics.removeAll()
        tunnelStatsAPIPorts.removeAll()
        proxyStatus = makeProxyStatus(running: false)
    }

    public var storeData: StoreData {
        get { StoreData(servers: servers, subscriptions: subscriptions, settings: settings, tunnels: tunnels) }
        set {
            servers = newValue.servers
            subscriptions = newValue.subscriptions
            settings = newValue.settings
            tunnels = newValue.tunnels
        }
    }

    @discardableResult
    public func withStoreData<T>(_ update: (inout StoreData) -> T) -> T {
        var data = storeData
        let result = update(&data)
        storeData = data
        return result
    }

    public func makeProxyStatus(running: Bool, activeServer: ServerConfig? = nil, startedAt: Date? = nil) -> ProxyStatus {
        ProxyStatus(running: running, activeServer: activeServer, proxyMode: settings.proxyMode,
                    httpPort: settings.httpPort, socksPort: settings.socksPort, startedAt: startedAt)
    }

    public func saveTunnels() {
        var data = storeData
        data.tunnels = tunnels
        store.save(data)
    }

    // MARK: - Auto Start

    public func performAutoStartIfNeeded() async {
        guard settings.autoStart, settings.activeServerId != nil else { return }
        guard let activeServer = servers.first(where: { $0.isActive }) ?? servers.first(where: { $0.id == settings.activeServerId }) else { return }
        do {
            try await startProxy(server: activeServer)
        } catch {
            appendLog("[AutoStart] Failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Server Methods

    public func addServer(_ server: ServerConfig) {
        withStoreData { self.store.addServer(&$0, server: server) }
    }

    public func updateServer(_ server: ServerConfig) {
        withStoreData { self.store.updateServer(&$0, server: server) }
    }

    public func deleteServer(_ id: String) {
        withStoreData { self.store.deleteServer(&$0, id: id) }
    }

    public func setActiveServer(_ id: String?) {
        withStoreData { self.store.setActiveServer(&$0, id: id) }

        // If running, restart with new server
        if proxyStatus.running, let serverId = id, let server = servers.first(where: { $0.id == serverId }) {
            Task {
                do {
                    try await restartProxy(server: server)
                } catch {
                    appendLog("[Proxy] Failed to restart with new server: \(error.localizedDescription)")
                }
            }
        }
    }

    public func testLatency(_ serverId: String) async {
        guard let server = servers.first(where: { $0.id == serverId }) else { return }
        let manager = xrayManager
        let latency = await manager.testLatency(server: server)
        withStoreData { self.store.setServerLatency(&$0, id: serverId, latency: latency) }
    }

    public func testAllLatency() async {
        let serverIds = servers.map(\.id)
        let batchSize = 3
        for batchStart in stride(from: 0, to: serverIds.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, serverIds.count)
            let batch = serverIds[batchStart..<batchEnd]
            await withTaskGroup(of: Void.self) { group in
                for id in batch {
                    group.addTask {
                        await self.testLatency(id)
                    }
                }
            }
        }
    }

    public func importServerUrl(_ urlString: String) -> ServerConfig? {
        guard let parsed = SubscriptionManager.parseVlessUrl(urlString) else { return nil }
        return withStoreData { self.store.addServer(&$0, server: parsed) }
    }

    // MARK: - Subscription Methods

    public func addSubscription(name: String, url: String) async {
        let sub = withStoreData { self.store.addSubscription(&$0, name: name, url: url) }

        // Immediately fetch servers
        await updateSubscription(sub.id)
    }

    private func performSubscriptionUpdate(_ sub: Subscription) async throws {
        let content = try await SubscriptionManager.fetchSubscription(url: sub.url)
        let parsedServers = SubscriptionManager.parseSubscriptionContent(content)
        withStoreData { data in
            self.store.removeServersForSubscription(&data, subscriptionId: sub.id)
            let newIds = self.store.addServersForSubscription(&data, subscriptionId: sub.id, servers: parsedServers)
            if var updatedSub = data.subscriptions.first(where: { $0.id == sub.id }) {
                updatedSub.serverIds = newIds
                updatedSub.lastUpdated = ISO8601DateFormatter().string(from: Date())
                self.store.updateSubscription(&data, subscription: updatedSub)
            }
        }
    }

    public func updateSubscription(_ id: String) async {
        guard let sub = subscriptions.first(where: { $0.id == id }) else { return }
        do {
            try await performSubscriptionUpdate(sub)
        } catch {
            appendLog("[Subscription] Failed to update '\(sub.name)': \(error.localizedDescription)")
        }
    }

    public func updateAllSubscriptions() async -> (success: Int, failed: Int) {
        var success = 0
        var failed = 0
        for sub in subscriptions {
            do {
                try await performSubscriptionUpdate(sub)
                success += 1
            } catch {
                failed += 1
                appendLog("[Subscription] Failed to update '\(sub.name)': \(error.localizedDescription)")
            }
        }
        return (success, failed)
    }

    public func deleteSubscription(_ id: String) {
        withStoreData { self.store.deleteSubscription(&$0, id: id) }
    }

    // MARK: - Proxy Control

    public func startProxy() async throws {
        guard let server = servers.first(where: { $0.isActive }) ?? servers.first(where: { $0.id == settings.activeServerId }) else {
            throw ProxyError.noActiveServer
        }
        try await startProxy(server: server)
    }

    public func startProxy(server: ServerConfig) async throws {
        let clock = ContinuousClock()
        let totalStart = clock.now
        let tunnelId = Tunnel.primaryId
        let configURL = store.configFileURL(for: tunnelId)
        let statsAPIPort = statsAPIPort(for: tunnelId)
        try ConfigGenerator.writeConfig(server: server, settings: settings, statsAPIPort: statsAPIPort, to: configURL)

        let xrayStart = clock.now
        try await xrayManager.start(tunnelId: tunnelId, configPath: configURL.path, socksPort: settings.socksPort)
        let xrayDuration = xrayStart.duration(to: clock.now)

        // Apply system proxy
        let proxyStart = clock.now
        await proxyManager.applyProxyMode(
            settings.proxyMode,
            httpPort: settings.httpPort,
            socksPort: settings.socksPort,
            pacUrl: settings.pacUrl
        )
        let proxyDuration = proxyStart.duration(to: clock.now)

        // Update tunnels list
        let tunnel = Tunnel(
            id: tunnelId,
            serverId: server.id,
            serverName: server.name,
            httpPort: settings.httpPort,
            socksPort: settings.socksPort,
            running: true,
            startedAt: Date()
        )
        if let idx = tunnels.firstIndex(where: { $0.id == tunnelId }) {
            tunnels[idx] = tunnel
        } else {
            tunnels.insert(tunnel, at: 0)
        }
        resetTunnelStatistics(for: tunnelId)
        saveTunnels()

        proxyStatus = makeProxyStatus(running: true, activeServer: server, startedAt: Date())
        appendLog("[Perf] startProxy xray=\(ms(xrayDuration))ms proxy=\(ms(proxyDuration))ms total=\(ms(totalStart.duration(to: clock.now)))ms")
    }

    public func stopProxy() async throws {
        let tunnelId = Tunnel.primaryId
        try await xrayManager.stop(tunnelId: tunnelId)
        store.removeConfigFile(for: tunnelId)
        await proxyManager.disableProxy()

        tunnels.removeAll { $0.id == tunnelId }
        tunnelStatsAPIPorts.removeValue(forKey: tunnelId)
        resetTunnelStatistics(for: tunnelId)
        saveTunnels()

        proxyStatus = makeProxyStatus(running: false)
    }

    public func setProxyMode(_ mode: ProxyMode) async {
        withStoreData { _ = self.store.updateSettingsTyped(&$0) { $0.proxyMode = mode } }

        proxyStatus = makeProxyStatus(running: proxyStatus.running, activeServer: proxyStatus.activeServer, startedAt: proxyStatus.startedAt)

        if proxyStatus.running {
            // Apply new mode first, then disable old to minimize IP leak window
            await proxyManager.applyProxyMode(
                mode,
                httpPort: settings.httpPort,
                socksPort: settings.socksPort,
                pacUrl: settings.pacUrl
            )
        }
    }

    private func restartProxy(server: ServerConfig) async throws {
        let tunnelId = Tunnel.primaryId
        let configURL = store.configFileURL(for: tunnelId)
        let statsAPIPort = statsAPIPort(for: tunnelId)
        try ConfigGenerator.writeConfig(server: server, settings: settings, statsAPIPort: statsAPIPort, to: configURL)
        try await xrayManager.restart(tunnelId: tunnelId, configPath: configURL.path, socksPort: settings.socksPort)

        await proxyManager.applyProxyMode(
            settings.proxyMode,
            httpPort: settings.httpPort,
            socksPort: settings.socksPort,
            pacUrl: settings.pacUrl
        )

        // Update primary tunnel
        if let idx = tunnels.firstIndex(where: { $0.id == tunnelId }) {
            tunnels[idx] = Tunnel(
                id: tunnelId,
                serverId: server.id,
                serverName: server.name,
                httpPort: settings.httpPort,
                socksPort: settings.socksPort,
                running: true,
                startedAt: Date()
            )
        }
        resetTunnelStatistics(for: tunnelId)
        saveTunnels()

        proxyStatus.activeServer = server
        proxyStatus.startedAt = Date()
    }

    // MARK: - Settings

    public func updateSettings(_ update: (inout AppSettings) -> Void) async {
        let oldSettings = settings
        withStoreData { _ = self.store.updateSettingsTyped(&$0, update) }

        proxyStatus = makeProxyStatus(running: proxyStatus.running, activeServer: proxyStatus.activeServer, startedAt: proxyStatus.startedAt)

        // Only restart if proxy-relevant settings changed
        let needsRestart = settings.needsProxyRestart(comparedTo: oldSettings)

        if needsRestart, proxyStatus.running, let server = proxyStatus.activeServer {
            do {
                try await restartProxy(server: server)
            } catch {
                appendLog("[Settings] Failed to restart proxy after settings change: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Logs

    public func appendLog(_ message: String) {
        logs.append(message)
        if logs.count > logBufferMax {
            logs.removeFirst(logs.count - logBufferMax)
        }
    }

    public func clearLogs() {
        logs.removeAll()
    }

    // MARK: - Multi-Tunnel

    public func addTunnel(serverId: String, httpPort: Int? = nil, socksPort: Int? = nil) async throws -> Tunnel {
        guard let server = servers.first(where: { $0.id == serverId }) else {
            throw ProxyError.noActiveServer
        }

        let tunnelId = UUID().uuidString
        let defaults = nextAvailablePorts()
        let finalHttp = httpPort ?? defaults.http
        let finalSocks = socksPort ?? defaults.socks

        let configURL = store.configFileURL(for: tunnelId)
        let statsAPIPort = statsAPIPort(for: tunnelId)
        try ConfigGenerator.writeConfig(
            server: server,
            settings: settings,
            httpPort: finalHttp,
            socksPort: finalSocks,
            statsAPIPort: statsAPIPort,
            to: configURL
        )

        try await xrayManager.start(tunnelId: tunnelId, configPath: configURL.path, socksPort: finalSocks)

        let tunnel = Tunnel(
            id: tunnelId,
            serverId: server.id,
            serverName: server.name,
            httpPort: finalHttp,
            socksPort: finalSocks,
            running: true,
            startedAt: Date()
        )
        tunnels.append(tunnel)
        resetTunnelStatistics(for: tunnelId)
        saveTunnels()
        return tunnel
    }

    public func updateTunnelPorts(_ tunnelId: String, httpPort: Int, socksPort: Int) async throws {
        guard let idx = tunnels.firstIndex(where: { $0.id == tunnelId }) else { return }
        let tunnel = tunnels[idx]

        // Nothing to do if ports unchanged
        guard tunnel.httpPort != httpPort || tunnel.socksPort != socksPort else { return }

        tunnels[idx].httpPort = httpPort
        tunnels[idx].socksPort = socksPort

        // If running, restart with new ports
        if tunnel.running {
            guard let server = servers.first(where: { $0.id == tunnel.serverId }) else {
                throw ProxyError.noActiveServer
            }
            try await xrayManager.stop(tunnelId: tunnelId)
            let configURL = store.configFileURL(for: tunnelId)
            let statsAPIPort = statsAPIPort(for: tunnelId)
            try ConfigGenerator.writeConfig(
                server: server,
                settings: settings,
                httpPort: httpPort,
                socksPort: socksPort,
                statsAPIPort: statsAPIPort,
                to: configURL
            )
            try await xrayManager.start(tunnelId: tunnelId, configPath: configURL.path, socksPort: socksPort)
            tunnels[idx].startedAt = Date()
            resetTunnelStatistics(for: tunnelId)

            // If this is the primary tunnel, update system proxy too
            if tunnelId == Tunnel.primaryId {
                await proxyManager.applyProxyMode(
                    settings.proxyMode,
                    httpPort: httpPort,
                    socksPort: socksPort,
                    pacUrl: settings.pacUrl
                )
            }
        }
        saveTunnels()
    }

    public func pauseTunnel(_ tunnelId: String) async {
        do {
            try await xrayManager.stop(tunnelId: tunnelId)
        } catch {
            appendLog("[Tunnel] Failed to pause tunnel \(tunnelId): \(error.localizedDescription)")
        }
        if let idx = tunnels.firstIndex(where: { $0.id == tunnelId }) {
            tunnels[idx].running = false
            tunnels[idx].startedAt = nil
        }
        resetTunnelStatistics(for: tunnelId)
        saveTunnels()
    }

    public func resumeTunnel(_ tunnelId: String) async throws {
        guard let idx = tunnels.firstIndex(where: { $0.id == tunnelId }) else { return }
        let tunnel = tunnels[idx]
        guard let server = servers.first(where: { $0.id == tunnel.serverId }) else {
            throw ProxyError.noActiveServer
        }

        let configURL = store.configFileURL(for: tunnelId)
        let statsAPIPort = statsAPIPort(for: tunnelId)
        try ConfigGenerator.writeConfig(
            server: server,
            settings: settings,
            httpPort: tunnel.httpPort,
            socksPort: tunnel.socksPort,
            statsAPIPort: statsAPIPort,
            to: configURL
        )
        try await xrayManager.start(tunnelId: tunnelId, configPath: configURL.path, socksPort: tunnel.socksPort)

        tunnels[idx].running = true
        tunnels[idx].startedAt = Date()
        resetTunnelStatistics(for: tunnelId)
        saveTunnels()
    }

    public func resumeAllTunnels() async {
        for tunnel in tunnels where !tunnel.running {
            do {
                try await resumeTunnel(tunnel.id)
            } catch {
                appendLog("[Tunnel] Failed to resume tunnel \(tunnel.id): \(error.localizedDescription)")
            }
        }
    }

    public func removeTunnel(_ tunnelId: String) async {
        do {
            try await xrayManager.stop(tunnelId: tunnelId)
        } catch {
            appendLog("[Tunnel] Failed to stop tunnel \(tunnelId) before removal: \(error.localizedDescription)")
        }
        store.removeConfigFile(for: tunnelId)
        tunnels.removeAll { $0.id == tunnelId }
        tunnelStatsAPIPorts.removeValue(forKey: tunnelId)
        resetTunnelStatistics(for: tunnelId)
        saveTunnels()
    }

    public func pauseAllTunnels() async {
        for tunnel in tunnels where tunnel.running {
            await pauseTunnel(tunnel.id)
        }
        await proxyManager.disableProxy()
        proxyStatus = makeProxyStatus(running: false)
    }

    public func stopAllTunnels() async {
        await xrayManager.stopAll()
        for tunnelId in tunnels.map(\.id) {
            store.removeConfigFile(for: tunnelId)
        }
        tunnels.removeAll()
        tunnelStatsAPIPorts.removeAll()
        tunnelStatistics.removeAll()
        saveTunnels()

        await proxyManager.disableProxy()
        proxyStatus = makeProxyStatus(running: false)
    }

    public var hasPausedTunnels: Bool {
        tunnels.contains { !$0.running }
    }

    public var tunnelStatisticsSummary: TunnelStatisticsSummary {
        TunnelStatisticsSummary(snapshots: tunnelStatistics)
    }

    public func nextAvailablePortsPreview() -> (http: Int, socks: Int) {
        nextAvailablePorts()
    }

    private func nextAvailablePorts() -> (http: Int, socks: Int) {
        let usedPorts = Set(tunnels.flatMap { [$0.httpPort, $0.socksPort] })
        var httpPort = settings.httpPort
        var socksPort = settings.socksPort

        // Keep incrementing by 2 until we find a pair that's not in use
        while usedPorts.contains(httpPort) || usedPorts.contains(socksPort) {
            httpPort += 2
            socksPort += 2
            // No valid ports available -- return base ports as fallback
            if httpPort > 65535 || socksPort > 65535 {
                appendLog("[Tunnel] No available ports in valid range (1-65535)")
                return (http: settings.httpPort, socks: settings.socksPort)
            }
        }
        return (http: httpPort, socks: socksPort)
    }

    public func refreshTunnelStatistics(now: Date = Date()) async {
        let activeTunnels = tunnels.filter(\.running)
        guard !activeTunnels.isEmpty else {
            tunnelStatistics.removeAll()
            return
        }

        let previousById = Dictionary(uniqueKeysWithValues: tunnelStatistics.map { ($0.id, $0) })
        let apiPorts = Dictionary(uniqueKeysWithValues: activeTunnels.map { ($0.id, statsAPIPort(for: $0.id)) })

        let results = await withTaskGroup(of: (String, Result<TunnelTrafficStats, Error>).self, returning: [String: Result<TunnelTrafficStats, Error>].self) { group in
            for tunnel in activeTunnels {
                guard let apiPort = apiPorts[tunnel.id] else { continue }
                let statsClient = self.statsClient
                group.addTask {
                    do {
                        return (tunnel.id, .success(try await statsClient.queryStats(apiPort: apiPort)))
                    } catch {
                        return (tunnel.id, .failure(error))
                    }
                }
            }

            var aggregated: [String: Result<TunnelTrafficStats, Error>] = [:]
            for await (tunnelId, result) in group {
                aggregated[tunnelId] = result
            }
            return aggregated
        }

        tunnelStatistics = activeTunnels.map { tunnel in
            let previous = previousById[tunnel.id]
            switch results[tunnel.id] {
            case let .success(traffic):
                return makeStatisticsSnapshot(for: tunnel, traffic: traffic, previous: previous, now: now)
            case .failure, .none:
                return makeUnavailableStatisticsSnapshot(for: tunnel, previous: previous)
            }
        }
    }

    private func statsAPIPort(for tunnelId: String) -> Int {
        if let existing = tunnelStatsAPIPorts[tunnelId] {
            return existing
        }
        let allocated = nextAvailableStatsAPIPort()
        tunnelStatsAPIPorts[tunnelId] = allocated
        return allocated
    }

    private func nextAvailableStatsAPIPort() -> Int {
        let usedPorts = Set(tunnels.flatMap { [$0.httpPort, $0.socksPort] })
            .union(tunnelStatsAPIPorts.values)
        var port = statsAPIBasePort

        while usedPorts.contains(port) {
            port += 1
            if port > 65535 {
                appendLog("[Tunnel] No available stats API ports in valid range (1-65535)")
                return statsAPIBasePort
            }
        }

        return port
    }

    private func resetTunnelStatistics(for tunnelId: String) {
        tunnelStatistics.removeAll { $0.id == tunnelId }
    }

    private func makeStatisticsSnapshot(
        for tunnel: Tunnel,
        traffic: TunnelTrafficStats,
        previous: TunnelStatisticsSnapshot?,
        now: Date
    ) -> TunnelStatisticsSnapshot {
        let uploadRate = rate(
            current: traffic.uplinkBytes,
            previous: previous?.uplinkBytes,
            previousDate: previous?.lastUpdated,
            now: now
        )
        let downloadRate = rate(
            current: traffic.downlinkBytes,
            previous: previous?.downlinkBytes,
            previousDate: previous?.lastUpdated,
            now: now
        )

        return TunnelStatisticsSnapshot(
            id: tunnel.id,
            serverName: tunnel.serverName,
            httpPort: tunnel.httpPort,
            socksPort: tunnel.socksPort,
            startedAt: tunnel.startedAt,
            isPrimary: tunnel.id == Tunnel.primaryId,
            isAvailable: true,
            lastUpdated: now,
            uplinkBytes: traffic.uplinkBytes,
            downlinkBytes: traffic.downlinkBytes,
            uploadRateBytesPerSecond: uploadRate,
            downloadRateBytesPerSecond: downloadRate
        )
    }

    private func makeUnavailableStatisticsSnapshot(
        for tunnel: Tunnel,
        previous: TunnelStatisticsSnapshot?
    ) -> TunnelStatisticsSnapshot {
        TunnelStatisticsSnapshot(
            id: tunnel.id,
            serverName: tunnel.serverName,
            httpPort: tunnel.httpPort,
            socksPort: tunnel.socksPort,
            startedAt: tunnel.startedAt,
            isPrimary: tunnel.id == Tunnel.primaryId,
            isAvailable: false,
            lastUpdated: previous?.lastUpdated,
            uplinkBytes: previous?.uplinkBytes ?? 0,
            downlinkBytes: previous?.downlinkBytes ?? 0,
            uploadRateBytesPerSecond: 0,
            downloadRateBytesPerSecond: 0
        )
    }

    private func rate(current: UInt64, previous: UInt64?, previousDate: Date?, now: Date) -> Double {
        guard let previous, let previousDate else { return 0 }
        let elapsed = now.timeIntervalSince(previousDate)
        guard elapsed > 0, current >= previous else { return 0 }
        return Double(current - previous) / elapsed
    }

    // MARK: - Shell Export

    public var shellExportString: String {
        if tunnels.count <= 1 {
            return """
            export http_proxy=http://127.0.0.1:\(settings.httpPort)
            export https_proxy=http://127.0.0.1:\(settings.httpPort)
            export ALL_PROXY=socks5://127.0.0.1:\(settings.socksPort)
            """
        }

        var lines: [String] = []
        for (i, tunnel) in tunnels.enumerated() {
            lines.append("# Tunnel: \(tunnel.serverName) (HTTP :\(tunnel.httpPort), SOCKS :\(tunnel.socksPort))")
            let prefix = i == 0 ? "" : "# "
            lines.append("\(prefix)export http_proxy=http://127.0.0.1:\(tunnel.httpPort)")
            lines.append("\(prefix)export https_proxy=http://127.0.0.1:\(tunnel.httpPort)")
            lines.append("\(prefix)export ALL_PROXY=socks5://127.0.0.1:\(tunnel.socksPort)")
            if i < tunnels.count - 1 { lines.append("") }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Cleanup

    public func cleanup() async {
        await stopAllTunnels()
    }

    private func ms(_ duration: Duration) -> Int {
        let components = duration.components
        let seconds = Double(components.seconds) * 1_000
        let attoseconds = Double(components.attoseconds) / 1_000_000_000_000_000
        return max(0, Int((seconds + attoseconds).rounded()))
    }
}
