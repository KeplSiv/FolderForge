import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Turns a `FolderStyle` into pixels.
///
/// Pipeline, in order:
///   1. rasterize the stock folder art
///   2. recolor it with a `.color` blend (keeps every gradient, shadow and highlight intact —
///      we replace hue + saturation and keep the original luminosity, exactly how you'd
///      recolor artwork in Photoshop)
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
        guard let base = BaseIconProvider.cgImage(style.baseIcon, pixels: pixels) else { return nil }

        let colored = recolor(base: base, style: style, pixels: pixels) ?? base
        let toned = applyTone(colored, style: style) ?? colored

        guard !style.overlay.isEmpty, style.overlay.kind != .none else { return toned }
        return composite(overlay: style, onto: toned, pixels: pixels) ?? toned
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

    private static func recolor(base: CGImage, style: FolderStyle, pixels: Int) -> CGImage? {
        guard style.tintStrength > 0.001 else { return base }
        guard let ctx = makeContext(pixels: pixels) else { return nil }

        let rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        ctx.draw(base, in: rect)

        // Replace hue + saturation, keep luminosity.
        ctx.saveGState()
        ctx.setBlendMode(.color)
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

        // The `.color` blend keeps the stock artwork's brightness, so a near-black or
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

        // The blend painted over transparent pixels too; clip back to the folder silhouette.
        ctx.saveGState()
        ctx.setBlendMode(.destinationIn)
        ctx.draw(base, in: rect)
        ctx.restoreGState()

        return ctx.makeImage()
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

    // MARK: - Step 4: overlay

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
            if let fill = tint(glyph, with: style.overlayColor.nsColor) {
                ctx.setBlendMode(.softLight)
                ctx.setAlpha(alpha)
                ctx.draw(fill, in: frame)
                ctx.setBlendMode(.softLight)
                ctx.setAlpha(alpha * 0.75)
                ctx.draw(fill, in: frame)
            }

        case .tinted:
            if style.overlayShadow, let dark = tint(glyph, with: NSColor.black),
               let blurred = blur(dark, radius: 6 * unit) {
                ctx.setBlendMode(.multiply)
                ctx.setAlpha(0.22 * alpha)
                ctx.draw(blurred, in: frame.offsetBy(dx: 0, dy: -4 * unit))
            }
            if let fill = tint(glyph, with: style.overlayColor.nsColor) {
                ctx.setBlendMode(.normal)
                ctx.setAlpha(alpha)
                ctx.draw(fill, in: frame)
            }

        case .stamped:
            if let fill = tint(glyph, with: style.overlayColor.nsColor) {
                ctx.setBlendMode(.multiply)
                ctx.setAlpha(alpha)
                ctx.draw(fill, in: frame)
            }

        case .raised:
            if style.overlayShadow, let dark = tint(glyph, with: NSColor.black),
               let blurred = blur(dark, radius: 10 * unit) {
                ctx.setBlendMode(.multiply)
                ctx.setAlpha(0.35 * alpha)
                ctx.draw(blurred, in: frame.offsetBy(dx: 0, dy: -8 * unit))
            }
            if let fill = tint(glyph, with: style.overlayColor.nsColor) {
                ctx.setBlendMode(.normal)
                ctx.setAlpha(alpha)
                ctx.draw(fill, in: frame)
                ctx.setBlendMode(.plusLighter)
                ctx.setAlpha(alpha * 0.25)
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
