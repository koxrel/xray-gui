import Foundation
@testable import XrayGUICore

@MainActor
final class MockTunnelStatsClient: TunnelStatsQuerying {
    var queryCalls: [Int] = []
    var stubbedByPort: [Int: TunnelTrafficStats] = [:]
    var errorsByPort: [Int: Error] = [:]

    func queryStats(apiPort: Int) async throws -> TunnelTrafficStats {
        queryCalls.append(apiPort)
        if let error = errorsByPort[apiPort] {
            throw error
        }
        return stubbedByPort[apiPort] ?? TunnelTrafficStats(uplinkBytes: 0, downlinkBytes: 0)
    }
}
