import SwiftUI
import XrayGUICore

struct SubscriptionsView: View {
    @Environment(AppState.self) private var appState
    @State private var showingAddSheet = false
    @State private var updatingId: String?
    @State private var updatingAll = false
    @State private var subscriptionToDelete: Subscription?

    var body: some View {
        List {
            if appState.subscriptions.isEmpty {
                emptyState
            } else {
                ForEach(appState.subscriptions) { sub in
                    subscriptionRow(sub)
                }
            }
        }
        .navigationTitle("Subscriptions")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task {
                        updatingAll = true
                        _ = await appState.updateAllSubscriptions()
                        updatingAll = false
                    }
                } label: {
                    Label("Update All", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(updatingAll || appState.subscriptions.isEmpty)
                .help("Update all subscriptions")

                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .help("Add subscription")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddSubscriptionSheet { name, url in
                showingAddSheet = false
                Task {
                    await appState.addSubscription(name: name, url: url)
                }
            }
        }
        .confirmationDialog(
            "Delete Subscription",
            isPresented: Binding(
                get: { subscriptionToDelete != nil },
                set: { if !$0 { subscriptionToDelete = nil } }
            ),
            presenting: subscriptionToDelete
        ) { sub in
            Button("Delete \"\(sub.name)\" and its servers", role: .destructive) {
                appState.deleteSubscription(sub.id)
                subscriptionToDelete = nil
            }
        } message: { sub in
            Text("This will also remove all \(sub.serverIds.count) server(s) from this subscription.")
        }
    }

    // MARK: - Subscription Row

    private func subscriptionRow(_ sub: Subscription) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(sub.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(sub.serverIds.count) servers")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let lastUpdated = sub.lastUpdated {
                        Text("Updated: \(formatDate(lastUpdated))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Actions
            GlassEffectContainer {
                HStack(spacing: 4) {
                    Button {
                        Task {
                            updatingId = sub.id
                            await appState.updateSubscription(sub.id)
                            updatingId = nil
                        }
                    } label: {
                        if updatingId == sub.id {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.glass)
                    .disabled(updatingId == sub.id)
                    .help("Update subscription")
                    .accessibilityLabel("Update \(sub.name)")

                    Button(role: .destructive) {
                        subscriptionToDelete = sub
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.glass)
                    .help("Delete subscription and its servers")
                    .accessibilityLabel("Delete \(sub.name)")
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("No Subscriptions")
                .font(.title3.weight(.medium))

            Text("Add a subscription URL to automatically import servers")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingAddSheet = true
            } label: {
                Label("Add Subscription", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func formatDate(_ isoString: String) -> String {
        guard let date = Self.isoFormatter.date(from: isoString) else { return isoString }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Add Subscription Sheet

struct AddSubscriptionSheet: View {
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var urlError: String?

    private var isURLValid: Bool {
        guard let parsed = URL(string: url),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "https",
              parsed.host != nil else {
            return false
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Subscription")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()

            Divider()

            Form {
                TextField("Name", text: $name, prompt: Text("My Subscription"))
                TextField("URL", text: $url, prompt: Text("https://example.com/sub"))
                    .onChange(of: url) { urlError = nil }
                if let urlError {
                    Text(urlError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    guard !name.isEmpty, !url.isEmpty else { return }
                    guard isURLValid else {
                        urlError = "Please enter a valid HTTPS URL"
                        return
                    }
                    onSave(name, url)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || url.isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 260)
    }
}
