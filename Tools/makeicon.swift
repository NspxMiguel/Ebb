#!/usr/bin/env swift
import AppKit

// Draws the Ebb icon set: a deep sea teal rounded square with three white
// waves in the lower half, shorter and fainter towards the bottom, like a tide
// going out. Run at build time: `swift Tools/makeicon.swift <out.iconset>`.

func wave(in rect: NSRect, y: CGFloat, inset: CGFloat, amplitude: CGFloat, cycles: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let start = rect.minX + inset
    let width = rect.width - inset * 2
    let steps = 96
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps)
        let point = NSPoint(x: start + width * t, y: y + sin(t * cycles * 2 * .pi) * amplitude)
        step == 0 ? path.move(to: point) : path.line(to: point)
    }
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    return path
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    // macOS icon grid: the tile leaves a margin around it for the shadow area.
    let margin = size * 0.1
    let tile = NSRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
    let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)

    let top = NSColor(srgbRed: 20 / 255, green: 128 / 255, blue: 133 / 255, alpha: 1)
    let bottom = NSColor(srgbRed: 14 / 255, green: 110 / 255, blue: 115 / 255, alpha: 1)
    NSGradient(starting: bottom, ending: top)?.draw(in: shape, angle: 90)

    // AppKit's origin is bottom-left: smaller y is lower on the icon.
    let waves: [(y: CGFloat, inset: CGFloat, width: CGFloat, alpha: CGFloat)] = [
        (0.52, 0.16, 0.050, 1.0),
        (0.37, 0.24, 0.040, 0.78),
        (0.23, 0.32, 0.030, 0.55),
    ]
    for item in waves {
        let path = wave(
            in: tile, y: tile.minY + tile.height * item.y, inset: tile.width * item.inset,
            amplitude: tile.height * 0.035, cycles: 1.5)
        path.lineWidth = size * item.width
        NSColor(white: 1, alpha: item.alpha).setStroke()
        path.stroke()
    }
    return image
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

let variants: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, size) in variants {
    // Render into a bitmap of exactly `size` pixels; NSImage alone would
    // follow the screen's scale factor and write @2x-sized files everywhere.
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
    else { continue }
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: size).draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: URL(fileURLWithPath: "\(output)/\(name).png"))
}
print("iconset at \(output)")
