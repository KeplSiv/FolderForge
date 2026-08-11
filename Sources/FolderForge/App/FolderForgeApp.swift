import AppKit
import SwiftUI

struct FolderForgeApp: App {
    @State private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate()
                    state.loadCustomizedFolders()
                    state.resumeSmartRuleWatches()
                    state.handleOpenURLs(AppDelegate.drainPendingOpenURLs())
                }
        }
        // Comfortably fits the full layout, and small enough to open whole on a 13" display.
        .defaultSize(width: 1080, height: 700)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands { commands }

        Settings {
            SettingsView(state: state)
        }
    }

    @CommandsBuilder
    private var commands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Folders…") { state.showingAddSheet = true }
                .keyboardShortcut("o")
            Button("Browse for Folders…") { state.chooseFolders() }
                .keyboardShortcut("o", modifiers: [.command, .option])
            Button("Add Finder Selection") { state.importFinderSelection() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        // `replacing:` here would delete the system Undo/Redo items, which is how every text
        // field in the app gets ⌘Z. Add alongside them instead, on a shortcut of our own.
        CommandGroup(after: .undoRedo) {
            Button("Undo Last Apply") { state.undoLastApply() }
                .keyboardShortcut("z", modifiers: [.command, .option])
                .disabled(!state.canUndo)
        }

        CommandMenu("Folder") {
            Button("Smart Style…") { state.showingSmartStyle = true }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Divider()
            Button("Apply Icon") { state.apply() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(state.targets.isEmpty)
            Button("Restore Original") { state.resetSelected() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(state.targets.isEmpty)
            Divider()
            Button("Copy Style") { state.copyStyle() }
                .keyboardShortcut("c", modifiers: [.command, .option])
            Button("Paste Style") { state.pasteStyle() }
                .keyboardShortcut("v", modifiers: [.command, .option])
                .disabled(state.copiedStyle == nil)
            Divider()
            Button("Surprise Me") { state.randomize() }
                .keyboardShortcut("r")
            Button("Save as Preset") { state.saveCurrentAsPreset() }
                .keyboardShortcut("s")
            Divider()
            Button("Make Sample Folders on Desktop…") {
                let desktop = FileManager.default.urls(for: .desktopDirectory,
                                                       in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
                state.createSampleFolders(in: desktop)
            }
        }

        CommandGroup(replacing: .importExport) {
            Button("Export PNG…") { state.exportPNG() }
                .keyboardShortcut("e")
            Button("Export ICNS…") { state.exportICNS() }
            Divider()
            Button("Export Style…") { state.exportStyleFile() }
            Button("Import Style…") { state.importStyleFile() }
        }

        CommandGroup(replacing: .help) {
            Button("FolderForge Help") {
                NSWorkspace.shared.open(URL(string: "https://developer.apple.com/sf-symbols/")!)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var pendingOpenURLs: [URL] = []
    private let finderServices = FinderServicesProvider()

    static func drainPendingOpenURLs() -> [URL] {
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        return urls
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.servicesProvider = finderServices
        // Snapshots for folders that have since been deleted are dead weight — several MB each.
        BackupStore.pruneOrphans()
    }

    /// Folders dropped on the Dock icon land here.
    func application(_ application: NSApplication, open urls: [URL]) {
        Self.pendingOpenURLs.append(contentsOf: urls)
        NotificationCenter.default.post(name: .folderForgeOpenURLs, object: urls)
    }
}

final class FinderServicesProvider: NSObject {
    @objc func chooseFolderStyle(
        _ pasteboard: NSPasteboard,
        userData: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let folders = folderURLs(from: pasteboard)
        guard !folders.isEmpty else {
            errorPointer.pointee = "Select one or more folders in Finder first." as NSString
            return
        }

        switch chooseStyle(for: folders) {
        case .apply(let style):
            apply(style, to: folders, error: errorPointer)
        case .cancel:
            break
        }
    }

    @objc func restoreFolderIcons(
        _ pasteboard: NSPasteboard,
        userData: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let folders = folderURLs(from: pasteboard)
        guard !folders.isEmpty else {
            errorPointer.pointee = "Select one or more folders in Finder first." as NSString
            return
        }

        restore(folders, error: errorPointer)
    }

    private func restore(
        _ folders: [URL],
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let failures = IconApplier.resetBatch(folders).filter { !$0.succeeded }
        if let first = failures.first {
            errorPointer.pointee = serviceError(failures: failures.count, total: folders.count, first: first)
        }
    }

    private func apply(
        _ style: FolderStyle,
        to folders: [URL],
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard !folders.isEmpty else {
            errorPointer.pointee = "Select one or more folders in Finder first." as NSString
            return
        }

        let failures = IconApplier.applyBatch(style, to: folders).filter { !$0.succeeded }
        if let first = failures.first {
            errorPointer.pointee = serviceError(failures: failures.count, total: folders.count, first: first)
        }
    }

    private func chooseStyle(for folders: [URL]) -> FinderStyleChooserResult {
        if !Thread.isMainThread {
            return DispatchQueue.main.sync {
                chooseStyle(for: folders)
            }
        }

        let presets = PresetStore()
        var result = FinderStyleChooserResult.cancel
        var panel: NSPanel!
        let chooser = FinderStyleChooser(
            folders: folders,
            userStyles: presets.userPresets,
            builtInStyles: presets.builtIn,
            restoreOriginal: { [weak self] in
                self?.restoreErrorMessage(for: folders)
            }
        ) { choice in
            result = choice
            NSApp.stopModal()
            panel.orderOut(nil)
        }

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 610),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Choose Folder Style"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: chooser)
        panel.center()
        panel.standardWindowButton(.closeButton)?.target = NSApp
        panel.standardWindowButton(.closeButton)?.action = #selector(NSApplication.abortModal)

        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return result
    }

    private func restoreErrorMessage(for folders: [URL]) -> String? {
        let failures = IconApplier.resetBatch(folders).filter { !$0.succeeded }
        guard let first = failures.first else { return nil }
        return serviceError(failures: failures.count, total: folders.count, first: first) as String
    }

    private func folderURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        var seen = Set<String>()
        return urls.compactMap { url in
            let normalized = url.standardizedFileURL
            guard seen.insert(normalized.path).inserted,
                  (try? normalized.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { return nil }
            return normalized
        }
    }

    private func serviceError(
        failures: Int,
        total: Int,
        first: IconApplier.Outcome
    ) -> NSString {
        let detail = first.error?.localizedDescription ?? "Unknown error"
        return "\(failures) of \(total) folders failed. \(detail)" as NSString
    }
}

extension Notification.Name {
    static let folderForgeOpenURLs = Notification.Name("FolderForgeOpenURLs")
}

// MARK: - Settings

struct SettingsView: View {
    @Bindable var state: AppState
    @State private var finderSetupExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Close") {
                    state.showingSettings = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 14)

            Form {
                Section("Where things live") {
                    LabeledContent("Presets & backups") {
                        Button(BackupStore.supportDirectory.path
                            .replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                            NSWorkspace.shared.open(BackupStore.supportDirectory)
                        }
                        .buttonStyle(.link)
                    }
                }

                // These load automatically at launch; this is how you get them back after
                // removing some from the list.
                Section("Customized folders") {
                    let records = BackupStore.allApplied()
                    if records.isEmpty {
                        Text("None yet.").foregroundStyle(.secondary)
                    } else {
                        LabeledContent {
                            Button("Add Them All to the List") {
                                state.addFolders(records.map { URL(fileURLWithPath: $0.path) })
                            }
                        } label: {
                            Text("\(records.count) folder\(records.count == 1 ? "" : "s") currently carry a FolderForge icon.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            Section("Housekeeping") {
                Button("Clean Up Snapshots for Deleted Folders") {
                    let removed = BackupStore.pruneOrphans()
                    state.toast = Toast(
                        kind: .success,
                        message: removed == 0
                            ? "Nothing to clean up"
                            : "Cleared \(removed) orphaned snapshot\(removed == 1 ? "" : "s")")
                }
            }

            Section("Removed icons") {
                Text("When you restore a folder whose icon FolderForge didn't create, a copy "
                     + "is archived here first so it's never lost outright.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Open Archive") {
                    NSWorkspace.shared.open(BackupStore.removedDirectory)
                }
            }

            Section("Styles") {
                Button("Import Style File…") { state.importStyleFile() }
            }

            Section("Finder Style Chooser") {
                Text("Open a compact visual style picker directly from Finder. My Styles appear first, followed by every built-in style.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                DisclosureGroup(isExpanded: $finderSetupExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        setupStep(1, "Save any designs you want to My Styles. Built-in styles are included automatically.")
                        setupStep(2, "Open Keyboard Settings, click Keyboard Shortcuts…, then select Services › Files and Folders.")
                        setupStep(3, "Enable FolderForge: Choose Style… and FolderForge: Restore Original Icon.")
                        setupStep(4, "In Finder, right-click folders and choose Services › FolderForge: Choose Style…")

                        Button("Open Keyboard Settings") {
                            openKeyboardSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 2)
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Set Up Finder Shortcuts", systemImage: "keyboard.badge.ellipsis")
                        .fontWeight(.semibold)
                }

                LabeledContent("Available in Finder") {
                    Text("\(state.presets.userPresets.count) My Styles · \(state.presets.builtIn.count) built-in")
                        .foregroundStyle(.secondary)
                }

                Text("The chooser updates automatically when you save, rename, or remove a style. You can also assign a keyboard combination to either service in Keyboard Shortcuts.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 720, height: 650)
    }
    }

    private func setupStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(.blue, in: Circle())
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func openKeyboardSettings() {
        guard let keyboardSettings = URL(
            string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(keyboardSettings)
    }
}
