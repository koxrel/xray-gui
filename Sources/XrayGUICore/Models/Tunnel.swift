import Foundation

public struct Tunnel: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let serverId: String
    public var serverName: String
    public var httpPort: Int
    public var socksPort: Int
    public var running: Bool
    public var startedAt: Date?

    public static let primaryId = "primary"

    public init(
        id: String,
        serverId: String,
        serverName: String,
        httpPort: Int,
        socksPort: Int,
        running: Bool = false,
        startedAt: Date? = nil
    ) {
        self.id = id
        self.serverId = serverId
        self.serverName = serverName
        self.httpPort = httpPort
        self.socksPort = socksPort
        self.running = running
        self.startedAt = startedAt
    }
}
