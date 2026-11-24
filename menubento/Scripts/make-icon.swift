// Draws the MenuBento app icon and writes Resources/AppIcon.icns.
//   swift Scripts/make-icon.swift [output-dir] [--png path/to/preview-1024.png]
//
// The design: a menu bar strip across the top of a dark tile, split into
// sections by glowing dividers, with a "bento" bar dropping down from it
// that holds the hidden items in little cells. Same family as DuoNotch's
// icon (dark gradient squircle, purple glow), but a bar and a drop-down
// instead of a notch and rings.
import AppKit

var args = Array(CommandLine.arguments.dropFirst())
var previewPath: String?
if let i = args.firstIndex(of: "--png"), i + 1 < args.count {
    previewPath = args[i + 1]
    args.removeSubrange(i...(i + 1))
}
let out = URL(fileURLWithPath: args.first ?? "Resources")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("MenuBentoIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(red: r, green: g, blue: b, alpha: a).cgColor
}

let purple = rgb(0.78, 0.45, 1.0)
let pink = rgb(1.0, 0.42, 0.72)
let cyan = rgb(0.30, 0.82, 1.0)
let mint = rgb(0.35, 0.92, 0.62)
let amber = rgb(1.0, 0.78, 0.30)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let space = CGColorSpaceCreateDeviceRGB()

    // Squircle tile on the Big Sur grid: 824/1024 body, centred, with a
    // transparent margin for the shadow.
    let inset = s * 100 / 1024
    let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgb(0, 0, 0, 0.45))
    ctx.addPath(tilePath); ctx.setFillColor(rgb(0, 0, 0)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    // Deep indigo → near-black, a cooler blue than DuoNotch's plum.
    let bg = CGGradient(colorsSpace: space, colors: [rgb(0.12, 0.11, 0.26), rgb(0.04, 0.04, 0.08)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    // A soft purple bloom behind the drop-down.
    let bloomCentre = CGPoint(x: tile.midX + tile.width * 0.08, y: tile.midY - tile.height * 0.05)
    let bloom = CGGradient(colorsSpace: space, colors: [rgb(0.55, 0.30, 0.95, 0.35), rgb(0.55, 0.30, 0.95, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(bloom, startCenter: bloomCentre, startRadius: 0, endCenter: bloomCentre, endRadius: tile.width * 0.55, options: [])

    // The menu bar strip.
    let barH = tile.height * 0.15
    let bar = CGRect(x: tile.minX + tile.width * 0.09, y: tile.maxY - tile.height * 0.15 - barH,
                     width: tile.width * 0.82, height: barH)
    let barPath = CGPath(roundedRect: bar, cornerWidth: barH * 0.5, cornerHeight: barH * 0.5, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.045, color: rgb(0.78, 0.45, 1.0, 0.85))
    ctx.addPath(barPath); ctx.setFillColor(rgb(0.02, 0.02, 0.05)); ctx.fillPath()
    ctx.restoreGState()
    // Travelling-glow rim: a gradient stroke from pink through purple to cyan.
    ctx.saveGState()
    ctx.addPath(barPath); ctx.setLineWidth(s * 0.009); ctx.replacePathWithStrokedPath(); ctx.clip()
    let rim = CGGradient(colorsSpace: space, colors: [pink, purple, cyan] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(rim, start: CGPoint(x: bar.minX, y: bar.midY), end: CGPoint(x: bar.maxX, y: bar.midY),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Items in the bar: dots, separated into sections by glowing dividers.
    let dotR = barH * 0.16
    func dot(_ x: CGFloat, _ color: CGColor) {
        ctx.addEllipse(in: CGRect(x: x - dotR, y: bar.midY - dotR, width: dotR * 2, height: dotR * 2))
        ctx.setFillColor(color); ctx.fillPath()
    }
    func divider(_ x: CGFloat, _ color: CGColor) {
        let w = s * 0.011, h = barH * 0.56
        let r = CGRect(x: x - w / 2, y: bar.midY - h / 2, width: w, height: h)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: s * 0.02, color: color)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: w / 2, cornerHeight: w / 2, transform: nil))
        ctx.setFillColor(color); ctx.fillPath()
        ctx.restoreGState()
    }
    let step = bar.width / 11
    let white = rgb(1, 1, 1, 0.82)
    dot(bar.minX + step * 1.15, white)
    dot(bar.minX + step * 2.05, white)
    divider(bar.minX + step * 3.0, pink)
    dot(bar.minX + step * 3.95, white)
    // The MenuBento item, picked out, with its drop-down hanging under it.
    let anchorX = bar.midX
    let hiW = step * 1.25, hiH = barH * 0.62
    let hi = CGRect(x: anchorX - hiW / 2, y: bar.midY - hiH / 2, width: hiW, height: hiH)
    ctx.addPath(CGPath(roundedRect: hi, cornerWidth: hiH * 0.3, cornerHeight: hiH * 0.3, transform: nil))
    ctx.setFillColor(rgb(0.78, 0.45, 1.0, 0.35)); ctx.fillPath()
    let g = hiH * 0.16, cell = (hiH * 0.62 - g) / 2
    for (cx, cy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
        let r = CGRect(x: anchorX - cell - g / 2 + CGFloat(cx) * (cell + g),
                       y: bar.midY - cell - g / 2 + CGFloat(cy) * (cell + g), width: cell, height: cell)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: cell * 0.25, cornerHeight: cell * 0.25, transform: nil))
        ctx.setFillColor(rgb(1, 1, 1, 0.95)); ctx.fillPath()
    }
    divider(bar.minX + step * 7.0, cyan)
    dot(bar.minX + step * 7.95, white)
    dot(bar.minX + step * 8.85, white)
    dot(bar.minX + step * 9.75, white)

    // The drop-down bento bar.
    let panelW = tile.width * 0.62, panelH = tile.height * 0.44
    let panel = CGRect(x: anchorX - panelW / 2, y: bar.minY - tile.height * 0.07 - panelH,
                       width: panelW, height: panelH)
    let panelPath = CGPath(roundedRect: panel, cornerWidth: tile.width * 0.075, cornerHeight: tile.width * 0.075, transform: nil)
    // Little pointer joining it to the item.
    let tip = CGMutablePath()
    let tw = tile.width * 0.07
    tip.move(to: CGPoint(x: anchorX - tw / 2, y: panel.maxY - 1))
    tip.addLine(to: CGPoint(x: anchorX, y: panel.maxY + tw * 0.55))
    tip.addLine(to: CGPoint(x: anchorX + tw / 2, y: panel.maxY - 1))
    tip.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.05, color: rgb(0.78, 0.45, 1.0, 0.7))
    ctx.addPath(panelPath); ctx.addPath(tip); ctx.setFillColor(rgb(0.06, 0.05, 0.12)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(panelPath); ctx.setLineWidth(s * 0.007); ctx.setStrokeColor(rgb(0.78, 0.45, 1.0, 0.85)); ctx.strokePath()

    // Bento cells: hidden items, each with a coloured glyph.
    let pad = panel.width * 0.09, gap = panel.width * 0.06
    let cols = 3, rows = 2
    let cw = (panel.width - pad * 2 - gap * CGFloat(cols - 1)) / CGFloat(cols)
    let ch = (panel.height - pad * 2 - gap * CGFloat(rows - 1)) / CGFloat(rows)
    let colors = [mint, amber, pink, cyan, purple, amber]
    for row in 0..<rows {
        for col in 0..<cols {
            let i = row * cols + col
            let r = CGRect(x: panel.minX + pad + CGFloat(col) * (cw + gap),
                           y: panel.maxY - pad - ch - CGFloat(row) * (ch + gap), width: cw, height: ch)
            let p = CGPath(roundedRect: r, cornerWidth: cw * 0.22, cornerHeight: cw * 0.22, transform: nil)
            ctx.addPath(p); ctx.setFillColor(rgb(1, 1, 1, 0.07)); ctx.fillPath()
            ctx.addPath(p); ctx.setLineWidth(s * 0.005)
            ctx.setStrokeColor(colors[i].copy(alpha: 0.75)!); ctx.strokePath()
            let gr = min(cw, ch) * 0.2
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: s * 0.012, color: colors[i])
            ctx.addEllipse(in: CGRect(x: r.midX - gr, y: r.midY - gr, width: gr * 2, height: gr * 2))
            ctx.setFillColor(colors[i]); ctx.fillPath()
            ctx.restoreGState()
        }
    }
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

if let previewPath {
    try! draw(1024).write(to: URL(fileURLWithPath: previewPath))
    print("Wrote \(previewPath)")
}
for base in [16, 32, 128, 256, 512] {
    try! draw(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! draw(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.appendingPathComponent("AppIcon.icns").path]
try! task.run(); task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "Wrote \(out.path)/AppIcon.icns" : "iconutil failed")
exit(task.terminationStatus)
