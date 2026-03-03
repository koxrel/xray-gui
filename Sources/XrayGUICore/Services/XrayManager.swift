import Foundation
import Network

/// Thread-safe wrapper for the "already resumed" flag used in latency tests.
private final class AtomicFlag: @unchecked Sendable {
    private var _value = false
    private let lock = NSLock()

    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }

    /// Atomically check-and-set. Returns `true` if this call flipped from false to true.
    func testAndSet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _value { return false }
        _value = true
        return true
    }
}

@MainActor
public final class XrayManager: XrayManaging, @unchecked Sendable {
    private var processes: [String: Process] = [:]
    public private(set) var startDates: [String: Date] = [:]
    public var logCallback: (@Sendable (String) -> Void)?

    public init() {}

    public var isRunning: Bool {
        processes.values.contains { $0.isRunning }
    }

    public func isRunning(tunnelId: String) -> Bool {
        processes[tunnelId]?.isRunning == true
    }

    public var runningCount: Int {
        processes.values.filter { $0.isRunning }.count
    }

    public func getXrayBinaryPath() -> String {
        // Check bundle resources first (packaged app)
        if let bundlePath = Bundle.main.resourceURL?.appendingPathComponent("xray-core/xray").path,
           FileManager.default.fileExists(atPath: bundlePath) {
            return bundlePath
        }
        // Development: check relative to working directory
        let devPath = FileManager.default.currentDirectoryPath + "/Resources/xray-core/xray"
        if FileManager.default.fileExists(atPath: devPath) {
            return devPath
        }
        // Check parent project resources
        let parentPath = (FileManager.default.currentDirectoryPath as NSString)
            .deletingLastPathComponent + "/Resources/xray-core/xray"
        if FileManager.default.fileExists(atPath: parentPath) {
            return parentPath
        }
        return devPath
    }

    public func start(tunnelId: String, configPath: String, socksPort: Int) async throws {
        // Stop this specific tunnel if already running
        if isRunning(tunnelId: tunnelId) {
            try await stop(tunnelId: tunnelId)
        }

        let binaryPath = getXrayBinaryPath()
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            throw XrayError.binaryNotFound(binaryPath)
        }

        // Make binary executable
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: binaryPath
        )

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = ["run", "-c", configPath]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe
        proc.standardInput = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            // Clean up pipe handles on failure
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        processes[tunnelId] = proc

        // Stream stdout and stderr with tunnel ID prefix
        let logCb = self.logCallback
        let tid = tunnelId

        func attachReader(_ pipe: Pipe) {
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
                for line in str.components(separatedBy: .newlines) where !line.isEmpty {
                    logCb?("[\(tid)] \(line)")
                }
            }
        }

        attachReader(stdoutPipe)
        attachReader(stderrPipe)

        // Health check: poll SOCKS port until Xray accepts connections (up to 5s)
        let ready = await waitForTCPReady(port: UInt16(socksPort))
        if !ready {
            if !proc.isRunning {
                throw XrayError.startFailed("Xray process exited unexpectedly during startup")
            }
            logCallback?("[\(tunnelId)] Warning: SOCKS port \(socksPort) not responding after 5s, proceeding anyway")
        }
        startDates[tunnelId] = Date()
    }

    /// Polls 127.0.0.1:port every 200 ms until a TCP connection succeeds or 5 seconds elapse.
    /// Returns `true` if the port became ready within the timeout.
    nonisolated private func waitForTCPReady(port: UInt16) async -> Bool {
        let deadline = DispatchTime.now() + 5.0
        while DispatchTime.now() < deadline {
            let connected = await singleTCPConnect(port: port)
            if connected { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    /// Attempts a single TCP connection to 127.0.0.1:port with a 1-second per-attempt timeout.
    /// Returns `true` if the connection reached `.ready`.
    nonisolated private func singleTCPConnect(port: UInt16) async -> Bool {
        await withCheckedContinuation { continuation in
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: false)
                return
            }
            let connection = NWConnection(host: "127.0.0.1", port: nwPort, using: .tcp)
            let resumed = AtomicFlag()

            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + 1)
            timer.setEventHandler {
                guard resumed.testAndSet() else { return }
                connection.cancel()
                continuation.resume(returning: false)
            }
            timer.resume()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard resumed.testAndSet() else { return }
                    timer.cancel()
                    connection.cancel()
                    continuation.resume(returning: true)
                case .failed, .cancelled:
                    guard resumed.testAndSet() else { return }
                    timer.cancel()
                    continuation.resume(returning: false)
                default:
                    break
                }
            }

            connection.start(queue: .global())
        }
    }

    public func stop(tunnelId: String) async throws {
        guard let proc = processes[tunnelId], proc.isRunning else {
            processes.removeValue(forKey: tunnelId)
            startDates.removeValue(forKey: tunnelId)
            return
        }

        // Nil out readability handlers to prevent leaks
        if let stdout = proc.standardOutput as? Pipe {
            stdout.fileHandleForReading.readabilityHandler = nil
        }
        if let stderr = proc.standardError as? Pipe {
            stderr.fileHandleForReading.readabilityHandler = nil
        }

        // Set terminationHandler BEFORE terminate() to avoid race window
        let terminated = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let resumed = AtomicFlag()

            proc.terminationHandler = { _ in
                if resumed.testAndSet() {
                    continuation.resume(returning: true)
                }
            }

            proc.terminate() // SIGTERM — handler is already in place

            // Process may have already exited
            if !proc.isRunning {
                if resumed.testAndSet() {
                    continuation.resume(returning: true)
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                if resumed.testAndSet() {
                    continuation.resume(returning: false)
                }
            }
        }

        if !terminated && proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
        }

        processes.removeValue(forKey: tunnelId)
        startDates.removeValue(forKey: tunnelId)
    }

    /// Synchronous cleanup for app termination — no async bridge needed.
    public func terminateAllSync() {
        // Clean up pipe handlers and send SIGTERM to all processes at once
        for (_, proc) in processes {
            if let stdout = proc.standardOutput as? Pipe {
                stdout.fileHandleForReading.readabilityHandler = nil
            }
            if let stderr = proc.standardError as? Pipe {
                stderr.fileHandleForReading.readabilityHandler = nil
            }
            if proc.isRunning {
                proc.terminate()
            }
        }

        // Brief grace period, then SIGKILL any stragglers
        Thread.sleep(forTimeInterval: 0.3)
        for (_, proc) in processes where proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
        }

        processes.removeAll()
        startDates.removeAll()
    }

    public func stopAll() async {
        for tunnelId in Array(processes.keys) {
            try? await stop(tunnelId: tunnelId)
        }
    }

    public func restart(tunnelId: String, configPath: String, socksPort: Int) async throws {
        try await stop(tunnelId: tunnelId)
        try await start(tunnelId: tunnelId, configPath: configPath, socksPort: socksPort)
    }

    nonisolated public func testLatency(server: ServerConfig) async -> Int {
        // TCP connection test - 3 attempts, return median
        var results: [Int] = []

        for _ in 0..<3 {
            let latency = await singleTCPLatency(host: server.address, port: UInt16(server.port))
            if latency >= 0 {
                results.append(latency)
            }
        }

        guard !results.isEmpty else { return -1 }
        results.sort()
        return results[results.count / 2] // median
    }

    nonisolated private func singleTCPLatency(host: String, port: UInt16) async -> Int {
        await withCheckedContinuation { continuation in
            let nwHost = NWEndpoint.Host(host)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: -1)
                return
            }
            let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)

            let start = DispatchTime.now()
            let resumed = AtomicFlag()

            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + 5)
            timer.setEventHandler {
                guard resumed.testAndSet() else { return }
                connection.cancel()
                continuation.resume(returning: -1)
            }
            timer.resume()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                    let ms = Int(elapsed / 1_000_000)
                    guard resumed.testAndSet() else { return }
                    timer.cancel()
                    connection.cancel()
                    continuation.resume(returning: ms)
                case .failed, .cancelled:
                    guard resumed.testAndSet() else { return }
                    timer.cancel()
                    connection.cancel()
                    continuation.resume(returning: -1)
                default:
                    break
                }
            }

            connection.start(queue: .global())
        }
    }
}

public enum XrayError: LocalizedError {
    case binaryNotFound(String)
    case startFailed(String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let path):
            return "Xray binary not found at: \(path)"
        case .startFailed(let reason):
            return "Failed to start xray: \(reason)"
        }
    }
}
