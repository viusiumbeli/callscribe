// Generates CallScribe's app icon natively — no Xcode, no brew.
// Draws an indigo→violet squircle with a white "audio waveform → text lines"
// glyph, renders every macOS iconset size, and packs them via `iconutil`.
//
//   swift scripts/make-icon.swift      (or: make icon)

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Drawing

/// Render the icon into `ctx`, a square of side `s` (origin bottom-left).
func draw(in ctx: CGContext, s: CGFloat) {
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // Squircle background, inset for the Dock's padding grid.
    let inset = s * 0.09
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.2237
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    // Top→bottom indigo → violet.
    let space = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(colorSpace: space, components: [0.31, 0.27, 0.90, 1])!,  // #4F46E5 indigo
        CGColor(colorSpace: space, components: [0.49, 0.23, 0.93, 1])!,  // #7C3AED violet
    ] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY),
                           options: [])
    // Subtle top sheen for depth — a soft gradient (no hard seam).
    let sheen = CGGradient(colorsSpace: space, colors: [
        CGColor(colorSpace: space, components: [1, 1, 1, 0.12])!,
        CGColor(colorSpace: space, components: [1, 1, 1, 0])!,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen,
                           start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.midY),
                           options: [])
    ctx.restoreGState()

    // Glyph area (padded inside the squircle).
    let pad = rect.width * 0.20
    let g = rect.insetBy(dx: pad, dy: pad)
    let white = CGColor(colorSpace: space, components: [1, 1, 1, 1])!

    // Waveform: 5 vertical rounded bars on the left ~42%, equalizer heights.
    let waveW = g.width * 0.42
    let barCount = 5
    let barW = waveW / CGFloat(barCount * 2 - 1)   // bars + equal gaps
    let heightFrac: [CGFloat] = [0.42, 0.72, 1.0, 0.64, 0.34]
    for i in 0..<barCount {
        let h = g.height * heightFrac[i]
        let x = g.minX + CGFloat(i) * barW * 2
        let y = g.midY - h / 2
        let bar = CGPath(roundedRect: CGRect(x: x, y: y, width: barW, height: h),
                         cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil)
        ctx.addPath(bar)
        ctx.setFillColor(white)
        ctx.fillPath()
    }

    // Text lines: 3 horizontal rounded bars on the right ~45%, decreasing width.
    let textX = g.minX + g.width * 0.55
    let textW = g.maxX - textX
    let lineH = g.height * 0.13
    let widths: [CGFloat] = [1.0, 0.80, 0.55]
    let alphas: [CGFloat] = [1.0, 1.0, 0.70]
    let gap = (g.height - lineH * 3) / 2
    for i in 0..<3 {
        let w = textW * widths[i]
        let y = g.maxY - lineH - CGFloat(i) * (lineH + gap)
        let line = CGPath(roundedRect: CGRect(x: textX, y: y, width: w, height: lineH),
                          cornerWidth: lineH / 2, cornerHeight: lineH / 2, transform: nil)
        ctx.addPath(line)
        ctx.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, alphas[i]])!)
        ctx.fillPath()
    }
}

// MARK: - Render + write

func renderPNG(px: Int, to url: URL) {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("cannot make context at \(px)px") }
    draw(in: ctx, s: CGFloat(px))
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("cannot encode \(px)px") }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// (filename, pixel size) for the standard macOS iconset.
let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in variants {
    renderPNG(px: px, to: iconset.appendingPathComponent("\(name).png"))
}

let icns = root.appendingPathComponent("Support/AppIcon.icns")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try proc.run()
proc.waitUntilExit()
guard proc.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(icns.path)")
