import AppKit
import SwiftUI

// MARK: - Color

/// A Codable, hashable color. Stored in sRGB so presets are portable across machines.
struct RGBA: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .white
        self.init(r: Double(c.redComponent), g: Double(c.greenComponent),
                  b: Double(c.blueComponent), a: Double(c.alphaComponent))
    }

    init(_ color: Color) { self.init(NSColor(color)) }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }

    var color: Color { Color(nsColor: nsColor) }

    var cgColor: CGColor { nsColor.cgColor }

    /// `#RRGGBB`
    var hex: String {
        String(format: "#%02X%02X%02X",
               Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    init?(hex raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(r: Double((v >> 16) & 0xFF) / 255,
                  g: Double((v >> 8) & 0xFF) / 255,
                  b: Double(v & 0xFF) / 255)
    }

    /// Perceived luminance, 0...1.
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    /// HSB brightness — the max channel. This is what people mean by "how dark is it".
    var brightnessValue: Double { max(r, max(g, b)) }

    static let white = RGBA(r: 1, g: 1, b: 1)
    static let black = RGBA(r: 0, g: 0, b: 0)
}

// MARK: - Base icon

/// Which stock macOS folder shape to start from.
enum BaseIconKind: String, Codable, CaseIterable, Identifiable {
    case generic, documents, downloads, desktop, pictures, music, movies
    case applications, developer, library, publicFolder, group, burnable, home, open

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generic: "Folder"
        case .documents: "Documents"
        case .downloads: "Downloads"
        case .desktop: "Desktop"
        case .pictures: "Pictures"
        case .music: "Music"
        case .movies: "Movies"
        case .applications: "Applications"
        case .developer: "Developer"
        case .library: "Library"
        case .publicFolder: "Public"
        case .group: "Shared"
        case .burnable: "Burnable"
        case .home: "Home"
        case .open: "Open Folder"
        }
    }

    /// Filename inside CoreTypes.bundle.
    var resourceName: String {
        switch self {
        case .generic: "GenericFolderIcon"
        case .documents: "DocumentsFolderIcon"
        case .downloads: "DownloadsFolder"
        case .desktop: "DesktopFolderIcon"
        case .pictures: "PicturesFolderIcon"
        case .music: "MusicFolderIcon"
        case .movies: "MovieFolderIcon"
        case .applications: "ApplicationsFolderIcon"
        case .developer: "DeveloperFolderIcon"
        case .library: "LibraryFolderIcon"
        case .publicFolder: "PublicFolderIcon"
        case .group: "GroupFolder"
        case .burnable: "BurnableFolderIcon"
        case .home: "HomeFolderIcon"
        case .open: "OpenFolderIcon"
        }
    }
}

// MARK: - Overlay

enum OverlayKind: String, Codable, CaseIterable, Identifiable {
    case none, symbol, emoji, text, image, icns
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "None"
        case .symbol: "Symbol"
        case .emoji: "Emoji"
        case .text: "Text"
        case .image: "Image"
        case .icns: "ICNS"
        }
    }
}

/// How the overlay art is fused into the folder face.
enum OverlayFinish: String, Codable, CaseIterable, Identifiable {
    /// Carved into the folder — tone-on-tone, feels like part of the icon. (Apple's own look.)
    case engraved
    /// Flat fill in a chosen color (white by default).
    case tinted
    /// Original artwork colors, untouched. Best for emoji and photos.
    case natural
    /// Dark ink pressed into the folder.
    case stamped
    /// Bright, glossy, sits on top with a soft shadow.
    case raised

    var id: String { rawValue }
    var title: String {
        switch self {
        case .engraved: "Engraved"
        case .tinted: "Tinted"
        case .natural: "Natural"
        case .stamped: "Stamped"
        case .raised: "Raised"
        }
    }
    var help: String {
        switch self {
        case .engraved: "Carved into the folder face. Matches Apple's own folder icons."
        case .tinted: "Flat fill in a color you pick."
        case .natural: "Keeps the artwork's own colors. Best for emoji and photos."
        case .stamped: "Dark ink pressed into the folder."
        case .raised: "Bright and glossy, floating above the folder."
        }
    }
    /// Finishes that ignore source color and use a mask instead.
    var isMasked: Bool { self != .natural }
}

struct Overlay: Codable, Hashable {
    var kind: OverlayKind = .none
    var symbolName: String = "star.fill"
    var emoji: String = "🚀"
    var text: String = "AB"
    /// PNG bytes, embedded so a preset stays valid after the source file moves.
    var imageData: Data?

    init() {}

    /// Same tolerance as `FolderStyle` — unknown or missing keys fall back to defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)).flatMap { $0 } ?? fallback
        }
        let blank = Overlay()
        kind = value(.kind, blank.kind)
        symbolName = value(.symbolName, blank.symbolName)
        emoji = value(.emoji, blank.emoji)
        text = value(.text, blank.text)
        imageData = (try? container.decodeIfPresent(Data.self, forKey: .imageData)) ?? nil
    }

    var isEmpty: Bool {
        switch kind {
        case .none: true
        case .symbol: symbolName.isEmpty
        case .emoji: emoji.isEmpty
        case .text: text.isEmpty
        case .image: imageData == nil
        case .icns: false
        }
    }
}

// MARK: - Style

/// The complete recipe for one folder icon.
struct FolderStyle: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = "Untitled"

    // Color
    var baseIcon: BaseIconKind = .generic
    var tint = RGBA(hex: "#2E9BFF")!
    var tintStrength: Double = 1.0          // 0…1 — how far from the stock blue
    var gradientEnabled = false
    var tintSecondary = RGBA(hex: "#8E5BFF")!
    var gradientAngle: Double = 90          // degrees, 0 = left→right
    /// Push the folder's brightness toward the tint, so dark and pale colors really land.
    var matchLuminance = true

    // Tone
    var saturation: Double = 1.0            // 0…2
    var brightness: Double = 0.0            // -0.35…0.35
    var contrast: Double = 1.0              // 0.6…1.6

    /// Full replacement icon bytes, used for imported `.icns` artwork. When this is set,
    /// FolderForge applies these pixels as the folder icon instead of composing a stock folder.
    var fullIconData: Data?

    // Overlay
    var overlay = Overlay()
    var finish: OverlayFinish = .engraved
    var overlayColor = RGBA.white
    var overlayScale: Double = 0.42         // fraction of canvas width
    var overlayOpacity: Double = 0.92
    var overlayOffsetX: Double = 0.0        // fraction of canvas width
    var overlayOffsetY: Double = 0.0
    var overlayRotation: Double = 0         // degrees
    var overlayShadow = true
    var symbolWeight: SymbolWeight = .regular

    enum SymbolWeight: String, Codable, CaseIterable, Identifiable {
        case ultraLight, light, regular, medium, semibold, bold, heavy, black
        var id: String { rawValue }
        var title: String {
            switch self {
            case .ultraLight: "Ultra Light"
            case .light: "Light"
            case .regular: "Regular"
            case .medium: "Medium"
            case .semibold: "Semibold"
            case .bold: "Bold"
            case .heavy: "Heavy"
            case .black: "Black"
            }
        }
        var nsWeight: NSFont.Weight {
            switch self {
            case .ultraLight: .ultraLight
            case .light: .light
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            case .heavy: .heavy
            case .black: .black
            }
        }
    }

    init() {}

    /// Hand-written so that a style file written by an older (or newer) build still loads:
    /// every key is optional and falls back to the default. Presets get shared between
    /// people, and a missing key should never turn into a decode failure.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? fallback
        }
        let blank = FolderStyle()

        id = value(.id, UUID())
        name = value(.name, blank.name)
        baseIcon = value(.baseIcon, blank.baseIcon)
        tint = value(.tint, blank.tint)
        tintStrength = value(.tintStrength, blank.tintStrength)
        gradientEnabled = value(.gradientEnabled, blank.gradientEnabled)
        tintSecondary = value(.tintSecondary, blank.tintSecondary)
        gradientAngle = value(.gradientAngle, blank.gradientAngle)
        matchLuminance = value(.matchLuminance, blank.matchLuminance)
        saturation = value(.saturation, blank.saturation)
        brightness = value(.brightness, blank.brightness)
        contrast = value(.contrast, blank.contrast)
        fullIconData = (try? container.decodeIfPresent(Data.self, forKey: .fullIconData)) ?? nil
        overlay = value(.overlay, blank.overlay)
        finish = value(.finish, blank.finish)
        overlayColor = value(.overlayColor, blank.overlayColor)
        overlayScale = value(.overlayScale, blank.overlayScale)
        overlayOpacity = value(.overlayOpacity, blank.overlayOpacity)
        overlayOffsetX = value(.overlayOffsetX, blank.overlayOffsetX)
        overlayOffsetY = value(.overlayOffsetY, blank.overlayOffsetY)
        overlayRotation = value(.overlayRotation, blank.overlayRotation)
        overlayShadow = value(.overlayShadow, blank.overlayShadow)
        symbolWeight = value(.symbolWeight, blank.symbolWeight)
    }

    /// Equality that ignores identity — used to detect "is this still the preset I loaded?"
    func matchesAppearance(of other: FolderStyle) -> Bool {
        var a = self, b = other
        a.id = UUID(); b.id = a.id
        a.name = ""; b.name = ""
        return a == b
    }

    // Ignore `id` and `name` for hashing purposes in preview caches.
    var renderKey: Int {
        var copy = self
        copy.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        copy.name = ""
        var hasher = Hasher()
        hasher.combine(copy)
        return hasher.finalize()
    }
}
