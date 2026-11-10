import SwiftUI
import AppKit

@main
struct PhotoPickerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var lib = Library.shared

    // The main window is created by AppDelegate (SwiftUI skips its own window when the app is
    // launched by dropping a folder on it), so the only scene here is Settings.
    var body: some Scene {
        Settings {
            SettingsView().environmentObject(lib)
        }
        .commands { AppCommands(lib: lib) }
    }
}

struct AppCommands: Commands {
    @ObservedObject var lib: Library
    @AppStorage("showFilmstrip") private var showFilmstrip = true

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…") { lib.openPanel() }.keyboardShortcut("o")
            Button("Open Camera Card") { lib.openCardIfPresent() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Show Picks in Finder") { lib.revealPicks() }.keyboardShortcut("r")
            Button("Show Original in Finder") { lib.revealOriginal() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(lib.current == nil)
            Divider()
            Button("Eject Card") { lib.eject() }.keyboardShortcut("e").disabled(!lib.canEject)
        }
        CommandGroup(after: .toolbar) {
            Toggle("Show Filmstrip", isOn: $showFilmstrip).keyboardShortcut("f", modifiers: [.command, .option])
            Divider()
            Button("Actual Size") { lib.zoomed = true }.keyboardShortcut("0").disabled(lib.current == nil)
            Button("Zoom to Fit") { lib.zoomed = false }.keyboardShortcut("9").disabled(lib.current == nil)
        }
        CommandMenu("Photo") {
            Button(lib.isCurrentPicked ? "Unpick Photo" : "Pick Photo") { lib.togglePick() }
                .disabled(lib.current == nil)
            Divider()
            Button("Next Photo") { lib.go(1) }.disabled(lib.current == nil)
            Button("Previous Photo") { lib.go(-1) }.disabled(lib.current == nil)
            Button("Next Picked Photo") { lib.goToPicked(forward: true) }
                .keyboardShortcut(.rightArrow, modifiers: .option).disabled(lib.picked.isEmpty)
            Button("Previous Picked Photo") { lib.goToPicked(forward: false) }
                .keyboardShortcut(.leftArrow, modifiers: .option).disabled(lib.picked.isEmpty)
            Divider()
            Button("First Photo") { lib.go(to: 0) }.keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(lib.current == nil)
            Button("Last Photo") { lib.go(to: lib.photos.count - 1) }.keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(lib.current == nil)
        }
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { lib.showShortcuts = true }.keyboardShortcut("/")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    private func showMainWindow() {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let host = NSHostingController(rootView: ContentView().environmentObject(Library.shared).preferredColorScheme(.dark))
        host.sceneBridgingOptions = [.toolbars, .title]
        host.sizingOptions = [.minSize]
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.toolbarStyle = .unified
        w.appearance = NSAppearance(named: .darkAqua)
        w.collectionBehavior.insert(.fullScreenPrimary)
        w.isReleasedWhenClosed = false
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        w.setContentSize(NSSize(width: min(1180, screen.width * 0.85), height: min(780, screen.height * 0.85)))
        w.center()
        w.setFrameAutosaveName("PhotoPickerMain")   // remembers size and position
        w.makeKeyAndOrderFront(nil)
        Library.shared.window = w
        window = w
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        showMainWindow()
        NSApp.activate(ignoringOtherApps: true)
        let lib = Library.shared
        if lib.phase == .empty {
            if let arg = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }),
               FileManager.default.fileExists(atPath: arg) {
                lib.open(URL(fileURLWithPath: arg))
            } else {
                lib.openCardIfPresent()
            }
        }
        if let out = ProcessInfo.processInfo.environment["PHOTOPICKER_SELFTEST"] { SelfTest.run(out) }
    }

    func application(_ app: NSApplication, open urls: [URL]) {
        showMainWindow()
        if let url = urls.first { Library.shared.open(url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    /// Never quit halfway through copying a RAW file into picks.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Library.shared.pendingCopies > 0 else { return .terminateNow }
        func check() {
            if Library.shared.pendingCopies == 0 { NSApp.reply(toApplicationShouldTerminate: true) }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: check) }
        }
        check()
        return .terminateLater
    }
}
