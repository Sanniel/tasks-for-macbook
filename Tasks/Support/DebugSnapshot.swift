#if DEBUG
import AppKit

/// Debug-only: launched with `-snapshot`, the app saves an image of its main window
/// to `<sandbox tmp>/snapshot.png` after a short delay and quits. Lets the UI be
/// checked from the command line without screen-recording permission.
enum DebugSnapshot {
    @MainActor
    static func scheduleIfRequested() {
        guard CommandLine.arguments.contains("-snapshot") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            MainActor.assumeIsolated {
                guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                      let view = window.contentView?.superview ?? window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "snapshot.png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                print("Snapshot written to \(url.path)")
                NSApp.terminate(nil)
            }
        }
    }
}
#endif
