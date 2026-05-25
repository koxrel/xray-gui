import Foundation

public final class Store: Storing, Sendable {
    private let fileURL: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("XrayGUI", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.fileURL = appDir.appendingPathComponent("xray-gui-data.json")
        print("[Store] Using store file: \(fileURL.path)")
    }

    // MARK: - Persistence

    public func load() -> StoreData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[Store] No store file found at \(fileURL.path); using defaults.")
            return StoreData()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(StoreData.self, from: data)
            // Merge with defaults to pick up any new settings fields
            var result = decoded
            let defaults = AppSettings.default
            if result.settings.httpPort == 0 { result.settings.httpPort = defaults.httpPort }
            if result.settings.socksPort == 0 { result.settings.socksPort = defaults.socksPort }
            if result.settings.dnsServers.isEmpty { result.settings.dnsServers = defaults.dnsServers }
            if result.settings.bypassDomains.isEmpty { result.settings.bypassDomains = defaults.bypassDomains }
            print("[Store] Loaded store from \(fileURL.path)")
            return result
        } catch {
            print("[Store] Failed to load store at \(fileURL.path): \(error). Backing up corrupted file.")
            let backupURL = fileURL.deletingPathExtension().appendingPathExtension("corrupted.json")
            try? FileManager.default.moveItem(at: fileURL, to: backupURL)
            return StoreData()
        }
    }

    public func save(_ data: StoreData) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save store: \(error)")
        }
    }

    // MARK: - Servers

    public func addServer(_ data: inout StoreData, server: ServerConfig) -> ServerConfig {
        var newServer = server
        if newServer.id.isEmpty { newServer.id = UUID().uuidString }
        newServer.isActive = false
        data.servers.append(newServer)
        save(data)
        return newServer
    }

    public func updateServer(_ data: inout StoreData, server: ServerConfig) -> ServerConfig {
        if let index = data.servers.firstIndex(where: { $0.id == server.id }) {
            data.servers[index] = server
            save(data)
        }
        return server
    }

    public func deleteServer(_ data: inout StoreData, id: String) {
        data.servers.removeAll { $0.id == id }
        if data.settings.activeServerId == id {
            data.settings.activeServerId = nil
        }
        save(data)
    }

    public func setActiveServer(_ data: inout StoreData, id: String?) {
        for i in data.servers.indices {
            data.servers[i].isActive = (data.servers[i].id == id)
        }
        data.settings.activeServerId = id
        save(data)
    }

    public func setServerLatency(_ data: inout StoreData, id: String, latency: Int) {
        if let index = data.servers.firstIndex(where: { $0.id == id }) {
            data.servers[index].latency = latency
            save(data)
        }
    }

    // MARK: - Subscriptions

    public func addSubscription(_ data: inout StoreData, name: String, url: String) -> Subscription {
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

    public func updateSubscription(_ data: inout StoreData, subscription: Subscription) {
        if let index = data.subscriptions.firstIndex(where: { $0.id == subscription.id }) {
            data.subscriptions[index] = subscription
            save(data)
        }
    }

    public func deleteSubscription(_ data: inout StoreData, id: String) {
        // Remove all servers belonging to this subscription.
        // Match by subscriptionId (set on each server by addServersForSubscription),
        // since sub.serverIds may be stale if the subscription was never updated.
        let removedIds = Set(data.servers.filter { $0.subscriptionId == id }.map(\.id))
        data.servers.removeAll { $0.subscriptionId == id }
        if let activeId = data.settings.activeServerId, removedIds.contains(activeId) {
            data.settings.activeServerId = nil
        }
        data.subscriptions.removeAll { $0.id == id }
        save(data)
    }

    public func addServersForSubscription(_ data: inout StoreData, subscriptionId: String, servers: [ServerConfig]) -> [String] {
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

    public func removeServersForSubscription(_ data: inout StoreData, subscriptionId: String) {
        let toRemove = Set(data.servers.filter { $0.subscriptionId == subscriptionId }.map(\.id))
        data.servers.removeAll { toRemove.contains($0.id) }
        if let activeId = data.settings.activeServerId, toRemove.contains(activeId) {
            data.settings.activeServerId = nil
        }
    }

    // MARK: - Settings

    public func updateSettingsTyped(_ data: inout StoreData, _ update: (inout AppSettings) -> Void) -> AppSettings {
        update(&data.settings)
        save(data)
        return data.settings
    }

    // MARK: - Config File Path

    public func configFileURL(for tunnelId: String) -> URL {
        // Sanitize tunnelId to prevent path injection — allow only alphanumeric and hyphens
        let sanitized = tunnelId.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let safeName = sanitized.isEmpty ? "unknown" : sanitized
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("XrayGUI", isDirectory: true)
        return appDir.appendingPathComponent("xray-config-\(safeName).json")
    }

    public func removeConfigFile(for tunnelId: String) {
        try? FileManager.default.removeItem(at: configFileURL(for: tunnelId))
    }
}
