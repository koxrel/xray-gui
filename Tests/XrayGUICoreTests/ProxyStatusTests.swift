import Testing
import Foundation
@testable import XrayGUICore

@Suite("ProxyStatus Tests")
struct ProxyStatusTests {

    // MARK: - Default Init

    @Test("Default init: running is false")
    func defaultRunning() {
        let status = ProxyStatus()
        #expect(status.running == false)
    }

    @Test("Default init: activeServer is nil")
    func defaultActiveServer() {
        let status = ProxyStatus()
        #expect(status.activeServer == nil)
    }

    @Test("Default init: proxyMode is manual")
    func defaultProxyMode() {
        let status = ProxyStatus()
        #expect(status.proxyMode == .manual)
    }

    @Test("Default init: httpPort is 1087")
    func defaultHttpPort() {
        let status = ProxyStatus()
        #expect(status.httpPort == 1087)
    }

    @Test("Default init: socksPort is 1080")
    func defaultSocksPort() {
        let status = ProxyStatus()
        #expect(status.socksPort == 1080)
    }

    @Test("Default init: startedAt is nil")
    func defaultStartedAt() {
        let status = ProxyStatus()
        #expect(status.startedAt == nil)
    }

    // MARK: - Custom Init

    @Test("Custom init preserves all provided values")
    func customInit() {
        let server = ServerConfig(id: "s1", name: "Test", address: "1.2.3.4", port: 443, uuid: "uuid")
        let date = Date(timeIntervalSince1970: 1_000_000)
        let status = ProxyStatus(
            running: true,
            activeServer: server,
            proxyMode: .global,
            httpPort: 2087,
            socksPort: 2080,
            startedAt: date
        )

        #expect(status.running == true)
        #expect(status.activeServer == server)
        #expect(status.proxyMode == .global)
        #expect(status.httpPort == 2087)
        #expect(status.socksPort == 2080)
        #expect(status.startedAt == date)
    }

    // MARK: - Equatable

    @Test("Two default ProxyStatus instances are equal")
    func equalDefaults() {
        #expect(ProxyStatus() == ProxyStatus())
    }

    @Test("Differs when running changes")
    func differsOnRunning() {
        let a = ProxyStatus(running: false)
        let b = ProxyStatus(running: true)
        #expect(a != b)
    }

    @Test("Differs when proxyMode changes")
    func differsOnProxyMode() {
        let a = ProxyStatus(proxyMode: .global)
        let b = ProxyStatus(proxyMode: .pac)
        #expect(a != b)
    }

    @Test("Differs when httpPort changes")
    func differsOnHttpPort() {
        let a = ProxyStatus(httpPort: 1087)
        let b = ProxyStatus(httpPort: 8080)
        #expect(a != b)
    }

    @Test("Differs when socksPort changes")
    func differsOnSocksPort() {
        let a = ProxyStatus(socksPort: 1080)
        let b = ProxyStatus(socksPort: 9090)
        #expect(a != b)
    }

    @Test("Differs when activeServer changes")
    func differsOnActiveServer() {
        let server = ServerConfig(id: "s1", name: "S", address: "a.com", port: 443, uuid: "u")
        let a = ProxyStatus(activeServer: nil)
        let b = ProxyStatus(activeServer: server)
        #expect(a != b)
    }

    @Test("Differs when startedAt changes")
    func differsOnStartedAt() {
        let a = ProxyStatus(startedAt: nil)
        let b = ProxyStatus(startedAt: Date())
        #expect(a != b)
    }

    @Test("Mutation: running can be toggled")
    func mutateRunning() {
        var status = ProxyStatus()
        status.running = true
        #expect(status.running == true)
        status.running = false
        #expect(status.running == false)
    }
}
