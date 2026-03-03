import Testing
import Foundation
@testable import XrayGUICore

@Suite("Tunnel Tests")
struct TunnelTests {

    // MARK: - Static Constants

    @Test("primaryId is the string 'primary'")
    func primaryId() {
        #expect(Tunnel.primaryId == "primary")
    }

    // MARK: - Init

    @Test("Init stores all provided values")
    func initValues() {
        let date = Date(timeIntervalSince1970: 500_000)
        let tunnel = Tunnel(
            id: "tunnel-1",
            serverId: "server-abc",
            serverName: "My Server",
            httpPort: 1087,
            socksPort: 1080,
            running: true,
            startedAt: date
        )

        #expect(tunnel.id == "tunnel-1")
        #expect(tunnel.serverId == "server-abc")
        #expect(tunnel.serverName == "My Server")
        #expect(tunnel.httpPort == 1087)
        #expect(tunnel.socksPort == 1080)
        #expect(tunnel.running == true)
        #expect(tunnel.startedAt == date)
    }

    @Test("Default running is false")
    func defaultRunning() {
        let tunnel = Tunnel(id: "t", serverId: "s", serverName: "N", httpPort: 1087, socksPort: 1080)
        #expect(tunnel.running == false)
    }

    @Test("Default startedAt is nil")
    func defaultStartedAt() {
        let tunnel = Tunnel(id: "t", serverId: "s", serverName: "N", httpPort: 1087, socksPort: 1080)
        #expect(tunnel.startedAt == nil)
    }

    // MARK: - Codable Round-trip

    @Test("Codable round-trip with all fields populated")
    func codableRoundTripFull() throws {
        let date = Date(timeIntervalSince1970: 1_234_567)
        let original = Tunnel(
            id: "t-1",
            serverId: "s-1",
            serverName: "Server One",
            httpPort: 2087,
            socksPort: 2080,
            running: true,
            startedAt: date
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Tunnel.self, from: data)

        #expect(decoded == original)
    }

    @Test("Codable round-trip with nil startedAt")
    func codableRoundTripNilDate() throws {
        let original = Tunnel(
            id: "t-2",
            serverId: "s-2",
            serverName: "Server Two",
            httpPort: 1087,
            socksPort: 1080,
            running: false,
            startedAt: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Tunnel.self, from: data)

        #expect(decoded.startedAt == nil)
        #expect(decoded.running == false)
    }

    // MARK: - Equatable

    @Test("Two tunnels with same values are equal")
    func equality() {
        let a = Tunnel(id: "t", serverId: "s", serverName: "N", httpPort: 1087, socksPort: 1080)
        let b = Tunnel(id: "t", serverId: "s", serverName: "N", httpPort: 1087, socksPort: 1080)
        #expect(a == b)
    }

    @Test("Tunnels with different IDs are not equal")
    func inequalityById() {
        let a = Tunnel(id: "t-1", serverId: "s", serverName: "N", httpPort: 1087, socksPort: 1080)
        let b = Tunnel(id: "t-2", serverId: "s", serverName: "N", httpPort: 1087, socksPort: 1080)
        #expect(a != b)
    }

    @Test("Tunnels with different ports are not equal")
    func inequalityByPort() {
        let a = Tunnel(id: "t", serverId: "s", serverName: "N", httpPort: 1087, socksPort: 1080)
        let b = Tunnel(id: "t", serverId: "s", serverName: "N", httpPort: 2087, socksPort: 2080)
        #expect(a != b)
    }

    @Test("Tunnels with different running state are not equal")
    func inequalityByRunning() {
        let a = Tunnel(id: "t", serverId: "s", serverName: "N", httpPort: 1087, socksPort: 1080, running: false)
        let b = Tunnel(id: "t", serverId: "s", serverName: "N", httpPort: 1087, socksPort: 1080, running: true)
        #expect(a != b)
    }

    // MARK: - Mutability

    @Test("serverName is mutable")
    func mutateServerName() {
        var tunnel = Tunnel(id: "t", serverId: "s", serverName: "Old", httpPort: 1087, socksPort: 1080)
        tunnel.serverName = "New"
        #expect(tunnel.serverName == "New")
    }

    @Test("running is mutable")
    func mutateRunning() {
        var tunnel = Tunnel(id: "t", serverId: "s", serverName: "N", httpPort: 1087, socksPort: 1080, running: false)
        tunnel.running = true
        #expect(tunnel.running == true)
    }

    @Test("startedAt is mutable")
    func mutateStartedAt() {
        var tunnel = Tunnel(id: "t", serverId: "s", serverName: "N", httpPort: 1087, socksPort: 1080)
        let now = Date()
        tunnel.startedAt = now
        #expect(tunnel.startedAt == now)
    }
}
