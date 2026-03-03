# Xray GUI

A native macOS menu bar application for managing Xray proxy connections. Built with Swift 6.2 and SwiftUI using the Liquid Glass design language.

> **Note:** This project is vibecoded — built collaboratively with AI assistance (Claude) through iterative natural language prompting rather than traditional manual development.

## What It Does

Xray GUI lives in your menu bar and manages VLESS proxy tunnels powered by [Xray-core](https://github.com/XTLS/Xray-core). It handles server configuration, subscription updates, multi-tunnel routing, and system proxy settings — all from a clean native macOS interface.

## Features

### Server Management
- Import VLESS servers via `vless://` URLs (single or bulk from clipboard)
- Configure transport (TCP, WebSocket, gRPC, HTTP/2, HTTPUpgrade) and security (TLS, Reality)
- Test server latency with one click
- Group servers by subscription

### Subscription Management
- Add subscription URLs with automatic server import and parsing
- Auto-update on a configurable interval (default: 24 hours)
- Batch update all subscriptions at once

### Multi-Tunnel Architecture
- **Primary tunnel** with configurable HTTP (default 1087) and SOCKS5 (default 1080) ports
- **Additional tunnels** — create as many independent tunnels as you need, each with its own server and ports
- Pause/resume individual tunnels without affecting others

### Proxy Modes
- **Global** — routes HTTP, HTTPS, and SOCKS5 traffic system-wide
- **PAC** — Proxy Auto-Config with a custom URL
- **Manual** — no system proxy changes; use the ports directly

### Routing & DNS
- Custom DNS servers (defaults: 1.1.1.1, 8.8.8.8)
- Domain-based routing rules: bypass, direct, and blocked lists
- Private IP bypass (always direct)

### Menu Bar & Dashboard
- Quick connect/disconnect from the tray icon
- Switch proxy modes, servers, and tunnels without opening the main window
- Dashboard with status cards, uptime, and a shell export button (`http_proxy`, `https_proxy`, `ALL_PROXY`)
- Real-time log viewer with filtering, auto-scroll, and color-coded log levels

## Requirements

- **macOS 26** (Tahoe) or later
- **Apple Silicon** (arm64)
- Swift 6.2 toolchain (included with Xcode 26+)

## Build & Run

```bash
# Build
swift build

# Run
swift run
```

The app launches into the menu bar — look for the tray icon. It hides its dock icon automatically.

## Project Structure

```
xray-gui/
├── Package.swift                 # Swift Package Manager manifest
├── Sources/
│   ├── XrayGUI/                  # App executable
│   │   ├── XrayGUIApp.swift      # Entry point, app delegate, tray menu
│   │   ├── ViewModels/
│   │   │   └── AppState.swift
│   │   └── Views/
│   │       ├── DashboardView.swift
│   │       ├── ServersView.swift
│   │       ├── TunnelsView.swift
│   │       ├── SubscriptionsView.swift
│   │       ├── SettingsView.swift
│   │       └── LogsView.swift
│   └── XrayGUICore/              # Core library
│       ├── Models/               # ServerConfig, Tunnel, Subscription, etc.
│       └── Services/             # XrayManager, ProxyManager, ConfigGenerator, etc.
├── Resources/
│   └── xray-core/                # Bundled Xray binary
├── tools/
├── build.sh, run.sh
└── AGENTS.md, CLAUDE.md, README.md
```

## Architecture

- **Pattern:** MVVM with Swift's `@Observable` macro (not Combine)
- **State:** Single `AppState` object injected via SwiftUI `@Environment`
- **Concurrency:** `@MainActor` isolation for all UI, strict `Sendable` conformance
- **Persistence:** JSON file at `~/Library/Application Support/XrayGUI/xray-gui-data.json`
- **Process management:** Each tunnel spawns its own Xray child process with health-check polling
- **Dependencies:** Zero third-party packages — pure Foundation, SwiftUI, AppKit, and Network framework

## Settings

Configurable from the Settings tab:

| Setting | Default | Description |
|---------|---------|-------------|
| HTTP Port | 1087 | Local HTTP proxy port |
| SOCKS5 Port | 1080 | Local SOCKS5 proxy port |
| Allow LAN | Off | Listen on all interfaces vs. localhost only |
| Auto-start | Off | Connect on app launch |
| Log Level | Warning | Xray log verbosity (debug/info/warning/error/none) |
| Mux | Off | Connection multiplexing (incompatible with XTLS flows) |
| DNS Servers | 1.1.1.1, 8.8.8.8 | Upstream DNS resolvers |
| Theme | System | System / Light / Dark |

## License

This project is for personal use.
