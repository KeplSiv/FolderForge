import Foundation

/// Bundled palettes keep theme switching fully offline. Source links are attribution for
/// the color combinations; no request to Coolors is made by the app.
struct WorkspaceTheme: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var colors: [RGBA]
    var sourceURL: URL?

    var isBuiltIn: Bool { Self.all.contains { $0.id == id } }

    static let all: [WorkspaceTheme] = [
        theme("coastal", "Coastal", ["#0A656A", "#0C9AA8", "#B8D6D8", "#F3C8A8", "#F57706"]),
        theme("orchid", "Orchid", ["#F6E0F2", "#F6A8DE", "#FE98CD", "#D8D9F8", "#D8BDEF"]),
        theme("woodland", "Woodland", ["#F1F7EE", "#B0BEA9", "#92AA83", "#E0EDC5", "#E7F59E"]),
        theme("mocha", "Mocha", ["#260C1A", "#432E36", "#5F4842", "#AF8D86", "#EDBFC6"]),
        theme("playful", "Playful", ["#F03F81", "#8CAF3A", "#3D405B", "#FFF460", "#D65C20"]),
    ]

    private static func theme(_ id: String, _ name: String, _ hex: [String]) -> WorkspaceTheme {
        WorkspaceTheme(id: id, name: name,
                       colors: hex.compactMap(RGBA.init(hex:)),
                       sourceURL: URL(string: "https://coolors.co/" + hex.map { String($0.dropFirst()).lowercased() }.joined(separator: "-"))!)
    }

    static func fromCoolorsURL(_ raw: String, name: String = "Imported Palette") -> WorkspaceTheme? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host?.lowercased() == "coolors.co" else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" && $0 != "palette" }
        guard segments.count == 1 else { return nil }
        let hex = segments[0].split(separator: "-").map(String.init)
        guard (2...10).contains(hex.count),
              hex.allSatisfy({ $0.count == 6 && $0.allSatisfy(\.isHexDigit) }) else { return nil }
        let colors = hex.compactMap { RGBA(hex: $0) }
        guard colors.count == hex.count else { return nil }
        return WorkspaceTheme(id: UUID().uuidString, name: name, colors: colors, sourceURL: url)
    }
}

struct WorkspaceThemeAssignment: Codable, Hashable, Identifiable {
    var rootPath: String
    var themeID: String
    var depth: Int
    var includeRoot: Bool
    var id: String { rootPath }
}

/// An exact, local snapshot of a workspace's folder styles. A nil style means the
/// folder had its original icon, so switching back restores it.
struct WorkspaceLook: Codable, Identifiable {
    struct Entry: Codable {
        var relativePath: String
        var style: FolderStyle?
    }

    var id: UUID
    var name: String
    var rootPath: String
    var entries: [Entry]
    var styledCount: Int { entries.filter { $0.style != nil }.count }
    var originalCount: Int { entries.count - styledCount }

    init(id: UUID = UUID(), name: String, root: URL, pairs: [(URL, FolderStyle?)]) {
        self.id = id
        self.name = name
        rootPath = root.standardizedFileURL.path
        entries = pairs.compactMap { url, style in
            guard let relative = Self.relativePath(of: url, under: root) else { return nil }
            return Entry(relativePath: relative, style: style)
        }
    }

    static func relativePath(of url: URL, under root: URL) -> String? {
        let path = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        if path == base { return "" }
        guard path.hasPrefix(base + "/") else { return nil }
        return String(path.dropFirst(base.count + 1))
    }

    func pairs(in root: URL) -> [(URL, FolderStyle?)] {
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        return entries.compactMap { entry -> (URL, FolderStyle?)? in
            let url = entry.relativePath.isEmpty ? root :
                root.appendingPathComponent(entry.relativePath, isDirectory: true).standardizedFileURL
            guard Self.relativePath(of: url, under: root) != nil else { return nil }
            // Imported looks may contain paths that pass through a symlink. Do not let a
            // workspace restore write outside the workspace's actual directory tree.
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolved == resolvedRoot || resolved.hasPrefix(resolvedRoot + "/") else { return nil }
            return (url, entry.style)
        }.filter { url, _ in
            var directory = ObjCBool(false)
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
        }
    }
}

enum WorkspaceStyleChange {
    static func needsWrite(target: FolderStyle?, current: FolderStyle?, hasCustomIcon: Bool) -> Bool {
        // A nil target means "leave or restore the original". If FolderForge has
        // no recorded style, leave an unrelated custom icon untouched as well.
        guard let target else { return current != nil }
        return target != current || !hasCustomIcon
    }
}

enum WorkspaceThemeEngine {
    /// The same path always receives the same palette slot, independent of scan order.
    static func paletteIndex(for url: URL, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let bytes = url.standardizedFileURL.path.lowercased().utf8
        let hash = bytes.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return Int(hash % UInt64(count))
    }

    static func style(for url: URL, theme: WorkspaceTheme, existing: FolderStyle?) -> FolderStyle {
        let matchingPreset = BuiltInPresets.all.first {
            $0.name.compare(url.lastPathComponent, options: .caseInsensitive) == .orderedSame
        }
        var style = existing ?? matchingPreset ?? FolderStyle()
        let index = paletteIndex(for: url, count: theme.colors.count)
        style.name = "\(theme.name) · \(url.lastPathComponent)"
        style.tint = theme.colors[index]
        style.tintSecondary = theme.colors[(index + 1) % theme.colors.count]
        style.gradientEnabled = true
        style.gradientAngle = 70
        style.tintStrength = 1
        style.matchLuminance = true
        // Image and full-icon fills cover the tint, so a theme replaces the fill while
        // retaining a separate image overlay, symbol, or text.
        if style.fill.kind != .color || style.fullIconData != nil {
            style.fill.kind = .color
            style.fill.imageData = nil
            style.fill.fullIconData = nil
            style.fullIconData = nil
        }
        if style.separateLayerColors {
            style.backFlapTint = style.tint
            style.frontFlapTint = style.tintSecondary
            style.backLayer.tint = style.tint
            style.frontLayer.tint = style.tintSecondary
            style.backLayer.fillKind = .color
            style.frontLayer.fillKind = .color
            style.backLayer.imageData = nil
            style.frontLayer.imageData = nil
            style.backLayer.gradientEnabled = false
            style.frontLayer.gradientEnabled = false
        }
        return style
    }
}
