import Testing
import Foundation
@testable import XrayGUICore

/// Live, end-to-end coverage of the statistics pipeline using the REAL
/// XrayManager + XrayStatsClient against a REAL spawned xray process.
///
/// This reproduces the runtime scenario that broke in the app: querying stats
/// from a process that also owns the long-lived xray child, while inbound
/// counters are still zero. With zero traffic, xray's protobuf-JSON stats omit
/// the `value` field, which previously failed the whole parse and surfaced as
/// "Stats unavailable". The test runs on throwaway ports so it never collides
/// with a running app instance, and skips cleanly when no xray binary exists.
@Suite("Stats Live Integration", .serialized)
struct StatsLiveIntegrationTests {

    @MainActor
    @Test("real xray + real stats client returns available stats while idle")
    func liveStatsRoundTrip() async throws {
        let xray = XrayManager()
        let binaryPath = xray.getXrayBinaryPath()

        guard FileManager.default.fileExists(atPath: binaryPath) else {
            print("SKIP: xray binary not found at \(binaryPath)")
            return
        }

        let httpPort = 18881
        let socksPort = 18882
        let apiPort = 10099

        let server = ServerConfig(
            id: "live", name: "Live", address: "example.com", port: 443,
            uuid: "00000000-0000-0000-0000-000000000000", flow: "", encryption: "none",
            network: "tcp", security: "none", sni: "", fingerprint: "",
            publicKey: "", shortId: "", alpn: [], allowInsecure: false,
            subscriptionId: nil, isActive: true
        )

        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xray-live-test-\(apiPort).json")
        try ConfigGenerator.writeConfig(
            server: server, settings: .default,
            httpPort: httpPort, socksPort: socksPort, statsAPIPort: apiPort,
            to: configURL
        )

        let tunnelId = "live-test"
        try await xray.start(tunnelId: tunnelId, configPath: configURL.path, socksPort: socksPort)
        defer { Task { try? await xray.stop(tunnelId: tunnelId) } }

        // Idle inbounds: counters are zero, so xray omits their `value` fields.
        // The query must still succeed (regression for the omitted-value parse bug).
        let client = XrayStatsClient(binaryPath: binaryPath)
        let stats = try await client.queryStats(apiPort: apiPort)
        #expect(stats.uplinkBytes >= 0)
        #expect(stats.downlinkBytes >= 0)
    }
}
