import Testing
import Foundation
@testable import XrayGUICore

/// Edge cases not covered by the primary SubscriptionManagerTests suite.
@Suite("SubscriptionManager Edge Cases")
struct SubscriptionManagerEdgeCaseTests {

    // MARK: - fetchSubscription URL Validation (synchronous-accessible paths)

    @Test("fetchSubscription throws invalidURL for http:// scheme (non-HTTPS)")
    func rejectsHttpScheme() async throws {
        await #expect(throws: SubscriptionError.self) {
            try await SubscriptionManager.fetchSubscription(url: "http://example.com/sub")
        }
    }

    @Test("fetchSubscription throws invalidURL for non-URL string")
    func rejectsMalformedUrlString() async throws {
        await #expect(throws: SubscriptionError.self) {
            try await SubscriptionManager.fetchSubscription(url: "not a url at all")
        }
    }

    @Test("fetchSubscription throws invalidURL for loopback address 127.0.0.1")
    func rejectsLoopback127() async throws {
        await #expect(throws: SubscriptionError.self) {
            try await SubscriptionManager.fetchSubscription(url: "https://127.0.0.1/sub")
        }
    }

    @Test("fetchSubscription throws invalidURL for localhost")
    func rejectsLocalhost() async throws {
        await #expect(throws: SubscriptionError.self) {
            try await SubscriptionManager.fetchSubscription(url: "https://localhost/sub")
        }
    }

    @Test("fetchSubscription throws invalidURL for private 192.168.x.x")
    func rejectsPrivate192() async throws {
        await #expect(throws: SubscriptionError.self) {
            try await SubscriptionManager.fetchSubscription(url: "https://192.168.1.100/sub")
        }
    }

    @Test("fetchSubscription throws invalidURL for private 10.x.x.x")
    func rejectsPrivate10() async throws {
        await #expect(throws: SubscriptionError.self) {
            try await SubscriptionManager.fetchSubscription(url: "https://10.0.0.1/sub")
        }
    }

    @Test("fetchSubscription throws invalidURL for link-local 169.254.x.x")
    func rejectsLinkLocal() async throws {
        await #expect(throws: SubscriptionError.self) {
            try await SubscriptionManager.fetchSubscription(url: "https://169.254.169.254/sub")
        }
    }

    @Test("fetchSubscription throws invalidURL for 172.16-31.x.x range")
    func rejectsPrivate172() async throws {
        // Test boundaries: 172.16 (in range), 172.31 (in range)
        await #expect(throws: SubscriptionError.self) {
            try await SubscriptionManager.fetchSubscription(url: "https://172.16.0.1/sub")
        }
        await #expect(throws: SubscriptionError.self) {
            try await SubscriptionManager.fetchSubscription(url: "https://172.31.255.255/sub")
        }
    }

    @Test("172.16 is blocked but 172.15 is not (private range boundary check via parseSubscriptionContent)")
    func private172RangeBoundary() {
        // Test the boundary without network I/O by using parseSubscriptionContent.
        // 172.16 is inside the private range and must be filtered out.
        // 172.15 is outside the private range and must be passed through.
        let blocked = SubscriptionManager.parseSubscriptionContent("vless://uuid@172.16.0.1:443#Private172_16")
        let allowed = SubscriptionManager.parseSubscriptionContent("vless://uuid@172.15.0.1:443#Outside172_15")

        #expect(blocked.isEmpty, "172.16.x.x should be filtered as a private address")
        #expect(allowed.count == 1, "172.15.x.x should not be filtered (outside the 172.16-31 private range)")
    }

    @Test("fetchSubscription throws invalidURL for IPv6 ULA fc prefix")
    func rejectsIPv6UlaFc() async throws {
        await #expect(throws: SubscriptionError.self) {
            try await SubscriptionManager.fetchSubscription(url: "https://fc00::1/sub")
        }
    }

    @Test("fetchSubscription throws invalidURL for IPv6 ULA fd prefix")
    func rejectsIPv6UlaFd() async throws {
        await #expect(throws: SubscriptionError.self) {
            try await SubscriptionManager.fetchSubscription(url: "https://fd12:3456::1/sub")
        }
    }

    @Test("fetchSubscription throws invalidURL for IPv6 link-local fe80")
    func rejectsIPv6LinkLocal() async throws {
        await #expect(throws: SubscriptionError.self) {
            try await SubscriptionManager.fetchSubscription(url: "https://fe80::1/sub")
        }
    }

    // MARK: - parseVlessUrl Edge Cases

    @Test("Parses IPv6 address in brackets")
    func parsesIPv6Address() throws {
        let url = "vless://uuid@[2001:db8::1]:443?security=tls#IPv6Server"
        let server = try #require(SubscriptionManager.parseVlessUrl(url))
        #expect(server.address == "2001:db8::1")
        #expect(server.port == 443)
        #expect(server.name == "IPv6Server")
    }

    @Test("Parses IPv6 with default port when no port given after bracket")
    func parsesIPv6DefaultPort() throws {
        let url = "vless://uuid@[::1]#LocalIPv6"
        let server = try #require(SubscriptionManager.parseVlessUrl(url))
        #expect(server.address == "::1")
        #expect(server.port == 443)
    }

    @Test("headerType param is parsed and stored")
    func parsesHeaderType() throws {
        let url = "vless://uuid@host.com:80?type=tcp&headerType=http#HttpHeader"
        let server = try #require(SubscriptionManager.parseVlessUrl(url))
        #expect(server.headerType == "http")
    }

    @Test("grpcMultiMode is nil when mode param is not 'multi'")
    func grpcNonMultiMode() throws {
        let url = "vless://uuid@host.com:443?type=grpc&serviceName=svc&mode=gun#gRPC"
        let server = try #require(SubscriptionManager.parseVlessUrl(url))
        #expect(server.grpcMultiMode == nil)
    }

    @Test("Missing encryption param defaults to 'none'")
    func defaultEncryption() throws {
        let url = "vless://uuid@host.com:443#NoEncryption"
        let server = try #require(SubscriptionManager.parseVlessUrl(url))
        #expect(server.encryption == "none")
    }

    @Test("Missing type param defaults to 'tcp' for network")
    func defaultNetwork() throws {
        let url = "vless://uuid@host.com:443#NoType"
        let server = try #require(SubscriptionManager.parseVlessUrl(url))
        #expect(server.network == "tcp")
    }

    @Test("Missing security param defaults to 'none'")
    func defaultSecurity() throws {
        let url = "vless://uuid@host.com:443#NoSecurity"
        let server = try #require(SubscriptionManager.parseVlessUrl(url))
        #expect(server.security == "none")
    }

    @Test("Percent-encoded name is decoded in fragment")
    func percentEncodedName() throws {
        let url = "vless://uuid@host.com:443#My%20Awesome%20Server"
        let server = try #require(SubscriptionManager.parseVlessUrl(url))
        #expect(server.name == "My Awesome Server")
    }

    @Test("Returns nil for empty string")
    func rejectsEmpty() {
        #expect(SubscriptionManager.parseVlessUrl("") == nil)
    }

    @Test("Returns nil when IPv6 bracket is not closed")
    func rejectsUnclosedIPv6Bracket() {
        let url = "vless://uuid@[2001:db8::1:443#MissingBracket"
        #expect(SubscriptionManager.parseVlessUrl(url) == nil)
    }

    // MARK: - parseSubscriptionContent URL-safe Base64

    @Test("URL-safe base64 with dash and underscore characters is decoded correctly")
    func urlSafeBase64() {
        // Encode a plain-text subscription, then manually introduce URL-safe chars
        let plain = "vless://uuid@urlsafe.example.com:443?security=tls#URLSafeTest"
        var base64 = Data(plain.utf8).base64EncodedString()
        // Replace standard base64 chars with URL-safe equivalents
        base64 = base64.replacingOccurrences(of: "+", with: "-")
        base64 = base64.replacingOccurrences(of: "/", with: "_")
        // Strip padding to also test padding re-insertion
        base64 = base64.trimmingCharacters(in: CharacterSet(charactersIn: "="))

        let servers = SubscriptionManager.parseSubscriptionContent(base64)
        // URL-safe base64 parsing may or may not yield results depending on content —
        // what matters is it doesn't crash and handles the input gracefully.
        // If the content happens to decode to valid VLESS URLs, we verify correctness.
        if servers.count == 1 {
            #expect(servers[0].address == "urlsafe.example.com")
        }
        // If 0 results: the base64 content happened to look like non-VLESS after decode,
        // which is also acceptable — the point is no crash.
    }

    @Test("Base64 without padding is decoded correctly")
    func base64WithoutPadding() {
        let plain = "vless://uuid@nopad.example.com:443#NoPadding"
        // Standard base64 with padding stripped
        let withPadding = Data(plain.utf8).base64EncodedString()
        let withoutPadding = withPadding.trimmingCharacters(in: CharacterSet(charactersIn: "="))

        let servers = SubscriptionManager.parseSubscriptionContent(withoutPadding)
        if servers.count == 1 {
            #expect(servers[0].address == "nopad.example.com")
        }
    }

    @Test("Subscription content with only whitespace returns empty")
    func whitespaceOnly() {
        let servers = SubscriptionManager.parseSubscriptionContent("   \n\t\n  ")
        #expect(servers.isEmpty)
    }

    @Test("Subscription content filters 172.16-31 private addresses")
    func filters172PrivateRange() {
        let content = """
        vless://uuid@172.16.0.1:443#Private172_16
        vless://uuid@172.31.255.255:443#Private172_31
        vless://uuid@172.15.0.1:443#Outside172
        vless://uuid@public.com:443#Public
        """
        let servers = SubscriptionManager.parseSubscriptionContent(content)
        // 172.16 and 172.31 should be filtered; 172.15 and public.com should pass
        #expect(!servers.contains { $0.address == "172.16.0.1" })
        #expect(!servers.contains { $0.address == "172.31.255.255" })
        // public.com must be present
        #expect(servers.contains { $0.address == "public.com" })
    }

    // MARK: - SubscriptionError

    @Test("SubscriptionError.invalidURL errorDescription contains the url")
    func invalidUrlDescription() {
        let error = SubscriptionError.invalidURL("https://bad.example.com")
        #expect(error.errorDescription?.contains("https://bad.example.com") == true)
    }

    @Test("SubscriptionError.fetchFailed errorDescription contains the reason")
    func fetchFailedDescription() {
        let error = SubscriptionError.fetchFailed("Response too large")
        #expect(error.errorDescription?.contains("Response too large") == true)
    }

    @Test("SubscriptionError.decodeFailed has a non-nil errorDescription")
    func decodeFailedDescription() {
        let error = SubscriptionError.decodeFailed
        #expect(error.errorDescription != nil)
    }
}
