import Foundation
import CoreGraphics
import CoreText
import ImageIO

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let S: CGFloat = 1024
let CS = CGColorSpaceCreateDeviceRGB()

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func newContext(_ size: CGFloat, opaque: Bool = false) -> CGContext {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let c = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                      bytesPerRow: 0, space: CS, bitmapInfo: info)!
    c.interpolationQuality = .high
    return c
}
func save(_ image: CGImage, _ path: String) {
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(d, image, nil)
    CGImageDestinationFinalize(d)
}
func Y(_ v: CGFloat) -> CGFloat { S - v }
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: Y(y)) }

func fillPath(_ c: CGContext, _ path: CGPath, colors: [CGColor], locs: [CGFloat],
              from: CGPoint, to: CGPoint) {
    c.saveGState(); c.addPath(path); c.clip()
    let g = CGGradient(colorsSpace: CS, colors: colors as CFArray, locations: locs)!
    c.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
}
func radialFill(_ c: CGContext, _ path: CGPath, colors: [CGColor], locs: [CGFloat],
                center: CGPoint, r0: CGFloat, r1: CGFloat) {
    c.saveGState(); c.addPath(path); c.clip()
    let g = CGGradient(colorsSpace: CS, colors: colors as CFArray, locations: locs)!
    c.drawRadialGradient(g, startCenter: center, startRadius: r0, endCenter: center, endRadius: r1,
                         options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
}
func disc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - r, y: Y(cy) - r, width: r * 2, height: r * 2), transform: nil)
}
func annulus(_ cx: CGFloat, _ cy: CGFloat, _ rOuter: CGFloat, _ rInner: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.addPath(disc(cx, cy, rOuter)); p.addPath(disc(cx, cy, rInner))
    return p.copy(using: nil)!   // even-odd handled at fill time
}
func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: Y(y + h), width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}

/// fine metallic grain, tiled from a small noise image
func grainImage(_ n: Int, alpha: CGFloat) -> CGImage {
    var px = [UInt8](repeating: 0, count: n * n * 4)
    var seed: UInt64 = 0x9E3779B97F4A7C15
    for i in 0..<(n * n) {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let v = UInt8((seed >> 33) & 0xff)
        let a = UInt8(CGFloat(v) * alpha / 3)
        px[i * 4] = v; px[i * 4 + 1] = v; px[i * 4 + 2] = v; px[i * 4 + 3] = a
    }
    let provider = CGDataProvider(data: Data(px) as CFData)!
    return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                   space: CS, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}
let grain = grainImage(180, alpha: 0.5)

func nightBackground(_ c: CGContext, top: UInt32, bottom: UInt32, glow: UInt32, glowAlpha: CGFloat) {
    fillPath(c, CGPath(rect: CGRect(x: 0, y: 0, width: S, height: S), transform: nil),
             colors: [rgb(top), rgb(bottom)], locs: [0, 1], from: P(0, 0), to: P(0, S))
    radialFill(c, CGPath(rect: CGRect(x: 0, y: 0, width: S, height: S), transform: nil),
               colors: [rgb(glow, glowAlpha), rgb(glow, 0)], locs: [0, 1],
               center: P(512, 430), r0: 0, r1: 700)
    // cool rim light from below, so the coin does not float in a black hole
    radialFill(c, CGPath(rect: CGRect(x: 0, y: 0, width: S, height: S), transform: nil),
               colors: [rgb(0x3E6BFF, 0.26), rgb(0x3E6BFF, 0)], locs: [0, 1],
               center: P(512, 900), r0: 0, r1: 560)
    // vignette
    radialFill(c, CGPath(rect: CGRect(x: 0, y: 0, width: S, height: S), transform: nil),
               colors: [rgb(0x000000, 0), rgb(0x000000, 0.40)], locs: [0.62, 1],
               center: P(512, 512), r0: 0, r1: 780)
}

/// the coin: rim bevel, reeded edge, recessed face
func drawCoin(_ c: CGContext, cx: CGFloat, cy: CGFloat, R: CGFloat,
              light: UInt32, mid: UInt32, dark: UInt32, deep: UInt32) {
    // cast shadow
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -26), blur: 70, color: rgb(0x000000, 0.65))
    c.addPath(disc(cx, cy, R)); c.setFillColor(rgb(deep)); c.fillPath()
    c.restoreGState()

    // rim: light from upper-left
    fillPath(c, disc(cx, cy, R), colors: [rgb(light), rgb(mid), rgb(dark), rgb(deep)],
             locs: [0, 0.38, 0.72, 1], from: P(cx - R, cy - R), to: P(cx + R, cy + R))

    // reeded edge
    c.saveGState()
    c.addPath(disc(cx, cy, R)); c.addPath(disc(cx, cy, R - 34)); c.clip(using: .evenOdd)
    let teeth = 96
    for i in 0..<teeth {
        let a0 = CGFloat(i) * 2 * .pi / CGFloat(teeth)
        let a1 = a0 + .pi / CGFloat(teeth)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: cx + cos(a0) * (R - 40), y: Y(cy) + sin(a0) * (R - 40)))
        p.addLine(to: CGPoint(x: cx + cos(a0) * (R + 4), y: Y(cy) + sin(a0) * (R + 4)))
        p.addLine(to: CGPoint(x: cx + cos(a1) * (R + 4), y: Y(cy) + sin(a1) * (R + 4)))
        p.addLine(to: CGPoint(x: cx + cos(a1) * (R - 40), y: Y(cy) + sin(a1) * (R - 40)))
        p.closeSubpath()
        c.addPath(p)
        c.setFillColor(rgb(0x000000, 0.22))
        c.fillPath()
    }
    c.restoreGState()

    // recessed face, lit from lower-right so it reads as a dish
    let fr = R - 62
    fillPath(c, disc(cx, cy, fr), colors: [rgb(dark), rgb(mid), rgb(light)],
             locs: [0, 0.55, 1], from: P(cx - fr, cy - fr), to: P(cx + fr, cy + fr))
    // inner shadow at the step
    c.saveGState()
    c.addPath(disc(cx, cy, fr)); c.clip()
    c.setShadow(offset: CGSize(width: 0, height: -14), blur: 26, color: rgb(0x3A2205, 0.85))
    c.addPath(disc(cx, cy, fr + 30)); c.setStrokeColor(rgb(0x3A2205, 0.9)); c.setLineWidth(60)
    c.strokePath()
    c.restoreGState()
    // hairline ring
    c.addPath(disc(cx, cy, fr - 16)); c.setStrokeColor(rgb(0xFFF0BC, 0.32)); c.setLineWidth(5); c.strokePath()
    // bright arc on the upper-left rim, dark arc opposite: reads as a real bevel
    c.saveGState()
    c.setLineCap(.round); c.setLineWidth(20)
    let arcHi = CGMutablePath()
    arcHi.addArc(center: CGPoint(x: cx, y: Y(cy)), radius: R - 18, startAngle: 0.62, endAngle: 2.36, clockwise: false)
    c.addPath(arcHi); c.setStrokeColor(rgb(0xFFF8DC, 0.55)); c.strokePath()
    let arcLo = CGMutablePath()
    arcLo.addArc(center: CGPoint(x: cx, y: Y(cy)), radius: R - 18, startAngle: 3.72, endAngle: 5.50, clockwise: false)
    c.addPath(arcLo); c.setStrokeColor(rgb(0x4A2D04, 0.45)); c.strokePath()
    c.restoreGState()

    // specular sweep across the upper-left
    c.saveGState()
    c.addPath(disc(cx, cy, R)); c.clip()
    c.translateBy(x: cx, y: Y(cy)); c.rotate(by: -0.55); c.translateBy(x: -cx, y: -Y(cy))
    let g = CGGradient(colorsSpace: CS, colors: [rgb(0xFFFFFF, 0), rgb(0xFFFFFF, 0.30), rgb(0xFFFFFF, 0)] as CFArray,
                       locations: [0, 0.5, 1])!
    c.clip(to: CGRect(x: cx - R, y: Y(cy) + R * 0.12, width: R * 2, height: R * 0.62))
    c.drawLinearGradient(g, start: CGPoint(x: cx - R, y: 0), end: CGPoint(x: cx + R, y: 0), options: [])
    c.restoreGState()

    // grain over the metal
    c.saveGState()
    c.addPath(disc(cx, cy, R)); c.clip()
    c.setAlpha(0.20); c.setBlendMode(.overlay)
    c.draw(grain, in: CGRect(x: 0, y: 0, width: S, height: S), byTiling: true)
    c.restoreGState()
}

/// raise a shape out of the metal: dark below, light above, gold face
func emboss(_ c: CGContext, _ shape: CGPath, faceTop: CGColor, faceBottom: CGColor,
            bounds: (top: CGFloat, bottom: CGFloat), depth: CGFloat = 13) {
    var down = CGAffineTransform(translationX: depth * 0.6, y: -depth)
    let shadow = shape.copy(using: &down)!
    c.saveGState(); c.addPath(shadow); c.setFillColor(rgb(0x4A2D04, 0.7))
    c.setShadow(offset: .zero, blur: 10, color: rgb(0x4A2D04, 0.5)); c.fillPath(); c.restoreGState()
    var up = CGAffineTransform(translationX: -depth * 0.5, y: depth * 0.9)
    let hi = shape.copy(using: &up)!
    c.saveGState(); c.addPath(hi); c.setFillColor(rgb(0xFFF6D2, 0.55)); c.fillPath(); c.restoreGState()
    fillPath(c, shape, colors: [faceTop, faceBottom], locs: [0, 1],
             from: P(0, bounds.top), to: P(0, bounds.bottom))
}

/// the mark: an "H" whose two legs are candlesticks (wicks above and below)
func candleH(cx: CGFloat, cy: CGFloat, scale: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let legW: CGFloat = 78 * scale, legH: CGFloat = 360 * scale
    let gap: CGFloat = 104 * scale
    let wickW: CGFloat = 26 * scale, wickOut: CGFloat = 64 * scale
    let barH: CGFloat = 62 * scale
    let top = cy - legH / 2, bottom = cy + legH / 2
    for sign in [-1.0, 1.0] as [CGFloat] {
        let x = cx + sign * (gap / 2 + legW / 2)
        p.addPath(rr(x - wickW / 2, top - wickOut, wickW, wickOut + 20 * scale, wickW / 2))
        p.addPath(rr(x - wickW / 2, bottom - 20 * scale, wickW, wickOut + 20 * scale, wickW / 2))
        p.addPath(rr(x - legW / 2, top, legW, legH, legW * 0.22))
    }
    p.addPath(rr(cx - gap / 2 - 6 * scale, cy - barH / 2, gap + 12 * scale, barH, barH * 0.3))
    return p.copy(using: nil)!
}

// -------------------------------------------------------------- 1. 金币 H
func iconCoinH() -> CGImage {
    let c = newContext(S)
    nightBackground(c, top: 0x0B1022, bottom: 0x05070F, glow: 0xE9A93C, glowAlpha: 0.30)
    drawCoin(c, cx: 512, cy: 508, R: 392, light: 0xFFE9A6, mid: 0xEDBA5A, dark: 0xA96F16, deep: 0x6B4108)
    let mark = candleH(cx: 512, cy: 508, scale: 1.0)
    emboss(c, mark, faceTop: rgb(0xFFF3C6), faceBottom: rgb(0xD59A28), bounds: (280, 740))
    return c.makeImage()!
}

// -------------------------------------------------------------- 2. 霓虹 H
func iconNeonH() -> CGImage {
    let c = newContext(S)
    nightBackground(c, top: 0x121A3A, bottom: 0x060912, glow: 0x3E6BFF, glowAlpha: 0.30)
    let shape = candleH(cx: 512, cy: 512, scale: 1.18)
    c.saveGState()
    c.setShadow(offset: .zero, blur: 70, color: rgb(0x14C8A0, 0.8))
    c.addPath(shape); c.setFillColor(rgb(0x18D9A8)); c.fillPath()
    c.restoreGState()
    fillPath(c, shape, colors: [rgb(0x7CFFD8), rgb(0x18C48C)], locs: [0, 1], from: P(0, 230), to: P(0, 800))
    c.saveGState()
    c.addPath(shape); c.clip()
    fillPath(c, CGPath(rect: CGRect(x: 0, y: Y(512), width: S, height: S), transform: nil),
             colors: [rgb(0xFFFFFF, 0.34), rgb(0xFFFFFF, 0)], locs: [0, 1], from: P(0, 230), to: P(0, 520))
    c.restoreGState()
    return c.makeImage()!
}

// -------------------------------------------------------------- 3. 金币 · 行情面
func iconCoinChart() -> CGImage {
    let c = newContext(S)
    nightBackground(c, top: 0x0C1124, bottom: 0x05070F, glow: 0xE9A93C, glowAlpha: 0.28)
    drawCoin(c, cx: 512, cy: 508, R: 392, light: 0xFFE9A6, mid: 0xEDBA5A, dark: 0xA96F16, deep: 0x6B4108)
    let p = CGMutablePath()
    let pts = [CGPoint(x: 330, y: 620), CGPoint(x: 430, y: 520), CGPoint(x: 512, y: 572),
               CGPoint(x: 612, y: 400), CGPoint(x: 700, y: 452)]
    p.move(to: P(pts[0].x, pts[0].y))
    for q in pts.dropFirst() { p.addLine(to: P(q.x, q.y)) }
    let line = p.copy(strokingWithWidth: 46, lineCap: .round, lineJoin: .round, miterLimit: 10)
    emboss(c, line, faceTop: rgb(0xFFF1C2), faceBottom: rgb(0xD69C2C), bounds: (380, 640))
    let dot = disc(700, 452, 46)
    emboss(c, dot, faceTop: rgb(0xFFF8DC), faceBottom: rgb(0xE0AE3C), bounds: (406, 498))
    return c.makeImage()!
}

func squircle(_ image: CGImage, _ size: CGFloat) -> CGImage {
    let c = newContext(size)
    let r = size * 0.2237
    c.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                     cornerWidth: r, cornerHeight: r, transform: nil))
    c.clip(); c.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return c.makeImage()!
}
func text(_ c: CGContext, _ s: String, x: CGFloat, y: CGFloat, size: CGFloat, color: CGColor) {
    let font = CTFontCreateWithName("PingFangSC-Semibold" as CFString, size, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [
        kCTFontAttributeName as NSAttributedString.Key: font,
        kCTForegroundColorAttributeName as NSAttributedString.Key: color]))
    let w = CTLineGetTypographicBounds(line, nil, nil, nil)
    c.textPosition = CGPoint(x: x - CGFloat(w) / 2, y: y)
    CTLineDraw(line, c)
}

let icons: [(CGImage, String, String)] = [
    (iconCoinH(), "E · 金币 H", "E-coin-h"),
    (iconNeonH(), "F · 霓虹 H", "F-neon-h"),
    (iconCoinChart(), "G · 金币行情", "G-coin-chart"),
]
for (img, _, slug) in icons {
    save(img, "\(outDir)/icon-\(slug)-1024.png")
    let small = newContext(120); small.draw(img, in: CGRect(x: 0, y: 0, width: 120, height: 120))
    save(squircle(small.makeImage()!, 120), "\(outDir)/small-\(slug)-120.png")
}

// contact sheet: three tiles + a 120px row underneath each
let W: CGFloat = 1180, H: CGFloat = 640
let sheetCtx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                         space: CS, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sheetCtx.interpolationQuality = .high
sheetCtx.setFillColor(rgb(0x1C1F2B)); sheetCtx.fill(CGRect(x: 0, y: 0, width: W, height: H))
let tile: CGFloat = 320, gap: CGFloat = 50, left: CGFloat = 95, top: CGFloat = 70
for (i, item) in icons.enumerated() {
    let x = left + CGFloat(i) * (tile + gap)
    sheetCtx.saveGState()
    sheetCtx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: rgb(0x000000, 0.6))
    sheetCtx.draw(squircle(item.0, tile), in: CGRect(x: x, y: H - top - tile, width: tile, height: tile))
    sheetCtx.restoreGState()
    sheetCtx.draw(squircle(item.0, 110), in: CGRect(x: x + tile / 2 - 55, y: H - top - tile - 140, width: 110, height: 110))
    text(sheetCtx, item.1, x: x + tile / 2, y: H - top - tile - 46, size: 30, color: rgb(0xE9E6DE))
}
save(sheetCtx.makeImage()!, "\(outDir)/contact-sheet-2.png")
print("done")
