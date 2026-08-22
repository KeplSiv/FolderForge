import AppKit

/// A curated, searchable set of SF Symbols that read well at folder-icon scale.
///
/// Everything is validated against the running system on first access, so the picker can
/// never show a tile that renders as nothing on an older macOS.
enum SymbolCatalog {

    struct Category: Identifiable, Hashable {
        var name: String
        var glyph: String
        var symbols: [String]
        var id: String { name }
    }

    private static let raw: [Category] = [
        Category(name: "Favorites", glyph: "star", symbols: [
            "star.fill", "heart.fill", "bolt.fill", "flame.fill", "sparkles", "crown.fill",
            "flag.fill", "bookmark.fill", "pin.fill", "tag.fill", "checkmark.seal.fill",
            "hand.thumbsup.fill", "diamond.fill", "seal.fill", "rosette", "medal.fill",
        ]),
        Category(name: "Work", glyph: "briefcase", symbols: [
            "briefcase.fill", "case.fill", "building.2.fill", "building.columns.fill",
            "person.2.fill", "person.crop.circle.fill", "calendar", "clock.fill",
            "chart.bar.fill", "chart.pie.fill", "chart.line.uptrend.xyaxis",
            "list.bullet.clipboard.fill", "signature", "paperclip", "tray.full.fill",
            "envelope.fill", "phone.fill", "megaphone.fill", "target", "lightbulb.fill",
        ]),
        Category(name: "Files", glyph: "doc", symbols: [
            "doc.fill", "doc.text.fill", "doc.richtext.fill", "doc.on.doc.fill",
            "folder.fill", "archivebox.fill", "shippingbox.fill", "tray.2.fill",
            "externaldrive.fill", "internaldrive.fill", "square.stack.3d.up.fill",
            "books.vertical.fill", "book.closed.fill", "newspaper.fill", "text.book.closed.fill",
            "arrow.down.circle.fill", "arrow.up.circle.fill", "trash.fill",
        ]),
        Category(name: "Media", glyph: "photo", symbols: [
            "photo.fill", "photo.stack.fill", "camera.fill", "video.fill", "film.fill",
            "play.circle.fill", "music.note", "music.note.list", "headphones", "mic.fill",
            "waveform", "speaker.wave.3.fill", "tv.fill", "radio.fill", "guitars.fill",
            "paintpalette.fill", "theatermasks.fill", "airplayvideo",
        ]),
        Category(name: "Design", glyph: "paintbrush", symbols: [
            "paintbrush.fill", "paintbrush.pointed.fill", "pencil", "pencil.and.scribble",
            "pencil.and.outline", "ruler.fill", "scissors", "eyedropper.halffull",
            "square.on.circle", "circle.hexagongrid.fill", "swatchpalette.fill",
            "lasso", "wand.and.stars", "cube.fill", "scribble.variable", "compass.drawing",
        ]),
        Category(name: "Code", glyph: "chevron.left.forwardslash.chevron.right", symbols: [
            "chevron.left.forwardslash.chevron.right", "terminal.fill", "curlybraces",
            "hammer.fill", "wrench.and.screwdriver.fill", "gearshape.fill", "gearshape.2.fill",
            "cpu.fill", "memorychip.fill", "server.rack", "network", "ladybug.fill",
            "app.badge.fill", "square.stack.3d.down.right.fill", "function", "point.3.connected.trianglepath.dotted",
        ]),
        Category(name: "Life", glyph: "house", symbols: [
            "house.fill", "bed.double.fill", "sofa.fill", "shower.fill", "washer.fill",
            "cart.fill", "creditcard.fill", "dollarsign.circle.fill", "banknote.fill",
            "gift.fill", "birthday.cake.fill", "fork.knife", "cup.and.saucer.fill",
            "wineglass.fill", "carrot.fill", "takeoutbag.and.cup.and.straw.fill",
            "pawprint.fill", "leaf.fill", "tree.fill",
        ]),
        Category(name: "Travel", glyph: "airplane", symbols: [
            "airplane", "car.fill", "bus.fill", "tram.fill", "bicycle", "sailboat.fill",
            "ferry.fill", "map.fill", "globe.americas.fill", "globe.europe.africa.fill",
            "mappin.and.ellipse", "suitcase.fill", "beach.umbrella.fill", "mountain.2.fill",
            "binoculars.fill", "signpost.right.fill", "tent.fill",
        ]),
        Category(name: "Health", glyph: "heart.text.square", symbols: [
            "heart.text.square.fill", "cross.case.fill", "pills.fill", "bandage.fill",
            "stethoscope", "figure.run", "figure.walk", "figure.yoga", "dumbbell.fill",
            "sportscourt.fill", "brain.head.profile", "lungs.fill", "drop.fill",
        ]),
        Category(name: "Nature", glyph: "sun.max", symbols: [
            "sun.max.fill", "moon.fill", "moon.stars.fill", "cloud.fill", "cloud.rain.fill",
            "snowflake", "wind", "water.waves", "flame.fill", "bolt.fill", "rainbow",
            "leaf.fill", "camera.macro", "fish.fill", "bird.fill", "ant.fill", "hare.fill",
        ]),
        Category(name: "Security", glyph: "lock", symbols: [
            "lock.fill", "lock.shield.fill", "key.fill", "shield.lefthalf.filled",
            "eye.slash.fill", "hand.raised.fill", "exclamationmark.triangle.fill",
            "checkmark.shield.fill", "faceid", "touchid", "lock.doc.fill",
        ]),
        Category(name: "Symbols", glyph: "circle.grid.3x3", symbols: [
            "circle.fill", "square.fill", "triangle.fill", "hexagon.fill", "octagon.fill",
            "capsule.fill", "circle.grid.3x3.fill", "square.grid.2x2.fill", "asterisk",
            "number", "plus.circle.fill", "minus.circle.fill", "xmark.circle.fill",
            "checkmark.circle.fill", "questionmark.circle.fill", "infinity",
            "arrow.triangle.2.circlepath", "arrow.right.circle.fill", "location.fill",
        ]),
        Category(name: "Letters", glyph: "a.circle", symbols: (UnicodeScalar("a").value...UnicodeScalar("z").value)
            .compactMap { UnicodeScalar($0).map { "\($0).circle.fill" } }),
        Category(name: "Numbers", glyph: "1.circle", symbols: (0...9).map { "\($0).circle.fill" }),
    ]

    /// Categories with unavailable symbols filtered out. Computed once.
    static let categories: [Category] = {
        raw.compactMap { category in
            let available = category.symbols.filter(GlyphFactory.symbolExists)
            guard !available.isEmpty else { return nil }
            return Category(name: category.name, glyph: category.glyph, symbols: available)
        }
    }()

    static let allSymbols: [String] = categories.flatMap(\.symbols)

    /// Substring search over symbol names, with the category name as a secondary haystack.
    static func search(_ query: String) -> [String] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return allSymbols }

        var seen = Set<String>()
        var results: [String] = []

        for category in categories {
            let categoryMatches = category.name.lowercased().contains(needle)
            for symbol in category.symbols {
                guard !seen.contains(symbol) else { continue }
                if symbol.lowercased().contains(needle) || categoryMatches {
                    seen.insert(symbol)
                    results.append(symbol)
                }
            }
        }

        // Let people type an exact SF Symbol name we didn't curate.
        if results.isEmpty, GlyphFactory.symbolExists(needle) { results = [needle] }
        return results
    }
}

/// Emoji offered in the picker, grouped the way the macOS emoji panel groups them.
enum EmojiCatalog {
    struct Group: Identifiable, Hashable {
        var name: String
        var emoji: [String]
        var id: String { name }
    }

    static let groups: [Group] = [
        Group(name: "Objects", emoji: [
            "📁", "📂", "🗂️", "📦", "🗃️", "📋", "📝", "📔", "📚", "📖", "🔖", "📎", "✂️",
            "🖊️", "✏️", "🖍️", "📐", "📏", "🔑", "🔒", "💼", "🧰", "🔧", "🔨", "⚙️", "🧲",
            "💡", "🔋", "💾", "💿", "🖥️", "⌨️", "🖱️", "📱", "☎️", "📷", "🎥", "🎬", "🎙️",
        ]),
        Group(name: "Symbols", emoji: [
            "⭐", "🌟", "✨", "💫", "🔥", "💥", "❄️", "💧", "🌈", "☀️", "🌙", "⚡", "☁️",
            "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💯", "✅", "❌", "⚠️",
            "🚫", "♻️", "🔱", "⚜️", "🔰", "🎯", "🧿", "🔮", "🏆", "🥇", "🎖️", "🏅",
        ]),
        Group(name: "Activity", emoji: [
            "🎮", "🕹️", "🎲", "🧩", "🎨", "🎭", "🎼", "🎵", "🎸", "🥁", "🎺", "🎧", "🎤",
            "⚽", "🏀", "🏈", "⚾", "🎾", "🏐", "🏓", "🏸", "🥊", "🏋️", "🚴", "🏃", "🧘",
            "🏕️", "🎣", "🎳", "🛹", "🎿", "🏂", "🪂",
        ]),
        Group(name: "Places", emoji: [
            "🏠", "🏡", "🏢", "🏫", "🏥", "🏦", "🏛️", "⛺", "🌍", "🌎", "🌏", "🗺️", "🧭",
            "✈️", "🚗", "🚕", "🚌", "🚂", "🚢", "⛵", "🚀", "🛸", "🏝️", "🏔️", "🌋", "🗻",
            "🌅", "🌇", "🌃", "🎢", "🎡",
        ]),
        Group(name: "Nature", emoji: [
            "🌱", "🌲", "🌳", "🌴", "🌵", "🍀", "🍁", "🍂", "🌷", "🌹", "🌺", "🌻", "🌼",
            "🐶", "🐱", "🐭", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸",
            "🐙", "🦋", "🐝", "🐳", "🐬", "🦄", "🦉", "🦜",
        ]),
        Group(name: "Food", emoji: [
            "🍏", "🍎", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍒", "🍑", "🥭", "🍍",
            "🥑", "🥕", "🌽", "🌶️", "🍞", "🧀", "🍕", "🍔", "🌮", "🍣", "🍜", "🍰", "🍪",
            "🍫", "🍿", "☕", "🍵", "🍺", "🍷", "🥂",
        ]),
        Group(name: "People", emoji: [
            "😀", "😎", "🤓", "🧐", "🤔", "😴", "🤖", "👻", "💀", "👽", "🎃", "🤡",
            "👨‍💻", "👩‍💻", "👨‍🎨", "👩‍🎨", "👨‍🍳", "👩‍🍳", "🧑‍🚀", "🕵️", "🧙", "🦸", "👑", "🫶", "👍", "🙌",
        ]),
    ]

    static let all: [String] = groups.flatMap(\.emoji)
}
