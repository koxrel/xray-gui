<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-01 | Updated: 2026-03-01 -->

# Models

## Purpose
Pure data model structs and enums representing the application's domain. All models are value types conforming to `Codable`, `Identifiable`, `Equatable`, and `Sendable` for safe concurrent use and JSON persistence.

## Key Files

| File | Description |
|------|-------------|
| `ServerConfig.swift` | VLESS server configuration — address, port, UUID, transport/security settings, latency, active state. Supports TCP, WebSocket, gRPC, H2, and HTTPUpgrade transports with TLS or Reality security |
| `Subscription.swift` | Remote subscription source — URL, linked server IDs, auto-update interval |
| `ProxyStatus.swift` | Runtime proxy state — running flag, active server, proxy mode, ports, start time. Not persisted (reconstructed on launch) |
| `Tunnel.swift` | Individual proxy tunnel instance — server reference, HTTP/SOCKS ports, running state. Has a static `primaryId` constant for the main tunnel |
| `StoreData.swift` | Top-level persistence container aggregating servers, subscriptions, settings, and tunnels into one JSON-serializable object |
| `AppSettings.swift` | User-configurable settings — ports, proxy mode, DNS, routing rules, mux, theme. Also defines `ProxyMode`, `LogLevel`, and `AppTheme` enums |

## For AI Agents

### Working In This Directory
- All models are **structs** — use value semantics, avoid reference types
- `ServerConfig` has many optional fields for transport-specific settings (e.g., `wsPath`, `grpcServiceName`) — only populate what the transport requires
- `StoreData` has a custom `init(from:)` decoder that handles missing `tunnels` key for backward compatibility
- `AppSettings.default` provides sensible defaults (HTTP 1087, SOCKS 1080, global mode, Cloudflare+Google DNS)
- `ProxyStatus` is the only model **not** `Codable` — it represents ephemeral runtime state

### Key Enums in AppSettings.swift
- `ProxyMode`: `.global` (system-wide), `.pac` (PAC URL), `.manual` (no system proxy)
- `LogLevel`: `.debug`, `.info`, `.warning`, `.error`, `.none`
- `AppTheme`: `.system`, `.light`, `.dark` — maps to SwiftUI `ColorScheme?`

### Testing Requirements
- Changes to model fields require updating `StoreData` serialization and `Store` save/load
- Adding new `AppSettings` fields: add to `AppSettings.default`, add migration in `Store.load()`, and update `SettingsView`

## Dependencies

### Internal
- Referenced by all other layers (Services, ViewModels, Views)

### External
- Foundation (Codable, UUID)
- SwiftUI (only `AppTheme.colorScheme` property)

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
