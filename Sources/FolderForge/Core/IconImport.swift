import AppKit
import UniformTypeIdentifiers

/// Normalizes artwork the user brings in from outside FolderForge.
enum IconImport {
    static let icnsType = UTType(filenameExtension: "icns") ?? .data
    static let allowedContentTypes: [UTType] = [.image, icnsType]

    static func canImport(_ url: URL) -> Bool {
        if isICNS(url) { return true }
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return false
        }
        return type.conforms(to: .image) || type.conforms(to: icnsType)
    }

    static func isICNS(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "icns"
    }

    static func pngData(from url: URL) -> Data? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return GlyphFactory.pngData(from: image)
    }
}
