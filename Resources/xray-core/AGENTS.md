<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-01 | Updated: 2026-03-01 -->

# xray-core

## Purpose
Pre-built Xray proxy binary and associated geodata files for macOS arm64. These are bundled into the app at build time and used at runtime to establish proxy tunnels.

## Key Files

| File | Description |
|------|-------------|
| `xray` | Xray-core binary (arm64-apple-macosx, ~31MB) — the proxy engine |
| `geoip.dat` | IP geolocation database (~19MB) for routing rules (e.g., `geoip:private`) |
| `geosite.dat` | Domain categorization database (~10MB) for routing rules (e.g., `geosite:category-ads-all`) |
| `LICENSE` | Xray-core license file |
| `README.md` | Xray-core documentation |

## For AI Agents

### Working In This Directory
- **Do not modify these files** — they are upstream binary artifacts
- The `xray` binary is invoked as: `xray run -c <config.json>`
- `XrayManager.getXrayBinaryPath()` resolves the binary location at runtime
- Geodata files are referenced in routing rules via `ConfigGenerator.buildRoutingRules()`
- To update xray-core, replace these files with a newer release from the upstream project

### Security Notes
- The binary runs with the user's permissions (no root/sudo)
- It binds to local ports (default HTTP 1087, SOCKS 1080)
- The app sets `posixPermissions: 0o755` on the binary before execution

<!-- MANUAL: Any manually added notes below this line are preserved on regeneration -->
