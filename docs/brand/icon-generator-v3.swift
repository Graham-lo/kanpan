// Hntcoin 桌面图标 · 第三轮：不出现任何图表元素，只做品牌符号。
// 用法：swift icon-generator-v3.swift <输出目录>
import Foundation
import CoreGraphics
import CoreImage
import CoreText
import ImageIO

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let S: CGFloat = 1024
let CS = CGColorSpaceCreateDeviceRGB()
let ciCtx = CIContext(options: [.workingColorSpace: CS])

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

func linear(_ c: CGContext, _ path: CGPath, _ colors: [CGColor], _ locs: [CGFloat],
            _ from: CGPoint, _ to: CGPoint) {
    c.saveGState(); c.addPath(path); c.clip()
    let g = CGGradient(colorsSpace: CS, colors: colors as CFArray, locations: locs)!
    c.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
}
func radial(_ c: CGContext, _ path: CGPath?, _ colors: [CGColor], _ locs: [CGFloat],
            _ center: CGPoint, _ r1: CGFloat, r0: CGFloat = 0) {
    c.saveGState()
    if let path { c.addPath(path); c.clip() }
    let g = CGGradient(colorsSpace: CS, colors: colors as CFArray, locations: locs)!
    c.drawRadialGradient(g, startCenter: center, startRadius: r0, endCenter: center, endRadius: r1,
                         options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
}
let full = CGPath(rect: CGRect(x: 0, y: 0, width: S, height: S), transform: nil)
func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: Y(y + h), width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}
func disc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - r, y: Y(cy) - r, width: r * 2, height: r * 2), transform: nil)
}
func blur(_ image: CGImage, _ radius: Double) -> CGImage {
    let ci = CIImage(cgImage: image)
    let f = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputImageKey: ci.clampedToExtent(),
                                                         kCIInputRadiusKey: radius])!
    return ciCtx.createCGImage(f.outputImage!, from: ci.extent)!
}

// ---- 字母 H：几何造型，圆角，腰线略微收窄，不是字体直出
func markH(cx: CGFloat, cy: CGFloat, scale sc: CGFloat) -> CGPath {
    let legW = 118 * sc, legH = 470 * sc, gap = 128 * sc, barH = 96 * sc, r = 30 * sc
    let p = CGMutablePath()
    p.addPath(rrect(cx - gap / 2 - legW, cy - legH / 2, legW, legH, r))
    p.addPath(rrect(cx + gap / 2, cy - legH / 2, legW, legH, r))
    p.addPath(rrect(cx - gap / 2 - 8 * sc, cy - barH / 2, gap + 16 * sc, barH, barH * 0.26))
    return p.copy(using: nil)!
}

/// 软发光：把形状单独画一遍、模糊，再叠回去
func glow(_ c: CGContext, path: CGPath, color: CGColor, radius: Double, alpha: CGFloat) {
    let layer = newContext(S)
    layer.addPath(path); layer.setFillColor(color); layer.fillPath()
    c.saveGState(); c.setAlpha(alpha)
    c.draw(blur(layer.makeImage()!, radius), in: CGRect(x: 0, y: 0, width: S, height: S))
    c.restoreGState()
}

func grainImage(_ n: Int) -> CGImage {
    var px = [UInt8](repeating: 0, count: n * n * 4)
    var seed: UInt64 = 0xD1B54A32D192ED03
    for i in 0..<(n * n) {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let v = UInt8((seed >> 33) & 0xff)
        px[i * 4] = v; px[i * 4 + 1] = v; px[i * 4 + 2] = v; px[i * 4 + 3] = 40
    }
    let provider = CGDataProvider(data: Data(px) as CFData)!
    return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: CS,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}
let grain = grainImage(160)
func addGrain(_ c: CGContext, _ alpha: CGFloat) {
    c.saveGState(); c.setAlpha(alpha); c.setBlendMode(.overlay)
    c.draw(grain, in: CGRect(x: 0, y: 0, width: S, height: S), byTiling: true)
    c.restoreGState()
}

// ============================================================ 1. 极光 H
func iconAurora() -> CGImage {
    let bg = newContext(S)
    bg.setFillColor(rgb(0x1A0B3D)); bg.fill(CGRect(x: 0, y: 0, width: S, height: S))
    let blobs: [(UInt32, CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (0xFF2E88, 250, 250, 560, 0.95), (0x7A3CFF, 700, 180, 520, 0.95),
        (0x22D6FF, 800, 760, 560, 0.90), (0xFF9436, 200, 830, 460, 0.75),
        (0x3B1E8F, 512, 560, 420, 0.60),
    ]
    for (hex, x, y, r, a) in blobs {
        radial(bg, full, [rgb(hex, a), rgb(hex, 0)], [0, 1], P(x, y), r)
    }
    let c = newContext(S)
    c.draw(blur(bg.makeImage()!, 70), in: CGRect(x: 0, y: 0, width: S, height: S))
    // 边缘压暗，居中的光提亮
    radial(c, full, [rgb(0xFFFFFF, 0.16), rgb(0x000000, 0), rgb(0x12052E, 0.55)], [0, 0.55, 1], P(512, 470), 760)

    let h = markH(cx: 512, cy: 512, scale: 1.0)
    glow(c, path: h, color: rgb(0xFFFFFF), radius: 34, alpha: 0.5)
    linear(c, h, [rgb(0xFFFFFF), rgb(0xF0E8FF), rgb(0xD9CBFF)], [0, 0.55, 1], P(0, 270), P(0, 760))
    // 顶面高光
    c.saveGState(); c.addPath(h); c.clip()
    linear(c, full, [rgb(0xFFFFFF, 0.9), rgb(0xFFFFFF, 0)], [0, 1], P(0, 270), P(0, 470))
    c.restoreGState()
    addGrain(c, 0.10)
    return c.makeImage()!
}

// ============================================================ 2. 液态铬 H
func iconChrome() -> CGImage {
    let c = newContext(S)
    linear(c, full, [rgb(0x141821), rgb(0x05070C)], [0, 1], P(0, 0), P(0, S))
    radial(c, full, [rgb(0x6D7CFF, 0.30), rgb(0x6D7CFF, 0)], [0, 1], P(512, 330), 620)
    radial(c, full, [rgb(0xFF5EA8, 0.18), rgb(0xFF5EA8, 0)], [0, 1], P(760, 860), 520)

    let h = markH(cx: 512, cy: 512, scale: 1.02)
    glow(c, path: h, color: rgb(0x9DB4FF), radius: 46, alpha: 0.55)
    // 铬：明暗带交替，中间一条地平线
    linear(c, h, [rgb(0xFFFFFF), rgb(0xB7C6DC), rgb(0x55647A), rgb(0xE8F1FF),
                  rgb(0xFFFFFF), rgb(0x9FB0C6), rgb(0x3A4658), rgb(0xD5E2F4)],
           [0, 0.16, 0.34, 0.46, 0.56, 0.74, 0.88, 1], P(0, 262), P(0, 762))
    // 彩虹色偏，只在高光处
    c.saveGState(); c.addPath(h); c.clip(); c.setBlendMode(.overlay); c.setAlpha(0.55)
    linear(c, full, [rgb(0x60E8FF), rgb(0xFF66C4, 0.7), rgb(0xFFD36E)], [0, 0.5, 1],
           P(200, 262), P(830, 762))
    c.restoreGState()
    // 边缘勾一道冷光
    c.saveGState(); c.addPath(h); c.setLineWidth(6); c.setStrokeColor(rgb(0xFFFFFF, 0.5)); c.strokePath(); c.restoreGState()
    addGrain(c, 0.08)
    return c.makeImage()!
}

// ============================================================ 3. 宝石
func iconGem() -> CGImage {
    let c = newContext(S)
    linear(c, full, [rgb(0x160C33), rgb(0x05030F)], [0, 1], P(0, 0), P(0, S))
    radial(c, full, [rgb(0x7A3CFF, 0.34), rgb(0x7A3CFF, 0)], [0, 1], P(512, 470), 640)

    let cx: CGFloat = 512, cy: CGFloat = 512, R: CGFloat = 320
    var pts: [CGPoint] = []
    for i in 0..<6 {
        let a = -.pi / 2 + CGFloat(i) * .pi / 3
        pts.append(CGPoint(x: cx + cos(a) * R, y: cy + sin(a) * R))
    }
    let outline = CGMutablePath()
    outline.move(to: P(pts[0].x, pts[0].y))
    for q in pts.dropFirst() { outline.addLine(to: P(q.x, q.y)) }
    outline.closeSubpath()

    glow(c, path: outline, color: rgb(0x8B5CFF), radius: 60, alpha: 0.85)
    linear(c, outline, [rgb(0x9A6BFF), rgb(0x4B2BC8)], [0, 1], P(0, 190), P(0, 840))

    // 台面（内六边形）
    let tR = R * 0.52
    var tp: [CGPoint] = []
    for i in 0..<6 {
        let a = -.pi / 2 + CGFloat(i) * .pi / 3
        tp.append(CGPoint(x: cx + cos(a) * tR, y: cy - 30 + sin(a) * tR))
    }
    let table = CGMutablePath()
    table.move(to: P(tp[0].x, tp[0].y))
    for q in tp.dropFirst() { table.addLine(to: P(q.x, q.y)) }
    table.closeSubpath()

    // 冠部刻面：外顶点 → 台面两点
    for i in 0..<6 {
        let j = (i + 1) % 6
        let f = CGMutablePath()
        f.move(to: P(pts[i].x, pts[i].y)); f.addLine(to: P(pts[j].x, pts[j].y))
        f.addLine(to: P(tp[j].x, tp[j].y)); f.addLine(to: P(tp[i].x, tp[i].y))
        f.closeSubpath()
        let tint: [CGColor] = [
            [rgb(0xC9A6FF), rgb(0x7B4BE8)], [rgb(0x63E8FF), rgb(0x2F7BE0)],
            [rgb(0xFF7BD5), rgb(0x9A3CD8)], [rgb(0x8A66FF), rgb(0x3A1FA8)],
            [rgb(0x5AD7FF), rgb(0x2B54C4)], [rgb(0xE0B8FF), rgb(0x6E3ADA)],
        ][i]
        linear(c, f, tint, [0, 1], P(cx, cy - R), P(cx, cy + R))
        c.saveGState(); c.addPath(f); c.setLineWidth(3); c.setStrokeColor(rgb(0xFFFFFF, 0.22)); c.strokePath(); c.restoreGState()
    }
    linear(c, table, [rgb(0xFFFFFF, 0.95), rgb(0xC6B0FF, 0.75)], [0, 1], P(0, cy - tR - 40), P(0, cy + tR))
    c.saveGState(); c.addPath(table); c.setLineWidth(4); c.setStrokeColor(rgb(0xFFFFFF, 0.6)); c.strokePath(); c.restoreGState()

    // 星芒
    let spark = CGMutablePath()
    spark.move(to: P(700, 268)); spark.addLine(to: P(722, 318)); spark.addLine(to: P(772, 340))
    spark.addLine(to: P(722, 362)); spark.addLine(to: P(700, 412)); spark.addLine(to: P(678, 362))
    spark.addLine(to: P(628, 340)); spark.addLine(to: P(678, 318)); spark.closeSubpath()
    glow(c, path: spark, color: rgb(0xFFFFFF), radius: 22, alpha: 0.9)
    c.addPath(spark); c.setFillColor(rgb(0xFFFFFF, 0.95)); c.fillPath()
    addGrain(c, 0.08)
    return c.makeImage()!
}

// ============================================================ 4. 环
func iconOrbit() -> CGImage {
    let c = newContext(S)
    linear(c, full, [rgb(0x0E1430), rgb(0x03050C)], [0, 1], P(0, 0), P(0, S))
    radial(c, full, [rgb(0x2B4BFF, 0.28), rgb(0x2B4BFF, 0)], [0, 1], P(360, 300), 620)
    radial(c, full, [rgb(0xFFB03A, 0.22), rgb(0xFFB03A, 0)], [0, 1], P(720, 780), 520)

    let cx: CGFloat = 512, cy: CGFloat = 520, R: CGFloat = 250
    // 环（后半部分）
    let ringRect = CGRect(x: cx - 420, y: Y(cy) - 150, width: 840, height: 300)
    func ringPath() -> CGPath {
        let e = CGPath(ellipseIn: ringRect, transform: nil)
        let t = CGAffineTransform(translationX: cx, y: Y(cy)).rotated(by: -0.42)
            .translatedBy(x: -cx, y: -Y(cy))
        var tt = t
        return e.copy(using: &tt)!
    }
    let ring = ringPath().copy(strokingWithWidth: 26, lineCap: .round, lineJoin: .round, miterLimit: 10)
    glow(c, path: ring, color: rgb(0xFFC96B), radius: 40, alpha: 0.7)
    linear(c, ring, [rgb(0xFFE7B0), rgb(0xE59A2E), rgb(0x8A4F0C)], [0, 0.5, 1],
           P(cx - 400, cy - 200), P(cx + 400, cy + 200))

    // 球体：主光左上，底部一圈反射光
    let sphere = disc(cx, cy, R)
    glow(c, path: sphere, color: rgb(0x8FB3FF), radius: 54, alpha: 0.45)
    radial(c, sphere, [rgb(0xFFF3D6), rgb(0xFFC98A), rgb(0x8A4F0C), rgb(0x2A1604)],
           [0, 0.35, 0.8, 1], P(cx - 90, cy - 100), 420)
    c.saveGState(); c.addPath(sphere); c.clip()
    radial(c, nil, [rgb(0xFF9A3D, 0.55), rgb(0xFF9A3D, 0)], [0, 1], P(cx + 120, cy + 190), 260)
    c.restoreGState()
    // 高光点
    radial(c, sphere, [rgb(0xFFFFFF, 0.9), rgb(0xFFFFFF, 0)], [0, 1], P(cx - 110, cy - 120), 120)

    // 环的前半：在球体下方穿过来
    c.saveGState()
    c.addPath(CGPath(rect: CGRect(x: 0, y: 0, width: S, height: Y(cy + 30)), transform: nil)); c.clip()
    linear(c, ring, [rgb(0xFFF0C8), rgb(0xF2AE42), rgb(0xA35E10)], [0, 0.5, 1],
           P(cx - 400, cy - 200), P(cx + 400, cy + 200))
    c.restoreGState()
    addGrain(c, 0.08)
    return c.makeImage()!
}

// ============================================================ 输出
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
    (iconAurora(), "H · 极光", "H-aurora"),
    (iconChrome(), "I · 液态铬", "I-chrome"),
    (iconGem(), "J · 宝石", "J-gem"),
    (iconOrbit(), "K · 环", "K-orbit"),
]
for (img, _, slug) in icons { save(img, "\(outDir)/icon-\(slug)-1024.png") }

let W: CGFloat = 1180, H: CGFloat = 1300
let sheet = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                      space: CS, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sheet.interpolationQuality = .high
sheet.setFillColor(rgb(0x1C1F2B)); sheet.fill(CGRect(x: 0, y: 0, width: W, height: H))
let tile: CGFloat = 420, gap: CGFloat = 70, left: CGFloat = 110, top: CGFloat = 70
for (i, item) in icons.enumerated() {
    let x = left + CGFloat(i % 2) * (tile + gap)
    let yTop = top + CGFloat(i / 2) * (tile + gap + 130)
    sheet.saveGState()
    sheet.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: rgb(0x000000, 0.6))
    sheet.draw(squircle(item.0, tile), in: CGRect(x: x, y: H - yTop - tile, width: tile, height: tile))
    sheet.restoreGState()
    sheet.draw(squircle(item.0, 104), in: CGRect(x: x + tile / 2 - 52, y: H - yTop - tile - 160, width: 104, height: 104))
    text(sheet, item.1, x: x + tile / 2, y: H - yTop - tile - 48, size: 32, color: rgb(0xE9E6DE))
}
save(sheet.makeImage()!, "\(outDir)/contact-sheet-3.png")
print("done")
