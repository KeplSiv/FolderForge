import AppKit
import UniformTypeIdentifiers

/// Normalizes artwork the user brings in from outside FolderForge.
enum IconImport {
    static let icnsType = UTType(filenameExtension: "icns") ?? .data
    static let svgType = UTType(filenameExtension: "svg") ?? .image
    static let imageContentTypes: [UTType] = [.image, svgType]
    static let allowedContentTypes: [UTType] = [.image, svgType, icnsType]
    static let applicationContentTypes: [UTType] = [.applicationBundle]

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

    static func isSVG(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "svg"
    }

    /// Keeps scalable and multi-representation formats intact. Raster artwork is normalized
    /// to PNG so style files remain portable and independent of the source file.
    static func embeddedData(from url: URL) -> Data? {
        if isSVG(url) || isICNS(url) {
            guard NSImage(contentsOf: url) != nil else { return nil }
            return try? Data(contentsOf: url)
        }
        return pngData(from: url)
    }

    static func pngData(from url: URL) -> Data? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return GlyphFactory.pngData(from: image)
    }

    static func applicationIcon(from url: URL) -> (name: String, pngData: Data)? {
        guard url.pathExtension.lowercased() == "app" else { return nil }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
        guard values?.isDirectory == true,
              values?.contentType?.conforms(to: .applicationBundle) != false
        else { return nil }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        guard let data = GlyphFactory.pngData(from: icon, side: 1024) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "", options: [.anchored, .caseInsensitive])
        return (name, data)
    }
}
