import SwiftUI
import XrayGUICore

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var uptime: String = ""
    @Namespace private var powerAnimation
    private let uptimePublisher = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Power Button
                powerButton
                    .padding(.top, 20)

                // Status Info
                statusSection

                // Proxy Mode
                proxyModeSection

                // Active Server Detail
                if let server = appState.proxyStatus.activeServer ?? activeServer {
                    serverDetailSection(server)
                }

                // Active Tunnels Summary
                if appState.tunnels.count > 1 {
                    tunnelsSummarySection
                }

                // Shell Export
                shellExportButton
            }
            .padding(24)
        }
        .navigationTitle("Dashboard")
        .onAppear { updateUptime() }
        .onReceive(uptimePublisher) { _ in updateUptime() }
        .alert("Connection Error", isPresented: Binding(
            get: { connectionError != nil },
            set: { if !$0 { connectionError = nil } }
        )) {
            Button("OK") { connectionError = nil }
        } message: {
            Text(connectionError ?? "")
        }
    }

    // MARK: - Power Button

    private var powerButton: some View {
        Button {
            Task { await toggleConnection() }
        } label: {
            Image(systemName: appState.proxyStatus.running ? "power.circle.fill" : "power.circle")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(buttonColor)
                .frame(width: 80, height: 80)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .tint(buttonColor)
        .glassEffectID("powerButton", in: powerAnimation)
        .disabled(isConnecting)
        .opacity(isConnecting ? 0.6 : 1)
        .animation(.bouncy, value: appState.proxyStatus.running)
        .accessibilityLabel(appState.proxyStatus.running ? "Disconnect" : "Connect")
        .accessibilityHint("Double-click to toggle the proxy connection")
    }

    private var buttonColor: Color {
        if isConnecting { return .orange }
        return appState.proxyStatus.running ? .green : .secondary
    }

    // MARK: - Status Section

    private var statusSection: some View {
        HStack(spacing: 16) {
            statusCard(
                title: "Status",
                value: appState.proxyStatus.running ? "Connected" : "Disconnected",
                color: appState.proxyStatus.running ? .green : .secondary
            )

            if appState.proxyStatus.running {
                statusCard(title: "Uptime", value: uptime, color: .blue)
            }

            statusCard(
                title: "HTTP",
                value: String(appState.settings.httpPort),
                color: .purple
            )

            statusCard(
                title: "SOCKS5",
                value: String(appState.settings.socksPort),
                color: .purple
            )
        }
    }

    private func statusCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    // MARK: - Proxy Mode

    private var proxyModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Proxy Mode")
                .font(.headline)

            GlassEffectContainer {
                HStack(spacing: 8) {
                    ForEach(ProxyMode.allCases, id: \.self) { mode in
                        proxyModeButton(mode)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func proxyModeButton(_ mode: ProxyMode) -> some View {
        let isActive = appState.proxyStatus.proxyMode == mode
        Button {
            Task { await appState.setProxyMode(mode) }
        } label: {
            Text(mode.displayName)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.glass)
        .tint(isActive ? Color.blue : nil)
        .accessibilityLabel("Proxy mode: \(mode.rawValue)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Server Detail

    private func serverDetailSection(_ server: ServerConfig) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Server")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                detailRow("Name", server.name)
                detailRow("Address", server.address + ":" + String(server.port))
                detailRow("Protocol", "VLESS")
                detailRow("Network", server.network.isEmpty ? "tcp" : server.network)
                detailRow("Security", server.security.isEmpty ? "none" : server.security)
                if !server.sni.isEmpty {
                    detailRow("SNI", server.sni)
                }
                if !server.flow.isEmpty {
                    detailRow("Flow", server.flow)
                }
                if let latency = server.latency {
                    detailRow("Latency", latency == -1 ? "Timeout" : "\(latency)ms")
                }
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.callout)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Tunnels Summary

    private var tunnelsSummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Tunnels (\(appState.tunnels.count))")
                .font(.headline)

            VStack(spacing: 6) {
                ForEach(appState.tunnels) { tunnel in
                    HStack {
                        Circle()
                            .fill(tunnel.running ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(tunnel.serverName)
                            .font(.callout)
                        if tunnel.id == Tunnel.primaryId {
                            Text("PRIMARY")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.blue.opacity(0.2))
                                .clipShape(.capsule)
                        }
                        Spacer()
                        Text(verbatim: "HTTP :\(tunnel.httpPort)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(verbatim: "SOCKS5 :\(tunnel.socksPort)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
    }

    // MARK: - Shell Export

    private var shellExportButton: some View {
        Button {
            appState.copyShellExport()
        } label: {
            Label("Copy Shell Export", systemImage: "doc.on.clipboard")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .accessibilityLabel("Copy shell export commands to clipboard")
    }

    // MARK: - Helpers

    private var activeServer: ServerConfig? {
        appState.servers.first { $0.isActive } ??
        appState.servers.first { $0.id == appState.settings.activeServerId }
    }

    private func toggleConnection() async {
        isConnecting = true
        defer { isConnecting = false }

        do {
            if appState.proxyStatus.running {
                try await appState.stopProxy()
            } else {
                try await appState.startProxy()
            }
        } catch {
            connectionError = error.localizedDescription
        }
    }

    private func updateUptime() {
        guard let startedAt = appState.proxyStatus.startedAt else {
            uptime = "0s"
            return
        }
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60

        if hours > 0 {
            uptime = "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            uptime = "\(minutes)m \(seconds)s"
        } else {
            uptime = "\(seconds)s"
        }
    }
}
