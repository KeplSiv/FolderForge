import Foundation

/// Persists folders the user grants through macOS's Open panel. The App Store build uses
/// these security-scoped bookmarks to regain access after relaunching; the direct-download
/// build has no sandbox and simply uses the original URL.
enum SandboxAccessStore {
#if APP_STORE
    private static let defaultsKey = "sandbox.folderBookmarks"

    static func remember(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard let data = try? standardized.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }

        var bookmarks = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
        bookmarks[standardized.path] = data
        UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
    }

    static func withAccess<T>(to requestedURL: URL, _ work: (URL) throws -> T) rethrows -> T {
        let requested = requestedURL.standardizedFileURL
        let bookmarks = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:]
        guard let rootPath = bookmarks.keys
            .filter({ contains(requested.path, in: $0) })
            .max(by: { $0.count < $1.count }),
              let data = bookmarks[rootPath]
        else {
            return try work(requested)
        }

        var stale = false
        guard let scopedRoot = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return try work(requested)
        }

        if stale { remember(scopedRoot) }
        let accessing = scopedRoot.startAccessingSecurityScopedResource()
        defer { if accessing { scopedRoot.stopAccessingSecurityScopedResource() } }

        let accessibleURL: URL
        if requested.path == rootPath {
            accessibleURL = scopedRoot
        } else {
            let suffix = String(requested.path.dropFirst(rootPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            accessibleURL = suffix.isEmpty
                ? scopedRoot
                : scopedRoot.appendingPathComponent(suffix)
        }
        return try work(accessibleURL)
    }

    private static func contains(_ path: String, in rootPath: String) -> Bool {
        path == rootPath || path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/")
    }
#else
    static func remember(_ url: URL) {}

    static func withAccess<T>(to url: URL, _ work: (URL) throws -> T) rethrows -> T {
        try work(url)
    }
#endif
}
