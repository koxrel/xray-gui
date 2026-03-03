import Testing
import Foundation
@testable import XrayGUICore

@Suite("Store Tests")
struct StoreTests {

    // MARK: - Server CRUD

    @Test("addServer appends and sets isActive to false")
    func addServer() {
        let store = Store()
        var data = StoreData()
        let server = ServerConfig(name: "Test", address: "test.com", uuid: "abc")
        let added = store.addServer(&data, server: server)

        #expect(data.servers.count == 1)
        #expect(added.isActive == false)
        #expect(added.address == "test.com")
        #expect(!added.id.isEmpty)
    }

    @Test("updateServer modifies existing server")
    func updateServer() {
        let store = Store()
        var data = StoreData()
        let server = store.addServer(&data, server: ServerConfig(name: "Original", address: "a.com", uuid: "1"))

        var modified = server
        modified.name = "Updated"
        store.updateServer(&data, server: modified)

        #expect(data.servers.count == 1)
        #expect(data.servers[0].name == "Updated")
    }

    @Test("deleteServer removes server and clears activeServerId if matching")
    func deleteServer() {
        let store = Store()
        var data = StoreData()
        let server = store.addServer(&data, server: ServerConfig(name: "ToDelete", address: "d.com", uuid: "1"))
        store.setActiveServer(&data, id: server.id)

        #expect(data.settings.activeServerId == server.id)

        store.deleteServer(&data, id: server.id)
        #expect(data.servers.isEmpty)
        #expect(data.settings.activeServerId == nil)
    }

    @Test("setActiveServer marks correct server as active")
    func setActiveServer() {
        let store = Store()
        var data = StoreData()
        let s1 = store.addServer(&data, server: ServerConfig(name: "S1", address: "s1.com", uuid: "1"))
        let s2 = store.addServer(&data, server: ServerConfig(name: "S2", address: "s2.com", uuid: "2"))

        store.setActiveServer(&data, id: s2.id)

        #expect(data.servers[0].isActive == false)
        #expect(data.servers[1].isActive == true)
        #expect(data.settings.activeServerId == s2.id)

        // Deselect all
        store.setActiveServer(&data, id: nil)
        #expect(data.servers.allSatisfy { !$0.isActive })
        #expect(data.settings.activeServerId == nil)

        // Suppress unused variable warning
        _ = s1
    }

    @Test("setServerLatency updates latency for matching server")
    func setServerLatency() {
        let store = Store()
        var data = StoreData()
        let server = store.addServer(&data, server: ServerConfig(name: "S1", address: "s1.com", uuid: "1"))

        store.setServerLatency(&data, id: server.id, latency: 42)
        #expect(data.servers[0].latency == 42)
    }

    // MARK: - Subscription CRUD

    @Test("addSubscription creates subscription with correct fields")
    func addSubscription() {
        let store = Store()
        var data = StoreData()
        let sub = store.addSubscription(&data, name: "My Sub", url: "https://example.com/sub")

        #expect(data.subscriptions.count == 1)
        #expect(sub.name == "My Sub")
        #expect(sub.url == "https://example.com/sub")
        #expect(sub.serverIds.isEmpty)
        #expect(sub.autoUpdate == true)
    }

    @Test("deleteSubscription removes subscription and its servers")
    func deleteSubscription() {
        let store = Store()
        var data = StoreData()
        let sub = store.addSubscription(&data, name: "Sub", url: "https://example.com")

        // Add servers for this subscription
        let serverIds = store.addServersForSubscription(
            &data,
            subscriptionId: sub.id,
            servers: [
                ServerConfig(name: "S1", address: "s1.com", uuid: "1"),
                ServerConfig(name: "S2", address: "s2.com", uuid: "2")
            ]
        )
        #expect(data.servers.count == 2)

        // Set one as active
        store.setActiveServer(&data, id: serverIds[0])

        // Delete subscription
        store.deleteSubscription(&data, id: sub.id)
        #expect(data.subscriptions.isEmpty)
        #expect(data.servers.isEmpty)
        #expect(data.settings.activeServerId == nil)
    }

    @Test("addServersForSubscription assigns subscriptionId and generates IDs")
    func addServersForSubscription() {
        let store = Store()
        var data = StoreData()

        let ids = store.addServersForSubscription(
            &data,
            subscriptionId: "sub-1",
            servers: [
                ServerConfig(name: "S1", address: "s1.com", uuid: "1"),
                ServerConfig(name: "S2", address: "s2.com", uuid: "2")
            ]
        )

        #expect(ids.count == 2)
        #expect(data.servers.count == 2)
        #expect(data.servers.allSatisfy { $0.subscriptionId == "sub-1" })
        #expect(data.servers.allSatisfy { !$0.isActive })
        // IDs should be newly generated, not the original empty string
        #expect(data.servers.allSatisfy { !$0.id.isEmpty })
    }

    @Test("removeServersForSubscription clears active server if affected")
    func removeServersForSubscription() {
        let store = Store()
        var data = StoreData()

        let ids = store.addServersForSubscription(
            &data,
            subscriptionId: "sub-1",
            servers: [ServerConfig(name: "S1", address: "s1.com", uuid: "1")]
        )
        store.setActiveServer(&data, id: ids[0])

        store.removeServersForSubscription(&data, subscriptionId: "sub-1")
        #expect(data.servers.isEmpty)
        #expect(data.settings.activeServerId == nil)
    }

    // MARK: - Settings

    @Test("updateSettingsTyped applies mutation and returns updated settings")
    func updateSettings() {
        let store = Store()
        var data = StoreData()

        let updated = store.updateSettingsTyped(&data) { s in
            s.httpPort = 9999
            s.enableMux = true
        }

        #expect(updated.httpPort == 9999)
        #expect(updated.enableMux == true)
        #expect(data.settings.httpPort == 9999)
    }

    // MARK: - Config File URL

    @Test("configFileURL sanitizes tunnel ID to prevent path injection")
    func configFileUrlSanitization() {
        let store = Store()

        let safe = store.configFileURL(for: "my-tunnel-123")
        #expect(safe.lastPathComponent == "xray-config-my-tunnel-123.json")

        let malicious = store.configFileURL(for: "../../../etc/passwd")
        #expect(malicious.lastPathComponent == "xray-config-etcpasswd.json")

        let empty = store.configFileURL(for: "///")
        #expect(empty.lastPathComponent == "xray-config-unknown.json")
    }
}
