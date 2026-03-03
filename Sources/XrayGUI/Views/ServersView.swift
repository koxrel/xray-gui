import SwiftUI
import XrayGUICore

struct ServersView: View {
    @Environment(AppState.self) private var appState
    @State private var testingAll = false
    @State private var testingId: String?
    @State private var editingServer: ServerConfig?
    @State private var serverToDelete: ServerConfig?
    @State private var clipboardImportCount: Int?
    @State private var collapsedGroups: Set<String> = []

    private func expandedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedGroups.contains(id) },
            set: { expanded in
                if expanded { collapsedGroups.remove(id) }
                else { collapsedGroups.insert(id) }
            }
        )
    }

    private var manualServers: [ServerConfig] {
        appState.servers.filter { $0.subscriptionId == nil }
    }

    private var serverGroups: [(Subscription, [ServerConfig])] {
        let grouped = Dictionary(grouping: appState.servers.filter { $0.subscriptionId != nil }) { $0.subscriptionId! }
        return appState.subscriptions.compactMap { sub in
            guard let servers = grouped[sub.id], !servers.isEmpty else { return nil }
            return (sub, servers)
        }
    }

    var body: some View {
        List {
            if appState.servers.isEmpty {
                emptyState
            } else {
                if !manualServers.isEmpty {
                    Section(isExpanded: expandedBinding(for: "manual")) {
                        ForEach(manualServers) { server in
                            serverRow(server)
                        }
                    } header: {
                        Text("Manual")
                    }
                }

                ForEach(serverGroups, id: \.0.id) { sub, servers in
                    Section(isExpanded: expandedBinding(for: sub.id)) {
                        ForEach(servers) { server in
                            serverRow(server)
                        }
                    } header: {
                        Text(sub.name)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.background)
        .navigationTitle("Servers")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    let imported = appState.importFromClipboard()
                    clipboardImportCount = imported.count
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .help("Import servers from clipboard")
                .accessibilityLabel("Import from clipboard")

                Button {
                    Task {
                        testingAll = true
                        await appState.testAllLatency()
                        testingAll = false
                    }
                } label: {
                    if testingAll {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Test All", systemImage: "bolt.horizontal")
                    }
                }
                .disabled(testingAll || appState.servers.isEmpty)
                .help("Test latency for all servers")
            }
        }
        .sheet(item: $editingServer) { server in
            ServerEditSheet(server: server) { updated in
                appState.updateServer(updated)
                editingServer = nil
            }
        }
        .confirmationDialog(
            "Delete Server",
            isPresented: Binding(
                get: { serverToDelete != nil },
                set: { if !$0 { serverToDelete = nil } }
            ),
            presenting: serverToDelete
        ) { server in
            Button("Delete \"\(server.name)\"", role: .destructive) {
                appState.deleteServer(server.id)
                serverToDelete = nil
            }
        } message: { server in
            Text("Are you sure you want to delete \"\(server.name)\"? This cannot be undone.")
        }
        .alert("Clipboard Import", isPresented: Binding(
            get: { clipboardImportCount != nil },
            set: { if !$0 { clipboardImportCount = nil } }
        )) {
            Button("OK") { clipboardImportCount = nil }
        } message: {
            if let count = clipboardImportCount {
                Text(count > 0 ? "Imported \(count) server(s) successfully." : "No valid server URLs found in clipboard.")
            }
        }
    }

    // MARK: - Server Row

    private func serverRow(_ server: ServerConfig) -> some View {
        HStack(spacing: 12) {
            // Radio selection
            Button {
                let newId = server.isActive ? nil : server.id
                appState.setActiveServer(newId)
            } label: {
                Image(systemName: server.isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(server.isActive ? .blue : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(server.isActive ? "Selected: \(server.name)" : "Select \(server.name)")

            // Server info
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(server.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(server.network.isEmpty ? "tcp" : server.network)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.blue)

                    Text(server.security.isEmpty ? "none" : server.security)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            // Latency badge with glass effect
            latencyBadge(server.latency)

            // Actions with glass
            GlassEffectContainer {
                HStack(spacing: 4) {
                    Button {
                        Task {
                            testingId = server.id
                            await appState.testLatency(server.id)
                            testingId = nil
                        }
                    } label: {
                        Image(systemName: "bolt.horizontal")
                    }
                    .buttonStyle(.glass)
                    .disabled(testingId == server.id)
                    .help("Test latency")
                    .accessibilityLabel("Test latency for \(server.name)")

                    Button {
                        editingServer = server
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.glass)
                    .help("Edit server")
                    .accessibilityLabel("Edit \(server.name)")

                    Button(role: .destructive) {
                        serverToDelete = server
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.glass)
                    .help("Delete server")
                    .accessibilityLabel("Delete \(server.name)")
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Latency Badge

    private func latencyBadge(_ latency: Int?) -> some View {
        Group {
            if let latency {
                if latency == -1 {
                    Text("timeout")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .glassEffect(.regular.tint(.red), in: .capsule)
                } else {
                    Text("\(latency)ms")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .glassEffect(.regular.tint(latencyColor(latency)), in: .capsule)
                }
            } else {
                Text("--")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassEffect(.regular, in: .capsule)
            }
        }
    }

    private func latencyColor(_ ms: Int) -> Color {
        if ms < 200 { return .green }
        if ms < 500 { return .orange }
        return .red
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("No Servers")
                .font(.title3.weight(.medium))

            Text("Add a subscription or paste server URLs from clipboard")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                clipboardImportCount = appState.importFromClipboard().count
            } label: {
                Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Server Edit Sheet

struct ServerEditSheet: View {
    @State var server: ServerConfig
    let onSave: (ServerConfig) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Server")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()

            Divider()

            Form {
                Section("General") {
                    TextField("Name", text: $server.name)
                    TextField("Address", text: $server.address)
                    TextField("Port", value: $server.port, format: .number)
                    TextField("UUID", text: $server.uuid)
                }

                Section("Protocol") {
                    TextField("Flow", text: $server.flow)
                    TextField("Encryption", text: $server.encryption)
                    Picker("Network", selection: $server.network) {
                        Text("TCP").tag("tcp")
                        Text("WebSocket").tag("ws")
                        Text("gRPC").tag("grpc")
                        Text("HTTP/2").tag("h2")
                        Text("HTTPUpgrade").tag("httpupgrade")
                    }
                    Picker("Security", selection: $server.security) {
                        Text("None").tag("none")
                        Text("TLS").tag("tls")
                        Text("Reality").tag("reality")
                    }
                }

                Section("TLS / Reality") {
                    TextField("SNI", text: $server.sni)
                    TextField("Fingerprint", text: $server.fingerprint)
                    TextField("Public Key", text: $server.publicKey)
                    TextField("Short ID", text: $server.shortId)
                    Toggle("Allow Insecure", isOn: $server.allowInsecure)
                }

                Section("Transport") {
                    TextField("Path", text: Binding(
                        get: { server.wsPath ?? "" },
                        set: { server.wsPath = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("Host", text: Binding(
                        get: { server.wsHost ?? "" },
                        set: { server.wsHost = $0.isEmpty ? nil : $0 }
                    ))
                    TextField("gRPC Service Name", text: Binding(
                        get: { server.grpcServiceName ?? "" },
                        set: { server.grpcServiceName = $0.isEmpty ? nil : $0 }
                    ))
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(server)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 480, height: 560)
    }
}
