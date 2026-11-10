import SwiftUI
import AppKit

/// Text-mode theme: SF Mono only, tarnished cream on near-black, one brass accent for picks.
enum Theme {
    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
    static let nsBG = rgb(0x0d0d0c)
    static let bg = Color(nsColor: nsBG)
    static let raised = Color(nsColor: rgb(0x141412))
    static let bright = Color(nsColor: rgb(0xe6dfcf))
    static let text = Color(nsColor: rgb(0xc4bdad))
    static let dim = Color(nsColor: rgb(0x7c766a))
    static let faint = Color(nsColor: rgb(0x403d37))
    static let brass = Color(nsColor: rgb(0xc2a15e))

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// SF Mono advance is 0.618 em; line height 1.25 em.
    static func advance(_ size: CGFloat) -> CGFloat { size * 0.618 }

    static func pad(_ n: Int, _ width: Int = 3) -> String {
        let s = String(n)
        return String(repeating: "0", count: max(0, width - s.count)) + s
    }
}

/// `[KEY] LABEL` text button.
struct KeyButton: View {
    let key: String
    let label: String
    var accent = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text("[").foregroundStyle(Theme.faint)
                Text(key).foregroundStyle(hover ? Theme.bright : (accent ? Theme.brass : Theme.dim))
                Text("] ").foregroundStyle(Theme.faint)
                Text(label).foregroundStyle(hover ? Theme.bright : (accent ? Theme.brass : Theme.text))
            }
            .font(Theme.mono(11.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// A horizontal rule made of box-drawing characters.
struct Rule: View {
    var color = Theme.faint
    var body: some View {
        GeometryReader { geo in
            Text(String(repeating: "─", count: max(1, Int(geo.size.width / Theme.advance(11)))))
                .font(Theme.mono(11))
                .foregroundStyle(color)
                .lineLimit(1)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        .frame(height: 9)
        .clipped()
    }
}

/// |/-\ spinner and a blinking block cursor, both driven by the clock.
struct Spinner: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            let frames = ["|", "/", "-", "\\"]
            Text(frames[Int(ctx.date.timeIntervalSinceReferenceDate * 10) % 4])
        }
    }
}

struct Cursor: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.53)) { ctx in
            Text("█").opacity(Int(ctx.date.timeIntervalSinceReferenceDate / 0.53) % 2 == 0 ? 1 : 0)
        }
    }
}
