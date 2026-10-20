#!/usr/bin/env swift
//
// make-icon.swift — render the app icon at every macOS size.
//
// Draws a page of code with one line struck red and the one beneath it added
// green: a diff hunk, which is what the app spends its time showing. Pure
// CoreGraphics, no assets, no dependencies — runs under plain `swift`. The
// Makefile runs `iconutil -c icns build/AppIcon.iconset` on the PNGs this
// writes.

import AppKit

let iconsetDir = "build/AppIcon.iconset"
try? FileManager.default.createDirectory(
    atPath: iconsetDir, withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

/// One line of "code" on the page: its indent and length as fractions of the
/// page width, and how it is marked.
struct CodeLine {
    enum Mark { case none, removed, added }
    let indent: CGFloat
    let length: CGFloat
    let mark: Mark
}

let lines: [CodeLine] = [
    CodeLine(indent: 0.00, length: 0.62, mark: .none),
    CodeLine(indent: 0.12, length: 0.70, mark: .none),
    CodeLine(indent: 0.12, length: 0.55, mark: .removed),
    CodeLine(indent: 0.12, length: 0.74, mark: .added),
    CodeLine(indent: 0.12, length: 0.40, mark: .none),
    CodeLine(indent: 0.00, length: 0.18, mark: .none),
]

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: the rounded square sits inside a ~10% margin.
    let inset = size * 0.1
    let tile = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = tile.width * 0.225
    let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(tilePath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1),
            CGColor(red: 0.09, green: 0.10, blue: 0.14, alpha: 1),
        ] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])

    // At 16pt only the two marked lines survive legibly, so small sizes draw
    // fewer, fatter lines.
    let shown = pixels <= 32 ? lines.filter { $0.mark != .none } : lines
    let pad = tile.width * 0.16
    let content = tile.insetBy(dx: pad, dy: pad)
    let pitch = content.height / CGFloat(shown.count)
    let thickness = pitch * (pixels <= 32 ? 0.62 : 0.46)

    for (row, line) in shown.enumerated() {
        let y = content.maxY - pitch * (CGFloat(row) + 0.5)
        if line.mark != .none {
            let band = CGRect(x: tile.minX, y: y - pitch / 2, width: tile.width, height: pitch)
            let tint =
                line.mark == .removed
                ? CGColor(red: 0.85, green: 0.25, blue: 0.27, alpha: 0.28)
                : CGColor(red: 0.20, green: 0.75, blue: 0.40, alpha: 0.28)
            ctx.setFillColor(tint)
            ctx.fill(band)
        }
        let stroke: CGColor =
            switch line.mark {
            case .none: CGColor(red: 0.62, green: 0.66, blue: 0.75, alpha: 1)
            case .removed: CGColor(red: 0.98, green: 0.45, blue: 0.45, alpha: 1)
            case .added: CGColor(red: 0.45, green: 0.90, blue: 0.58, alpha: 1)
            }
        let x = content.minX + content.width * line.indent
        let bar = CGRect(x: x, y: y - thickness / 2, width: content.width * line.length, height: thickness)
        ctx.setFillColor(stroke)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil))
        ctx.fillPath()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for variant in variants {
    let url = URL(fileURLWithPath: "\(iconsetDir)/\(variant.name)")
    try render(pixels: variant.pixels).write(to: url)
}
print("✓ wrote \(variants.count) icon sizes to \(iconsetDir)")
