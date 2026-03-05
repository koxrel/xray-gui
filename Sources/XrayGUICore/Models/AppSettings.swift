import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var httpPort: Int
    public var socksPort: Int
    public var allowLan: Bool
    public var proxyMode: ProxyMode
    public var pacUrl: String
    public var autoStart: Bool
    public var logLevel: LogLevel
    public var dnsServers: [String]
    public var dnsMode: DNSMode
    public var dohServer: String
    public var enableMux: Bool
    public var muxConcurrency: Int
    public var bypassDomains: [String]
    public var directDomains: [String]
    public var blockedDomains: [String]
    public var activeServerId: String?
    public var theme: AppTheme

    public func needsProxyRestart(comparedTo other: AppSettings) -> Bool {
        httpPort != other.httpPort || socksPort != other.socksPort || allowLan != other.allowLan
            || logLevel != other.logLevel || enableMux != other.enableMux
            || muxConcurrency != other.muxConcurrency || dnsServers != other.dnsServers
            || dnsMode != other.dnsMode || dohServer != other.dohServer
            || bypassDomains != other.bypassDomains || directDomains != other.directDomains
            || blockedDomains != other.blockedDomains
    }

    public init(
        httpPort: Int = 1087,
        socksPort: Int = 1080,
        allowLan: Bool = false,
        proxyMode: ProxyMode = .global,
        pacUrl: String = "",
        autoStart: Bool = false,
        logLevel: LogLevel = .warning,
        dnsServers: [String] = ["1.1.1.1", "8.8.8.8"],
        dnsMode: DNSMode = .plain,
        dohServer: String = "https://1.1.1.1/dns-query",
        enableMux: Bool = false,
        muxConcurrency: Int = 8,
        bypassDomains: [String] = ["localhost", "127.0.0.1", "*.local"],
        directDomains: [String] = [],
        blockedDomains: [String] = ["geosite:category-ads-all"],
        activeServerId: String? = nil,
        theme: AppTheme = .system
    ) {
        self.httpPort = httpPort
        self.socksPort = socksPort
        self.allowLan = allowLan
        self.proxyMode = proxyMode
        self.pacUrl = pacUrl
        self.autoStart = autoStart
        self.logLevel = logLevel
        self.dnsServers = dnsServers
        self.dnsMode = dnsMode
        self.dohServer = dohServer
        self.enableMux = enableMux
        self.muxConcurrency = muxConcurrency
        self.bypassDomains = bypassDomains
        self.directDomains = directDomains
        self.blockedDomains = blockedDomains
        self.activeServerId = activeServerId
        self.theme = theme
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings.default
        httpPort = try container.decodeIfPresent(Int.self, forKey: .httpPort) ?? defaults.httpPort
        socksPort = try container.decodeIfPresent(Int.self, forKey: .socksPort) ?? defaults.socksPort
        allowLan = try container.decodeIfPresent(Bool.self, forKey: .allowLan) ?? defaults.allowLan
        proxyMode = (try? container.decodeIfPresent(ProxyMode.self, forKey: .proxyMode)) ?? defaults.proxyMode
        pacUrl = try container.decodeIfPresent(String.self, forKey: .pacUrl) ?? defaults.pacUrl
        autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? defaults.autoStart
        logLevel = (try? container.decodeIfPresent(LogLevel.self, forKey: .logLevel)) ?? defaults.logLevel
        dnsServers = try container.decodeIfPresent([String].self, forKey: .dnsServers) ?? defaults.dnsServers
        dnsMode = (try? container.decodeIfPresent(DNSMode.self, forKey: .dnsMode)) ?? defaults.dnsMode
        dohServer = try container.decodeIfPresent(String.self, forKey: .dohServer) ?? defaults.dohServer
        enableMux = try container.decodeIfPresent(Bool.self, forKey: .enableMux) ?? defaults.enableMux
        muxConcurrency = try container.decodeIfPresent(Int.self, forKey: .muxConcurrency) ?? defaults.muxConcurrency
        bypassDomains = try container.decodeIfPresent([String].self, forKey: .bypassDomains) ?? defaults.bypassDomains
        directDomains = try container.decodeIfPresent([String].self, forKey: .directDomains) ?? defaults.directDomains
        blockedDomains = try container.decodeIfPresent([String].self, forKey: .blockedDomains) ?? defaults.blockedDomains
        activeServerId = try container.decodeIfPresent(String.self, forKey: .activeServerId)
        theme = (try? container.decodeIfPresent(AppTheme.self, forKey: .theme)) ?? defaults.theme
    }

    public static let `default` = AppSettings(
        httpPort: 1087,
        socksPort: 1080,
        allowLan: false,
        proxyMode: .global,
        pacUrl: "",
        autoStart: false,
        logLevel: .warning,
        dnsServers: ["1.1.1.1", "8.8.8.8"],
        dnsMode: .plain,
        dohServer: "https://1.1.1.1/dns-query",
        enableMux: false,
        muxConcurrency: 8,
        bypassDomains: ["localhost", "127.0.0.1", "*.local"],
        directDomains: [],
        blockedDomains: ["geosite:category-ads-all"],
        activeServerId: nil,
        theme: .system
    )
}

public enum ProxyMode: String, Codable, CaseIterable, Sendable {
    case global
    case pac
    case manual

    public var displayName: String {
        switch self {
        case .global: return "Global"
        case .pac: return "PAC"
        case .manual: return "Manual"
        }
    }
}

public enum LogLevel: String, Codable, CaseIterable, Sendable {
    case debug
    case info
    case warning
    case error
    case none
}

public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark
}

public enum DNSMode: String, Codable, CaseIterable, Sendable {
    case plain
    case doh

    public var displayName: String {
        switch self {
        case .plain: return "Plain DNS"
        case .doh: return "DNS over HTTPS"
        }
    }
}

public enum DoHPreset: String, CaseIterable, Identifiable, Sendable {
    case cloudflare
    case google
    case quad9
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cloudflare: return "Cloudflare (1.1.1.1)"
        case .google: return "Google (8.8.8.8)"
        case .quad9: return "Quad9 (9.9.9.9)"
        case .custom: return "Custom"
        }
    }

    public var url: String {
        switch self {
        case .cloudflare: return "https://1.1.1.1/dns-query"
        case .google: return "https://8.8.8.8/dns-query"
        case .quad9: return "https://9.9.9.9/dns-query"
        case .custom: return ""
        }
    }

    public static func from(url: String) -> DoHPreset {
        let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        for preset in allCases where preset != .custom {
            if preset.url == normalized { return preset }
        }
        return .custom
    }
}
