#!/usr/bin/env swift
//
// generate-app-icon.swift
// Generates the Xray GUI app icon (.icns) for macOS Launchpad/Finder.
//
// Design: "Xray Prism" — a diamond prism refracting a beam of light into
// three spectral rays (cyan, white, violet) on a deep indigo background.
// Matches the tray-icon branding from TrayIcon.swift but in full colour.
//
// Usage:  swift tools/generate-app-icon.swift [output-path]
//         Default output: Resources/AppIcon.icns
//

import Foundation
import CoreGraphics
import ImageIO

// MARK: - Colour helpers

private let cs = CGColorSpaceCreateDeviceRGB()

private func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

// MARK: - Beam path builder

/// A closed quadrilateral tapering from `wStart` at `origin` to `wEnd` at `tip`.
private func beamPath(
    origin: CGPoint, tip: CGPoint,
    wStart: CGFloat, wEnd: CGFloat
) -> CGPath {
    let dx = tip.x - origin.x
    let dy = tip.y - origin.y
    let len = sqrt(dx * dx + dy * dy)
    guard len > 0 else { return CGMutablePath() }
    // Perpendicular unit vector
    let nx = -dy / len
    let ny =  dx / len
    let p = CGMutablePath()
    p.move(to:    CGPoint(x: origin.x + nx * wStart / 2, y: origin.y + ny * wStart / 2))
    p.addLine(to: CGPoint(x: tip.x    + nx * wEnd   / 2, y: tip.y    + ny * wEnd   / 2))
    p.addLine(to: CGPoint(x: tip.x    - nx * wEnd   / 2, y: tip.y    - ny * wEnd   / 2))
    p.addLine(to: CGPoint(x: origin.x - nx * wStart / 2, y: origin.y - ny * wStart / 2))
    p.closeSubpath()
    return p
}

// MARK: - Diamond path builder

private func diamondPath(center: CGPoint, halfDiag: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to:    CGPoint(x: center.x,             y: center.y + halfDiag)) // top
    p.addLine(to: CGPoint(x: center.x + halfDiag,  y: center.y))           // right
    p.addLine(to: CGPoint(x: center.x,             y: center.y - halfDiag)) // bottom
    p.addLine(to: CGPoint(x: center.x - halfDiag,  y: center.y))           // left
    p.closeSubpath()
    return p
}

// MARK: - Icon renderer

private func renderIcon(size: Int) -> CGImage? {
    let s = CGFloat(size)
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // ── Geometry ──────────────────────────────────────────────
    let diamondHalf = s * 0.21          // half-diagonal
    let cx          = s * 0.40          // diamond centre X (left of canvas centre)
    let cy          = s * 0.50          // diamond centre Y
    let bgCentre    = CGPoint(x: cx, y: cy)

    let dRight = CGPoint(x: cx + diamondHalf, y: cy)
    let dLeft  = CGPoint(x: cx - diamondHalf, y: cy)
    let dTop   = CGPoint(x: cx,               y: cy + diamondHalf)
    let dBot   = CGPoint(x: cx,               y: cy - diamondHalf)

    // Beam origin: slightly inside the diamond so the prism covers the join
    let bO       = CGPoint(x: dRight.x - s * 0.015, y: cy)
    let midLen   = s * 0.34
    let sideLen  = s * 0.28
    let fan      = CGFloat(26) * .pi / 180
    let wS       = s * 0.028          // beam width at prism
    let wE       = s * 0.006          // beam width at tip

    let midTip   = CGPoint(x: bO.x + midLen,                  y: bO.y)
    let upTip    = CGPoint(x: bO.x + sideLen * cos(fan),      y: bO.y + sideLen * sin(fan))
    let downTip  = CGPoint(x: bO.x + sideLen * cos(fan),      y: bO.y - sideLen * sin(fan))

    // ── 1. Background radial gradient ────────────────────────
    do {
        let colors = [rgba(0.07, 0.06, 0.25), rgba(0.015, 0.015, 0.06)] as CFArray
        if let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1] as [CGFloat]) {
            ctx.drawRadialGradient(
                g,
                startCenter: bgCentre, startRadius: 0,
                endCenter: CGPoint(x: s * 0.5, y: s * 0.5), endRadius: s * 0.80,
                options: .drawsAfterEndLocation)
        }
    }

    // ── 2. Ambient glow behind the prism ─────────────────────
    do {
        let colors = [rgba(0.18, 0.15, 0.60, 0.22), rgba(0.10, 0.08, 0.35, 0.0)] as CFArray
        if let g = CGGradient(colorsSpace: cs, colors: colors, locations: nil) {
            ctx.drawRadialGradient(
                g,
                startCenter: bgCentre, startRadius: 0,
                endCenter: bgCentre, endRadius: s * 0.35,
                options: [])
        }
    }

    // ── 3. Incoming beam from the left (subtle) ──────────────
    do {
        let inOrigin = CGPoint(x: s * 0.06, y: cy)
        let inTip    = CGPoint(x: dLeft.x + s * 0.015, y: cy)
        let p = beamPath(origin: inOrigin, tip: inTip,
                         wStart: s * 0.007, wEnd: s * 0.022)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: s * 0.018,
                       color: rgba(0.65, 0.70, 1.0, 0.30))
        ctx.addPath(p)
        ctx.setFillColor(rgba(0.85, 0.88, 1.0, 0.22))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // ── 4. Spectral beams with glow ──────────────────────────
    let beams: [(tip: CGPoint, fill: CGColor, glow: CGColor)] = [
        (upTip,   rgba(0.0,  0.85, 1.0,  0.92), rgba(0.0,  0.55, 0.88, 0.55)),
        (midTip,  rgba(0.93, 0.96, 1.0,  0.96), rgba(0.45, 0.55, 0.95, 0.45)),
        (downTip, rgba(0.72, 0.30, 1.0,  0.92), rgba(0.50, 0.16, 0.82, 0.55)),
    ]
    let blurR = s * 0.030
    for b in beams {
        let p = beamPath(origin: bO, tip: b.tip, wStart: wS, wEnd: wE)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: blurR, color: b.glow)
        ctx.addPath(p)
        ctx.setFillColor(b.fill)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // ── 5. Diamond prism (on top so beams emerge from behind) ─
    let diamond = diamondPath(center: bgCentre, halfDiag: diamondHalf)

    // 5a. Outer glow around the prism
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.035,
                   color: rgba(0.4, 0.5, 1.0, 0.30))
    ctx.addPath(diamond)
    ctx.setFillColor(rgba(0.6, 0.7, 0.95, 0.10))
    ctx.fillPath()
    ctx.restoreGState()

    // 5b. Glass-gradient fill
    ctx.saveGState()
    ctx.addPath(diamond)
    ctx.clip()
    let prismColors = [rgba(0.42, 0.55, 0.88, 0.90), rgba(0.78, 0.87, 1.0, 0.94)] as CFArray
    if let g = CGGradient(colorsSpace: cs, colors: prismColors, locations: nil) {
        ctx.drawLinearGradient(
            g,
            start: CGPoint(x: dLeft.x, y: dBot.y),
            end:   CGPoint(x: dRight.x, y: dTop.y),
            options: [])
    }

    // 5c. Specular highlight (top-left of diamond)
    let specColors = [rgba(1, 1, 1, 0.35), rgba(1, 1, 1, 0.0)] as CFArray
    if let g = CGGradient(colorsSpace: cs, colors: specColors, locations: nil) {
        let specCentre = CGPoint(x: cx - diamondHalf * 0.22,
                                  y: cy + diamondHalf * 0.22)
        ctx.drawRadialGradient(
            g,
            startCenter: specCentre, startRadius: 0,
            endCenter: specCentre, endRadius: diamondHalf * 0.50,
            options: [])
    }
    ctx.restoreGState()

    // 5d. Edge highlight stroke
    ctx.addPath(diamond)
    ctx.setStrokeColor(rgba(1, 1, 1, 0.40))
    ctx.setLineWidth(max(s * 0.008, 0.5))
    ctx.strokePath()

    // ── 6. Tiny bright dot at the refraction point ───────────
    do {
        let dotR = s * 0.018
        let dotColors = [rgba(1, 1, 1, 0.50), rgba(1, 1, 1, 0.0)] as CFArray
        if let g = CGGradient(colorsSpace: cs, colors: dotColors, locations: nil) {
            ctx.drawRadialGradient(
                g,
                startCenter: dRight, startRadius: 0,
                endCenter: dRight, endRadius: dotR,
                options: [])
        }
    }

    return ctx.makeImage()
}

// MARK: - PNG writer

private func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, "public.png" as CFString, 1, nil
    ) else {
        fputs("error: cannot create \(path)\n", stderr)
        return
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) {
        fputs("error: failed writing \(path)\n", stderr)
    }
}

// MARK: - Main

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()

// Determine output path
let outputPath: String
if CommandLine.arguments.count > 1 {
    let arg = CommandLine.arguments[1]
    if arg.hasPrefix("/") {
        outputPath = arg
    } else {
        outputPath = FileManager.default.currentDirectoryPath + "/" + arg
    }
} else {
    outputPath = projectRoot.appendingPathComponent("Resources/AppIcon.icns").path
}

let fm = FileManager.default
let tmpDir = fm.temporaryDirectory.appendingPathComponent("xraygui-iconset-\(ProcessInfo.processInfo.processIdentifier)")
let iconsetPath = tmpDir.appendingPathComponent("AppIcon.iconset")

try? fm.removeItem(at: tmpDir)
try fm.createDirectory(at: iconsetPath, withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16",       16), ("icon_16x16@2x",    32),
    ("icon_32x32",       32), ("icon_32x32@2x",    64),
    ("icon_128x128",    128), ("icon_128x128@2x",  256),
    ("icon_256x256",    256), ("icon_256x256@2x",  512),
    ("icon_512x512",    512), ("icon_512x512@2x", 1024),
]

print("Generating Xray GUI app icon...")
for (name, px) in variants {
    guard let img = renderIcon(size: px) else {
        fputs("  FAIL  \(name) (\(px)px)\n", stderr)
        continue
    }
    writePNG(img, to: iconsetPath.appendingPathComponent("\(name).png").path)
    print("  ok  \(name) (\(px)px)")
}

print("Running iconutil...")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetPath.path, "-o", outputPath]
try proc.run()
proc.waitUntilExit()

guard proc.terminationStatus == 0 else {
    fputs("iconutil failed (exit \(proc.terminationStatus))\n", stderr)
    try? fm.removeItem(at: tmpDir)
    exit(1)
}

try? fm.removeItem(at: tmpDir)

let attrs = try fm.attributesOfItem(atPath: outputPath)
let bytes = (attrs[.size] as? Int) ?? 0
print("Created \(outputPath) (\(bytes) bytes)")
