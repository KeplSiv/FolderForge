import AppKit

/// Writes icons to folders on disk, and can put things back the way it found them.
enum IconApplier {

    enum ApplyError: LocalizedError {
        case notAFolder(URL)
        case notWritable(URL)
        case renderFailed
        case systemRefused(URL)

        var errorDescription: String? {
            switch self {
            case .notAFolder(let url):
                "“\(url.lastPathComponent)” isn't a folder."
            case .notWritable(let url):
                "No permission to modify “\(url.lastPathComponent)”. Grant access in System Settings › Privacy & Security › Files and Folders."
            case .renderFailed:
                "The icon couldn't be rendered."
            case .systemRefused(let url):
                "macOS refused to set the icon on “\(url.lastPathComponent)”."
            }
        }
    }

    struct Outcome {
        var url: URL
        var error: Error?
        var succeeded: Bool { error == nil }
    }

    /// The `Icon\r` file Finder uses to store a per-folder custom icon.
    private static let iconFileName = "Icon\r"

    static func customIconURL(for folder: URL) -> URL {
        folder.appendingPathComponent(iconFileName)
    }

    static func hasCustomIcon(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: customIconURL(for: folder).path)
    }

    // MARK: - Apply

    @discardableResult
    static func apply(_ style: FolderStyle, to folder: URL) throws -> NSImage {
        try validate(folder)

        let image = IconRenderer.iconImage(style)
        guard !image.representations.isEmpty else { throw ApplyError.renderFailed }

        BackupStore.captureOriginalIfNeeded(for: folder)

        guard NSWorkspace.shared.setIcon(image, forFile: folder.path, options: []) else {
            throw ApplyError.systemRefused(folder)
        }

        BackupStore.recordApplied(style: style, to: folder)
        refreshFinder(folder)
        return image
    }

    /// Applies to many folders, reporting progress as it goes. Never throws — each folder's
    /// result is reported individually so one permission failure doesn't sink the batch.
    static func applyBatch(_ style: FolderStyle,
                           to folders: [URL],
                           progress: ((Int, Int) -> Void)? = nil) -> [Outcome] {
        var outcomes: [Outcome] = []
        for (index, folder) in folders.enumerated() {
            do {
                try apply(style, to: folder)
                outcomes.append(Outcome(url: folder, error: nil))
            } catch {
                outcomes.append(Outcome(url: folder, error: error))
            }
            progress?(index + 1, folders.count)
        }
        return outcomes
    }

    // MARK: - Reset

    /// Puts the folder back to whatever it looked like before FolderForge touched it — the
    /// original custom icon if there was one, otherwise the plain system folder.
    static func reset(_ folder: URL) throws {
        try validate(folder)

        switch BackupStore.restoreOriginal(for: folder) {
        case .restored:
            BackupStore.clearApplied(for: folder)
            refreshFinder(folder)
            return
        case .failed:
            // We have the original but couldn't write it. Clearing here would destroy the
            // icon we were asked to bring back, so stop and let the user retry.
            throw ApplyError.systemRefused(folder)
        case .nothingToRestore:
            // Only worth archiving if the icon isn't ours. An icon FolderForge generated is
            // fully reproducible from the style in the ledger, so copying it would just burn
            // megabytes on every reset. A foreign icon is irreplaceable — keep that one.
            if BackupStore.appliedStyle(for: folder) == nil {
                BackupStore.archiveRemovedIcon(for: folder)
            }
        }

        NSWorkspace.shared.setIcon(nil, forFile: folder.path, options: [])

        // setIcon(nil:) usually removes the Icon\r file, but clean up if it lingers.
        let iconFile = customIconURL(for: folder)
        if FileManager.default.fileExists(atPath: iconFile.path) {
            try? FileManager.default.removeItem(at: iconFile)
        }

        BackupStore.clearApplied(for: folder)
        refreshFinder(folder)
    }

    static func resetBatch(_ folders: [URL]) -> [Outcome] {
        folders.map { folder in
            do { try reset(folder); return Outcome(url: folder, error: nil) }
            catch { return Outcome(url: folder, error: error) }
        }
    }

    // MARK: - Reading

    /// The icon Finder currently shows for this folder.
    static func currentIcon(of folder: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: folder.path)
    }

    // MARK: - Plumbing

    private static func validate(_ folder: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ApplyError.notAFolder(folder)
        }
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            throw ApplyError.notWritable(folder)
        }
    }

    /// Nudges Finder so the new icon shows up without needing a relaunch.
    private static func refreshFinder(_ folder: URL) {
        NSWorkspace.shared.noteFileSystemChanged(folder.path)
        // Touching the parent makes Finder re-read the directory entry.
        let parent = folder.deletingLastPathComponent().path
        NSWorkspace.shared.noteFileSystemChanged(parent)
    }
}
