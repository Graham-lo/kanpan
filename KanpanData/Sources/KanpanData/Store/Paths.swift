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

  /// 旧版快照：磁盘上唯一的一份。现在只用来清理，写入一律走 `series`。
  public var snapshot: URL { root.appendingPathComponent("last.kbar") }
  /// 启动快照目录。按 (品种, 周期) 一对一个文件，条数和总字节都封顶，
  /// 见 `SeriesStore`。放大到十几对是为了换品种、换周期也能第一帧就有图。
  public var series: URL { root.appendingPathComponent("series", isDirectory: true) }
  /// 品种表缓存，24 小时。
  public var exchangeInfo: URL { root.appendingPathComponent("exchangeInfo.json") }
  /// 上次看到的自选报价。冷启动第一帧用它，避免整张列表空着等网络。
  public var quotes: URL { root.appendingPathComponent("quotes.json") }
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
