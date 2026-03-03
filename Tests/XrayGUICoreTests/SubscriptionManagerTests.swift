import Testing
import Foundation
@testable import XrayGUICore

@Suite("SubscriptionManager Tests")
struct SubscriptionManagerTests {

    // MARK: - parseVlessUrl

    @Test("Parses basic VLESS URL correctly")
    func parseBasicVlessUrl() throws {
        let url = "vless://abc-123@example.com:443?security=tls&type=tcp&sni=example.com#My%20Server"
        let server = try #require(SubscriptionManager.parseVlessUrl(url))

        #expect(server.uuid == "abc-123")
        #expect(server.address == "example.com")
        #expect(server.port == 443)
        #expect(server.security == "tls")
        #expect(server.network == "tcp")
        #expect(server.sni == "example.com")
        #expect(server.name == "My Server")
    }

    @Test("Parses VLESS URL with Reality settings")
    func parseRealityVlessUrl() throws {
        let url = "vless://uuid@host.com:443?security=reality&type=tcp&flow=xtls-rprx-vision&pbk=publickey123&sid=shortid456&fp=chrome&sni=target.com#Reality"
        let server = try #require(SubscriptionManager.parseVlessUrl(url))

        #expect(server.flow == "xtls-rprx-vision")
        #expect(server.publicKey == "publickey123")
        #expect(server.shortId == "shortid456")
        #expect(server.fingerprint == "chrome")
        #expect(server.security == "reality")
    }

    @Test("Parses VLESS URL with WebSocket transport")
    func parseWebSocketVlessUrl() throws {
        let url = "vless://uuid@ws.example.com:8080?type=ws&path=%2Fwebsocket&host=cdn.example.com&security=tls#WS"
        let server = try #require(SubscriptionManager.parseVlessUrl(url))

        #expect(server.network == "ws")
        #expect(server.wsPath == "/websocket")
        #expect(server.wsHost == "cdn.example.com")
    }

    @Test("Parses VLESS URL with gRPC transport")
    func parseGrpcVlessUrl() throws {
        let url = "vless://uuid@grpc.example.com:443?type=grpc&serviceName=myService&mode=multi&security=tls#gRPC"
        let server = try #require(SubscriptionManager.parseVlessUrl(url))

        #expect(server.network == "grpc")
        #expect(server.grpcServiceName == "myService")
        #expect(server.grpcMultiMode == true)
    }

    @Test("Parses VLESS URL with ALPN")
    func parseAlpn() throws {
        let url = "vless://uuid@host.com:443?security=tls&alpn=h2,http/1.1#Test"
        let server = try #require(SubscriptionManager.parseVlessUrl(url))
        #expect(server.alpn == ["h2", "http/1.1"])
    }

    @Test("Defaults port to 443 when missing")
    func defaultPort() throws {
        let url = "vless://uuid@host.com#NoPort"
        let server = try #require(SubscriptionManager.parseVlessUrl(url))
        #expect(server.port == 443)
    }

    @Test("Uses address:port as name when fragment is missing")
    func nameFromAddressPort() throws {
        let url = "vless://uuid@host.com:8443"
        let server = try #require(SubscriptionManager.parseVlessUrl(url))
        #expect(server.name == "host.com:8443")
    }

    @Test("Returns nil for non-VLESS URL")
    func rejectsNonVlessUrl() {
        #expect(SubscriptionManager.parseVlessUrl("vmess://abc@host:443") == nil)
    }

    @Test("Returns nil for malformed URL without @")
    func rejectsMalformedUrl() {
        #expect(SubscriptionManager.parseVlessUrl("vless://no-at-sign") == nil)
    }

    @Test("Always sets allowInsecure to false")
    func allowInsecureAlwaysFalse() throws {
        let url = "vless://uuid@host.com:443?allowInsecure=true#Test"
        let server = try #require(SubscriptionManager.parseVlessUrl(url))
        #expect(server.allowInsecure == false)
    }

    // MARK: - parseSubscriptionContent

    @Test("Parses plain text VLESS lines")
    func parsePlainTextLines() {
        let content = """
        vless://uuid1@server1.com:443?security=tls#Server1
        vless://uuid2@server2.com:443?security=tls#Server2
        """
        let servers = SubscriptionManager.parseSubscriptionContent(content)
        #expect(servers.count == 2)
        #expect(servers[0].address == "server1.com")
        #expect(servers[1].address == "server2.com")
    }

    @Test("Parses base64-encoded subscription content")
    func parseBase64Content() {
        let plain = "vless://uuid@host.com:443?security=tls#Base64Server"
        let base64 = Data(plain.utf8).base64EncodedString()
        let servers = SubscriptionManager.parseSubscriptionContent(base64)
        #expect(servers.count == 1)
        #expect(servers[0].name == "Base64Server")
    }

    @Test("Skips non-VLESS lines in subscription content")
    func skipsNonVlessLines() {
        let content = """
        # This is a comment
        vmess://some-vmess-server
        vless://uuid@valid.com:443#Valid
        ss://some-ss-server
        """
        let servers = SubscriptionManager.parseSubscriptionContent(content)
        #expect(servers.count == 1)
        #expect(servers[0].address == "valid.com")
    }

    @Test("Returns empty array for empty content")
    func emptyContent() {
        let servers = SubscriptionManager.parseSubscriptionContent("")
        #expect(servers.isEmpty)
    }

    @Test("Filters out private/loopback addresses from subscription")
    func filtersPrivateAddresses() {
        let content = """
        vless://uuid@127.0.0.1:443#Loopback
        vless://uuid@192.168.1.1:443#Private
        vless://uuid@10.0.0.1:443#Private10
        vless://uuid@public.com:443#Public
        """
        let servers = SubscriptionManager.parseSubscriptionContent(content)
        #expect(servers.count == 1)
        #expect(servers[0].address == "public.com")
    }
}
