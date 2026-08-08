import Foundation

/// Walks a directory tree and returns the folders worth customizing.
///
/// Deliberately conservative about what counts as a "folder": app bundles, `.photoslibrary`
/// and friends are directories on disk but customizing them is never what someone means.
enum FolderScanner {

    struct Options: Codable, Hashable, Sendable {
        /// How many levels below the root to descend. 0 = the root only.
        var depth: Int = 1
        /// Include the root folder itself in the results.
        var includeRoot = true
        /// Skip folders whose name starts with a dot.
        var skipHidden = true
        /// Skip bundles — `.app`, `.photoslibrary`, `.rtfd`…
        var skipPackages = true
        /// Skip symlinked directories (following them invites cycles).
        var skipSymlinks = true
        /// Glob patterns. A pattern containing `/` is matched against the full path,
        /// otherwise against the folder name.
        var excludePatterns: [String] = defaultExclusions
        /// Optional whitelist — when non-empty, a folder must match one of these to be kept.
        var includePatterns: [String] = []
        /// Hard stop so a scan of `/` can't hang the app.
        var maxResults = 2000

        static let defaultExclusions = [
            "node_modules", ".git", ".svn", "Library", "*.app", "*.framework",
            "*.photoslibrary", "*.xcodeproj", "*.bundle", "__pycache__", ".build",
            "venv", ".venv", "DerivedData", "*.lproj",
        ]
    }

    struct Result: Sendable {
        var folders: [URL]
        /// How many directories we looked at, including ones that were filtered out.
        var examined: Int
        /// True if `maxResults` cut the walk short.
        var truncated: Bool
        var excludedCount: Int
        /// Deepest eligible folder found, measured below the root. Root itself is level 0.
        var deepestLevel: Int
    }

    // MARK: - Scan

    static func scan(root: URL, options: Options) -> Result {
        let root = root.standardizedFileURL
        var results: [URL] = []
        var examined = 0
        var excluded = 0
        var truncated = false

        let manager = FileManager.default

        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return Result(folders: [], examined: 0, truncated: false,
                          excludedCount: 0, deepestLevel: 0)
        }

        var deepestLevel = 0
        if options.includeRoot {
            // The root is what the user explicitly asked for — exclusion patterns and the
            // hidden-folder rule shouldn't second-guess that.
            results.append(root)
        }

        // Breadth-first so a shallow depth limit costs nothing, and so `maxResults` truncates
        // at the top of the tree rather than deep inside one arbitrary branch.
        var frontier: [(url: URL, level: Int)] = [(root, 0)]

        while !frontier.isEmpty, !truncated {
            var next: [(url: URL, level: Int)] = []

            for (directory, level) in frontier {
                guard level < options.depth else { continue }

                let children = (try? manager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [
                        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isHiddenKey,
                    ],
                    options: options.skipHidden ? [.skipsHiddenFiles] : []
                )) ?? []

                for child in children {
                    let values = try? child.resourceValues(forKeys: [
                        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
                    ])
                    guard values?.isDirectory == true else { continue }

                    examined += 1

                    if options.skipSymlinks, values?.isSymbolicLink == true { continue }
                    if options.skipPackages, values?.isPackage == true { excluded += 1; continue }
                    if options.skipHidden, child.lastPathComponent.hasPrefix(".") {
                        excluded += 1; continue
                    }
                    if matches(child, patterns: options.excludePatterns) {
                        excluded += 1; continue
                    }
                    if !options.includePatterns.isEmpty,
                       !matches(child, patterns: options.includePatterns) {
                        excluded += 1; continue
                    }
                    deepestLevel = max(deepestLevel, level + 1)

                    guard results.count < options.maxResults else {
                        truncated = true
                        break
                    }

                    results.append(child)
                    // Only queue for descent if we can actually go deeper.
                    if level + 1 < options.depth { next.append((child, level + 1)) }
                }

                if truncated { break }
            }

            frontier = next
        }

        return Result(folders: results, examined: examined,
                      truncated: truncated, excludedCount: excluded,
                      deepestLevel: deepestLevel)
    }

    // MARK: - Pattern matching

    /// Shell-glob matching via `fnmatch`, the same engine your shell uses.
    static func matches(_ url: URL, patterns: [String]) -> Bool {
        let name = url.lastPathComponent
        let path = url.path

        for pattern in patterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Patterns with a slash are matched against the whole path, everything else
            // against the folder's own name.
            let matchesPath = trimmed.contains("/")
            let subject = matchesPath ? path : name

            // Case-folded so `*.APP` and `node_modules` behave the way people expect on a
            // case-insensitive filesystem. FNM_PATHNAME stops `*` from leaping across
            // directory separators in path patterns.
            var flags = Int32(FNM_CASEFOLD)
            if matchesPath { flags |= Int32(FNM_PATHNAME) }

            if fnmatch(trimmed, subject, flags) == 0 { return true }
        }
        return false
    }

    /// Splits a user-typed exclusion list on commas and newlines.
    static func parsePatterns(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Expands `~`, resolves relative paths, and tidies the result.
    ///
    /// A relative path is tried against the working directory first (what you'd expect from
    /// the CLI) and then against home (what you'd expect typing "Projects" into the app).
    static func resolve(path raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Accept a dragged-in path that arrived shell-escaped or quoted.
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count > 1 {
            text = String(text.dropFirst().dropLast())
        }
        if text.hasPrefix("'"), text.hasSuffix("'"), text.count > 1 {
            text = String(text.dropFirst().dropLast())
        }
        text = text.replacingOccurrences(of: "\\ ", with: " ")

        if text.hasPrefix("file://"), let url = URL(string: text) {
            return url.standardizedFileURL
        }

        let expanded = (text as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }

        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(expanded).standardizedFileURL,
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(expanded).standardizedFileURL,
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
            ?? candidates[0]
    }

    /// Directory suggestions for a partially typed path, for inline completion.
    static func completions(for raw: String, limit: Int = 8) -> [URL] {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }

        let expanded = (text as NSString).expandingTildeInPath
        let endsWithSeparator = expanded.hasSuffix("/")

        let directory = endsWithSeparator
            ? URL(fileURLWithPath: expanded)
            : URL(fileURLWithPath: expanded).deletingLastPathComponent()
        let prefix = endsWithSeparator
            ? ""
            : URL(fileURLWithPath: expanded).lastPathComponent.lowercased()

        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return children
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .filter { prefix.isEmpty || $0.lastPathComponent.lowercased().hasPrefix(prefix) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(limit)
            .map { $0 }
    }
}
