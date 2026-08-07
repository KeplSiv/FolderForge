// Rasterizes an SVG to a transparent PNG at an exact pixel size.
//
//   swift Scripts/svg2png.swift <in.svg> <out.png> <size>
//
// Used by build.sh to render the app icon at each iconset size straight from the vector,
// rather than downsampling one master — small sizes stay crisp that way. AppKit reads SVG
// natively on macOS 13+, so this needs no third-party renderer.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 4, let size = Int(arguments[3]), size > 0 else {
    FileHandle.standardError.write(Data("usage: svg2png <in.svg> <out.png> <size>\n".utf8))
    exit(2)
}

let input = arguments[1]
let output = URL(fileURLWithPath: arguments[2])

guard let image = NSImage(contentsOfFile: input) else {
    FileHandle.standardError.write(Data("Could not read \(input)\n".utf8))
    exit(1)
}

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("Could not allocate a \(size)px bitmap\n".utf8))
    exit(1)
}
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
           from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("PNG encoding failed\n".utf8))
    exit(1)
}

do {
    try data.write(to: output, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("Write failed: \(error)\n".utf8))
    exit(1)
}
