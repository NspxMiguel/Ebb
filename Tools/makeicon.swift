#!/usr/bin/env swift
import AppKit

// Draws AppIcon.icns: a deep sea teal rounded square with three white
// horizontal wave strokes stacked in the lower half, suggesting an ebbing tide.
// No text, no emoji. Generated at build time.

func drawIcon(size: CGFloat) -> NSImage {
  let image = NSImage(size: NSSize(width: size, height: size))
  image.lockFocus()
  guard let ctx = NSGraphicsContext.current?.cgContext else {
    image.unlockFocus()
    return image
  }
  ctx.setShouldAntialias(true)

  // Rounded square background with generous margins.
  let inset = size * 0.1
  let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
  let radius = rect.width * 0.225
  let background = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

  // Deep sea teal fill with subtle gradient.
  let colorTop = NSColor(
    red: 14.0 / 255.0,
    green: 110.0 / 255.0,
    blue: 115.0 / 255.0,
    alpha: 1.0
  )
  let colorBottom = NSColor(
    red: 20.0 / 255.0,
    green: 130.0 / 255.0,
    blue: 135.0 / 255.0,
    alpha: 1.0
  )

  let gradient = NSGradient(starting: colorTop, ending: colorBottom)
  gradient?.draw(in: background, angle: 90)

  // Three white horizontal wave strokes in the lower half, decreasing width.
  let waveAreaStart = rect.midY + rect.height * 0.05
  let waveSpacing = rect.height * 0.12

  let strokeColor = NSColor.white
  strokeColor.setStroke()

  // Wave 1: widest, highest opacity
  let wave1 = NSBezierPath()
  wave1.lineWidth = size * 0.038
  wave1.lineCapStyle = .round
  wave1.move(to: NSPoint(x: rect.minX + rect.width * 0.15, y: waveAreaStart))
  wave1.line(to: NSPoint(x: rect.maxX - rect.width * 0.15, y: waveAreaStart))
  wave1.stroke()

  // Wave 2: medium width, medium opacity
  let wave2 = NSBezierPath()
  wave2.lineWidth = size * 0.028
  wave2.lineCapStyle = .round
  wave2.move(to: NSPoint(x: rect.minX + rect.width * 0.22, y: waveAreaStart + waveSpacing))
  wave2.line(to: NSPoint(x: rect.maxX - rect.width * 0.22, y: waveAreaStart + waveSpacing))
  NSColor(white: 1, alpha: 0.85).setStroke()
  wave2.stroke()

  // Wave 3: narrowest, lowest opacity
  let wave3 = NSBezierPath()
  wave3.lineWidth = size * 0.018
  wave3.lineCapStyle = .round
  wave3.move(to: NSPoint(x: rect.minX + rect.width * 0.32, y: waveAreaStart + waveSpacing * 2))
  wave3.line(to: NSPoint(x: rect.maxX - rect.width * 0.32, y: waveAreaStart + waveSpacing * 2))
  NSColor(white: 1, alpha: 0.7).setStroke()
  wave3.stroke()

  image.unlockFocus()
  return image
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

let variants: [(String, CGFloat)] = [
  ("icon_16x16", 16), ("icon_16x16@2x", 32),
  ("icon_32x32", 32), ("icon_32x32@2x", 64),
  ("icon_128x128", 128), ("icon_128x128@2x", 256),
  ("icon_256x256", 256), ("icon_256x256@2x", 512),
  ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, size) in variants {
  let image = drawIcon(size: size)
  guard let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
  else { continue }
  try? png.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
print("iconset at \(out)")
