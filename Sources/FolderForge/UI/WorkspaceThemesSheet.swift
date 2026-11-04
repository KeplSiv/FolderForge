import AppKit
import SwiftUI

struct WorkspaceThemesSheet: View {
    private enum Choice: Equatable {
        case current
        case palette(String)
        case look(UUID)
    }

    @Bindable var state: AppState
    var initialThemeID: String? = nil
    var initialRootPath: String? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var rootPath = ""
    @State private var theme = WorkspaceTheme.all[0]
    @State private var choice: Choice = .current
    @State private var depth = 2
    @State private var allLevels = false
    @State private var includeRoot = false
    @State private var preview: [(url: URL, style: FolderStyle?)] = []
    @State private var scannedURLs: [URL] = []
    @State private var truncated = false
    @State private var scanning = false
    @State private var scanTask: Task<Void, Never>?
    @State private var editingTheme: WorkspaceTheme?
    @State private var importingCoolors = false
    @State private var importURL = ""
    @State private var importError = false
    @State private var savingLook = false
    @State private var lookName = ""

    private var root: URL? { FolderScanner.resolve(path: rootPath) }
    private var rootExists: Bool {
        guard let root else { return false }
        var directory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: root.path, isDirectory: &directory) && directory.boolValue
    }
    private var assignment: WorkspaceThemeAssignment? {
        root.flatMap { state.themes.assignment(for: $0) }
    }
    private var selectedLook: WorkspaceLook? {
        guard case .look(let id) = choice else { return nil }
        return state.themes.looks.first { $0.id == id }
    }
    private var savedLooks: [WorkspaceLook] { state.themes.looks }
    private var currentStyledCount: Int {
        scannedURLs.reduce(0) { count, url in
            count + (BackupStore.appliedStyle(for: url) == nil ? 0 : 1)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "paintpalette.fill").foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workspace Themes").font(.headline)
                    Text("Preview a palette across a whole folder tree, then switch it in one batch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionLabel(text: "Workspace", symbol: "folder")
                    HStack {
                        TextField("Choose a folder tree", text: $rootPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse…", action: browse)
                    }
                    if !state.themes.assignments.isEmpty {
                        Menu("Assigned Workspaces") {
                            ForEach(state.themes.assignments) { saved in
                                Button(saved.rootPath.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                                    rootPath = saved.rootPath
                                    includeRoot = saved.includeRoot
                                    allLevels = saved.depth == Int.max
                                    if !allLevels { depth = saved.depth }
                                    if let assigned = state.themes.allThemes.first(where: { $0.id == saved.themeID }) {
                                        theme = assigned
                                    }
                                    choice = .current
                                }
                            }
                        }
                        .font(.caption)
                    }
                    if let assignment,
                       let assigned = state.themes.allThemes.first(where: { $0.id == assignment.themeID }) {
                        HStack {
                            Text("Last applied palette: \(assigned.name). Current shows the folder styles now.")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Forget") {
                                if let root { state.themes.forgetAssignment(for: root) }
                            }
                            .font(.caption)
                            .help("Forget this workspace assignment without changing its current icons")
                        }
                    }
                    HStack {
                        Toggle("Include workspace folder", isOn: $includeRoot)
                        Spacer()
                        Toggle("All levels", isOn: $allLevels)
                        if !allLevels {
                            Stepper("\(depth) levels", value: $depth, in: 1...20)
                                .fixedSize()
                        }
                    }
                    .font(.caption)

                    Divider()
                    HStack {
                        SectionLabel(text: "Current & Saved Looks", symbol: "clock.arrow.circlepath")
                        Spacer()
                        Menu("Quick Switch") {
                            if !savedLooks.isEmpty {
                                Section("Saved Looks") {
                                    ForEach(savedLooks) { saved in
                                        Button("\(saved.name) · \(URL(fileURLWithPath: saved.rootPath).lastPathComponent)") {
                                            quickSwitch(to: saved)
                                        }
                                    }
                                }
                            }
                            Section("Theme Palettes") {
                                ForEach(state.themes.allThemes) { palette in
                                    Button(palette.name) { quickSwitch(to: palette) }
                                }
                            }
                        }
                        .disabled(state.isBatchRunning || !rootExists)
                        Button("Save Current…") {
                            lookName = "My Workspace"
                            savingLook = true
                        }
                        .disabled(!rootExists || scanning)
                        .help("Save the styles currently applied to this workspace, including original icons")
                    }
                    Text("Current uses FolderForge's records: \(currentStyledCount) styled · \(max(0, scannedURLs.count - currentStyledCount)) unstyled. Finder may show older cached icons.")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        HStack {
                            Button {
                                choice = .current
                            } label: {
                                Label("Current", systemImage: "checkmark.circle")
                            }
                            .buttonStyle(.bordered)
                            .tint(choice == .current ? .accentColor : nil)
                            ForEach(savedLooks) { saved in
                                Button {
                                    choice = .look(saved.id)
                                    rootPath = saved.rootPath
                                    includeRoot = saved.entries.contains { $0.relativePath.isEmpty }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(saved.name)
                                        Text(URL(fileURLWithPath: saved.rootPath).lastPathComponent)
                                            .font(.caption2).foregroundStyle(.secondary)
                                        Text("\(saved.styledCount) styled · \(saved.originalCount) unstyled")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                    .buttonStyle(.bordered)
                                    .tint(choice == .look(saved.id) ? .accentColor : nil)
                                    .contextMenu {
                                        Button("Delete Saved Look", role: .destructive) {
                                            state.themes.deleteLook(saved.id)
                                            if choice == .look(saved.id) { choice = .current }
                                        }
                                    }
                            }
                        }
                    }
                    .font(.caption)

                    Divider()
                    HStack {
                        SectionLabel(text: "Theme Presets", symbol: "paintpalette")
                        Spacer()
                        Menu {
                            Button("Create Theme…") { createTheme() }
                            Button("Import Coolors URL…") { importURL = ""; importingCoolors = true }
                            Divider()
                            Button(theme.isBuiltIn ? "Customize a Copy…" : "Edit Theme…") {
                                editingTheme = editableCopy(of: theme)
                            }
                            .disabled(choice == .current || selectedLook != nil)
                            Button("Duplicate Theme…") {
                                editingTheme = editableCopy(of: theme, alwaysCopy: true)
                            }
                            .disabled(choice == .current || selectedLook != nil)
                            if !theme.isBuiltIn {
                                Divider()
                                Button("Delete Theme", role: .destructive) {
                                    state.themes.deleteTheme(theme.id)
                                    theme = WorkspaceTheme.all[0]
                                    choice = .current
                                }
                                .disabled(choice == .current || selectedLook != nil)
                            }
                        } label: {
                            Label("Manage", systemImage: "ellipsis.circle")
                        }
                        .controlSize(.small)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 9) {
                        ForEach(state.themes.allThemes) { choice in
                            Button { theme = choice; self.choice = .palette(choice.id) } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(spacing: 0) {
                                        ForEach(choice.colors.indices, id: \.self) { index in
                                            choice.colors[index].color
                                        }
                                    }
                                    .frame(height: 26)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                    Text(choice.name).font(.caption.weight(.semibold))
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(self.choice == .palette(choice.id) ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.07),
                                            in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(self.choice == .palette(choice.id) ? Color.accentColor : .clear))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if case .palette = choice, let sourceURL = theme.sourceURL {
                        Link("Palette on Coolors", destination: sourceURL)
                            .font(.caption)
                    }

                    Divider()
                    HStack {
                        SectionLabel(text: "Preview", symbol: "eye")
                        Spacer()
                        if scanning { ProgressView().controlSize(.small) }
                        Text("\(preview.count) folders" + (truncated ? " · scan capped at 2,000" : ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(choice == .current
                         ? "Unstyled means FolderForge has no applied style recorded for that folder."
                         : selectedLook.map { "This saved look contains \($0.styledCount) styled and \($0.originalCount) unstyled folders. Undo Last Apply reverses a switch." }
                           ?? "Original icons are backed up; Undo Last Apply reverses a switch.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !rootExists {
                        Text("Choose an existing folder to preview a theme.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        LazyVStack(spacing: 5) {
                            ForEach(Array(preview.prefix(100).enumerated()), id: \.element.url) { _, entry in
                                HStack(spacing: 8) {
                                    Circle().fill(entry.style?.tint.color ?? Color.secondary).frame(width: 13, height: 13)
                                    Text(entry.url.lastPathComponent).lineLimit(1)
                                    Spacer()
                                    Text(entry.style?.tint.hex ?? "Unstyled").foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                            if preview.count > 100 {
                                Text("…and \(preview.count - 100) more")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(16)
            }
            Divider()
            HStack {
                Text("Only local folders are changed.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if choice == .current {
                    Text("Showing current look")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                Button(selectedLook.map { "Switch to \($0.name)" } ?? "Apply \(theme.name) to \(preview.count)") {
                    guard let root else { return }
                    if let selectedLook {
                        state.applyWorkspaceLook(selectedLook, to: root)
                    } else {
                        state.applyWorkspaceTheme(preview.compactMap { pair in
                            pair.style.map { (pair.url, $0) }
                        }, theme: theme, root: root,
                        depth: allLevels ? Int.max : depth,
                        includeRoot: includeRoot)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(scanning || preview.isEmpty || state.isBatchRunning)
                }
            }
            .padding(16)
        }
        .screenFittedDialog(width: 680, height: 760)
        .sheet(item: $editingTheme) { draft in
            WorkspaceThemeEditor(theme: draft) { saved in
                theme = state.themes.saveTheme(saved)
                choice = .palette(theme.id)
            }
        }
        .alert("Import Coolors Palette", isPresented: $importingCoolors) {
            TextField("https://coolors.co/hex-hex-hex", text: $importURL)
            Button("Import") { importCoolors() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste a Coolors palette URL. Colors are read from the URL and saved locally.")
        }
        .alert("Invalid Coolors URL", isPresented: $importError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Use a coolors.co palette link containing 2–10 six-digit hex colors.")
        }
        .alert("Save Current Look", isPresented: $savingLook) {
            TextField("Look name", text: $lookName)
            Button("Save") { saveCurrentLook() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save the exact styles currently applied to these workspace folders.")
        }
        .onAppear {
            rootPath = initialRootPath ?? state.selectedFolders.first?.url.path
                ?? state.themes.assignments.first?.rootPath
                ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path
                ?? NSHomeDirectory()
            includeRoot = state.selectedFolders.count == 1
            if let root, let assigned = state.themes.assignment(for: root) {
                includeRoot = assigned.includeRoot
                allLevels = assigned.depth == Int.max
                if !allLevels { depth = assigned.depth }
                if let saved = state.themes.allThemes.first(where: { $0.id == assigned.themeID }) {
                    theme = saved
                }
            }
            if let initialThemeID,
               let initialTheme = state.themes.allThemes.first(where: { $0.id == initialThemeID }) {
                theme = initialTheme
                choice = .palette(initialThemeID)
            } else {
                choice = .current
            }
            rescan()
        }
        .onDisappear { scanTask?.cancel() }
        .onChange(of: rootPath) { _, newPath in
            if initialThemeID == nil,
               selectedLook?.rootPath != URL(fileURLWithPath: newPath).standardizedFileURL.path {
                choice = .current
            }
            rescan()
        }
        .onChange(of: theme) { _, _ in rescan() }
        .onChange(of: choice) { _, _ in rescan() }
        .onChange(of: depth) { _, _ in rescan() }
        .onChange(of: allLevels) { _, _ in rescan() }
        .onChange(of: includeRoot) { _, _ in rescan() }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Workspace"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        SandboxAccessStore.remember(url)
        rootPath = url.path
    }

    private func createTheme() {
        editingTheme = WorkspaceTheme(id: UUID().uuidString, name: "My Theme",
                                      colors: [RGBA(hex: "#2E9BFF")!, RGBA(hex: "#8E5BFF")!],
                                      sourceURL: nil)
    }

    private func editableCopy(of source: WorkspaceTheme, alwaysCopy: Bool = false) -> WorkspaceTheme {
        var copy = source
        if source.isBuiltIn || alwaysCopy {
            copy.id = UUID().uuidString
            copy.name += " Copy"
        }
        return copy
    }

    private func importCoolors() {
        guard let parsed = WorkspaceTheme.fromCoolorsURL(importURL) else {
            importError = true
            return
        }
        theme = state.themes.saveTheme(parsed)
        choice = .palette(theme.id)
    }

    private func saveCurrentLook() {
        guard let root, rootExists else { return }
        var options = FolderScanner.Options()
        options.depth = allLevels ? Int.max : depth
        options.includeRoot = includeRoot
        let urls = FolderScanner.scan(root: root, options: options).folders
        guard !urls.isEmpty else { return }
        let look = WorkspaceLook(name: lookName, root: root,
                                 pairs: urls.map { ($0, BackupStore.appliedStyle(for: $0)) })
        _ = state.themes.saveLook(look)
        choice = .look(look.id)
    }

    private func quickSwitch(to look: WorkspaceLook) {
        let targetRoot = URL(fileURLWithPath: look.rootPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: targetRoot.path) else { return }
        state.applyWorkspaceLook(look, to: targetRoot)
        dismiss()
    }

    private func quickSwitch(to palette: WorkspaceTheme) {
        guard let root, rootExists else { return }
        var options = FolderScanner.Options()
        options.depth = allLevels ? Int.max : depth
        options.includeRoot = includeRoot
        let result = FolderScanner.scan(root: root, options: options)
        let pairs = result.folders.map { url in
            (url, WorkspaceThemeEngine.style(for: url, theme: palette,
                                             existing: BackupStore.appliedStyle(for: url)))
        }
        guard !pairs.isEmpty else { return }
        state.applyWorkspaceTheme(pairs, theme: palette, root: root,
                                  depth: options.depth, includeRoot: includeRoot)
        dismiss()
    }

    private func rescan() {
        scanTask?.cancel()
        guard let root, rootExists else {
            preview = []
            scannedURLs = []
            truncated = false
            scanning = false
            return
        }
        var options = FolderScanner.Options()
        options.depth = allLevels ? Int.max : depth
        options.includeRoot = includeRoot
        let selectedTheme = theme
        let selectedChoice = choice
        scanning = true
        if case .look = selectedChoice, let selectedLook {
            let pairs = selectedLook.pairs(in: root)
            preview = pairs.map { (url: $0.0, style: $0.1) }
            scannedURLs = pairs.map(\.0)
            truncated = false
            scanning = false
            return
        }
        scanTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) {
                FolderScanner.scan(root: root, options: options)
            }.value
            guard !Task.isCancelled else { return }
            scannedURLs = result.folders
            preview = result.folders.map { url in
                let existing = BackupStore.appliedStyle(for: url)
                if selectedChoice == .current { return (url, existing) }
                return (url, WorkspaceThemeEngine.style(for: url, theme: selectedTheme,
                                                        existing: existing))
            }
            truncated = result.truncated
            scanning = false
        }
    }
}
