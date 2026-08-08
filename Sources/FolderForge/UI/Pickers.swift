import AppKit
import SwiftUI

/// Searchable, category-browsable SF Symbol picker.
struct SymbolPicker: View {
    @Binding var selection: String
    @State private var query = ""
    @State private var category: String = SymbolCatalog.categories.first?.name ?? ""

    private var results: [String] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return SymbolCatalog.categories.first { $0.name == category }?.symbols ?? []
        }
        return SymbolCatalog.search(query)
    }

    private let columns = [GridItem(.adaptive(minimum: 30, maximum: 30), spacing: 5)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                TextField("Search symbols", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))

            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(SymbolCatalog.categories) { item in
                            Button { category = item.name } label: {
                                Text(item.name)
                                    .font(.system(size: 10, weight: category == item.name ? .semibold : .regular))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background {
                                        Capsule().fill(category == item.name
                                            ? Color.accentColor.opacity(0.18)
                                            : Color.secondary.opacity(0.10))
                                    }
                                    .foregroundStyle(category == item.name ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }

            if results.isEmpty {
                Text("No symbols match “\(query)”.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 5) {
                        ForEach(results, id: \.self) { name in
                            Button { selection = name } label: {
                                Image(systemName: name)
                                    .font(.system(size: 14))
                                    .frame(width: 30, height: 30)
                                    .background {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(selection == name
                                                ? Color.accentColor
                                                : Color.secondary.opacity(0.10))
                                    }
                                    .foregroundStyle(selection == name ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                            .help(name)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 168)
            }

            Text(selection)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct DefaultSymbolRow: View {
    @Binding var selection: String
    private let symbols: [String] = [
        "star.fill", "heart.fill", "folder.fill", "bolt.fill", "doc.text.fill",
        "camera.fill", "paintbrush.fill", "hammer.fill", "briefcase.fill",
        "cloud.fill", "trash.fill", "tag.fill", "sparkles", "checkmark.circle.fill",
        "music.note", "film.fill", "paperplane.fill", "airplane", "house.fill",
        "lock.fill", "lightbulb.fill"
    ]

    private let columns = [GridItem(.adaptive(minimum: 30, maximum: 30), spacing: 5)]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: [GridItem(.fixed(30))], spacing: 8) {
                ForEach(symbols, id: \.self) { name in
                    Button {
                        selection = name
                    } label: {
                        Image(systemName: name)
                            .font(.system(size: 14))
                            .frame(width: 30, height: 30)
                            .background {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selection == name ? Color.accentColor : Color.secondary.opacity(0.10))
                            }
                            .foregroundStyle(selection == name ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .help(name)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 40)
    }
}

struct FullSymbolBrowser: View {
    @Binding var selection: String
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var results: [String] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return SymbolCatalog.allSymbols
        }
        return SymbolCatalog.search(query)
    }

    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 8)]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("SF Symbols")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search symbols", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }
            .padding(.bottom, 4)

            if results.isEmpty {
                Text("No symbols match “\(query)”.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(results, id: \.self) { name in
                            Button {
                                selection = name
                                dismiss()
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: name)
                                        .font(.system(size: 20))
                                        .frame(width: 40, height: 40)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(selection == name ? Color.accentColor : Color.secondary.opacity(0.10))
                                        )
                                        .foregroundStyle(selection == name ? Color.white : Color.primary)
                                    Text(name)
                                        .font(.system(size: 9, design: .monospaced))
                                        .lineLimit(1)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: 60)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(name)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
    }
}

/// Emoji grid with the system picker one click away.
struct EmojiPicker: View {
    @Binding var selection: String
    @State private var group: String = EmojiCatalog.groups.first?.name ?? ""

    private var emoji: [String] {
        EmojiCatalog.groups.first { $0.name == group }?.emoji ?? []
    }

    private let columns = [GridItem(.adaptive(minimum: 30, maximum: 30), spacing: 5)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(selection.isEmpty ? "-" : selection)
                    .font(.system(size: 26))
                    .frame(width: 44, height: 44)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Or type/paste any emoji", text: $selection)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    Button {
                        NSApp.orderFrontCharacterPalette(nil)
                    } label: {
                        Label("System Emoji Picker", systemImage: "face.smiling")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.accessoryBar)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(EmojiCatalog.groups) { item in
                        Button { group = item.name } label: {
                            Text(item.name)
                                .font(.system(size: 10, weight: group == item.name ? .semibold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background {
                                    Capsule().fill(group == item.name
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.secondary.opacity(0.10))
                                }
                                .foregroundStyle(group == item.name ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 5) {
                    ForEach(emoji, id: \.self) { item in
                        Button { selection = item } label: {
                            Text(item)
                                .font(.system(size: 17))
                                .frame(width: 30, height: 30)
                                .background {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selection == item
                                            ? Color.accentColor.opacity(0.25)
                                            : Color.secondary.opacity(0.08))
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 168)
        }
    }
}
