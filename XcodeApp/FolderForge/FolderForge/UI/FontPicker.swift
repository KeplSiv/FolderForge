import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FontPickerSheet: View {
    @Binding var selection: String?
    var reportError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var fontNames = FontCatalog.availableFontNames()

    private var filteredFonts: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fontNames }
        return fontNames.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose a Text Font")
                        .font(.title3.weight(.semibold))
                    Text("Installed and imported fonts render only the text on your folder icon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Import Font…", action: importFont)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            List(selection: Binding(
                get: { selection ?? "__system__" },
                set: { selection = $0 == "__system__" ? nil : $0 }
            )) {
                fontRow(name: nil)
                    .tag("__system__")

                ForEach(filteredFonts, id: \.self) { name in
                    fontRow(name: name)
                        .tag(name)
                }
            }
            .searchable(text: $query, placement: .toolbar, prompt: "Search fonts")
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    private func fontRow(name: String?) -> some View {
        HStack {
            Text(name ?? "System Default")
                .font(name.map { .custom($0, size: 15) } ?? .system(size: 15))
            Spacer()
            if selection == name {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selection = name }
        .padding(.vertical, 3)
    }

    private func importFont() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = FontCatalog.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.message = "Choose a TrueType or OpenType font to use for folder text"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let imported = try FontCatalog.importFont(from: url)
            fontNames = FontCatalog.availableFontNames()
            selection = imported.first
            query = ""
        } catch {
            reportError(error.localizedDescription)
        }
    }
}
