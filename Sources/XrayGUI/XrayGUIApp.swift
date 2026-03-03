import SwiftUI
import AppKit
import XrayGUICore

@main
struct XrayGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Main window
        Window("Xray GUI", id: "main") {
            ContentView()
                .environment(appState)
                .frame(minWidth: 700, minHeight: 500)
                .preferredColorScheme(appState.settings.theme.colorScheme)
                .onAppear {
                    // Hide dock icon — this is a menu bar app
                    NSApp.setActivationPolicy(.accessory)
                    appDelegate.appState = appState
                }
        }
        .defaultSize(width: 800, height: 600)

        // Menu bar extra (tray)
        MenuBarExtra {
            TrayMenuView(openDashboard: {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            })
            .environment(appState)
        } label: {
            Image(nsImage: TrayIcon.create(connected: appState.proxyStatus.running))
        }
    }
}

// MARK: - App Delegate for lifecycle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Show main window when dock icon clicked (if visible)
            for window in sender.windows {
                if window.identifier?.rawValue == "main" {
                    window.makeKeyAndOrderFront(nil)
                    return true
                }
            }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let appState else { return }
        appState.xrayManager.terminateAllSync()
        appState.proxyManager.disableProxySync()
    }
}

// MARK: - Tray Menu View

struct TrayMenuView: View {
    @Environment(AppState.self) private var appState
    let openDashboard: () -> Void

    var body: some View {
        // Connection toggle
        Button(appState.proxyStatus.running ? "Disconnect" : "Connect") {
            Task {
                do {
                    if appState.proxyStatus.running {
                        try await appState.stopProxy()
                    } else {
                        try await appState.startProxy()
                    }
                } catch {
                    appState.appendLog("[Error] \(error.localizedDescription)")
                }
            }
        }
        .keyboardShortcut("c", modifiers: [.command])

        Divider()

        // Proxy Mode
        Menu("Proxy Mode") {
            ForEach(ProxyMode.allCases, id: \.self) { mode in
                Button {
                    Task { await appState.setProxyMode(mode) }
                } label: {
                    HStack {
                        Text(mode.displayName)
                        if appState.proxyStatus.proxyMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        // Servers submenu grouped by subscription
        if !appState.servers.isEmpty {
            Menu("Servers") {
                let manualServers = appState.servers.filter { $0.subscriptionId == nil }
                if !manualServers.isEmpty {
                    Section("Manual") {
                        ForEach(manualServers) { server in
                            serverMenuItem(server)
                        }
                    }
                }

                ForEach(appState.subscriptions) { sub in
                    let subServers = appState.servers.filter { $0.subscriptionId == sub.id }
                    if !subServers.isEmpty {
                        Section(sub.name) {
                            ForEach(subServers) { server in
                                serverMenuItem(server)
                            }
                        }
                    }
                }
            }
        }

        // Tunnels submenu
        if !appState.tunnels.isEmpty {
            Menu("Tunnels (\(appState.tunnels.count))") {
                ForEach(appState.tunnels) { tunnel in
                    Button {
                        Task {
                            if tunnel.running {
                                await appState.pauseTunnel(tunnel.id)
                            } else {
                                try? await appState.resumeTunnel(tunnel.id)
                            }
                        }
                    } label: {
                        HStack {
                            Text(verbatim: "\(tunnel.serverName) (:\(tunnel.httpPort))")
                            if tunnel.running {
                                Image(systemName: "circle.fill")
                            } else {
                                Image(systemName: "pause.circle")
                            }
                            if tunnel.id == Tunnel.primaryId {
                                Text("Primary")
                            }
                        }
                    }
                }

                Divider()

                if appState.hasPausedTunnels {
                    Button("Resume All") {
                        Task { await appState.resumeAllTunnels() }
                    }
                }

                Button("Pause All") {
                    Task { await appState.pauseAllTunnels() }
                }

                Button("Stop All & Remove") {
                    Task { await appState.stopAllTunnels() }
                }
            }
        }

        Divider()

        // Update Subscriptions
        if !appState.subscriptions.isEmpty {
            Button("Update Subscriptions") {
                Task { _ = await appState.updateAllSubscriptions() }
            }

            Divider()
        }

        // Open Dashboard
        Button("Open Dashboard...") {
            openDashboard()
        }
        .keyboardShortcut("o", modifiers: [.command])

        // Shell Export
        Button("Copy Shell Export") {
            appState.copyShellExport()
        }
        .keyboardShortcut("e", modifiers: [.command])

        Divider()

        // Quit
        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    private func serverMenuItem(_ server: ServerConfig) -> some View {
        Button {
            appState.setActiveServer(server.id)
        } label: {
            HStack {
                Text(serverLabel(server))
                if server.isActive {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private func serverLabel(_ server: ServerConfig) -> String {
        var label = server.name
        if let latency = server.latency {
            if latency == -1 {
                label += " (timeout)"
            } else {
                label += " (\(latency)ms)"
            }
        }
        return label
    }
}
