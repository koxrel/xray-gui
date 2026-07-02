import Foundation
@testable import XrayGUICore

/// A test double for `Storing` that performs all CRUD operations in memory
/// without any filesystem I/O. Delegates data mutations to the same logic
/// as the real `Store` (operating on `StoreData`) but replaces persistence
/// with no-ops and uses a temp directory for config file URLs.
final class MockStore: Storing, @unchecked Sendable {

    // MARK: - In-memory state

    var data: StoreData

    // MARK: - Call recording

    var saveCalls: [StoreData] = []
    var loadCallCount: Int = 0
    var removeConfigFileCalls: [String] = []

    // MARK: - Init

    init(data: StoreData = StoreData()) {
        self.data = data
    }

    // MARK: - Persistence (no-ops)

    func load() -> StoreData {
        loadCallCount += 1
        return data
    }

    func save(_ data: StoreData) {
        saveCalls.append(data)
        self.data = data
    }

    func configFileURL(for tunnelId: String) -> URL {
        let sanitized = tunnelId.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let safeName = sanitized.isEmpty ? "unknown" : sanitized
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("xray-test-configs")
            .appendingPathComponent("xray-config-\(safeName).json")
    }

    func removeConfigFile(for tunnelId: String) {
        removeConfigFileCalls.append(tunnelId)
        // Also remove the actual temp file if it was written by ConfigGenerator
        let url = configFileURL(for: tunnelId)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Server CRUD (same logic as Store)

    @discardableResult
    func addServer(_ data: inout StoreData, server: ServerConfig) -> ServerConfig {
        var newServer = server
        if newServer.id.isEmpty { newServer.id = UUID().uuidString }
        newServer.isActive = false
        data.servers.append(newServer)
        save(data)
        return newServer
    }

    @discardableResult
    func updateServer(_ data: inout StoreData, server: ServerConfig) -> ServerConfig {
        if let index = data.servers.firstIndex(where: { $0.id == server.id }) {
            data.servers[index] = server
            save(data)
        }
        return server
    }

    func deleteServer(_ data: inout StoreData, id: String) {
        data.servers.removeAll { $0.id == id }
        if data.settings.activeServerId == id {
            data.settings.activeServerId = nil
        }
        save(data)
    }

    func setActiveServer(_ data: inout StoreData, id: String?) {
        for i in data.servers.indices {
            data.servers[i].isActive = (data.servers[i].id == id)
        }
        data.settings.activeServerId = id
        save(data)
    }

    func setServerLatency(_ data: inout StoreData, id: String, latency: Int) {
        if let index = data.servers.firstIndex(where: { $0.id == id }) {
            data.servers[index].latency = latency
            save(data)
        }
    }

    // MARK: - Subscription CRUD

    func addSubscription(_ data: inout StoreData, name: String, url: String) -> Subscription {
        let sub = Subscription(
            id: UUID().uuidString,
            name: name,
            url: url,
            serverIds: [],
            lastUpdated: nil,
            autoUpdate: true,
            autoUpdateIntervalHours: 24
        )
        data.subscriptions.append(sub)
        save(data)
        return sub
    }

    func updateSubscription(_ data: inout StoreData, subscription: Subscription) {
        if let index = data.subscriptions.firstIndex(where: { $0.id == subscription.id }) {
            data.subscriptions[index] = subscription
            save(data)
        }
    }

    func deleteSubscription(_ data: inout StoreData, id: String) {
        let removedIds = Set(data.servers.filter { $0.subscriptionId == id }.map(\.id))
        data.servers.removeAll { $0.subscriptionId == id }
        if let activeId = data.settings.activeServerId, removedIds.contains(activeId) {
            data.settings.activeServerId = nil
        }
        data.subscriptions.removeAll { $0.id == id }
        save(data)
    }

    func addServersForSubscription(_ data: inout StoreData, subscriptionId: String, servers: [ServerConfig]) -> [String] {
        var newIds: [String] = []
        for var server in servers {
            server.id = UUID().uuidString
            server.isActive = false
            server.subscriptionId = subscriptionId
            data.servers.append(server)
            newIds.append(server.id)
        }
        save(data)
        return newIds
    }

    func removeServersForSubscription(_ data: inout StoreData, subscriptionId: String) {
        let toRemove = Set(data.servers.filter { $0.subscriptionId == subscriptionId }.map(\.id))
        data.servers.removeAll { toRemove.contains($0.id) }
        if let activeId = data.settings.activeServerId, toRemove.contains(activeId) {
            data.settings.activeServerId = nil
        }
    }

    @discardableResult
    func reconcileServersForSubscription(_ data: inout StoreData, subscriptionId: String, servers parsedServers: [ServerConfig]) -> [String] {
        var existingByKey: [String: [ServerConfig]] = [:]
        for server in data.servers where server.subscriptionId == subscriptionId {
            existingByKey[server.identityKey, default: []].append(server)
        }

        var reconciled: [ServerConfig] = []
        var reconciledIds: [String] = []

        for var parsed in parsedServers {
            parsed.subscriptionId = subscriptionId
            let key = parsed.identityKey
            if var matches = existingByKey[key], let existing = matches.first {
                matches.removeFirst()
                existingByKey[key] = matches
                parsed.id = existing.id
                parsed.isActive = existing.isActive
                parsed.latency = existing.latency
            } else {
                parsed.id = UUID().uuidString
                parsed.isActive = false
                parsed.latency = nil
            }
            reconciled.append(parsed)
            reconciledIds.append(parsed.id)
        }

        let survivingIds = Set(reconciledIds)
        if let activeId = data.settings.activeServerId,
           data.servers.contains(where: { $0.id == activeId && $0.subscriptionId == subscriptionId }),
           !survivingIds.contains(activeId) {
            data.settings.activeServerId = nil
        }

        data.servers.removeAll { $0.subscriptionId == subscriptionId }
        data.servers.append(contentsOf: reconciled)
        save(data)
        return reconciledIds
    }

    // MARK: - Settings

    @discardableResult
    func updateSettingsTyped(_ data: inout StoreData, _ update: (inout AppSettings) -> Void) -> AppSettings {
        update(&data.settings)
        save(data)
        return data.settings
    }
}
