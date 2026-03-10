# Tray Icon Redesign Design

## Context

The current menu bar icon is a prism-and-rays mark rendered programmatically in `Sources/XrayGUI/Utilities/TrayIcon.swift`. It uses fine geometry and leaves too much unused space in the 22pt menu bar canvas, which makes it easy to miss in a crowded macOS tray.

## Approved Direction

Replace the current icon with a simpler, bolder bolt glyph that occupies more of the same 22pt canvas.

- Connected state: filled bolt
- Disconnected state: outlined version of the same bolt
- Rendering model: keep using a template `NSImage` generated in code so the icon continues to adapt to light/dark menu bar appearances automatically

## Rationale

The bolt is the strongest option for tray visibility because it is compact, high-contrast, and legible at small sizes. Reusing the same silhouette across both states preserves recognizability, while the fill versus outline treatment keeps the active/inactive distinction clear without adding extra detail.

## Constraints

- Preserve the current `MenuBarExtra` integration in `Sources/XrayGUI/XrayGUIApp.swift`
- Keep the icon generated programmatically; do not introduce bundled image assets
- Retain a template image so macOS controls final tinting
- Verify the result with a build and targeted tests
