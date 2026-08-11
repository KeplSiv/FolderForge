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
    case none, symbol, emoji, text, appIcon, image, icns
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "None"
        case .symbol: "Symbol"
        case .emoji: "Emoji"
        case .text: "Text"
        case .appIcon: "App Icon"
        case .image: "Image"
        case .icns: "ICNS"
        }
    }

    /// Photos, emoji and application icons need their internal luminance preserved when a
    /// monochrome finish is applied. Symbols and text are already template-shaped masks.
    var preservesArtworkDetail: Bool {
        switch self {
        case .emoji, .appIcon, .image: true
        case .none, .symbol, .text, .icns: false
        }
    }
}

// MARK: - Fill

/// What occupies the folder face before any symbol, emoji or text overlay is added.
enum FillKind: String, Codable, CaseIterable, Identifiable {
    case color, image, icns

    var id: String { rawValue }
    var title: String {
        switch self {
        case .color: "Color"
        case .image: "Image"
        case .icns: "ICNS"
        }
    }
}

struct FolderFill: Codable, Hashable {
    var kind: FillKind = .color
    /// PNG bytes embedded from a PNG/JPG import. These become the folder face.
    var imageData: Data?
    /// PNG bytes rasterized from an imported ICNS. These replace the whole folder icon.
    var fullIconData: Data?
}

enum NativeLayerFillKind: String, Codable, CaseIterable, Identifiable {
    case color, image

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Independent appearance for one component of Apple's native folder artwork.
struct NativeFolderLayerStyle: Codable, Hashable {
    var enabled = true
    var fillKind: NativeLayerFillKind = .color
    var tint = RGBA(hex: "#2E9BFF")!
    var gradientEnabled = false
    var tintSecondary = RGBA(hex: "#8E5BFF")!
    var gradientAngle: Double = 90
    var imageData: Data?
    var imageScale: Double = 1
    var imageOpacity: Double = 1
    var imageOffsetX: Double = 0
    var imageOffsetY: Double = 0
    var imageRotation: Double = 0

    static func paper() -> NativeFolderLayerStyle {
        var layer = NativeFolderLayerStyle()
        layer.tint = .white
        layer.tintSecondary = RGBA(hex: "#E8F4FF")!
        return layer
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
        case .tinted: "A clean monochrome treatment in a color you pick."
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
    /// Display-only source name retained with imported application artwork.
    var sourceAppName: String?

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
        sourceAppName = (try? container.decodeIfPresent(String.self, forKey: .sourceAppName)) ?? nil
    }

    var isEmpty: Bool {
        switch kind {
        case .none: true
        case .symbol: symbolName.isEmpty
        case .emoji: emoji.isEmpty
        case .text: text.isEmpty
        case .appIcon: imageData == nil
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
    /// Native generic folders can optionally style Apple's component layers separately.
    var separateLayerColors = false
    var backFlapTint = RGBA(hex: "#2E9BFF")!
    var paperTint = RGBA.white
    var frontFlapTint = RGBA(hex: "#2E9BFF")!
    var backLayer = NativeFolderLayerStyle()
    var paperLayer = NativeFolderLayerStyle.paper()
    var frontLayer = NativeFolderLayerStyle()

    // Tone
    var saturation: Double = 1.0            // 0…2
    var brightness: Double = 0.0            // -0.35…0.35
    var contrast: Double = 1.0              // 0.6…1.6

    // Fill
    var fill = FolderFill()
    var fillScale: Double = 1.0
    var fillOpacity: Double = 1.0
    var fillOffsetX: Double = 0.0
    var fillOffsetY: Double = 0.0
    var fillRotation: Double = 0.0

    /// Legacy location for imported `.icns` artwork. New styles use `fill.fullIconData`.
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
        separateLayerColors = value(.separateLayerColors, blank.separateLayerColors)
        backFlapTint = value(.backFlapTint, blank.backFlapTint)
        paperTint = value(.paperTint, blank.paperTint)
        frontFlapTint = value(.frontFlapTint, blank.frontFlapTint)
        backLayer = value(.backLayer, {
            var layer = blank.backLayer
            layer.tint = backFlapTint
            return layer
        }())
        paperLayer = value(.paperLayer, {
            var layer = blank.paperLayer
            layer.tint = paperTint
            return layer
        }())
        frontLayer = value(.frontLayer, {
            var layer = blank.frontLayer
            layer.tint = frontFlapTint
            return layer
        }())
        saturation = value(.saturation, blank.saturation)
        brightness = value(.brightness, blank.brightness)
        contrast = value(.contrast, blank.contrast)
        fill = value(.fill, blank.fill)
        fillScale = value(.fillScale, blank.fillScale)
        fillOpacity = value(.fillOpacity, blank.fillOpacity)
        fillOffsetX = value(.fillOffsetX, blank.fillOffsetX)
        fillOffsetY = value(.fillOffsetY, blank.fillOffsetY)
        fillRotation = value(.fillRotation, blank.fillRotation)
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

        migrateLegacyArtworkIntoFill()
    }

    private mutating func migrateLegacyArtworkIntoFill() {
        guard fill.kind == .color else { return }

        if let fullIconData {
            fill.kind = .icns
            fill.fullIconData = fullIconData
            self.fullIconData = nil
            if overlay.kind == .icns { overlay.kind = .none }
            return
        }

        if overlay.kind == .image, let imageData = overlay.imageData {
            fill.kind = .image
            fill.imageData = imageData
            fillScale = overlayScale
            fillOpacity = overlayOpacity
            fillOffsetX = overlayOffsetX
            fillOffsetY = overlayOffsetY
            fillRotation = overlayRotation
            overlay.kind = .none
            overlay.imageData = nil
        } else if overlay.kind == .icns {
            overlay.kind = .none
        }
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
