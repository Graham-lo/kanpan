// 读截图某区域的文字：ocr <png> x0,y0,x1,y1  → 每行一段识别结果
import Vision
import AppKit
let a = CommandLine.arguments
let img = NSImage(contentsOfFile: a[1])!
var rect = CGRect(x: 0, y: 0, width: img.size.width, height: img.size.height)
let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
let r = a[2].split(separator: ",").map { Double($0)! }
let W = Double(cg.width), H = Double(cg.height)
let crop = cg.cropping(to: CGRect(x: r[0]*W, y: r[1]*H, width: (r[2]-r[0])*W, height: (r[3]-r[1])*H))!
let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
req.usesLanguageCorrection = false
try! VNImageRequestHandler(cgImage: crop).perform([req])
// 每段再报它框内像素的平均彩度（白字色底的价格胶囊彩度高，灰字浅底的刻度低）
let ctx = CGContext(data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: crop.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
for o in req.results ?? [] {
  let b = o.boundingBox   // 归一化，左下原点
  var sat = 0, n = 0
  let x0 = Int(b.minX * Double(crop.width)), x1 = Int(b.maxX * Double(crop.width))
  let y0 = Int((1 - b.maxY) * Double(crop.height)), y1 = Int((1 - b.minY) * Double(crop.height))
  for y in max(0, y0)..<min(crop.height, max(y0 + 1, y1)) { for x in max(0, x0)..<min(crop.width, max(x0 + 1, x1)) {
    let o4 = (y * crop.width + x) * 4
    let r = Int(px[o4]), g = Int(px[o4 + 1]), bb = Int(px[o4 + 2])
    sat += max(r, g, bb) - min(r, g, bb); n += 1 } }
  print("\(o.topCandidates(1).first?.string ?? "")\t\(n > 0 ? sat / n : 0)")
}
