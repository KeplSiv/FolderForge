import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Bindable var state: AppState
    @State private var isTargeted = false
    @State private var quickPath = ""

    /// Folders imported recursively nest under their parent. Collapsed by exception:
    /// everything an import brought in is visible until the user closes it.
    @State private var collapsed: Set<UUID> = []

    private struct FolderNode: Identifiable {
        let item: FolderItem
        var children: [FolderNode] = []
        var id: UUID { item.id }
    }

    /// One line in the list: the folder plus the depth needed to draw its indent guides.
    private struct FlatRow: Identifiable {
        let item: FolderItem
        let level: Int
        let hasChildren: Bool
        var id: UUID { item.id }
    }

    private var folderTree: [FolderNode] {
        let items = state.folders
        var nodes = Dictionary(items.map { ($0.url, FolderNode(item: $0)) }, uniquingKeysWith: { a, _ in a })

        // Deepest first, so a child already carries its own subtree when it's attached.
        for item in items.sorted(by: { $0.url.pathComponents.count > $1.url.pathComponents.count }) {
            let parentURL = item.url.deletingLastPathComponent()
            guard var parent = nodes[parentURL], parentURL != item.url, let child = nodes[item.url] else { continue }
            parent.children.append(child)
            nodes[parentURL] = parent
        }

        let roots = nodes.values.filter { node in
            let parent = node.item.url.deletingLastPathComponent()
            return parent == node.item.url || nodes[parent] == nil
        }
        return sortForest(Array(roots))
    }

    private func toggleCollapsed(_ id: UUID) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    private func sortForest(_ nodes: [FolderNode]) -> [FolderNode] {
        nodes.sorted { $0.item.name.localizedCaseInsensitiveCompare($1.item.name) == .orderedAscending }
            .map { node in
                var node = node
                node.children = sortForest(node.children)
                return node
            }
    }

    private var visibleRows: [FlatRow] {
        var rows: [FlatRow] = []
        func walk(_ nodes: [FolderNode], level: Int) {
            for node in nodes {
                rows.append(FlatRow(item: node.item, level: level, hasChildren: !node.children.isEmpty))
                if !collapsed.contains(node.item.id) { walk(node.children, level: level + 1) }
            }
        }
        walk(folderTree, level: 0)
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            if state.folders.isEmpty {
                emptyState
            } else {
                folderList
            }
            Divider()
            pathBar
            bottomBar
        }
        .background(alignment: .center) {
            if isTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(6)
                    .transition(.opacity)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            state.addFolders(urls)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.12)) { isTargeted = targeted }
        }
    }

    // MARK: - Pieces

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: 4) {
                Text("Drop folders here")
                    .font(.system(size: 13, weight: .medium))
                Text("or type a path below")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Add by Path…") { state.showingAddSheet = true }
                    .controlSize(.small)
                    .padding(.top, 2)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var folderList: some View {
        List(selection: $state.selection) {
            Section {
                ForEach(visibleRows) { flat in
                    row(flat)
                        .tag(flat.item.id)
                        .contextMenu { contextMenu(for: flat.item) }
                }
            } header: {
                HStack(spacing: 4) {
                    Text("Folders")
                    Text("·").foregroundStyle(.quaternary)
                    Text("\(state.folders.count)").foregroundStyle(.tertiary)
                    Spacer()
                }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand { state.removeSelected() }
    }

    private func row(_ flat: FlatRow) -> some View {
        let item = flat.item
        return HStack(spacing: 8) {
            // The whole indent column is the hit target, not just the chevron glyph.
            HStack(spacing: 0) {
                // One vertical guide per ancestor level, so a recursive import reads as
                // a single connected group.
                ForEach(0..<flat.level, id: \.self) { _ in
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .padding(.trailing, 9)
                }

                Image(systemName: collapsed.contains(item.id) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                    .opacity(flat.hasChildren ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                guard flat.hasChildren else { return }
                withAnimation(.easeOut(duration: 0.12)) { toggleCollapsed(item.id) }
            }

            // Show what the folder looks like on disk right now.
            Image(nsImage: IconApplier.currentIcon(of: item.url))
                .resizable()
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                // Nested rows already show their location through the parent above them.
                if flat.level == 0 {
                    Text(item.parentPath)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer(minLength: 4)

            if item.isCustomized {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .help("Made in FolderForge with “\(item.appliedStyleName ?? "")”")
            } else if item.hasForeignIcon {
                Image(systemName: "app.badge")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .help("Already has a custom icon that FolderForge didn't make. "
                          + "Its settings can't be recovered, but the icon is preserved "
                          + "and Restore will bring it back.")
            }
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func contextMenu(for item: FolderItem) -> some View {
        Button("Reveal in Finder") { state.revealInFinder(item) }
        Button("Load This Folder's Style") {
            if let existing = BackupStore.appliedStyle(for: item.url) { state.style = existing }
        }
        .disabled(BackupStore.appliedStyle(for: item.url) == nil)
        Divider()
        Button("Restore Original Icon") {
            focusContextTarget(item)
            state.resetSelected()
        }
        Button("Remove from List") {
            focusContextTarget(item)
            state.removeSelected()
        }
    }

    /// A row-level context menu should respect an existing multi-selection when the clicked
    /// row is already part of it. If the user invoked the menu on an unselected row, treat
    /// that row as the target instead.
    private func focusContextTarget(_ item: FolderItem) {
        guard !state.selection.contains(item.id) else { return }
        state.selection = [item.id]
    }

    /// Type or paste a path and press return. `~` works, so do quoted and shell-escaped
    /// paths dragged in from a terminal.
    private var pathBar: some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)

            TextField("~/Projects", text: $quickPath)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .onSubmit {
                    if state.addPath(quickPath) { quickPath = "" }
                }

            if !quickPath.isEmpty {
                Button {
                    if state.addPath(quickPath) { quickPath = "" }
                } label: {
                    Image(systemName: "return").font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Add this path")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    private var bottomBar: some View {
        HStack(spacing: 2) {
            Button { state.showingAddSheet = true } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Add folders by path, with depth and exclusions…")

            Button { state.chooseFolders() } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Browse for folders…")

            Button { state.removeSelected() } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .disabled(state.selection.isEmpty)
            .help("Remove from list")

            Divider().frame(height: 14)

            Button { state.importFinderSelection() } label: {
                Image(systemName: "arrow.down.left.square")
            }
            .buttonStyle(.borderless)
            .help("Add whatever is selected in Finder")

            Spacer()

            if !state.selection.isEmpty {
                Text("\(state.selection.count) selected")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
