import Foundation

public struct ProxyStatus: Equatable, Sendable {
    public var running: Bool
    public var activeServer: ServerConfig?
    public var proxyMode: ProxyMode
    public var httpPort: Int
    public var socksPort: Int
    public var startedAt: Date?

    public init(
        running: Bool = false,
        activeServer: ServerConfig? = nil,
        proxyMode: ProxyMode = .manual,
        httpPort: Int = 1087,
        socksPort: Int = 1080,
        startedAt: Date? = nil
    ) {
        self.running = running
        self.activeServer = activeServer
        self.proxyMode = proxyMode
        self.httpPort = httpPort
        self.socksPort = socksPort
        self.startedAt = startedAt
    }
}
