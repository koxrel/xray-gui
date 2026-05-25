import SwiftUI
import XrayGUICore

enum SidebarTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case servers = "Servers"
    case tunnels = "Tunnels"
    case statistics = "Statistics"
    case subscriptions = "Subscriptions"
    case settings = "Settings"
    case logs = "Logs"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .servers: return "server.rack"
        case .tunnels: return "point.3.connected.trianglepath.dotted"
        case .statistics: return "chart.xyaxis.line"
        case .subscriptions: return "antenna.radiowaves.left.and.right"
        case .settings: return "gearshape"
        case .logs: return "doc.text"
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: SidebarTab = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SidebarTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch selectedTab {
                case .dashboard:
                    DashboardView()
                case .servers:
                    ServersView()
                case .tunnels:
                    TunnelsView()
                case .statistics:
                    StatisticsView()
                case .subscriptions:
                    SubscriptionsView()
                case .settings:
                    SettingsView()
                case .logs:
                    LogsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
