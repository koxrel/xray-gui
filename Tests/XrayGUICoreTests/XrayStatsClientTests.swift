import Foundation
import Testing
@testable import XrayGUICore

@Suite("XrayStatsClient Tests")
struct XrayStatsClientTests {

    @Test("parseStatsQueryResponse sums HTTP and SOCKS inbound traffic counters")
    func parseSumsInboundTraffic() throws {
        let json = """
        {
          "stat": [
            {
              "name": "inbound>>>http-in>>>traffic>>>uplink",
              "value": "128"
            },
            {
              "name": "inbound>>>http-in>>>traffic>>>downlink",
              "value": "512"
            },
            {
              "name": "inbound>>>socks-in>>>traffic>>>uplink",
              "value": "256"
            },
            {
              "name": "inbound>>>socks-in>>>traffic>>>downlink",
              "value": "1024"
            }
          ]
        }
        """

        let stats = try XrayStatsClient.parseStatsQueryResponse(json)

        #expect(stats.uplinkBytes == 384)
        #expect(stats.downlinkBytes == 1536)
    }

    @Test("parseStatsQueryResponse treats missing counters as zero")
    func parseMissingCountersAsZero() throws {
        let json = """
        {
          "stat": [
            {
              "name": "inbound>>>http-in>>>traffic>>>uplink",
              "value": "64"
            }
          ]
        }
        """

        let stats = try XrayStatsClient.parseStatsQueryResponse(json)

        #expect(stats.uplinkBytes == 64)
        #expect(stats.downlinkBytes == 0)
    }

    @Test("parseStatsQueryResponse throws for malformed JSON")
    func parseInvalidJsonThrows() {
        #expect(throws: XrayStatsError.self) {
            try XrayStatsClient.parseStatsQueryResponse("not-json")
        }
    }

    /// Regression: Xray serializes stats as protobuf JSON, which OMITS the
    /// `value` field entirely for zero-valued counters. A single idle counter
    /// (no `value` key) must be treated as 0, not fail the whole response —
    /// otherwise every tunnel reads as "Stats unavailable". This is the exact
    /// shape captured from a live `xray api statsquery` with idle inbounds.
    @Test("parseStatsQueryResponse treats omitted value field as zero")
    func parseOmittedValueFieldAsZero() throws {
        let json = """
        {
          "stat": [
            { "name": "inbound>>>http-in>>>traffic>>>uplink", "value": 277 },
            { "name": "inbound>>>http-in>>>traffic>>>downlink" },
            { "name": "inbound>>>socks-in>>>traffic>>>uplink" },
            { "name": "inbound>>>socks-in>>>traffic>>>downlink" }
          ]
        }
        """

        let stats = try XrayStatsClient.parseStatsQueryResponse(json)

        #expect(stats.uplinkBytes == 277)
        #expect(stats.downlinkBytes == 0)
    }

    @Test("parseStatsQueryResponse accepts numeric (non-string) values")
    func parseNumericValues() throws {
        let json = """
        {
          "stat": [
            { "name": "inbound>>>http-in>>>traffic>>>uplink", "value": 1000 },
            { "name": "inbound>>>socks-in>>>traffic>>>downlink", "value": 2000 }
          ]
        }
        """

        let stats = try XrayStatsClient.parseStatsQueryResponse(json)

        #expect(stats.uplinkBytes == 1000)
        #expect(stats.downlinkBytes == 2000)
    }
}
