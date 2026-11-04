import SwiftUI

struct WorkspaceThemeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkspaceTheme
    @State private var hexDrafts: [String]
    var onSave: (WorkspaceTheme) -> Void

    init(theme: WorkspaceTheme, onSave: @escaping (WorkspaceTheme) -> Void) {
        _draft = State(initialValue: theme)
        _hexDrafts = State(initialValue: theme.colors.map(\.hex))
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Theme").font(.headline)
                Spacer()
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Theme name", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                    Text("Choose 2–10 colors. Paste a hex value or use the color picker.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(draft.colors.indices, id: \.self) { index in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(width: 18)
                            ColorPicker("", selection: Binding(
                                get: { draft.colors[index].color },
                                set: {
                                    draft.colors[index] = RGBA($0)
                                    hexDrafts[index] = draft.colors[index].hex
                                    draft.sourceURL = nil
                                }
                            ), supportsOpacity: false)
                            .labelsHidden()
                            TextField("#RRGGBB", text: Binding(
                                get: { hexDrafts[index] },
                                set: {
                                    hexDrafts[index] = $0
                                    if let color = RGBA(hex: $0) {
                                        draft.colors[index] = color
                                        draft.sourceURL = nil
                                    }
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            Button {
                                draft.colors.remove(at: index)
                                hexDrafts.remove(at: index)
                                draft.sourceURL = nil
                            } label: { Image(systemName: "minus.circle") }
                            .disabled(draft.colors.count <= 2)
                            .help("Remove color")
                        }
                    }
                    Button {
                        draft.colors.append(RGBA(hex: "#6E85A8")!)
                        hexDrafts.append("#6E85A8")
                        draft.sourceURL = nil
                    } label: { Label("Add Color", systemImage: "plus") }
                    .disabled(draft.colors.count >= 10)
                }
                .padding(16)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Theme") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          hexDrafts.contains { RGBA(hex: $0) == nil })
            }
            .padding(16)
        }
        .screenFittedDialog(width: 460, height: 550)
    }
}
