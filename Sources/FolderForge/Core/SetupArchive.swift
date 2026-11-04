import Foundation

/// A portable, local JSON snapshot of user configuration and applied folder recipes.
/// Paths under the exporting user's home are remapped to the importing user's home.
struct SetupArchive: Codable, Identifiable {
    struct AppliedFolder: Codable {
        var path: String
        var style: FolderStyle
        var originalIconData: Data?
    }

    var id = UUID()
    var version = 1
    var exportedAt = Date()
    var sourceHome: String
    var presets: [FolderStyle]
    var themes: [WorkspaceTheme]
    var themeAssignments: [WorkspaceThemeAssignment]
    var looks: [WorkspaceLook]? = nil
    var ruleSets: [SmartRuleSet]
    var activeRuleSetID: UUID?
    var watches: [SmartRuleWatch]?
    var appliedFolders: [AppliedFolder]

    static func mappedPath(_ path: String, sourceHome: String, destinationHome: String) -> String {
        let source = URL(fileURLWithPath: sourceHome).standardizedFileURL.path
        let destination = URL(fileURLWithPath: destinationHome).standardizedFileURL.path
        if path == source { return destination }
        if path.hasPrefix(source + "/") { return destination + String(path.dropFirst(source.count)) }
        return path
    }

    func destination(for entry: AppliedFolder, home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: Self.mappedPath(entry.path, sourceHome: sourceHome,
                                            destinationHome: home), isDirectory: true)
    }

    func matchingFolders(home: String = NSHomeDirectory()) -> [(URL, AppliedFolder)] {
        appliedFolders.compactMap { entry in
            let url = destination(for: entry, home: home)
            var directory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory),
                  directory.boolValue else { return nil }
            return (url, entry)
        }
    }
}
