import AppKit
import CoreText

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let tile = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 205, yRadius: 205)
        NSGradient(starting: NSColor(srgbRed: 0.23, green: 0.62, blue: 0.95, alpha: 1),
                   ending: NSColor(srgbRed: 0.18, green: 0.32, blue: 0.78, alpha: 1))!.draw(in: tile, angle: -70)
        NSColor.white.withAlphaComponent(0.94).setFill()
        NSBezierPath(roundedRect: NSRect(x: 275, y: 212, width: 474, height: 566), xRadius: 60, yRadius: 60).fill()
        NSColor(srgbRed: 0.13, green: 0.30, blue: 0.67, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 402, y: 728, width: 220, height: 95), xRadius: 35, yRadius: 35).fill()
        let text = "10" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 255, weight: .bold),
            .foregroundColor: NSColor(srgbRed: 0.18, green: 0.40, blue: 0.80, alpha: 1)
        ]
        let bounds = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (1024 - bounds.width) / 2, y: 335), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}

// ICNS supports PNG payloads directly; assemble without depending on iconutil's conversion service.
func bigEndian(_ value: Int) -> Data {
    var word = UInt32(value).bigEndian
    return withUnsafeBytes(of: &word) { Data($0) }
}
var payload = Data()
for (type, filename) in [
    ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"),
    ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic14", "icon_256x256@2x.png")
] {
    let png = try Data(contentsOf: directory.appendingPathComponent(filename))
    payload.append(Data(type.utf8))
    payload.append(bigEndian(png.count + 8))
    payload.append(png)
}
var icns = Data("icns".utf8)
icns.append(bigEndian(payload.count + 8))
icns.append(payload)
try icns.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
