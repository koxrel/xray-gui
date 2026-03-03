import AppKit
import CoreGraphics

enum TrayIcon {
    private static let connectedIcon: NSImage = generateIcon(connected: true)
    private static let disconnectedIcon: NSImage = generateIcon(connected: false)

    /// Returns a cached template NSImage for the menu bar.
    static func create(connected: Bool) -> NSImage {
        connected ? connectedIcon : disconnectedIcon
    }

    /// Generates a template NSImage for the menu bar (22pt @2x = 44px).
    ///
    /// Design: Diamond prism emitting refracted rays — evokes the "Xray" name.
    /// - Connected: Solid diamond with three tapered beams fanning rightward.
    /// - Disconnected: Diamond outline only (dormant prism).
    private static func generateIcon(connected: Bool) -> NSImage {
        let size = CGSize(width: 22, height: 22)
        let scale: CGFloat = 2
        let pixelW = Int(size.width * scale)
        let pixelH = Int(size.height * scale)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: pixelW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(size: size)
        }

        let w = CGFloat(pixelW)
        let h = CGFloat(pixelH)
        let aa: CGFloat = 0.04  // anti-alias smoothing radius

        for py in 0..<pixelH {
            for px in 0..<pixelW {
                // Map pixel to [-1, 1] with half-pixel centering for sub-pixel accuracy
                let nx = (CGFloat(px) + 0.5) / w * 2.0 - 1.0
                let ny = (CGFloat(py) + 0.5) / h * 2.0 - 1.0

                var alpha: CGFloat = 0

                if connected {
                    // Filled diamond + three radiating beams
                    let dDiamond = diamondSDF(nx: nx, ny: ny)
                    let dRays = raysSDF(nx: nx, ny: ny)
                    let d = min(dDiamond, dRays)  // union of shapes
                    alpha = smoothstep(edge0: aa, edge1: -aa, x: d) * 0.9
                } else {
                    // Outlined diamond (dormant prism)
                    let dDiamond = diamondSDF(nx: nx, ny: ny)
                    let strokeW: CGFloat = 0.09
                    let strokeDist = abs(dDiamond) - strokeW / 2
                    alpha = smoothstep(edge0: aa, edge1: -aa, x: strokeDist) * 0.78
                }

                if alpha > 0.003 {
                    context.setFillColor(red: 0, green: 0, blue: 0, alpha: alpha)
                    context.fill(CGRect(x: px, y: pixelH - 1 - py, width: 1, height: 1))
                }
            }
        }

        guard let cgImage = context.makeImage() else {
            return NSImage(size: size)
        }

        let image = NSImage(cgImage: cgImage, size: size)
        image.isTemplate = true
        return image
    }

    // MARK: - SDF Primitives

    /// Diamond (rotated square) prism, centered slightly left for balance with rays.
    /// Uses L1 norm: negative inside, positive outside.
    private static func diamondSDF(nx: CGFloat, ny: CGFloat) -> CGFloat {
        let cx: CGFloat = -0.18
        let halfDiag: CGFloat = 0.34
        return abs(nx - cx) + abs(ny) - halfDiag
    }

    /// Three tapered beams fanning rightward from the diamond's right vertex.
    /// Middle beam is longest; outer beams are slightly shorter and angled ±24°.
    private static func raysSDF(nx: CGFloat, ny: CGFloat) -> CGFloat {
        // Start slightly inside the diamond so rays emerge seamlessly from the edge
        let ox: CGFloat = 0.14
        let oy: CGFloat = 0.0

        let midLen: CGFloat = 0.58
        let sideLen: CGFloat = 0.48
        let fanAngle: CGFloat = 24.0 * .pi / 180.0

        let wStart: CGFloat = 0.052  // thick at the prism
        let wEnd: CGFloat = 0.018    // tapers to a fine point

        // Middle ray (horizontal, longest)
        let d1 = taperedLineSDF(
            px: nx, py: ny,
            ax: ox, ay: oy,
            bx: ox + midLen, by: oy,
            wStart: wStart, wEnd: wEnd
        )

        // Upper ray (angled upward)
        let d2 = taperedLineSDF(
            px: nx, py: ny,
            ax: ox, ay: oy,
            bx: ox + sideLen * cos(fanAngle),
            by: oy - sideLen * sin(fanAngle),
            wStart: wStart, wEnd: wEnd
        )

        // Lower ray (angled downward)
        let d3 = taperedLineSDF(
            px: nx, py: ny,
            ax: ox, ay: oy,
            bx: ox + sideLen * cos(fanAngle),
            by: oy + sideLen * sin(fanAngle),
            wStart: wStart, wEnd: wEnd
        )

        return min(d1, min(d2, d3))
    }

    /// SDF for a line segment from A to B with linearly tapering half-width.
    /// Produces rounded caps at both ends.
    private static func taperedLineSDF(
        px: CGFloat, py: CGFloat,
        ax: CGFloat, ay: CGFloat,
        bx: CGFloat, by: CGFloat,
        wStart: CGFloat, wEnd: CGFloat
    ) -> CGFloat {
        let pax = px - ax, pay = py - ay
        let bax = bx - ax, bay = by - ay
        let lenSq = bax * bax + bay * bay
        guard lenSq > 0 else { return sqrt(pax * pax + pay * pay) - wStart }
        let t = min(max((pax * bax + pay * bay) / lenSq, 0), 1)

        let nearX = ax + t * bax
        let nearY = ay + t * bay
        let dx = px - nearX
        let dy = py - nearY

        let width = wStart + (wEnd - wStart) * t
        return sqrt(dx * dx + dy * dy) - width
    }

    /// Hermite smoothstep for anti-aliased SDF rendering.
    private static func smoothstep(edge0: CGFloat, edge1: CGFloat, x: CGFloat) -> CGFloat {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
