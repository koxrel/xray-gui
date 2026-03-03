import SwiftUI
import XrayGUICore

private struct LogEntry: Identifiable {
    let id = UUID()
    let text: String
}

struct LogsView: View {
    @Environment(AppState.self) private var appState
    @State private var filterText = ""
    @State private var autoScroll = true
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        let entries = filteredLogEntries
        VStack(spacing: 0) {
            // Log content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(entries) { entry in
                            logLine(entry.text)
                                .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .onAppear { scrollProxy = proxy }
                .onChange(of: appState.logs.count) {
                    if autoScroll, let lastId = entries.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            .background(.background)

            Divider()

            // Toolbar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Filter logs...", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))

                Spacer()

                Text("\(entries.count) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                GlassEffectContainer {
                    HStack(spacing: 4) {
                        Toggle(isOn: $autoScroll) {
                            Image(systemName: "arrow.down.to.line")
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .help("Auto-scroll")

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(appState.logs.joined(separator: "\n"), forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .help("Copy all logs")

                        Button {
                            appState.clearLogs()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .help("Clear logs")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationTitle("Logs")
    }

    // MARK: - Log Line

    private func logLine(_ line: String) -> some View {
        Text(line)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(logColor(for: line))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func logColor(for line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("[e]") {
            return .red
        } else if lower.contains("warning") || lower.contains("[w]") {
            return .orange
        } else if lower.contains("info") || lower.contains("[i]") {
            return .primary
        } else if lower.contains("debug") || lower.contains("[d]") {
            return .secondary
        }
        return .primary
    }

    private var filteredLogEntries: [LogEntry] {
        let lines: [String]
        if filterText.isEmpty {
            lines = appState.logs
        } else {
            lines = appState.logs.filter { $0.localizedCaseInsensitiveContains(filterText) }
        }
        return lines.map { LogEntry(text: $0) }
    }
}
