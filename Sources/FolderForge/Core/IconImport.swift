import AppKit
import UniformTypeIdentifiers

/// Normalizes artwork the user brings in from outside FolderForge.
enum IconImport {
    static let icnsType = UTType(filenameExtension: "icns") ?? .data
    static let imageContentTypes: [UTType] = [.image]
    static let allowedContentTypes: [UTType] = [.image, icnsType]
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
