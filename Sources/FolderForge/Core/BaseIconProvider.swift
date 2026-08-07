import AppKit
import UniformTypeIdentifiers

/// Loads the stock macOS folder artwork we recolor.
///
/// Preferred source is CoreTypes.bundle, which ships full 1024pt masters. If Apple ever
/// moves those, we fall back to `NSWorkspace.icon(for:)`, which is always available but
/// tops out at whatever the current system provides.
enum BaseIconProvider {
    private static let coreTypesPath =
        "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources"

    private static var cache: [String: CGImage] = [:]
    private static let lock = NSLock()

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

        let url = URL(fileURLWithPath: coreTypesPath)
            .appendingPathComponent(kind.resourceName)
            .appendingPathExtension("icns")

        let image = NSImage(contentsOf: url) ?? NSWorkspace.shared.icon(for: .folder)

        lock.lock(); imageCache[kind.rawValue] = image; lock.unlock()
        return image
    }

    private static var luminanceCache: [String: Double] = [:]

    /// Average HSB *brightness* (max RGB component) of the folder's opaque pixels, 0…1.
    ///
    /// A `.color` blend only transfers hue and saturation — it deliberately keeps the
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

        var rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        // Ask the NSImage for the representation closest to the size we want.
        if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: [
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
