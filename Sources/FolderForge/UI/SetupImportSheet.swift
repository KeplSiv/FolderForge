import SwiftUI

struct SetupImportSheet: View {
    @Bindable var state: AppState
    let archive: SetupArchive
    @Environment(\.dismiss) private var dismiss
    @State private var reapply = true

    private var matches: [(URL, SetupArchive.AppliedFolder)] { archive.matchingFolders() }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "square.and.arrow.down").foregroundStyle(.tint)
                Text("Import FolderForge Setup").font(.headline)
                Spacer()
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(archive.presets.count) presets · \(archive.themes.count) custom themes · \(archive.looks?.count ?? 0) saved looks · \(archive.ruleSets.count) rule sets · \(archive.watches?.count ?? 0) paused watches · \(archive.themeAssignments.count) workspace assignments")
                        .font(.subheadline)
                    Text("\(matches.count) of \(archive.appliedFolders.count) styled folders exist at the mapped paths on this Mac. Home-folder paths are adjusted to this Mac's account. Other paths stay unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Reapply styles to matching folders", isOn: $reapply)
                    Text("Original icon backups from the export are kept when the destination has no existing custom icon. Existing destination icons take precedence. Imported Smart Style watches are paused until you enable them.")
                        .font(.caption).foregroundStyle(.secondary)
                    Divider()
                    SectionLabel(text: "Matching folders", symbol: "folder.badge.checkmark")
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(matches.prefix(100).enumerated()), id: \.element.0) { _, pair in
                            HStack {
                                Text(pair.0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(pair.1.style.name).foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                    if matches.count > 100 {
                        Text("…and \(matches.count - 100) more")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { state.pendingSetupImport = nil; dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import Setup") {
                    state.importCompleteSetup(archive, reapply: reapply)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(state.isBatchRunning)
            }
            .padding(16)
        }
        .screenFittedDialog(width: 680, height: 620)
    }
}
