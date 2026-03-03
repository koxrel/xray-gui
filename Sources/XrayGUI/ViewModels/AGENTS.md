<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-01 | Updated: 2026-03-01 -->

# ViewModels

## Purpose
Central application state management using Swift's Observation framework (`@Observable`). Contains the single source of truth for all UI-bound state and coordinates between services.

## Key Files

| File | Description |
|------|-------------|
| `AppState.swift` | The application's sole ViewModel (~560 lines). Owns all observable state (servers, subscriptions, settings, tunnels, logs, proxyStatus) and orchestrates all services. Injected into the view hierarchy via `@Environment(AppState.self)` |

## For AI Agents

### Working In This Directory
- `AppState` is `@Observable` + `@MainActor` — all mutations happen on the main thread
- It owns `Store` and `XrayManager` as stored properties, delegates to static services (`ProxyManager`, `SubscriptionManager`, `ConfigGenerator`)
- The `storeData` computed property provides a bidirectional bridge between individual observable arrays and the `StoreData` aggregate

### Key Sections in AppState
| Section | Responsibility |
|---------|---------------|
| Server Methods | CRUD, active selection, latency testing, clipboard import |
| Subscription Methods | Add, update (single/all), delete with cascading server removal |
| Proxy Control | Start/stop/restart primary tunnel, proxy mode switching |
| Multi-Tunnel | Add/pause/resume/remove secondary tunnels with auto port allocation |
| Settings | Apply with validation, auto-restart proxy on relevant changes |
| Shell Export | Generate `export http_proxy=...` strings, copy to clipboard |
| Cleanup | Graceful shutdown of all tunnels and proxy on app quit |

### Port Allocation
- `nextAvailablePorts()` increments by 2 from base ports until a free pair is found
- Prevents collisions with existing tunnels; caps at port 65535

### Common Patterns
- All service calls go through `AppState` — views never call services directly
- Pattern for mutations: get `storeData`, call `store.method(&data, ...)`, set `storeData` back
- Error handling: most operations use `try? await` and log errors via `appendLog()`

### Testing Requirements
- Changes here affect the entire app — verify both the specific feature and side effects
- Auto-restart logic triggers when proxy-relevant settings change — test that unrelated settings (theme) don't trigger restarts

## Dependencies

### Internal
- `Models/` — all model types
- `Services/` — Store, XrayManager, ProxyManager, SubscriptionManager, ConfigGenerator

### External
- SwiftUI (for `NSPasteboard` clipboard access)
- AppKit (`NSPasteboard`)

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
