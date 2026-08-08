import AppKit
import SwiftUI

/// Type or browse to a path, decide how deep to go and what to leave out, see the result
/// before committing.
struct AddFoldersSheet: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss

    /// Prefilled only by `--ui-snapshot`, so a screenshot can show a populated scan.
    var initialPath = ""

    @State private var pathText = ""
    @State private var excludeText = FolderScanner.Options.defaultExclusions.joined(separator: ", ")
    @State private var options = FolderScanner.Options()
    @State private var preview: FolderScanner.Result?
    @State private var scanning = false
    @State private var scanTask: Task<Void, Never>?
    @State private var completions: [URL] = []
    @State private var showCompletions = false
    @State private var finiteDepth = 1
    @State private var availableDepth = 0
    @State private var depthScanTruncated = false
    /// The preview tree starts fully expanded; this tracks what the user has closed.
    @State private var collapsedPreviewURLs: Set<URL> = []
    @FocusState private var pathFocused: Bool

    private struct PreviewNode: Identifiable {
        let url: URL
        var children: [PreviewNode] = []
        var id: URL { url }
    }

    private struct PreviewRow: Identifiable {
        let url: URL
        let level: Int
        let hasChildren: Bool
        var id: URL { url }

        var displayName: String {
            let name = url.lastPathComponent
            return name.isEmpty ? url.path : name
        }
    }

    private var resolvedRoot: URL? { FolderScanner.resolve(path: pathText) }
    private var finiteDepthBinding: Binding<Int> {
        Binding {
            options.depth == Int.max ? finiteDepth : options.depth
        } set: { newValue in
            let clamped = min(maxSelectableDepth, max(0, newValue))
            finiteDepth = clamped
            options.depth = clamped
        }
    }
    private var sliderDepthBinding: Binding<Double> {
        Binding {
            Double(finiteDepthBinding.wrappedValue)
        } set: { newValue in
            finiteDepthBinding.wrappedValue = Int(newValue.rounded())
        }
    }
    private var allLevelsBinding: Binding<Bool> {
        Binding {
            options.depth == Int.max
        } set: { enabled in
            if enabled {
                finiteDepth = options.depth == Int.max ? finiteDepth : options.depth
                options.depth = Int.max
            } else {
                options.depth = finiteDepth
            }
        }
    }
    private var maxSelectableDepth: Int { max(0, availableDepth) }

    private var rootExists: Bool {
        guard let root = resolvedRoot else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    locationSection
                    Divider()
                    depthSection
                    Divider()
                    filterSection
                }
                .padding(18)
            }

            Divider()
            footer
        }
        // Tall enough that the match preview sits above the fold rather than needing a scroll.
        .frame(width: 560, height: 780)
        .onAppear {
            if pathText.isEmpty {
                pathText = initialPath.isEmpty
                    ? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)
                        .first?.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                        ?? "~/Desktop"
                    : initialPath
            }
            rescan()
        }
        .onChange(of: options) { _, _ in rescan() }
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 17))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Add Folders").font(.system(size: 14, weight: .semibold))
                Text("Point at a location and pick what comes along")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if scanning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text("Looking…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else if let preview {
                Label {
                    Text(summary(preview)).font(.system(size: 11))
                } icon: {
                    Image(systemName: preview.truncated
                          ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(preview.truncated ? .orange : .green)
                }
            } else if !rootExists && !pathText.isEmpty {
                Label("That path doesn't exist", systemImage: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button("Add \(preview?.folders.count ?? 0)") {
                if let preview { state.addFolders(preview.folders) }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled((preview?.folders.isEmpty ?? true))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func summary(_ result: FolderScanner.Result) -> String {
        var parts = ["\(result.folders.count) folder\(result.folders.count == 1 ? "" : "s")"]
        if result.excludedCount > 0 { parts.append("\(result.excludedCount) skipped") }
        if result.truncated { parts.append("stopped at the \(options.maxResults) cap") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Location", symbol: "point.topleft.down.curvedto.point.bottomright.up")

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(rootExists ? Color.accentColor : .secondary)

                TextField("~/Projects  or  /Volumes/Work/Clients", text: $pathText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($pathFocused)
                    .onSubmit {
                        showCompletions = false
                        rescan()
                    }
                    .onChange(of: pathText) { _, new in
                        completions = FolderScanner.completions(for: new)
                        showCompletions = pathFocused && !completions.isEmpty
                        rescan()
                    }

                if !pathText.isEmpty {
                    Button { pathText = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }

                Button("Browse…") { browse() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(rootExists ? Color.accentColor.opacity(0.5) : .clear,
                                  lineWidth: 1)
            }

            if showCompletions, !completions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(completions, id: \.self) { url in
                        Button {
                            pathText = url.path
                                .replacingOccurrences(of: NSHomeDirectory(), with: "~") + "/"
                            completions = FolderScanner.completions(for: pathText)
                            rescan()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                Text(url.lastPathComponent).font(.system(size: 11))
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
            }

            // Fast jumps to the places people actually keep folders.
            HStack(spacing: 5) {
                ForEach(shortcuts, id: \.name) { shortcut in
                    Button(shortcut.name) {
                        pathText = shortcut.path
                        showCompletions = false
                        rescan()
                    }
                    .buttonStyle(.accessoryBar)
                    .font(.system(size: 10))
                }
            }
        }
    }

    private var shortcuts: [(name: String, path: String)] {
        [("Home", "~"), ("Desktop", "~/Desktop"), ("Documents", "~/Documents"),
         ("Downloads", "~/Downloads"), ("Developer", "~/Developer")]
            .filter { FileManager.default.fileExists(
                atPath: ($0.path as NSString).expandingTildeInPath) }
    }

    // MARK: - Depth

    private var depthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "How deep", symbol: "arrow.down.to.line")

            Toggle(isOn: allLevelsBinding) {
                Text("All levels").font(.system(size: 11))
            }
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(depthLabel(finiteDepthBinding.wrappedValue))
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Stepper("", value: finiteDepthBinding, in: 0...maxSelectableDepth)
                        .labelsHidden()
                        .disabled(options.depth == Int.max)
                }

                Slider(value: sliderDepthBinding, in: 0...Double(max(1, maxSelectableDepth)), step: 1)
                    .disabled(options.depth == Int.max || maxSelectableDepth == 0)

                Text(availableDepthLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .opacity(options.depth == Int.max ? 0.45 : 1)

            Toggle(isOn: $options.includeRoot) {
                Text("Include the folder itself, not just what's inside it")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)

            if options.depth == Int.max {
                Label("Unlimited depth on a large tree can pull in a lot. The \(options.maxResults)-folder cap still applies.",
                      systemImage: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if depthScanTruncated {
                Label("Depth range is based on the first \(options.maxResults) folders found.",
                      systemImage: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func depthLabel(_ depth: Int) -> String {
        switch depth {
        case 0: "This folder only"
        case 1: "1 level down"
        default: "\(depth) levels down"
        }
    }

    private var availableDepthLabel: String {
        if maxSelectableDepth == 0 { return "No nested folders found" }
        return "Available: \(depthLabel(maxSelectableDepth))"
    }

    // MARK: - Filters

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Leave out", symbol: "line.3.horizontal.decrease.circle")

            Toggle(isOn: $options.skipHidden) {
                Text("Hidden folders (names starting with a dot)").font(.system(size: 11))
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: $options.skipPackages) {
                Text("Bundles — apps, photo libraries, Xcode projects").font(.system(size: 11))
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: $options.skipSymlinks) {
                Text("Symlinked folders").font(.system(size: 11))
            }
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 4) {
                Text("Name patterns to skip")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextEditor(text: $excludeText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 58)
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    .onChange(of: excludeText) { _, new in
                        options.excludePatterns = FolderScanner.parsePatterns(new)
                    }

                HStack {
                    Text("Comma or newline separated. Shell wildcards work: `*.app`, `tmp*`.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Reset") {
                        excludeText = FolderScanner.Options.defaultExclusions
                            .joined(separator: ", ")
                        options.excludePatterns = FolderScanner.Options.defaultExclusions
                    }
                    .buttonStyle(.accessoryBar)
                    .font(.system(size: 10))
                }
            }

            if let preview, !preview.folders.isEmpty {
                matchesPreview(preview)
            }
        }
    }

    private func matchesPreview(_ result: FolderScanner.Result) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Will add").font(.system(size: 11)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    let rows = visibleRows(for: result.folders)
                    ForEach(rows.prefix(200)) { flat in
                        previewRow(flat)
                    }
                    if rows.count > 200 {
                        Text("…and \(rows.count - 200) more")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(8)
            }
            .frame(height: 220)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func previewRow(_ flat: PreviewRow) -> some View {
        HStack(spacing: 0) {
            // The whole indent column toggles, not just the chevron glyph.
            HStack(spacing: 0) {
                // One vertical guide per ancestor level so a recursive match reads as one group.
                ForEach(0..<flat.level, id: \.self) { _ in
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 1, height: 15)
                        .padding(.trailing, 9)
                }

                Image(systemName: collapsedPreviewURLs.contains(flat.url) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, alignment: .leading)
                    .opacity(flat.hasChildren ? 1 : 0)
            }
            .frame(height: 15)
            .contentShape(Rectangle())
            .onTapGesture {
                guard flat.hasChildren else { return }
                withAnimation(.easeOut(duration: 0.12)) { toggleExpanded(flat.url) }
            }

            Text(flat.displayName)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func toggleExpanded(_ url: URL) {
        if collapsedPreviewURLs.contains(url) {
            collapsedPreviewURLs.remove(url)
        } else {
            collapsedPreviewURLs.insert(url)
        }
    }

    /// Flattened, expanded-by-default view of the matched folders.
    private func visibleRows(for urls: [URL]) -> [PreviewRow] {
        var rows: [PreviewRow] = []
        func walk(_ nodes: [PreviewNode], level: Int) {
            for node in nodes {
                rows.append(PreviewRow(url: node.url, level: level, hasChildren: !node.children.isEmpty))
                if !collapsedPreviewURLs.contains(node.url) { walk(node.children, level: level + 1) }
            }
        }
        walk(buildTree(from: urls), level: 0)
        return rows
    }

    private func buildTree(from urls: [URL]) -> [PreviewNode] {
        var nodesByURL = Dictionary(urls.map { ($0, PreviewNode(url: $0)) }, uniquingKeysWith: { a, _ in a })

        // Deepest first: a child is fully built before it's attached to its parent.
        for url in urls.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            let parentURL = url.deletingLastPathComponent()
            guard parentURL != url, var parent = nodesByURL[parentURL], let child = nodesByURL[url] else { continue }
            parent.children.append(child)
            nodesByURL[parentURL] = parent
        }

        let roots = nodesByURL.values.filter { node in
            let parent = node.url.deletingLastPathComponent()
            return parent == node.url || nodesByURL[parent] == nil
        }
        return sortTree(Array(roots))
    }

    private func sortTree(_ nodes: [PreviewNode]) -> [PreviewNode] {
        nodes.sorted {
            $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending
        }
            .map { node in
                var node = node
                node.children = sortTree(node.children)
                return node
            }
    }

    // MARK: - Actions

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if let root = resolvedRoot, rootExists { panel.directoryURL = root }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pathText = url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        showCompletions = false
        rescan()
    }

    /// Scans off the main thread, debounced.
    ///
    /// Typing a single `/` with "All levels" selected walks the entire disk. Doing that
    /// synchronously on every keystroke froze the window until it finished.
    private func rescan() {
        scanTask?.cancel()

        guard let root = resolvedRoot, rootExists else {
            preview = nil
            availableDepth = 0
            depthScanTruncated = false
            scanning = false
            return
        }

        var current = options
        current.excludePatterns = FolderScanner.parsePatterns(excludeText)
        scanning = true

        scanTask = Task {
            // Let the typing settle before touching the filesystem.
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }

            let scan = await Task.detached(priority: .userInitiated) {
                var depthProbe = current
                depthProbe.depth = Int.max
                depthProbe.includeRoot = false
                let result = FolderScanner.scan(root: root, options: current)
                let available = FolderScanner.scan(root: root, options: depthProbe)
                return (result: result, depthProbe: available)
            }.value

            guard !Task.isCancelled else { return }
            preview = scan.result
            availableDepth = scan.depthProbe.deepestLevel
            depthScanTruncated = scan.depthProbe.truncated
            if options.depth != Int.max, options.depth > availableDepth {
                options.depth = availableDepth
            }
            finiteDepth = options.depth == Int.max ? min(finiteDepth, availableDepth) : options.depth
            scanning = false
        }
    }
}
