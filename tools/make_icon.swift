// Generates AppIcon.icns: a layered chip illustration on Apple's 1024pt icon grid
// (824pt rounded body centred on a 1024pt canvas, ~100pt transparent margin for the shadow).
// Usage: swiftc -O tools/make_icon.swift -o /tmp/make_icon && /tmp/make_icon <out.icns>
import Cocoa

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

/// Superellipse approximating Apple's continuous-corner squircle.
func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let a = r.width / 2, b = r.height / 2, cx = r.midX, cy = r.midY
    let steps = 360
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func rounded(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil) }

func gradient(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func draw(_ ctx: CGContext) {
    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let body = canvas.insetBy(dx: 100, dy: 100)  // 824 x 824
    let bodyPath = squircle(body)

    // Layer 0: drop shadow under the whole icon body
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: rgb(0, 0, 0, 0.35))
    ctx.addPath(bodyPath); ctx.setFillColor(rgb(10, 20, 40)); ctx.fillPath()
    ctx.restoreGState()

    // Layer 1: background gradient, clipped to the body
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    gradient(ctx, [rgb(90, 170, 255), rgb(46, 112, 240), rgb(28, 58, 160)], from: CGPoint(x: 300, y: 924), to: CGPoint(x: 724, y: 100))
    // soft glow behind the chip
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [rgb(150, 230, 255, 0.65), rgb(150, 230, 255, 0)] as CFArray, locations: nil)!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 512), startRadius: 0, endCenter: CGPoint(x: 512, y: 512), endRadius: 400, options: [])
    // faint circuit traces
    ctx.setStrokeColor(rgb(200, 230, 255, 0.16)); ctx.setLineWidth(6); ctx.setLineCap(.round)
    for y in stride(from: 190, through: 830, by: 64) {
        ctx.move(to: CGPoint(x: 100, y: y)); ctx.addLine(to: CGPoint(x: 190, y: y))
        ctx.move(to: CGPoint(x: 834, y: y)); ctx.addLine(to: CGPoint(x: 924, y: y))
    }
    ctx.strokePath()
    ctx.restoreGState()

    // Layer 2: chip pins (6 per side), tucked under the package
    let chip = CGRect(x: 512 - 190, y: 512 - 190, width: 380, height: 380)
    let pinLen: CGFloat = 70, pinW: CGFloat = 26, pitch: CGFloat = 56
    for i in 0..<6 {
        let off = (CGFloat(i) - 2.5) * pitch
        let pins = [
            CGRect(x: 512 + off - pinW / 2, y: chip.maxY - 8, width: pinW, height: pinLen + 8),
            CGRect(x: 512 + off - pinW / 2, y: chip.minY - pinLen, width: pinW, height: pinLen + 8),
            CGRect(x: chip.minX - pinLen, y: 512 + off - pinW / 2, width: pinLen + 8, height: pinW),
            CGRect(x: chip.maxX - 8, y: 512 + off - pinW / 2, width: pinLen + 8, height: pinW),
        ]
        for p in pins {
            ctx.saveGState()
            ctx.addPath(rounded(p, 8)); ctx.clip()
            gradient(ctx, [rgb(236, 240, 247), rgb(150, 162, 184)], from: CGPoint(x: p.minX, y: p.maxY), to: CGPoint(x: p.maxX, y: p.minY))
            ctx.restoreGState()
        }
    }

    // Layer 3: chip package with its own shadow for depth
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: rgb(0, 0, 20, 0.55))
    ctx.addPath(rounded(chip, 60)); ctx.setFillColor(rgb(30, 40, 70)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(rounded(chip, 60)); ctx.clip()
    gradient(ctx, [rgb(140, 156, 200), rgb(78, 94, 140), rgb(52, 64, 104)], from: CGPoint(x: chip.minX, y: chip.maxY), to: CGPoint(x: chip.maxX, y: chip.minY))
    ctx.restoreGState()
    // package rim highlight
    ctx.addPath(rounded(chip.insetBy(dx: 2, dy: 2), 58)); ctx.setStrokeColor(rgb(200, 220, 255, 0.45)); ctx.setLineWidth(4); ctx.strokePath()

    // Layer 4: silicon die
    let die = chip.insetBy(dx: 52, dy: 52)
    ctx.saveGState()
    ctx.addPath(rounded(die, 34)); ctx.clip()
    gradient(ctx, [rgb(26, 40, 82), rgb(16, 24, 56)], from: CGPoint(x: die.minX, y: die.maxY), to: CGPoint(x: die.maxX, y: die.minY))
    ctx.restoreGState()
    ctx.addPath(rounded(die, 34)); ctx.setStrokeColor(rgb(110, 170, 255, 0.55)); ctx.setLineWidth(3); ctx.strokePath()

    // pin-1 notch on the package
    ctx.setFillColor(rgb(150, 190, 255, 0.9))
    ctx.fillEllipse(in: CGRect(x: chip.minX + 20, y: chip.maxY - 38, width: 18, height: 18))

    // Layer 5: activity pulse glyph with glow
    let mid = die.midY, l = die.minX + 28, r = die.maxX - 28
    let pulse = CGMutablePath()
    pulse.move(to: CGPoint(x: l, y: mid))
    pulse.addLine(to: CGPoint(x: l + 52, y: mid))
    pulse.addLine(to: CGPoint(x: l + 82, y: mid + 62))
    pulse.addLine(to: CGPoint(x: l + 126, y: mid - 70))
    pulse.addLine(to: CGPoint(x: l + 156, y: mid + 18))
    pulse.addLine(to: CGPoint(x: l + 176, y: mid))
    pulse.addLine(to: CGPoint(x: r, y: mid))
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 22, color: rgb(70, 255, 190, 0.9))
    ctx.addPath(pulse); ctx.setStrokeColor(rgb(90, 255, 200)); ctx.setLineWidth(15)
    ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.strokePath()
    ctx.restoreGState()
    ctx.addPath(pulse); ctx.setStrokeColor(rgb(215, 255, 240)); ctx.setLineWidth(5)
    ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.strokePath()

    // Layer 6: glossy top highlight and inner edge on the body
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    let gloss = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [rgb(255, 255, 255, 0.32), rgb(255, 255, 255, 0)] as CFArray, locations: nil)!
    ctx.drawLinearGradient(gloss, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 600), options: [])
    ctx.restoreGState()
    ctx.addPath(squircle(body.insetBy(dx: 1.5, dy: 1.5))); ctx.setStrokeColor(rgb(255, 255, 255, 0.18)); ctx.setLineWidth(3); ctx.strokePath()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    ctx.interpolationQuality = .high
    draw(ctx)
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let set = (out as NSString).deletingLastPathComponent + "/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: set)
try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(pixels: base).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base).png"))
    try! render(pixels: base * 2).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set, "-o", out]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(atPath: set)
try! render(pixels: 1024).write(to: URL(fileURLWithPath: (out as NSString).deletingPathExtension + ".png"))
