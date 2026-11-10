import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var lib: Library
    @AppStorage("showFilmstrip") private var showFilmstrip = true

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Rule()
            Group {
                switch lib.phase {
                case .empty:
                    Stage(lines: lib.lastMessage.map { [$0.uppercased(), "WAITING FOR A CARD"] }
                          ?? ["NO CARD", "INSERT A MEMORY CARD OR CONNECT YOUR CAMERA"])
                case .scanning(let name):
                    Stage(lines: ["READING \(name.uppercased())"], busy: true)
                case .noPhotos(let name):
                    Stage(lines: ["NO PHOTOS IN \(name.uppercased())", "TRY ANOTHER FOLDER"])
                case .ready:
                    VStack(spacing: 0) {
                        Viewer()
                        Rule()
                        InfoBar()
                        CardMap()
                        if showFilmstrip {
                            Rule()
                            Filmstrip()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .font(Theme.mono(12))
        .foregroundStyle(Theme.text)
        .background(Theme.bg)
        .ignoresSafeArea()
        .frame(minWidth: 700, minHeight: 460)
        .background(WindowAccessor { lib.window = $0 })
        .onChange(of: lib.title, initial: true) { _, t in lib.window?.title = t }
        .dropDestination(for: URL.self) { urls, _ in
            guard let dir = urls.first(where: { $0.hasDirectoryPath }) else { return false }
            lib.open(dir)
            return true
        }
        .sheet(isPresented: $lib.showShortcuts) { ShortcutsSheet() }
        .alert("Photo Picker", isPresented: Binding(get: { lib.alert != nil }, set: { if !$0 { lib.alert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(lib.alert ?? "") }
    }
}

// MARK: top bar

struct TopBar: View {
    @EnvironmentObject var lib: Library
    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 0) {
                Text("PHOTO PICKER").foregroundStyle(Theme.dim)
                if lib.phase == .ready || lib.source != nil {
                    Text("  /  ").foregroundStyle(Theme.faint)
                    Text(lib.title.uppercased()).foregroundStyle(Theme.bright)
                }
                if lib.phase == .ready {
                    Text("  /  ").foregroundStyle(Theme.faint)
                    Text("\(Theme.pad(lib.photos.count)) SHOTS").foregroundStyle(Theme.dim)
                    Text("  ").foregroundStyle(Theme.faint)
                    Text("\(Theme.pad(lib.picked.count)) PICKED").foregroundStyle(lib.picked.isEmpty ? Theme.dim : Theme.brass)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 12)
            if lib.pendingCopies > 0 {
                HStack(spacing: 6) { Text("COPYING"); Spinner() }.foregroundStyle(Theme.brass)
            }
            if lib.phase == .ready {
                KeyButton(key: "SPACE", label: lib.isCurrentPicked ? "UNPICK" : "PICK", accent: lib.isCurrentPicked) { lib.togglePick() }
            } else {
                KeyButton(key: "⌘O", label: "OPEN FOLDER") { lib.openPanel() }
            }
            KeyButton(key: "⌘R", label: "PICKS") { lib.revealPicks() }
            if lib.canEject { KeyButton(key: "⌘E", label: "EJECT") { lib.eject() } }
            KeyButton(key: "?", label: "KEYS") { lib.showShortcuts = true }
        }
        .font(Theme.mono(11.5))
        .padding(.leading, 84)      // clear of the window buttons
        .padding(.trailing, 16)
        .frame(height: 38)
    }
}

// MARK: empty / loading

struct Stage: View {
    @EnvironmentObject var lib: Library
    let lines: [String]
    var busy = false

    private let card = """
     _____________
    |  ▌▌▌▌▌▌▌▌   \\
    |              |
    |              |
    |      SD      |
    |              |
    |______________|
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(card).foregroundStyle(busy ? Theme.text : Theme.dim).fixedSize()
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    HStack(spacing: 0) {
                        Text("> ").foregroundStyle(Theme.faint)
                        Text(line).foregroundStyle(i == 0 ? Theme.bright : Theme.dim)
                        if i == lines.count - 1 {
                            Text(" ")
                            if busy { Spinner().foregroundStyle(Theme.brass) } else { Cursor().foregroundStyle(Theme.text) }
                        }
                    }
                }
            }
            if !busy {
                KeyButton(key: "⌘O", label: "OPEN A FOLDER INSTEAD") { lib.openPanel() }
                    .padding(.leading, 16)
            }
        }
        .font(Theme.mono(13))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: viewer

struct Viewer: View {
    @EnvironmentObject var lib: Library
    var body: some View {
        ZStack {
            PhotoCanvas(lib: lib)
            if lib.currentImage == nil {
                HStack(spacing: 8) { Text("LOADING"); Spinner() }.foregroundStyle(Theme.dim)
            }
            Viewfinder().allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            if lib.isCurrentPicked {
                Text(" ■ PICKED ")
                    .font(Theme.mono(12, .semibold))
                    .foregroundStyle(Theme.bg)
                    .padding(.vertical, 3)
                    .background(Theme.brass)
                    .padding(20)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if lib.zoomed {
                Text("ZOOM 1:1  ·  DRAG TO PAN  ·  [Z] FIT")
                    .font(Theme.mono(11))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.bg.opacity(0.85))
                    .padding(20)
            }
        }
        .animation(.easeOut(duration: 0.12), value: lib.isCurrentPicked)
    }
}

/// Corner marks around the frame, like a viewfinder.
struct Viewfinder: View {
    var body: some View {
        let c = Theme.faint
        VStack {
            HStack { Text("┌─"); Spacer(); Text("─┐") }
            Spacer()
            HStack { Text("└─"); Spacer(); Text("─┘") }
        }
        .font(Theme.mono(13))
        .foregroundStyle(c)
        .padding(8)
    }
}

// MARK: info + card map

struct InfoBar: View {
    @EnvironmentObject var lib: Library
    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    var body: some View {
        HStack(spacing: 0) {
            if let p = lib.current {
                Text(p.name).foregroundStyle(Theme.bright)
                Text("  \(p.kinds.replacingOccurrences(of: " + ", with: "+"))").foregroundStyle(Theme.dim)
                sep
                if let ex = lib.currentInfo?.exposure { Text(ex); sep }
                if let cam = lib.currentInfo?.camera { Text(cam.uppercased()).foregroundStyle(Theme.dim) }
                Spacer(minLength: 12)
                Text(Self.dateFormat.string(from: lib.currentInfo?.captured ?? p.date)).foregroundStyle(Theme.dim)
                sep
                Text("\(Theme.pad(lib.index + 1))/\(Theme.pad(lib.photos.count))").foregroundStyle(Theme.bright)
            }
        }
        .font(Theme.mono(11.5))
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: 28)
    }

    private var sep: some View { Text("  │  ").foregroundStyle(Theme.faint) }
}

/// The whole card on one line: · shot, ■ picked, ▲ where you are. Click to jump.
struct CardMap: View {
    @EnvironmentObject var lib: Library
    var body: some View {
        GeometryReader { geo in
            let cw = Theme.advance(11)
            let cols = max(8, Int(geo.size.width / cw) - 1)
            Text(line(cols))
                .font(Theme.mono(11))
                .lineLimit(1)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { loc in
                    let n = lib.photos.count, c = Int(loc.x / cw)
                    let i = n <= cols ? Int((Double(c) * Double(n - 1) / Double(max(cols - 1, 1))).rounded()) : c * n / cols
                    lib.go(to: min(max(i, 0), lib.photos.count - 1))
                }
        }
        .frame(height: 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .help("Every shot on the card. ■ picked, ▲ current. Click to jump.")
    }

    private func picked(_ a: Int, _ b: Int) -> Bool {
        (a..<min(b, lib.photos.count)).contains { lib.picked.contains(lib.photos[$0].id) }
    }

    private func line(_ cols: Int) -> AttributedString {
        var out = AttributedString()
        let n = lib.photos.count
        guard n > 0 else { return out }
        func glyph(_ ch: String, _ color: Color) { var s = AttributedString(ch); s.foregroundColor = color; out += s }
        if n <= cols {
            // one mark per shot, evenly spaced
            var slots = [Int?](repeating: nil, count: cols)
            for i in 0..<n { slots[n == 1 ? 0 : i * (cols - 1) / (n - 1)] = i }
            for slot in slots {
                guard let i = slot else { glyph(" ", Theme.faint); continue }
                if i == lib.index { glyph("▲", Theme.bright) }
                else if lib.picked.contains(lib.photos[i].id) { glyph("■", Theme.brass) }
                else { glyph("·", Theme.dim) }
            }
        } else {
            // each character covers several shots
            for c in 0..<cols {
                let a = c * n / cols, b = max(a + 1, (c + 1) * n / cols)
                if (a..<b).contains(lib.index) { glyph("▲", Theme.bright) }
                else if picked(a, b) { glyph("■", Theme.brass) }
                else { glyph("·", Theme.faint) }
            }
        }
        return out
    }
}

// MARK: filmstrip

struct Filmstrip: View {
    @EnvironmentObject var lib: Library
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 18) {
                    ForEach(Array(lib.photos.enumerated()), id: \.element.id) { i, p in
                        Thumb(photo: p, selected: i == lib.index, picked: lib.picked.contains(p.id))
                            .id(p.id)
                            .onTapGesture { lib.go(to: i) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onChange(of: lib.index) { _, _ in
                guard let id = lib.current?.id else { return }
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .center) }
            }
            .onAppear { if let id = lib.current?.id { proxy.scrollTo(id, anchor: .center) } }
        }
        .frame(height: 104)
    }
}

/// A real thumbnail; the theme only touches its frame and label.
struct Thumb: View {
    @EnvironmentObject var lib: Library
    let photo: Photo, selected: Bool, picked: Bool
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Group {
                if let image { Image(nsImage: image).resizable().scaledToFill() } else { Theme.raised }
            }
            .frame(width: 96, height: 64)
            .clipped()
            .opacity(selected ? 1 : 0.6)
            .overlay(Rectangle().stroke(selected ? Theme.bright : (picked ? Theme.brass : Theme.faint), lineWidth: 1))
            HStack(spacing: 0) {
                Text(selected ? "▸" : " ").foregroundStyle(Theme.bright)
                Text(picked ? "■" : " ").foregroundStyle(Theme.brass)
                Text(" \(photo.name)").foregroundStyle(selected ? Theme.bright : Theme.dim)
            }
            .font(Theme.mono(10))
        }
        .contentShape(Rectangle())
        .task(id: photo.id) { image = await lib.thumbnail(photo) }
    }
}

// MARK: shortcuts

struct ShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let rows: [(String, String)] = [
        ("← →", "previous / next photo"),
        ("⇧ ← →", "jump 10 photos"),
        ("home  end", "first / last photo"),
        ("space", "pick / unpick"),
        ("⌥ ← →", "previous / next pick"),
        ("z  dbl-click", "zoom 1:1 and back"),
        ("⌘R", "show picks in finder"),
        ("⌘E", "eject card"),
        ("⌘O", "open a folder"),
        ("⌘,", "settings"),
    ]

    private var table: String {
        let k = 14, v = 26
        func row(_ a: String, _ b: String) -> String {
            "│ " + a.padding(toLength: k, withPad: " ", startingAt: 0) + " │ " + b.padding(toLength: v, withPad: " ", startingAt: 0) + " │"
        }
        let top = "┌" + String(repeating: "─", count: k + 2) + "┬" + String(repeating: "─", count: v + 2) + "┐"
        let mid = "├" + String(repeating: "─", count: k + 2) + "┼" + String(repeating: "─", count: v + 2) + "┤"
        let bot = "└" + String(repeating: "─", count: k + 2) + "┴" + String(repeating: "─", count: v + 2) + "┘"
        return ([top, row("KEY", "ACTION"), mid] + rows.map { row($0.0, $0.1) } + [bot]).joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(table).font(Theme.mono(12)).foregroundStyle(Theme.text).fixedSize()
            HStack { Spacer(); KeyButton(key: "esc", label: "CLOSE") { dismiss() } }
        }
        .padding(22)
        .background(Theme.bg)
        .onExitCommand { dismiss() }
    }
}

// MARK: settings

struct SettingsView: View {
    @EnvironmentObject var lib: Library
    @AppStorage("picksBase") private var picksBase = ""
    @AppStorage("daySubfolders") private var daySubfolders = true
    @AppStorage("copyMode") private var copyMode = CopyMode.both.rawValue
    @AppStorage("pickSound") private var pickSound = false

    private var baseURL: URL { picksBase.isEmpty ? Prefs.defaultBase : URL(fileURLWithPath: picksBase) }
    private var example: String {
        let p = (daySubfolders ? baseURL.appendingPathComponent(Prefs.today) : baseURL).path
        return (p as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Picks folder") {
                    HStack {
                        Text((baseURL.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(Theme.dim)
                        Button("Choose…", action: choose)
                    }
                }
                Toggle("A folder for each day", isOn: $daySubfolders)
            } footer: {
                Text("> picks go to \(example)").foregroundStyle(Theme.dim)
            }
            Section {
                Picker("RAW + JPEG shots: copy", selection: $copyMode) {
                    ForEach(CopyMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Sound when picking", isOn: $pickSound)
            } footer: {
                Text("> the card is never changed. unpicking moves the copy to the trash.").foregroundStyle(Theme.dim)
            }
        }
        .formStyle(.grouped)
        .font(Theme.mono(12))
        .tint(Theme.brass)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: picksBase) { lib.refreshPicked() }
        .onChange(of: daySubfolders) { lib.refreshPicked() }
        .onChange(of: copyMode) { lib.refreshPicked() }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.directoryURL = baseURL
        if panel.runModal() == .OK, let u = panel.url { picksBase = u.path }
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        if let w = v.window { DispatchQueue.main.async { onWindow(w) } }
    }
}
