import Foundation
import CoreGraphics
import ImageIO

let src = CommandLine.arguments[1], dst = CommandLine.arguments[2]
let img = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(URL(fileURLWithPath: src) as CFURL, nil)!, 0, nil)!
let n = img.width
let c = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
c.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
c.fill(CGRect(x: 0, y: 0, width: n, height: n))
c.draw(img, in: CGRect(x: 0, y: 0, width: n, height: n))
let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dst) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(out, c.makeImage()!, nil)
CGImageDestinationFinalize(out)
print("flattened \(n)x\(n)")
