import AppKit
import SwiftUI

/// The user's saved styles, persisted to Application Support and shareable as `.folderstyle`
/// files.
@Observable
final class PresetStore {
    private(set) var userPresets: [FolderStyle] = []

    let builtIn = BuiltInPresets.all

    private var storeURL: URL {
        BackupStore.supportDirectory.appendingPathComponent("presets.json")
    }

    init() { load() }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder.forgeDecoder.decode([FolderStyle].self, from: data)
        else { return }
        userPresets = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder.forgeEncoder.encode(userPresets) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    // MARK: - Mutations

    func add(_ style: FolderStyle, named name: String) {
        var copy = style
        copy.id = UUID()
        copy.name = uniqueName(from: name)
        userPresets.insert(copy, at: 0)
        save()
    }

    func update(_ style: FolderStyle) {
        guard let index = userPresets.firstIndex(where: { $0.id == style.id }) else { return }
        userPresets[index] = style
        save()
    }

    func delete(_ style: FolderStyle) {
        userPresets.removeAll { $0.id == style.id }
        save()
    }

    func rename(_ style: FolderStyle, to name: String) {
        guard let index = userPresets.firstIndex(where: { $0.id == style.id }) else { return }
        userPresets[index].name = uniqueName(from: name, excluding: style.id)
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        userPresets.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func move(_ style: FolderStyle, by offset: Int) {
        guard let source = userPresets.firstIndex(where: { $0.id == style.id }) else { return }
        let destination = source + offset
        guard userPresets.indices.contains(destination) else { return }
        userPresets.swapAt(source, destination)
        save()
    }

    private func uniqueName(from name: String, excluding id: UUID? = nil) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Untitled" : trimmed
        let taken = Set(userPresets.filter { $0.id != id }.map(\.name))
        guard taken.contains(base) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    // MARK: - Import / export

    static let fileExtension = "folderstyle"

    func exportData(for styles: [FolderStyle]) -> Data? {
        try? JSONEncoder.forgeEncoder.encode(styles)
    }

    /// Accepts either a single style or an array of them.
    @discardableResult
    func importStyles(from url: URL) -> Int {
        guard let data = try? Data(contentsOf: url) else { return 0 }

        var incoming: [FolderStyle] = []
        if let many = try? JSONDecoder.forgeDecoder.decode([FolderStyle].self, from: data) {
            incoming = many
        } else if let one = try? JSONDecoder.forgeDecoder.decode(FolderStyle.self, from: data) {
            incoming = [one]
        }

        for style in incoming { add(style, named: style.name) }
        return incoming.count
    }
}
