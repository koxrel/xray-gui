import Foundation

public enum SubscriptionManager {
    private static let maxResponseSize = 1_048_576 // 1 MB

    public static func fetchSubscription(url: String) async throws -> String {
        guard let requestURL = URL(string: url) else {
            throw SubscriptionError.invalidURL(url)
        }

        // Enforce HTTPS
        guard requestURL.scheme?.lowercased() == "https" else {
            throw SubscriptionError.invalidURL("Only HTTPS subscription URLs are allowed")
        }

        // Reject private/loopback hosts.
        // Note: This checks the hostname string only. DNS rebinding attacks can bypass
        // this by resolving a public hostname to a private IP at request time. Full
        // mitigation would require a custom URLProtocol that validates resolved IPs.
        if let host = requestURL.host?.lowercased() {
            if isPrivateOrLoopback(host) {
                throw SubscriptionError.invalidURL("Private or loopback hosts are not allowed")
            }
        }

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: request)

        // Limit response size
        guard data.count <= maxResponseSize else {
            throw SubscriptionError.fetchFailed("Response too large (\(data.count) bytes)")
        }

        guard let body = String(data: data, encoding: .utf8) else {
            throw SubscriptionError.decodeFailed
        }
        return body
    }

    private static func isPrivateOrLoopback(_ host: String) -> Bool {
        let blocked = ["localhost", "127.0.0.1", "0.0.0.0", "::1", "[::1]", "::"]
        if blocked.contains(host) { return true }
        // 10.x.x.x
        if host.hasPrefix("10.") { return true }
        // 192.168.x.x
        if host.hasPrefix("192.168.") { return true }
        // 169.254.x.x (link-local — blocks cloud metadata SSRF)
        if host.hasPrefix("169.254.") { return true }
        // 0.x.x.x
        if host.hasPrefix("0.") { return true }
        // 172.16-31.x.x
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        // IPv6 ULA (fc00::/7) and link-local (fe80::/10)
        if host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80") {
            return true
        }
        return false
    }

    public static func parseSubscriptionContent(_ base64Content: String) -> [ServerConfig] {
        // Try base64 decode
        let cleaned = base64Content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let decoded = base64Decode(cleaned) else {
            // If not valid base64, try parsing directly as vless:// lines
            return parseLines(cleaned)
        }

        return parseLines(decoded)
    }

    private static func base64Decode(_ input: String) -> String? {
        // Handle URL-safe base64
        var base64 = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func parseLines(_ content: String) -> [ServerConfig] {
        content
            .components(separatedBy: .newlines)
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("vless://") else { return nil }
                guard let server = parseVlessUrl(trimmed) else { return nil }
                // Reject servers pointing to private/loopback addresses
                if isPrivateOrLoopback(server.address.lowercased()) { return nil }
                return server
            }
    }

    public static func parseVlessUrl(_ urlString: String) -> ServerConfig? {
        // Format: vless://uuid@host:port?params#name
        guard urlString.hasPrefix("vless://") else { return nil }

        let afterScheme = String(urlString.dropFirst("vless://".count))

        // Split fragment (#name)
        let fragmentParts = afterScheme.split(separator: "#", maxSplits: 1)
        let beforeFragment = String(fragmentParts[0])
        let fragment = fragmentParts.count > 1 ? String(fragmentParts[1]) : nil
        let name = fragment.flatMap { $0.removingPercentEncoding } ?? ""

        // Split query string (?params)
        let queryParts = beforeFragment.split(separator: "?", maxSplits: 1)
        let beforeQuery = String(queryParts[0])
        let queryString = queryParts.count > 1 ? String(queryParts[1]) : ""

        // Parse uuid@host:port
        let atParts = beforeQuery.split(separator: "@", maxSplits: 1)
        guard atParts.count == 2 else { return nil }

        let uuid = String(atParts[0])
        let hostPort = String(atParts[1])

        // Handle IPv6: [::1]:443
        let address: String
        let port: Int

        if hostPort.hasPrefix("[") {
            // IPv6
            guard let closeBracket = hostPort.firstIndex(of: "]") else { return nil }
            address = String(hostPort[hostPort.index(after: hostPort.startIndex)..<closeBracket])
            let afterBracket = hostPort[hostPort.index(after: closeBracket)...]
            if afterBracket.hasPrefix(":") {
                port = Int(afterBracket.dropFirst()) ?? 443
            } else {
                port = 443
            }
        } else {
            // IPv4 or hostname
            let colonParts = hostPort.split(separator: ":", maxSplits: 1)
            address = String(colonParts[0])
            port = colonParts.count > 1 ? Int(colonParts[1]) ?? 443 : 443
        }

        // Parse query parameters
        var params: [String: String] = [:]
        if !queryString.isEmpty {
            for param in queryString.split(separator: "&") {
                let kv = param.split(separator: "=", maxSplits: 1)
                let key = String(kv[0])
                let value = kv.count > 1 ? String(kv[1]).removingPercentEncoding ?? String(kv[1]) : ""
                params[key] = value
            }
        }

        var server = ServerConfig()
        server.name = name.isEmpty ? "\(address):\(port)" : name
        server.address = address
        server.port = port
        server.uuid = uuid
        server.flow = params["flow"] ?? ""
        server.encryption = params["encryption"] ?? "none"
        server.network = params["type"] ?? "tcp"
        server.security = params["security"] ?? "none"
        server.sni = params["sni"] ?? ""
        server.fingerprint = params["fp"] ?? ""
        server.publicKey = params["pbk"] ?? ""
        server.shortId = params["sid"] ?? ""
        server.headerType = params["headerType"]

        // ALPN: comma-separated
        if let alpnStr = params["alpn"], !alpnStr.isEmpty {
            server.alpn = alpnStr.components(separatedBy: ",")
        }

        // Always override allowInsecure to false for safety
        server.allowInsecure = false

        // Transport-specific
        server.wsPath = params["path"]
        server.wsHost = params["host"]
        server.grpcServiceName = params["serviceName"]
        server.grpcMultiMode = params["mode"] == "multi" ? true : nil

        return server
    }
}

public enum SubscriptionError: LocalizedError {
    case invalidURL(String)
    case decodeFailed
    case fetchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .decodeFailed: return "Failed to decode subscription content"
        case .fetchFailed(let reason): return "Fetch failed: \(reason)"
        }
    }
}
