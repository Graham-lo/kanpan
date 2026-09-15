// Hntcoin 桌面图标 · 第四轮：安静版。没有图表、没有霓虹、没有彩色渐变，
// 一块底色加一个克制的符号，远看是一个色块，近看才有微妙的层次。
// 用法：swift icon-generator-v4.swift <输出目录>
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
    CGImageDestinationAddImage(d, image, nil); CGImageDestinationFinalize(d)
}
func Y(_ v: CGFloat) -> CGFloat { S - v }
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: Y(y)) }
let full = CGPath(rect: CGRect(x: 0, y: 0, width: S, height: S), transform: nil)

func linear(_ c: CGContext, _ path: CGPath, _ colors: [CGColor], _ locs: [CGFloat], _ a: CGPoint, _ b: CGPoint) {
    c.saveGState(); c.addPath(path); c.clip()
    let g = CGGradient(colorsSpace: CS, colors: colors as CFArray, locations: locs)!
    c.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
}
func radial(_ c: CGContext, _ path: CGPath, _ colors: [CGColor], _ locs: [CGFloat], _ center: CGPoint, _ r: CGFloat) {
    c.saveGState(); c.addPath(path); c.clip()
    let g = CGGradient(colorsSpace: CS, colors: colors as CFArray, locations: locs)!
    c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: r,
                         options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
}
func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: Y(y + h), width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}
func disc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - r, y: Y(cy) - r, width: r * 2, height: r * 2), transform: nil)
}

/// 细一号的 H，横梁略低于中线，看着比正中更稳
func markH(cx: CGFloat, cy: CGFloat, w legW: CGFloat = 92, h legH: CGFloat = 400,
           gap: CGFloat = 116, bar: CGFloat = 74) -> CGPath {
    let p = CGMutablePath()
    let r = legW * 0.30
    p.addPath(rrect(cx - gap / 2 - legW, cy - legH / 2, legW, legH, r))
    p.addPath(rrect(cx + gap / 2, cy - legH / 2, legW, legH, r))
    p.addPath(rrect(cx - gap / 2 - 6, cy - bar / 2 + 6, gap + 12, bar, bar * 0.28))
    return p.copy(using: nil)!
}

/// 极细的噪点，只为了让大色块不死板
func grainImage() -> CGImage {
    let n = 200
    var px = [UInt8](repeating: 0, count: n * n * 4)
    var seed: UInt64 = 0x5DEECE66D
    for i in 0..<(n * n) {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let v = UInt8((seed >> 33) & 0xff)
        px[i * 4] = v; px[i * 4 + 1] = v; px[i * 4 + 2] = v; px[i * 4 + 3] = 26
    }
    let provider = CGDataProvider(data: Data(px) as CFData)!
    return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: CS,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}
let grain = grainImage()
func addGrain(_ c: CGContext, _ a: CGFloat) {
    c.saveGState(); c.setAlpha(a); c.setBlendMode(.overlay)
    c.draw(grain, in: CGRect(x: 0, y: 0, width: S, height: S), byTiling: true)
    c.restoreGState()
}

// ============================================ L 墨底 · 黄铜 H
func iconInkBrass() -> CGImage {
    let c = newContext(S)
    linear(c, full, [rgb(0x191C22), rgb(0x0D0F13)], [0, 1], P(0, 0), P(0, S))
    radial(c, full, [rgb(0xFFFFFF, 0.05), rgb(0xFFFFFF, 0)], [0, 1], P(512, 330), 620)
    let h = markH(cx: 512, cy: 512)
    linear(c, h, [rgb(0xD8B77C), rgb(0xB08B4F)], [0, 1], P(0, 300), P(0, 720))
    addGrain(c, 0.5)
    return c.makeImage()!
}

// ============================================ M 纸底 · 墨 H
func iconPaperInk() -> CGImage {
    let c = newContext(S)
    linear(c, full, [rgb(0xF4F1EA), rgb(0xE6E2D8)], [0, 1], P(0, 0), P(0, S))
    radial(c, full, [rgb(0xFFFFFF, 0.55), rgb(0xFFFFFF, 0)], [0, 1], P(512, 360), 640)
    let h = markH(cx: 512, cy: 512)
    linear(c, h, [rgb(0x232A36), rgb(0x161B24)], [0, 1], P(0, 300), P(0, 720))
    addGrain(c, 0.45)
    return c.makeImage()!
}

// ============================================ N 同色浮雕 H
func iconToneOnTone() -> CGImage {
    let c = newContext(S)
    linear(c, full, [rgb(0x232833), rgb(0x141821)], [0, 1], P(0, 0), P(0, S))
    let h = markH(cx: 512, cy: 512)
    var down = CGAffineTransform(translationX: 0, y: -7)
    c.saveGState(); c.addPath(h.copy(using: &down)!); c.setFillColor(rgb(0x0B0E14, 0.85)); c.fillPath(); c.restoreGState()
    var up = CGAffineTransform(translationX: 0, y: 7)
    c.saveGState(); c.addPath(h.copy(using: &up)!); c.setFillColor(rgb(0xFFFFFF, 0.13)); c.fillPath(); c.restoreGState()
    linear(c, h, [rgb(0x2E3440), rgb(0x1E2430)], [0, 1], P(0, 300), P(0, 720))
    addGrain(c, 0.5)
    return c.makeImage()!
}

// ============================================ O 一个环，中间一点
func iconRing() -> CGImage {
    let c = newContext(S)
    linear(c, full, [rgb(0x1A1D24), rgb(0x0C0E13)], [0, 1], P(0, 0), P(0, S))
    radial(c, full, [rgb(0xFFFFFF, 0.05), rgb(0xFFFFFF, 0)], [0, 1], P(512, 340), 600)
    let ring = disc(512, 512, 250).copy(strokingWithWidth: 30, lineCap: .round, lineJoin: .round, miterLimit: 10)
    linear(c, ring, [rgb(0xD8B77C), rgb(0x8E6E3A)], [0, 1], P(0, 262), P(0, 762))
    let dot = disc(512, 512, 62)
    linear(c, dot, [rgb(0xE4C78F), rgb(0xB08B4F)], [0, 1], P(0, 450), P(0, 574))
    addGrain(c, 0.5)
    return c.makeImage()!
}

// ============================================ 输出
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
    (iconInkBrass(), "L · 墨底黄铜", "L-ink-brass"),
    (iconPaperInk(), "M · 纸底墨字", "M-paper-ink"),
    (iconToneOnTone(), "N · 同色浮雕", "N-tone"),
    (iconRing(), "O · 环与点", "O-ring"),
]
for (img, _, slug) in icons { save(img, "\(outDir)/icon-\(slug)-1024.png") }

let W: CGFloat = 1180, H: CGFloat = 1300
let sheet = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                      space: CS, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sheet.interpolationQuality = .high
sheet.setFillColor(rgb(0x2A2E38)); sheet.fill(CGRect(x: 0, y: 0, width: W, height: H))
let tile: CGFloat = 420, gap: CGFloat = 70, left: CGFloat = 110, top: CGFloat = 70
for (i, item) in icons.enumerated() {
    let x = left + CGFloat(i % 2) * (tile + gap)
    let yTop = top + CGFloat(i / 2) * (tile + gap + 130)
    sheet.saveGState()
    sheet.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.55))
    sheet.draw(squircle(item.0, tile), in: CGRect(x: x, y: H - yTop - tile, width: tile, height: tile))
    sheet.restoreGState()
    sheet.draw(squircle(item.0, 104), in: CGRect(x: x + tile / 2 - 52, y: H - yTop - tile - 160, width: 104, height: 104))
    text(sheet, item.1, x: x + tile / 2, y: H - yTop - tile - 48, size: 32, color: rgb(0xE9E6DE))
}
save(sheet.makeImage()!, "\(outDir)/contact-sheet-4.png")
print("done")
