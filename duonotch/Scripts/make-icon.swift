// Draws the DuoNotch app icon and writes Resources/AppIcon.icns.
//   swift Scripts/make-icon.swift
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Squircle tile (Big Sur grid: 824/1024 body, centred).
    let inset = s * 100 / 1024
    let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(tilePath); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [NSColor(red: 0.16, green: 0.12, blue: 0.24, alpha: 1).cgColor,
                                 NSColor(red: 0.05, green: 0.05, blue: 0.09, alpha: 1).cgColor] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])

    // The notch: a black pill near the top edge with a glow rim.
    let nw = tile.width * 0.78, nh = tile.height * 0.36
    let notch = CGRect(x: tile.midX - nw / 2, y: tile.maxY - nh - tile.height * 0.12, width: nw, height: nh)
    let notchPath = CGPath(roundedRect: notch, cornerWidth: nh * 0.5, cornerHeight: nh * 0.5, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.05, color: NSColor(red: 0.85, green: 0.45, blue: 1, alpha: 0.9).cgColor)
    ctx.addPath(notchPath); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(notchPath); ctx.setLineWidth(s * 0.008)
    ctx.setStrokeColor(NSColor(red: 0.8, green: 0.55, blue: 1, alpha: 0.85).cgColor); ctx.strokePath()

    // Two usage rings inside the notch (one per login).
    func ring(center: CGPoint, r: CGFloat, color: NSColor, fraction: CGFloat) {
        let w = r * 0.32
        ctx.setLineWidth(w); ctx.setLineCap(.round)
        ctx.setStrokeColor(color.withAlphaComponent(0.22).cgColor)
        ctx.addArc(center: center, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false); ctx.strokePath()
        ctx.setStrokeColor(color.cgColor)
        ctx.addArc(center: center, radius: r, startAngle: .pi / 2, endAngle: .pi / 2 - .pi * 2 * fraction, clockwise: true)
        ctx.strokePath()
    }
    let r = nh * 0.27
    ring(center: CGPoint(x: notch.midX - nw * 0.2, y: notch.midY), r: r, color: NSColor(red: 1, green: 0.55, blue: 0.25, alpha: 1), fraction: 0.68)
    ring(center: CGPoint(x: notch.midX + nw * 0.2, y: notch.midY), r: r, color: NSColor(red: 0.3, green: 0.7, blue: 1, alpha: 1), fraction: 0.35)

    // Bento tiles below.
    let gap = tile.width * 0.04
    let rowY = tile.minY + tile.height * 0.12
    let rowH = notch.minY - rowY - tile.height * 0.08
    let colW = (nw - gap) / 2
    let tiles: [(CGRect, NSColor)] = [
        (CGRect(x: notch.minX, y: rowY, width: colW, height: rowH), NSColor(red: 0.35, green: 0.85, blue: 0.55, alpha: 1)),
        (CGRect(x: notch.minX + colW + gap, y: rowY + rowH / 2 + gap / 2, width: colW, height: rowH / 2 - gap / 2), NSColor(red: 1, green: 0.8, blue: 0.3, alpha: 1)),
        (CGRect(x: notch.minX + colW + gap, y: rowY, width: colW, height: rowH / 2 - gap / 2), NSColor(red: 0.95, green: 0.4, blue: 0.6, alpha: 1)),
    ]
    for (rect, color) in tiles {
        let p = CGPath(roundedRect: rect, cornerWidth: s * 0.04, cornerHeight: s * 0.04, transform: nil)
        ctx.addPath(p); ctx.setFillColor(NSColor.white.withAlphaComponent(0.08).cgColor); ctx.fillPath()
        ctx.addPath(p); ctx.setLineWidth(s * 0.006); ctx.setStrokeColor(color.withAlphaComponent(0.8).cgColor); ctx.strokePath()
    }
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.appendingPathComponent("AppIcon.icns").path]
try! task.run(); task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote \(out.path)/AppIcon.icns" : "iconutil failed")
