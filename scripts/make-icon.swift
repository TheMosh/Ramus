// Renders Ramus's app icon artwork: a full-bleed 1024×1024 square that macOS masks to its icon shape.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size = 1024
let outputPath = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let canvas = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(colors: [
    NSColor(srgbRed: 0.40, green: 0.72, blue: 1.00, alpha: 1),
    NSColor(srgbRed: 0.10, green: 0.36, blue: 0.92, alpha: 1),
])!.draw(in: canvas, angle: -90)

let configuration = NSImage.SymbolConfiguration(pointSize: 470, weight: .medium)
    .applying(.init(paletteColors: [.white]))
let symbol = NSImage(systemSymbolName: "memorychip.fill", accessibilityDescription: nil)!
    .withSymbolConfiguration(configuration)!

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.shadowBlurRadius = 36
shadow.set()

let symbolRect = NSRect(
    x: (CGFloat(size) - symbol.size.width) / 2,
    y: (CGFloat(size) - symbol.size.height) / 2,
    width: symbol.size.width,
    height: symbol.size.height
)
symbol.draw(in: symbolRect)

NSGraphicsContext.restoreGraphicsState()
try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outputPath))
