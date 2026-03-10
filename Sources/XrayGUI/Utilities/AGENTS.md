<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-01 | Updated: 2026-03-01 -->

# Utilities

## Purpose
Helper utilities for the application. Currently contains the programmatic menu bar icon renderer.

## Key Files

| File | Description |
|------|-------------|
| `TrayIcon.swift` | Generates the menu bar tray icon as a template `NSImage` using Core Graphics vector drawing. Draws a bold bolt glyph — filled when connected, outlined when disconnected. Renders at 22pt @2x (44px) |

## For AI Agents

### Working In This Directory
- `TrayIcon.create(connected:)` is called from `XrayGUIApp.swift` in the `MenuBarExtra` label
- The icon is an `NSImage` with `isTemplate = true` — macOS automatically adapts it for light/dark mode and vibrancy
- The rendering uses a manually defined Core Graphics path for a bold bolt silhouette
- No image assets are needed — everything is generated programmatically
- Modifying the icon shape: adjust the control points in `boltPath(in:)`

### Testing Requirements
- Build and run the app — the icon appears in the macOS menu bar
- Verify both connected (filled bolt) and disconnected (outlined bolt) states
- Test with both light and dark macOS appearance

## Dependencies

### External
- AppKit (`NSImage`)
- CoreGraphics (`CGContext`, `CGImage`)

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
