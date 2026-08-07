import AppKit

// MARK: - Color palettes

enum Palettes {
    struct Swatch: Identifiable, Hashable {
        var name: String
        var color: RGBA
        var id: String { name }
    }

    struct Group: Identifiable, Hashable {
        var name: String
        var swatches: [Swatch]
        var id: String { name }
    }

    static func swatch(_ name: String, _ hex: String) -> Swatch {
        Swatch(name: name, color: RGBA(hex: hex) ?? .white)
    }

    static let groups: [Group] = [
        Group(name: "System", swatches: [
            swatch("Blue", "#0A84FF"), swatch("Indigo", "#5E5CE6"), swatch("Purple", "#BF5AF2"),
            swatch("Pink", "#FF375F"), swatch("Red", "#FF453A"), swatch("Orange", "#FF9F0A"),
            swatch("Yellow", "#FFD60A"), swatch("Green", "#32D74B"), swatch("Mint", "#66D4CF"),
            swatch("Teal", "#40C8E0"), swatch("Cyan", "#64D2FF"), swatch("Brown", "#AC8E68"),
            swatch("Gray", "#98989D"), swatch("Graphite", "#5A5A5E"),
        ]),
        Group(name: "Muted", swatches: [
            swatch("Sage", "#9CAF88"), swatch("Clay", "#C97C5D"), swatch("Sand", "#D9C3A5"),
            swatch("Dusty Rose", "#C9A0A0"), swatch("Slate", "#7B8794"), swatch("Moss", "#6B7F5C"),
            swatch("Plum", "#8E6C88"), swatch("Denim", "#6E85A8"), swatch("Ochre", "#C89F5D"),
            swatch("Fog", "#B8BFC7"), swatch("Cocoa", "#8A6A5B"), swatch("Olive", "#8A8B5C"),
        ]),
        Group(name: "Vivid", swatches: [
            swatch("Electric", "#00E5FF"), swatch("Magenta", "#FF00E5"), swatch("Lime", "#B6FF00"),
            swatch("Sunset", "#FF6B35"), swatch("Hot Pink", "#FF2D95"), swatch("Ultraviolet", "#7A00FF"),
            swatch("Acid", "#D4FF00"), swatch("Aqua", "#00FFC8"), swatch("Coral", "#FF5E5B"),
            swatch("Flare", "#FFB300"), swatch("Neon Blue", "#2979FF"), swatch("Poison", "#39FF14"),
        ]),
        Group(name: "Deep", swatches: [
            swatch("Midnight", "#1B2A4A"), swatch("Forest", "#1F3D2B"), swatch("Wine", "#4A1B2A"),
            swatch("Espresso", "#3B2A21"), swatch("Ink", "#22252A"), swatch("Navy", "#16324F"),
            swatch("Aubergine", "#3A2145"), swatch("Pine", "#123B32"), swatch("Rust", "#6B2D14"),
        ]),
        Group(name: "Neutral", swatches: [
            swatch("Snow", "#F5F5F7"), swatch("Pearl", "#E3E3E6"), swatch("Silver", "#C7C7CC"),
            swatch("Ash", "#8E8E93"), swatch("Steel", "#5B5B60"), swatch("Charcoal", "#3A3A3C"),
            swatch("Onyx", "#1C1C1E"),
        ]),
    ]

    static let gradients: [(name: String, from: String, to: String, angle: Double)] = [
        ("Sunset", "#FF9F0A", "#FF375F", 60),
        ("Ocean", "#0A84FF", "#00E5C0", 90),
        ("Twilight", "#5E5CE6", "#BF5AF2", 75),
        ("Citrus", "#FFD60A", "#FF6B35", 45),
        ("Aurora", "#39FF14", "#00E5FF", 110),
        ("Bubblegum", "#FF2D95", "#7A00FF", 70),
        ("Ember", "#FF453A", "#6B2D14", 90),
        ("Mint Cream", "#66D4CF", "#F5F5F7", 90),
        ("Deep Sea", "#16324F", "#40C8E0", 100),
        ("Peach", "#FFB3A7", "#FFD9A0", 60),
    ]
}

// MARK: - Built-in style presets

enum BuiltInPresets {

    static func make(_ name: String,
                     hex: String,
                     symbol: String?,
                     finish: OverlayFinish = .engraved,
                     scale: Double = 0.42,
                     gradientTo: String? = nil,
                     angle: Double = 90,
                     saturation: Double = 1,
                     brightness: Double = 0) -> FolderStyle {
        var style = FolderStyle()
        style.name = name
        style.tint = RGBA(hex: hex) ?? .white
        style.saturation = saturation
        style.brightness = brightness
        if let gradientTo {
            style.gradientEnabled = true
            style.tintSecondary = RGBA(hex: gradientTo) ?? style.tint
            style.gradientAngle = angle
        }
        if let symbol {
            style.overlay.kind = .symbol
            style.overlay.symbolName = symbol
            style.finish = finish
            style.overlayScale = scale
        } else {
            style.overlay.kind = .none
        }
        return style
    }

    static let all: [FolderStyle] = [
        make("Code", hex: "#2E9BFF", symbol: "chevron.left.forwardslash.chevron.right"),
        make("Design", hex: "#BF5AF2", symbol: "paintbrush.pointed.fill"),
        make("Photos", hex: "#FF9F0A", symbol: "photo.stack.fill"),
        make("Music", hex: "#FF375F", symbol: "music.note"),
        make("Video", hex: "#5E5CE6", symbol: "film.fill"),
        make("Documents", hex: "#64D2FF", symbol: "doc.text.fill"),
        make("Archive", hex: "#8A6A5B", symbol: "archivebox.fill"),
        make("Finance", hex: "#32D74B", symbol: "dollarsign.circle.fill"),
        make("Work", hex: "#7B8794", symbol: "briefcase.fill"),
        make("School", hex: "#FFD60A", symbol: "graduationcap.fill"),
        make("Travel", hex: "#40C8E0", symbol: "airplane"),
        make("Games", hex: "#FF2D95", symbol: "gamecontroller.fill"),
        make("Secure", hex: "#3A3A3C", symbol: "lock.fill"),
        make("Favorites", hex: "#FFB300", symbol: "star.fill"),
        make("Downloads", hex: "#00E5C0", symbol: "arrow.down.circle.fill"),
        make("Trash It", hex: "#98989D", symbol: "trash.fill"),
        make("Ideas", hex: "#FFD60A", symbol: "lightbulb.fill", finish: .raised),
        make("Health", hex: "#FF453A", symbol: "heart.fill"),
        make("Recipes", hex: "#C97C5D", symbol: "fork.knife"),
        make("Fitness", hex: "#39FF14", symbol: "figure.run", saturation: 0.9),
        make("Cloud", hex: "#B8BFC7", symbol: "cloud.fill"),
        make("Research", hex: "#6E85A8", symbol: "magnifyingglass"),
        make("Writing", hex: "#D9C3A5", symbol: "pencil.and.scribble"),
        make("Podcast", hex: "#8E6C88", symbol: "mic.fill"),

        // Gradients
        make("Sunset", hex: "#FF9F0A", symbol: "sun.max.fill", gradientTo: "#FF375F", angle: 60),
        make("Ocean", hex: "#0A84FF", symbol: "water.waves", gradientTo: "#00E5C0", angle: 90),
        make("Twilight", hex: "#5E5CE6", symbol: "moon.stars.fill", gradientTo: "#BF5AF2", angle: 75),
        make("Aurora", hex: "#39FF14", symbol: "sparkles", gradientTo: "#00E5FF", angle: 110),
        make("Ember", hex: "#FF453A", symbol: "flame.fill", gradientTo: "#6B2D14", angle: 90),
        make("Bubblegum", hex: "#FF2D95", symbol: "heart.fill", gradientTo: "#7A00FF", angle: 70),

        // Monochrome
        make("Midnight", hex: "#22252A", symbol: "circle.hexagongrid.fill", brightness: -0.05),
        make("Snow", hex: "#F5F5F7", symbol: "snowflake", saturation: 0.2, brightness: 0.10),
        make("Graphite", hex: "#5A5A5E", symbol: "square.stack.3d.up.fill", saturation: 0.15),
        make("Blank Slate", hex: "#98989D", symbol: nil, saturation: 0.1),
    ]
}
