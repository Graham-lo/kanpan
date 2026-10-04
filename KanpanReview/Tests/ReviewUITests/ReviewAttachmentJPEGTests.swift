import Foundation
import ImageIO
import Testing
import UIKit
@testable import ReviewUI

/// 补图压缩：按目标边长直接解码、在后台跑（审查 E 线自查：原来整张原图解成位图、在主线程上连画最多六遍）。
struct ReviewAttachmentJPEGTests {
  /// 一张宽 3000、高 1500 的图，填满不规则色块，压起来不至于小得离谱。
  private func photo(width: CGFloat = 3000, height: CGFloat = 1500) -> Data {
    let format = UIGraphicsImageRendererFormat.default(); format.scale = 1; format.opaque = true
    let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
      var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
      for y in stride(from: 0, to: Int(height), by: 25) {
        for x in stride(from: 0, to: Int(width), by: 25) {
          seed = seed &* 6364136223846793005 &+ 1442695040888963407
          UIColor(red: CGFloat(seed >> 56) / 255, green: CGFloat((seed >> 48) & 0xFF) / 255,
                  blue: CGFloat((seed >> 40) & 0xFF) / 255, alpha: 1).setFill()
          context.fill(CGRect(x: x, y: y, width: 25, height: 25))
        }
      }
    }
    return image.pngData()!
  }
  private func pixelSize(_ data: Data) -> (Int, Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
    return (w, h)
  }

  @Test func longSideShrinksTo2048OffTheMainActor() async throws {
    let raw = photo()
    // 在后台调得动（`nonisolated`），和 app 里 `Task.detached` 那条路一样。
    let compressed = await Task.detached { ReviewAttachmentsSection.jpeg(raw, limit: 5 * 1024 * 1024) }.value
    let out = try #require(compressed)
    let size = try #require(pixelSize(out))
    #expect(max(size.0, size.1) == 2048)
    #expect(size.0 > size.1)
    #expect(out.count <= 5 * 1024 * 1024)
  }

  @Test func overLimitKeepsShrinkingUntilItFits() async throws {
    let raw = photo()
    let first = try #require(ReviewAttachmentsSection.jpeg(raw, limit: .max))
    let limit = first.count / 3
    let out = try #require(ReviewAttachmentsSection.jpeg(raw, limit: limit))
    #expect(out.count <= limit)
    let size = try #require(pixelSize(out))
    #expect(max(size.0, size.1) < 2048)
  }

  @Test func smallPictureIsNotUpscaledAndGarbageIsRejected() throws {
    let out = try #require(ReviewAttachmentsSection.jpeg(photo(width: 400, height: 300), limit: 5 * 1024 * 1024))
    let size = try #require(pixelSize(out))
    #expect(size.0 == 400 && size.1 == 300)
    #expect(ReviewAttachmentsSection.jpeg(Data("不是图".utf8), limit: 5 * 1024 * 1024) == nil)
  }
}
