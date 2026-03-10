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
    /// Design: Bold bolt glyph optimized for menu bar visibility.
    /// - Connected: Solid bolt
    /// - Disconnected: Heavy outlined bolt
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

        context.scaleBy(x: scale, y: scale)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(true)
        context.setLineJoin(.round)
        context.setLineCap(.round)

        let path = boltPath(in: CGRect(x: 1.75, y: 0.5, width: 18.5, height: 21))
        let alpha: CGFloat = connected ? 0.92 : 0.82

        if connected {
            context.setFillColor(red: 0, green: 0, blue: 0, alpha: alpha)
            context.addPath(path)
            context.fillPath()
        } else {
            context.setStrokeColor(red: 0, green: 0, blue: 0, alpha: alpha)
            context.setLineWidth(2.0)
            context.addPath(path)
            context.strokePath()
        }

        guard let cgImage = context.makeImage() else {
            return NSImage(size: size)
        }

        let image = NSImage(cgImage: cgImage, size: size)
        image.isTemplate = true
        return image
    }

    private static func boltPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let points = [
            CGPoint(x: rect.minX + rect.width * 0.64, y: rect.maxY),
            CGPoint(x: rect.minX + rect.width * 0.05, y: rect.minY + rect.height * 0.58),
            CGPoint(x: rect.minX + rect.width * 0.36, y: rect.minY + rect.height * 0.58),
            CGPoint(x: rect.minX + rect.width * 0.20, y: rect.minY + rect.height * 0.03),
            CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.45),
            CGPoint(x: rect.minX + rect.width * 0.58, y: rect.minY + rect.height * 0.45)
        ]

        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}
