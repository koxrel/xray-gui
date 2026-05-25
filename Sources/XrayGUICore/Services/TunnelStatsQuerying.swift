import Foundation

public protocol TunnelStatsQuerying: Sendable {
    func queryStats(apiPort: Int) async throws -> TunnelTrafficStats
}
