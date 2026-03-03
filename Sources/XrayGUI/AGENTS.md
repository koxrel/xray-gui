<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-01 | Updated: 2026-03-01 -->

# XrayGUI

## Purpose
Root of the application module. Contains the `@main` app entry point and is organized into MVVM layers: Models, ViewModels, Views, Services, and Utilities.

## Key Files

| File | Description |
|------|-------------|
| `XrayGUIApp.swift` | App entry point (`@main`), window/scene setup, `MenuBarExtra` tray menu, `AppDelegate` for lifecycle, and `TrayMenuView` for the menu bar dropdown |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `Models/` | Data model structs and enums (see `Models/AGENTS.md`) |
| `ViewModels/` | Observable state management (see `ViewModels/AGENTS.md`) |
| `Views/` | SwiftUI view layer (see `Views/AGENTS.md`) |
| `Services/` | Business logic — persistence, process management, networking (see `Services/AGENTS.md`) |
| `Utilities/` | Helpers — icon rendering (see `Utilities/AGENTS.md`) |

## For AI Agents

### Working In This Directory
- `XrayGUIApp.swift` is the app entry point — it defines two scenes:
  1. `Window("Xray GUI", id: "main")` — the main dashboard window
  2. `MenuBarExtra` — the always-visible tray icon and dropdown menu
- The app hides its dock icon on launch via `NSApp.setActivationPolicy(.accessory)`
- `AppDelegate` handles `applicationWillTerminate` to cleanly stop xray processes and disable system proxy
- `TrayMenuView` (~170 lines) provides quick access to connect/disconnect, server selection, tunnel management, and proxy mode switching

### Data Flow
```
XrayGUIApp
  └─ AppState (@Observable, @Environment)
       ├─ Store (JSON persistence)
       ├─ XrayManager (process lifecycle)
       ├─ ProxyManager (system proxy via networksetup)
       ├─ SubscriptionManager (fetch & parse VLESS URLs)
       └─ ConfigGenerator (Xray JSON config)
```

### Common Patterns
- State is shared via `@Environment(AppState.self)` — every view reads from the single `AppState` instance
- Async operations use `Task { }` blocks inside SwiftUI button actions
- Error handling: most errors are caught and logged via `appState.appendLog("[Error] ...")`

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
