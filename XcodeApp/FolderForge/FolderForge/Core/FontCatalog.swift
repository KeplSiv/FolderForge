import AppKit
import CoreText
import Foundation

enum FontCatalog {
    enum ImportError: LocalizedError {
        case unsupportedFile
        case noFontsFound
        case registrationFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFile:
                "Choose a TrueType or OpenType font (.ttf, .otf, or .ttc)."
            case .noFontsFound:
                "No usable fonts were found in that file."
            case .registrationFailed(let detail):
                "The font couldn't be loaded. \(detail)"
            }
        }
    }

    static let supportedExtensions = ["ttf", "otf", "ttc"]

    static var directory: URL {
        BackupStore.supportDirectory.appendingPathComponent("Fonts", isDirectory: true)
    }

    static func registerStoredFonts() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in files where supportedExtensions.contains(file.pathExtension.lowercased()) {
            var error: Unmanaged<CFError>?
            _ = CTFontManagerRegisterFontsForURL(file as CFURL, .process, &error)
        }
    }

    static func availableFontNames() -> [String] {
        NSFontManager.shared.availableFontFamilies.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    @discardableResult
    static func importFont(from source: URL) throws -> [String] {
        guard supportedExtensions.contains(source.pathExtension.lowercased()) else {
            throw ImportError.unsupportedFile
        }

        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = uniqueDestination(for: source)
        if source.standardizedFileURL != destination.standardizedFileURL {
            try FileManager.default.copyItem(at: source, to: destination)
        }

        var registrationError: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(
            destination as CFURL,
            .process,
            &registrationError
        )

        let names = fontNames(in: destination)
        guard !names.isEmpty else {
            try? FileManager.default.removeItem(at: destination)
            throw ImportError.noFontsFound
        }

        if !registered, let error = registrationError?.takeRetainedValue() {
            // Core Text reports an error when an identical font is already registered. If
            // its family is available, the import is still usable and should be kept.
            let installed = Set(availableFontNames())
            guard names.contains(where: installed.contains) else {
                try? FileManager.default.removeItem(at: destination)
                throw ImportError.registrationFailed(error.localizedDescription)
            }
        }

        return names
    }

    private static func fontNames(in url: URL) -> [String] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
                as? [CTFontDescriptor]
        else { return [] }

        var result: [String] = []
        for descriptor in descriptors {
            if let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute)
                as? String,
               !result.contains(family) {
                result.append(family)
            }
        }
        return result
    }

    private static func uniqueDestination(for source: URL) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension.lowercased()
        var candidate = directory.appendingPathComponent("\(base).\(ext)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(suffix).\(ext)")
            suffix += 1
        }
        return candidate
    }
}
