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
        case smart
        case themes
        case themesPalette
        case themeEditor
        case setupImport
    }

    static func capture(target: Target,
                        width: Int,
                        height: Int,
                        to url: URL,
                        folders: [URL] = [],
                        selectIndex: Int? = nil,
                        inspectorTab: AppState.InspectorTab? = nil,
                        overlayKind: OverlayKind? = nil,
                        styleOverride: FolderStyle? = nil,
                        iconURL: URL? = nil,
                        sheetPath: String = "",
                        demo: Bool = false) -> Bool {
        // Accessory, not regular: no Dock icon, no focus stealing. The window still gets a
        // real window-server backing store, which is what we capture from.
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let state = AppState()
        seed(state, folders: folders, selectIndex: selectIndex)
        var demoStoreURL: URL?
        var demoRulesDirectory: URL?
        if demo, let demoRoot = folders.first {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("folderforge-demo-themes-\(UUID().uuidString).json")
            demoStoreURL = url
            state.themes = WorkspaceThemeStore(storeURL: url)
            let rulesDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("folderforge-demo-rules-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: rulesDirectory,
                                                     withIntermediateDirectories: true)
            demoRulesDirectory = rulesDirectory
            state.smartRules = SmartRuleStore(storageDirectory: rulesDirectory)
            var options = FolderScanner.Options()
            options.depth = 1
            let scanned = FolderScanner.scan(root: demoRoot, options: options).folders
                .filter { $0.standardizedFileURL != demoRoot.standardizedFileURL }
            let pairs: [(URL, FolderStyle?)] = scanned.enumerated().map { index, folder in
                (folder, index == scanned.count - 1 ? nil :
                    WorkspaceThemeEngine.style(for: folder, theme: WorkspaceTheme.all[1],
                                               existing: nil))
            }
            state.themes.saveLook(WorkspaceLook(name: "Studio Set", root: demoRoot, pairs: pairs))
        }
        defer {
            if let demoStoreURL { try? FileManager.default.removeItem(at: demoStoreURL) }
            if let demoRulesDirectory { try? FileManager.default.removeItem(at: demoRulesDirectory) }
        }
        if let styleOverride { state.style = styleOverride }
        if let inspectorTab { state.inspectorTab = inspectorTab }
        if let overlayKind { state.style.overlay.kind = overlayKind }
        if let iconURL, let data = IconImport.embeddedData(from: iconURL) {
            state.style.fill.kind = .icns
            state.style.fill.fullIconData = data
            state.style.fill.imageData = nil
            state.inspectorTab = .fill
        }

        let root: AnyView = switch target {
        case .main: AnyView(ContentView(state: state))
        case .sheet: AnyView(AddFoldersSheet(state: state, initialPath: sheetPath))
        case .smart: AnyView(SmartStyleSheet(state: state, initialPath: sheetPath))
        case .themes: AnyView(WorkspaceThemesSheet(
            state: state, initialRootPath: demo ? folders.first?.path : nil
        ))
        case .themesPalette: AnyView(WorkspaceThemesSheet(
            state: state, initialThemeID: "orchid",
            initialRootPath: demo ? folders.first?.path : nil
        ))
        case .themeEditor: AnyView(WorkspaceThemeEditor(
            theme: WorkspaceTheme(id: "snapshot-theme", name: "My Coastal Theme",
                                  colors: WorkspaceTheme.all[0].colors, sourceURL: nil),
            onSave: { _ in }
        ))
        case .setupImport:
            AnyView(SetupImportSheet(state: state, archive: SetupArchive(
                sourceHome: NSHomeDirectory(),
                presets: Array(BuiltInPresets.all.prefix(4)),
                themes: [WorkspaceTheme.all[0]],
                themeAssignments: [],
                ruleSets: [],
                activeRuleSetID: nil,
                watches: [],
                appliedFolders: state.folders.prefix(3).map {
                    SetupArchive.AppliedFolder(path: $0.url.path,
                                               style: WorkspaceThemeEngine.style(
                                                for: $0.url, theme: WorkspaceTheme.all[0],
                                                existing: nil),
                                               originalIconData: nil)
                }
            )))
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
