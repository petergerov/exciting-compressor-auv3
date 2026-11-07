// Renders App/Assets.xcassets/AppIcon.appiconset/: the 1024 px iOS icon and
// the macOS sizes.
//
// Same composition as the jj-breeze, jj-midnight and jj-moon icons: painted
// panel, four corner screws, a meter arc with ticks, serif italic wordmark,
// three jewel lamps. They read as one product family wearing different
// finishes. The colours are hex values from GearTheme.swift; if a palette
// there changes, change these with it.
//
//   swift icon/make-icon.swift [output-dir]
//
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024

// MARK: - GearPalette.tweed
// The panel is the Tweed front-plate paint rather than its oxblood sub-plate:
// jj-midnight already wears oxblood, and the sand lacquer is what this
// editor opens in.
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: a)
}

let panelTop = rgb(0x9c7a48)      // Tweed paint (0xc2a068 → 0x8a6b3c), pulled down so the cream wordmark keeps its contrast
let panelBottom = rgb(0x5a4426)
let weaveLight: UInt32 = 0xd8bc8a
let weaveDark: UInt32 = 0x1a0c0a
let brass = rgb(0xf0c96a)
let brassDim = rgb(0x7f6730)
let cream = rgb(0xf7eeda)
let metalLight = rgb(0xf0e2c2)
let metalMid = rgb(0xb99a5e)
let metalDark = rgb(0x3a2d18)
let lampGreen = rgb(0x8fd96a)
let lampAmber = rgb(0xf5bd45)
let lampRed = rgb(0xff4030)

let cs = CGColorSpaceCreateDeviceRGB()

// Opaque: the App Store rejects an iOS icon with an alpha channel.
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                          bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("could not create bitmap context")
}

// MARK: - Panel paint
let paint = CGGradient(colorsSpace: cs, colors: [panelTop, panelBottom] as CFArray,
                       locations: [0, 1])!
ctx.drawLinearGradient(paint, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0),
                       options: [])

// MARK: - Weave
// Lacquered cloth, not a flat painted panel: two sets of diagonal threads
// crossing at right angles. Kept very low contrast. At 40 pt it should read
// as texture, never as stripes.
ctx.saveGState()
let threadSpacing: CGFloat = 9
for direction in [CGFloat(1), CGFloat(-1)] {
    ctx.setLineWidth(3)
    var offset: CGFloat = -size
    while offset < size * 2 {
        let light = Int(offset / threadSpacing) % 2 == 0
        ctx.setStrokeColor(light ? rgb(weaveLight, 0.040) : rgb(weaveDark, 0.055))
        ctx.beginPath()
        ctx.move(to: CGPoint(x: offset, y: 0))
        ctx.addLine(to: CGPoint(x: offset + direction * size, y: size))
        ctx.strokePath()
        offset += threadSpacing
    }
}
ctx.restoreGState()

// MARK: - Vignette
// Pulls the corners down so the wordmark and arc sit in the light.
let vignette = CGGradient(colorsSpace: cs,
                          colors: [rgb(0x000000, 0), rgb(0x000000, 0.42)] as CFArray,
                          locations: [0.45, 1])!
ctx.drawRadialGradient(vignette,
                       startCenter: CGPoint(x: size / 2, y: size * 0.56), startRadius: 0,
                       endCenter: CGPoint(x: size / 2, y: size * 0.56), endRadius: size * 0.78,
                       options: [.drawsAfterEndLocation])

// MARK: - Corner screws
func screw(at p: CGPoint, radius r: CGFloat, slotAngle: CGFloat) {
    let head = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)

    ctx.saveGState()
    ctx.addEllipse(in: head)
    ctx.clip()
    let body = CGGradient(colorsSpace: cs, colors: [metalLight, metalMid, metalDark] as CFArray,
                          locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(body,
                           start: CGPoint(x: p.x - r, y: p.y + r),
                           end: CGPoint(x: p.x + r, y: p.y - r), options: [])
    ctx.restoreGState()

    ctx.setStrokeColor(rgb(0x000000, 0.55))
    ctx.setLineWidth(2)
    ctx.strokeEllipse(in: head)

    // Slot, rotated so the screws don't look machine-placed.
    ctx.saveGState()
    ctx.translateBy(x: p.x, y: p.y)
    ctx.rotate(by: slotAngle)
    ctx.setFillColor(rgb(0x120a06, 0.85))
    ctx.fill(CGRect(x: -r * 0.72, y: -r * 0.14, width: r * 1.44, height: r * 0.28))
    ctx.setFillColor(rgb(weaveLight, 0.30))
    ctx.fill(CGRect(x: -r * 0.72, y: r * 0.10, width: r * 1.44, height: r * 0.08))
    ctx.restoreGState()
}

let screwInset: CGFloat = 124
let screwRadius: CGFloat = 23
screw(at: CGPoint(x: screwInset, y: size - screwInset), radius: screwRadius, slotAngle: 0.55)
screw(at: CGPoint(x: size - screwInset, y: size - screwInset), radius: screwRadius, slotAngle: -0.7)
screw(at: CGPoint(x: screwInset, y: screwInset), radius: screwRadius, slotAngle: -0.35)
screw(at: CGPoint(x: size - screwInset, y: screwInset), radius: screwRadius, slotAngle: 0.85)

// MARK: - Meter arc
// Geometry is the same as the sibling icons, so they sit side by side in a
// home screen folder without one looking redrawn.
let arcCenter = CGPoint(x: size / 2, y: size - 572)
let arcRadius: CGFloat = 332
let startAngle = CGFloat.pi * (202.0 / 180.0)
let endAngle = CGFloat.pi * (338.0 / 180.0)

func strokeArc(radius: CGFloat, width: CGFloat, color: CGColor) {
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.beginPath()
    // Negative angles because the context's origin is bottom-left but the
    // geometry above is written top-down.
    ctx.addArc(center: arcCenter, radius: radius,
               startAngle: -startAngle, endAngle: -endAngle, clockwise: true)
    ctx.strokePath()
}

strokeArc(radius: arcRadius, width: 30, color: rgb(0x000000, 0.30))   // shadow under the arc
strokeArc(radius: arcRadius, width: 22, color: brassDim)              // dim outer edge
strokeArc(radius: arcRadius, width: 14, color: brass)                 // lit face

// Ticks, radiating outward past the arc.
ctx.setLineCap(.butt)
ctx.setLineWidth(9)
ctx.setStrokeColor(rgb(weaveLight, 0.62))
let tickCount = 9
for i in 0..<tickCount {
    let t = CGFloat(i) / CGFloat(tickCount - 1)
    let angle = startAngle + (endAngle - startAngle) * t
    let dx = cos(angle), dy = -sin(angle)
    let inner = arcRadius + 28, outer = arcRadius + 64
    ctx.beginPath()
    ctx.move(to: CGPoint(x: arcCenter.x + dx * inner, y: arcCenter.y + dy * inner))
    ctx.addLine(to: CGPoint(x: arcCenter.x + dx * outer, y: arcCenter.y + dy * outer))
    ctx.strokePath()
}

// MARK: - Wordmark
// Georgia Bold Italic, as in the sibling icons. "Exciting Compressor" on one
// line would shrink to about 75 pt and turn to mush at home-screen size, so
// it is stacked on two lines. Both lines share one size, set by the wider.
let lines = ["Exciting", "Compressor"]
let maxFontSize: CGFloat = 150
let wordmarkMaxWidth: CGFloat = 720
let lineBaselines: [CGFloat] = [566, 690]   // top-down, like the arc geometry
let lineHeight = lineBaselines[1] - lineBaselines[0]

func makeLine(_ string: String, font: CTFont, colour: CGColor? = nil) -> CTLine {
    // CoreText keys rather than the AppKit/UIKit ones: this script links
    // neither.
    var attrs: [NSAttributedString.Key: Any] = [kCTFontAttributeName as NSAttributedString.Key: font]
    if let colour {
        attrs[kCTForegroundColorAttributeName as NSAttributedString.Key] = colour
    }
    return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attrs))
}

func wordmarkFont() -> CTFont {
    var pt = maxFontSize
    while pt > 40 {
        let candidate = CTFontCreateWithName("Georgia-BoldItalic" as CFString, pt, nil)
        let widest = lines
            .map { CTLineGetBoundsWithOptions(makeLine($0, font: candidate), .useOpticalBounds).width }
            .max() ?? 0
        // The ascent must also fit between the baselines, or the
        // descender of the first line collides with the second.
        if widest <= wordmarkMaxWidth && CTFontGetAscent(candidate) <= lineHeight {
            return candidate
        }
        pt -= 1
    }
    return CTFontCreateWithName("Georgia-BoldItalic" as CFString, 40, nil)
}

let font = wordmarkFont()

func drawWordmark(dy: CGFloat, colour: CGColor) {
    for (string, baseline) in zip(lines, lineBaselines) {
        let line = makeLine(string, font: font, colour: colour)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.textPosition = CGPoint(x: (size - bounds.width) / 2 - bounds.minX,
                                   y: size - baseline + dy)
        CTLineDraw(line, ctx)
    }
}

drawWordmark(dy: -6, colour: rgb(0x120a06, 0.55))   // drop shadow
drawWordmark(dy: 0, colour: cream)

// MARK: - Jewel lamps
func lamp(at p: CGPoint, radius r: CGFloat, colour: CGColor) {
    // Bezel
    ctx.saveGState()
    let bezel = CGRect(x: p.x - r - 5, y: p.y - r - 5, width: (r + 5) * 2, height: (r + 5) * 2)
    ctx.addEllipse(in: bezel)
    ctx.clip()
    let ring = CGGradient(colorsSpace: cs, colors: [metalLight, metalDark] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(ring,
                           start: CGPoint(x: bezel.minX, y: bezel.maxY),
                           end: CGPoint(x: bezel.maxX, y: bezel.minY), options: [])
    ctx.restoreGState()

    // Glass
    ctx.setFillColor(colour)
    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))

    // Highlight, offset up-left so the lamps read as domed
    ctx.setFillColor(rgb(0xffffff, 0.42))
    ctx.fillEllipse(in: CGRect(x: p.x - r * 0.52, y: p.y + r * 0.06,
                               width: r * 0.62, height: r * 0.52))
}

let lampY = size - 800
let lampRadius: CGFloat = 23
lamp(at: CGPoint(x: size / 2 - 82, y: lampY), radius: lampRadius, colour: lampGreen)
lamp(at: CGPoint(x: size / 2, y: lampY), radius: lampRadius, colour: lampAmber)
lamp(at: CGPoint(x: size / 2 + 82, y: lampY), radius: lampRadius, colour: lampRed)

guard let artwork = ctx.makeImage() else { fatalError("could not render") }

// MARK: - macOS variant
// macOS doesn't mask icons the way iOS does: the file carries its own
// rounded body, transparent margin and shadow. Apple's grid puts an 824 px
// body on the 1024 px canvas.
func macIcon(pixels: Int) -> CGImage {
    let s = CGFloat(pixels)
    guard let mac = CGContext(data: nil, width: pixels, height: pixels,
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("could not create macOS bitmap context")
    }
    mac.interpolationQuality = .high
    mac.scaleBy(x: s / size, y: s / size)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    mac.saveGState()
    mac.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: rgb(0x000000, 0.35))
    mac.addPath(shape)
    mac.setFillColor(panelBottom)
    mac.fillPath()
    mac.restoreGState()

    mac.saveGState()
    mac.addPath(shape)
    mac.clip()
    mac.draw(artwork, in: body)
    mac.restoreGState()

    guard let image = mac.makeImage() else { fatalError("could not render macOS icon") }
    return image
}

// MARK: - Write
let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "App/Assets.xcassets/AppIcon.appiconset"

func write(_ image: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString,
                                                     1, nil) else {
        fatalError("could not open \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
    print("wrote \(url.path)")
}

write(artwork, "AppIcon.png")
for points in [16, 32, 128, 256, 512] {
    write(macIcon(pixels: points), "mac-\(points).png")
    write(macIcon(pixels: points * 2), "mac-\(points)@2x.png")
}
