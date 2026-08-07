import AppKit

/// A small command-line surface over the same engine the UI uses. Handy for scripting,
/// for CI, and for generating the app's own icon at build time.
enum CLI {

    static func run(_ args: [String]) -> Int32 {
        var args = args
        guard let command = args.first else { printUsage(); return 1 }
        args.removeFirst()

        switch command {
        case "--help", "-h":
            printUsage(); return 0
        case "--list-presets":
            for preset in BuiltInPresets.all { print(preset.name) }
            return 0
        case "--export":
            return export(args)
        case "--contact-sheet":
            return contactSheet(args)
        case "--apply":
            return apply(args)
        case "--reset":
            return reset(args)
        case "--iconset":
            return iconset(args)
        case "--ui-snapshot":
            return uiSnapshot(args)
        case "--debug-selection":
            return debugSelection(args)
        default:
            FileHandle.standardError.write(Data("Unknown option: \(command)\n".utf8))
            printUsage()
            return 1
        }
    }

    // MARK: - Argument parsing

    private struct Options {
        var positional: [String] = []
        var flags: [String: String] = [:]

        subscript(_ key: String) -> String? { flags[key] }

        func double(_ key: String) -> Double? { flags[key].flatMap(Double.init) }
        func int(_ key: String) -> Int? { flags[key].flatMap(Int.init) }
    }

    private static func parse(_ args: [String]) -> Options {
        var options = Options()
        var index = 0
        while index < args.count {
            let arg = args[index]
            if arg.hasPrefix("--") {
                let key = String(arg.dropFirst(2))
                if index + 1 < args.count, !args[index + 1].hasPrefix("--") {
                    options.flags[key] = args[index + 1]
                    index += 2
                } else {
                    options.flags[key] = "true"
                    index += 1
                }
            } else {
                options.positional.append(arg)
                index += 1
            }
        }
        return options
    }

    /// Builds a style from `--preset`, `--style <file.json>` and individual overrides.
    private static func style(from options: Options) -> FolderStyle {
        var style: FolderStyle

        // Fail loudly on a typo'd preset or an unreadable style file. Silently falling back
        // to the default meant `--preset Cdoe` quietly painted every folder plain blue.
        if let path = options["style"] {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let decoded = try? JSONDecoder.forgeDecoder.decode(FolderStyle.self, from: data)
            else {
                FileHandle.standardError.write(
                    Data("error: couldn't read a style from \(path)\n".utf8))
                exit(1)
            }
            style = decoded
        } else if let name = options["preset"] {
            guard let match = BuiltInPresets.all.first(where: {
                $0.name.compare(name, options: .caseInsensitive) == .orderedSame
            }) else {
                let known = BuiltInPresets.all.map(\.name).joined(separator: ", ")
                FileHandle.standardError.write(
                    Data("error: no preset named “\(name)”.\nAvailable: \(known)\n".utf8))
                exit(1)
            }
            style = match
        } else {
            style = FolderStyle()
        }

        if let hex = options["color"], let color = RGBA(hex: hex) { style.tint = color }
        if let hex = options["color2"], let color = RGBA(hex: hex) {
            style.tintSecondary = color
            style.gradientEnabled = true
        }
        if let angle = options.double("angle") { style.gradientAngle = angle }
        if let symbol = options["symbol"] {
            style.overlay.kind = .symbol
            style.overlay.symbolName = symbol
        }
        if let emoji = options["emoji"] {
            style.overlay.kind = .emoji
            style.overlay.emoji = emoji
        }
        if let text = options["text"] {
            style.overlay.kind = .text
            style.overlay.text = text
        }
        if let path = options["image"],
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let image = NSImage(data: data),
           let png = GlyphFactory.pngData(from: image) {
            style.overlay.kind = .image
            style.overlay.imageData = png
            style.finish = .natural
        }
        if let finish = options["finish"],
           let match = OverlayFinish(rawValue: finish) { style.finish = match }
        if let base = options["base"],
           let match = BaseIconKind(rawValue: base) { style.baseIcon = match }
        if let scale = options.double("scale") { style.overlayScale = scale }
        if let value = options.double("saturation") { style.saturation = value }
        if let value = options.double("brightness") { style.brightness = value }
        if let value = options.double("contrast") { style.contrast = value }
        if let value = options.double("opacity") { style.overlayOpacity = value }

        return style
    }

    // MARK: - Commands

    private static func export(_ args: [String]) -> Int32 {
        let options = parse(args)
        guard let out = options.positional.first ?? options["out"] else {
            FileHandle.standardError.write(Data("--export needs an output path\n".utf8))
            return 1
        }
        let size = options.int("size") ?? 1024
        guard let cg = IconRenderer.render(style(from: options), pixels: size) else {
            FileHandle.standardError.write(Data("Render failed\n".utf8))
            return 1
        }
        guard writePNG(cg, to: URL(fileURLWithPath: out)) else { return 1 }
        print("Wrote \(out) (\(size)×\(size))")
        return 0
    }

    /// Renders every built-in preset into one grid image — the fastest way to eyeball the
    /// whole library after a change to the renderer.
    private static func contactSheet(_ args: [String]) -> Int32 {
        let options = parse(args)
        let out = options.positional.first ?? options["out"] ?? "contact-sheet.png"
        let cell = options.int("cell") ?? 180
        let columns = options.int("columns") ?? 6

        var styles = BuiltInPresets.all
        if options["finishes"] != nil {
            // One row per finish, so the finishes can be compared side by side.
            styles = OverlayFinish.allCases.flatMap { finish -> [FolderStyle] in
                ["#0A84FF", "#FF9F0A", "#32D74B", "#BF5AF2", "#FF375F", "#3A3A3C"].map { hex in
                    var s = BuiltInPresets.make(finish.title, hex: hex, symbol: "star.fill",
                                                finish: finish)
                    if finish == .stamped { s.overlayColor = .black }
                    return s
                }
            }
        }

        let rows = Int(ceil(Double(styles.count) / Double(columns)))
        let labelHeight = 22
        let width = columns * cell
        let height = rows * (cell + labelHeight)

        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 1 }

        ctx.setFillColor(NSColor(white: 0.14, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics

        for (index, style) in styles.enumerated() {
            let column = index % columns
            let row = index / columns
            let originY = height - (row + 1) * (cell + labelHeight)

            if let cg = IconRenderer.render(style, pixels: cell) {
                ctx.draw(cg, in: CGRect(x: column * cell, y: originY + labelHeight,
                                        width: cell, height: cell))
            }

            let label = NSAttributedString(string: style.name, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white,
            ])
            let size = label.size()
            label.draw(at: CGPoint(x: CGFloat(column * cell) + (CGFloat(cell) - size.width) / 2,
                                   y: CGFloat(originY) + 4))
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let cg = ctx.makeImage(), writePNG(cg, to: URL(fileURLWithPath: out)) else { return 1 }
        print("Wrote \(out) — \(styles.count) styles")
        return 0
    }

    /// Expands the positional arguments through the scanner, honoring --depth / --exclude.
    private static func resolveTargets(_ options: Options) -> [URL] {
        let roots = options.positional.compactMap { FolderScanner.resolve(path: $0) }

        let depth: Int? = if options["recursive"] != nil, options["depth"] == nil {
            Int.max
        } else if let value = options.int("depth") {
            value
        } else {
            nil
        }

        guard let depth else { return roots }

        var scan = FolderScanner.Options()
        scan.depth = depth
        scan.includeRoot = options["no-root"] == nil
        if let excludes = options["exclude"] {
            scan.excludePatterns = FolderScanner.parsePatterns(excludes)
        }
        if let includes = options["only"] {
            scan.includePatterns = FolderScanner.parsePatterns(includes)
        }
        if let limit = options.int("limit") { scan.maxResults = limit }
        if options["include-hidden"] != nil { scan.skipHidden = false }

        var seen = Set<URL>()
        var results: [URL] = []
        for root in roots {
            let found = FolderScanner.scan(root: root, options: scan)
            if found.truncated {
                FileHandle.standardError.write(
                    Data("warning: stopped at the \(scan.maxResults)-folder cap under \(root.path)\n".utf8))
            }
            for url in found.folders where !seen.contains(url) {
                seen.insert(url)
                results.append(url)
            }
        }
        return results
    }

    private static func apply(_ args: [String]) -> Int32 {
        let options = parse(args)
        guard !options.positional.isEmpty else {
            FileHandle.standardError.write(Data("--apply needs at least one folder\n".utf8))
            return 1
        }
        let target = style(from: options)
        let urls = resolveTargets(options)
        guard !urls.isEmpty else {
            FileHandle.standardError.write(Data("Nothing matched\n".utf8))
            return 1
        }
        if options["dry-run"] != nil {
            for url in urls { print("would apply → \(url.path)") }
            print("\(urls.count) folder(s)")
            return 0
        }
        var failures = 0
        for outcome in IconApplier.applyBatch(target, to: urls) {
            if let error = outcome.error {
                failures += 1
                FileHandle.standardError.write(
                    Data("✗ \(outcome.url.path): \(error.localizedDescription)\n".utf8))
            } else {
                print("✓ \(outcome.url.path)")
            }
        }
        return failures == 0 ? 0 : 1
    }

    private static func reset(_ args: [String]) -> Int32 {
        let options = parse(args)
        guard !options.positional.isEmpty else {
            FileHandle.standardError.write(Data("--reset needs at least one folder\n".utf8))
            return 1
        }
        let urls = resolveTargets(options)
        guard !urls.isEmpty else {
            FileHandle.standardError.write(Data("Nothing matched\n".utf8))
            return 1
        }
        if options["dry-run"] != nil {
            for url in urls { print("would restore → \(url.path)") }
            return 0
        }
        var failures = 0
        for outcome in IconApplier.resetBatch(urls) {
            if let error = outcome.error {
                failures += 1
                FileHandle.standardError.write(
                    Data("✗ \(outcome.url.path): \(error.localizedDescription)\n".utf8))
            } else {
                print("↺ \(outcome.url.path)")
            }
        }
        return failures == 0 ? 0 : 1
    }

    /// Writes an `.iconset` directory that `iconutil` can turn into an `.icns`.
    private static func iconset(_ args: [String]) -> Int32 {
        let options = parse(args)
        guard let out = options.positional.first ?? options["out"] else {
            FileHandle.standardError.write(Data("--iconset needs an output directory\n".utf8))
            return 1
        }
        let directory = URL(fileURLWithPath: out)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let target = style(from: options)
        let variants: [(Int, String)] = [
            (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
        ]
        for (pixels, name) in variants {
            guard let cg = IconRenderer.render(target, pixels: pixels) else { continue }
            _ = writePNG(cg, to: directory.appendingPathComponent(name))
        }
        print("Wrote \(out)")
        return 0
    }

    /// Renders the interface offscreen at an exact size. Development aid for checking that
    /// the layout survives a small window.
    private static func uiSnapshot(_ args: [String]) -> Int32 {
        let options = parse(args)
        guard let out = options.positional.first ?? options["out"] else {
            FileHandle.standardError.write(Data("--ui-snapshot needs an output path\n".utf8))
            return 1
        }
        let target = UISnapshot.Target(rawValue: options["view"] ?? "main") ?? .main
        let folders = (options["folders"] ?? "")
            .split(separator: ",")
            .compactMap { FolderScanner.resolve(path: String($0)) }
        let ok = UISnapshot.capture(
            target: target,
            width: options.int("width") ?? 1080,
            height: options.int("height") ?? 700,
            to: URL(fileURLWithPath: out),
            folders: folders,
            selectIndex: options.int("select"),
            sheetPath: options["path"] ?? ""
        )
        if ok { print("Wrote \(out)") }
        return ok ? 0 : 1
    }

    /// Headless check of what the editor adopts as you move the selection around.
    /// Screenshots need an unlocked screen; this doesn't.
    private static func debugSelection(_ args: [String]) -> Int32 {
        let options = parse(args)
        let folders = options.positional.compactMap { FolderScanner.resolve(path: $0) }
        guard !folders.isEmpty else {
            FileHandle.standardError.write(Data("--debug-selection needs folders\n".utf8))
            return 1
        }

        let state = AppState()
        state.addFolders(folders)
        state.selection = []

        func describe(_ style: FolderStyle) -> String {
            let overlay: String = switch style.overlay.kind {
            case .none: "no overlay"
            case .symbol: "symbol:\(style.overlay.symbolName)"
            case .emoji: "emoji:\(style.overlay.emoji)"
            case .text: "text:\(style.overlay.text)"
            case .image: "image"
            }
            let tint = style.tintStrength < 0.01 ? "stock blue (untinted)" : style.tint.hex
            return "\(tint), \(overlay)"
        }

        // Walk the selection across each folder, exactly as the UI does on change.
        for (index, item) in state.folders.enumerated() {
            state.selection = [item.id]
            state.syncStyleToSelection()
            let onDisk: String = if BackupStore.appliedStyle(for: item.url) != nil {
                "ours"
            } else if IconApplier.hasCustomIcon(item.url) {
                "foreign"
            } else {
                "plain"
            }
            let shows = state.previewShowsExistingIcon
                ? "the folder's existing icon (from disk)"
                : describe(state.style)
            print("select[\(index)] \(item.name.padding(toLength: 14, withPad: " ", startingAt: 0)) "
                  + "on disk: \(onDisk.padding(toLength: 9, withPad: " ", startingAt: 0)) "
                  + "shows: \(shows)")
        }

        // And a multi-select of everything.
        state.selection = Set(state.folders.map(\.id))
        state.syncStyleToSelection()
        print("select[all]                 \(String(repeating: " ", count: 24))"
              + "editor shows: \(describe(state.style))")

        return 0
    }

    // MARK: - Helpers

    private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("PNG encoding failed\n".utf8))
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            FileHandle.standardError.write(Data("Write failed: \(error)\n".utf8))
            return false
        }
    }

    private static func printUsage() {
        print("""
        FolderForge — macOS folder icon designer

        Launch with no arguments to open the app.

        COMMANDS
          --export <out.png> [style options] [--size 1024]
          --contact-sheet <out.png> [--columns 6] [--cell 180] [--finishes]
          --iconset <out.iconset> [style options]
          --apply <folder...> [style options] [scan options]
          --reset <folder...> [scan options]
          --list-presets

        SCAN OPTIONS (apply to --apply and --reset)
          --depth <n>             also include subfolders n levels down (0 = just the folder)
          --recursive             every level, however deep
          --no-root               subfolders only; leave the named folder alone
          --exclude <a,b,c>       skip names matching these globs
                                  (default: node_modules, .git, Library, *.app, …)
          --only <a,b,c>          keep only names matching these globs
          --include-hidden        don't skip dot-folders
          --limit <n>             stop after n folders (default 2000)
          --dry-run               list what would be touched, change nothing

        STYLE OPTIONS
          --preset <name>         start from a built-in preset
          --style <file.json>     start from an exported style file
          --color <#hex>          folder tint
          --color2 <#hex>         second color (enables the gradient)
          --angle <degrees>       gradient angle
          --symbol <sf.symbol>    SF Symbol overlay
          --emoji <emoji>         emoji overlay
          --text <string>         text overlay
          --image <file>          image overlay
          --finish <name>         engraved | tinted | natural | stamped | raised
          --base <name>           generic | documents | downloads | …
          --scale <0…1>           overlay size
          --opacity <0…1>         overlay opacity
          --saturation <0…2>  --brightness <-0.35…0.35>  --contrast <0.6…1.6>

        EXAMPLES
          FolderForge --apply ~/Projects --preset Code
          FolderForge --apply ~/Notes --color '#FF9F0A' --emoji 📓 --finish natural
          FolderForge --export preview.png --preset Ocean --size 512

          # every immediate subfolder of ~/Clients, but not ~/Clients itself
          FolderForge --apply ~/Clients --depth 1 --no-root --preset Work

          # the whole tree, skipping build output — check first, then commit
          FolderForge --apply ~/Code --recursive --exclude 'node_modules,dist,build' --dry-run
          FolderForge --apply ~/Code --recursive --exclude 'node_modules,dist,build' --preset Code
        """)
    }
}
