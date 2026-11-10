// Draws the 1024px app icon in the app's text-mode theme: a near-black tile, an ASCII
// landscape in tarnished cream inside viewfinder corners, and the brass pick tag.
// Usage: swift make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments[1]
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

// Tile
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.4).cgColor)
ctx.addPath(tilePath); ctx.setFillColor(color(0x0d0d0c).cgColor); ctx.fillPath()
ctx.restoreGState()
ctx.addPath(tilePath); ctx.setStrokeColor(color(0x2a2824).cgColor); ctx.setLineWidth(3); ctx.strokePath()

// Hand-drawn ASCII landscape: mountains and a sun
let art = [
    "            .--.  ",
    "    /\\     (    ) ",
    "   /  \\     '--'  ",
    "  /    \\  /\\      ",
    " /      \\/  \\     ",
    "/   /\\   \\   \\    ",
    "__________________",
]
let font = NSFont.monospacedSystemFont(ofSize: 44, weight: .bold)
let adv: CGFloat = 44 * 0.618, line: CGFloat = 56
let cols = art.map(\.count).max()!, rows = art.count
let artW = CGFloat(cols) * adv, artH = CGFloat(rows) * line
let origin = CGPoint(x: (size - artW) / 2, y: (size - artH) / 2 - 24)
for (r, s) in art.enumerated() {
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color(0xd2cbbb)])
        .draw(at: CGPoint(x: origin.x, y: origin.y + artH - CGFloat(r + 1) * line))
}

// Viewfinder corners
let frame = CGRect(x: origin.x - 60, y: origin.y - 50, width: artW + 120, height: artH + 90)
ctx.setStrokeColor(color(0x7c766a).cgColor); ctx.setLineWidth(10); ctx.setLineCap(.square)
let arm: CGFloat = 54
for (p, dx, dy) in [(CGPoint(x: frame.minX, y: frame.maxY), 1.0, -1.0), (CGPoint(x: frame.maxX, y: frame.maxY), -1.0, -1.0),
                    (CGPoint(x: frame.minX, y: frame.minY), 1.0, 1.0), (CGPoint(x: frame.maxX, y: frame.minY), -1.0, 1.0)] {
    ctx.move(to: CGPoint(x: p.x + arm * dx, y: p.y)); ctx.addLine(to: p); ctx.addLine(to: CGPoint(x: p.x, y: p.y + arm * dy))
}
ctx.strokePath()

// Brass pick tag, like the app's " ■ PICKED " tag
let mark = CGRect(x: frame.maxX - 150, y: frame.maxY + 26, width: 150, height: 84)
ctx.setFillColor(color(0xc2a15e).cgColor); ctx.fill(mark)
let sq: CGFloat = 34
ctx.setFillColor(color(0x0d0d0c).cgColor)
ctx.fill(CGRect(x: mark.midX - sq / 2, y: mark.midY - sq / 2, width: sq, height: sq))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
