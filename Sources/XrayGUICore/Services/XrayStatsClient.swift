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

public final class XrayStatsClient: TunnelStatsQuerying, @unchecked Sendable {
    private let binaryPath: String?

    public init(binaryPath: String? = nil) {
        self.binaryPath = binaryPath
    }

    public func queryStats(apiPort: Int) async throws -> TunnelTrafficStats {
        let binaryPath = if let binaryPath {
            binaryPath
        } else {
            await MainActor.run { XrayManager().getXrayBinaryPath() }
        }

        guard FileManager.default.fileExists(atPath: binaryPath) else {
            throw XrayStatsError.binaryNotFound(binaryPath)
        }

        return try await Task.detached(priority: .utility) { [binaryPath] in
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

            try process.run()
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard process.terminationStatus == 0 else {
                throw XrayStatsError.commandFailed(stderr.isEmpty ? stdout : stderr)
            }

            return try Self.parseStatsQueryResponse(stdout)
        }.value
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

        if let stringValue = try? container.decode(String.self, forKey: .value),
           let parsed = UInt64(stringValue) {
            value = parsed
        } else if let intValue = try? container.decode(UInt64.self, forKey: .value) {
            value = intValue
        } else {
            throw DecodingError.dataCorruptedError(forKey: .value, in: container, debugDescription: "Unsupported stat value")
        }
    }
}
