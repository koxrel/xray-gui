import Foundation

public struct Subscription: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var url: String
    public var serverIds: [String]
    public var lastUpdated: String?
    public var autoUpdate: Bool
    public var autoUpdateIntervalHours: Int

    public init(
        id: String = UUID().uuidString,
        name: String = "",
        url: String = "",
        serverIds: [String] = [],
        lastUpdated: String? = nil,
        autoUpdate: Bool = true,
        autoUpdateIntervalHours: Int = 24
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.serverIds = serverIds
        self.lastUpdated = lastUpdated
        self.autoUpdate = autoUpdate
        self.autoUpdateIntervalHours = autoUpdateIntervalHours
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        serverIds = try container.decodeIfPresent([String].self, forKey: .serverIds) ?? []
        lastUpdated = try container.decodeIfPresent(String.self, forKey: .lastUpdated)
        autoUpdate = try container.decodeIfPresent(Bool.self, forKey: .autoUpdate) ?? true
        autoUpdateIntervalHours = try container.decodeIfPresent(Int.self, forKey: .autoUpdateIntervalHours) ?? 24
    }
}
