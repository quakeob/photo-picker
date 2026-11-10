// Draws the 1024px app icon: a graphite tile, a loose stack of prints, the top one
// pulled forward with the green pick mark. Usage: swift make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments[1]
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a) }

// Tile (Big Sur grid: 824px squircle-ish rounded rect with a soft drop shadow)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0, 0, 0, 0.35))
ctx.addPath(tilePath); ctx.setFillColor(rgb(36, 38, 42)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [rgb(52, 55, 60), rgb(28, 30, 33)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(shade, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
ctx.restoreGState()

// A print: white border, a quiet landscape inside
func print(center: CGPoint, angle: CGFloat, tone: CGFloat, scene: Bool) {
    let w: CGFloat = 470, h: CGFloat = 340, border: CGFloat = 22
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle * .pi / 180)
    let r = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: rgb(0, 0, 0, 0.45))
    ctx.setFillColor(rgb(245 * tone, 243 * tone, 238 * tone))
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil)); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    let inner = r.insetBy(dx: border, dy: border)
    ctx.clip(to: inner)
    if scene {
        let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [rgb(126, 150, 172), rgb(204, 196, 178)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: inner.maxY), end: CGPoint(x: 0, y: inner.minY + 90), options: [.drawsAfterEndLocation])
        ctx.setFillColor(rgb(232, 214, 176)); ctx.fillEllipse(in: CGRect(x: inner.minX + 290, y: inner.minY + 150, width: 58, height: 58))
        let far = CGMutablePath()
        far.move(to: CGPoint(x: inner.minX, y: inner.minY + 110))
        far.addLine(to: CGPoint(x: inner.minX + 110, y: inner.minY + 200))
        far.addLine(to: CGPoint(x: inner.minX + 190, y: inner.minY + 150))
        far.addLine(to: CGPoint(x: inner.minX + 300, y: inner.minY + 230))
        far.addLine(to: CGPoint(x: inner.maxX, y: inner.minY + 120))
        far.addLine(to: CGPoint(x: inner.maxX, y: inner.minY)); far.addLine(to: CGPoint(x: inner.minX, y: inner.minY))
        ctx.addPath(far); ctx.setFillColor(rgb(84, 98, 110)); ctx.fillPath()
        let near = CGMutablePath()
        near.move(to: CGPoint(x: inner.minX, y: inner.minY + 70))
        near.addCurve(to: CGPoint(x: inner.maxX, y: inner.minY + 60), control1: CGPoint(x: inner.minX + 150, y: inner.minY + 120),
                      control2: CGPoint(x: inner.minX + 280, y: inner.minY + 20))
        near.addLine(to: CGPoint(x: inner.maxX, y: inner.minY)); near.addLine(to: CGPoint(x: inner.minX, y: inner.minY))
        ctx.addPath(near); ctx.setFillColor(rgb(46, 56, 60)); ctx.fillPath()
    } else {
        ctx.setFillColor(rgb(150 * tone, 156 * tone, 164 * tone)); ctx.fill(inner)
    }
    ctx.restoreGState()
}

print(center: CGPoint(x: 492, y: 560), angle: 9, tone: 0.78, scene: false)
print(center: CGPoint(x: 520, y: 536), angle: -6, tone: 0.88, scene: false)
print(center: CGPoint(x: 512, y: 470), angle: 2, tone: 1, scene: true)

// Pick mark
let badge = CGRect(x: 640, y: 560, width: 170, height: 170)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: rgb(0, 0, 0, 0.4))
ctx.setFillColor(rgb(77, 209, 107)); ctx.fillEllipse(in: badge)
ctx.restoreGState()
ctx.setStrokeColor(rgb(16, 30, 18)); ctx.setLineWidth(22); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: badge.minX + 45, y: badge.midY + 2))
ctx.addLine(to: CGPoint(x: badge.minX + 75, y: badge.midY - 30))
ctx.addLine(to: CGPoint(x: badge.maxX - 42, y: badge.midY + 34))
ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
