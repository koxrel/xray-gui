import SwiftUI
import XrayGUICore

struct TunnelsView: View {
    @Environment(AppState.self) private var appState
    @State private var showAddSheet = false
    @State private var addError: String?
    @State private var showStopAllConfirmation = false
    @State private var editingTunnel: Tunnel?
    @Namespace private var tunnelAnimation

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if appState.tunnels.isEmpty {
                    emptyState
                } else {
                    tunnelsList
                }
            }
            .padding(24)
        }
        .navigationTitle("Tunnels")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Tunnel", systemImage: "plus")
                }
                .disabled(appState.servers.isEmpty)
            }

            if appState.hasPausedTunnels {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await appState.resumeAllTunnels() }
                    } label: {
                        Label("Resume All", systemImage: "play.fill")
                    }
                }
            }

            if appState.tunnels.count > 1 {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button {
                            Task { await appState.pauseAllTunnels() }
                        } label: {
                            Label("Pause All", systemImage: "pause.fill")
                        }

                        Button(role: .destructive) {
                            showStopAllConfirmation = true
                        } label: {
                            Label("Stop All & Remove", systemImage: "stop.fill")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddTunnelSheet(error: $addError)
        }
        .sheet(item: $editingTunnel) { tunnel in
            EditTunnelPortsSheet(tunnel: tunnel, error: $addError)
        }
        .alert("Failed to add tunnel", isPresented: .init(
            get: { addError != nil },
            set: { if !$0 { addError = nil } }
        )) {
            Button("OK") { addError = nil }
        } message: {
            Text(addError ?? "")
        }
        .confirmationDialog(
            "Stop All Tunnels",
            isPresented: $showStopAllConfirmation
        ) {
            Button("Stop All & Remove", role: .destructive) {
                Task { await appState.stopAllTunnels() }
            }
        } message: {
            Text("This will stop all \(appState.tunnels.count) tunnel(s) and remove them. This cannot be undone.")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Active Tunnels")
                .font(.title2.weight(.semibold))

            Text("Add a tunnel to proxy traffic through a server.\nEach tunnel runs independently with its own ports.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showAddSheet = true
            } label: {
                Label("Add Tunnel", systemImage: "plus")
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .padding(.top, 8)
            .disabled(appState.servers.isEmpty)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Tunnels List

    private var tunnelsList: some View {
        VStack(spacing: 12) {
            ForEach(appState.tunnels) { tunnel in
                tunnelRow(tunnel)
            }
        }
    }

    private func tunnelRow(_ tunnel: Tunnel) -> some View {
        HStack(spacing: 16) {
            // Status indicator
            Circle()
                .fill(tunnel.running ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
                .accessibilityLabel(tunnel.running ? "Running" : "Paused")

            // Server info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tunnel.serverName)
                        .font(.headline)
                    if tunnel.id == Tunnel.primaryId {
                        Text("PRIMARY")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.2))
                            .clipShape(.capsule)
                    }
                    if !tunnel.running {
                        Text("PAUSED")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.2))
                            .clipShape(.capsule)
                    }
                }

                if tunnel.running, let startedAt = tunnel.startedAt {
                    Text("Up \(startedAt, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !tunnel.running {
                    Text("Paused")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            // Port badges
            portBadge("HTTP", port: tunnel.httpPort)
            portBadge("SOCKS", port: tunnel.socksPort)

            // Pause/Resume button
            Button {
                Task {
                    if tunnel.running {
                        await appState.pauseTunnel(tunnel.id)
                    } else {
                        do {
                            try await appState.resumeTunnel(tunnel.id)
                        } catch {
                            addError = error.localizedDescription
                        }
                    }
                }
            } label: {
                Image(systemName: tunnel.running ? "pause.fill" : "play.fill")
                    .font(.body)
                    .foregroundStyle(tunnel.running ? .orange : .green)
            }
            .buttonStyle(.plain)
            .help(tunnel.running ? "Pause tunnel" : "Resume tunnel")
            .accessibilityLabel(tunnel.running ? "Pause \(tunnel.serverName)" : "Resume \(tunnel.serverName)")

            // Actions menu
            Menu {
                Button {
                    editingTunnel = tunnel
                } label: {
                    Label("Edit Ports", systemImage: "slider.horizontal.3")
                }

                Button {
                    copyTunnelExport(tunnel)
                } label: {
                    Label("Copy Shell Export", systemImage: "doc.on.clipboard")
                }

                Divider()

                if tunnel.id != Tunnel.primaryId {
                    Button(role: .destructive) {
                        Task { await appState.removeTunnel(tunnel.id) }
                    } label: {
                        Label("Remove Tunnel", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private func portBadge(_ label: String, port: Int) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(verbatim: ":\(port)")
                .font(.system(.caption, design: .monospaced, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) port \(port)")
    }

    private func copyTunnelExport(_ tunnel: Tunnel) {
        let export = """
        export http_proxy=http://127.0.0.1:\(tunnel.httpPort)
        export https_proxy=http://127.0.0.1:\(tunnel.httpPort)
        export ALL_PROXY=socks5://127.0.0.1:\(tunnel.socksPort)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(export, forType: .string)
    }

}

// MARK: - Add Tunnel Sheet

struct AddTunnelSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Binding var error: String?
    @State private var selectedServerId: String?
    @State private var isStarting = false
    @State private var httpPortText = ""
    @State private var socksPortText = ""
    @State private var portsInitialized = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Tunnel")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Server picker
            List(selection: $selectedServerId) {
                let manualServers = appState.servers.filter { $0.subscriptionId == nil }
                if !manualServers.isEmpty {
                    Section("Manual") {
                        ForEach(manualServers) { server in
                            serverRow(server)
                                .tag(server.id)
                        }
                    }
                }

                ForEach(appState.subscriptions) { sub in
                    let subServers = appState.servers.filter { $0.subscriptionId == sub.id }
                    if !subServers.isEmpty {
                        Section(sub.name) {
                            ForEach(subServers) { server in
                                serverRow(server)
                                    .tag(server.id)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)

            Divider()

            // Port configuration
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text("HTTP")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("port", text: $httpPortText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .font(.system(.caption, design: .monospaced))
                }
                HStack(spacing: 6) {
                    Text("SOCKS")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("port", text: $socksPortText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .font(.system(.caption, design: .monospaced))
                }

                Spacer()

                Button {
                    startTunnel()
                } label: {
                    if isStarting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                    } else {
                        Text("Start Tunnel")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedServerId == nil || isStarting || !portsValid)
            }
            .padding()
        }
        .frame(width: 420, height: 400)
        .onAppear { initPorts() }
    }

    private var portsValid: Bool {
        guard let http = Int(httpPortText), let socks = Int(socksPortText) else { return false }
        return http >= 1024 && http <= 65535 && socks >= 1024 && socks <= 65535 && http != socks
    }

    private func initPorts() {
        guard !portsInitialized else { return }
        let ports = appState.nextAvailablePortsPreview()
        httpPortText = "\(ports.http)"
        socksPortText = "\(ports.socks)"
        portsInitialized = true
    }

    private func serverRow(_ server: ServerConfig) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.body)
                Text(verbatim: "\(server.address):\(server.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let latency = server.latency {
                Text(verbatim: latency == -1 ? "timeout" : "\(latency)ms")
                    .font(.caption)
                    .foregroundStyle(latency == -1 ? .red : .green)
            }
        }
    }

    private func startTunnel() {
        guard let serverId = selectedServerId else { return }
        isStarting = true
        Task {
            do {
                _ = try await appState.addTunnel(
                    serverId: serverId,
                    httpPort: Int(httpPortText),
                    socksPort: Int(socksPortText)
                )
                dismiss()
            } catch {
                self.error = error.localizedDescription
                isStarting = false
            }
        }
    }
}

// MARK: - Edit Tunnel Ports Sheet

struct EditTunnelPortsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let tunnel: Tunnel
    @Binding var error: String?
    @State private var httpPortText: String
    @State private var socksPortText: String
    @State private var isSaving = false

    init(tunnel: Tunnel, error: Binding<String?>) {
        self.tunnel = tunnel
        self._error = error
        self._httpPortText = State(initialValue: "\(tunnel.httpPort)")
        self._socksPortText = State(initialValue: "\(tunnel.socksPort)")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit Ports")
                        .font(.title2.weight(.semibold))
                    Text(tunnel.serverName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Port fields
            Form {
                HStack {
                    Text("HTTP Port")
                    Spacer()
                    TextField("HTTP port", text: $httpPortText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .font(.system(.body, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("SOCKS5 Port")
                    Spacer()
                    TextField("SOCKS port", text: $socksPortText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .font(.system(.body, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                }
            }
            .formStyle(.grouped)

            if !portsValid {
                Text("Ports must be 1024–65535 and different from each other.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Spacer()

            Divider()

            // Footer
            HStack {
                if tunnel.running {
                    Text("Tunnel will restart with new ports.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!portsValid || !portsChanged || isSaving)
            }
            .padding()
        }
        .frame(width: 340, height: 280)
    }

    private var portsValid: Bool {
        guard let http = Int(httpPortText), let socks = Int(socksPortText) else { return false }
        return http >= 1024 && http <= 65535 && socks >= 1024 && socks <= 65535 && http != socks
    }

    private var portsChanged: Bool {
        Int(httpPortText) != tunnel.httpPort || Int(socksPortText) != tunnel.socksPort
    }

    private func save() {
        guard let http = Int(httpPortText), let socks = Int(socksPortText) else { return }
        isSaving = true
        Task {
            do {
                try await appState.updateTunnelPorts(tunnel.id, httpPort: http, socksPort: socks)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                isSaving = false
            }
        }
    }
}
