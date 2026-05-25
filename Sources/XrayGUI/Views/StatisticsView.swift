import SwiftUI
import XrayGUICore

struct StatisticsView: View {
    @Environment(AppState.self) private var appState

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private static let uptimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()

    private var refreshKey: String {
        appState.tunnels
            .map { "\($0.id):\($0.running):\($0.httpPort):\($0.socksPort)" }
            .joined(separator: "|")
    }

    private var activeTunnelCount: Int {
        appState.tunnels.filter(\.running).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if appState.tunnelStatistics.isEmpty {
                    emptyState
                } else {
                    summarySection
                    tunnelRowsSection
                }
            }
            .padding(24)
        }
        .navigationTitle("Statistics")
        .task(id: refreshKey) {
            await refreshLoop()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Active Tunnels",
            systemImage: "chart.bar.xaxis",
            description: Text("Start a tunnel to see live upload, download, and rate statistics.")
        )
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var summarySection: some View {
        let summary = appState.tunnelStatisticsSummary

        return VStack(alignment: .leading, spacing: 12) {
            Text("Live Summary")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 170), spacing: 12)
            ], spacing: 12) {
                summaryCard(
                    title: "Active Tunnels",
                    value: "\(summary.activeTunnelCount)",
                    accent: .blue
                )
                summaryCard(
                    title: "Downloaded",
                    value: byteString(summary.totalDownlinkBytes),
                    accent: .green
                )
                summaryCard(
                    title: "Uploaded",
                    value: byteString(summary.totalUplinkBytes),
                    accent: .orange
                )
                summaryCard(
                    title: "Download Rate",
                    value: rateString(summary.downloadRateBytesPerSecond),
                    accent: .teal
                )
                summaryCard(
                    title: "Upload Rate",
                    value: rateString(summary.uploadRateBytesPerSecond),
                    accent: .pink
                )
            }
        }
    }

    private var tunnelRowsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Per-Tunnel")
                .font(.headline)

            ForEach(appState.tunnelStatistics) { snapshot in
                tunnelRow(snapshot)
            }
        }
    }

    private func summaryCard(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular.tint(accent.opacity(0.14)), in: .rect(cornerRadius: 16))
    }

    private func tunnelRow(_ snapshot: TunnelStatisticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(snapshot.isAvailable ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)

                Text(snapshot.serverName)
                    .font(.headline)

                if snapshot.isPrimary {
                    Text("PRIMARY")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2))
                        .clipShape(.capsule)
                }

                Spacer()

                Text(uptimeString(from: snapshot.startedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 12) {
                metricColumn("Downloaded", byteString(snapshot.downlinkBytes), accent: .green)
                metricColumn("Uploaded", byteString(snapshot.uplinkBytes), accent: .orange)
                metricColumn("Down Rate", rateString(snapshot.downloadRateBytesPerSecond), accent: .teal)
                metricColumn("Up Rate", rateString(snapshot.uploadRateBytesPerSecond), accent: .pink)
            }

            HStack {
                Label("HTTP :\(snapshot.httpPort)", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                Label("SOCKS5 :\(snapshot.socksPort)", systemImage: "arrow.left.arrow.right")
                Spacer()
                if snapshot.isAvailable {
                    Text("Live")
                        .foregroundStyle(.green)
                } else {
                    Text("Stats unavailable")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func metricColumn(_ title: String, _ value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func byteString(_ bytes: UInt64) -> String {
        Self.byteFormatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
    }

    private func rateString(_ bytesPerSecond: Double) -> String {
        let clamped = max(0, bytesPerSecond.rounded())
        let value = Self.byteFormatter.string(fromByteCount: Int64(min(clamped, Double(Int64.max))))
        return "\(value)/s"
    }

    private func uptimeString(from startedAt: Date?) -> String {
        guard let startedAt else { return "Uptime --" }
        return Self.uptimeFormatter.string(from: startedAt, to: Date()) ?? "Uptime --"
    }

    private func refreshLoop() async {
        await appState.refreshTunnelStatistics()
        guard activeTunnelCount > 0 else { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await appState.refreshTunnelStatistics()
            guard activeTunnelCount > 0 else { return }
        }
    }
}
