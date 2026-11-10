import AppKit
import Combine
import Photos

enum CopyMode: String, CaseIterable, Identifiable {
    case both, jpegOnly, rawOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .both: return "RAW and JPEG"
        case .jpegOnly: return "JPEG only"
        case .rawOnly: return "RAW only"
        }
    }
    func files(of p: Photo) -> [URL] {
        let pick: (URL) -> Bool
        switch self {
        case .both: return p.files
        case .jpegOnly: pick = { previewExts.contains($0.pathExtension.lowercased()) }
        case .rawOnly: pick = { rawExts.contains($0.pathExtension.lowercased()) }
        }
        let chosen = p.files.filter(pick)
        return chosen.isEmpty ? p.files : chosen   // a JPEG-only shot still copies its JPEG in RAW-only mode
    }
    func resources(of p: Photo) -> [PHAssetResource] {
        let chosen: [PHAssetResource]
        switch self {
        case .both: return p.resources
        case .jpegOnly: chosen = p.resources.filter { !PhotosSource.isRaw($0) }
        case .rawOnly: chosen = p.resources.filter(PhotosSource.isRaw)
        }
        return chosen.isEmpty ? p.resources : chosen
    }
}

enum Prefs {
    static let defaults = UserDefaults.standard
    static let defaultBase = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Camera Picks")
    static var picksBase: URL {
        if let o = ProcessInfo.processInfo.environment["PHOTOPICKER_PICKS"] { return URL(fileURLWithPath: o) }
        if let p = defaults.string(forKey: "picksBase"), !p.isEmpty { return URL(fileURLWithPath: p) }
        return defaultBase
    }
    static var daySubfolders: Bool { defaults.object(forKey: "daySubfolders") as? Bool ?? true }
    static var copyMode: CopyMode { CopyMode(rawValue: defaults.string(forKey: "copyMode") ?? "") ?? .both }
    static var pickSound: Bool { defaults.bool(forKey: "pickSound") }
    static var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
    static var picksFolder: URL { daySubfolders ? picksBase.appendingPathComponent(today) : picksBase }

    // Apple Photos source: one flat folder, Desktop by default.
    static let defaultPhotosFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Fujifilm Picks")
    static var photosPicksFolder: URL {
        if let o = ProcessInfo.processInfo.environment["PHOTOPICKER_PICKS"] { return URL(fileURLWithPath: o).appendingPathComponent("photos") }
        if let p = defaults.string(forKey: "photosPicksFolder"), !p.isEmpty { return URL(fileURLWithPath: p) }
        return defaultPhotosFolder
    }
    static var photosFujifilmOnly: Bool { defaults.object(forKey: "photosFujifilmOnly") as? Bool ?? true }
}

/// Everything the window shows: the open card, the current photo, and what has been picked.
final class Library: ObservableObject {
    static let shared = Library()

    enum Phase: Equatable { case empty, scanning(String), ready, noPhotos(String) }

    @Published private(set) var phase: Phase = .empty
    @Published private(set) var photos: [Photo] = []
    @Published private(set) var index = 0
    @Published private(set) var picked: Set<String> = []
    @Published private(set) var source: URL?
    @Published private(set) var photosMode = false      // browsing the Apple Photos library
    @Published private(set) var pendingCopies = 0
    @Published private(set) var currentImage: NSImage?
    @Published private(set) var currentInfo: PhotoInfo?
    @Published var zoomed = false { didSet { if zoomed && !oldValue { loadFullResolution() } } }
    @Published var showShortcuts = false
    @Published var alert: String?
    @Published var lastMessage: String?
    weak var window: NSWindow?

    private var generation = 0
    private let previews = NSCache<NSString, NSImage>()
    private let thumbs = NSCache<NSString, NSImage>()
    private var infos: [String: PhotoInfo] = [:]
    private var inflight = Set<String>()
    private var fullImage: (id: String, image: NSImage)?
    private let loadQueue = DispatchQueue(label: "preview", qos: .userInitiated, attributes: .concurrent)
    private let thumbQueue = DispatchQueue(label: "thumbs", qos: .utility, attributes: .concurrent)
    private let copyQueue = DispatchQueue(label: "copy", qos: .userInitiated)
    private var keyMonitor: Any?

    init() {
        previews.countLimit = 16
        thumbs.countLimit = 4000
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(volumeMounted(_:)), name: NSWorkspace.didMountNotification, object: nil)
        ws.addObserver(self, selector: #selector(volumeUnmounted(_:)), name: NSWorkspace.didUnmountNotification, object: nil)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            (self?.handleKey(e) ?? false) ? nil : e
        }
    }

    // MARK: derived state

    var current: Photo? { photos.indices.contains(index) ? photos[index] : nil }
    var isCurrentPicked: Bool { current.map { picked.contains($0.id) } ?? false }
    var title: String {
        if photosMode { return Prefs.photosFujifilmOnly ? "Apple Photos · Fujifilm" : "Apple Photos" }
        guard let source else { return "Photo Picker" }
        return volume(of: source).flatMap { $0.path == "/" ? nil : $0.lastPathComponent } ?? source.lastPathComponent
    }
    var subtitle: String {
        guard phase == .ready else { return "" }
        let n = photos.count
        return "\(n) photo\(n == 1 ? "" : "s") · \(picked.count) picked"
    }
    var canEject: Bool {
        guard !photosMode, let source, let vol = volume(of: source), vol.path != "/" else { return false }
        let v = try? vol.resourceValues(forKeys: [.volumeIsEjectableKey, .volumeIsRemovableKey])
        return v?.volumeIsEjectable == true || v?.volumeIsRemovable == true
    }
    private var previewPixels: Int {
        let s = window?.screen ?? NSScreen.main
        return Int(max(s?.frame.width ?? 1800, s?.frame.height ?? 1200) * (s?.backingScaleFactor ?? 2))
    }

    private func volume(of url: URL) -> URL? {
        (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume
    }

    static func cameraCards() -> [URL] {
        let vols = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        return vols.filter { $0.path != "/" && FileManager.default.fileExists(atPath: $0.appendingPathComponent("DCIM").path) }
    }

    // MARK: opening

    func openCardIfPresent() {
        if let card = Library.cameraCards().first { open(card) }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose a camera card or a folder of photos"
        panel.prompt = "Open"
        panel.directoryURL = Library.cameraCards().first ?? source
        if let w = window {
            panel.beginSheetModal(for: w) { [weak self] r in if r == .OK, let u = panel.url { self?.open(u) } }
        } else if panel.runModal() == .OK, let u = panel.url { open(u) }
    }

    /// Where picks from what's open right now are copied.
    var picksFolder: URL { photosMode ? Prefs.photosPicksFolder : Prefs.picksFolder }

    func openPhotosLibrary() {
        PhotosSource.authorize { [weak self] ok in
            guard let self else { return }
            guard ok else {
                self.alert = "Photo Picker doesn't have access to your Photos library. Turn it on in System Settings → Privacy & Security → Photos, then try again."
                return
            }
            self.generation += 1
            let gen = self.generation
            self.resetContents()
            self.lastMessage = nil
            self.source = nil
            self.photosMode = true
            self.phase = .scanning("APPLE PHOTOS")
            let fujiOnly = Prefs.photosFujifilmOnly, dest = Prefs.photosPicksFolder, mode = Prefs.copyMode
            self.loadQueue.async {
                let found = PhotosSource.scan(fujifilmOnly: fujiOnly) { done, total in
                    DispatchQueue.main.async {
                        guard gen == self.generation else { return }
                        self.phase = .scanning("APPLE PHOTOS  \(Theme.pad(done, String(total).count))/\(total)")
                    }
                }
                let already = Set(found.filter { Library.isPicked($0, in: dest, mode: mode) }.map(\.id))
                DispatchQueue.main.async {
                    guard gen == self.generation else { return }
                    self.photos = found
                    self.picked = already
                    self.index = max(0, found.count - 1)       // newest shot first
                    self.phase = found.isEmpty ? .noPhotos(fujiOnly ? "your Photos library (no Fujifilm shots)" : "your Photos library") : .ready
                    self.showCurrent()
                }
            }
        }
    }

    func open(_ root: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { return }
        generation += 1
        let gen = generation
        resetContents()
        lastMessage = nil
        photosMode = false
        source = root
        let name = title
        phase = .scanning(name)
        let dest = Prefs.picksFolder, mode = Prefs.copyMode
        loadQueue.async {
            let found = Imaging.scan(root)
            let already = Set(found.filter { Library.isPicked($0, in: dest, mode: mode) }.map(\.id))
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.generation else { return }
                self.photos = found
                self.picked = already
                self.index = 0
                self.phase = found.isEmpty ? .noPhotos(name) : .ready
                self.showCurrent()
            }
        }
    }

    func close() {
        generation += 1
        resetContents()
        source = nil
        photosMode = false
        phase = .empty
    }

    private func resetContents() {
        photos = []
        picked = []
        index = 0
        zoomed = false
        currentImage = nil
        currentInfo = nil
        fullImage = nil
        infos = [:]
        inflight = []
        previews.removeAllObjects()
        thumbs.removeAllObjects()
    }

    /// Re-check which photos are already in the picks folder (after Settings change).
    func refreshPicked() {
        guard phase == .ready else { return }
        let all = photos, dest = picksFolder, mode = Prefs.copyMode, gen = generation
        loadQueue.async {
            let already = Set(all.filter { Library.isPicked($0, in: dest, mode: mode) }.map(\.id))
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.generation else { return }
                self.picked = already
            }
        }
    }

    @objc private func volumeMounted(_ n: Notification) {
        guard phase == .empty,
              let vol = n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL,
              FileManager.default.fileExists(atPath: vol.appendingPathComponent("DCIM").path) else { return }
        open(vol)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func volumeUnmounted(_ n: Notification) {
        guard let vol = n.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL, let source else { return }
        let v = vol.standardizedFileURL.path
        if source.standardizedFileURL.path == v || source.standardizedFileURL.path.hasPrefix(v + "/") { close() }
    }

    func eject() {
        guard let source, let vol = volume(of: source) else { return }
        guard pendingCopies == 0 else {
            alert = "Photo Picker is still copying picks from this card. Eject again when it's done."
            return
        }
        let name = title
        close()
        lastMessage = "Ejecting \(name)…"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: vol)
                DispatchQueue.main.async { Library.shared.lastMessage = "\(name) ejected. It's safe to remove." }
            } catch {
                DispatchQueue.main.async {
                    Library.shared.alert = "Couldn't eject \(name): \(error.localizedDescription)"
                    Library.shared.open(source)
                }
            }
        }
    }

    // MARK: navigation

    func go(_ delta: Int) { go(to: index + delta) }

    func go(to i: Int) {
        guard !photos.isEmpty else { return }
        let next = min(max(i, 0), photos.count - 1)
        guard next != index else { NSSound.beep(); return }
        index = next
        if zoomed { zoomed = false }
        showCurrent()
    }

    func goToPicked(forward: Bool) {
        let order = forward ? Array(photos.indices.dropFirst(index + 1)) : Array(photos.indices.prefix(index).reversed())
        if let i = order.first(where: { picked.contains(photos[$0].id) }) { go(to: i) } else { NSSound.beep() }
    }

    private func showCurrent() {
        guard let p = current else { currentImage = nil; currentInfo = nil; return }
        currentImage = previews.object(forKey: p.id as NSString)
        currentInfo = infos[p.id]
        requestPreview(index)
        for d in [1, -1, 2, 3, -2] { requestPreview(index + d) }
    }

    private func requestPreview(_ i: Int) {
        guard photos.indices.contains(i) else { return }
        let p = photos[i], key = p.id as NSString
        guard previews.object(forKey: key) == nil, !inflight.contains(p.id) else { return }
        inflight.insert(p.id)
        let gen = generation, px = previewPixels
        loadQueue.async {
            let img = Library.loadImage(p, maxPixel: px, minAcceptable: 1600)
            let info = p.asset.map(PhotosSource.info) ?? p.display.map(Imaging.info) ?? PhotoInfo()
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.generation else { return }
                self.inflight.remove(p.id)
                self.infos[p.id] = info
                if let img { self.previews.setObject(img, forKey: key) }
                if self.current?.id == p.id {
                    self.currentInfo = info
                    if self.fullImage?.id != p.id { self.currentImage = img }
                }
            }
        }
    }

    private func loadFullResolution() {
        guard let p = current else { return }
        if let f = fullImage, f.id == p.id { currentImage = f.image; return }
        let size = infos[p.id]?.pixelSize ?? CGSize(width: 9000, height: 9000)
        let px = Int(max(size.width, size.height)), gen = generation
        loadQueue.async {
            guard let img = Library.loadImage(p, maxPixel: p.asset == nil ? px : nil, minAcceptable: px) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.generation, self.current?.id == p.id else { return }
                self.fullImage = (p.id, img)
                self.currentImage = img
            }
        }
    }

    func thumbnail(_ p: Photo) async -> NSImage? {
        let key = p.id as NSString
        if let t = thumbs.object(forKey: key) { return t }
        let queue = thumbQueue
        let img: NSImage? = await withCheckedContinuation { c in
            queue.async { c.resume(returning: Library.loadImage(p, maxPixel: 240, minAcceptable: 120)) }
        }
        if let img { thumbs.setObject(img, forKey: key) }
        return img
    }

    /// Decodes a photo from a file or from Photos. nil maxPixel = full size (Photos only).
    static func loadImage(_ p: Photo, maxPixel: Int?, minAcceptable: Int) -> NSImage? {
        if let a = p.asset { return PhotosSource.image(a, maxPixel: maxPixel) }
        guard let url = p.display else { return nil }
        return Imaging.image(url, maxPixel: maxPixel ?? 20000, minAcceptable: minAcceptable)
    }

    // MARK: picking

    func togglePick() {
        guard let p = current else { return }
        let dest = picksFolder, mode = Prefs.copyMode
        let adding = !picked.contains(p.id)
        if adding { picked.insert(p.id) } else { picked.remove(p.id) }
        if adding && Prefs.pickSound { NSSound(named: "Tink")?.play() }
        pendingCopies += 1
        copyQueue.async {
            let fm = FileManager.default
            var failure: String?
            do {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                if adding, p.asset != nil {
                    for r in mode.resources(of: p) {
                        let target = dest.appendingPathComponent(PhotosSource.exportName(r, date: p.date))
                        if SelfTest.active { print("  export \(r.originalFilename) -> \(target.lastPathComponent)") }
                        if !fm.fileExists(atPath: target.path) { try PhotosSource.write(r, to: target, date: p.date) }
                        if SelfTest.active { print("  wrote \(target.lastPathComponent): \((try? fm.attributesOfItem(atPath: target.path)[.size] as? NSNumber)??.intValue ?? -1) bytes") }
                    }
                } else if p.asset != nil {
                    for r in p.resources {
                        let target = dest.appendingPathComponent(PhotosSource.exportName(r, date: p.date))
                        guard fm.fileExists(atPath: target.path) else { continue }
                        if SelfTest.active { try fm.removeItem(at: target) } else { try fm.trashItem(at: target, resultingItemURL: nil) }
                    }
                } else if adding {
                    for f in mode.files(of: p) {
                        let target = Library.destination(for: f, in: dest)
                        if SelfTest.active { print("  copy \(f.lastPathComponent) -> \(target.url.lastPathComponent) exists=\(target.exists)") }
                        if !target.exists { try fm.copyItem(at: f, to: target.url) }
                    }
                } else {
                    for f in p.files {   // every copy of this shot, whatever the copy setting was
                        let target = Library.destination(for: f, in: dest)
                        if SelfTest.active { print("  remove \(f.lastPathComponent) -> \(target.url.lastPathComponent) exists=\(target.exists)") }
                        guard target.exists else { continue }
                        if SelfTest.active { try fm.removeItem(at: target.url) }   // keep test runs out of the Trash
                        else { try fm.trashItem(at: target.url, resultingItemURL: nil) }
                    }
                }
            } catch { failure = error.localizedDescription }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingCopies -= 1
                guard let failure else { return }
                if adding { self.picked.remove(p.id) } else { self.picked.insert(p.id) }
                self.alert = (adding ? "Couldn't copy \(p.name): " : "Couldn't remove \(p.name) from picks: ") + failure
            }
        }
    }

    func revealPicks() {
        let dir = picksFolder
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    func revealOriginal() {
        guard let p = current, p.asset == nil else { return }
        NSWorkspace.shared.activateFileViewerSelecting(p.files)
    }

    static func isPicked(_ p: Photo, in dest: URL, mode: CopyMode) -> Bool {
        if p.asset != nil {
            return mode.resources(of: p).allSatisfy {
                FileManager.default.fileExists(atPath: dest.appendingPathComponent(PhotosSource.exportName($0, date: p.date)).path)
            }
        }
        return mode.files(of: p).allSatisfy { destination(for: $0, in: dest).exists }
    }

    /// Cameras restart numbering per DCIM folder, so a clash with a *different* file gets the
    /// folder name as a prefix (101CANON_IMG_0001.CR3). A copy keeps size + modification date.
    static func destination(for file: URL, in dir: URL) -> (url: URL, exists: Bool) {
        let plain = dir.appendingPathComponent(file.lastPathComponent)
        guard FileManager.default.fileExists(atPath: plain.path) else { return (plain, false) }
        if sameFile(plain, file) { return (plain, true) }
        let alt = dir.appendingPathComponent("\(file.deletingLastPathComponent().lastPathComponent)_\(file.lastPathComponent)")
        return (alt, sameFile(alt, file))
    }

    private static func sameFile(_ a: URL, _ b: URL) -> Bool {
        let k: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let x = try? a.resourceValues(forKeys: k), let y = try? b.resourceValues(forKeys: k),
              let sx = x.fileSize, let mx = x.contentModificationDate else { return false }
        return sx == y.fileSize && abs(mx.timeIntervalSince(y.contentModificationDate ?? .distantPast)) < 0.01
    }

    // MARK: keyboard

    /// Plain keys (arrows, Space, Z) are handled here rather than as menu shortcuts so they never
    /// fire while you're typing in an Open panel or another window.
    private func handleKey(_ e: NSEvent) -> Bool {
        guard let w = window, e.window === w, w.attachedSheet == nil, phase == .ready,
              !(w.firstResponder is NSText) else { return false }
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function, .capsLock])
        guard mods.isEmpty || mods == .shift else { return false }
        let step = mods == .shift ? 10 : 1
        switch e.keyCode {
        case 123, 126: go(-step)                         // ← ↑
        case 124, 125: go(step)                          // → ↓
        case 49: togglePick()                            // space
        case 115: go(to: 0)                              // home
        case 119: go(to: photos.count - 1)               // end
        case 6: zoomed.toggle()                          // Z
        case 53 where zoomed: zoomed = false             // esc
        default: return false
        }
        return true
    }
}
