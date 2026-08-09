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

    static func drainPendingOpenURLs() -> [URL] {
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        return urls
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Snapshots for folders that have since been deleted are dead weight — several MB each.
        BackupStore.pruneOrphans()
    }

    /// Folders dropped on the Dock icon land here.
    func application(_ application: NSApplication, open urls: [URL]) {
        Self.pendingOpenURLs.append(contentsOf: urls)
        NotificationCenter.default.post(name: .folderForgeOpenURLs, object: urls)
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
        }
        .formStyle(.grouped)
        .frame(width: 720, height: 520)
    }
}
}
