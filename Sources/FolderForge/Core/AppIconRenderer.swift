import AppKit

/// Builds FolderForge's app icon from the same native-folder pipeline used by the editor.
enum AppIconRenderer {
    static func render(pixels: Int) -> CGImage? {
        var style = FolderStyle()
        style.baseIcon = .generic
        style.separateLayerColors = true
        style.backLayer.tint = RGBA(hex: "#315E78")!
        style.backLayer.fillKind = .image
        style.backLayer.imageData = layerGradient(
            stops: ["#315E78", "#526B78", "#806B63"]
        )
        style.paperLayer = .paper()
        style.frontLayer.tint = RGBA(hex: "#417A98")!
        style.frontLayer.fillKind = .image
        style.frontLayer.imageData = layerGradient(
            stops: ["#417A98", "#627786", "#A9826F"]
        )
        style.overlay.kind = .none

        guard let folder = IconRenderer.render(style, pixels: pixels),
              let context = IconRenderer.makeContext(pixels: pixels) else { return nil }

        let scale = CGFloat(pixels) / 1024
        context.scaleBy(x: scale, y: scale)

        let tile = CGPath(
            roundedRect: CGRect(x: 42, y: 42, width: 940, height: 940),
            cornerWidth: 190,
            cornerHeight: 190,
            transform: nil
        )
        context.addPath(tile)
        context.setFillColor(NSColor(calibratedRed: 0.035, green: 0.051, blue: 0.086, alpha: 1).cgColor)
        context.fillPath()

        // The renderer returns a square canvas around Apple's folder artwork. Insets keep
        // the folder prominent while leaving the standard macOS app-icon breathing room.
        context.draw(folder, in: CGRect(x: 92, y: 92, width: 840, height: 840))

        drawBrandMark(in: context)
        return context.makeImage()
    }

    private static func drawBrandMark(in context: CGContext) {
        let main = sparkle(center: CGPoint(x: 512, y: 478), horizontal: 116, vertical: 162)
        context.saveGState()
        context.translateBy(x: 0, y: -10)
        context.addPath(main)
        context.setFillColor(NSColor(calibratedRed: 0.02, green: 0.07, blue: 0.12, alpha: 0.30).cgColor)
        context.fillPath()
        context.restoreGState()
        fill(main, in: context, colors: ["#65C8FF", "#F7FBFF", "#FFE078", "#FF6849"])

        let inner = sparkle(center: CGPoint(x: 512, y: 478), horizontal: 70, vertical: 98)
        fill(inner, in: context, colors: ["#FFFFFF", "#FFF0AF"])

        fill(sparkle(center: CGPoint(x: 368, y: 394), horizontal: 28, vertical: 28),
             in: context, colors: ["#83D7FF", "#3C9FE0"])
        fill(sparkle(center: CGPoint(x: 656, y: 392), horizontal: 35, vertical: 35),
             in: context, colors: ["#FFD17F", "#FF7058"])

        let smile = CGMutablePath()
        smile.move(to: CGPoint(x: 424, y: 326))
        smile.addCurve(to: CGPoint(x: 606, y: 325),
                       control1: CGPoint(x: 474, y: 298),
                       control2: CGPoint(x: 551, y: 297))

        context.saveGState()
        context.translateBy(x: 0, y: -7)
        context.addPath(smile)
        context.setStrokeColor(NSColor(calibratedRed: 0.02, green: 0.07, blue: 0.12, alpha: 0.30).cgColor)
        context.setLineWidth(25)
        context.setLineCap(.round)
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        context.addPath(smile)
        context.setLineWidth(20)
        context.setLineCap(.round)
        context.replacePathWithStrokedPath()
        context.clip()
        drawGradient(in: context, from: "#4E9BDC", to: "#E95542",
                     start: CGPoint(x: 408, y: 326), end: CGPoint(x: 622, y: 326))
        context.restoreGState()
    }

    private static func layerGradient(stops: [String]) -> Data? {
        let side = 1024
        guard let context = IconRenderer.makeContext(pixels: side) else { return nil }
        let colors = stops.compactMap { RGBA(hex: $0)?.cgColor }
        guard colors.count == stops.count,
              let gradient = CGGradient(
                  colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                  colors: colors as CFArray,
                  locations: [0, 0.68, 1]
              ) else { return nil }

        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 90, y: 780),
            end: CGPoint(x: 970, y: 320),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private static func sparkle(center: CGPoint, horizontal: CGFloat, vertical: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x, y: center.y + vertical))
        path.addLine(to: CGPoint(x: center.x + horizontal * 0.27, y: center.y + vertical * 0.27))
        path.addLine(to: CGPoint(x: center.x + horizontal, y: center.y))
        path.addLine(to: CGPoint(x: center.x + horizontal * 0.27, y: center.y - vertical * 0.27))
        path.addLine(to: CGPoint(x: center.x, y: center.y - vertical))
        path.addLine(to: CGPoint(x: center.x - horizontal * 0.27, y: center.y - vertical * 0.27))
        path.addLine(to: CGPoint(x: center.x - horizontal, y: center.y))
        path.addLine(to: CGPoint(x: center.x - horizontal * 0.27, y: center.y + vertical * 0.27))
        path.closeSubpath()
        return path
    }

    private static func fill(_ path: CGPath, in context: CGContext, colors: [String]) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        let cgColors = colors.compactMap { RGBA(hex: $0)?.cgColor }
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: cgColors as CFArray,
            locations: nil
        ) else { context.restoreGState(); return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: path.boundingBox.minX, y: path.boundingBox.maxY),
            end: CGPoint(x: path.boundingBox.maxX, y: path.boundingBox.minY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    private static func drawGradient(in context: CGContext, from: String, to: String,
                                     start: CGPoint, end: CGPoint) {
        guard let first = RGBA(hex: from)?.cgColor,
              let second = RGBA(hex: to)?.cgColor,
              let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [first, second] as CFArray,
                locations: [0, 1]
              ) else { return }
        context.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
}
