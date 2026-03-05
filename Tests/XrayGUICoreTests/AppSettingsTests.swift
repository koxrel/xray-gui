import Testing
import Foundation
@testable import XrayGUICore

@Suite("AppSettings Tests")
struct AppSettingsTests {

    // MARK: - Default Values

    @Test("Default settings have expected values")
    func defaultValues() {
        let settings = AppSettings.default
        #expect(settings.httpPort == 1087)
        #expect(settings.socksPort == 1080)
        #expect(settings.allowLan == false)
        #expect(settings.proxyMode == .global)
        #expect(settings.autoStart == false)
        #expect(settings.logLevel == .warning)
        #expect(settings.enableMux == false)
        #expect(settings.muxConcurrency == 8)
        #expect(settings.dnsServers == ["1.1.1.1", "8.8.8.8"])
        #expect(settings.dnsMode == .plain)
        #expect(settings.dohServer == "https://1.1.1.1/dns-query")
        #expect(settings.bypassDomains == ["localhost", "127.0.0.1", "*.local"])
        #expect(settings.blockedDomains == ["geosite:category-ads-all"])
        #expect(settings.theme == .system)
        #expect(settings.activeServerId == nil)
    }

    // MARK: - Codable Round-trip

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = AppSettings(
            httpPort: 2087,
            socksPort: 2080,
            allowLan: true,
            proxyMode: .pac,
            pacUrl: "http://example.com/pac",
            autoStart: true,
            logLevel: .debug,
            dnsServers: ["9.9.9.9"],
            enableMux: true,
            muxConcurrency: 16,
            bypassDomains: ["mysite.local"],
            directDomains: ["direct.com"],
            blockedDomains: ["ads.com"],
            activeServerId: "server-1",
            theme: .dark
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded == original)
    }

    // MARK: - Resilient Decoding

    @Test("Decoding from empty JSON uses defaults")
    func decodingEmptyJson() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        #expect(settings.httpPort == 1087)
        #expect(settings.socksPort == 1080)
        #expect(settings.proxyMode == .global)
        #expect(settings.logLevel == .warning)
        #expect(settings.theme == .system)
    }

    @Test("Decoding handles unknown enum values gracefully")
    func decodingUnknownEnum() throws {
        let json = Data("""
        {"proxyMode": "unknown_mode", "logLevel": "extreme", "theme": "neon"}
        """.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        // Unknown values should fall back to defaults
        #expect(settings.proxyMode == .global)
        #expect(settings.logLevel == .warning)
        #expect(settings.theme == .system)
    }

    // MARK: - needsProxyRestart

    @Test("needsProxyRestart returns false for identical settings")
    func noRestartForSameSettings() {
        let settings = AppSettings.default
        #expect(settings.needsProxyRestart(comparedTo: settings) == false)
    }

    @Test("needsProxyRestart returns true when httpPort changes")
    func restartOnHttpPortChange() {
        let a = AppSettings.default
        var b = a
        b.httpPort = 9999
        #expect(a.needsProxyRestart(comparedTo: b) == true)
    }

    @Test("needsProxyRestart returns true when socksPort changes")
    func restartOnSocksPortChange() {
        let a = AppSettings.default
        var b = a
        b.socksPort = 9999
        #expect(a.needsProxyRestart(comparedTo: b) == true)
    }

    @Test("needsProxyRestart returns true when allowLan changes")
    func restartOnAllowLanChange() {
        let a = AppSettings.default
        var b = a
        b.allowLan = true
        #expect(a.needsProxyRestart(comparedTo: b) == true)
    }

    @Test("needsProxyRestart returns true when logLevel changes")
    func restartOnLogLevelChange() {
        let a = AppSettings.default
        var b = a
        b.logLevel = .debug
        #expect(a.needsProxyRestart(comparedTo: b) == true)
    }

    @Test("needsProxyRestart returns true when DNS servers change")
    func restartOnDnsChange() {
        let a = AppSettings.default
        var b = a
        b.dnsServers = ["9.9.9.9"]
        #expect(a.needsProxyRestart(comparedTo: b) == true)
    }

    @Test("needsProxyRestart returns false when only theme changes")
    func noRestartOnThemeChange() {
        let a = AppSettings.default
        var b = a
        b.theme = .dark
        #expect(a.needsProxyRestart(comparedTo: b) == false)
    }

    @Test("needsProxyRestart returns false when only proxyMode changes")
    func noRestartOnProxyModeChange() {
        let a = AppSettings.default
        var b = a
        b.proxyMode = .pac
        #expect(a.needsProxyRestart(comparedTo: b) == false)
    }

    @Test("needsProxyRestart returns false when only autoStart changes")
    func noRestartOnAutoStartChange() {
        let a = AppSettings.default
        var b = a
        b.autoStart = true
        #expect(a.needsProxyRestart(comparedTo: b) == false)
    }

    @Test("needsProxyRestart returns true when enableMux changes")
    func restartOnEnableMuxChange() {
        let a = AppSettings.default
        var b = a
        b.enableMux = true
        #expect(a.needsProxyRestart(comparedTo: b) == true)
    }

    @Test("needsProxyRestart returns true when muxConcurrency changes")
    func restartOnMuxConcurrencyChange() {
        let a = AppSettings.default
        var b = a
        b.muxConcurrency = 16
        #expect(a.needsProxyRestart(comparedTo: b) == true)
    }

    @Test("needsProxyRestart returns true when bypassDomains change")
    func restartOnBypassDomainsChange() {
        let a = AppSettings.default
        var b = a
        b.bypassDomains = ["newsite.local"]
        #expect(a.needsProxyRestart(comparedTo: b) == true)
    }

    @Test("needsProxyRestart returns true when directDomains change")
    func restartOnDirectDomainsChange() {
        let a = AppSettings.default
        var b = a
        b.directDomains = ["direct.example.com"]
        #expect(a.needsProxyRestart(comparedTo: b) == true)
    }

    @Test("needsProxyRestart returns true when blockedDomains change")
    func restartOnBlockedDomainsChange() {
        let a = AppSettings.default
        var b = a
        b.blockedDomains = ["ads.blocked.com"]
        #expect(a.needsProxyRestart(comparedTo: b) == true)
    }

    @Test("needsProxyRestart returns true when dnsMode changes")
    func restartOnDnsModeChange() {
        let a = AppSettings.default
        var b = a
        b.dnsMode = .doh
        #expect(a.needsProxyRestart(comparedTo: b) == true)
    }

    @Test("needsProxyRestart returns true when dohServer changes")
    func restartOnDohServerChange() {
        let a = AppSettings.default
        var b = a
        b.dohServer = "https://8.8.8.8/dns-query"
        #expect(a.needsProxyRestart(comparedTo: b) == true)
    }

    @Test("needsProxyRestart returns false when only pacUrl changes")
    func noRestartOnPacUrlChange() {
        let a = AppSettings.default
        var b = a
        b.pacUrl = "http://example.com/proxy.pac"
        #expect(a.needsProxyRestart(comparedTo: b) == false)
    }

    @Test("needsProxyRestart returns false when only activeServerId changes")
    func noRestartOnActiveServerIdChange() {
        let a = AppSettings.default
        var b = a
        b.activeServerId = "some-server-id"
        #expect(a.needsProxyRestart(comparedTo: b) == false)
    }

    // MARK: - Enums

    @Test("ProxyMode displayName values")
    func proxyModeDisplayNames() {
        #expect(ProxyMode.global.displayName == "Global")
        #expect(ProxyMode.pac.displayName == "PAC")
        #expect(ProxyMode.manual.displayName == "Manual")
    }

    @Test("ProxyMode has 3 cases")
    func proxyModeCases() {
        #expect(ProxyMode.allCases.count == 3)
    }

    @Test("LogLevel has 5 cases")
    func logLevelCases() {
        #expect(LogLevel.allCases.count == 5)
    }

    @Test("AppTheme has 3 cases")
    func appThemeCases() {
        #expect(AppTheme.allCases.count == 3)
    }

    // MARK: - DNS Mode & DoH

    @Test("DNSMode has 2 cases")
    func dnsModeCases() {
        #expect(DNSMode.allCases.count == 2)
    }

    @Test("DNSMode displayName values")
    func dnsModeDisplayNames() {
        #expect(DNSMode.plain.displayName == "Plain DNS")
        #expect(DNSMode.doh.displayName == "DNS over HTTPS")
    }

    @Test("Decoding JSON without dnsMode/dohServer uses defaults")
    func decodingMissingDnsFields() throws {
        let json = Data("""
        {"httpPort": 1087, "socksPort": 1080}
        """.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        #expect(settings.dnsMode == .plain)
        #expect(settings.dohServer == "https://1.1.1.1/dns-query")
    }

    @Test("Codable round-trip preserves dnsMode and dohServer")
    func codableRoundTripDns() throws {
        var original = AppSettings.default
        original.dnsMode = .doh
        original.dohServer = "https://9.9.9.9/dns-query"
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.dnsMode == .doh)
        #expect(decoded.dohServer == "https://9.9.9.9/dns-query")
    }

    @Test("DoHPreset.from reverse-maps known URLs correctly")
    func dohPresetFromUrl() {
        #expect(DoHPreset.from(url: "https://1.1.1.1/dns-query") == .cloudflare)
        #expect(DoHPreset.from(url: "https://8.8.8.8/dns-query") == .google)
        #expect(DoHPreset.from(url: "https://9.9.9.9/dns-query") == .quad9)
        #expect(DoHPreset.from(url: "https://custom.example.com/dns-query") == .custom)
    }

    @Test("DoHPreset.from trims whitespace before matching")
    func dohPresetFromUrlWhitespace() {
        #expect(DoHPreset.from(url: "  https://1.1.1.1/dns-query  ") == .cloudflare)
        #expect(DoHPreset.from(url: "https://8.8.8.8/dns-query\n") == .google)
    }
}
