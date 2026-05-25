import Foundation

public struct TunnelTrafficStats: Equatable, Sendable {
    public var uplinkBytes: UInt64
    public var downlinkBytes: UInt64

    public init(uplinkBytes: UInt64, downlinkBytes: UInt64) {
        self.uplinkBytes = uplinkBytes
        self.downlinkBytes = downlinkBytes
    }
}

public struct TunnelStatisticsSnapshot: Identifiable, Equatable, Sendable {
    public let id: String
    public let serverName: String
    public let httpPort: Int
    public let socksPort: Int
    public let startedAt: Date?
    public let isPrimary: Bool
    public let isAvailable: Bool
    public let lastUpdated: Date?
    public let uplinkBytes: UInt64
    public let downlinkBytes: UInt64
    public let uploadRateBytesPerSecond: Double
    public let downloadRateBytesPerSecond: Double

    public init(
        id: String,
        serverName: String,
        httpPort: Int,
        socksPort: Int,
        startedAt: Date?,
        isPrimary: Bool,
        isAvailable: Bool,
        lastUpdated: Date?,
        uplinkBytes: UInt64,
        downlinkBytes: UInt64,
        uploadRateBytesPerSecond: Double,
        downloadRateBytesPerSecond: Double
    ) {
        self.id = id
        self.serverName = serverName
        self.httpPort = httpPort
        self.socksPort = socksPort
        self.startedAt = startedAt
        self.isPrimary = isPrimary
        self.isAvailable = isAvailable
        self.lastUpdated = lastUpdated
        self.uplinkBytes = uplinkBytes
        self.downlinkBytes = downlinkBytes
        self.uploadRateBytesPerSecond = uploadRateBytesPerSecond
        self.downloadRateBytesPerSecond = downloadRateBytesPerSecond
    }
}

public struct TunnelStatisticsSummary: Equatable, Sendable {
    public let activeTunnelCount: Int
    public let totalUplinkBytes: UInt64
    public let totalDownlinkBytes: UInt64
    public let uploadRateBytesPerSecond: Double
    public let downloadRateBytesPerSecond: Double

    public init(
        activeTunnelCount: Int,
        totalUplinkBytes: UInt64,
        totalDownlinkBytes: UInt64,
        uploadRateBytesPerSecond: Double,
        downloadRateBytesPerSecond: Double
    ) {
        self.activeTunnelCount = activeTunnelCount
        self.totalUplinkBytes = totalUplinkBytes
        self.totalDownlinkBytes = totalDownlinkBytes
        self.uploadRateBytesPerSecond = uploadRateBytesPerSecond
        self.downloadRateBytesPerSecond = downloadRateBytesPerSecond
    }

    public init(snapshots: [TunnelStatisticsSnapshot]) {
        activeTunnelCount = snapshots.count
        totalUplinkBytes = snapshots.reduce(0) { $0 + $1.uplinkBytes }
        totalDownlinkBytes = snapshots.reduce(0) { $0 + $1.downlinkBytes }
        uploadRateBytesPerSecond = snapshots.reduce(0) { $0 + $1.uploadRateBytesPerSecond }
        downloadRateBytesPerSecond = snapshots.reduce(0) { $0 + $1.downloadRateBytesPerSecond }
    }
}
