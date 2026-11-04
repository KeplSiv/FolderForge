import XCTest
@testable import FolderForge

final class WorkspaceThemeTests: XCTestCase {
    func testThemeSwapKeepsFolderArtworkAndUsesStableColors() {
        let url = URL(fileURLWithPath: "/tmp/Workspace/Design", isDirectory: true)
        var original = FolderStyle()
        original.overlay.kind = .symbol
        original.overlay.symbolName = "paintbrush.pointed.fill"
        original.textFontName = "Avenir"

        let coastal = WorkspaceTheme.all[0]
        let first = WorkspaceThemeEngine.style(for: url, theme: coastal, existing: original)
        let repeated = WorkspaceThemeEngine.style(for: url, theme: coastal, existing: first)
        let orchid = WorkspaceThemeEngine.style(for: url, theme: WorkspaceTheme.all[1], existing: first)

        XCTAssertEqual(first.tint, repeated.tint)
        XCTAssertEqual(first.overlay, original.overlay)
        XCTAssertEqual(orchid.overlay, original.overlay)
        XCTAssertEqual(orchid.textFontName, original.textFontName)
        XCTAssertNotEqual(first.tint, orchid.tint)
    }

    func testThemeUsesMatchingBuiltInSymbolOnNewFolder() {
        let url = URL(fileURLWithPath: "/tmp/Workspace/Photos", isDirectory: true)
        let style = WorkspaceThemeEngine.style(for: url, theme: WorkspaceTheme.all[0], existing: nil)
        XCTAssertEqual(style.overlay.symbolName, "photo.stack.fill")
    }

    func testThemeReplacesCoveringImageFillButKeepsImageOverlay() {
        let url = URL(fileURLWithPath: "/tmp/Workspace/Images", isDirectory: true)
        var original = FolderStyle()
        original.fill.kind = .image
        original.fill.imageData = Data([1, 2, 3])
        original.overlay.kind = .image
        original.overlay.imageData = Data([4, 5, 6])

        let themed = WorkspaceThemeEngine.style(for: url, theme: WorkspaceTheme.all[0], existing: original)
        XCTAssertEqual(themed.fill.kind, .color)
        XCTAssertNil(themed.fill.imageData)
        XCTAssertEqual(themed.overlay.imageData, original.overlay.imageData)
    }

    func testCoolorsURLCanBecomeAnEditableLocalTheme() {
        let theme = WorkspaceTheme.fromCoolorsURL("https://coolors.co/0a656a-0c9aa8-b8d6d8")
        XCTAssertEqual(theme?.colors.map(\.hex), ["#0A656A", "#0C9AA8", "#B8D6D8"])
        XCTAssertNil(WorkspaceTheme.fromCoolorsURL("https://example.com/0a656a-0c9aa8"))
        XCTAssertNil(WorkspaceTheme.fromCoolorsURL("https://coolors.co/not-a-palette"))
    }

    func testCustomThemeAndWorkspaceAssignmentSurviveReload() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("workspace-themes.json")
        let root = folder.appendingPathComponent("Project", isDirectory: true)
        let store = WorkspaceThemeStore(storeURL: file)
        let custom = store.saveTheme(WorkspaceTheme(id: UUID().uuidString, name: "My Palette",
                                                    colors: [RGBA(hex: "#123456")!, RGBA(hex: "#ABCDEF")!],
                                                    sourceURL: nil))
        store.assign(themeID: custom.id, root: root, depth: 3, includeRoot: true)

        let reloaded = WorkspaceThemeStore(storeURL: file)
        XCTAssertEqual(reloaded.customThemes.first?.colors, custom.colors)
        XCTAssertEqual(reloaded.assignment(for: root)?.themeID, custom.id)
        XCTAssertEqual(reloaded.assignment(for: root)?.depth, 3)
        reloaded.forgetAssignment(for: root)
        XCTAssertNil(WorkspaceThemeStore(storeURL: file).assignment(for: root))
    }

    func testSavedLookKeepsExactStylesAndOriginalIcons() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = folder.appendingPathComponent("Workspace", isDirectory: true)
        let styled = root.appendingPathComponent("Design", isDirectory: true)
        let original = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: styled, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var style = FolderStyle()
        style.tint = RGBA(hex: "#123456")!
        style.overlay.kind = .text
        style.overlay.text = "DS"
        let look = WorkspaceLook(name: " Before Changes ", root: root,
                                 pairs: [(styled, style), (original, nil)])
        let storeURL = folder.appendingPathComponent("themes.json")
        let store = WorkspaceThemeStore(storeURL: storeURL)
        store.saveLook(look)

        let reloaded = WorkspaceThemeStore(storeURL: storeURL)
        XCTAssertEqual(reloaded.looks.first?.name, "Before Changes")
        let pairs = try XCTUnwrap(reloaded.looks.first).pairs(in: root)
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].1?.overlay.text, "DS")
        XCTAssertNil(pairs[1].1)
    }

    func testSavedLookRejectsPathsOutsideWorkspace() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = folder.appendingPathComponent("Workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var look = WorkspaceLook(name: "Safe", root: root, pairs: [])
        look.entries = [.init(relativePath: "..", style: nil)]
        XCTAssertTrue(look.pairs(in: root).isEmpty)
    }

    func testSavedLookRejectsSymlinkEscapingWorkspace() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = folder.appendingPathComponent("Workspace", isDirectory: true)
        let outside = folder.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Shortcut"),
                                                   withDestinationURL: outside)
        var look = WorkspaceLook(name: "Imported", root: root, pairs: [])
        look.entries = [.init(relativePath: "Shortcut", style: FolderStyle())]
        XCTAssertTrue(look.pairs(in: root).isEmpty)
    }

    func testWorkspaceScanSkipsSymlinkedFolders() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = folder.appendingPathComponent("Workspace", isDirectory: true)
        let outside = folder.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Design"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside.appendingPathComponent("Nested"),
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Shortcut"),
                                                   withDestinationURL: outside)
        var options = FolderScanner.Options()
        options.depth = 2
        options.includeRoot = false
        let paths = FolderScanner.scan(root: root, options: options).folders.map(\.lastPathComponent)
        XCTAssertEqual(paths, ["Design"])
    }

    func testImportSkipsMalformedThemeAndItsAssignment() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = WorkspaceThemeStore(storeURL: folder.appendingPathComponent("themes.json"))
        let invalid = WorkspaceTheme(id: "invalid", name: "Empty", colors: [], sourceURL: nil)
        let workspace = folder.appendingPathComponent("Workspace", isDirectory: true)
        let assignment = WorkspaceThemeAssignment(rootPath: workspace.path, themeID: invalid.id,
                                                  depth: 1, includeRoot: false)
        store.importSetupThemes([invalid], assignments: [assignment], sourceHome: "/Users/old")
        XCTAssertTrue(store.customThemes.isEmpty)
        XCTAssertNil(store.assignment(for: workspace))
    }

    func testWorkspaceSwitchSkipsUnchangedAndUntrackedOriginalIcons() {
        let style = WorkspaceTheme.all[0].colors[0]
        var folderStyle = FolderStyle()
        folderStyle.tint = style
        XCTAssertFalse(WorkspaceStyleChange.needsWrite(target: nil, current: nil, hasCustomIcon: true))
        XCTAssertFalse(WorkspaceStyleChange.needsWrite(target: folderStyle, current: folderStyle,
                                                       hasCustomIcon: true))
        XCTAssertTrue(WorkspaceStyleChange.needsWrite(target: folderStyle, current: folderStyle,
                                                      hasCustomIcon: false))
        XCTAssertTrue(WorkspaceStyleChange.needsWrite(target: nil, current: folderStyle,
                                                      hasCustomIcon: true))
    }

    @MainActor
    func testApplyPaletteThenRestoreSavedWorkspaceLook() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderForgeIntegration-\(UUID().uuidString)", isDirectory: true)
        let styled = root.appendingPathComponent("Design", isDirectory: true)
        let unstyled = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: styled, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unstyled, withIntermediateDirectories: true)
        defer {
            try? IconApplier.reset(styled)
            try? IconApplier.reset(unstyled)
            try? FileManager.default.removeItem(at: root)
        }

        var original = FolderStyle()
        original.name = "My Design"
        original.tint = RGBA(hex: "#F03F81")!
        original.overlay.kind = .symbol
        original.overlay.symbolName = "paintbrush.fill"
        try IconApplier.apply(original, to: styled)
        let look = WorkspaceLook(name: "Before", root: root,
                                 pairs: [(styled, original), (unstyled, nil)])

        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let state = AppState(engagementDefaults: defaults)
        state.themes = WorkspaceThemeStore(storeURL: root.appendingPathComponent("themes.json"))
        let palette = WorkspaceTheme.all[0]
        state.applyWorkspaceTheme([(styled, WorkspaceThemeEngine.style(for: styled, theme: palette,
                                                                       existing: original)),
                                   (unstyled, WorkspaceThemeEngine.style(for: unstyled, theme: palette,
                                                                         existing: nil))],
                                  theme: palette, root: root, depth: 1, includeRoot: false)
        try await waitForBatch(state, containing: "Applied \(palette.name)")
        XCTAssertNotNil(BackupStore.appliedStyle(for: unstyled))
        XCTAssertTrue(IconApplier.hasCustomIcon(unstyled))

        state.toast = nil
        state.applyWorkspaceLook(look, to: root)
        try await waitForBatch(state, containing: "Applied Before")
        XCTAssertEqual(BackupStore.appliedStyle(for: styled), original)
        XCTAssertTrue(IconApplier.hasCustomIcon(styled))
        XCTAssertNil(BackupStore.appliedStyle(for: unstyled))
        XCTAssertFalse(IconApplier.hasCustomIcon(unstyled))
    }

    @MainActor
    private func waitForBatch(_ state: AppState, containing message: String) async throws {
        for _ in 0..<250 {
            if state.toast?.message.contains(message) == true { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(message); last toast: \(state.toast?.message ?? "none")")
    }
}
