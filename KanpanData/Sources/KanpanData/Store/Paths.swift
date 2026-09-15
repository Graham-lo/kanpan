import Foundation

/// 沙盒里 app 用到的目录（§4.3）。根目录可注入，测试就不碰真沙盒。
public struct Paths: Sendable {
  public var root: URL

  public init(root: URL) { self.root = root }

  /// 真机 / 模拟器上的默认位置：`Library/Caches/kanpan`。
  /// 放 Caches 是故意的——系统缺空间可以自动清，app 不依赖它存在。
  ///
  /// UI 测试跑的是同一个 app、同一个沙盒，但 `KANPAN_TEST_PROFILE=1` 会把
  /// 自选表换成内存实现——于是测试里的「自选」是空的。这个缓存目录要是不跟着
  /// 隔开，那一趟结束时 `QuoteBook` 就会拿「测试期间手里的那一两个品种」把
  /// `quotes.json` 原样覆盖掉，把用户真实的几十行快照抹了。下一次冷启动自然
  /// 又是一行行慢慢加载——现象和真的没修一样，但根本不是 app 的问题。
  /// 所以在测试档里另起一棵 `tests/<profile>` 子树，和账号、行情源偏好的做法一致。
  public static func caches() -> Paths {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    var root = base.appendingPathComponent("kanpan", isDirectory: true)
    // 不加 `#if DEBUG`：包目标的编译条件由外层配置决定，隔离要是在测试那一档
    // 没生效，后果正是它要防的那件事。跟 `SymbolPrefsStore` 一样只认环境变量。
    if ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1" {
      let profile = ProcessInfo.processInfo.environment["KANPAN_PERSISTENCE_PROFILE"] ?? "normal"
      root = root.appendingPathComponent("tests", isDirectory: true)
                 .appendingPathComponent(profile, isDirectory: true)
    }
    return Paths(root: root)
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
  /// 上次算涨跌幅用的当日开盘价。见 `BaselineSnapshot`。
  public var opens: URL { root.appendingPathComponent("opens.json") }
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
