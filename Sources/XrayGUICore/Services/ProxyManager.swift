import Foundation

protocol NetworkSetupExecuting: Sendable {
    func run(_ args: [String]) async -> String
    func runSync(_ args: [String]) -> String
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

private final class ProxySessionState: @unchecked Sendable {
    private let lock = NSLock()
    private var hasManagedSystemProxy = false

    var isManagingSystemProxy: Bool {
        lock.withLock { hasManagedSystemProxy }
    }

    func markManaged() {
        lock.withLock {
            hasManagedSystemProxy = true
        }
    }

    func clear() {
        lock.withLock {
            hasManagedSystemProxy = false
        }
    }
}

private struct NetworkSetupExecutor: NetworkSetupExecuting {
    func run(_ args: [String]) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                process.terminationHandler = { _ in
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                }
                try process.run()
            } catch {
                continuation.resume(returning: "")
            }
        }
    }

    func runSync(_ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

public final class DefaultProxyManager: ProxyManaging, Sendable {
    private let executor: any NetworkSetupExecuting
    private let sessionState: ProxySessionState

    public convenience init() {
        self.init(executor: NetworkSetupExecutor())
    }

    init(executor: any NetworkSetupExecuting) {
        self.executor = executor
        self.sessionState = ProxySessionState()
    }

    public func getNetworkServices() async -> [String] {
        let output = await executor.run(["-listallnetworkservices"])
        return output
            .components(separatedBy: "\n")
            .dropFirst() // Skip header line
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
    }

    public func enableGlobalProxy(httpPort: Int, socksPort: Int) async {
        let services = await getNetworkServices()
        await withTaskGroup(of: Void.self) { group in
            for service in services {
                group.addTask {
                    _ = await self.executor.run(["-setwebproxy", service, "127.0.0.1", "\(httpPort)"])
                    _ = await self.executor.run(["-setsecurewebproxy", service, "127.0.0.1", "\(httpPort)"])
                    _ = await self.executor.run(["-setsocksfirewallproxy", service, "127.0.0.1", "\(socksPort)"])
                    _ = await self.executor.run(["-setwebproxystate", service, "on"])
                    _ = await self.executor.run(["-setsecurewebproxystate", service, "on"])
                    _ = await self.executor.run(["-setsocksfirewallproxystate", service, "on"])
                }
            }
        }
        if !services.isEmpty {
            sessionState.markManaged()
        }
    }

    public func enablePacProxy(pacUrl: String) async {
        // Validate PAC URL scheme -- only http/https allowed
        guard let url = URL(string: pacUrl),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return
        }

        let services = await getNetworkServices()
        await withTaskGroup(of: Void.self) { group in
            for service in services {
                group.addTask {
                    _ = await self.executor.run(["-setautoproxyurl", service, pacUrl])
                    _ = await self.executor.run(["-setautoproxystate", service, "on"])
                    _ = await self.executor.run(["-setwebproxystate", service, "off"])
                    _ = await self.executor.run(["-setsecurewebproxystate", service, "off"])
                    _ = await self.executor.run(["-setsocksfirewallproxystate", service, "off"])
                }
            }
        }
        if !services.isEmpty {
            sessionState.markManaged()
        }
    }

    public func disableProxy() async {
        guard sessionState.isManagingSystemProxy else { return }
        let services = await getNetworkServices()
        await withTaskGroup(of: Void.self) { group in
            for service in services {
                group.addTask {
                    _ = await self.executor.run(["-setwebproxystate", service, "off"])
                    _ = await self.executor.run(["-setsecurewebproxystate", service, "off"])
                    _ = await self.executor.run(["-setsocksfirewallproxystate", service, "off"])
                    _ = await self.executor.run(["-setautoproxystate", service, "off"])
                }
            }
        }
        sessionState.clear()
    }

    public func applyProxyMode(_ mode: ProxyMode, httpPort: Int, socksPort: Int, pacUrl: String) async {
        switch mode {
        case .global:
            await enableGlobalProxy(httpPort: httpPort, socksPort: socksPort)
        case .pac:
            await enablePacProxy(pacUrl: pacUrl)
        case .manual:
            await disableProxy()
        }
    }

    // MARK: - Synchronous cleanup for app termination

    public func disableProxySync() {
        guard sessionState.isManagingSystemProxy else { return }
        let services = getNetworkServicesSync()
        let group = DispatchGroup()

        for service in services {
            group.enter()
            DispatchQueue.global().async {
                _ = self.executor.runSync(["-setwebproxystate", service, "off"])
                _ = self.executor.runSync(["-setsecurewebproxystate", service, "off"])
                _ = self.executor.runSync(["-setsocksfirewallproxystate", service, "off"])
                _ = self.executor.runSync(["-setautoproxystate", service, "off"])
                group.leave()
            }
        }

        group.wait()
        sessionState.clear()
    }

    private func getNetworkServicesSync() -> [String] {
        executor.runSync(["-listallnetworkservices"])
            .components(separatedBy: "\n")
            .dropFirst()
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
    }
}
