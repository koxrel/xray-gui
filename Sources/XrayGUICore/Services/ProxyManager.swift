import Foundation

public final class DefaultProxyManager: ProxyManaging, Sendable {
    public init() {}

    public func getNetworkServices() async -> [String] {
        let output = await shell("-listallnetworkservices")
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
                    await self.shell("-setwebproxy", service, "127.0.0.1", "\(httpPort)")
                    await self.shell("-setsecurewebproxy", service, "127.0.0.1", "\(httpPort)")
                    await self.shell("-setsocksfirewallproxy", service, "127.0.0.1", "\(socksPort)")
                    await self.shell("-setwebproxystate", service, "on")
                    await self.shell("-setsecurewebproxystate", service, "on")
                    await self.shell("-setsocksfirewallproxystate", service, "on")
                }
            }
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
                    await self.shell("-setautoproxyurl", service, pacUrl)
                    await self.shell("-setautoproxystate", service, "on")
                    await self.shell("-setwebproxystate", service, "off")
                    await self.shell("-setsecurewebproxystate", service, "off")
                    await self.shell("-setsocksfirewallproxystate", service, "off")
                }
            }
        }
    }

    public func disableProxy() async {
        let services = await getNetworkServices()
        await withTaskGroup(of: Void.self) { group in
            for service in services {
                group.addTask {
                    await self.shell("-setwebproxystate", service, "off")
                    await self.shell("-setsecurewebproxystate", service, "off")
                    await self.shell("-setsocksfirewallproxystate", service, "off")
                    await self.shell("-setautoproxystate", service, "off")
                }
            }
        }
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

    @discardableResult
    private func shell(_ args: String...) async -> String {
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

    // MARK: - Synchronous cleanup for app termination

    public func disableProxySync() {
        let services = getNetworkServicesSync()
        for service in services {
            shellSync("-setwebproxystate", service, "off")
            shellSync("-setsecurewebproxystate", service, "off")
            shellSync("-setsocksfirewallproxystate", service, "off")
            shellSync("-setautoproxystate", service, "off")
        }
    }

    private func getNetworkServicesSync() -> [String] {
        shellSync("-listallnetworkservices")
            .components(separatedBy: "\n")
            .dropFirst()
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
    }

    @discardableResult
    private func shellSync(_ args: String...) -> String {
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
