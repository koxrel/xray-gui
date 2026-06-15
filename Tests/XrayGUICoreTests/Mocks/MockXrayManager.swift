import Foundation
@testable import XrayGUICore

/// A test double for `XrayManaging` that records all call arguments,
/// tracks running state in memory, and supports configurable error injection.
@MainActor
final class MockXrayManager: XrayManaging {

    // MARK: - Call recording

    var startCalls: [(tunnelId: String, configPath: String, socksPort: Int)] = []
    var stopCalls: [String] = []
    var restartCalls: [(tunnelId: String, configPath: String, socksPort: Int)] = []
    var stopAllCallCount: Int = 0
    var terminateAllSyncCallCount: Int = 0
    var testLatencyCalls: [ServerConfig] = []

    // MARK: - Configurable behavior

    var shouldThrowOnStart: Bool = false
    var shouldThrowOnStop: Bool = false
    var stubbedLatency: Int = 50

    // MARK: - State tracking

    /// Tunnel IDs that are currently "running".
    var runningTunnelIds: Set<String> = []

    /// Backing storage for start dates, keyed by tunnel ID.
    var _startDates: [String: Date] = [:]

    // MARK: - XrayManaging conformance

    var logCallback: (@Sendable (String) -> Void)?

    var isRunning: Bool {
        !runningTunnelIds.isEmpty
    }

    var startDates: [String: Date] {
        _startDates
    }

    func isRunning(tunnelId: String) -> Bool {
        runningTunnelIds.contains(tunnelId)
    }

    var runningCount: Int {
        runningTunnelIds.count
    }

    func start(tunnelId: String, configPath: String, socksPort: Int) async throws {
        startCalls.append((tunnelId: tunnelId, configPath: configPath, socksPort: socksPort))
        if shouldThrowOnStart {
            throw XrayError.startFailed("Mock configured to throw on start")
        }
        runningTunnelIds.insert(tunnelId)
        _startDates[tunnelId] = Date()
    }

    func stop(tunnelId: String) async throws {
        stopCalls.append(tunnelId)
        if shouldThrowOnStop {
            throw XrayError.startFailed("Mock configured to throw on stop")
        }
        runningTunnelIds.remove(tunnelId)
        _startDates.removeValue(forKey: tunnelId)
    }

    func stopAll() async {
        stopAllCallCount += 1
        runningTunnelIds.removeAll()
        _startDates.removeAll()
    }

    func restart(tunnelId: String, configPath: String, socksPort: Int) async throws {
        restartCalls.append((tunnelId: tunnelId, configPath: configPath, socksPort: socksPort))
        runningTunnelIds.remove(tunnelId)
        _startDates.removeValue(forKey: tunnelId)
        if shouldThrowOnStart {
            throw XrayError.startFailed("Mock configured to throw on restart")
        }
        runningTunnelIds.insert(tunnelId)
        _startDates[tunnelId] = Date()
    }

    func terminateAllSync() {
        terminateAllSyncCallCount += 1
        runningTunnelIds.removeAll()
        _startDates.removeAll()
    }

    func testLatency(server: ServerConfig) async -> Int {
        testLatencyCalls.append(server)
        return stubbedLatency
    }

    func getXrayBinaryPath() -> String {
        "/mock/xray"
    }
}
