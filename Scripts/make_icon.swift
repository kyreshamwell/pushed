import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Generates the Pushed app icon ("Today", from 1.3): a 4x4 GitHub-style
// contribution grid that builds toward the bottom-right square. That square is
// today, so it glows and wears the same thin ring the widgets draw around today.
// The approved design is the "Today" row in Design/1.3-redesign/Icon.dc.html.
//
// Usage: swift Scripts/make_icon.swift <light|dark|tinted> <output.png>
//
// - light:  GitHub light-mode palette on white (default home screens)
// - dark:   GitHub dark-mode palette on #0d1117 (dark home screens)
// - tinted: grayscale on transparent, which iOS recolors with the user's tint

let variant = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dark"
let outPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "icon-\(variant).png"

let size = 1024

// Only the tinted variant is allowed an alpha channel: iOS composites it over
// its own gradient. The App Store icon must be fully opaque, and a light or dark
// PNG that merely *looks* opaque still trips ITMS-90717 if it carries an alpha
// channel at all, so those two are rendered without one rather than painted
// over a background and left translucent-capable.
let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: (variant == "tinted"
        ? CGImageAlphaInfo.premultipliedLast
        : CGImageAlphaInfo.noneSkipLast).rawValue
)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// Per-variant styling
let background: UInt32?   // nil = transparent
let palette: [UInt32]     // level 0-4
let glowColor: UInt32
let glowAlpha: CGFloat
let liftAlpha: CGFloat    // the soft light behind today's corner
let ringColor: UInt32

switch variant {
case "light":
    background = 0xFFFFFF
    palette = [0xEBEDF0, 0x9BE9A8, 0x40C463, 0x30A14E, 0x216E39]
    glowColor = 0x26A641
    glowAlpha = 0.45
    liftAlpha = 0.08
    ringColor = 0x1F2328
case "tinted":
    // Grayscale only: iOS lays this over its own gradient and applies the
    // user's tint. White is the brightest after tinting.
    background = nil
    palette = [0x3D3D3D, 0x6B6B6B, 0x999999, 0xC7C7C7, 0xFFFFFF]
    glowColor = 0xFFFFFF
    glowAlpha = 0.5
    liftAlpha = 0
    ringColor = 0xFFFFFF
default: // dark
    background = 0x0D1117
    palette = [0x161B22, 0x0E4429, 0x006D32, 0x26A641, 0x39D353]
    glowColor = 0x39D353
    glowAlpha = 0.65
    liftAlpha = 0.22
    ringColor = 0xE6EDF3
}

if let background {
    ctx.setFillColor(color(background))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

    // A soft light rising from today's corner (bottom right; CoreGraphics puts
    // the origin at the bottom left).
    if liftAlpha > 0 {
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: [color(glowColor, alpha: liftAlpha), color(glowColor, alpha: 0)] as CFArray,
            locations: [0, 1]
        )!
        let corner = CGPoint(x: CGFloat(size), y: 0)
        ctx.drawRadialGradient(
            gradient,
            startCenter: corner, startRadius: 0,
            endCenter: corner, endRadius: CGFloat(size) * 0.66,
            options: []
        )
    }
}

// 4x4 levels, row 0 = top. Builds toward the bottom right, which is today.
let levels: [[Int]] = [
    [1, 0, 2, 1],
    [0, 2, 1, 3],
    [2, 1, 3, 3],
    [1, 3, 3, 4],
]

let count = levels.count
let padding = CGFloat(size) * 0.14
let gap = CGFloat(size) * 0.045
let cell = (CGFloat(size) - 2 * padding - CGFloat(count - 1) * gap) / CGFloat(count)
let radius = cell * 0.2
let ringWidth = (CGFloat(size) * 0.012).rounded()
let ringOffset = ringWidth

for (row, cols) in levels.enumerated() {
    for (col, level) in cols.enumerated() {
        let x = padding + CGFloat(col) * (cell + gap)
        // CoreGraphics origin is bottom-left; flip rows so row 0 is on top
        let y = padding + CGFloat(count - 1 - row) * (cell + gap)
        let rect = CGRect(x: x, y: y, width: cell, height: cell)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let isToday = row == count - 1 && col == count - 1

        // Glow behind today's square.
        if isToday {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: cell * 0.6, color: color(glowColor, alpha: glowAlpha))
            ctx.addPath(path)
            ctx.setFillColor(color(palette[level]))
            ctx.fillPath()
            ctx.restoreGState()
        }

        ctx.addPath(path)
        ctx.setFillColor(color(palette[level]))
        ctx.fillPath()

        // The ring around today, the same mark the widgets use.
        if isToday {
            let inset = -(ringOffset + ringWidth / 2)
            let ringRect = rect.insetBy(dx: inset, dy: inset)
            let ringRadius = radius - inset
            let ring = CGPath(roundedRect: ringRect, cornerWidth: ringRadius, cornerHeight: ringRadius, transform: nil)
            ctx.addPath(ring)
            ctx.setStrokeColor(color(ringColor))
            ctx.setLineWidth(ringWidth)
            ctx.strokePath()
        }
    }
}

let image = ctx.makeImage()!
let outURL = URL(fileURLWithPath: outPath)
let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outURL.path)")
