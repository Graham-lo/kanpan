// Hntcoin 桌面图标 · 第五轮：纯形状。不取字母、不画行情、不附寓意，
// 就是四个安静的几何构图，靠比例和明暗关系立住。
// 用法：swift icon-generator-v5.swift <输出目录>
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
func newContext(_ size: CGFloat) -> CGContext {
    let c = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                      bytesPerRow: 0, space: CS,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
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
func disc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - r, y: Y(cy) - r, width: r * 2, height: r * 2), transform: nil)
}
func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: Y(y + h), width: w, height: h),
           cornerWidth: r, cornerHeight: r, transform: nil)
}
func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
    let p = CGMutablePath()
    p.move(to: P(pts[0].0, pts[0].1))
    for q in pts.dropFirst() { p.addLine(to: P(q.0, q.1)) }
    p.closeSubpath()
    return p
}

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

// ======================================== P 折：一道斜向的折面
func iconFold() -> CGImage {
    let c = newContext(S)
    linear(c, full, [rgb(0x3A4358), rgb(0x272E3D)], [0, 1], P(0, 0), P(0, 560))
    // 下半折面，比上半暗好几档，小尺寸下靠这个反差立住
    let lower = poly([(0, 380), (S, 640), (S, S), (0, S)])
    linear(c, lower, [rgb(0x11151D), rgb(0x080A0F)], [0, 1], P(0, 380), P(0, S))
    // 折线上一条细高光
    let seam = poly([(0, 380), (S, 640), (S, 648), (0, 388)])
    linear(c, seam, [rgb(0xE6D3AC, 0.8), rgb(0xE6D3AC, 0.2)], [0, 1], P(0, 0), P(S, 0))
    addGrain(c, 0.5)
    return c.makeImage()!
}

// ======================================== Q 叠：一个圆压在一个圆角方上
func iconOverlap() -> CGImage {
    let c = newContext(S)
    linear(c, full, [rgb(0x1B1F28), rgb(0x0E1117)], [0, 1], P(0, 0), P(0, S))
    let square = rrect(196, 262, 404, 404, 102)
    let circle = disc(614, 606, 204)
    c.saveGState(); c.addPath(square); c.setFillColor(rgb(0xE9E4DA, 0.92)); c.fillPath(); c.restoreGState()
    c.saveGState(); c.addPath(circle); c.setFillColor(rgb(0xC9A567, 0.92)); c.fillPath(); c.restoreGState()
    // 交叠处再暗一层，做出前后关系
    c.saveGState()
    c.addPath(square); c.clip()
    c.addPath(circle); c.clip()
    c.setFillColor(rgb(0x8A6E3E, 0.95))
    c.fill(CGRect(x: 0, y: 0, width: S, height: S))
    c.restoreGState()
    addGrain(c, 0.45)
    return c.makeImage()!
}

// ======================================== R 弧：一条粗弧从左下扫到右上
func iconArc() -> CGImage {
    let c = newContext(S)
    linear(c, full, [rgb(0x1C212B), rgb(0x0D1016)], [0, 1], P(0, 0), P(0, S))
    radial(c, full, [rgb(0xFFFFFF, 0.05), rgb(0xFFFFFF, 0)], [0, 1], P(360, 320), 640)
    let arc = CGMutablePath()
    arc.addArc(center: P(316, 708), radius: 344, startAngle: 0, endAngle: .pi / 2, clockwise: false)
    let band = arc.copy(strokingWithWidth: 112, lineCap: .round, lineJoin: .round, miterLimit: 10)
    linear(c, band, [rgb(0xE9D2A6), rgb(0x94743E)], [0, 1], P(300, 330), P(700, 740))
    addGrain(c, 0.5)
    return c.makeImage()!
}

// ======================================== S 丘：一个软球，底下压着一道暗面
func iconOrb() -> CGImage {
    let c = newContext(S)
    linear(c, full, [rgb(0x22262F), rgb(0x12151B)], [0, 1], P(0, 0), P(0, S))
    let orb = disc(512, 512, 268)
    radial(c, orb, [rgb(0xF0E6D2), rgb(0xD5BC90), rgb(0x9A7C4C)], [0, 0.55, 1], P(430, 400), 400)
    // 底部一圈反光，让球不塌
    c.saveGState(); c.addPath(orb); c.clip()
    radial(c, orb, [rgb(0xFFF3DC, 0.5), rgb(0xFFF3DC, 0)], [0, 1], P(560, 742), 220)
    c.restoreGState()
    addGrain(c, 0.5)
    return c.makeImage()!
}

// ======================================== 输出
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
    (iconFold(), "P · 折", "P-fold"),
    (iconOverlap(), "Q · 叠", "Q-overlap"),
    (iconArc(), "R · 弧", "R-arc"),
    (iconOrb(), "S · 丘", "S-orb"),
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
save(sheet.makeImage()!, "\(outDir)/contact-sheet-5.png")
print("done")
