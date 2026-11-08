import AppKit
import SwiftUI

// Screenshot mode for CI. Inactive unless the environment variable DS_SNAPSHOT_DIR is set, which
// only the CI workflow (or a developer, deliberately) does. In that mode the running app resizes
// its real window, shows each section, renders the window's own view hierarchy to PNG and quits.
//
// Why the app captures itself: system screenshots of a CI runner's screen need Screen Recording
// permission that a non-interactive job cannot grant. Rendering its own window needs no permission.
// The images are the actual views of the running app, not mock-ups. Parts drawn by the window
// server outside the app's views (window shadow, and on some systems the title bar) may be missing.
//
// The same file is kept in each product; keep the copies identical.

enum DSSnapshot {
    static let environmentKey = "DS_SNAPSHOT_DIR"

    static var directory: URL? {
        guard let path = ProcessInfo.processInfo.environment[environmentKey], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static var isActive: Bool { directory != nil }

    struct Entry {
        let file: String
        let section: String
        let state: String
        let size: CGSize
        let ok: Bool
    }

    @MainActor static var window: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) }
    }

    @MainActor static func resize(to size: CGSize) {
        guard let window else { return }
        window.setContentSize(size)
        window.center()
    }

    static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Renders the window (frame view including the title bar where AppKit draws it, otherwise the
    /// content view) to `<directory>/<name>.png`.
    @MainActor static func capture(_ name: String, section: String, state: String) -> Entry {
        guard let directory, let window, let content = window.contentView else {
            return Entry(file: name + ".png", section: section, state: state, size: .zero, ok: false)
        }
        let views = [content.superview, content].compactMap { $0 }
        for view in views {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: directory.appendingPathComponent(name + ".png"))
                return Entry(file: name + ".png", section: section, state: state, size: content.bounds.size, ok: true)
            } catch {
                continue
            }
        }
        return Entry(file: name + ".png", section: section, state: state, size: content.bounds.size, ok: false)
    }

    /// Writes `manifest.md` describing every capture, then quits the app.
    @MainActor static func finish(app: String, build: String, entries: [Entry]) {
        if let directory {
            var lines = [
                "# \(app) — CI window captures",
                "",
                "Build: \(build)",
                "",
                "Rendered by the running app from its own window (NSView.cacheDisplay), in the default",
                "appearance. These are the app's real views, not mock-ups. The window shadow, and on some",
                "systems the title bar, are drawn by the window server and may be missing.",
                "",
                "| File | Section | State | Window content size | Captured |",
                "|---|---|---|---|---|",
            ]
            for e in entries {
                lines.append("| \(e.file) | \(e.section) | \(e.state) | \(Int(e.size.width))×\(Int(e.size.height)) | \(e.ok ? "yes" : "FAILED") |")
            }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? lines.joined(separator: "\n").write(to: directory.appendingPathComponent("manifest.md"),
                                                     atomically: true, encoding: .utf8)
        }
        NSApp.terminate(nil)
        // If termination is held up (for example by a prompt), leave anyway: this is a CI run.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { exit(entries.allSatisfy(\.ok) ? 0 : 1) }
    }
}
