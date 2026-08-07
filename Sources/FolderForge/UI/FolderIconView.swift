import AppKit
import SwiftUI

/// Memoizes rendered icons so scrolling a gallery of 30 presets doesn't re-run the whole
/// pipeline on every frame.
enum PreviewCache {
    private static let cache: NSCache<NSNumber, NSImage> = {
        let cache = NSCache<NSNumber, NSImage>()
        cache.countLimit = 400
        return cache
    }()

    static func image(_ style: FolderStyle, pixels: Int) -> NSImage {
        var hasher = Hasher()
        hasher.combine(style.renderKey)
        hasher.combine(pixels)
        let key = NSNumber(value: hasher.finalize())

        if let hit = cache.object(forKey: key) { return hit }
        let image = IconRenderer.renderNSImage(style, pixels: pixels)
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Draws a style at a given point size, rendering at the backing-store resolution.
struct FolderIconView: View {
    var style: FolderStyle
    var side: CGFloat

    var body: some View {
        Image(nsImage: PreviewCache.image(style, pixels: pixels))
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
    }

    /// Round up to a sensible bucket so tiny drags don't invalidate the cache constantly.
    private var pixels: Int {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let wanted = Int((side * scale).rounded())
        let buckets = [32, 64, 128, 192, 256, 384, 512, 768, 1024]
        return buckets.first { $0 >= wanted } ?? 1024
    }
}

/// A folder as Finder would draw it: icon above a rounded, tinted name label.
struct FinderTile: View {
    var style: FolderStyle
    var name: String
    var side: CGFloat
    var selected = false

    var body: some View {
        VStack(spacing: 6) {
            FolderIconView(style: style, side: side)
            Text(name)
                .font(.system(size: max(9, min(13, side * 0.09))))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selected ? Color.accentColor : .clear)
                }
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(maxWidth: side * 1.35)
        }
    }
}
