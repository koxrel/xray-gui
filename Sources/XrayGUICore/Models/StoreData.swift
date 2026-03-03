import Foundation

public struct StoreData: Codable {
    public var servers: [ServerConfig]
    public var subscriptions: [Subscription]
    public var settings: AppSettings
    public var tunnels: [Tunnel]

    public init(
        servers: [ServerConfig] = [],
        subscriptions: [Subscription] = [],
        settings: AppSettings = .default,
        tunnels: [Tunnel] = []
    ) {
        self.servers = servers
        self.subscriptions = subscriptions
        self.settings = settings
        self.tunnels = tunnels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        servers = try container.decodeIfPresent([ServerConfig].self, forKey: .servers) ?? []
        subscriptions = try container.decodeIfPresent([Subscription].self, forKey: .subscriptions) ?? []
        settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? .default
        tunnels = try container.decodeIfPresent([Tunnel].self, forKey: .tunnels) ?? []
    }
}
