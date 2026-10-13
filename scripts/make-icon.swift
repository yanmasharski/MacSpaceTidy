// Draws the app icon and writes Assets/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

let SIZE: CGFloat = 1024
// Apple icon grid: the shape is 824 px inside a 1024 px canvas.
let SHAPE_INSET: CGFloat = 100
let CORNER_RADIUS: CGFloat = 185
let ICONSET = "build/AppIcon.iconset"
let OUTPUT = "Assets/AppIcon.icns"

func symbol(_ name: String, pointSize: CGFloat, colors: [NSColor]) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: colors))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}

func draw(_ image: NSImage, centerX: CGFloat, centerY: CGFloat) {
    let rect = NSRect(x: centerX - image.size.width / 2, y: centerY - image.size.height / 2, width: image.size.width, height: image.size.height)
    image.draw(in: rect)
}

let canvas = NSImage(size: NSSize(width: SIZE, height: SIZE))
canvas.lockFocus()
let shapeRect = NSRect(x: SHAPE_INSET, y: SHAPE_INSET, width: SIZE - 2 * SHAPE_INSET, height: SIZE - 2 * SHAPE_INSET)
let shape = NSBezierPath(roundedRect: shapeRect, xRadius: CORNER_RADIUS, yRadius: CORNER_RADIUS)
NSShadow().with {
    $0.shadowColor = NSColor.black.withAlphaComponent(0.3)
    $0.shadowOffset = NSSize(width: 0, height: -12)
    $0.shadowBlurRadius = 24
}.set()
NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.85, alpha: 1),
           ending: NSColor(calibratedRed: 0.20, green: 0.32, blue: 0.85, alpha: 1))!.draw(in: shape, angle: -90)
NSShadow().set()

// Disk, a free-space bar on it, and sparkles for "tidy".
draw(symbol("internaldrive.fill", pointSize: 380, colors: [.white]), centerX: SIZE / 2, centerY: SIZE / 2 - 40)
draw(symbol("sparkles", pointSize: 230, colors: [NSColor(calibratedRed: 1, green: 0.85, blue: 0.3, alpha: 1)]), centerX: SIZE / 2 + 220, centerY: SIZE / 2 + 210)
canvas.unlockFocus()

extension NSShadow {
    func with(_ setup: (NSShadow) -> Void) -> NSShadow {
        setup(self)
        return self
    }
}

let fileManager = FileManager.default
try? fileManager.removeItem(atPath: ICONSET)
try! fileManager.createDirectory(atPath: ICONSET, withIntermediateDirectories: true)
let cgImage = canvas.cgImage(forProposedRect: nil, context: nil, hints: nil)!
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.cgContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(ICONSET)/icon_\(points)x\(points)\(suffix).png"))
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", ICONSET, "-o", OUTPUT]
try! iconutil.run()
iconutil.waitUntilExit()
print("Wrote \(OUTPUT)")
