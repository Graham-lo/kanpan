// 逐帧：在给定区域里数「高彩度像素」（K 线蜡烛的红绿），输出每帧时刻与计数。
// 用法：frames <video.mp4> <x0> <y0> <x1> <y1>  （归一化 0..1 坐标，左上为原点）
import AVFoundation
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let asset = AVURLAsset(url: URL(fileURLWithPath: a[1]))
let r = (Double(a[2])!, Double(a[3])!, Double(a[4])!, Double(a[5])!)
let track = asset.tracks(withMediaType: .video)[0]
let reader = try! AVAssetReader(asset: asset)
let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
reader.add(out); reader.startReading()
while let sb = out.copyNextSampleBuffer() {
  let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
  guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
  CVPixelBufferLockBaseAddress(pb, .readOnly)
  let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), bpr = CVPixelBufferGetBytesPerRow(pb)
  let p = CVPixelBufferGetBaseAddress(pb)!.assumingMemoryBound(to: UInt8.self)
  let x0 = Int(r.0 * Double(w)), y0 = Int(r.1 * Double(h)), x1 = Int(r.2 * Double(w)), y1 = Int(r.3 * Double(h))
  var chroma = 0, sum = 0
  var y = y0
  while y < y1 {
    var x = x0
    while x < x1 {
      let o = y * bpr + x * 4
      let b = Int(p[o]), g = Int(p[o+1]), rr = Int(p[o+2])
      if max(b, g, rr) - min(b, g, rr) > 70 { chroma += 1 }
      sum += (b + g + rr)
      x += 2
    }
    y += 2
  }
  CVPixelBufferUnlockBaseAddress(pb, .readOnly)
  print(String(format: "%.4f %d %d", t, chroma, sum))
}
