import AppKit
import CryptoKit

/// Remembers what each folder looked like before we touched it, and which style is currently
/// applied. Lives in Application Support so it survives relaunches.
enum BackupStore {

    struct AppliedRecord: Codable {
        var path: String
        var styleName: String
        var style: FolderStyle
        var appliedAt: Date
        /// True if the folder already had a custom icon that we stashed away.
        var hadOriginalIcon: Bool
    }

    // MARK: - Locations

    static var supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("FolderForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var backupsDirectory: URL = {
        let dir = supportDirectory.appendingPathComponent("OriginalIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var ledgerURL: URL {
        supportDirectory.appendingPathComponent("applied.json")
    }

    private static func key(for folder: URL) -> String {
        let path = folder.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Ledger

    private static let lock = NSLock()
    private static var _ledger: [String: AppliedRecord]?

    private static var ledger: [String: AppliedRecord] {
        get {
            if let cached = _ledger { return cached }
            let loaded = (try? Data(contentsOf: ledgerURL))
                .flatMap { try? JSONDecoder.forgeDecoder.decode([String: AppliedRecord].self, from: $0) }
                ?? [:]
            _ledger = loaded
            return loaded
        }
        set {
            _ledger = newValue
            if let data = try? JSONEncoder.forgeEncoder.encode(newValue) {
                try? data.write(to: ledgerURL, options: .atomic)
            }
        }
    }

    static func appliedStyle(for folder: URL) -> FolderStyle? {
        lock.lock(); defer { lock.unlock() }
        return ledger[key(for: folder)]?.style
    }

    static func allApplied() -> [AppliedRecord] {
        lock.lock(); defer { lock.unlock() }
        return ledger.values.sorted { $0.appliedAt > $1.appliedAt }
    }

    static func recordApplied(style: FolderStyle, to folder: URL) {
        lock.lock(); defer { lock.unlock() }
        let id = key(for: folder)
        let hadOriginal = FileManager.default.fileExists(atPath: backupURL(for: folder).path)
        ledger[id] = AppliedRecord(path: folder.standardizedFileURL.path,
                                   styleName: style.name,
                                   style: style,
                                   appliedAt: Date(),
                                   hadOriginalIcon: hadOriginal)
    }

    static func clearApplied(for folder: URL) {
        lock.lock(); defer { lock.unlock() }
        ledger[key(for: folder)] = nil
    }

    // MARK: - Original icon backups

    private static func backupURL(for folder: URL) -> URL {
        backupsDirectory.appendingPathComponent(key(for: folder) + ".tiff")
    }

    private static func sentinelURL(for folder: URL) -> URL {
        backupsDirectory.appendingPathComponent(key(for: folder) + ".none")
    }

    /// Snapshots the folder's pre-existing custom icon exactly once, so the very first apply is
    /// always reversible. Subsequent applies leave the snapshot untouched.
    ///
    /// We save the *composited* icon as a multi-representation TIFF rather than copying the
    /// `Icon\r` file: that file keeps its payload in the resource fork, which the image loaders
    /// can't read back.
    static func captureOriginalIfNeeded(for folder: URL) {
        let destination = backupURL(for: folder)
        let sentinel = sentinelURL(for: folder)

        // Already decided about this folder once.
        guard !FileManager.default.fileExists(atPath: destination.path),
              !FileManager.default.fileExists(atPath: sentinel.path) else { return }

        guard IconApplier.hasCustomIcon(folder) else {
            // Nothing to preserve — remember that, so restore clears instead of re-applying.
            FileManager.default.createFile(atPath: sentinel.path, contents: Data())
            return
        }

        let icon = NSWorkspace.shared.icon(forFile: folder.path)
        if let tiff = snapshotData(of: icon) {
            try? tiff.write(to: destination, options: .atomic)
        } else {
            FileManager.default.createFile(atPath: sentinel.path, contents: Data())
        }
    }

    /// Icon snapshots, losslessly compressed.
    ///
    /// A raw `tiffRepresentation` of a folder icon is ~37 MB — every representation up to
    /// 2048×2048 stored uncompressed. LZW keeps all of them, bit for bit, at a tiny
    /// fraction of the size. Icon art is flat-colored, so it compresses extremely well.
    static func snapshotData(of icon: NSImage) -> Data? {
        icon.tiffRepresentation(using: .lzw, factor: 0) ?? icon.tiffRepresentation
    }

    static var removedDirectory: URL = {
        let dir = supportDirectory.appendingPathComponent("RemovedIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Keeps a copy of an icon we're about to delete but never made.
    ///
    /// Restoring a folder whose icon came from another tool means clearing it outright —
    /// there's no snapshot to put back, because FolderForge was never involved. Without
    /// this, one click would destroy artwork the user may have no other copy of.
    @discardableResult
    static func archiveRemovedIcon(for folder: URL) -> URL? {
        guard IconApplier.hasCustomIcon(folder) else { return nil }

        let icon = NSWorkspace.shared.icon(forFile: folder.path)
        guard let tiff = snapshotData(of: icon) else { return nil }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let name = "\(folder.lastPathComponent) \(stamp).tiff"
        let destination = removedDirectory.appendingPathComponent(name)

        do {
            try tiff.write(to: destination, options: .atomic)
            trimArchive()
            return destination
        } catch {
            return nil
        }
    }

    /// Caps the archive so it can't grow without bound. Newest kept.
    private static func trimArchive(keeping limit: Int = 25) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: removedDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        guard files.count > limit else { return }

        let sorted = files.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return l > r
        }

        for stale in sorted.dropFirst(limit) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    /// Drops snapshots for folders that no longer exist.
    ///
    /// Deleting or moving a customized folder leaves its snapshot behind with nothing to
    /// restore it to, and those are megabytes each. Runs once at launch.
    ///
    /// Deliberately conservative: it only removes entries whose recorded path is gone from
    /// disk. Snapshot files with no ledger entry are left alone, because a lost or
    /// half-written ledger shouldn't cost anyone their original artwork.
    @discardableResult
    static func pruneOrphans() -> Int {
        lock.lock()
        let current = ledger
        lock.unlock()

        var removed = 0
        var survivors = current

        for (id, record) in current where !FileManager.default.fileExists(atPath: record.path) {
            let folder = URL(fileURLWithPath: record.path)
            try? FileManager.default.removeItem(at: backupURL(for: folder))
            try? FileManager.default.removeItem(at: sentinelURL(for: folder))
            survivors[id] = nil
            removed += 1
        }

        guard removed > 0 else { return 0 }

        lock.lock()
        ledger = survivors
        lock.unlock()
        return removed
    }

    enum RestoreResult {
        /// The folder's original icon is back.
        case restored
        /// There was never an original icon — the caller should clear to the stock folder.
        case nothingToRestore
        /// We have a snapshot but couldn't write it. It has been kept for a retry.
        case failed
    }

    /// The snapshot is only discarded once it has actually been put back. Deleting it
    /// unconditionally would throw away the user's original icon whenever a restore failed —
    /// a permissions error would have been silently unrecoverable.
    static func restoreOriginal(for folder: URL) -> RestoreResult {
        let backup = backupURL(for: folder)
        let sentinel = sentinelURL(for: folder)

        guard FileManager.default.fileExists(atPath: backup.path),
              let image = NSImage(contentsOf: backup) else {
            // Nothing to put back. The sentinel has done its job either way.
            try? FileManager.default.removeItem(at: sentinel)
            return .nothingToRestore
        }

        guard NSWorkspace.shared.setIcon(image, forFile: folder.path, options: []) else {
            // Keep the snapshot so the user can try again.
            return .failed
        }

        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.removeItem(at: sentinel)
        return .restored
    }
}

// MARK: - Shared coders

extension JSONEncoder {
    static var forgeEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var forgeDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
