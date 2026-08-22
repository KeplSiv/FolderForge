import AppKit
import SwiftUI

enum FinderStyleChooserResult {
    case apply(FolderStyle)
    case cancel
}

struct FinderStyleChooser: View {
    let folders: [URL]
    let userStyles: [FolderStyle]
    let builtInStyles: [FolderStyle]
    let restoreOriginal: () -> String?
    let complete: (FinderStyleChooserResult) -> Void

    @State private var selectedStyle: FolderStyle?
    @State private var searchText = ""
    @State private var restoreError: String?
    @State private var previewRevision = 0

    init(
        folders: [URL],
        userStyles: [FolderStyle],
        builtInStyles: [FolderStyle],
        restoreOriginal: @escaping () -> String?,
        complete: @escaping (FinderStyleChooserResult) -> Void
    ) {
        self.folders = folders
        self.userStyles = userStyles
        self.builtInStyles = builtInStyles
        self.restoreOriginal = restoreOriginal
        self.complete = complete
        _selectedStyle = State(initialValue: userStyles.first ?? builtInStyles.first)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    preview

                    if !filteredUserStyles.isEmpty {
                        styleSection("My Styles", styles: filteredUserStyles)
                    }

                    styleSection("Built-in", styles: filteredBuiltInStyles)
                }
                .padding(22)
            }

            Divider()

            footer
        }
        .frame(width: 720, height: 610)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Could Not Restore Icon", isPresented: Binding(
            get: { restoreError != nil },
            set: { if !$0 { restoreError = nil } }
        )) {
            Button("OK") { restoreError = nil }
        } message: {
            Text(restoreError ?? "Unknown error")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: folders[0].path))
                .resizable()
                .interpolation(.high)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(folderTitle)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(folderSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            TextField("Search styles", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)
        }
        .padding(20)
    }

    private var preview: some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))

                if let selectedStyle {
                    FolderIconView(style: selectedStyle, side: 132)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: folders[0].path))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 132, height: 132)
                        .id(previewRevision)
                }
            }
            .frame(width: 190, height: 170)

            VStack(alignment: .leading, spacing: 8) {
                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(selectedStyle?.name ?? "Current folder icon")
                    .font(.title2.weight(.semibold))
                Text("Choose a style below, then apply it to \(selectionDescription).")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

    private func styleSection(_ title: String, styles: [FolderStyle]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(title))
                    .font(.headline)
                Text("\(styles.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 104, maximum: 118), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(styles) { style in
                    styleCard(style)
                }
            }
        }
    }

    private func styleCard(_ style: FolderStyle) -> some View {
        let selected = selectedStyle?.id == style.id
        return Button {
            selectedStyle = style
        } label: {
            VStack(spacing: 7) {
                FolderIconView(style: style, side: 68)
                Text(style.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.name) style")
    }

    private var footer: some View {
        HStack {
            Button("Restore Original") {
                if let error = restoreOriginal() {
                    restoreError = error
                } else {
                    selectedStyle = nil
                    previewRevision += 1
                }
            }

            Spacer()

            Button("Cancel") {
                complete(.cancel)
            }
            .keyboardShortcut(.cancelAction)

            Button("Apply Style") {
                guard let selectedStyle else { return }
                complete(.apply(selectedStyle))
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedStyle == nil)
        }
        .padding(18)
    }

    private var filteredUserStyles: [FolderStyle] {
        filtered(userStyles)
    }

    private var filteredBuiltInStyles: [FolderStyle] {
        filtered(builtInStyles)
    }

    private func filtered(_ styles: [FolderStyle]) -> [FolderStyle] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return styles }
        return styles.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var folderTitle: String {
        folders.count == 1 ? folders[0].lastPathComponent : "\(folders.count) folders selected"
    }

    private var folderSubtitle: String {
        if folders.count == 1 {
            return folders[0].deletingLastPathComponent().path
                .replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
        return folders.map(\.lastPathComponent).prefix(3).joined(separator: ", ")
            + (folders.count > 3 ? " and \(folders.count - 3) more" : "")
    }

    private var selectionDescription: String {
        folders.count == 1 ? "this folder" : "all \(folders.count) selected folders"
    }
}
