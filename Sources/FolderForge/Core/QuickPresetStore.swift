import Foundation
import Observation

struct QuickPresetSlot: Codable, Hashable, Identifiable {
    let id: Int
    var style: FolderStyle?
}

/// Preset snapshots used by Finder's FolderForge Services menu.
@Observable
final class QuickPresetStore {
    static let slotCount = 10

    private(set) var slots: [QuickPresetSlot]
    private let storeURL: URL

    init(storeURL: URL = BackupStore.supportDirectory.appendingPathComponent("quick-presets.json")) {
        self.storeURL = storeURL
        let decoded = (try? Data(contentsOf: storeURL))
            .flatMap { try? JSONDecoder.forgeDecoder.decode([QuickPresetSlot].self, from: $0) }
            ?? []
        let saved = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0.style) })
        slots = (1...Self.slotCount).map { QuickPresetSlot(id: $0, style: saved[$0] ?? nil) }
    }

    func style(at slot: Int) -> FolderStyle? {
        slots.first { $0.id == slot }?.style
    }

    func assign(_ style: FolderStyle, to slot: Int) {
        guard let index = slots.firstIndex(where: { $0.id == slot }) else { return }
        var snapshot = style
        snapshot.id = UUID()
        slots[index].style = snapshot
        save()
    }

    func clear(_ slot: Int) {
        guard let index = slots.firstIndex(where: { $0.id == slot }) else { return }
        slots[index].style = nil
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder.forgeEncoder.encode(slots) else { return }
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: storeURL, options: .atomic)
    }
}
