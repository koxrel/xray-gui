import SwiftUI
import XrayGUICore

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    // Local state for all fields — only pushed to AppState on commit
    @State private var httpPortText: String = "1087"
    @State private var socksPortText: String = "1080"
    @State private var allowLan: Bool = false
    @State private var autoStart: Bool = false
    @State private var logLevel: LogLevel = .warning
    @State private var enableMux: Bool = false
    @State private var muxConcurrencyText: String = "8"
    @State private var dnsText: String = ""
    @State private var dnsMode: DNSMode = .plain
    @State private var dohServer: String = "https://1.1.1.1/dns-query"
    @State private var dohPreset: DoHPreset = .cloudflare
    @State private var bypassText: String = ""
    @State private var directText: String = ""
    @State private var blockedText: String = ""
    @State private var pacUrlText: String = ""
    @State private var theme: AppTheme = .system
    @State private var hasChanges = false
    @State private var validationError: String?

    var body: some View {
        Form {
            appearanceSection
            networkSection
            advancedSection
            routingSection

            if hasChanges {
                Section {
                    HStack {
                        Spacer()
                        Button("Revert") {
                            loadFromAppState()
                        }
                        Button("Apply") {
                            Task { await applyChanges() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear { loadFromAppState() }
        .alert("Validation Error", isPresented: Binding(
            get: { validationError != nil },
            set: { if !$0 { validationError = nil } }
        )) {
            Button("OK") { validationError = nil }
        } message: {
            Text(validationError ?? "")
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $theme) {
                ForEach(AppTheme.allCases, id: \.self) { t in
                    Text(t.rawValue.capitalized).tag(t)
                }
            }
            .onChange(of: theme) { markChanged() }
        }
    }

    // MARK: - Network Section

    private var networkSection: some View {
        Section("Network") {
            LabeledContent("HTTP Port") {
                TextField("", text: $httpPortText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: httpPortText) { markChanged() }
            }

            LabeledContent("SOCKS Port") {
                TextField("", text: $socksPortText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: socksPortText) { markChanged() }
            }

            Toggle("Allow LAN Connections", isOn: $allowLan)
                .onChange(of: allowLan) { markChanged() }

            Toggle("Auto Start on Launch", isOn: $autoStart)
                .onChange(of: autoStart) { markChanged() }

            LabeledContent("PAC URL") {
                TextField("", text: $pacUrlText, prompt: Text("http://127.0.0.1:1087/pac"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .onChange(of: pacUrlText) { markChanged() }
            }
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        Section("Advanced") {
            Picker("Log Level", selection: $logLevel) {
                ForEach(LogLevel.allCases, id: \.self) { level in
                    Text(level.rawValue.capitalized).tag(level)
                }
            }
            .onChange(of: logLevel) { markChanged() }

            Toggle("Enable Mux", isOn: $enableMux)
                .onChange(of: enableMux) { markChanged() }

            if enableMux {
                LabeledContent("Mux Concurrency") {
                    TextField("", text: $muxConcurrencyText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: muxConcurrencyText) { markChanged() }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("DNS")
                Picker("DNS Mode", selection: $dnsMode) {
                    ForEach(DNSMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: dnsMode) { markChanged() }

                if dnsMode == .plain {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DNS Servers")
                            .font(.caption)
                        TextEditor(text: $dnsText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 50)
                            .onChange(of: dnsText) { markChanged() }
                        Text("One per line")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Provider", selection: $dohPreset) {
                            ForEach(DoHPreset.allCases) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .onChange(of: dohPreset) {
                            if dohPreset != .custom {
                                dohServer = dohPreset.url
                            }
                            markChanged()
                        }

                        if dohPreset == .custom {
                            TextField("DoH URL", text: $dohServer)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                                .onChange(of: dohServer) { markChanged() }
                            Text("e.g. https://dns.example.com/dns-query")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Routing Section

    private var routingSection: some View {
        Section("Routing") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bypass Domains (Direct)")
                TextEditor(text: $bypassText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 60)
                    .onChange(of: bypassText) { markChanged() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Direct Domains")
                TextEditor(text: $directText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 60)
                    .onChange(of: directText) { markChanged() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Blocked Domains")
                TextEditor(text: $blockedText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 60)
                    .onChange(of: blockedText) { markChanged() }
            }
        }
    }

    // MARK: - Helpers

    private func loadFromAppState() {
        let s = appState.settings
        httpPortText = String(s.httpPort)
        socksPortText = String(s.socksPort)
        allowLan = s.allowLan
        autoStart = s.autoStart
        logLevel = s.logLevel
        enableMux = s.enableMux
        muxConcurrencyText = String(s.muxConcurrency)
        dnsText = s.dnsServers.joined(separator: "\n")
        dnsMode = s.dnsMode
        dohServer = s.dohServer
        dohPreset = DoHPreset.from(url: s.dohServer)
        bypassText = s.bypassDomains.joined(separator: "\n")
        directText = s.directDomains.joined(separator: "\n")
        blockedText = s.blockedDomains.joined(separator: "\n")
        pacUrlText = s.pacUrl
        theme = s.theme
        hasChanges = false
    }

    private func markChanged() {
        hasChanges = true
    }

    private func parseLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func applyChanges() async {
        // Validate ports
        let httpPort = Int(httpPortText) ?? 0
        let socksPort = Int(socksPortText) ?? 0

        guard (1024...65535).contains(httpPort) else {
            validationError = "HTTP port must be between 1024 and 65535"
            return
        }
        guard (1024...65535).contains(socksPort) else {
            validationError = "SOCKS port must be between 1024 and 65535"
            return
        }
        guard httpPort != socksPort else {
            validationError = "HTTP and SOCKS ports must be different"
            return
        }

        // Validate PAC URL if non-empty
        if !pacUrlText.isEmpty {
            guard let url = URL(string: pacUrlText),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                validationError = "PAC URL must be a valid HTTP or HTTPS URL"
                return
            }
        }

        // Validate mux concurrency
        let muxConcurrency = Int(muxConcurrencyText) ?? 8
        if enableMux && !(1...1024).contains(muxConcurrency) {
            validationError = "Mux concurrency must be between 1 and 1024"
            return
        }

        // Validate DoH URL
        if dnsMode == .doh {
            let trimmed = dohServer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let url = URL(string: trimmed),
                  url.scheme?.lowercased() == "https",
                  url.host != nil else {
                validationError = "DoH server must be a valid HTTPS URL (e.g. https://1.1.1.1/dns-query)"
                return
            }
        }

        await appState.updateSettings { s in
            s.httpPort = httpPort
            s.socksPort = socksPort
            s.allowLan = allowLan
            s.autoStart = autoStart
            s.logLevel = logLevel
            s.enableMux = enableMux
            s.muxConcurrency = muxConcurrency
            s.dnsServers = parseLines(dnsText)
            s.dnsMode = dnsMode
            s.dohServer = dohServer
            s.bypassDomains = parseLines(bypassText)
            s.directDomains = parseLines(directText)
            s.blockedDomains = parseLines(blockedText)
            s.pacUrl = pacUrlText
            s.theme = theme
        }
        hasChanges = false
    }
}
