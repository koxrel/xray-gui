import Testing
import Foundation
@testable import XrayGUICore

@Suite("ConfigGenerator Tests")
struct ConfigGeneratorTests {

    private func makeServer(
        address: String = "example.com",
        port: Int = 443,
        uuid: String = "test-uuid",
        flow: String = "",
        network: String = "tcp",
        security: String = "tls",
        sni: String = "example.com"
    ) -> ServerConfig {
        ServerConfig(
            name: "Test",
            address: address,
            port: port,
            uuid: uuid,
            flow: flow,
            network: network,
            security: security,
            sni: sni
        )
    }

    private func makeSettings(
        httpPort: Int = 1087,
        socksPort: Int = 1080,
        allowLan: Bool = false,
        logLevel: LogLevel = .warning,
        enableMux: Bool = false,
        dnsServers: [String] = ["1.1.1.1"],
        dnsMode: DNSMode = .plain,
        dohServer: String = "https://1.1.1.1/dns-query",
        bypassDomains: [String] = ["localhost"],
        directDomains: [String] = [],
        blockedDomains: [String] = []
    ) -> AppSettings {
        AppSettings(
            httpPort: httpPort,
            socksPort: socksPort,
            allowLan: allowLan,
            logLevel: logLevel,
            dnsServers: dnsServers,
            dnsMode: dnsMode,
            dohServer: dohServer,
            enableMux: enableMux,
            bypassDomains: bypassDomains,
            directDomains: directDomains,
            blockedDomains: blockedDomains
        )
    }

    // MARK: - Basic Config Structure

    @Test("Config contains required top-level keys")
    func topLevelKeys() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(),
            settings: makeSettings()
        )
        #expect(config["inbounds"] != nil)
        #expect(config["outbounds"] != nil)
        #expect(config["log"] != nil)
    }

    @Test("Config has two inbound entries (HTTP + SOCKS)")
    func inboundsCount() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(),
            settings: makeSettings()
        )
        let inbounds = config["inbounds"] as? [[String: Any]]
        #expect(inbounds?.count == 2)
    }

    @Test("Config has three outbounds (proxy, direct, block)")
    func outboundsCount() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(),
            settings: makeSettings()
        )
        let outbounds = config["outbounds"] as? [[String: Any]]
        #expect(outbounds?.count == 3)

        let tags = outbounds?.compactMap { $0["tag"] as? String }
        #expect(tags?.contains("proxy") == true)
        #expect(tags?.contains("direct") == true)
        #expect(tags?.contains("block") == true)
    }

    // MARK: - Inbound Ports

    @Test("Uses default ports from settings")
    func defaultPorts() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(),
            settings: makeSettings(httpPort: 2087, socksPort: 2080)
        )
        let inbounds = config["inbounds"] as? [[String: Any]] ?? []
        let httpInbound = inbounds.first { ($0["tag"] as? String) == "http-in" }
        let socksInbound = inbounds.first { ($0["tag"] as? String) == "socks-in" }
        #expect(httpInbound?["port"] as? Int == 2087)
        #expect(socksInbound?["port"] as? Int == 2080)
    }

    @Test("Port overrides take precedence")
    func portOverrides() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(),
            settings: makeSettings(httpPort: 1087, socksPort: 1080),
            httpPort: 3087,
            socksPort: 3080
        )
        let inbounds = config["inbounds"] as? [[String: Any]] ?? []
        let httpInbound = inbounds.first { ($0["tag"] as? String) == "http-in" }
        let socksInbound = inbounds.first { ($0["tag"] as? String) == "socks-in" }
        #expect(httpInbound?["port"] as? Int == 3087)
        #expect(socksInbound?["port"] as? Int == 3080)
    }

    // MARK: - Listen Address

    @Test("Listens on 127.0.0.1 when allowLan is false")
    func listenLocalhost() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(),
            settings: makeSettings(allowLan: false)
        )
        let inbounds = config["inbounds"] as? [[String: Any]] ?? []
        for inbound in inbounds {
            #expect(inbound["listen"] as? String == "127.0.0.1")
        }
    }

    @Test("Listens on 0.0.0.0 when allowLan is true")
    func listenAllInterfaces() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(),
            settings: makeSettings(allowLan: true)
        )
        let inbounds = config["inbounds"] as? [[String: Any]] ?? []
        for inbound in inbounds {
            #expect(inbound["listen"] as? String == "0.0.0.0")
        }
    }

    // MARK: - Mux

    @Test("Mux is included when enabled and no flow")
    func muxEnabled() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(flow: ""),
            settings: makeSettings(enableMux: true)
        )
        let outbounds = config["outbounds"] as? [[String: Any]] ?? []
        let proxy = outbounds.first { ($0["tag"] as? String) == "proxy" }
        let mux = proxy?["mux"] as? [String: Any]
        #expect(mux?["enabled"] as? Bool == true)
    }

    @Test("Mux is excluded when flow is set (XTLS incompatibility)")
    func muxExcludedWithFlow() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(flow: "xtls-rprx-vision"),
            settings: makeSettings(enableMux: true)
        )
        let outbounds = config["outbounds"] as? [[String: Any]] ?? []
        let proxy = outbounds.first { ($0["tag"] as? String) == "proxy" }
        #expect(proxy?["mux"] == nil)
    }

    // MARK: - Routing Rules

    @Test("Blocked domains produce block routing rule")
    func blockedDomainsRule() {
        let rules = ConfigGenerator.buildRoutingRules(
            settings: makeSettings(blockedDomains: ["ads.example.com"])
        )
        let blockRule = rules.first { ($0["outboundTag"] as? String) == "block" }
        let domains = blockRule?["domain"] as? [String]
        #expect(domains?.contains("ads.example.com") == true)
    }

    @Test("Always includes private IP bypass rule")
    func privateIpBypass() {
        let rules = ConfigGenerator.buildRoutingRules(
            settings: makeSettings(bypassDomains: [], directDomains: [], blockedDomains: [])
        )
        let ipRule = rules.first { ($0["ip"] as? [String]) != nil }
        let ips = ipRule?["ip"] as? [String]
        #expect(ips?.contains("geoip:private") == true)
        #expect(ipRule?["outboundTag"] as? String == "direct")
    }

    // MARK: - Log Level

    @Test("Config log level matches settings")
    func logLevel() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(),
            settings: makeSettings(logLevel: .debug)
        )
        let log = config["log"] as? [String: Any]
        #expect(log?["loglevel"] as? String == "debug")
    }

    // MARK: - DNS

    @Test("DNS servers are included when non-empty")
    func dnsServers() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(),
            settings: makeSettings(dnsServers: ["8.8.8.8", "1.1.1.1"])
        )
        let dns = config["dns"] as? [String: Any]
        let servers = dns?["servers"] as? [String]
        #expect(servers == ["8.8.8.8", "1.1.1.1"])
    }

    @Test("DoH mode generates Xray DoH config with queryStrategy")
    func dohDnsConfig() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(),
            settings: makeSettings(dnsMode: .doh, dohServer: "https://1.1.1.1/dns-query")
        )
        let dns = config["dns"] as? [String: Any]
        #expect(dns != nil)
        #expect(dns?["queryStrategy"] as? String == "UseIP")
        let servers = dns?["servers"] as? [String]
        #expect(servers?.count == 2)
        #expect(servers?.first == "https+local://1.1.1.1/dns-query")
        #expect(servers?.last == "localhost")
    }

    @Test("DoH mode with empty URL produces no dns block")
    func dohEmptyUrl() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(),
            settings: makeSettings(dnsMode: .doh, dohServer: "")
        )
        let dns = config["dns"] as? [String: Any]
        #expect(dns == nil)
    }

    @Test("xrayDoHAddress converts https:// to https+local://")
    func xrayDoHAddressHttps() {
        let result = ConfigGenerator.xrayDoHAddress("https://8.8.8.8/dns-query")
        #expect(result == "https+local://8.8.8.8/dns-query")
    }

    @Test("xrayDoHAddress passes through already-prefixed URLs")
    func xrayDoHAddressIdempotent() {
        let result = ConfigGenerator.xrayDoHAddress("https+local://1.1.1.1/dns-query")
        #expect(result == "https+local://1.1.1.1/dns-query")
    }

    @Test("xrayDoHAddress returns empty for empty string")
    func xrayDoHAddressEmpty() {
        let result = ConfigGenerator.xrayDoHAddress("")
        #expect(result == "")
    }

    @Test("xrayDoHAddress returns empty for http:// URLs")
    func xrayDoHAddressHttp() {
        let result = ConfigGenerator.xrayDoHAddress("http://1.1.1.1/dns-query")
        #expect(result == "")
    }

    @Test("xrayDoHAddress handles bare hostname")
    func xrayDoHAddressBareHost() {
        let result = ConfigGenerator.xrayDoHAddress("1.1.1.1/dns-query")
        #expect(result == "https+local://1.1.1.1/dns-query")
    }

    // MARK: - Stream Settings

    @Test("TLS stream settings include SNI and fingerprint")
    func tlsStreamSettings() {
        let server = makeServer(security: "tls", sni: "sni.example.com")
        let stream = ConfigGenerator.buildStreamSettings(server: server)
        let tls = stream["tlsSettings"] as? [String: Any]
        #expect(tls?["serverName"] as? String == "sni.example.com")
    }

    @Test("Reality stream settings include publicKey and shortId")
    func realityStreamSettings() {
        var server = makeServer(security: "reality")
        server.publicKey = "realpk"
        server.shortId = "realshortid"
        let stream = ConfigGenerator.buildStreamSettings(server: server)
        let reality = stream["realitySettings"] as? [String: Any]
        #expect(reality?["publicKey"] as? String == "realpk")
        #expect(reality?["shortId"] as? String == "realshortid")
    }

    @Test("WebSocket stream settings include path and host header")
    func wsStreamSettings() {
        var server = makeServer(network: "ws")
        server.wsPath = "/mypath"
        server.wsHost = "cdn.example.com"
        let stream = ConfigGenerator.buildStreamSettings(server: server)
        let ws = stream["wsSettings"] as? [String: Any]
        #expect(ws?["path"] as? String == "/mypath")
        let headers = ws?["headers"] as? [String: Any]
        #expect(headers?["Host"] as? String == "cdn.example.com")
    }

    // MARK: - Statistics API

    @Test("Stats API config is omitted by default")
    func statsApiOmittedByDefault() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(),
            settings: makeSettings()
        )

        #expect(config["api"] == nil)
        #expect(config["stats"] == nil)
        #expect(config["policy"] == nil)
    }

    @Test("Stats API config is included when stats API port is provided")
    func statsApiIncludedWhenPortProvided() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(),
            settings: makeSettings(),
            statsAPIPort: 10085
        )

        let api = config["api"] as? [String: Any]
        #expect(api?["tag"] as? String == "api")
        #expect(api?["listen"] as? String == "127.0.0.1:10085")
        let services = api?["services"] as? [String]
        #expect(services?.contains("StatsService") == true)

        let stats = config["stats"] as? [String: Any]
        #expect(stats?.isEmpty == true)

        let policy = config["policy"] as? [String: Any]
        let system = policy?["system"] as? [String: Any]
        #expect(system?["statsInboundUplink"] as? Bool == true)
        #expect(system?["statsInboundDownlink"] as? Bool == true)
    }
}
