import Testing
import Foundation
@testable import XrayGUICore

/// Minimal reference-type container for capturing mutable state inside `@Sendable` closures in tests.
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

// MARK: - MockXrayManager Tests

@Suite("MockXrayManager Tests")
@MainActor
struct MockXrayManagerTests {

    // MARK: Call tracking — start

    @Test("start records tunnelId, configPath, and socksPort")
    func startRecordsArguments() async throws {
        let mock = MockXrayManager()
        try await mock.start(tunnelId: "t1", configPath: "/tmp/config.json", socksPort: 1080)
        #expect(mock.startCalls.count == 1)
        #expect(mock.startCalls[0].tunnelId == "t1")
        #expect(mock.startCalls[0].configPath == "/tmp/config.json")
        #expect(mock.startCalls[0].socksPort == 1080)
    }

    @Test("start marks tunnel as running and records startDate")
    func startSetsRunningState() async throws {
        let mock = MockXrayManager()
        try await mock.start(tunnelId: "t1", configPath: "/tmp/config.json", socksPort: 1080)
        #expect(mock.isRunning(tunnelId: "t1") == true)
        #expect(mock.isRunning == true)
        #expect(mock.startDates["t1"] != nil)
    }

    // MARK: Call tracking — stop

    @Test("stop records tunnelId")
    func stopRecordsArguments() async throws {
        let mock = MockXrayManager()
        try await mock.start(tunnelId: "t2", configPath: "/tmp/cfg.json", socksPort: 2080)
        try await mock.stop(tunnelId: "t2")
        #expect(mock.stopCalls.count == 1)
        #expect(mock.stopCalls[0] == "t2")
    }

    @Test("stop removes tunnel from running state")
    func stopClearsRunningState() async throws {
        let mock = MockXrayManager()
        try await mock.start(tunnelId: "t3", configPath: "/tmp/c.json", socksPort: 3000)
        try await mock.stop(tunnelId: "t3")
        #expect(mock.isRunning(tunnelId: "t3") == false)
        #expect(mock.isRunning == false)
        #expect(mock.startDates["t3"] == nil)
    }

    // MARK: Call tracking — restart

    @Test("restart records tunnelId, configPath, and socksPort")
    func restartRecordsArguments() async throws {
        let mock = MockXrayManager()
        try await mock.start(tunnelId: "t4", configPath: "/tmp/x.json", socksPort: 4000)
        try await mock.restart(tunnelId: "t4", configPath: "/tmp/x2.json", socksPort: 4001)
        #expect(mock.restartCalls.count == 1)
        #expect(mock.restartCalls[0].tunnelId == "t4")
        #expect(mock.restartCalls[0].configPath == "/tmp/x2.json")
        #expect(mock.restartCalls[0].socksPort == 4001)
    }

    @Test("restart keeps tunnel running after completion")
    func restartKeepsTunnelRunning() async throws {
        let mock = MockXrayManager()
        try await mock.start(tunnelId: "t5", configPath: "/tmp/y.json", socksPort: 5000)
        try await mock.restart(tunnelId: "t5", configPath: "/tmp/y.json", socksPort: 5000)
        #expect(mock.isRunning(tunnelId: "t5") == true)
    }

    // MARK: runningCount

    @Test("runningCount matches number of running tunnels")
    func runningCountMatchesRunningTunnels() async throws {
        let mock = MockXrayManager()
        #expect(mock.runningCount == 0)
        try await mock.start(tunnelId: "a", configPath: "/tmp/a.json", socksPort: 1000)
        #expect(mock.runningCount == 1)
        try await mock.start(tunnelId: "b", configPath: "/tmp/b.json", socksPort: 1001)
        #expect(mock.runningCount == 2)
        try await mock.stop(tunnelId: "a")
        #expect(mock.runningCount == 1)
    }

    // MARK: testLatency

    @Test("testLatency returns stubbed value and records server")
    func testLatencyReturnsStubbedValue() async {
        let mock = MockXrayManager()
        mock.stubbedLatency = 123
        let server = ServerConfig(name: "Test", address: "example.com", port: 443, uuid: "uuid-1")
        let result = await mock.testLatency(server: server)
        #expect(result == 123)
        #expect(mock.testLatencyCalls.count == 1)
        #expect(mock.testLatencyCalls[0].address == "example.com")
    }

    // MARK: logCallback

    @Test("logCallback can be set and is stored")
    func logCallbackCanBeSet() {
        let mock = MockXrayManager()
        let received = Box<String?>(nil)
        mock.logCallback = { msg in received.value = msg }
        mock.logCallback?("hello")
        #expect(received.value == "hello")
    }

    // MARK: Error injection

    @Test("shouldThrowOnStart causes start to throw")
    func shouldThrowOnStartThrows() async {
        let mock = MockXrayManager()
        mock.shouldThrowOnStart = true
        do {
            try await mock.start(tunnelId: "err", configPath: "/tmp/c.json", socksPort: 9000)
            Issue.record("Expected start to throw but it did not")
        } catch {
            #expect(error is XrayError)
        }
        // Start call should still be recorded even if it throws
        #expect(mock.startCalls.count == 1)
    }

    @Test("shouldThrowOnStop causes stop to throw")
    func shouldThrowOnStopThrows() async throws {
        let mock = MockXrayManager()
        try await mock.start(tunnelId: "err2", configPath: "/tmp/c.json", socksPort: 9001)
        mock.shouldThrowOnStop = true
        do {
            try await mock.stop(tunnelId: "err2")
            Issue.record("Expected stop to throw but it did not")
        } catch {
            #expect(error is XrayError)
        }
        #expect(mock.stopCalls.count == 1)
    }

    // MARK: stopAll / terminateAllSync

    @Test("stopAll increments call count and clears all running tunnels")
    func stopAllClearsAll() async throws {
        let mock = MockXrayManager()
        try await mock.start(tunnelId: "x", configPath: "/tmp/x.json", socksPort: 7000)
        try await mock.start(tunnelId: "y", configPath: "/tmp/y.json", socksPort: 7001)
        await mock.stopAll()
        #expect(mock.stopAllCallCount == 1)
        #expect(mock.isRunning == false)
        #expect(mock.runningCount == 0)
    }

    @Test("terminateAllSync increments call count and clears state")
    func terminateAllSyncClearsState() async throws {
        let mock = MockXrayManager()
        try await mock.start(tunnelId: "z", configPath: "/tmp/z.json", socksPort: 8000)
        mock.terminateAllSync()
        #expect(mock.terminateAllSyncCallCount == 1)
        #expect(mock.isRunning == false)
        #expect(mock.startDates.isEmpty)
    }
}

// MARK: - XrayManager Concrete Tests

@Suite("XrayManager Tests")
@MainActor
struct XrayManagerTests {

    // MARK: Initial state

    @Test("Initial state: isRunning is false")
    func initialIsRunningFalse() {
        let manager = XrayManager()
        #expect(manager.isRunning == false)
    }

    @Test("Initial state: runningCount is zero")
    func initialRunningCountZero() {
        let manager = XrayManager()
        #expect(manager.runningCount == 0)
    }

    @Test("Initial state: startDates is empty")
    func initialStartDatesEmpty() {
        let manager = XrayManager()
        #expect(manager.startDates.isEmpty)
    }

    // MARK: isRunning(tunnelId:)

    @Test("isRunning(tunnelId:) returns false for unknown tunnel ID")
    func isRunningFalseForUnknownId() {
        let manager = XrayManager()
        #expect(manager.isRunning(tunnelId: "nonexistent") == false)
        #expect(manager.isRunning(tunnelId: "") == false)
    }

    // MARK: getXrayBinaryPath

    @Test("getXrayBinaryPath returns a non-empty string")
    func getXrayBinaryPathNonEmpty() {
        let manager = XrayManager()
        let path = manager.getXrayBinaryPath()
        #expect(!path.isEmpty)
    }

    @Test("getXrayBinaryPath ends with 'xray'")
    func getXrayBinaryPathEndsWithXray() {
        let manager = XrayManager()
        let path = manager.getXrayBinaryPath()
        #expect(path.hasSuffix("xray"))
    }

    // MARK: XrayError descriptions

    @Test("XrayError.binaryNotFound has descriptive message")
    func binaryNotFoundDescription() {
        let error = XrayError.binaryNotFound("/usr/local/bin/xray")
        let desc = error.errorDescription ?? ""
        #expect(desc.contains("/usr/local/bin/xray"))
        #expect(desc.contains("not found"))
    }

    @Test("XrayError.startFailed has descriptive message")
    func startFailedDescription() {
        let reason = "process exited with code 1"
        let error = XrayError.startFailed(reason)
        let desc = error.errorDescription ?? ""
        #expect(desc.contains(reason))
    }

    @Test("XrayError.binaryNotFound is a LocalizedError")
    func binaryNotFoundIsLocalizedError() {
        let error: any LocalizedError = XrayError.binaryNotFound("/some/path")
        #expect(error.errorDescription != nil)
    }

    @Test("XrayError.startFailed is a LocalizedError")
    func startFailedIsLocalizedError() {
        let error: any LocalizedError = XrayError.startFailed("reason")
        #expect(error.errorDescription != nil)
    }

    // MARK: start() with nonexistent binary

    @Test("start throws binaryNotFound when binary does not exist")
    func startThrowsBinaryNotFound() async {
        let manager = XrayManager()
        // Verify the path resolution itself works
        let path = manager.getXrayBinaryPath()
        // We can only test the error type if the binary is absent.
        // In CI (no binary), start should throw binaryNotFound.
        guard !FileManager.default.fileExists(atPath: path) else {
            // Binary exists (developer machine) — skip error-path assertion
            return
        }
        do {
            try await manager.start(tunnelId: "test", configPath: "/tmp/fake.json", socksPort: 1090)
            Issue.record("Expected binaryNotFound error but start succeeded")
        } catch let error as XrayError {
            if case .binaryNotFound = error {
                // Correct error type
            } else {
                Issue.record("Expected binaryNotFound but got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: Protocol conformance

    @Test("XrayManager conforms to XrayManaging")
    func conformsToXrayManaging() {
        let manager = XrayManager()
        let _: any XrayManaging = manager  // Compile-time conformance check
        #expect(Bool(true))
    }

    @Test("logCallback can be assigned and retrieved")
    func logCallbackAssignment() {
        let manager = XrayManager()
        let received = Box<String?>(nil)
        manager.logCallback = { msg in received.value = msg }
        manager.logCallback?("test message")
        #expect(received.value == "test message")
    }
}
