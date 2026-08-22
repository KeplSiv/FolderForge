import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Turns a `FolderStyle` into pixels.
///
/// Pipeline, in order:
///   1. rasterize the stock folder art
///   2. recolor it with a `.hue` blend so Apple's saturation, white inner edge, shading,
///      translucency and shadow remain part of the native artwork
///   3. tone pass — saturation / brightness / contrast via CoreImage
///   4. composite the overlay glyph onto the folder face
enum IconRenderer {

    static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Where the middle of the folder's front face sits, as a fraction of the canvas.
    /// The macOS folder shape is not vertically centered — the tab pushes the body down —
    /// so a naive center lands too high.
    static let faceCenter = CGPoint(x: 0.5, y: 0.435)

    // MARK: - Public

    static func render(_ style: FolderStyle, pixels: Int) -> CGImage? {
        if style.fill.kind == .icns,
           let data = style.fill.fullIconData,
           let image = NSImage(data: data) {
            return GlyphFactory.rasterizeFitting(image, side: pixels)
        }

        guard let base = renderedBase(style: style, pixels: pixels) else { return nil }

        let colored: CGImage
        if style.baseIcon == .generic,
           let layers = BaseIconProvider.nativeFolderLayers(pixels: pixels) {
            colored = renderNativeFolder(layers: layers, style: style, pixels: pixels) ?? base
        } else {
            colored = recolor(base: base, style: style, pixels: pixels) ?? base
        }
        let toned = applyTone(colored, style: style) ?? colored
        let filled: CGImage
        if style.fill.kind == .image {
            filled = compositeImageArtwork(style: style, onto: toned, mask: base, pixels: pixels) ?? toned
        } else {
            filled = toned
        }

        guard !style.overlay.isEmpty, style.overlay.kind != .none else { return filled }
        return composite(overlay: style, onto: filled, pixels: pixels) ?? filled
    }

    static func renderNSImage(_ style: FolderStyle, pixels: Int) -> NSImage {
        let side = CGFloat(pixels)
        guard let cg = render(style, pixels: pixels) else {
            return NSImage(size: NSSize(width: side, height: side))
        }
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }

    /// A multi-representation image suitable for `NSWorkspace.setIcon`. Each size is rendered
    /// independently so the glyph stays crisp at 16pt instead of being downsampled to mush.
    static func iconImage(_ style: FolderStyle) -> NSImage {
        let sizes = [16, 32, 64, 128, 256, 512, 1024]
        let image = NSImage(size: NSSize(width: 512, height: 512))
        for size in sizes {
            guard let cg = render(style, pixels: size) else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = NSSize(width: size, height: size)
            image.addRepresentation(rep)
        }
        return image
    }

    // MARK: - Step 2: recolor

    private static func renderedBase(style: FolderStyle, pixels: Int) -> CGImage? {
        if style.baseIcon == .generic,
           let layers = BaseIconProvider.nativeFolderLayers(pixels: pixels) {
            return compositeNativeFolder(layers: layers, back: layers.back,
                                         paper: layers.paper, front: layers.front, pixels: pixels)
        }
        return BaseIconProvider.cgImage(style.baseIcon, pixels: pixels)
    }

    private static func renderNativeFolder(layers: BaseIconProvider.NativeFolderLayers,
                                           style: FolderStyle,
                                           pixels: Int) -> CGImage? {
        guard style.separateLayerColors else {
            let back = recolor(base: layers.back, style: style, pixels: pixels) ?? layers.back
            let front = recolor(base: layers.front, style: style, pixels: pixels) ?? layers.front
            return compositeNativeFolder(layers: layers, back: back,
                                         paper: layers.paper, front: front, pixels: pixels)
        }

        let back = style.backLayer.enabled
            ? renderNativeLayer(base: layers.back, layer: style.backLayer,
                                style: style, pixels: pixels, isPaper: false)
            : nil
        let paper = style.paperLayer.enabled
            ? renderNativeLayer(base: layers.paper, layer: style.paperLayer,
                                style: style, pixels: pixels, isPaper: true)
            : nil
        let front = renderNativeLayer(base: layers.front, layer: style.frontLayer,
                                      style: style, pixels: pixels, isPaper: false)
        return compositeNativeFolder(layers: layers, back: back,
                                     paper: paper, front: front, pixels: pixels)
    }

    private static func renderNativeLayer(base: CGImage,
                                          layer: NativeFolderLayerStyle,
                                          style: FolderStyle,
                                          pixels: Int,
                                          isPaper: Bool) -> CGImage {
        let layerStyle = layerStyle(style, layer: layer)
        let colored = recolor(base: base, style: layerStyle, pixels: pixels,
                              blendMode: isPaper ? .multiply : .hue) ?? base
        guard layer.fillKind == .image, let data = layer.imageData,
              let image = NSImage(data: data) else { return colored }
        return compositeLayerImage(image, onto: colored, mask: base,
                                   layer: layer, pixels: pixels) ?? colored
    }

    private static func layerStyle(_ style: FolderStyle,
                                   layer: NativeFolderLayerStyle) -> FolderStyle {
        var result = style
        result.tint = layer.tint
        result.gradientEnabled = layer.gradientEnabled
        result.tintSecondary = layer.tintSecondary
        result.gradientAngle = layer.gradientAngle
        return result
    }

    private static func compositeLayerImage(_ image: NSImage,
                                            onto layerImage: CGImage,
                                            mask: CGImage,
                                            layer: NativeFolderLayerStyle,
                                            pixels: Int) -> CGImage? {
        guard let artwork = GlyphFactory.rasterizeFilling(image, side: pixels),
              let context = makeContext(pixels: pixels) else { return nil }
        let side = CGFloat(pixels)
        let full = CGRect(x: 0, y: 0, width: side, height: side)
        let scale = max(0.15, CGFloat(layer.imageScale))
        let drawSide = side * scale
        let center = CGPoint(
            x: side * (0.5 + CGFloat(layer.imageOffsetX)),
            y: side * (0.5 + CGFloat(layer.imageOffsetY))
        )
        let frame = CGRect(x: center.x - drawSide / 2, y: center.y - drawSide / 2,
                           width: drawSide, height: drawSide)

        context.draw(layerImage, in: full)
        context.saveGState()
        context.clip(to: full, mask: mask)
        if abs(layer.imageRotation) > 0.01 {
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: CGFloat(layer.imageRotation) * .pi / 180)
            context.translateBy(x: -center.x, y: -center.y)
        }
        context.setAlpha(CGFloat(layer.imageOpacity))
        context.draw(artwork, in: frame)
        context.restoreGState()

        // Reapply Apple's native lighting so an image fill still reads as the same layer.
        context.saveGState()
        context.clip(to: full, mask: mask)
        context.setBlendMode(.softLight)
        context.setAlpha(0.38)
        context.draw(layerImage, in: full)
        context.restoreGState()
        return context.makeImage()
    }

    private static func compositeNativeFolder(layers: BaseIconProvider.NativeFolderLayers,
                                              back: CGImage?,
                                              paper: CGImage?,
                                              front: CGImage?,
                                              pixels: Int) -> CGImage? {
        guard let context = makeContext(pixels: pixels) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        if let back { context.draw(back, in: rect) }
        if let paper { context.draw(paper, in: rect) }
        if let front { context.draw(front, in: rect) }
        return context.makeImage()
    }

    private static func recolor(base: CGImage, style: FolderStyle, pixels: Int,
                                blendMode: CGBlendMode = .hue) -> CGImage? {
        guard style.tintStrength > 0.001 else { return base }
        guard let ctx = makeContext(pixels: pixels) else { return nil }

        let rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        ctx.draw(base, in: rect)

        // Replace hue only. A `.color` blend also transfers saturation, which paints over
        // the low-saturation white inner edge in Apple's native folder artwork.
        ctx.saveGState()
        ctx.setBlendMode(blendMode)
        ctx.setAlpha(CGFloat(style.tintStrength))

        if style.gradientEnabled {
            drawGradient(in: ctx, rect: rect,
                         from: style.tint, to: style.tintSecondary,
                         angle: style.gradientAngle)
        } else {
            ctx.setFillColor(style.tint.cgColor)
            ctx.fill(rect)
        }
        ctx.restoreGState()

        // The `.hue` blend keeps the stock artwork's brightness, so a near-black or
        // near-white tint would come out gray. Push the luminosity the rest of the way.
        if style.matchLuminance {
            let baseBrightness = BaseIconProvider.averageBrightness(style.baseIcon)
            let target = style.gradientEnabled
                ? (style.tint.brightnessValue + style.tintSecondary.brightnessValue) / 2
                : style.tint.brightnessValue
            let delta = target - baseBrightness

            ctx.saveGState()
            if delta < 0 {
                // Multiplying by black at alpha `a` scales brightness by (1 - a), so this
                // lands exactly on the requested value.
                let amount = (-delta / max(baseBrightness, 0.001)) * style.tintStrength
                ctx.setBlendMode(.multiply)
                ctx.setAlpha(CGFloat(min(0.90, max(0, amount))))
                ctx.setFillColor(NSColor.black.cgColor)
            } else {
                // Lifting is deliberately gentler than the exact inverse: the stock artwork
                // is already near the top of the range, and normalizing by (1 - brightness)
                // blows out every bright color into white.
                let amount = delta * 1.4 * style.tintStrength
                ctx.setBlendMode(.screen)
                ctx.setAlpha(CGFloat(min(0.80, max(0, amount))))
                ctx.setFillColor(NSColor.white.cgColor)
            }
            ctx.fill(rect)
            ctx.restoreGState()
        }

        guard let recolored = ctx.makeImage() else { return nil }
        guard let finalContext = makeContext(pixels: pixels) else { return recolored }
        finalContext.draw(recolored, in: rect)

        // The blend painted over transparent pixels too; clip back to the folder silhouette.
        finalContext.saveGState()
        finalContext.setBlendMode(.destinationIn)
        finalContext.draw(base, in: rect)
        finalContext.restoreGState()

        return finalContext.makeImage()
    }

    private static func drawGradient(in ctx: CGContext, rect: CGRect,
                                     from: RGBA, to: RGBA, angle: Double) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [from.cgColor, to.cgColor] as CFArray,
            locations: [0, 1]
        ) else { return }

        let radians = CGFloat(angle) * .pi / 180
        let cx = rect.midX, cy = rect.midY
        let reach = max(rect.width, rect.height) / 2 * 1.42
        let dx = CGFloat(cos(Double(radians))) * reach
        let dy = CGFloat(sin(Double(radians))) * reach
        let start = CGPoint(x: cx - dx, y: cy - dy)
        let end = CGPoint(x: cx + dx, y: cy + dy)

        ctx.drawLinearGradient(gradient, start: start, end: end,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    // MARK: - Step 3: tone

    private static func applyTone(_ image: CGImage, style: FolderStyle) -> CGImage? {
        let neutral = abs(style.saturation - 1) < 0.001
            && abs(style.brightness) < 0.001
            && abs(style.contrast - 1) < 0.001
        if neutral { return image }

        let input = CIImage(cgImage: image)
        let filter = CIFilter.colorControls()
        filter.inputImage = input
        filter.saturation = Float(style.saturation)
        filter.brightness = Float(style.brightness)
        filter.contrast = Float(style.contrast)

        guard let output = filter.outputImage else { return image }
        return ciContext.createCGImage(output, from: input.extent)
    }

    // MARK: - Step 4: image artwork

    private static func compositeImageArtwork(style: FolderStyle,
                                              onto folder: CGImage,
                                              mask: CGImage,
                                              pixels: Int) -> CGImage? {
        guard let data = style.fill.imageData,
              let image = NSImage(data: data) else { return folder }
        guard let ctx = makeContext(pixels: pixels) else { return folder }

        let side = CGFloat(pixels)
        let full = CGRect(x: 0, y: 0, width: side, height: side)
        ctx.draw(folder, in: full)
        ctx.interpolationQuality = .high

        let artwork: CGImage?
        switch style.fill.imageContentMode {
        case .fit:
            artwork = GlyphFactory.rasterizeFitting(image, side: pixels)
        case .fill:
            artwork = GlyphFactory.rasterizeFilling(image, side: pixels)
        }
        guard let artwork else { return folder }

        let zoom = max(0.35, CGFloat(style.fillScale))
        let drawSide = side * zoom
        let cx = side * (0.5 + CGFloat(style.fillOffsetX))
        let cy = side * (0.47 + CGFloat(style.fillOffsetY))
        let frame = CGRect(x: cx - drawSide / 2, y: cy - drawSide / 2,
                           width: drawSide, height: drawSide)

        let alpha = CGFloat(style.fillOpacity)
        ctx.saveGState()
        if abs(style.fillRotation) > 0.01 {
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: CGFloat(style.fillRotation) * .pi / 180)
            ctx.translateBy(x: -cx, y: -cy)
        }
        ctx.setAlpha(alpha)
        ctx.draw(artwork, in: frame)
        ctx.restoreGState()

        // Keep the photo inside the real folder silhouette, including the tab and rounded body.
        ctx.saveGState()
        ctx.setBlendMode(.destinationIn)
        ctx.setAlpha(1)
        ctx.draw(mask, in: full)
        ctx.restoreGState()

        // Put the stock highlights/shadows back over the image so it still reads as a folder.
        ctx.saveGState()
        ctx.setBlendMode(.softLight)
        ctx.setAlpha(0.35)
        ctx.draw(folder, in: full)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setBlendMode(.sourceAtop)
        ctx.setAlpha(0.18)
        ctx.draw(folder, in: full)
        ctx.restoreGState()

        return ctx.makeImage()
    }

    // MARK: - Step 5: overlay

    private static func composite(overlay style: FolderStyle,
                                  onto folder: CGImage,
                                  pixels: Int) -> CGImage? {
        let side = CGFloat(pixels)
        guard let glyph = GlyphFactory.image(for: style, canvas: pixels) else { return folder }
        guard let ctx = makeContext(pixels: pixels) else { return folder }

        let full = CGRect(x: 0, y: 0, width: side, height: side)
        ctx.draw(folder, in: full)
        ctx.interpolationQuality = .high

        // Fit the glyph inside a square box on the folder face, preserving aspect ratio.
        let box = side * CGFloat(style.overlayScale)
        let aspect = CGFloat(glyph.width) / CGFloat(glyph.height)
        var w = box, h = box
        if aspect > 1 { h = box / aspect } else if aspect < 1 { w = box * aspect }

        let cx = side * (faceCenter.x + CGFloat(style.overlayOffsetX))
        let cy = side * (faceCenter.y + CGFloat(style.overlayOffsetY))
        let frame = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)

        ctx.saveGState()
        if abs(style.overlayRotation) > 0.01 {
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: CGFloat(style.overlayRotation) * .pi / 180)
            ctx.translateBy(x: -cx, y: -cy)
        }

        let alpha = CGFloat(style.overlayOpacity)
        let unit = side / 1024  // so offsets/blurs scale with canvas size
        let detailedArtwork = style.overlay.kind.preservesArtworkDetail

        func coloredGlyph(_ color: NSColor) -> CGImage? {
            detailedArtwork
                ? colorizePreservingLuminance(glyph, with: color)
                : tint(glyph, with: color)
        }

        switch style.finish {
        case .engraved:
            // Shadow above (light comes from the top), highlight below — reads as carved in.
            if let dark = tint(glyph, with: NSColor.black),
               let blurred = blur(dark, radius: 5 * unit) {
                ctx.setBlendMode(.multiply)
                ctx.setAlpha(0.30 * alpha)
                ctx.draw(blurred, in: frame.offsetBy(dx: 0, dy: 5 * unit))
            }
            if let light = tint(glyph, with: NSColor.white),
               let blurred = blur(light, radius: 5 * unit) {
                ctx.setBlendMode(.plusLighter)
                ctx.setAlpha(0.22 * alpha)
                ctx.draw(blurred, in: frame.offsetBy(dx: 0, dy: -5 * unit))
            }
            if let fill = coloredGlyph(style.overlayColor.nsColor) {
                ctx.setBlendMode(.softLight)
                ctx.setAlpha(alpha)
                ctx.draw(fill, in: frame)
                ctx.setBlendMode(.softLight)
                ctx.setAlpha(alpha * 0.75)
                ctx.draw(fill, in: frame)
                if detailedArtwork {
                    ctx.setBlendMode(.multiply)
                    ctx.setAlpha(alpha * 0.16)
                    ctx.draw(fill, in: frame)
                }
            }

        case .tinted:
            if style.overlayShadow, let dark = tint(glyph, with: NSColor.black),
               let blurred = blur(dark, radius: 6 * unit) {
                ctx.setBlendMode(.multiply)
                ctx.setAlpha(0.22 * alpha)
                ctx.draw(blurred, in: frame.offsetBy(dx: 0, dy: -4 * unit))
            }
            if let fill = coloredGlyph(style.overlayColor.nsColor) {
                ctx.setBlendMode(.normal)
                ctx.setAlpha(alpha)
                ctx.draw(fill, in: frame)
            }

        case .stamped:
            // Multiply with a light color is effectively invisible. Keep the selected hue,
            // but force it into a useful ink range so every saved preset remains visible.
            let ink = readableStampedInk(style.overlayColor.nsColor)
            if let fill = coloredGlyph(ink) {
                ctx.setBlendMode(.multiply)
                ctx.setAlpha(alpha * 0.92)
                ctx.draw(fill, in: frame)
            }

        case .raised:
            if style.overlayShadow, let dark = tint(glyph, with: NSColor.black),
               let blurred = blur(dark, radius: 10 * unit) {
                ctx.setBlendMode(.multiply)
                ctx.setAlpha(0.35 * alpha)
                ctx.draw(blurred, in: frame.offsetBy(dx: 0, dy: -8 * unit))
            }
            if let lowerEdge = tint(glyph, with: NSColor.black) {
                ctx.setBlendMode(.multiply)
                ctx.setAlpha(alpha * 0.22)
                ctx.draw(lowerEdge, in: frame.offsetBy(dx: 0, dy: -3 * unit))
            }
            if let upperEdge = tint(glyph, with: NSColor.white) {
                ctx.setBlendMode(.plusLighter)
                ctx.setAlpha(alpha * 0.38)
                ctx.draw(upperEdge, in: frame.offsetBy(dx: 0, dy: 3 * unit))
            }
            if let fill = coloredGlyph(style.overlayColor.nsColor) {
                ctx.setBlendMode(.normal)
                ctx.setAlpha(alpha)
                ctx.draw(fill, in: frame)
                ctx.setBlendMode(.plusLighter)
                ctx.setAlpha(alpha * 0.14)
                ctx.draw(fill, in: frame)
            }

        case .natural:
            if style.overlayShadow, let dark = tint(glyph, with: NSColor.black),
               let blurred = blur(dark, radius: 8 * unit) {
                ctx.setBlendMode(.multiply)
                ctx.setAlpha(0.30 * alpha)
                ctx.draw(blurred, in: frame.offsetBy(dx: 0, dy: -6 * unit))
            }
            ctx.setBlendMode(.normal)
            ctx.setAlpha(alpha)
            ctx.draw(glyph, in: frame)
        }

        ctx.restoreGState()

        // Anything that spilled past the folder edge gets clipped away.
        ctx.saveGState()
        ctx.setBlendMode(.destinationIn)
        ctx.setAlpha(1)
        ctx.draw(folder, in: full)
        ctx.restoreGState()

        return ctx.makeImage()
    }

    // MARK: - Helpers

    static func makeContext(pixels: Int) -> CGContext? {
        let ctx = CGContext(
            data: nil, width: pixels, height: pixels,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        ctx?.interpolationQuality = .high
        return ctx
    }

    /// Replaces every color in `image` with `color`, keeping the alpha channel as a mask.
    static func tint(_ image: CGImage, with color: NSColor) -> CGImage? {
        guard let ctx = makeContext(pixels: max(image.width, image.height)) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height)
        ctx.draw(image, in: rect)
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor((color.usingColorSpace(.sRGB) ?? color).cgColor)
        ctx.fill(rect)
        return ctx.makeImage()
    }

    /// Applies a monochrome color while retaining the source artwork's highlights, shadows
    /// and interior boundaries. Using alpha alone turns every app icon into a blank squircle.
    static func colorizePreservingLuminance(_ image: CGImage, with color: NSColor) -> CGImage? {
        guard let ctx = makeContext(pixels: max(image.width, image.height)) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height)
        ctx.draw(image, in: rect)

        ctx.saveGState()
        ctx.setBlendMode(.color)
        ctx.setFillColor((color.usingColorSpace(.sRGB) ?? color).cgColor)
        ctx.fill(rect)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setBlendMode(.destinationIn)
        ctx.draw(image, in: rect)
        ctx.restoreGState()
        return ctx.makeImage()
    }

    static func readableStampedInk(_ color: NSColor) -> NSColor {
        let source = color.usingColorSpace(.sRGB) ?? color
        let brightness = max(source.redComponent, source.greenComponent, source.blueComponent)
        guard brightness > 0.42 else { return source }
        let scale = 0.30 / max(brightness, 0.001)
        return NSColor(
            srgbRed: source.redComponent * scale,
            green: source.greenComponent * scale,
            blue: source.blueComponent * scale,
            alpha: source.alphaComponent
        )
    }

    static func blur(_ image: CGImage, radius: CGFloat) -> CGImage? {
        guard radius > 0.1 else { return image }
        let input = CIImage(cgImage: image)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = input.clampedToExtent()
        filter.radius = Float(radius)
        guard let output = filter.outputImage else { return image }
        return ciContext.createCGImage(output, from: input.extent)
    }
}
