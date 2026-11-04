import Foundation

/// Fast, explainable checks for problems that show up at Finder's 16 and 32 point sizes.
/// The preview strip remains the final visual check; these warnings catch common cases.
enum IconLegibility {
    static func warnings(for style: FolderStyle) -> [String] {
        guard !style.overlay.isEmpty else { return [] }
        var warnings: [String] = []
        if style.overlay.kind == .text && style.overlay.text.count > 2 {
            warnings.append("Text may be unreadable at 16 px. Try one or two characters.")
        }
        if style.overlayScale < 0.36 {
            warnings.append("Overlay may disappear at 16 px. Increase Icon › Placement › Size.")
        }
        if style.overlayOpacity < 0.65 {
            warnings.append("Overlay is faint at small sizes. Increase Icon › Placement › Opacity.")
        }
        if style.finish == .tinted && contrast(style.overlayColor, style.tint) < 2.5 {
            warnings.append("Ink and folder color are close. Choose lighter or darker ink.")
        }
        return warnings
    }

    static func contrast(_ first: RGBA, _ second: RGBA) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        func luminance(_ color: RGBA) -> Double {
            0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
        }
        let a = luminance(first)
        let b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
