#!/usr/bin/env swift
//
// DockStat app icon — the mono percent glyph in the app's own colours.
//
// Run via Scripts/make-icons.sh (needs an .iconset directory + iconutil) or
// directly: `swift Scripts/make-icon.swift <out.iconset>`.
//
// The art is pure geometry in a 1024pt design space, identical to the macOS
// icon grid the Dock uses (824pt squircle inside 1024pt), so every size is
// drawn from vectors instead of downsampled from one big bitmap.
//
import AppKit
import CoreGraphics
import CoreText

// MARK: - Design space

let design: CGFloat = 1024
let content = CGRect(x: 100, y: 100, width: 824, height: 824)  // 824/1024, Apple's grid
let corner: CGFloat = 184

enum Palette {
    static let top = "#1E5C34"
    static let bottom = "#0A2413"
    static let glow = "#04E518"
    static let glyphTop = "#D2FF8A"
    static let glyphBottom = "#04E518"
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func col(_ hex: String, _ alpha: CGFloat = 1) -> CGColor {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    let v = UInt32(s, radix: 16)!
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255,
                   alpha: alpha)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
}

func fill(_ cg: CGContext, _ path: CGPath, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    cg.drawLinearGradient(gradient(colors), start: from, end: to,
                          options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    cg.restoreGState()
}

/// Percent sign as a filled, gradient-shaded path.
func percentPath() -> CGPath? {
    let font = NSFont.monospacedSystemFont(ofSize: 600, weight: .bold) as CTFont
    var glyph = CGGlyph(0)
    var chars = Array("%".utf16)
    guard CTFontGetGlyphsForCharacters(font, &chars, &glyph, 1),
          let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return nil }
    let box = path.boundingBoxOfPath
    return path.copy(using: [CGAffineTransform(
        translationX: design / 2 - box.midX,
        y: design / 2 - box.midY
    )])
}

// MARK: - Drawing

func drawIcon(in cg: CGContext, size: CGFloat) {
    cg.setShouldAntialias(true)
    cg.setAllowsAntialiasing(true)
    cg.interpolationQuality = .high
    cg.scaleBy(x: size / design, y: size / design)  // draw in design space

    let squircle = CGPath(roundedRect: content, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Baked drop shadow, as in Apple's icon template.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -18), blur: 44, color: col("#000000", 0.38))
    cg.addPath(squircle)
    cg.setFillColor(col("#000000"))
    cg.fillPath()
    cg.restoreGState()

    // Green bloom behind the glyph.
    cg.saveGState()
    cg.addPath(squircle)
    cg.clip()
    cg.drawRadialGradient(gradient([col(Palette.glow, 0.40), col(Palette.glow, 0)]),
                          startCenter: CGPoint(x: 512, y: 780), startRadius: 0,
                          endCenter: CGPoint(x: 512, y: 780), endRadius: 640, options: [])
    cg.restoreGState()

    // Body: vertical gradient + top highlight.
    fill(cg, squircle, [col(Palette.top), col(Palette.bottom)],
         from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
    cg.saveGState()
    cg.addPath(squircle)
    cg.clip()
    cg.drawLinearGradient(gradient([col("#FFFFFF", 0.10), col("#FFFFFF", 0)]),
                          start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 500), options: [])
    cg.restoreGState()

    guard let glyph = percentPath() else { return }

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 34, color: col(Palette.glow, 0.32))
    cg.addPath(glyph)
    cg.setFillColor(col(Palette.glow))
    cg.fillPath()
    cg.restoreGState()
    fill(cg, glyph, [col(Palette.glyphTop), col(Palette.glyphBottom)],
         from: CGPoint(x: 330, y: 820), to: CGPoint(x: 700, y: 220))
}

func png(_ cg: CGContext) -> Data {
    NSBitmapImageRep(cgImage: cg.makeImage()!).representation(using: .png, properties: [:])!
}

func render(pixels: Int) -> Data {
    let cg = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                       bytesPerRow: 0, space: space,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawIcon(in: cg, size: CGFloat(pixels))
    return png(cg)
}

// MARK: - Entry point

/// The ten slots `iconutil` expects: every size plus its Retina twin.
let at2 = "@" + "2x"
let slots: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16\(at2).png", 32),
    ("icon_32x32.png", 32), ("icon_32x32\(at2).png", 64),
    ("icon_128x128.png", 128), ("icon_128x128\(at2).png", 256),
    ("icon_256x256.png", 256), ("icon_256x256\(at2).png", 512),
    ("icon_512x512.png", 512), ("icon_512x512\(at2).png", 1024)
]

// `make-icon.swift <out.png> [size]` writes one PNG (README logo); a directory
// argument gets the full iconset instead.
if let out = CommandLine.arguments.dropFirst().first, out.hasSuffix(".png") {
    let size = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 1024 : 1024
    let directory = (out as NSString).deletingLastPathComponent
    if !directory.isEmpty {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }
    try! render(pixels: size).write(to: URL(fileURLWithPath: out))
    print("logo: \(out) (\(size)px)")
    exit(0)
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".build/DockStat.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for (name, pixels) in slots {
    let path = "\(outDir)/\(name)"
    try! render(pixels: pixels).write(to: URL(fileURLWithPath: path))
    print("  \(name) (\(pixels)px)")
}
print("iconset at \(outDir)")
