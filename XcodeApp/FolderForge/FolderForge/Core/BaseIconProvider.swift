import AppKit
import UniformTypeIdentifiers

/// Loads the stock macOS folder artwork we recolor.
///
/// Preferred source is CoreTypes.bundle, which ships full 1024pt masters. If Apple ever
/// moves those, we fall back to `NSWorkspace.icon(for:)`, which is always available but
/// tops out at whatever the current system provides.
enum BaseIconProvider {
    struct NativeFolderLayers {
        let back: CGImage
        let paper: CGImage
        let front: CGImage
    }

    private static let coreTypesPath =
        "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources"

    private static var cache: [String: CGImage] = [:]
    private static var layerCache: [String: NativeFolderLayers] = [:]
    private static let lock = NSLock()

    /// Apple's current folder artwork is stored as three separately composited layers.
    /// Keeping the paper separate lets tinting preserve Finder's exact inset and shadow.
    static func nativeFolderLayers(pixels: Int) -> NativeFolderLayers? {
        let key = "native-layers@\(pixels)"
        lock.lock()
        if let hit = layerCache[key] { lock.unlock(); return hit }
        lock.unlock()

        guard let bundle = Bundle(path: "/System/Library/CoreServices/CoreTypes.bundle") else {
            return nil
        }
        let assetSize: Int
        switch pixels {
        case ...16: assetSize = 16
        case ...64: assetSize = 32
        case ...128: assetSize = 128
        case ...256: assetSize = 256
        default: assetSize = 512
        }

        func layer(_ name: String) -> CGImage? {
            let resource = NSImage.Name("FolderComponent_\(name)/image_\(assetSize)")
            guard let image = bundle.image(forResource: resource) else { return nil }
            return rasterize(image, pixels: pixels)
        }

        guard let back = layer("BackFlap"),
              let paper = layer("PaperSheet"),
              let front = layer("FrontFlap") else {
            return nil
        }
        let result = NativeFolderLayers(back: back, paper: paper, front: front)
        lock.lock(); layerCache[key] = result; lock.unlock()
        return result
    }

    /// A square CGImage of the stock folder at `pixels` × `pixels`.
    static func cgImage(_ kind: BaseIconKind, pixels: Int) -> CGImage? {
        let key = "\(kind.rawValue)@\(pixels)"
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        guard let source = nsImage(kind) else { return nil }
        guard let rendered = rasterize(source, pixels: pixels) else { return nil }

        lock.lock(); cache[key] = rendered; lock.unlock()
        return rendered
    }

    private static var imageCache: [String: NSImage] = [:]

    private static func nsImage(_ kind: BaseIconKind) -> NSImage? {
        lock.lock()
        if let hit = imageCache[kind.rawValue] { lock.unlock(); return hit }
        lock.unlock()

        let image: NSImage?
        if kind == .generic {
            // Ask Launch Services for the current system folder artwork so the default shape
            // matches Finder on the version of macOS the user is running.
            image = NSWorkspace.shared.icon(for: .folder)
        } else {
            let url = URL(fileURLWithPath: coreTypesPath)
                .appendingPathComponent(kind.resourceName)
                .appendingPathExtension("icns")
            image = NSImage(contentsOf: url) ?? NSWorkspace.shared.icon(for: .folder)
        }

        lock.lock(); imageCache[kind.rawValue] = image; lock.unlock()
        return image
    }

    private static var luminanceCache: [String: Double] = [:]

    /// Average HSB *brightness* (max RGB component) of the folder's opaque pixels, 0…1.
    ///
    /// A `.hue` blend transfers hue while deliberately keeping the backdrop's brightness.
    /// backdrop's brightness. That's what makes the recolor look native, but it also means
    /// picking near-black or near-white gives you a gray folder. The renderer uses this
    /// number to work out how far to push the folder's brightness.
    ///
    /// Deliberately *not* perceived luminance: a fully saturated red has a luminance of only
    /// 0.21, so matching luminance would render `#FF375F` as a near-black folder even though
    /// nobody would call that color dark. HSB brightness matches the intuition.
    static func averageBrightness(_ kind: BaseIconKind) -> Double {
        lock.lock()
        if let hit = luminanceCache[kind.rawValue] { lock.unlock(); return hit }
        lock.unlock()

        let side = 64
        var result = 0.5

        if let image = cgImage(kind, pixels: side) {
            var pixels = [UInt8](repeating: 0, count: side * side * 4)
            pixels.withUnsafeMutableBytes { buffer in
                guard let ctx = CGContext(
                    data: buffer.baseAddress, width: side, height: side,
                    bitsPerComponent: 8, bytesPerRow: side * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            }

            var total = 0.0
            var weight = 0.0
            for index in stride(from: 0, to: pixels.count, by: 4) {
                let alpha = Double(pixels[index + 3]) / 255
                guard alpha > 0.35 else { continue }
                // Un-premultiply so translucent edge pixels don't drag the average down.
                let r = Double(pixels[index]) / 255 / alpha
                let g = Double(pixels[index + 1]) / 255 / alpha
                let b = Double(pixels[index + 2]) / 255 / alpha
                total += max(r, max(g, b)) * alpha
                weight += alpha
            }
            if weight > 0 { result = min(1, max(0, total / weight)) }
        }

        lock.lock(); luminanceCache[kind.rawValue] = result; lock.unlock()
        return result
    }

    /// Draws an NSImage into a fixed-size sRGB bitmap, preserving aspect ratio and alpha.
    private static func rasterize(_ image: NSImage, pixels: Int) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: pixels, height: pixels,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high

        // Finder's folder icon has hand-tuned representations for each display size. Select
        // the closest one explicitly instead of letting AppKit flatten the largest master.
        let representation = image.representations
            .filter { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }
            .min { lhs, rhs in
                abs(lhs.pixelsWide - pixels) < abs(rhs.pixelsWide - pixels)
            }
        var rect = CGRect(
            origin: .zero,
            size: representation?.size ?? CGSize(width: pixels, height: pixels)
        )
        if let cg = representation?.cgImage(
            forProposedRect: &rect,
            context: nil,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        ) ?? image.cgImage(forProposedRect: &rect, context: nil, hints: [
            .interpolation: NSImageInterpolation.high.rawValue
        ]) {
            let aspect = CGFloat(cg.width) / CGFloat(cg.height)
            var draw = CGRect(x: 0, y: 0, width: pixels, height: pixels)
            if aspect > 1 {
                draw.size.height = CGFloat(pixels) / aspect
                draw.origin.y = (CGFloat(pixels) - draw.height) / 2
            } else if aspect < 1 {
                draw.size.width = CGFloat(pixels) * aspect
                draw.origin.x = (CGFloat(pixels) - draw.width) / 2
            }
            ctx.draw(cg, in: draw)
        }

        return ctx.makeImage()
    }
}
