import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FolderItem: Identifiable, Hashable {
    let id: UUID
    var url: URL
    var appliedStyleName: String?
    /// There's an `Icon\r` on disk, whoever put it there.
    var hasCustomIconOnDisk: Bool
    /// Bumped whenever the folder's icon changes on disk. Without it, re-applying a design
    /// that happens to have the same name leaves every field identical, so SwiftUI sees no
    /// change and the row keeps drawing the old thumbnail.
    var iconRevision = 0

    init(url: URL) {
        self.id = UUID()
        self.url = url.standardizedFileURL
        self.appliedStyleName = BackupStore.appliedStyle(for: url)?.name
        self.hasCustomIconOnDisk = IconApplier.hasCustomIcon(url)
    }

    /// A custom icon that FolderForge didn't make. We have its pixels but none of the
    /// settings that produced them, so there is nothing to load into the editor.
    var hasForeignIcon: Bool { appliedStyleName == nil && hasCustomIconOnDisk }

    var name: String { url.lastPathComponent }
    var parentPath: String {
        url.deletingLastPathComponent().path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
    var isCustomized: Bool { appliedStyleName != nil }
}

struct Toast: Identifiable, Equatable {
    enum Kind { case success, failure, info }
    let id = UUID()
    var kind: Kind
    var message: String
    var detail: String?
}

@Observable
final class AppState {

    // MARK: - Stored state

    var folders: [FolderItem] = []
    var selection: Set<FolderItem.ID> = []

    /// The style currently being edited.
    var style = FolderStyle()

    var presets = PresetStore()
    var quickPresets = QuickPresetStore()
    var smartRules = SmartRuleStore()

    var previewScale: Double = 1.0
    var showingOriginal = false
    var toast: Toast?
    var applyProgress: (done: Int, total: Int)?
    var inspectorTab: InspectorTab = .color
    var showingAddSheet = false
    var showingSettings = false
    var showingSmartStyle = false

    enum InspectorTab: String, CaseIterable, Identifiable {
        case color, fill, icon, tune
        var id: String { rawValue }
        var title: String {
            switch self {
            case .color: "Color"
            case .fill: "Fill"
            case .icon: "Icon"
            case .tune: "Tune"
            }
        }
        var symbol: String {
            switch self {
            case .color: "paintpalette"
            case .fill: "rectangle.on.rectangle"
            case .icon: "star"
            case .tune: "slider.horizontal.3"
            }
        }
    }

    // MARK: - Undo of the last batch

    private struct AppliedSnapshot {
        var urls: [URL]
        var previous: [URL: FolderStyle?]
        var styleName: String
    }
    private var lastApply: AppliedSnapshot?
    var canUndo: Bool { lastApply != nil }

    // MARK: - Derived

    var selectedFolders: [FolderItem] {
        folders.filter { selection.contains($0.id) }
    }

    /// What the preview should show — the selection, or a stand-in when nothing is picked.
    var previewName: String {
        switch selectedFolders.count {
        case 0: folders.isEmpty ? "Untitled Folder" : "\(folders.count) folders"
        case 1: selectedFolders[0].name
        default: "\(selectedFolders.count) folders"
        }
    }

    var targets: [FolderItem] {
        selectedFolders.isEmpty ? folders : selectedFolders
    }

    // MARK: - Folder management

    /// Every folder that already carries a FolderForge icon belongs in the list from the
    /// start — there's nothing to opt into, so no button asks for it.
    func loadCustomizedFolders() {
        let urls = BackupStore.allApplied().map { URL(fileURLWithPath: $0.path) }
        guard !urls.isEmpty else { return }
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            let standardized = url.standardizedFileURL
            guard !folders.contains(where: { $0.url == standardized }) else { continue }
            folders.append(FolderItem(url: standardized))
        }
        // Loading isn't a user pick, so leave the selection (and the edited style) alone.
    }

    func addFolders(_ urls: [URL]) {
        var added = 0
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            let standardized = url.standardizedFileURL
            guard !folders.contains(where: { $0.url == standardized }) else { continue }
            folders.append(FolderItem(url: standardized))
            added += 1
        }
        if added > 0 {
            // Selecting them is enough — the selection observer adopts whatever design the
            // folders already carry, and keeps `styleAtLoad` honest while doing it.
            selection = Set(folders.suffix(added).map(\.id))
            syncStyleToSelection()
        } else if !urls.isEmpty {
            toast = Toast(kind: .info, message: "Already in the list")
        }
    }

    /// Adds a typed path. Returns false if it doesn't resolve to a real directory.
    @discardableResult
    func addPath(_ raw: String) -> Bool {
        guard let url = FolderScanner.resolve(path: raw) else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            toast = Toast(kind: .failure,
                          message: "No folder at that path",
                          detail: url.path)
            return false
        }
        addFolders([url])
        return true
    }

    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders to customize"
        guard panel.runModal() == .OK else { return }
        addFolders(panel.urls)
    }

    func removeSelected() {
        folders.removeAll { selection.contains($0.id) }
        selection = []
    }

    func revealInFinder(_ item: FolderItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Pulls whatever is highlighted in Finder right now. Needs Automation permission, which
    /// macOS prompts for the first time.
    func importFinderSelection() {
        let source = """
        tell application "Finder"
            set output to ""
            repeat with anItem in (get selection)
                set output to output & (POSIX path of (anItem as alias)) & linefeed
            end repeat
            return output
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return }
        let result = script.executeAndReturnError(&error)

        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Finder wouldn't answer."
            toast = Toast(kind: .failure,
                          message: "Couldn't read the Finder selection",
                          detail: message + " Allow FolderForge to control Finder in System Settings › Privacy & Security › Automation.")
            return
        }

        let paths = (result.stringValue ?? "")
            .split(separator: "\n")
            .map { URL(fileURLWithPath: String($0)) }

        guard !paths.isEmpty else {
            toast = Toast(kind: .info, message: "Nothing selected in Finder")
            return
        }
        addFolders(paths)
    }

    func refreshFinder() {
        if !targets.isEmpty {
            for item in targets {
                NSWorkspace.shared.noteFileSystemChanged(item.url.path)
                NSWorkspace.shared.noteFileSystemChanged(item.url.deletingLastPathComponent().path)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Finder"]
        do {
            try process.run()
            process.waitUntilExit()
            toast = process.terminationStatus == 0
                ? Toast(kind: .success, message: "Finder refreshed")
                : Toast(kind: .failure, message: "Couldn't refresh Finder")
        } catch {
            toast = Toast(kind: .failure, message: "Couldn't refresh Finder",
                          detail: error.localizedDescription)
        }
    }

    /// Creates a sandbox folder full of examples so you can see the result immediately.
    func createSampleFolders(in parent: URL) {
        let root = parent.appendingPathComponent("FolderForge Samples", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var created: [URL] = []
        for preset in BuiltInPresets.all.prefix(8) {
            let url = root.appendingPathComponent(preset.name, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            _ = try? IconApplier.apply(preset, to: url)
            created.append(url)
        }

        addFolders(created)
        NSWorkspace.shared.activateFileViewerSelecting(created)
        toast = Toast(kind: .success,
                      message: "Made \(created.count) sample folders",
                      detail: root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
    }

    // MARK: - Applying

    /// Set when a batch is running so the progress sheet can offer a way out.
    private var batchTask: Task<Void, Never>?
    var isBatchRunning: Bool { batchTask != nil }

    func cancelBatch() {
        batchTask?.cancel()
    }

    /// True when Apply/Restore would hit everything in the list because nothing is selected.
    /// The UI asks first in that case — it's the one action here that's hard to undo in bulk.
    var actionHitsEverything: Bool {
        selection.isEmpty && folders.count > 1
    }

    func apply() {
        let items = targets
        guard !items.isEmpty else {
            toast = Toast(kind: .info, message: "Add a folder first")
            return
        }
        guard batchTask == nil else { return }

        var previous: [URL: FolderStyle?] = [:]
        for item in items { previous[item.url] = BackupStore.appliedStyle(for: item.url) }

        let design = style
        applyProgress = (0, items.count)

        // Run as a task that yields between folders. Done synchronously, a 2000-folder batch
        // would block the main run loop start to finish — the progress bar would never draw
        // a single frame and the app would look hung.
        batchTask = Task { @MainActor in
            var outcomes: [IconApplier.Outcome] = []
            var cancelled = false

            for (index, item) in items.enumerated() {
                if Task.isCancelled { cancelled = true; break }
                do {
                    try IconApplier.apply(design, to: item.url)
                    outcomes.append(IconApplier.Outcome(url: item.url, error: nil))
                } catch {
                    outcomes.append(IconApplier.Outcome(url: item.url, error: error))
                }
                applyProgress = (index + 1, items.count)
                // Hand the run loop a slot so SwiftUI can actually paint the progress.
                await Task.yield()
            }

            applyProgress = nil
            batchTask = nil

            lastApply = AppliedSnapshot(urls: outcomes.filter(\.succeeded).map(\.url),
                                        previous: previous,
                                        styleName: design.name)
            refreshBadges()
            // Applied work isn't unsaved work — switching folders can now adopt freely.
            styleAtLoad = design

            let failed = outcomes.filter { !$0.succeeded }
            if cancelled {
                toast = Toast(kind: .info,
                              message: "Stopped after \(outcomes.count) of \(items.count)")
            } else if failed.isEmpty {
                toast = Toast(kind: .success,
                              message: items.count == 1
                                  ? "Applied to \(items[0].name)"
                                  : "Applied to \(items.count) folders")
            } else {
                toast = Toast(kind: .failure,
                              message: "\(failed.count) of \(items.count) failed",
                              detail: failed.first?.error?.localizedDescription)
            }
        }
    }

    func resetSelected() {
        let items = targets
        guard !items.isEmpty else { return }
        guard batchTask == nil else { return }

        applyProgress = (0, items.count)

        batchTask = Task { @MainActor in
            var outcomes: [IconApplier.Outcome] = []
            var cancelled = false

            for (index, item) in items.enumerated() {
                if Task.isCancelled { cancelled = true; break }
                do {
                    try IconApplier.reset(item.url)
                    outcomes.append(IconApplier.Outcome(url: item.url, error: nil))
                } catch {
                    outcomes.append(IconApplier.Outcome(url: item.url, error: error))
                }
                applyProgress = (index + 1, items.count)
                await Task.yield()
            }

            applyProgress = nil
            batchTask = nil
            refreshBadges()
            syncStyleToSelection(preservingDirtyStyle: false)

            let failed = outcomes.filter { !$0.succeeded }
            if cancelled {
                toast = Toast(kind: .info,
                              message: "Stopped after \(outcomes.count) of \(items.count)")
            } else if failed.isEmpty {
                toast = Toast(kind: .success,
                              message: "Restored \(items.count) folder\(items.count == 1 ? "" : "s")")
            } else {
                toast = Toast(kind: .failure,
                              message: "\(failed.count) couldn't be restored",
                              detail: failed.first?.error?.localizedDescription)
            }
        }
    }

    func undoLastApply() {
        guard let snapshot = lastApply else { return }
        for url in snapshot.urls {
            if let previousStyle = snapshot.previous[url] ?? nil {
                _ = try? IconApplier.apply(previousStyle, to: url)
            } else {
                try? IconApplier.reset(url)
            }
        }
        lastApply = nil
        refreshBadges()
        toast = Toast(kind: .success, message: "Undid “\(snapshot.styleName)”")
    }

    /// Apply explicit mapped suggestions: a list of (folderURL, style) pairs.
    func applyMappedSuggestions(_ pairs: [(URL, FolderStyle)]) async {
        guard !pairs.isEmpty else { return }
        guard batchTask == nil else { return }

        var previous: [URL: FolderStyle?] = [:]
        for pair in pairs { previous[pair.0] = BackupStore.appliedStyle(for: pair.0) }
        applyProgress = (0, pairs.count)

        batchTask = Task { @MainActor in
            var outcomes: [IconApplier.Outcome] = []
            var cancelled = false

            for (index, pair) in pairs.enumerated() {
                if Task.isCancelled { cancelled = true; break }
                do {
                    try IconApplier.apply(pair.1, to: pair.0)
                    outcomes.append(IconApplier.Outcome(url: pair.0, error: nil))
                } catch {
                    outcomes.append(IconApplier.Outcome(url: pair.0, error: error))
                }
                applyProgress = (index + 1, pairs.count)
                await Task.yield()
            }

            applyProgress = nil
            batchTask = nil
            refreshBadges()
            lastApply = AppliedSnapshot(urls: outcomes.filter(\.succeeded).map(\.url),
                                        previous: previous,
                                        styleName: "Smart Style")

            let failed = outcomes.filter { !$0.succeeded }
            if cancelled {
                toast = Toast(kind: .info,
                              message: "Stopped after \(outcomes.count) of \(pairs.count)")
            } else if failed.isEmpty {
                toast = Toast(kind: .success,
                              message: "Applied mapped presets to \(pairs.count) folders")
            } else {
                toast = Toast(kind: .failure,
                              message: "\(failed.count) of \(pairs.count) failed",
                              detail: failed.first?.error?.localizedDescription)
            }
        }
    }

    func previewSmartStyle(root: URL, options: FolderScanner.Options,
                           ruleSetID: UUID? = nil) -> SmartStylePreview {
        SmartStyleEngine.preview(root: root, options: options,
                                 rules: smartRules.resolvedRules(for: ruleSetID),
                                 presets: presets.builtIn,
                                 customPresets: presets.userPresets)
    }

    func applySmartStyle(_ preview: SmartStylePreview) {
        guard !preview.matches.isEmpty else {
            toast = Toast(kind: .info, message: "No matching folders to style")
            return
        }
        addFolders(preview.scannedURLs)
        Task { await applyMappedSuggestions(preview.matches.map { ($0.url, $0.style) }) }
    }

    /// Starts opt-in FSEvents roots after the app has finished creating its UI. A watch only
    /// applies an unambiguous matching rule; it never resets an unmatched folder.
    func resumeSmartRuleWatches() {
        smartRules.resumeWatches { [weak self] watch in
            self?.reevaluateSmartRuleWatch(watch)
        }
    }

    private func reevaluateSmartRuleWatch(_ watch: SmartRuleWatch) {
        guard watch.reapplyOnChanges, batchTask == nil else { return }
        Task { @MainActor in
            var options = FolderScanner.Options()
            options.depth = watch.scanDepth
            options.includeRoot = watch.includeRoot
            let preview = previewSmartStyle(root: watch.rootURL, options: options,
                                            ruleSetID: watch.ruleSetID)
            let pairs = preview.matches
                .filter { !$0.hasConflict }
                .filter { BackupStore.appliedStyle(for: $0.url)?.matchesAppearance(of: $0.style) != true }
                .map { ($0.url, $0.style) }
            guard !pairs.isEmpty else { return }
            addFolders(preview.scannedURLs)
            await applyMappedSuggestions(pairs)
        }
    }

    private func refreshBadges() {
        for index in folders.indices {
            folders[index].appliedStyleName =
                BackupStore.appliedStyle(for: folders[index].url)?.name
            folders[index].hasCustomIconOnDisk =
                IconApplier.hasCustomIcon(folders[index].url)
            folders[index].iconRevision &+= 1
        }
    }

    // MARK: - Icons we didn't make

    /// The selected folder when it carries a custom icon from another tool.
    var foreignIconFolder: FolderItem? {
        guard selectedFolders.count == 1,
              let item = selectedFolders.first,
              item.hasForeignIcon else { return nil }
        return item
    }

    /// Show the real icon off disk instead of a made-up plain folder — right up until the
    /// user starts designing, at which point the preview switches to their work.
    var previewShowsExistingIcon: Bool {
        foreignIconFolder != nil && !styleIsDirty
    }

    // MARK: - Style helpers

    /// The working style as it was when we last adopted it from the selection. Anything the
    /// user changes afterwards counts as unsaved work.
    private var styleAtLoad: FolderStyle?

    var styleIsDirty: Bool {
        guard let styleAtLoad else { return false }
        return !style.matchesAppearance(of: styleAtLoad)
    }

    /// A bare stock folder — what a folder with no custom icon actually looks like.
    static func plainStyle(base: BaseIconKind = .generic) -> FolderStyle {
        var plain = FolderStyle()
        plain.name = "Plain"
        plain.baseIcon = base
        plain.tintStrength = 0
        plain.overlay.kind = .none
        return plain
    }

    /// Makes the editor show whatever the selected folder actually is: its saved design if
    /// it has one, a plain folder if it doesn't.
    ///
    /// Unsaved work isn't thrown away — it goes to the style clipboard so ⌥⌘V puts it back.
    func syncStyleToSelection(preservingDirtyStyle: Bool = true) {
        let selected = selectedFolders
        guard !selected.isEmpty else { return }

        let applied: [FolderStyle?] = selected.map { BackupStore.appliedStyle(for: $0.url) }

        // Written out longhand on purpose: the terse `applied.first ?? nil` plus a
        // `matchesAppearance` closure sent the type checker into a 2-minute stall.
        let shared: FolderStyle? = {
            guard let head = applied.first, let head else { return nil }
            for entry in applied {
                guard let entry, entry.matchesAppearance(of: head) else { return nil }
            }
            return head
        }()

        var noneCustomized = true
        for entry in applied where entry != nil { noneCustomized = false }

        let target: FolderStyle
        if let shared {
            // Every selected folder carries the same saved design — show it.
            target = shared
        } else if noneCustomized {
            // Nothing customized here. Don't clobber a design in progress: adding a second
            // plain folder to the selection is how you apply one design to both.
            if preservingDirtyStyle && styleIsDirty { return }
            target = Self.plainStyle(base: style.baseIcon)
        } else {
            // Mixed selection — no single truth to show, so leave the design alone.
            return
        }

        guard !target.matchesAppearance(of: style) else {
            styleAtLoad = style
            return
        }

        if preservingDirtyStyle && styleIsDirty {
            copiedStyle = style
            toast = Toast(kind: .info,
                          message: "Your unsaved design was kept",
                          detail: "Press ⌥⌘V to put it on this folder.")
        }

        var copy = target
        copy.id = style.id
        style = copy
        styleAtLoad = copy
    }

    // MARK: - Style clipboard

    var copiedStyle: FolderStyle?

    func copyStyle() {
        copiedStyle = style
        toast = Toast(kind: .success, message: "Style copied")
    }

    func pasteStyle() {
        guard let copiedStyle else {
            toast = Toast(kind: .info, message: "No style copied yet")
            return
        }
        var copy = copiedStyle
        copy.id = style.id
        style = copy
    }

    func load(preset: FolderStyle) {
        var copy = preset
        copy.id = style.id
        style = copy
    }

    func saveCurrentAsPreset() {
        let name = style.name == "Untitled" || style.name.isEmpty
            ? suggestedName()
            : style.name
        presets.add(style, named: name)
        toast = Toast(kind: .success, message: "Saved “\(name)”")
    }

    private func suggestedName() -> String {
        switch style.overlay.kind {
        case .symbol:
            style.overlay.symbolName
                .split(separator: ".").first.map(String.init)?.capitalized ?? "Custom"
        case .emoji: style.overlay.emoji
        case .text: style.overlay.text
        default: "Custom"
        }
    }

    func randomize() {
        var next = FolderStyle()
        next.name = "Surprise"

        let swatches = Palettes.groups.flatMap(\.swatches)
        next.tint = swatches.randomElement()?.color ?? next.tint

        if Bool.random() {
            next.gradientEnabled = true
            next.tintSecondary = swatches.randomElement()?.color ?? next.tintSecondary
            next.gradientAngle = Double(Int.random(in: 0...11) * 30)
        }
        if let symbol = SymbolCatalog.allSymbols.randomElement() {
            next.overlay.kind = .symbol
            next.overlay.symbolName = symbol
        }
        next.finish = [.engraved, .engraved, .tinted, .raised].randomElement() ?? .engraved
        next.overlayScale = Double.random(in: 0.34...0.48)
        next.baseIcon = style.baseIcon
        style = next
    }

    // MARK: - Export

    func exportPNG() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(style.name.isEmpty ? "Folder" : style.name).png"
        panel.message = "Save the icon as a 1024×1024 PNG"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let cg = IconRenderer.render(style, pixels: 1024),
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        else {
            toast = Toast(kind: .failure, message: "Couldn't render the icon")
            return
        }
        do {
            try data.write(to: url)
            toast = Toast(kind: .success, message: "Exported \(url.lastPathComponent)")
        } catch {
            toast = Toast(kind: .failure, message: "Export failed",
                          detail: error.localizedDescription)
        }
    }

    func exportICNS() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "icns") ?? .data]
        panel.nameFieldStringValue = "\(style.name.isEmpty ? "Folder" : style.name).icns"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderForge-\(UUID().uuidString).iconset")
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let variants: [(Int, String)] = [
            (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
        ]
        for (pixels, name) in variants {
            guard let cg = IconRenderer.render(style, pixels: pixels),
                  let data = NSBitmapImageRep(cgImage: cg)
                      .representation(using: .png, properties: [:]) else { continue }
            try? data.write(to: staging.appendingPathComponent(name))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", staging.path, "-o", url.path]
        do {
            try process.run()
            process.waitUntilExit()
            toast = process.terminationStatus == 0
                ? Toast(kind: .success, message: "Exported \(url.lastPathComponent)")
                : Toast(kind: .failure, message: "iconutil failed")
        } catch {
            toast = Toast(kind: .failure, message: "Export failed",
                          detail: error.localizedDescription)
        }
    }

    func exportStyleFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: PresetStore.fileExtension) ?? .json]
        panel.nameFieldStringValue = "\(style.name.isEmpty ? "Style" : style.name).\(PresetStore.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = presets.exportData(for: [style]) else { return }
        try? data.write(to: url)
        toast = Toast(kind: .success, message: "Exported \(url.lastPathComponent)")
    }

    func importStyleFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: PresetStore.fileExtension) ?? .json, .json,
        ]
        guard panel.runModal() == .OK else { return }

        let count = panel.urls.reduce(0) { $0 + presets.importStyles(from: $1) }
        toast = count > 0
            ? Toast(kind: .success, message: "Imported \(count) style\(count == 1 ? "" : "s")")
            : Toast(kind: .failure, message: "Nothing readable in that file")
    }

    @discardableResult
    func importIconFile(_ url: URL) -> Bool {
        guard let png = IconImport.pngData(from: url) else {
            toast = Toast(kind: .failure,
                          message: "Couldn't read that image or icon",
                          detail: url.lastPathComponent)
            return false
        }
        if IconImport.isICNS(url) {
            style.fill.kind = .icns
            style.fill.fullIconData = png
            style.fill.imageData = nil
        } else {
            style.fill.kind = .image
            style.fill.imageData = png
            style.fill.fullIconData = nil
            style.fillScale = 1.0
            style.fillOpacity = 1.0
            style.fillOffsetX = 0
            style.fillOffsetY = 0
            style.fillRotation = 0
        }
        inspectorTab = .fill
        toast = Toast(kind: .success, message: "Imported \(url.lastPathComponent)")
        return true
    }

    func handleOpenURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        var folderURLs: [URL] = []
        var importedStyles = 0
        var importedIcons = 0
        var unreadable: URL?

        for url in urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                folderURLs.append(url)
                continue
            }

            let ext = url.pathExtension.lowercased()
            if ext == PresetStore.fileExtension || ext == "json" {
                let count = presets.importStyles(from: url)
                if count > 0 {
                    importedStyles += count
                    continue
                }
            }

            if IconImport.canImport(url), importIconFile(url) {
                importedIcons += 1
            } else {
                unreadable = unreadable ?? url
            }
        }

        if !folderURLs.isEmpty { addFolders(folderURLs) }

        if importedIcons > 0 || importedStyles > 0 || !folderURLs.isEmpty {
            var pieces: [String] = []
            if !folderURLs.isEmpty {
                pieces.append("\(folderURLs.count) folder\(folderURLs.count == 1 ? "" : "s")")
            }
            if importedIcons > 0 {
                pieces.append("\(importedIcons) icon\(importedIcons == 1 ? "" : "s")")
            }
            if importedStyles > 0 {
                pieces.append("\(importedStyles) style\(importedStyles == 1 ? "" : "s")")
            }
            toast = Toast(kind: .success, message: "Imported " + pieces.joined(separator: ", "))
        } else if let unreadable {
            toast = Toast(kind: .failure,
                          message: "Nothing readable in that file",
                          detail: unreadable.lastPathComponent)
        }
    }
}
