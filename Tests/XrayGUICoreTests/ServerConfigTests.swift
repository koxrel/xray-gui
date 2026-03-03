import Testing
import Foundation
@testable import XrayGUICore

@Suite("ServerConfig Tests")
struct ServerConfigTests {

    // MARK: - Default Init

    @Test("Default initializer sets expected values")
    func defaultInit() {
        let config = ServerConfig()
        #expect(config.port == 443)
        #expect(config.encryption == "none")
        #expect(config.network == "tcp")
        #expect(config.security == "none")
        #expect(config.alpn.isEmpty)
        #expect(config.allowInsecure == false)
        #expect(config.isActive == false)
        #expect(config.latency == nil)
        #expect(config.subscriptionId == nil)
        #expect(!config.id.isEmpty) // UUID is auto-generated
    }

    // MARK: - Codable Round-trip

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = ServerConfig(
            id: "test-id",
            name: "Test Server",
            address: "example.com",
            port: 8443,
            uuid: "abc-123",
            flow: "xtls-rprx-vision",
            encryption: "none",
            network: "ws",
            security: "tls",
            sni: "example.com",
            fingerprint: "chrome",
            publicKey: "pk123",
            shortId: "sid456",
            alpn: ["h2", "http/1.1"],
            allowInsecure: false,
            wsPath: "/ws",
            wsHost: "cdn.example.com",
            grpcServiceName: nil,
            grpcMultiMode: nil,
            headerType: nil,
            subscriptionId: "sub-1",
            latency: 42,
            isActive: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(ServerConfig.self, from: data)

        #expect(decoded == original)
    }

    // MARK: - Resilient Decoding

    @Test("Decoding from empty JSON object uses defaults")
    func decodingWithMissingFields() throws {
        let json = Data("{}".utf8)
        let config = try JSONDecoder().decode(ServerConfig.self, from: json)
        #expect(config.port == 443)
        #expect(config.encryption == "none")
        #expect(config.network == "tcp")
        #expect(config.security == "none")
        #expect(config.isActive == false)
    }

    @Test("Decoding preserves optional nil values")
    func decodingOptionalNils() throws {
        let json = Data("""
        {"id": "x", "name": "Test", "address": "1.2.3.4", "port": 443}
        """.utf8)
        let config = try JSONDecoder().decode(ServerConfig.self, from: json)
        #expect(config.wsPath == nil)
        #expect(config.wsHost == nil)
        #expect(config.grpcServiceName == nil)
        #expect(config.latency == nil)
        #expect(config.subscriptionId == nil)
    }

    // MARK: - Equatable

    @Test("Two configs with same fields are equal")
    func equality() {
        let a = ServerConfig(id: "1", name: "S", address: "a.com", port: 443, uuid: "u")
        let b = ServerConfig(id: "1", name: "S", address: "a.com", port: 443, uuid: "u")
        #expect(a == b)
    }

    @Test("Two configs with different IDs are not equal")
    func inequality() {
        let a = ServerConfig(id: "1", name: "S", address: "a.com")
        let b = ServerConfig(id: "2", name: "S", address: "a.com")
        #expect(a != b)
    }
}
