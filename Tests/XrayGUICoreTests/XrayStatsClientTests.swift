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
}
