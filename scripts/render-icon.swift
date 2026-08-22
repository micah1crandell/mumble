#!/usr/bin/env swift
import AppKit
import Foundation

// Renders Mumble's monochrome icon. Run: swift scripts/render-icon.swift

// The mark is intentionally simple: a dark tile and a clear voice trace.
let tile = NSColor(white: 0.04, alpha: 1)
let waveform = NSColor(white: 0.98, alpha: 1)

/// Relative bar heights, center-weighted so the mark reads as a voice waveform rather
/// than a bar chart.
let bars: [CGFloat] = [0.50, 0.18, 0.76, 0.22, 0.88, 0.30, 0.68, 0.26, 0.50]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Leave the outer gutter expected by the macOS icon grid.
    let inset = size * 0.09
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    // Match the familiar macOS squircle proportion.
    let radius = rect.width * 0.2237

    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.012),
        blur: size * 0.035,
        color: NSColor.black.withAlphaComponent(0.30).cgColor
    )
    ctx.addPath(squircle)
    ctx.setFillColor(tile.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Keep the mark flat and legible at every size.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    ctx.restoreGState()

    // A single rounded waveform stroke keeps the mark legible at small sizes.
    let totalWidth = rect.width * 0.62
    let startX = rect.midX - totalWidth / 2
    let step = totalWidth / CGFloat(bars.count - 1)
    let maxHeight = rect.height * 0.34
    let path = CGMutablePath()
    for (index, bar) in bars.enumerated() {
        let x = startX + CGFloat(index) * step
        let y = rect.midY + maxHeight * (bar - 0.5)
        if index == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.004),
        blur: size * 0.014,
        color: NSColor.black.withAlphaComponent(0.22).cgColor
    )
    ctx.setStrokeColor(waveform.cgColor)
    ctx.setLineWidth(size * 0.055)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(path)
    ctx.strokePath()
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

func png(_ image: NSImage, pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Redraw at native pixel size rather than scaling a single render — keeps the small
    // sizes crisp instead of muddy.
    drawIcon(size: CGFloat(pixels)).draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero, operation: .sourceOver, fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("assets/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// Point-size and scale pairs consumed by iconutil.
let variants: [(Int, Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
    (256, 1), (256, 2), (512, 1), (512, 2),
]

for (points, scale) in variants {
    let pixels = points * scale
    guard let data = png(NSImage(), pixels: pixels) else {
        print("failed at \(pixels)px"); exit(1)
    }
    let suffix = scale == 2 ? "@2x" : ""
    let name = "icon_\(points)x\(points)\(suffix).png"
    try data.write(to: iconset.appendingPathComponent(name))
}

print("wrote \(variants.count) PNGs to assets/AppIcon.iconset")
