<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-01 | Updated: 2026-03-01 -->

# Views

## Purpose
SwiftUI view layer implementing the full UI. Uses a `NavigationSplitView` with a sidebar for tab navigation and detail views for each section. Styled with macOS Tahoe's Liquid Glass design language.

## Key Files

| File | Description |
|------|-------------|
| `ContentView.swift` | Root view with `NavigationSplitView` sidebar. Defines `SidebarTab` enum (Dashboard, Servers, Tunnels, Subscriptions, Settings, Logs) and routes to detail views |
| `DashboardView.swift` | Main status view — power button (glass circle), status cards (connection/uptime/ports), proxy mode picker, active server details, tunnel summary, shell export button |
| `ServersView.swift` | Server list grouped by subscription. Supports selection (radio), latency testing, editing (sheet), deletion (confirmation dialog), and clipboard import. Includes `ServerEditSheet` with full VLESS field editing |
| `TunnelsView.swift` | Multi-tunnel management — add/pause/resume/remove tunnels. Each tunnel shows server name, ports, running state. Includes `AddTunnelSheet` for creating new tunnels from server list |
| `SubscriptionsView.swift` | Subscription CRUD — add via URL (HTTPS only), update individual/all, delete with server cascade. Includes `AddSubscriptionSheet` with URL validation |
| `SettingsView.swift` | Settings form with local state buffering — changes only apply on explicit "Apply" click. Sections: Appearance (theme), Network (ports, LAN, PAC), Advanced (log level, mux, DNS), Routing (bypass/direct/blocked domains). Validates ports (1024-65535, must differ) |
| `LogsView.swift` | Real-time log viewer with text filter, auto-scroll toggle, copy-all, and clear. Uses `LazyVStack` for performance. Color-codes lines by severity (error=red, warning=orange, debug=gray) |

## For AI Agents

### Working In This Directory
- All views access state via `@Environment(AppState.self)` — never create new `AppState` instances
- Views use **Liquid Glass** APIs: `.glassEffect()`, `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`, `GlassEffectContainer`
- The `@Namespace` property wrapper + `.glassEffectID()` is used for matched glass animations (DashboardView power button)
- Sheets are presented via `@State` booleans + `.sheet(isPresented:)` pattern
- Confirmation dialogs use `.confirmationDialog(presenting:)` for type-safe data passing

### Design Patterns
- **Local state buffering** (SettingsView): text fields bind to local `@State`, only pushed to `AppState` on "Apply"
- **Empty states**: every list view has an `emptyState` computed property with icon + message + CTA
- **Server grouping**: ServersView groups by subscription using `Section(isExpanded:)` with collapsible headers
- **Accessibility**: views include `accessibilityLabel`, `accessibilityHint`, `accessibilityAddTraits` throughout

### Testing Requirements
- UI changes: build and run the app, navigate to the affected tab
- Glass effects require macOS Tahoe — they won't render on earlier versions
- Test both populated and empty states for list views

## Dependencies

### Internal
- `ViewModels/AppState` — all state access
- `Models/` — ServerConfig, Subscription, Tunnel, ProxyMode, etc.

### External
- SwiftUI (primary UI framework)
- AppKit (`NSPasteboard` for clipboard in ServersView, TunnelsView, LogsView)

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
