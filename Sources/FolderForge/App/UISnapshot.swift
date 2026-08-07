import AppKit
import SwiftUI

/// Renders the app's own interface to a PNG without going through the window server.
///
/// This is a development aid: it makes layout regressions (clipped panes, columns that
/// refuse to compress, controls that overflow) checkable at any window size, including
/// sizes larger than the display, and without Screen Recording permission.
enum UISnapshot {

    enum Target: String {
        case main
        case sheet
    }

    static func capture(target: Target,
                        width: Int,
                        height: Int,
                        to url: URL,
                        folders: [URL] = [],
                        selectIndex: Int? = nil,
                        sheetPath: String = "") -> Bool {
        // Accessory, not regular: no Dock icon, no focus stealing. The window still gets a
        // real window-server backing store, which is what we capture from.
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let state = AppState()
        seed(state, folders: folders, selectIndex: selectIndex)

        let root: AnyView = switch target {
        case .main: AnyView(ContentView(state: state))
        case .sheet: AnyView(AddFoldersSheet(state: state, initialPath: sheetPath))
        }

        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(x: 0, y: 0, width: width, height: height)

        // SwiftUI needs a real window for materials, vibrancy and the split-view chrome to
        // resolve. It never gets ordered on screen.
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.appearance = NSAppearance(named: .darkAqua)
        window.title = "FolderForge"

        // Park it well off any physical display, then order it in. It never appears to the
        // user, but the window server composites it for real — so materials, vibrancy and
        // text all render, which `cacheDisplay(in:to:)` alone does not manage for a
        // layer-backed SwiftUI hierarchy.
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()

        // Let SwiftUI settle: GeometryReader-driven layout and ViewThatFits both need at
        // least one pass through the run loop before they report final sizes.
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))

        // Capturing our own window needs no Screen Recording permission.
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            FileHandle.standardError.write(Data("Window capture failed\n".utf8))
            return false
        }

        let rep = NSBitmapImageRep(cgImage: image)
        window.orderOut(nil)

        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            FileHandle.standardError.write(Data("Write failed: \(error)\n".utf8))
            return false
        }
    }

    /// Populates the state so the screenshot shows a realistic, populated interface rather
    /// than the empty placeholder.
    private static func seed(_ state: AppState, folders: [URL], selectIndex: Int?) {
        state.style = BuiltInPresets.all.first { $0.name == "Ocean" } ?? FolderStyle()

        if folders.isEmpty {
            let candidates = [
                "~/Documents", "~/Downloads", "~/Desktop", "~/Pictures", "~/Music",
            ].map { ($0 as NSString).expandingTildeInPath }

            let existing = candidates
                .filter { FileManager.default.fileExists(atPath: $0) }
                .map { URL(fileURLWithPath: $0) }
            state.addFolders(existing)
        } else {
            state.addFolders(folders)
        }

        if let selectIndex, state.folders.indices.contains(selectIndex) {
            state.selection = [state.folders[selectIndex].id]
            // The real app runs this from an onChange(of: selection); do the same here so
            // the snapshot exercises the same code path.
            state.syncStyleToSelection()
        } else {
            state.selection = []
        }
    }
}
