import Foundation

@MainActor
public protocol XrayManaging: AnyObject, Sendable {
    var isRunning: Bool { get }
    var startDates: [String: Date] { get }
    var logCallback: (@Sendable (String) -> Void)? { get set }

    func isRunning(tunnelId: String) -> Bool
    var runningCount: Int { get }

    func start(tunnelId: String, configPath: String, socksPort: Int) async throws
    func stop(tunnelId: String) async throws
    func stopAll() async
    func restart(tunnelId: String, configPath: String, socksPort: Int) async throws
    func terminateAllSync()

    func testLatency(server: ServerConfig) async -> Int

    func getXrayBinaryPath() -> String
}
