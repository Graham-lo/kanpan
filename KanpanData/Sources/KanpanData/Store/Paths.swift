import Foundation

/// 沙盒里 app 用到的目录（§4.3）。根目录可注入，测试就不碰真沙盒。
public struct Paths: Sendable {
  public var root: URL

  public init(root: URL) { self.root = root }

  /// 真机 / 模拟器上的默认位置：`Library/Caches/kanpan`。
  /// 放 Caches 是故意的——系统缺空间可以自动清，app 不依赖它存在。
  public static func caches() -> Paths {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return Paths(root: base.appendingPathComponent("kanpan", isDirectory: true))
  }

  /// 磁盘上**唯一**的 K 线痕迹：上次看的那对 (品种, 周期) 的最后 600 根。
  public var snapshot: URL { root.appendingPathComponent("last.kbar") }
  /// 品种表缓存，24 小时。
  public var exchangeInfo: URL { root.appendingPathComponent("exchangeInfo.json") }
  /// OI 归档切片，按天存，总上限 20 MB。
  public var oi: URL { root.appendingPathComponent("oi", isDirectory: true) }
  public func oiDay(symbol: String, day: String) -> URL {
    oi.appendingPathComponent(symbol, isDirectory: true).appendingPathComponent("\(day).oi")
  }

  public func ensure(_ dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }
  public func ensureRoot() throws { try ensure(root) }
}
