// 从录像里取指定时刻的一帧存 PNG（缩到宽 402）。用法：grab <video> <秒> <out.png>
import AVFoundation
import AppKit
let a = CommandLine.arguments
let g = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: a[1])))
g.requestedTimeToleranceBefore = .zero; g.requestedTimeToleranceAfter = .zero
g.maximumSize = CGSize(width: 402, height: 2000)
let img = try! g.copyCGImage(at: CMTime(seconds: Double(a[2])!, preferredTimescale: 6000), actualTime: nil)
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[3]))
