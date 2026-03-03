import Testing
import Foundation
@testable import XrayGUICore

@Suite("Subscription Tests")
struct SubscriptionTests {

    // MARK: - Default Init

    @Test("Default init uses empty strings and sensible defaults")
    func defaultInit() {
        let sub = Subscription()
        #expect(sub.name == "")
        #expect(sub.url == "")
        #expect(sub.serverIds.isEmpty)
        #expect(sub.lastUpdated == nil)
        #expect(sub.autoUpdate == true)
        #expect(sub.autoUpdateIntervalHours == 24)
        #expect(!sub.id.isEmpty) // UUID auto-generated
    }

    // MARK: - Codable Round-trip

    @Test("Codable round-trip preserves all fields including nil lastUpdated")
    func codableRoundTripWithNilLastUpdated() throws {
        let original = Subscription(
            id: "sub-1",
            name: "My Sub",
            url: "https://example.com/sub",
            serverIds: ["s1", "s2"],
            lastUpdated: nil,
            autoUpdate: true,
            autoUpdateIntervalHours: 12
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Subscription.self, from: data)

        #expect(decoded == original)
        #expect(decoded.lastUpdated == nil)
    }

    @Test("Codable round-trip preserves lastUpdated when set")
    func codableRoundTripWithLastUpdated() throws {
        let timestamp = "2026-03-03T10:00:00Z"
        let original = Subscription(
            id: "sub-2",
            name: "Updated Sub",
            url: "https://example.com",
            serverIds: [],
            lastUpdated: timestamp,
            autoUpdate: false,
            autoUpdateIntervalHours: 48
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Subscription.self, from: data)

        #expect(decoded.lastUpdated == timestamp)
        #expect(decoded.autoUpdate == false)
        #expect(decoded.autoUpdateIntervalHours == 48)
    }

    // MARK: - Resilient Decoding

    @Test("Decoding from empty JSON object uses all defaults")
    func decodingEmptyJson() throws {
        let json = Data("{}".utf8)
        let sub = try JSONDecoder().decode(Subscription.self, from: json)

        #expect(sub.name == "")
        #expect(sub.url == "")
        #expect(sub.serverIds.isEmpty)
        #expect(sub.lastUpdated == nil)
        #expect(sub.autoUpdate == true)
        #expect(sub.autoUpdateIntervalHours == 24)
        #expect(!sub.id.isEmpty)
    }

    @Test("Decoding partial JSON fills missing fields with defaults")
    func decodingPartialJson() throws {
        let json = Data("""
        {"id": "sub-x", "name": "Partial", "url": "https://partial.com"}
        """.utf8)
        let sub = try JSONDecoder().decode(Subscription.self, from: json)

        #expect(sub.id == "sub-x")
        #expect(sub.name == "Partial")
        #expect(sub.autoUpdate == true)
        #expect(sub.autoUpdateIntervalHours == 24)
        #expect(sub.serverIds.isEmpty)
    }

    @Test("Decoding preserves populated serverIds array")
    func decodingServerIds() throws {
        let json = Data("""
        {"id": "s", "serverIds": ["a", "b", "c"]}
        """.utf8)
        let sub = try JSONDecoder().decode(Subscription.self, from: json)
        #expect(sub.serverIds == ["a", "b", "c"])
    }

    // MARK: - Equatable

    @Test("Same-field subscriptions are equal")
    func equality() {
        let a = Subscription(id: "s", name: "N", url: "https://u.com", serverIds: ["x"], lastUpdated: nil, autoUpdate: true, autoUpdateIntervalHours: 24)
        let b = Subscription(id: "s", name: "N", url: "https://u.com", serverIds: ["x"], lastUpdated: nil, autoUpdate: true, autoUpdateIntervalHours: 24)
        #expect(a == b)
    }

    @Test("Different IDs are not equal")
    func inequalityById() {
        let a = Subscription(id: "a", name: "N", url: "u")
        let b = Subscription(id: "b", name: "N", url: "u")
        #expect(a != b)
    }

    @Test("Different lastUpdated values are not equal")
    func inequalityByLastUpdated() {
        let a = Subscription(id: "s", name: "N", url: "u", lastUpdated: nil)
        let b = Subscription(id: "s", name: "N", url: "u", lastUpdated: "2026-01-01")
        #expect(a != b)
    }

    @Test("Different serverIds arrays are not equal")
    func inequalityByServerIds() {
        let a = Subscription(id: "s", name: "N", url: "u", serverIds: ["x"])
        let b = Subscription(id: "s", name: "N", url: "u", serverIds: ["y"])
        #expect(a != b)
    }
}
