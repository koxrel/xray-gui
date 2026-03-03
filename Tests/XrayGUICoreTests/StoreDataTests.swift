import Testing
import Foundation
@testable import XrayGUICore

@Suite("StoreData Tests")
struct StoreDataTests {

    // MARK: - Default Init

    @Test("Default init produces empty collections and default settings")
    func defaultInit() {
        let data = StoreData()
        #expect(data.servers.isEmpty)
        #expect(data.subscriptions.isEmpty)
        #expect(data.tunnels.isEmpty)
        #expect(data.settings == AppSettings.default)
    }

    // MARK: - Resilient Decoding

    @Test("Decoding from empty JSON uses defaults for all fields")
    func decodingEmptyJson() throws {
        let json = Data("{}".utf8)
        let data = try JSONDecoder().decode(StoreData.self, from: json)

        #expect(data.servers.isEmpty)
        #expect(data.subscriptions.isEmpty)
        #expect(data.tunnels.isEmpty)
        #expect(data.settings.httpPort == 1087)
        #expect(data.settings.socksPort == 1080)
    }

    @Test("Decoding preserves non-empty servers array")
    func decodingWithServers() throws {
        let server = ServerConfig(id: "s1", name: "Test", address: "example.com", port: 443, uuid: "uuid-1")
        let original = StoreData(servers: [server])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StoreData.self, from: data)

        #expect(decoded.servers.count == 1)
        #expect(decoded.servers[0].id == "s1")
        #expect(decoded.servers[0].address == "example.com")
    }

    @Test("Decoding preserves non-empty subscriptions array")
    func decodingWithSubscriptions() throws {
        let sub = Subscription(id: "sub-1", name: "My Sub", url: "https://example.com")
        let original = StoreData(subscriptions: [sub])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StoreData.self, from: data)

        #expect(decoded.subscriptions.count == 1)
        #expect(decoded.subscriptions[0].id == "sub-1")
    }

    @Test("Decoding preserves non-empty tunnels array")
    func decodingWithTunnels() throws {
        let tunnel = Tunnel(id: "t-1", serverId: "s-1", serverName: "S", httpPort: 1087, socksPort: 1080)
        let original = StoreData(tunnels: [tunnel])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StoreData.self, from: data)

        #expect(decoded.tunnels.count == 1)
        #expect(decoded.tunnels[0].id == "t-1")
    }

    @Test("Decoding preserves non-default settings")
    func decodingWithCustomSettings() throws {
        let settings = AppSettings(httpPort: 9999, socksPort: 9998, allowLan: true, logLevel: .debug)
        let original = StoreData(settings: settings)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StoreData.self, from: data)

        #expect(decoded.settings.httpPort == 9999)
        #expect(decoded.settings.socksPort == 9998)
        #expect(decoded.settings.allowLan == true)
        #expect(decoded.settings.logLevel == .debug)
    }

    // MARK: - Codable Round-trip

    @Test("Full round-trip preserves all collections and settings")
    func fullRoundTrip() throws {
        let server = ServerConfig(id: "s1", name: "Server", address: "1.2.3.4", port: 443, uuid: "u1")
        let sub = Subscription(id: "sub-1", name: "Sub", url: "https://example.com")
        let tunnel = Tunnel(id: "t-1", serverId: "s1", serverName: "Server", httpPort: 1087, socksPort: 1080)
        let settings = AppSettings(httpPort: 2087, socksPort: 2080, logLevel: .info)

        let original = StoreData(servers: [server], subscriptions: [sub], settings: settings, tunnels: [tunnel])

        let jsonData = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StoreData.self, from: jsonData)

        #expect(decoded.servers.count == 1)
        #expect(decoded.subscriptions.count == 1)
        #expect(decoded.tunnels.count == 1)
        #expect(decoded.settings.httpPort == 2087)
        #expect(decoded.settings.logLevel == .info)
    }

    // MARK: - Mutation

    @Test("StoreData fields are mutable")
    func mutability() {
        var data = StoreData()
        let server = ServerConfig(name: "New", address: "new.com", uuid: "u")
        data.servers.append(server)
        data.settings.httpPort = 9000
        #expect(data.servers.count == 1)
        #expect(data.settings.httpPort == 9000)
    }
}
