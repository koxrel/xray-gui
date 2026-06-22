import Foundation

public enum XrayStatsError: LocalizedError {
    case binaryNotFound(String)
    case commandFailed(String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case let .binaryNotFound(path):
            return "Xray binary not found at \(path)"
        case let .commandFailed(message):
            return "Xray stats query failed: \(message)"
        case let .invalidResponse(message):
            return "Invalid Xray stats response: \(message)"
        }
    }
}

/// One-shot, thread-safe latch: the first `claim()` returns true, all others false.
/// Used to ensure a continuation is resumed exactly once across racing callbacks.
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

public final class XrayStatsClient: TunnelStatsQuerying, @unchecked Sendable {
    private let binaryPath: String

    public init(binaryPath: String) {
        self.binaryPath = binaryPath
    }

    public func queryStats(apiPort: Int) async throws -> TunnelTrafficStats {
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            throw XrayStatsError.binaryNotFound(binaryPath)
        }

        let stdout = try await runStatsQuery(apiPort: apiPort)
        return try Self.parseStatsQueryResponse(stdout)
    }

    /// Launches the `xray api statsquery` child process and resumes when it exits.
    ///
    /// Critically, this does NOT call `process.waitUntilExit()`. That call blocks
    /// the calling thread, and Swift concurrency runs `async` work (including
    /// `Task.detached`) on a fixed-size cooperative thread pool — one thread per
    /// core. Blocking those threads on synchronous process waits starves the pool;
    /// under enough concurrent stats queries the runtime can no longer drain the
    /// enclosing `withTaskGroup`, and an in-flight child task offering its result
    /// to a torn-down group segfaults (`TaskGroup::offer`, EXC_BAD_ACCESS).
    ///
    /// Instead we bridge completion via `terminationHandler`, which Foundation
    /// invokes on its own internal queue — never the cooperative pool — so no
    /// concurrency thread is ever blocked on this process.
    private func runStatsQuery(apiPort: Int) async throws -> String {
        let binaryPath = self.binaryPath
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = [
                "api",
                "statsquery",
                "--server=127.0.0.1:\(apiPort)",
                "-pattern",
                "inbound>>>"
            ]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = FileHandle.nullDevice

            // Guarantees the continuation is resumed exactly once, no matter which
            // path (normal exit, run() failure, or watchdog kill) gets there first.
            let resumeGuard = ResumeGuard()
            let finish: @Sendable (Result<String, Error>) -> Void = { result in
                guard resumeGuard.claim() else { return }
                continuation.resume(with: result)
            }

            process.terminationHandler = { proc in
                // The process has already exited, so the (small) stats payload is
                // fully buffered — reading to end here cannot deadlock.
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if proc.terminationStatus == 0 {
                    finish(.success(stdout))
                } else {
                    finish(.failure(XrayStatsError.commandFailed(stderr.isEmpty ? stdout : stderr)))
                }
            }

            do {
                try process.run()
            } catch {
                finish(.failure(XrayStatsError.commandFailed(error.localizedDescription)))
                return
            }

            // Watchdog: a stats query must never hang. Crucially this resumes the
            // continuation DIRECTLY rather than relying on terminationHandler.
            //
            // `Process.terminationHandler` is not guaranteed to fire in every edge
            // case (notably a process that exits in the narrow window around launch,
            // which happens right after a tunnel restart when the gRPC API isn't
            // listening yet and `xray` exits almost immediately). If the handler is
            // missed, the continuation would be orphaned forever — and because the
            // caller coalesces refreshes behind `isRefreshingStatistics`, that one
            // orphaned query freezes the ENTIRE stats feature on its last snapshot.
            // Resuming here (ResumeGuard makes it a no-op if the handler already ran)
            // bounds every query to `timeout` seconds no matter what Foundation does.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { [weak process] in
                finish(.failure(XrayStatsError.commandFailed("stats query timed out")))
                process?.terminate() // best-effort cleanup; no-op if already exited
            }
        }
    }

    static func parseStatsQueryResponse(_ response: String) throws -> TunnelTrafficStats {
        let data = Data(response.utf8)

        let decoded: StatsQueryResponse
        do {
            decoded = try JSONDecoder().decode(StatsQueryResponse.self, from: data)
        } catch {
            throw XrayStatsError.invalidResponse(error.localizedDescription)
        }

        var uplink: UInt64 = 0
        var downlink: UInt64 = 0

        for entry in decoded.stat {
            switch entry.name {
            case "inbound>>>http-in>>>traffic>>>uplink", "inbound>>>socks-in>>>traffic>>>uplink":
                uplink += entry.value
            case "inbound>>>http-in>>>traffic>>>downlink", "inbound>>>socks-in>>>traffic>>>downlink":
                downlink += entry.value
            default:
                continue
            }
        }

        return TunnelTrafficStats(uplinkBytes: uplink, downlinkBytes: downlink)
    }
}

private struct StatsQueryResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case stat
    }

    var stat: [StatsQueryEntry]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stat = try container.decodeIfPresent([StatsQueryEntry].self, forKey: .stat) ?? []
    }
}

private struct StatsQueryEntry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name
        case value
    }

    let name: String
    let value: UInt64

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)

        // Xray serializes stats as protobuf JSON, which OMITS the `value` field
        // entirely for zero-valued counters (e.g. an idle inbound). A missing value
        // therefore means 0 — it must not fail the decode, or a single idle counter
        // would poison the whole response and make all stats read as unavailable.
        // Accept numeric or string-encoded values; treat absent/null/unparseable as 0.
        if let intValue = try? container.decodeIfPresent(UInt64.self, forKey: .value) {
            value = intValue
        } else if let stringValue = try? container.decodeIfPresent(String.self, forKey: .value),
                  let parsed = UInt64(stringValue) {
            value = parsed
        } else {
            value = 0
        }
    }
}
