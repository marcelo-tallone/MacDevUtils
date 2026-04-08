#!/usr/bin/env swift
import AppKit
import Foundation

let iconsetDir = "MacDevUtils.iconset"
try! FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true, attributes: nil)

func drawIcon(size: Int) -> NSImage {
    let s  = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()

    let pad = s * 0.06
    let r   = NSRect(x: pad, y: pad, width: s - 2 * pad, height: s - 2 * pad)
    let rad = s * 0.20

    // ── Background gradient (dark navy) ──
    let bg1 = NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.22, alpha: 1)
    let bg2 = NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.34, alpha: 1)
    let path = NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad)

    // Shadow
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -(s * 0.02))
    shadow.shadowBlurRadius = s * 0.06
    shadow.set()
    bg1.setFill(); path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Gradient fill
    if let gradient = NSGradient(starting: bg2, ending: bg1) {
        gradient.draw(in: path, angle: -90)
    }

    // ── Subtle border ──
    NSColor.white.withAlphaComponent(0.08).setStroke()
    path.lineWidth = max(0.5, s * 0.012)
    path.stroke()

    // ── Code symbol "</>" ──
    if size >= 32 {
        let cyan = NSColor(calibratedRed: 0.30, green: 0.78, blue: 0.95, alpha: 1)
        let fontSize = s * 0.34
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: cyan]
        let text = "</>" as NSString
        let sz = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (s - sz.width) / 2, y: (s - sz.height) / 2 - s * 0.01), withAttributes: attrs)
    }

    // ── Tiny wrench accent ──
    if size >= 64 {
        let accent = NSColor(calibratedRed: 1.0, green: 0.65, blue: 0.20, alpha: 0.9)
        let wSize  = s * 0.11
        let wRect  = NSRect(x: r.maxX - wSize - s * 0.06, y: r.minY + s * 0.06, width: wSize, height: wSize)
        let wPath  = NSBezierPath(ovalIn: wRect)
        accent.setFill(); wPath.fill()
    }

    img.unlockFocus()
    return img
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff   = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png    = bitmap.representation(using: .png, properties: [:]) else { return }
    try! png.write(to: URL(fileURLWithPath: path))
}

let entries: [(file: String, px: Int)] = [
    ("icon_16x16.png",       16),  ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),  ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",    128),  ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),  ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),  ("icon_512x512@2x.png",1024),
]

var cache: [Int: NSImage] = [:]
for e in entries {
    if cache[e.px] == nil { cache[e.px] = drawIcon(size: e.px) }
    savePNG(cache[e.px]!, to: "\(iconsetDir)/\(e.file)")
    print("  \(e.file)")
}
print("Iconset listo.")
