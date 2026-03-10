# Tray Icon Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current small prism tray icon with a larger-reading bolt glyph that is filled when connected and outlined when disconnected.

**Architecture:** Keep the existing `MenuBarExtra` label wiring and replace only the renderer in `TrayIcon.swift`. Add a lightweight `XrayGUITests` target so the icon geometry can be exercised with TDD by asserting visible pixel coverage and state differences before changing production code.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, CoreGraphics, Swift Testing, Swift Package Manager.

---

### Task 1: Add app-side tray icon tests

**Files:**
- Modify: `Package.swift`
- Create: `Tests/XrayGUITests/TrayIconTests.swift`

**Step 1: Write the failing test**

Create tests that render the current `TrayIcon` images and assert:

- the connected icon fills a substantial portion of the 22pt canvas
- the disconnected icon still has strong visible coverage
- the filled and outlined states do not render identical alpha maps

**Step 2: Run test to verify it fails**

Run: `swift test --filter TrayIconTests`

Expected: FAIL because the current prism icon does not meet the new visibility thresholds or because the test target is not wired yet.

**Step 3: Write minimal implementation**

Add a new `XrayGUITests` target in `Package.swift` that depends on `XrayGUI`, then keep the failing assertions focused on icon visibility characteristics rather than exact snapshots.

**Step 4: Run test to verify it passes compilation and still fails behaviorally**

Run: `swift test --filter TrayIconTests`

Expected: build succeeds for the new test target and the visibility assertions fail against the current icon.

**Step 5: Commit**

```bash
git add Package.swift Tests/XrayGUITests/TrayIconTests.swift
git commit -m "test: add tray icon visibility tests"
```

### Task 2: Replace the renderer with the bolt glyph

**Files:**
- Modify: `Sources/XrayGUI/Utilities/TrayIcon.swift`
- Modify: `Sources/XrayGUI/Utilities/AGENTS.md`

**Step 1: Write the failing test**

Reuse the visibility tests from Task 1 as the red state; do not weaken the thresholds to fit the old renderer.

**Step 2: Run test to verify it fails**

Run: `swift test --filter TrayIconTests`

Expected: FAIL with coverage or state-difference assertions against the current prism icon.

**Step 3: Write minimal implementation**

Replace the prism/rays SDF logic with a centered bolt shape that:

- uses thicker geometry
- occupies more horizontal and vertical space
- renders filled when connected
- renders as a bold outline when disconnected

Update the utility documentation comment to describe the new glyph accurately.

**Step 4: Run test to verify it passes**

Run: `swift test --filter TrayIconTests`

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/XrayGUI/Utilities/TrayIcon.swift Sources/XrayGUI/Utilities/AGENTS.md
git commit -m "feat: switch tray icon to bold bolt glyph"
```

### Task 3: Final verification

**Files:**
- No code changes required unless verification exposes an issue

**Step 1: Run the focused automated checks**

Run: `swift test --filter TrayIconTests`

Expected: PASS

**Step 2: Run package build**

Run: `swift build`

Expected: BUILD SUCCEEDED

**Step 3: Optional manual verification**

Run: `swift run`

Expected: the tray icon appears larger and easier to spot in the macOS menu bar, with filled and outlined states switching correctly.

**Step 4: Commit**

```bash
git add docs/plans/2026-03-06-tray-icon-redesign-design.md docs/plans/2026-03-06-tray-icon-redesign.md
git commit -m "docs: capture tray icon redesign plan"
```
