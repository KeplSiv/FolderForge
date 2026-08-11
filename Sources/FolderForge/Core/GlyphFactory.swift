import AppKit

/// Rasterizes whatever the user chose as an overlay — SF Symbol, emoji, text or a dropped
/// image — into a transparent square the renderer can composite.
enum GlyphFactory {

    static func image(for style: FolderStyle, canvas: Int) -> CGImage? {
        // Render the glyph generously so the compositor downsamples rather than upscales.
        let side = max(64, Int(Double(canvas) * max(0.2, style.overlayScale) * 1.6))

        switch style.overlay.kind {
        case .none:
            return nil
        case .symbol:
            return symbol(style.overlay.symbolName, weight: style.symbolWeight, side: side)
        case .emoji:
            return text(style.overlay.emoji, side: side, font: emojiFont(size: CGFloat(side) * 0.82))
        case .text:
            let weight = style.symbolWeight.nsWeight
            let font = NSFont.systemFont(ofSize: CGFloat(side) * 0.6, weight: weight)
            return text(style.overlay.text, side: side, font: font)
        case .appIcon:
            guard let data = style.overlay.imageData,
                  let image = NSImage(data: data)
            else { return nil }
            return rasterizeFitting(image, side: side)
        case .image, .icns:
            return nil
        }
    }

    // MARK: - SF Symbols

    static func symbol(_ name: String,
                       weight: FolderStyle.SymbolWeight,
                       side: Int) -> CGImage? {
        guard !name.isEmpty,
              let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        else { return nil }

        let config = NSImage.SymbolConfiguration(
            pointSize: CGFloat(side) * 0.72,
            weight: weight.nsWeight,
            scale: .large
        )
        let configured = symbol.withSymbolConfiguration(config) ?? symbol
        configured.isTemplate = true

        // Draw the template in white so the alpha channel carries the shape.
        return rasterizeFitting(configured, side: side, tintTemplate: .white)
    }

    /// True if the running system knows this symbol — used to filter the picker so we never
    /// show a tile that renders as nothing.
    static func symbolExists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    // MARK: - Text & emoji

    static func emojiFont(size: CGFloat) -> NSFont {
        NSFont(name: "Apple Color Emoji", size: size) ?? NSFont.systemFont(ofSize: size)
    }

    private static func text(_ string: String, side: Int, font: NSFont) -> CGImage? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]

        var attributed = NSAttributedString(string: trimmed, attributes: attributes)
        var bounds = attributed.size()

        // Shrink to fit — long text and wide emoji sequences would otherwise overflow.
        let target = CGFloat(side) * 0.92
        if bounds.width > target || bounds.height > target {
            let scale = min(target / max(bounds.width, 1), target / max(bounds.height, 1))
            let resized = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * scale)
                ?? NSFont.systemFont(ofSize: font.pointSize * scale)
            attributes[.font] = resized
            attributed = NSAttributedString(string: trimmed, attributes: attributes)
            bounds = attributed.size()
        }

        guard let ctx = IconRenderer.makeContext(pixels: side) else { return nil }
        let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics

        let origin = CGPoint(x: (CGFloat(side) - bounds.width) / 2,
                             y: (CGFloat(side) - bounds.height) / 2)
        attributed.draw(at: origin)

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    // MARK: - Arbitrary images

    /// Draws an NSImage centered in a transparent square, scaled to fit.
    static func rasterizeFitting(_ image: NSImage,
                                 side: Int,
                                 tintTemplate: NSColor? = nil) -> CGImage? {
        guard let ctx = IconRenderer.makeContext(pixels: side) else { return nil }
        let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics

        let source = image.size
        guard source.width > 0, source.height > 0 else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }

        let scale = min(CGFloat(side) / source.width, CGFloat(side) / source.height)
        let drawn = NSSize(width: source.width * scale, height: source.height * scale)
        let frame = NSRect(x: (CGFloat(side) - drawn.width) / 2,
                           y: (CGFloat(side) - drawn.height) / 2,
                           width: drawn.width, height: drawn.height)

        if let tintTemplate, image.isTemplate {
            tintTemplate.set()
            image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
            ctx.setBlendMode(.sourceIn)
            ctx.setFillColor(tintTemplate.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        } else {
            image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
        }

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// Draws an NSImage into a square, scaled to cover it. Used when photos become the folder
    /// artwork rather than a small overlay glyph.
    static func rasterizeFilling(_ image: NSImage, side: Int) -> CGImage? {
        guard let ctx = IconRenderer.makeContext(pixels: side) else { return nil }
        let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics

        let source = image.size
        guard source.width > 0, source.height > 0 else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }

        let scale = max(CGFloat(side) / source.width, CGFloat(side) / source.height)
        let drawn = NSSize(width: source.width * scale, height: source.height * scale)
        let frame = NSRect(x: (CGFloat(side) - drawn.width) / 2,
                           y: (CGFloat(side) - drawn.height) / 2,
                           width: drawn.width, height: drawn.height)
        image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// Normalizes any dropped/imported image to PNG bytes for storage in a style.
    static func pngData(from image: NSImage) -> Data? {
        var rect = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = image.size
        return rep.representation(using: .png, properties: [:])
    }

    /// Produces a predictable, high-resolution PNG from images whose logical size may be small.
    static func pngData(from image: NSImage, side: Int) -> Data? {
        guard let cg = rasterizeFitting(image, side: side) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = NSSize(width: side, height: side)
        return rep.representation(using: .png, properties: [:])
    }
}
