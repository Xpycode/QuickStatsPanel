// GenerateAppIcon.swift
// Renders the QuickStatsPanel app icon — "Abstract (bars)" direction from the
// design handoff (02_Design/design_handoff_quickstatspanel/sec-icon.jsx) — natively
// with Core Graphics, at every macOS AppIcon pixel size, and writes a complete
// AppIcon.appiconset (PNGs + Contents.json).
//
//   swift GenerateAppIcon.swift <output-appiconset-dir>
//
// Spec (from sec-icon.jsx, normalized to a 172pt reference square):
//   shell radius   = 0.2237 * size  (macOS continuous-corner ratio)
//   shell bg       = linear-gradient(158°, #2b3340 → #1a1e27 @52% → #0e1014)
//   top sheen      = top 46%, white 0.12 → 0
//   bevel          = inset top white 0.18, inset bottom black 0.40
//   hairline ring  = inset 1px white 0.08
//   bars[5]        = heights [0.42,0.66,0.50,0.86,0.62] of a 70u-tall area
//                    bar w=13u, gap=8u, radius=5u (u = size/172)
//                    fill = linear cyan-green → mix(60% accent, bg); tallest glows
//   baseline       = w=92u, h=6u, radius=3u, white 0.90, 11u below bars

import AppKit
import CoreGraphics

// MARK: - Palette (oklch pre-converted to sRGB; see header)
let accent    = NSColor(srgbRed: 65/255,  green: 210/255, blue: 179/255, alpha: 1) // oklch(0.78 0.13 175)
let bgTop     = NSColor(srgbRed: 43/255,  green: 51/255,  blue: 64/255,  alpha: 1) // #2b3340
let bgMid     = NSColor(srgbRed: 26/255,  green: 30/255,  blue: 39/255,  alpha: 1) // #1a1e27
let bgBot     = NSColor(srgbRed: 14/255,  green: 16/255,  blue: 20/255,  alpha: 1) // #0e1014
// bar bottom = mix(60% accent, 40% bgMid) approximated in sRGB
let barBottom = NSColor(srgbRed: 49/255,  green: 138/255, blue: 123/255, alpha: 1)

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawIcon(size P: CGFloat, into ctx: CGContext) {
    let u = P / 172.0
    let rect = CGRect(x: 0, y: 0, width: P, height: P)
    let r = 0.2237 * P
    let shell = roundedPath(rect, r)

    // --- Shell background gradient (158° ≈ near-vertical, tilted) ---
    ctx.saveGState()
    ctx.addPath(shell); ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let bgGrad = CGGradient(colorsSpace: space,
        colors: [bgTop.cgColor, bgMid.cgColor, bgBot.cgColor] as CFArray,
        locations: [0.0, 0.52, 1.0])!
    // Note: CG y-axis is bottom-up, so "top" of the icon is y = P.
    ctx.drawLinearGradient(bgGrad,
        start: CGPoint(x: P * 0.46, y: P),
        end:   CGPoint(x: P * 0.54, y: 0),
        options: [])

    // --- Top sheen (top 46%, white 0.12 → 0) ---
    let sheen = CGGradient(colorsSpace: space,
        colors: [NSColor(white: 1, alpha: 0.12).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray,
        locations: [0.0, 1.0])!
    ctx.drawLinearGradient(sheen,
        start: CGPoint(x: 0, y: P),
        end:   CGPoint(x: 0, y: P * 0.54),
        options: [])
    ctx.restoreGState()

    // --- Bars + baseline group, vertically centered ---
    let barHeights: [CGFloat] = [0.42, 0.66, 0.50, 0.86, 0.62]
    let tallest = 3
    let barAreaH = 70 * u
    let barW = 13 * u
    let gap = 8 * u
    let barRadius = 5 * u
    let groupGap = 11 * u
    let baseW = 92 * u
    let baseH = 6 * u
    let baseRadius = 3 * u

    let barsTotalW = CGFloat(barHeights.count) * barW + CGFloat(barHeights.count - 1) * gap
    let groupH = barAreaH + groupGap + baseH
    // Center the whole group; nudge up a hair so it reads optically centered.
    let groupBottom = (P - groupH) / 2 + baseH + groupGap

    // bars (drawn bottom-aligned at groupBottom, growing upward)
    let barsStartX = (P - barsTotalW) / 2
    for (i, h) in barHeights.enumerated() {
        let bh = h * barAreaH
        let x = barsStartX + CGFloat(i) * (barW + gap)
        let barRect = CGRect(x: x, y: groupBottom, width: barW, height: bh)
        let path = roundedPath(barRect, barRadius)

        if i == tallest {
            // glow for the one accent bar
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 10 * u, color: accent.withAlphaComponent(0.85).cgColor)
            ctx.addPath(path); ctx.setFillColor(accent.cgColor); ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let topCol = (i == tallest) ? accent : accent.withAlphaComponent(0.92)
        let barGrad = CGGradient(colorsSpace: space,
            colors: [topCol.cgColor, barBottom.cgColor] as CFArray,
            locations: [0.0, 1.0])!
        ctx.drawLinearGradient(barGrad,
            start: CGPoint(x: 0, y: groupBottom + bh),
            end:   CGPoint(x: 0, y: groupBottom),
            options: [])
        ctx.restoreGState()
    }

    // baseline (white bar under the bars)
    let baseRect = CGRect(x: (P - baseW) / 2, y: groupBottom - groupGap - baseH, width: baseW, height: baseH)
    ctx.addPath(roundedPath(baseRect, baseRadius))
    ctx.setFillColor(NSColor(white: 1, alpha: 0.90).cgColor)
    ctx.fillPath()

    // --- Bevel: inset top highlight + bottom shadow (clipped to shell) ---
    ctx.saveGState()
    ctx.addPath(shell); ctx.clip()
    let lw = max(1, u) // ~1px at large sizes
    ctx.setLineWidth(lw)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.18).cgColor)
    ctx.move(to: CGPoint(x: r, y: P - lw/2)); ctx.addLine(to: CGPoint(x: P - r, y: P - lw/2)); ctx.strokePath()
    ctx.setStrokeColor(NSColor(white: 0, alpha: 0.40).cgColor)
    ctx.move(to: CGPoint(x: r, y: lw/2)); ctx.addLine(to: CGPoint(x: P - r, y: lw/2)); ctx.strokePath()
    ctx.restoreGState()

    // --- Hairline ring (inset 1px white 0.08) ---
    ctx.saveGState()
    let inset = lw / 2
    ctx.addPath(roundedPath(rect.insetBy(dx: inset, dy: inset), r - inset))
    ctx.setLineWidth(lw)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.08).cgColor)
    ctx.strokePath()
    ctx.restoreGState()
}

func renderPNG(pixelSize: Int) -> Data {
    let s = CGFloat(pixelSize)
    let space = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: pixelSize, height: pixelSize,
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    drawIcon(size: s, into: ctx)
    let cg = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: cg)
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Asset catalog entries (macOS)
struct Entry { let size: Int; let scale: Int; let px: Int }
let entries: [Entry] = [
    Entry(size: 16,  scale: 1, px: 16),
    Entry(size: 16,  scale: 2, px: 32),
    Entry(size: 32,  scale: 1, px: 32),
    Entry(size: 32,  scale: 2, px: 64),
    Entry(size: 128, scale: 1, px: 128),
    Entry(size: 128, scale: 2, px: 256),
    Entry(size: 256, scale: 1, px: 256),
    Entry(size: 256, scale: 2, px: 512),
    Entry(size: 512, scale: 1, px: 512),
    Entry(size: 512, scale: 2, px: 1024),
]

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.appiconset"
let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

var images: [[String: String]] = []
// Render each distinct pixel size once, reuse the file across matching idioms.
var written: [Int: String] = [:]
for e in entries {
    let filename = "icon_\(e.size)x\(e.size)@\(e.scale)x.png"
    if written[e.px] == nil {
        let data = renderPNG(pixelSize: e.px)
        try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(filename)"))
        written[e.px] = filename
    } else {
        // still emit a unique file per entry for clarity
        let data = renderPNG(pixelSize: e.px)
        try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(filename)"))
    }
    images.append([
        "idiom": "mac",
        "size": "\(e.size)x\(e.size)",
        "scale": "\(e.scale)x",
        "filename": filename,
    ])
}

let contents: [String: Any] = [
    "images": images,
    "info": ["version": 1, "author": "xcode"],
]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: URL(fileURLWithPath: "\(outDir)/Contents.json"))
print("Wrote \(images.count) images + Contents.json to \(outDir)")
