import SwiftUI
import AppKit

let pickGreen = Color(red: 0.30, green: 0.82, blue: 0.42)

struct ContentView: View {
    @EnvironmentObject var lib: Library
    @AppStorage("showFilmstrip") private var showFilmstrip = true

    var body: some View {
        Group {
            switch lib.phase {
            case .empty:
                EmptyState(title: "No Camera Connected", symbol: "sdcard",
                           message: lib.lastMessage ?? "Insert a memory card or connect your camera. Photo Picker opens it as soon as it shows up.")
            case .scanning(let name):
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("Reading \(name)…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .noPhotos(let name):
                EmptyState(title: "No Photos", symbol: "photo.on.rectangle.angled",
                           message: "\(name) doesn't contain any photos Photo Picker can read.")
            case .ready:
                VStack(spacing: 0) {
                    ZStack(alignment: .topTrailing) {
                        PhotoCanvas(lib: lib)
                        if lib.currentImage == nil { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                        if lib.isCurrentPicked { PickedBadge().padding(14).transition(.scale(scale: 0.6).combined(with: .opacity)) }
                        if lib.zoomed { ZoomHint().padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading) }
                    }
                    .animation(.spring(response: 0.22, dampingFraction: 0.7), value: lib.isCurrentPicked)
                    InfoBar()
                    if showFilmstrip { Filmstrip() }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .background(Color(nsColor: ZoomView.canvas))
        .background(WindowAccessor { lib.window = $0 })
        .navigationTitle(lib.title)
        .navigationSubtitle(lib.subtitle)
        .toolbar { MainToolbar() }
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

struct EmptyState: View {
    @EnvironmentObject var lib: Library
    let title: String, symbol: String, message: String
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            Button("Open Folder…") { lib.openPanel() }
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PickedBadge: View {
    var body: some View {
        Label("Picked", systemImage: "checkmark")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(pickGreen, in: Capsule())
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }
}

struct ZoomHint: View {
    var body: some View {
        Text("100%  ·  drag to look around  ·  Z or Esc to fit")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.55), in: Capsule())
    }
}

struct InfoBar: View {
    @EnvironmentObject var lib: Library
    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 18) {
            if let p = lib.current {
                HStack(spacing: 8) {
                    Text(p.name).fontWeight(.medium).foregroundStyle(.primary)
                    Text(p.kinds).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary.opacity(0.5)))
                }
                if let ex = lib.currentInfo?.exposure { Text(ex) }
                if let cam = lib.currentInfo?.camera { Text(cam).lineLimit(1) }
                Spacer(minLength: 8)
                if let d = lib.currentInfo?.captured ?? Optional(p.date) { Text(Self.dateFormat.string(from: d)) }
                Text("\(lib.index + 1) of \(lib.photos.count)").monospacedDigit().foregroundStyle(.primary)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(Color(white: 0.135))
        .overlay(alignment: .top) { Divider() }
    }
}

struct Filmstrip: View {
    @EnvironmentObject var lib: Library
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(Array(lib.photos.enumerated()), id: \.element.id) { i, p in
                        Thumb(photo: p, selected: i == lib.index, picked: lib.picked.contains(p.id))
                            .id(p.id)
                            .onTapGesture { lib.go(to: i) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onChange(of: lib.index) { _, _ in
                guard let id = lib.current?.id else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
            }
            .onAppear { if let id = lib.current?.id { proxy.scrollTo(id, anchor: .center) } }
        }
        .frame(height: 86)
        .background(Color(white: 0.09))
        .overlay(alignment: .top) { Divider() }
    }
}

struct Thumb: View {
    @EnvironmentObject var lib: Library
    let photo: Photo, selected: Bool, picked: Bool
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image { Image(nsImage: image).resizable().scaledToFill() } else { Color(white: 0.16) }
            }
            .frame(width: 96, height: 64)
            .clipped()
            .opacity(selected ? 1 : 0.72)
            if picked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.black, pickGreen)
                    .padding(3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(selected ? Color.white : (picked ? pickGreen.opacity(0.8) : .clear),
                                                          lineWidth: selected ? 2 : 1.5))
        .contentShape(Rectangle())
        .task(id: photo.id) { image = await lib.thumbnail(photo) }
    }
}

struct MainToolbar: ToolbarContent {
    @EnvironmentObject var lib: Library
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if lib.pendingCopies > 0 {
                ProgressView().controlSize(.small).help("Copying picks…")
            }
            Button { lib.togglePick() } label: {
                Label(lib.isCurrentPicked ? "Unpick" : "Pick",
                      systemImage: lib.isCurrentPicked ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .help(lib.isCurrentPicked ? "Remove from picks (Space)" : "Copy to picks (Space)")
            .disabled(lib.current == nil)
            Button { lib.revealPicks() } label: { Label("Show Picks", systemImage: "folder") }
                .help("Show the picks folder in Finder (⌘R)")
            if lib.canEject {
                Button { lib.eject() } label: { Label("Eject", systemImage: "eject") }
                    .help("Eject the card (⌘E)")
            }
        }
    }
}

struct ShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let rows: [(String, String)] = [
        ("← →", "Previous / next photo"),
        ("⇧ ← →", "Jump 10 photos"),
        ("Home  End", "First / last photo"),
        ("Space", "Pick, or unpick, the photo"),
        ("⌥ ← →", "Previous / next picked photo"),
        ("Z  or double-click", "Zoom to 100% and back"),
        ("Pinch", "Zoom in and out"),
        ("⌘R", "Show picks in Finder"),
        ("⌘E", "Eject the card"),
        ("⌘O", "Open a folder"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keyboard Shortcuts").font(.title3.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                ForEach(rows, id: \.0) { k, v in
                    GridRow {
                        Text(k).font(.system(.body, design: .rounded).weight(.medium)).gridColumnAlignment(.trailing)
                        Text(v).foregroundStyle(.secondary)
                    }
                }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24)
        .frame(width: 420)
    }
}

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
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button("Choose…", action: choose)
                    }
                }
                Toggle("Put each day's picks in their own folder", isOn: $daySubfolders)
            } footer: {
                Text("Picks are copied to \(example)").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker("For RAW + JPEG shots, copy", selection: $copyMode) {
                    ForEach(CopyMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Play a sound when you pick a photo", isOn: $pickSound)
            } footer: {
                Text("Originals on the card are never changed. Unpicking moves the copy to the Trash.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
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
