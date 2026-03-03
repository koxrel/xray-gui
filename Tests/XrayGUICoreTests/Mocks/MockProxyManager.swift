import Foundation
@testable import XrayGUICore

/// A mock implementation of `ProxyManaging` for use in tests.
/// Records all method calls and supports configurable stubbed responses.
@MainActor
final class MockProxyManager: @preconcurrency ProxyManaging {

    // MARK: - Call Recording

    var enableGlobalProxyCalls: [(httpPort: Int, socksPort: Int)] = []
    var enablePacProxyCalls: [String] = []
    var disableProxyCallCount: Int = 0
    var disableProxySyncCallCount: Int = 0
    var applyProxyModeCalls: [(mode: ProxyMode, httpPort: Int, socksPort: Int, pacUrl: String)] = []
    var getNetworkServicesCallCount: Int = 0

    // MARK: - Stubbed Responses

    var stubbedNetworkServices: [String] = ["Wi-Fi", "Ethernet"]

    // MARK: - ProxyManaging

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
