import AppKit

/// PHOTOPICKER_SELFTEST=<dir>: drives the app with real key events (through NSApp.sendEvent,
/// the same path as the keyboard), prints state after each, and saves window snapshots.
/// PHOTOPICKER_SELFTEST_EJECT=1 ejects the card at the end.
enum SelfTest {
    static let active = ProcessInfo.processInfo.environment["PHOTOPICKER_SELFTEST"] != nil

    static func run(_ out: String) {
        let lib = Library.shared
        snap("0-launch", out, after: 2.0)
        waitForReady(deadline: Date().addingTimeInterval(30)) {
            let steps: [(String, () -> Void)] = [
                ("space", key(49)), ("right", key(124)), ("right", key(124)), ("right", key(124)),
                ("right", key(124)), ("space", key(49)), ("right", key(124)), ("right-at-end", key(124)),
                ("left", key(123)), ("space-unpick", key(49)), ("space-repick", key(49)),
                ("shift-left", key(123, shift: true)), ("opt-right(next picked)", { lib.goToPicked(forward: true) }),
                ("z-zoom", key(6)),
            ]
            var t = 0.6
            for (i, (name, act)) in steps.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                    act()
                    print("\(i + 1) \(name): \(status())")
                }
                t += 0.6
            }
            snapAt("1-browsing", out, delay: 3.0)   // after the space on photo 5
            snapAt("2-zoomed", out, delay: t + 1.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + t + 2.0) {
                key(53)()
                print("esc: \(status())")
                if let w = lib.window { print("window \(w.frame.size) screen \(w.screen?.visibleFrame.size ?? .zero)") }
                if ProcessInfo.processInfo.environment["PHOTOPICKER_SELFTEST_EJECT"] == "1" {
                    lib.eject()
                    print("eject requested: phase=\(lib.phase)")
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + t + 5.0) {
                print("final: pending=\(lib.pendingCopies) phase=\(lib.phase) message=\(lib.lastMessage ?? "-") alert=\(lib.alert ?? "-")")
                snap("3-final", out, after: 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
            }
        }
    }

    private static func status() -> String {
        let lib = Library.shared
        return "\(lib.index + 1)/\(lib.photos.count) \(lib.current?.name ?? "-") picked=\(lib.isCurrentPicked) total=\(lib.picked.count) zoomed=\(lib.zoomed)"
    }

    private static func waitForReady(deadline: Date, then: @escaping () -> Void) {
        if Library.shared.phase == .ready { then(); return }
        guard Date() < deadline else { print("never became ready: \(Library.shared.phase)"); snap("x-timeout", "", after: 0); NSApp.terminate(nil); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { waitForReady(deadline: deadline, then: then) }
    }

    private static func key(_ code: UInt16, shift: Bool = false) -> () -> Void {
        return {
            guard let w = Library.shared.window,
                  let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? .shift : [],
                                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                           context: nil, characters: " ", charactersIgnoringModifiers: " ",
                                           isARepeat: false, keyCode: code) else { print("no window"); return }
            NSApp.sendEvent(e)
        }
    }

    private static func snapAt(_ name: String, _ out: String, delay: Double) {
        snap(name, out, after: delay)
    }

    static func snap(_ name: String, _ out: String, after: Double) {
        guard !out.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + after) {
            guard let w = Library.shared.window, let v = w.contentView?.superview ?? w.contentView,
                  let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { print("snap \(name): no window"); return }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
        }
    }
}
