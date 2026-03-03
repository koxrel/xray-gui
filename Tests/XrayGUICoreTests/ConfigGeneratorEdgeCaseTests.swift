import Testing
import Foundation
@testable import XrayGUICore

/// Edge cases not covered by the primary ConfigGeneratorTests suite.
@Suite("ConfigGenerator Edge Cases")
struct ConfigGeneratorEdgeCaseTests {

    // MARK: - Helpers

    private func makeServer(
        flow: String = "",
        network: String = "tcp",
        security: String = "none"
    ) -> ServerConfig {
        ServerConfig(
            name: "Edge",
            address: "edge.example.com",
            port: 443,
            uuid: "edge-uuid",
            flow: flow,
            network: network,
            security: security
        )
    }

    private func makeSettings(
        httpPort: Int = 1087,
        socksPort: Int = 1080,
        dnsServers: [String] = ["1.1.1.1"],
        bypassDomains: [String] = [],
        directDomains: [String] = [],
        blockedDomains: [String] = [],
        enableMux: Bool = false,
        muxConcurrency: Int = 8
    ) -> AppSettings {
        AppSettings(
            httpPort: httpPort,
            socksPort: socksPort,
            dnsServers: dnsServers,
            enableMux: enableMux,
            muxConcurrency: muxConcurrency,
            bypassDomains: bypassDomains,
            directDomains: directDomains,
            blockedDomains: blockedDomains
        )
    }

    // MARK: - Port Clamping

    @Test("Port 0 is clamped to 1")
    func portClampLow() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(),
            settings: makeSettings(),
            httpPort: 0,
            socksPort: 0
        )
        let inbounds = config["inbounds"] as? [[String: Any]] ?? []
        let http = inbounds.first { ($0["tag"] as? String) == "http-in" }
        let socks = inbounds.first { ($0["tag"] as? String) == "socks-in" }
        #expect(http?["port"] as? Int == 1)
        #expect(socks?["port"] as? Int == 1)
    }

    @Test("Port above 65535 is clamped to 65535")
    func portClampHigh() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(),
            settings: makeSettings(),
            httpPort: 99999,
            socksPort: 99999
        )
        let inbounds = config["inbounds"] as? [[String: Any]] ?? []
        let http = inbounds.first { ($0["tag"] as? String) == "http-in" }
        let socks = inbounds.first { ($0["tag"] as? String) == "socks-in" }
        #expect(http?["port"] as? Int == 65535)
        #expect(socks?["port"] as? Int == 65535)
    }

    // MARK: - DNS

    @Test("Empty dnsServers omits dns key from config")
    func emptyDnsOmitsKey() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(),
            settings: makeSettings(dnsServers: [])
        )
        #expect(config["dns"] == nil)
    }

    // MARK: - Routing Rules

    @Test("Direct domains produce direct routing rule")
    func directDomainsRule() {
        let rules = ConfigGenerator.buildRoutingRules(
            settings: makeSettings(directDomains: ["direct.example.com"])
        )
        let directRule = rules.first { ($0["outboundTag"] as? String) == "direct" && ($0["domain"] as? [String]) != nil }
        let domains = directRule?["domain"] as? [String]
        #expect(domains?.contains("direct.example.com") == true)
    }

    @Test("Empty blocked, direct, bypass still has exactly one rule: private IP bypass")
    func onlyPrivateIpRuleWhenEmpty() {
        let rules = ConfigGenerator.buildRoutingRules(
            settings: makeSettings(bypassDomains: [], directDomains: [], blockedDomains: [])
        )
        #expect(rules.count == 1)
        let ipRule = rules.first { ($0["ip"] as? [String]) != nil }
        #expect(ipRule != nil)
    }

    @Test("All three domain lists produce rules in correct order: blocked, direct, bypass, private IP")
    func ruleOrder() {
        let rules = ConfigGenerator.buildRoutingRules(
            settings: makeSettings(
                bypassDomains: ["bypass.com"],
                directDomains: ["direct.com"],
                blockedDomains: ["block.com"]
            )
        )
        // Order: blocked -> direct (directDomains) -> bypass (bypassDomains) -> private IP
        #expect(rules.count == 4)
        #expect(rules[0]["outboundTag"] as? String == "block")
        #expect(rules[1]["outboundTag"] as? String == "direct")
        #expect(rules[2]["outboundTag"] as? String == "direct")
        #expect(rules[3]["outboundTag"] as? String == "direct")
        let ipRule = rules[3]["ip"] as? [String]
        #expect(ipRule?.contains("geoip:private") == true)
    }

    // MARK: - VLESS User Flow

    @Test("VLESS user includes flow when non-empty")
    func vlessUserWithFlow() {
        var server = makeServer(flow: "xtls-rprx-vision")
        server.uuid = "my-uuid"
        let config = ConfigGenerator.generateXrayConfig(server: server, settings: makeSettings())
        let outbounds = config["outbounds"] as? [[String: Any]] ?? []
        let proxy = outbounds.first { ($0["tag"] as? String) == "proxy" }
        let settings = proxy?["settings"] as? [String: Any]
        let vnext = settings?["vnext"] as? [[String: Any]]
        let users = vnext?.first?["users"] as? [[String: Any]]
        let user = users?.first
        #expect(user?["flow"] as? String == "xtls-rprx-vision")
    }

    @Test("VLESS user omits flow key when empty")
    func vlessUserWithoutFlow() {
        let server = makeServer(flow: "")
        let config = ConfigGenerator.generateXrayConfig(server: server, settings: makeSettings())
        let outbounds = config["outbounds"] as? [[String: Any]] ?? []
        let proxy = outbounds.first { ($0["tag"] as? String) == "proxy" }
        let proxySettings = proxy?["settings"] as? [String: Any]
        let vnext = proxySettings?["vnext"] as? [[String: Any]]
        let users = vnext?.first?["users"] as? [[String: Any]]
        let user = users?.first
        #expect(user?["flow"] == nil)
    }

    // MARK: - Mux Concurrency

    @Test("Mux concurrency value propagates from settings")
    func muxConcurrency() {
        let config = ConfigGenerator.generateXrayConfig(
            server: makeServer(flow: ""),
            settings: makeSettings(enableMux: true, muxConcurrency: 16)
        )
        let outbounds = config["outbounds"] as? [[String: Any]] ?? []
        let proxy = outbounds.first { ($0["tag"] as? String) == "proxy" }
        let mux = proxy?["mux"] as? [String: Any]
        #expect(mux?["concurrency"] as? Int == 16)
    }

    // MARK: - Stream Settings: Default Fallbacks

    @Test("Empty network defaults to tcp in stream settings")
    func emptyNetworkDefaultsTcp() {
        var server = makeServer()
        server.network = ""
        let stream = ConfigGenerator.buildStreamSettings(server: server)
        #expect(stream["network"] as? String == "tcp")
    }

    @Test("Empty security defaults to none in stream settings")
    func emptySecurityDefaultsNone() {
        var server = makeServer()
        server.security = ""
        let stream = ConfigGenerator.buildStreamSettings(server: server)
        #expect(stream["security"] as? String == "none")
    }

    // MARK: - Stream Settings: TLS ALPN

    @Test("TLS stream settings include ALPN array when set")
    func tlsWithAlpn() {
        var server = makeServer(security: "tls")
        server.alpn = ["h2", "http/1.1"]
        let stream = ConfigGenerator.buildStreamSettings(server: server)
        let tls = stream["tlsSettings"] as? [String: Any]
        let alpn = tls?["alpn"] as? [String]
        #expect(alpn == ["h2", "http/1.1"])
    }

    @Test("TLS stream settings with empty ALPN omits alpn key")
    func tlsWithEmptyAlpn() {
        var server = makeServer(security: "tls")
        server.alpn = []
        let stream = ConfigGenerator.buildStreamSettings(server: server)
        let tls = stream["tlsSettings"] as? [String: Any]
        #expect(tls?["alpn"] == nil)
    }

    @Test("TLS allowInsecure is reflected in tlsSettings")
    func tlsAllowInsecure() {
        // The model always forces allowInsecure=false from parsed URLs,
        // but the ConfigGenerator writes whatever value the ServerConfig carries.
        var server = makeServer(security: "tls")
        server.allowInsecure = false
        let stream = ConfigGenerator.buildStreamSettings(server: server)
        let tls = stream["tlsSettings"] as? [String: Any]
        #expect(tls?["allowInsecure"] as? Bool == false)
    }

    // MARK: - Stream Settings: Reality with Empty Optional Fields

    @Test("Reality stream omits sni key when empty")
    func realityEmptySni() {
        var server = makeServer(security: "reality")
        server.sni = ""
        let stream = ConfigGenerator.buildStreamSettings(server: server)
        let reality = stream["realitySettings"] as? [String: Any]
        #expect(reality?["serverName"] == nil)
    }

    @Test("Reality stream omits fingerprint key when empty")
    func realityEmptyFingerprint() {
        var server = makeServer(security: "reality")
        server.fingerprint = ""
        let stream = ConfigGenerator.buildStreamSettings(server: server)
        let reality = stream["realitySettings"] as? [String: Any]
        #expect(reality?["fingerprint"] == nil)
    }

    // MARK: - Stream Settings: gRPC

    @Test("gRPC stream settings include serviceName")
    func grpcServiceName() {
        var server = makeServer(network: "grpc")
        server.grpcServiceName = "my-service"
        let stream = ConfigGenerator.buildStreamSettings(server: server)
        let grpc = stream["grpcSettings"] as? [String: Any]
        #expect(grpc?["serviceName"] as? String == "my-service")
    }

    @Test("gRPC stream with multiMode=true sets multiMode key")
    func grpcMultiMode() {
        var server = makeServer(network: "grpc")
        server.grpcMultiMode = true
        let stream = ConfigGenerator.buildStreamSettings(server: server)
        let grpc = stream["grpcSettings"] as? [String: Any]
        #expect(grpc?["multiMode"] as? Bool == true)
    }

    @Test("gRPC stream with multiMode=false sets multiMode key to false")
    func grpcMultiModeExplicitFalse() {
        var server = makeServer(network: "grpc")
        server.grpcMultiMode = false
        let stream = ConfigGenerator.buildStreamSettings(server: server)
        let grpc = stream["grpcSettings"] as? [String: Any]
        #expect(grpc?["multiMode"] as? Bool == false)
    }

    // MARK: - Stream Settings: h2

    @Test("h2 network produces httpSettings with path and host")
    func h2StreamSettings() {
        var server = makeServer(network: "h2")
        server.wsPath = "/h2path"
        server.wsHost = "h2.example.com"
        let stream = ConfigGenerator.buildStreamSettings(server: server)
        let h2 = stream["httpSettings"] as? [String: Any]
        #expect(h2?["path"] as? String == "/h2path")
        let host = h2?["host"] as? [String]
        #expect(host?.first == "h2.example.com")
    }

    // MARK: - Stream Settings: httpupgrade

    @Test("httpupgrade network produces httpupgradeSettings with path and host")
    func httpupgradeStreamSettings() {
        var server = makeServer(network: "httpupgrade")
        server.wsPath = "/upgrade"
        server.wsHost = "cdn.example.com"
        let stream = ConfigGenerator.buildStreamSettings(server: server)
        let hu = stream["httpupgradeSettings"] as? [String: Any]
        #expect(hu?["path"] as? String == "/upgrade")
        #expect(hu?["host"] as? String == "cdn.example.com")
    }

    // MARK: - Stream Settings: TCP with HTTP Header

    @Test("TCP with headerType http produces tcpSettings")
    func tcpWithHttpHeader() {
        var server = makeServer(network: "tcp")
        server.headerType = "http"
        server.wsPath = "/path"
        server.wsHost = "host.example.com"
        let stream = ConfigGenerator.buildStreamSettings(server: server)
        let tcp = stream["tcpSettings"] as? [String: Any]
        let header = tcp?["header"] as? [String: Any]
        #expect(header?["type"] as? String == "http")
        let request = header?["request"] as? [String: Any]
        #expect(request?["method"] as? String == "GET")
        let path = request?["path"] as? [String]
        #expect(path?.first == "/path")
    }

    @Test("TCP without headerType http produces no tcpSettings")
    func tcpWithoutHttpHeader() {
        var server = makeServer(network: "tcp")
        server.headerType = nil
        let stream = ConfigGenerator.buildStreamSettings(server: server)
        #expect(stream["tcpSettings"] == nil)
    }

    // MARK: - writeConfig

    @Test("writeConfig writes valid parseable JSON to a temp URL")
    func writeConfigProducesValidJson() throws {
        let server = ServerConfig(name: "Write Test", address: "write.example.com", port: 443, uuid: "wuuid")
        let settings = AppSettings.default
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xray-write-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try ConfigGenerator.writeConfig(server: server, settings: settings, to: url)

        #expect(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(parsed?["inbounds"] != nil)
        #expect(parsed?["outbounds"] != nil)
        #expect(parsed?["log"] != nil)
    }

    @Test("writeConfig overwrites existing file")
    func writeConfigOverwrites() throws {
        let server = ServerConfig(name: "Overwrite Test", address: "over.example.com", port: 443, uuid: "ou")
        let settings = AppSettings.default
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xray-overwrite-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        // Write twice — second call should not throw
        try ConfigGenerator.writeConfig(server: server, settings: settings, to: url)
        try ConfigGenerator.writeConfig(server: server, settings: settings, to: url)

        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
