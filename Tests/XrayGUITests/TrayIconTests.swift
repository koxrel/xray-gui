import AppKit
import Testing
@testable import XrayGUI

@Suite("Tray Icon Tests")
struct TrayIconTests {
    @Test("Connected tray icon has strong pixel coverage")
    func connectedIconHasStrongCoverage() throws {
        let coverage = try visiblePixelRatio(for: TrayIcon.create(connected: true))
        #expect(coverage >= 0.24, "Expected connected icon coverage >= 0.24, got \(coverage)")
    }

    @Test("Disconnected tray icon remains easy to spot")
    func disconnectedIconHasStrongCoverage() throws {
        let coverage = try visiblePixelRatio(for: TrayIcon.create(connected: false))
        #expect(coverage >= 0.14, "Expected disconnected icon coverage >= 0.14, got \(coverage)")
    }

    @Test("Disconnected tray icon outline stays lighter than the connected fill")
    func disconnectedIconStaysLighterThanConnectedFill() throws {
        let coverage = try visiblePixelRatio(for: TrayIcon.create(connected: false))
        #expect(coverage <= 0.30, "Expected disconnected icon coverage <= 0.30, got \(coverage)")
    }

    @Test("Connected and disconnected tray icons are visibly different")
    func trayIconsUseDistinctAlphaMaps() throws {
        let connected = try alphaMask(for: TrayIcon.create(connected: true))
        let disconnected = try alphaMask(for: TrayIcon.create(connected: false))

        let changedPixels = zip(connected, disconnected).filter { abs(Int($0) - Int($1)) > 32 }.count
        let deltaRatio = Double(changedPixels) / Double(connected.count)

        #expect(deltaRatio >= 0.10, "Expected icon alpha delta >= 0.10, got \(deltaRatio)")
    }

    private func visiblePixelRatio(for image: NSImage) throws -> Double {
        let alpha = try alphaMask(for: image)
        let visiblePixels = alpha.filter { $0 > 24 }.count
        return Double(visiblePixels) / Double(alpha.count)
    }

    private func alphaMask(for image: NSImage) throws -> [UInt8] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            struct MissingCGImage: Error {}
            throw MissingCGImage()
        }

        guard
            let provider = cgImage.dataProvider,
            let data = provider.data
        else {
            struct MissingDataProvider: Error {}
            throw MissingDataProvider()
        }

        let bytes = CFDataGetBytePtr(data)!
        let byteCount = CFDataGetLength(data)
        let bytesPerPixel = cgImage.bitsPerPixel / 8

        return stride(from: 0, to: byteCount, by: bytesPerPixel).map { offset in
            bytes[offset + bytesPerPixel - 1]
        }
    }
}
