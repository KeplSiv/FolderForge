import Foundation

@Observable
final class WorkspaceThemeStore {
    private struct Saved: Codable {
        var themes: [WorkspaceTheme]
        var assignments: [WorkspaceThemeAssignment]
        var looks: [WorkspaceLook]?
    }

    private(set) var customThemes: [WorkspaceTheme] = []
    private(set) var assignments: [WorkspaceThemeAssignment] = []
    private(set) var looks: [WorkspaceLook] = []
    var allThemes: [WorkspaceTheme] { WorkspaceTheme.all + customThemes }

    private let storeURL: URL

    init(storeURL: URL = BackupStore.supportDirectory.appendingPathComponent("workspace-themes.json")) {
        self.storeURL = storeURL
        guard let data = try? Data(contentsOf: storeURL),
              let saved = try? JSONDecoder.forgeDecoder.decode(Saved.self, from: data) else { return }
        customThemes = saved.themes.filter { !$0.isBuiltIn && (2...10).contains($0.colors.count) }
        assignments = saved.assignments
        looks = saved.looks ?? []
    }

    @discardableResult
    func saveTheme(_ theme: WorkspaceTheme) -> WorkspaceTheme {
        var copy = theme
        copy.name = uniqueName(theme.name, excluding: theme.id)
        if copy.isBuiltIn { copy.id = UUID().uuidString }
        if let index = customThemes.firstIndex(where: { $0.id == copy.id }) {
            customThemes[index] = copy
        } else {
            customThemes.append(copy)
        }
        persist()
        return copy
    }

    func deleteTheme(_ id: String) {
        customThemes.removeAll { $0.id == id }
        assignments.removeAll { $0.themeID == id }
        persist()
    }

    func assign(themeID: String, root: URL, depth: Int, includeRoot: Bool) {
        let path = root.standardizedFileURL.path
        let assignment = WorkspaceThemeAssignment(rootPath: path, themeID: themeID,
                                                   depth: depth, includeRoot: includeRoot)
        assignments.removeAll { $0.rootPath == path }
        assignments.insert(assignment, at: 0)
        persist()
    }

    func assignment(for root: URL) -> WorkspaceThemeAssignment? {
        assignments.first { $0.rootPath == root.standardizedFileURL.path }
    }

    func forgetAssignment(for root: URL) {
        assignments.removeAll { $0.rootPath == root.standardizedFileURL.path }
        persist()
    }

    @discardableResult
    func saveLook(_ look: WorkspaceLook) -> WorkspaceLook {
        var copy = look
        let base = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = base.isEmpty ? "My Workspace" : base
        if let index = looks.firstIndex(where: { $0.id == copy.id }) {
            looks[index] = copy
        } else {
            looks.insert(copy, at: 0)
        }
        persist()
        return copy
    }

    func deleteLook(_ id: UUID) {
        looks.removeAll { $0.id == id }
        persist()
    }

    func importSetupLooks(_ incoming: [WorkspaceLook],
                          sourceHome: String, destinationHome: String = NSHomeDirectory()) {
        for var look in incoming {
            look.rootPath = SetupArchive.mappedPath(look.rootPath, sourceHome: sourceHome,
                                                    destinationHome: destinationHome)
            if looks.contains(where: { $0.id == look.id }) { look.id = UUID() }
            saveLook(look)
        }
    }

    @discardableResult
    func importSetupThemes(_ incoming: [WorkspaceTheme],
                           assignments incomingAssignments: [WorkspaceThemeAssignment],
                           sourceHome: String, destinationHome: String = NSHomeDirectory()) -> Int {
        var mappedIDs: [String: String] = [:]
        for theme in incoming {
            if theme.isBuiltIn {
                mappedIDs[theme.id] = theme.id
                continue
            }
            guard (2...10).contains(theme.colors.count) else { continue }
            var copy = theme
            if let existing = customThemes.first(where: { $0.id == copy.id }) {
                if existing == copy {
                    mappedIDs[theme.id] = existing.id
                    continue
                }
                copy.id = UUID().uuidString
            }
            let saved = saveTheme(copy)
            mappedIDs[theme.id] = saved.id
        }
        for assignment in incomingAssignments {
            guard let themeID = mappedIDs[assignment.themeID] ??
                    (WorkspaceTheme.all.contains { $0.id == assignment.themeID } ? assignment.themeID : nil)
            else { continue }
            let path = SetupArchive.mappedPath(assignment.rootPath, sourceHome: sourceHome,
                                               destinationHome: destinationHome)
            assign(themeID: themeID, root: URL(fileURLWithPath: path),
                   depth: assignment.depth, includeRoot: assignment.includeRoot)
        }
        return mappedIDs.count
    }

    private func uniqueName(_ raw: String, excluding id: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "My Theme" : trimmed
        let taken = Set(allThemes.filter { $0.id != id }.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var suffix = 2
        while taken.contains("\(base) \(suffix)".lowercased()) { suffix += 1 }
        return "\(base) \(suffix)"
    }

    private func persist() {
        let saved = Saved(themes: customThemes, assignments: assignments, looks: looks)
        guard let data = try? JSONEncoder.forgeEncoder.encode(saved) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
