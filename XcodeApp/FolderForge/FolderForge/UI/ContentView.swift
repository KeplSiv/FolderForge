import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var state: AppState
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var confirming: BulkAction?

    /// Apply and Restore both fall back to "everything in the list" when nothing is
    /// selected. That's convenient for one or two folders and alarming for two hundred.
    private enum BulkAction: String, Identifiable {
        case apply, restore
        var id: String { rawValue }
        var verb: String { self == .apply ? "Apply to" : "Restore" }
    }

    var body: some View {
        // Three real columns rather than a detail pane with a fixed-width inspector glued on:
        // every divider is draggable, and the window can get small without clipping anything.
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(state: state)
                .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 340)
        } content: {
            PreviewPane(state: state)
                .navigationSplitViewColumnWidth(min: 300, ideal: 480)
        } detail: {
            InspectorView(state: state)
                .navigationSplitViewColumnWidth(min: 250, ideal: 296, max: 400)
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle("FolderForge")
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .sheet(isPresented: $state.showingSettings) {
            SettingsView(state: state)
        }
        .overlay(alignment: .top) { toastLayer }
        .overlay(alignment: .bottom) { githubStarLayer }
        .overlay { progressLayer }
        .sheet(isPresented: $state.showingAddSheet) {
            AddFoldersSheet(state: state)
        }
        .sheet(isPresented: $state.showingSmartStyle) {
            SmartStyleSheet(state: state)
        }
        .confirmationDialog(
            "\(confirming?.verb ?? "") all \(state.folders.count) folders?",
            isPresented: Binding(get: { confirming != nil },
                                 set: { if !$0 { confirming = nil } }),
            presenting: confirming
        ) { action in
            Button("\(action.verb) All \(state.folders.count)", role: action == .restore ? .destructive : nil) {
                if action == .apply { state.apply() } else { state.resetSelected() }
                confirming = nil
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: { action in
            Text(action == .apply
                 ? "Nothing is selected, so this writes the current design to every folder in the list."
                 : "Nothing is selected, so this restores the original icon on every folder in the list.")
        }
        .frame(minWidth: 720, minHeight: 480)
        .onReceive(NotificationCenter.default.publisher(for: .folderForgeOpenURLs)) { notification in
            let pending = AppDelegate.drainPendingOpenURLs()
            let urls = pending.isEmpty ? (notification.object as? [URL] ?? []) : pending
            guard !urls.isEmpty else { return }
            state.handleOpenURLs(urls)
        }
        .onChange(of: state.selection) { _, _ in
            state.syncStyleToSelection()
        }
        .onChange(of: state.toast) { _, toast in
            guard let toast else { return }
            Task {
                try? await Task.sleep(for: .seconds(toast.kind == .failure ? 6 : 2.6))
                if state.toast?.id == toast.id {
                    withAnimation(.easeOut(duration: 0.2)) { state.toast = nil }
                }
            }
        }
    }

    private var subtitle: String {
        let count = state.targets.count
        if count == 0 { return "No folders yet" }
        if state.selection.isEmpty { return "\(count) folder\(count == 1 ? "" : "s") - all" }
        return "\(count) selected"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { state.showingAddSheet = true } label: {
                Label("Add Folders", systemImage: "folder.badge.plus")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .help("Add folders by path, with depth and exclusions (⌘O)")
        }

        ToolbarItem {
            Button { state.refreshFinder() } label: {
                Text("Refresh Finder")
            }
            .help("Refresh Finder if macOS is still showing cached folder icons")
        }

        ToolbarItem {
            Button { state.showingSmartStyle = true } label: {
                Label("Smart Style", systemImage: "wand.and.stars")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .help("Style a folder tree from deterministic name rules")
        }

        ToolbarItem {
            Menu {
                Button("Export PNG…") { state.exportPNG() }
                Button("Export ICNS…") { state.exportICNS() }
                Divider()
                Button("Export Style File…") { state.exportStyleFile() }
                Button("Import Style File…") { state.importStyleFile() }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }

        ToolbarItem {
            Button {
                if state.actionHitsEverything { confirming = .restore } else { state.resetSelected() }
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward.circle")
            }
            .disabled(state.targets.isEmpty || state.isBatchRunning)
            .help("Put the original icons back")
        }

        ToolbarItem {
            Button {
                if state.actionHitsEverything { confirming = .apply } else { state.apply() }
            } label: {
                Label("Apply", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.targets.isEmpty || state.isBatchRunning)
            .help("Write this icon to the selected folders (⌘↩)")
        }


        ToolbarItem(placement: .primaryAction) {
            Button { state.showingSettings = true } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Open Preferences")
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var toastLayer: some View {
        if let toast = state.toast {
            ToastView(toast: toast)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: toast.id)
        }
    }

    @ViewBuilder
    private var progressLayer: some View {
        if let progress = state.applyProgress, progress.total > 1 {
            ZStack {
                Color.black.opacity(0.18).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView(value: Double(progress.done), total: Double(progress.total))
                        .frame(width: 240)
                    Text("\(progress.done) of \(progress.total)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Button("Stop") { state.cancelBatch() }
                        .controlSize(.small)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
            }
        }
    }

    @ViewBuilder
    private var githubStarLayer: some View {
        if state.showingGitHubStarPrompt {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue)

                Text("Enjoying FolderForge? Consider starring it on GitHub.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Button {
                    state.openGitHubRepository(completingPrompt: true)
                } label: {
                    Label("Star on GitHub", systemImage: "star.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button { state.snoozeGitHubStarPrompt() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remind me in 7 days")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.separator)
                    .frame(height: 0.5)
            }
            .shadow(color: .black.opacity(0.16), radius: 10, y: -2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
