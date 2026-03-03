<!-- Generated: 2026-03-01 | Updated: 2026-03-04 -->

# xray-gui

## Purpose
A native macOS menu bar application for managing Xray proxy connections, built with Swift 6.2 and SwiftUI. Runs as a menu bar extra (tray icon) with an optional main window, supporting VLESS protocol servers, subscription management, multi-tunnel routing, and system proxy configuration.

## Key Files

| File | Description |
|------|-------------|
| `Package.swift` | Swift Package Manager manifest (macOS 26, Swift 6.2) |
| `CLAUDE.md` | Project-level AI instructions |
| `build.sh` | Release build and install script |
| `run.sh` | Quick debug build + launch |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `Sources/XrayGUI/` | App executable target — entry point, views, view models |
| `Sources/XrayGUICore/` | Core library target — models and services |
| `Tests/XrayGUICoreTests/` | Unit tests for the core library |
| `Resources/` | Bundled binary dependencies (see `Resources/AGENTS.md`) |
| `tools/` | Development utilities (icon generator) |

## For AI Agents

### Working In This Directory
- This is a **Swift Package Manager** project targeting **macOS 26** (Tahoe) on Apple Silicon (arm64)
- The Swift toolchain version is **6.2** with strict concurrency enabled by default
- Build with `swift build` from the repo root
- Run with `swift run` from the repo root
- The app uses SwiftUI's new **Liquid Glass** design language (`.glassEffect`, `.buttonStyle(.glass)`)
- The app hides its dock icon (`NSApp.setActivationPolicy(.accessory)`) — it lives in the menu bar

### Architecture Overview
- **Pattern**: MVVM with `@Observable` (Swift Observation framework, not Combine)
- **State**: Single `AppState` class injected via SwiftUI `@Environment`
- **Persistence**: JSON file at `~/Library/Application Support/XrayGUI/xray-gui-data.json`
- **Process management**: Xray binary spawned as child `Process`, one per tunnel
- **System proxy**: Configured via `/usr/sbin/networksetup` shell calls
- **Protocol**: VLESS only (no VMess, Shadowsocks, or Trojan)

### Key Conventions
- All UI code is `@MainActor`-isolated
- Services use `enum` namespaces (stateless) or `final class` (stateful, `Sendable`)
- Models are `struct`s conforming to `Codable, Identifiable, Equatable, Sendable`
- No third-party dependencies — pure Foundation + SwiftUI + AppKit + Network framework

### Testing Requirements
- No test targets exist yet — test changes manually by building and running
- Build: `swift build`
- Run: `swift run`

## Dependencies

### External
- Xray-core binary (bundled in `Resources/xray-core/`)
- macOS system frameworks: SwiftUI, AppKit, Foundation, Network, CoreGraphics

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
