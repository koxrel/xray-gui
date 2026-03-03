<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-01 | Updated: 2026-03-01 -->

# resources

## Purpose
Contains bundled binary dependencies and data files that are copied into the app bundle at build time via SwiftPM's `.copy()` resource rule.

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `xray-core/` | Xray proxy binary and geodata files (see `xray-core/AGENTS.md`) |

## For AI Agents

### Working In This Directory
- These are **pre-built binaries and data files** — do not modify them directly
- The root `Package.swift` references this directory via `.copy("../../Resources/xray-core")` (relative to Sources/XrayGUI/)
- The xray binary must be **arm64 macOS** compatible
- Binary permissions are set to `0o755` at runtime by `XrayManager`

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
