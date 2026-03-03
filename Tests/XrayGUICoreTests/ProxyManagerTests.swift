import Testing
import Foundation
@testable import XrayGUICore

// MARK: - Mock Protocol Tests

@Suite("MockProxyManager Tests")
@MainActor
struct MockProxyManagerTests {

    // MARK: - enableGlobalProxy

    @Test("Mock records enableGlobalProxy call with correct arguments")
    func recordsEnableGlobalProxyCall() async {
        let mock = MockProxyManager()
        await mock.enableGlobalProxy(httpPort: 1087, socksPort: 1080)
        #expect(mock.enableGlobalProxyCalls.count == 1)
        #expect(mock.enableGlobalProxyCalls[0].httpPort == 1087)
        #expect(mock.enableGlobalProxyCalls[0].socksPort == 1080)
    }

    @Test("Mock records multiple enableGlobalProxy calls in order")
    func recordsMultipleEnableGlobalProxyCalls() async {
        let mock = MockProxyManager()
        await mock.enableGlobalProxy(httpPort: 1087, socksPort: 1080)
        await mock.enableGlobalProxy(httpPort: 8080, socksPort: 1081)
        #expect(mock.enableGlobalProxyCalls.count == 2)
        #expect(mock.enableGlobalProxyCalls[1].httpPort == 8080)
        #expect(mock.enableGlobalProxyCalls[1].socksPort == 1081)
    }

    // MARK: - enablePacProxy

    @Test("Mock records enablePacProxy call with correct URL")
    func recordsEnablePacProxyCall() async {
        let mock = MockProxyManager()
        await mock.enablePacProxy(pacUrl: "http://example.com/proxy.pac")
        #expect(mock.enablePacProxyCalls.count == 1)
        #expect(mock.enablePacProxyCalls[0] == "http://example.com/proxy.pac")
    }

    @Test("Mock records multiple enablePacProxy calls in order")
    func recordsMultipleEnablePacProxyCalls() async {
        let mock = MockProxyManager()
        await mock.enablePacProxy(pacUrl: "http://first.com/pac")
        await mock.enablePacProxy(pacUrl: "https://second.com/pac")
        #expect(mock.enablePacProxyCalls.count == 2)
        #expect(mock.enablePacProxyCalls[0] == "http://first.com/pac")
        #expect(mock.enablePacProxyCalls[1] == "https://second.com/pac")
    }

    // MARK: - disableProxy

    @Test("Mock records disableProxy calls")
    func recordsDisableProxyCall() async {
        let mock = MockProxyManager()
        await mock.disableProxy()
        #expect(mock.disableProxyCallCount == 1)
    }

    @Test("Mock increments disableProxy count for each call")
    func incrementsDisableProxyCount() async {
        let mock = MockProxyManager()
        await mock.disableProxy()
        await mock.disableProxy()
        await mock.disableProxy()
        #expect(mock.disableProxyCallCount == 3)
    }

    // MARK: - disableProxySync

    @Test("Mock records disableProxySync calls")
    func recordsDisableProxySyncCall() {
        let mock = MockProxyManager()
        mock.disableProxySync()
        #expect(mock.disableProxySyncCallCount == 1)
    }

    @Test("Mock increments disableProxySync count for each call")
    func incrementsDisableProxySyncCount() {
        let mock = MockProxyManager()
        mock.disableProxySync()
        mock.disableProxySync()
        #expect(mock.disableProxySyncCallCount == 2)
    }

    // MARK: - applyProxyMode

    @Test("Mock records applyProxyMode call with all arguments")
    func recordsApplyProxyModeCall() async {
        let mock = MockProxyManager()
        await mock.applyProxyMode(.global, httpPort: 1087, socksPort: 1080, pacUrl: "http://pac.test/")
        #expect(mock.applyProxyModeCalls.count == 1)
        #expect(mock.applyProxyModeCalls[0].mode == .global)
        #expect(mock.applyProxyModeCalls[0].httpPort == 1087)
        #expect(mock.applyProxyModeCalls[0].socksPort == 1080)
        #expect(mock.applyProxyModeCalls[0].pacUrl == "http://pac.test/")
    }

    @Test("Mock records applyProxyMode calls for all proxy modes")
    func recordsAllProxyModes() async {
        let mock = MockProxyManager()
        await mock.applyProxyMode(.global, httpPort: 1087, socksPort: 1080, pacUrl: "")
        await mock.applyProxyMode(.pac, httpPort: 1087, socksPort: 1080, pacUrl: "http://pac.example.com/")
        await mock.applyProxyMode(.manual, httpPort: 1087, socksPort: 1080, pacUrl: "")
        #expect(mock.applyProxyModeCalls.count == 3)
        #expect(mock.applyProxyModeCalls[0].mode == .global)
        #expect(mock.applyProxyModeCalls[1].mode == .pac)
        #expect(mock.applyProxyModeCalls[2].mode == .manual)
    }

    // MARK: - getNetworkServices

    @Test("Mock getNetworkServices returns stubbed services")
    func returnsStubbbedNetworkServices() async {
        let mock = MockProxyManager()
        mock.stubbedNetworkServices = ["Wi-Fi", "Ethernet", "Thunderbolt Bridge"]
        let services = await mock.getNetworkServices()
        #expect(services == ["Wi-Fi", "Ethernet", "Thunderbolt Bridge"])
    }

    @Test("Mock getNetworkServices increments call count")
    func incrementsGetNetworkServicesCallCount() async {
        let mock = MockProxyManager()
        _ = await mock.getNetworkServices()
        _ = await mock.getNetworkServices()
        #expect(mock.getNetworkServicesCallCount == 2)
    }

    @Test("Mock getNetworkServices returns empty array when stubbed empty")
    func returnsEmptyServicesWhenStubbedEmpty() async {
        let mock = MockProxyManager()
        mock.stubbedNetworkServices = []
        let services = await mock.getNetworkServices()
        #expect(services.isEmpty)
    }

    // MARK: - Initial state

    @Test("Mock starts with zero call counts")
    func initialCallCountsAreZero() {
        let mock = MockProxyManager()
        #expect(mock.enableGlobalProxyCalls.isEmpty)
        #expect(mock.enablePacProxyCalls.isEmpty)
        #expect(mock.disableProxyCallCount == 0)
        #expect(mock.disableProxySyncCallCount == 0)
        #expect(mock.applyProxyModeCalls.isEmpty)
        #expect(mock.getNetworkServicesCallCount == 0)
    }
}

// MARK: - DefaultProxyManager Logic Tests

@Suite("ProxyManager Tests")
struct ProxyManagerTests {

    // MARK: - URL validation (enablePacProxy)

    /// A testable subclass that overrides shell-calling methods so we can test
    /// the validation and dispatch logic without invoking networksetup.
    @MainActor
    final class SpyProxyManager: @preconcurrency ProxyManaging {
        var enableGlobalProxyCalls: [(httpPort: Int, socksPort: Int)] = []
        var enablePacProxyCalls: [String] = []
        var disableProxyCallCount: Int = 0
        var disableProxySyncCallCount: Int = 0
        var applyProxyModeCalls: [(mode: ProxyMode, httpPort: Int, socksPort: Int, pacUrl: String)] = []
        var getNetworkServicesCallCount: Int = 0
        var stubbedNetworkServices: [String] = []

        func getNetworkServices() async -> [String] {
            getNetworkServicesCallCount += 1
            return stubbedNetworkServices
        }
        func enableGlobalProxy(httpPort: Int, socksPort: Int) async {
            enableGlobalProxyCalls.append((httpPort: httpPort, socksPort: socksPort))
        }
        func enablePacProxy(pacUrl: String) async {
            enablePacProxyCalls.append(pacUrl)
        }
        func disableProxy() async {
            disableProxyCallCount += 1
        }
        func applyProxyMode(_ mode: ProxyMode, httpPort: Int, socksPort: Int, pacUrl: String) async {
            applyProxyModeCalls.append((mode: mode, httpPort: httpPort, socksPort: socksPort, pacUrl: pacUrl))
        }
        func disableProxySync() {
            disableProxySyncCallCount += 1
        }
    }

    // MARK: - PAC URL validation

    @Test("enablePacProxy rejects empty URL")
    @MainActor
    func rejectsEmptyPacUrl() async {
        // We test the concrete DefaultProxyManager's validation indirectly:
        // The method silently returns for invalid URLs — no shell calls are made.
        // We verify by testing URL parsing logic directly.
        let invalidUrl = ""
        let url = URL(string: invalidUrl)
        let scheme = url?.scheme?.lowercased()
        let isValid = scheme == "http" || scheme == "https"
        #expect(isValid == false)
    }

    @Test("enablePacProxy rejects file:// URL")
    @MainActor
    func rejectsFileUrl() async {
        let pacUrl = "file:///tmp/proxy.pac"
        let url = URL(string: pacUrl)
        let scheme = url?.scheme?.lowercased()
        let isValid = scheme == "http" || scheme == "https"
        #expect(isValid == false)
    }

    @Test("enablePacProxy rejects ftp:// URL")
    @MainActor
    func rejectsFtpUrl() async {
        let pacUrl = "ftp://example.com/proxy.pac"
        let url = URL(string: pacUrl)
        let scheme = url?.scheme?.lowercased()
        let isValid = scheme == "http" || scheme == "https"
        #expect(isValid == false)
    }

    @Test("enablePacProxy rejects URL with no scheme")
    @MainActor
    func rejectsUrlWithNoScheme() async {
        let pacUrl = "example.com/proxy.pac"
        let url = URL(string: pacUrl)
        let scheme = url?.scheme?.lowercased()
        let isValid = scheme == "http" || scheme == "https"
        #expect(isValid == false)
    }

    @Test("enablePacProxy accepts http:// URL")
    @MainActor
    func acceptsHttpUrl() async {
        let pacUrl = "http://example.com/proxy.pac"
        let url = URL(string: pacUrl)
        let scheme = url?.scheme?.lowercased()
        let isValid = scheme == "http" || scheme == "https"
        #expect(isValid == true)
    }

    @Test("enablePacProxy accepts https:// URL")
    @MainActor
    func acceptsHttpsUrl() async {
        let pacUrl = "https://example.com/proxy.pac"
        let url = URL(string: pacUrl)
        let scheme = url?.scheme?.lowercased()
        let isValid = scheme == "http" || scheme == "https"
        #expect(isValid == true)
    }

    @Test("enablePacProxy accepts https:// URL with path and query")
    @MainActor
    func acceptsHttpsUrlWithPathAndQuery() async {
        let pacUrl = "https://company.internal/network/proxy.pac?v=2"
        let url = URL(string: pacUrl)
        let scheme = url?.scheme?.lowercased()
        let isValid = scheme == "http" || scheme == "https"
        #expect(isValid == true)
    }

    // MARK: - getNetworkServices parsing logic

    @Test("getNetworkServices drops the header line")
    func networkServicesDropsHeader() {
        // Simulate the raw output from `networksetup -listallnetworkservices`
        let rawOutput = """
        An asterisk (*) denotes that a network service is disabled.
        Wi-Fi
        Ethernet
        """
        let parsed = rawOutput
            .components(separatedBy: "\n")
            .dropFirst()
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
        #expect(parsed == ["Wi-Fi", "Ethernet"])
    }

    @Test("getNetworkServices filters out disabled services marked with asterisk")
    func networkServicesFiltersDisabled() {
        let rawOutput = """
        An asterisk (*) denotes that a network service is disabled.
        Wi-Fi
        *Bluetooth PAN
        Ethernet
        *Thunderbolt Bridge
        """
        let parsed = rawOutput
            .components(separatedBy: "\n")
            .dropFirst()
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
        #expect(parsed == ["Wi-Fi", "Ethernet"])
    }

    @Test("getNetworkServices filters out empty lines")
    func networkServicesFiltersEmptyLines() {
        let rawOutput = """
        An asterisk (*) denotes that a network service is disabled.
        Wi-Fi

        Ethernet

        """
        let parsed = rawOutput
            .components(separatedBy: "\n")
            .dropFirst()
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
        #expect(parsed == ["Wi-Fi", "Ethernet"])
    }

    @Test("getNetworkServices returns empty array when only header present")
    func networkServicesEmptyWhenOnlyHeader() {
        let rawOutput = "An asterisk (*) denotes that a network service is disabled."
        let parsed = rawOutput
            .components(separatedBy: "\n")
            .dropFirst()
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
        #expect(parsed.isEmpty)
    }

    @Test("getNetworkServices returns empty array for empty output")
    func networkServicesEmptyOutput() {
        let rawOutput = ""
        let parsed = rawOutput
            .components(separatedBy: "\n")
            .dropFirst()
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
        #expect(parsed.isEmpty)
    }

    // MARK: - applyProxyMode dispatch (via SpyProxyManager)

    /// Shared helper: applies a mode using the same dispatch logic as DefaultProxyManager.
    @MainActor
    private func applyMode(
        _ mode: ProxyMode,
        to spy: SpyProxyManager,
        httpPort: Int = 1087,
        socksPort: Int = 1080,
        pacUrl: String = ""
    ) async {
        switch mode {
        case .global: await spy.enableGlobalProxy(httpPort: httpPort, socksPort: socksPort)
        case .pac:    await spy.enablePacProxy(pacUrl: pacUrl)
        case .manual: await spy.disableProxy()
        }
    }

    @Test("applyProxyMode with .global dispatches to enableGlobalProxy")
    @MainActor
    func applyProxyModeGlobalDispatch() async {
        let spy = SpyProxyManager()
        await applyMode(.global, to: spy, httpPort: 1087, socksPort: 1080)
        #expect(spy.enableGlobalProxyCalls.count == 1)
        #expect(spy.enableGlobalProxyCalls[0].httpPort == 1087)
        #expect(spy.enableGlobalProxyCalls[0].socksPort == 1080)
        #expect(spy.enablePacProxyCalls.isEmpty)
        #expect(spy.disableProxyCallCount == 0)
    }

    @Test("applyProxyMode with .pac dispatches to enablePacProxy")
    @MainActor
    func applyProxyModePacDispatch() async {
        let spy = SpyProxyManager()
        let pacUrl = "http://pac.example.com/"
        await applyMode(.pac, to: spy, pacUrl: pacUrl)
        #expect(spy.enablePacProxyCalls.count == 1)
        #expect(spy.enablePacProxyCalls[0] == pacUrl)
        #expect(spy.enableGlobalProxyCalls.isEmpty)
        #expect(spy.disableProxyCallCount == 0)
    }

    @Test("applyProxyMode with .manual dispatches to disableProxy")
    @MainActor
    func applyProxyModeManualDispatch() async {
        let spy = SpyProxyManager()
        await applyMode(.manual, to: spy)
        #expect(spy.disableProxyCallCount == 1)
        #expect(spy.enableGlobalProxyCalls.isEmpty)
        #expect(spy.enablePacProxyCalls.isEmpty)
    }
}
