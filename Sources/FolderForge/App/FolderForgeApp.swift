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
    @objc func applyQuickPreset(
        _ pasteboard: NSPasteboard,
        userData: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let slot = Int(userData),
              let style = QuickPresetStore().style(at: slot)
        else {
            errorPointer.pointee = "Quick Preset \(userData) is not configured. Set it in FolderForge Settings." as NSString
            return
        }

        apply(style, to: folderURLs(from: pasteboard), error: errorPointer)
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

            Section("Finder Quick Presets") {
                Text("Right-click selected folders in Finder, open Services, then choose a FolderForge quick preset. Each slot keeps its own snapshot of the style.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                ForEach(state.quickPresets.slots) { slot in
                    HStack(spacing: 10) {
                        Text(String(format: "%02d", slot.id))
                            .font(.system(.body, design: .monospaced, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)

                        if let selected = slot.style {
                            FolderIconView(style: selected, side: 28)
                                .frame(width: 28, height: 28)
                            Text(selected.name)
                                .lineLimit(1)
                            Spacer()
                        } else {
                            Image(systemName: "square.dashed")
                                .foregroundStyle(.tertiary)
                                .frame(width: 28, height: 28)
                            Text("Not configured")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        Menu("Choose Style") {
                            Section("Built-in") {
                                ForEach(state.presets.builtIn) { preset in
                                    Button(preset.name) {
                                        state.quickPresets.assign(preset, to: slot.id)
                                    }
                                }
                            }
                            if !state.presets.userPresets.isEmpty {
                                Section("My Styles") {
                                    ForEach(state.presets.userPresets) { preset in
                                        Button(preset.name) {
                                            state.quickPresets.assign(preset, to: slot.id)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(width: 112)

                        Button {
                            state.quickPresets.clear(slot.id)
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(slot.style == nil)
                        .help("Clear this slot")
                    }
                }

                Text("You can assign keyboard shortcuts to these Services in System Settings › Keyboard › Keyboard Shortcuts.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 720, height: 650)
    }
}
}
