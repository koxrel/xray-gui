import Foundation

public protocol ProxyManaging: Sendable {
    func getNetworkServices() async -> [String]
    func enableGlobalProxy(httpPort: Int, socksPort: Int) async
    func enablePacProxy(pacUrl: String) async
    func disableProxy() async
    func applyProxyMode(_ mode: ProxyMode, httpPort: Int, socksPort: Int, pacUrl: String) async
    func disableProxySync()
}
