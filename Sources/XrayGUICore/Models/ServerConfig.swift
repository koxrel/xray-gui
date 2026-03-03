import Foundation

public struct ServerConfig: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var address: String
    public var port: Int
    public var uuid: String
    public var flow: String
    public var encryption: String
    public var network: String
    public var security: String
    public var sni: String
    public var fingerprint: String
    public var publicKey: String
    public var shortId: String
    public var alpn: [String]
    public var allowInsecure: Bool
    public var wsPath: String?
    public var wsHost: String?
    public var grpcServiceName: String?
    public var grpcMultiMode: Bool?
    public var headerType: String?
    public var subscriptionId: String?
    public var latency: Int?
    public var isActive: Bool

    public init(
        id: String = UUID().uuidString,
        name: String = "",
        address: String = "",
        port: Int = 443,
        uuid: String = "",
        flow: String = "",
        encryption: String = "none",
        network: String = "tcp",
        security: String = "none",
        sni: String = "",
        fingerprint: String = "",
        publicKey: String = "",
        shortId: String = "",
        alpn: [String] = [],
        allowInsecure: Bool = false,
        wsPath: String? = nil,
        wsHost: String? = nil,
        grpcServiceName: String? = nil,
        grpcMultiMode: Bool? = nil,
        headerType: String? = nil,
        subscriptionId: String? = nil,
        latency: Int? = nil,
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.port = port
        self.uuid = uuid
        self.flow = flow
        self.encryption = encryption
        self.network = network
        self.security = security
        self.sni = sni
        self.fingerprint = fingerprint
        self.publicKey = publicKey
        self.shortId = shortId
        self.alpn = alpn
        self.allowInsecure = allowInsecure
        self.wsPath = wsPath
        self.wsHost = wsHost
        self.grpcServiceName = grpcServiceName
        self.grpcMultiMode = grpcMultiMode
        self.headerType = headerType
        self.subscriptionId = subscriptionId
        self.latency = latency
        self.isActive = isActive
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        address = try container.decodeIfPresent(String.self, forKey: .address) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 443
        uuid = try container.decodeIfPresent(String.self, forKey: .uuid) ?? ""
        flow = try container.decodeIfPresent(String.self, forKey: .flow) ?? ""
        encryption = try container.decodeIfPresent(String.self, forKey: .encryption) ?? "none"
        network = try container.decodeIfPresent(String.self, forKey: .network) ?? "tcp"
        security = try container.decodeIfPresent(String.self, forKey: .security) ?? "none"
        sni = try container.decodeIfPresent(String.self, forKey: .sni) ?? ""
        fingerprint = try container.decodeIfPresent(String.self, forKey: .fingerprint) ?? ""
        publicKey = try container.decodeIfPresent(String.self, forKey: .publicKey) ?? ""
        shortId = try container.decodeIfPresent(String.self, forKey: .shortId) ?? ""
        alpn = try container.decodeIfPresent([String].self, forKey: .alpn) ?? []
        allowInsecure = try container.decodeIfPresent(Bool.self, forKey: .allowInsecure) ?? false
        wsPath = try container.decodeIfPresent(String.self, forKey: .wsPath)
        wsHost = try container.decodeIfPresent(String.self, forKey: .wsHost)
        grpcServiceName = try container.decodeIfPresent(String.self, forKey: .grpcServiceName)
        grpcMultiMode = try container.decodeIfPresent(Bool.self, forKey: .grpcMultiMode)
        headerType = try container.decodeIfPresent(String.self, forKey: .headerType)
        subscriptionId = try container.decodeIfPresent(String.self, forKey: .subscriptionId)
        latency = try container.decodeIfPresent(Int.self, forKey: .latency)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
    }
}
