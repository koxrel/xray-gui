<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-01 | Updated: 2026-03-01 -->

# Services

## Purpose
Business logic layer handling persistence, process management, system proxy configuration, network requests, and Xray config generation. Services are either stateless `enum` namespaces or `Sendable` classes.

## Key Files

| File | Description |
|------|-------------|
| `Store.swift` | JSON persistence to `~/Library/Application Support/XrayGUI/xray-gui-data.json`. CRUD operations for servers, subscriptions, settings. Manages per-tunnel config file paths. Merges loaded data with defaults for forward compatibility |
| `XrayManager.swift` | Xray process lifecycle — start/stop/restart per tunnel ID. Manages `Process` instances, streams stdout/stderr to log callback, handles graceful SIGTERM with SIGKILL fallback. Also provides TCP latency testing (3-probe median) via Network framework |
| `ProxyManager.swift` | macOS system proxy configuration via `/usr/sbin/networksetup`. Supports global (HTTP+HTTPS+SOCKS), PAC, and manual modes. Configures all detected network services in parallel. Has both async and synchronous variants for app termination cleanup |
| `SubscriptionManager.swift` | Fetches subscription URLs (HTTPS only), decodes base64 content, parses `vless://` URIs into `ServerConfig` structs. Includes SSRF protection (blocks private/loopback IPs) and 1MB response size limit |
| `ConfigGenerator.swift` | Generates Xray JSON configuration dictionaries. Builds inbound (HTTP+SOCKS), outbound (VLESS proxy + direct + blackhole), stream settings (TLS/Reality, transport), routing rules (bypass/direct/block domains, private IPs), DNS, and mux settings |

## For AI Agents

### Working In This Directory
- `Store` is the only **stateful** service (holds `fileURL`); all others are stateless `enum`s
- `XrayManager` is `@MainActor` — process management happens on the main thread
- `ProxyManager` calls `networksetup` via `Process` — requires no special entitlements but changes are system-wide
- `SubscriptionManager.parseVlessUrl()` is the VLESS URI parser — it handles IPv4, IPv6, and all query parameters
- `ConfigGenerator` outputs `[String: Any]` dictionaries (not Codable) serialized via `JSONSerialization`

### Security Considerations
- `SubscriptionManager` enforces HTTPS-only and blocks private/loopback hosts (SSRF mitigation)
- `ProxyManager.enablePacProxy()` validates PAC URL scheme before applying
- `SubscriptionManager` always sets `allowInsecure = false` when parsing server URLs
- `XrayManager` uses `AtomicFlag` (NSLock-based) to prevent double-resume of continuations in termination/latency handlers

### Testing Requirements
- `ConfigGenerator`: verify JSON output matches Xray's expected schema for each transport type
- `SubscriptionManager`: test base64 decoding, VLESS URL parsing edge cases (IPv6, missing params)
- `ProxyManager`: cannot unit test easily (calls system binaries) — test manually
- `Store`: test save/load round-trip, migration of missing fields

## Dependencies

### Internal
- `Models/` — all model types used throughout

### External
- Foundation (Process, FileManager, JSONSerialization, URLSession)
- Network framework (NWConnection for latency testing)

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
