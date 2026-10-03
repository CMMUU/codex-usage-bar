import AppKit
import CryptoKit
import Foundation

// Format and size exports all come from the approved, transparent master.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let masterURL = root.appendingPathComponent("Resources/Brand/LogoMaster.png")
let source = NSBitmapImageRep(data: try Data(contentsOf: masterURL))!
var minX = source.pixelsWide
var minY = source.pixelsHigh
var maxX = 0
var maxY = 0
for y in 0..<source.pixelsHigh {
  for x in 0..<source.pixelsWide where (source.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
    minX = min(minX, x)
    maxX = max(maxX, x)
    minY = min(minY, y)
    maxY = max(maxY, y)
  }
}
let mark = source.cgImage!.cropping(
  to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!
var hashes: [String: String] = [:]

func save(_ data: Data, _ path: String) throws {
  let destination = root.appendingPathComponent(path)
  try FileManager.default.createDirectory(
    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
  try data.write(to: destination, options: .atomic)
  hashes[path] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func render(_ size: Int, occupancy: CGFloat = 0.96) -> Data {
  let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  let side = CGFloat(size) * occupancy
  let scale = side / CGFloat(max(mark.width, mark.height))
  let width = CGFloat(mark.width) * scale
  let height = CGFloat(mark.height) * scale
  context.interpolationQuality = .high
  context.draw(
    mark,
    in: CGRect(
      x: (CGFloat(size) - width) / 2, y: (CGFloat(size) - height) / 2, width: width, height: height)
  )
  return NSBitmapImageRep(cgImage: context.makeImage()!).representation(
    using: .png, properties: [:])!
}

try save(render(1024, occupancy: 0.82), "Resources/AppIcon/AppIcon-1024.png")
try save(render(256), "Sources/CodexUsageShared/Resources/BrandMark.png")
try save(render(256), "web/public/assets/brand-mark.png")
try save(render(32), "web/public/assets/favicon.png")
try save(render(180, occupancy: 0.82), "web/public/assets/apple-touch-icon.png")
try save(render(192, occupancy: 0.82), "web/public/assets/icon-192.png")
try save(render(512, occupancy: 0.82), "web/public/assets/icon-512.png")
let embedded = render(128).base64EncodedString()
try save(
  Data(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 128 128\"><image width=\"128\" height=\"128\" href=\"data:image/png;base64,\(embedded)\"/></svg>\n"
      .utf8), "web/public/assets/favicon.svg")

let iconset = root.appendingPathComponent(".build/brand/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let suffix = scale == 2 ? "@2x" : ""
    try render(size * scale, occupancy: 0.82).write(
      to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
  }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
  "-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path,
]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
try save(
  Data(contentsOf: root.appendingPathComponent("Resources/AppIcon.icns")), "Resources/AppIcon.icns")

// Render the share card from the same mark and real typography, not another logo.
let card = NSBitmapImageRep(
  bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 630,
  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: card)
NSColor(srgbRed: 0.035, green: 0.052, blue: 0.10, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 1200, height: 630).fill()
NSImage(data: render(360))!.draw(in: NSRect(x: 80, y: 140, width: 360, height: 360))
func label(
  _ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight
) {
  (text as NSString).draw(
    at: NSPoint(x: x, y: y),
    withAttributes: [
      .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
    ])
}
label("Codex Usage Bar", x: 480, y: 330, size: 58, color: .white, weight: .bold)
label(
  "Codex & Kimi quota monitor", x: 483, y: 265, size: 29,
  color: NSColor(srgbRed: 0.72, green: 0.79, blue: 0.93, alpha: 1), weight: .regular)
label(
  "macOS  /  Menu bar  /  Widgets", x: 483, y: 185, size: 23,
  color: NSColor(srgbRed: 0.52, green: 0.64, blue: 0.88, alpha: 1), weight: .medium)
NSGraphicsContext.restoreGraphicsState()
try save(card.representation(using: .png, properties: [:])!, "web/public/assets/og-cover.png")
hashes["Resources/Brand/LogoMaster.png"] = SHA256.hash(data: try Data(contentsOf: masterURL)).map {
  String(format: "%02x", $0)
}.joined()
let manifest = try JSONSerialization.data(
  withJSONObject: hashes, options: [.prettyPrinted, .sortedKeys])
try manifest.write(
  to: root.appendingPathComponent("Resources/Brand/asset-hashes.json"), options: .atomic)
print("Exported \(hashes.count) brand assets from the quota orbit master.")
