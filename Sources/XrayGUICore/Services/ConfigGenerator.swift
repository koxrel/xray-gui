import Foundation

public enum ConfigGenerator {
    public static func generateXrayConfig(server: ServerConfig, settings: AppSettings, httpPort: Int? = nil, socksPort: Int? = nil) -> [String: Any] {
        let listen = settings.allowLan ? "0.0.0.0" : "127.0.0.1"
        let effectiveHttpPort = max(1, min(httpPort ?? settings.httpPort, 65535))
        let effectiveSocksPort = max(1, min(socksPort ?? settings.socksPort, 65535))

        let httpInbound: [String: Any] = [
            "tag": "http-in",
            "port": effectiveHttpPort,
            "listen": listen,
            "protocol": "http",
            "sniffing": [
                "enabled": true,
                "destOverride": ["http", "tls"]
            ] as [String: Any]
        ]

        let socksInbound: [String: Any] = [
            "tag": "socks-in",
            "port": effectiveSocksPort,
            "listen": listen,
            "protocol": "socks",
            "settings": ["udp": true] as [String: Any],
            "sniffing": [
                "enabled": true,
                "destOverride": ["http", "tls"]
            ] as [String: Any]
        ]

        // VLESS user
        var user: [String: Any] = [
            "id": server.uuid,
            "encryption": server.encryption.isEmpty ? "none" : server.encryption
        ]
        if !server.flow.isEmpty {
            user["flow"] = server.flow
        }

        var proxyOutbound: [String: Any] = [
            "tag": "proxy",
            "protocol": "vless",
            "settings": [
                "vnext": [[
                    "address": server.address,
                    "port": server.port,
                    "users": [user]
                ] as [String: Any]]
            ] as [String: Any],
            "streamSettings": buildStreamSettings(server: server)
        ]

        // Mux: only when enabled and no flow (incompatible with XTLS)
        if settings.enableMux && server.flow.isEmpty {
            proxyOutbound["mux"] = [
                "enabled": true,
                "concurrency": settings.muxConcurrency
            ] as [String: Any]
        }

        let directOutbound: [String: Any] = [
            "tag": "direct",
            "protocol": "freedom",
            "settings": [:] as [String: Any]
        ]

        let blockOutbound: [String: Any] = [
            "tag": "block",
            "protocol": "blackhole",
            "settings": [
                "response": ["type": "http"]
            ] as [String: Any]
        ]

        var config: [String: Any] = [
            "inbounds": [httpInbound, socksInbound],
            "outbounds": [proxyOutbound, directOutbound, blockOutbound]
        ]

        // Log
        config["log"] = [
            "loglevel": settings.logLevel.rawValue
        ] as [String: Any]

        // Routing
        let rules = buildRoutingRules(settings: settings)
        if !rules.isEmpty {
            config["routing"] = [
                "domainStrategy": "AsIs",
                "rules": rules
            ] as [String: Any]
        }

        // DNS
        switch settings.dnsMode {
        case .plain:
            if !settings.dnsServers.isEmpty {
                config["dns"] = [
                    "servers": settings.dnsServers
                ] as [String: Any]
            }
        case .doh:
            let dohAddress = ConfigGenerator.xrayDoHAddress(settings.dohServer)
            if !dohAddress.isEmpty {
                config["dns"] = [
                    "servers": [
                        dohAddress,
                        "localhost"
                    ],
                    "queryStrategy": "UseIP"
                ] as [String: Any]
            }
        }

        return config
    }

    public static func buildStreamSettings(server: ServerConfig) -> [String: Any] {
        let network = server.network.isEmpty ? "tcp" : server.network
        let security = server.security.isEmpty ? "none" : server.security

        var stream: [String: Any] = [
            "network": network,
            "security": security
        ]

        // TLS settings
        if security == "tls" {
            var tls: [String: Any] = [:]
            if !server.sni.isEmpty { tls["serverName"] = server.sni }
            if !server.fingerprint.isEmpty { tls["fingerprint"] = server.fingerprint }
            if !server.alpn.isEmpty { tls["alpn"] = server.alpn }
            tls["allowInsecure"] = server.allowInsecure
            stream["tlsSettings"] = tls
        }

        // Reality settings
        if security == "reality" {
            var reality: [String: Any] = [:]
            if !server.sni.isEmpty { reality["serverName"] = server.sni }
            if !server.fingerprint.isEmpty { reality["fingerprint"] = server.fingerprint }
            if !server.publicKey.isEmpty { reality["publicKey"] = server.publicKey }
            if !server.shortId.isEmpty { reality["shortId"] = server.shortId }
            stream["realitySettings"] = reality
        }

        // Transport settings
        switch network {
        case "ws":
            var ws: [String: Any] = [:]
            if let path = server.wsPath, !path.isEmpty { ws["path"] = path }
            if let host = server.wsHost, !host.isEmpty {
                ws["headers"] = ["Host": host] as [String: Any]
            }
            stream["wsSettings"] = ws

        case "grpc":
            var grpc: [String: Any] = [:]
            if let name = server.grpcServiceName, !name.isEmpty { grpc["serviceName"] = name }
            if let multi = server.grpcMultiMode { grpc["multiMode"] = multi }
            stream["grpcSettings"] = grpc

        case "h2":
            var h2: [String: Any] = [:]
            if let path = server.wsPath, !path.isEmpty { h2["path"] = path }
            if let host = server.wsHost, !host.isEmpty { h2["host"] = [host] }
            stream["httpSettings"] = h2

        case "httpupgrade":
            var hu: [String: Any] = [:]
            if let path = server.wsPath, !path.isEmpty { hu["path"] = path }
            if let host = server.wsHost, !host.isEmpty { hu["host"] = host }
            stream["httpupgradeSettings"] = hu

        case "tcp":
            if server.headerType == "http" {
                stream["tcpSettings"] = [
                    "header": [
                        "type": "http",
                        "request": [
                            "version": "1.1",
                            "method": "GET",
                            "path": [server.wsPath ?? "/"],
                            "headers": [
                                "Host": [server.wsHost ?? server.address],
                                "User-Agent": [
                                    "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/53.0.2785.143 Safari/537.36",
                                    "Mozilla/5.0 (iPhone; CPU iPhone OS 10_0_2 like Mac OS X) AppleWebKit/601.1 (KHTML, like Gecko) CriOS/53.0.2785.109 Mobile/14A456 Safari/601.1.46"
                                ],
                                "Accept-Encoding": ["gzip, deflate"],
                                "Connection": ["keep-alive"],
                                "Pragma": ["no-cache"]
                            ] as [String: Any]
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            }

        default:
            break
        }

        return stream
    }

    /// Converts a user-facing `https://` DoH URL to Xray's `https+local://` format.
    /// The `+local` prefix tells Xray to resolve the DoH server via system DNS,
    /// avoiding circular resolution. Returns empty string for invalid input.
    static func xrayDoHAddress(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("https+local://") { return trimmed }
        if trimmed.hasPrefix("https://") {
            let afterScheme = trimmed.dropFirst("https://".count)
            return "https+local://\(afterScheme)"
        }
        if trimmed.hasPrefix("http://") { return "" }
        return "https+local://\(trimmed)"
    }

    public static func buildRoutingRules(settings: AppSettings) -> [[String: Any]] {
        var rules: [[String: Any]] = []

        if !settings.blockedDomains.isEmpty {
            rules.append([
                "type": "field",
                "domain": settings.blockedDomains,
                "outboundTag": "block"
            ] as [String: Any])
        }

        if !settings.directDomains.isEmpty {
            rules.append([
                "type": "field",
                "domain": settings.directDomains,
                "outboundTag": "direct"
            ] as [String: Any])
        }

        if !settings.bypassDomains.isEmpty {
            rules.append([
                "type": "field",
                "domain": settings.bypassDomains,
                "outboundTag": "direct"
            ] as [String: Any])
        }

        // Always bypass private IPs
        rules.append([
            "type": "field",
            "ip": ["geoip:private"],
            "outboundTag": "direct"
        ] as [String: Any])

        return rules
    }

    public static func writeConfig(server: ServerConfig, settings: AppSettings, httpPort: Int? = nil, socksPort: Int? = nil, to url: URL) throws {
        let config = generateXrayConfig(server: server, settings: settings, httpPort: httpPort, socksPort: socksPort)
        let jsonData = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: url, options: .atomic)
    }
}
