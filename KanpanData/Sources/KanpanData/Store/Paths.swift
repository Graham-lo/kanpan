import Foundation

/// 沙盒里 app 用到的目录（§4.3）。根目录可注入，测试就不碰真沙盒。
///
/// 这棵树底下**只放能重新取回来的东西**（K 线快照、品种表、报价、开盘价、OI、
/// 板块历史）：判据就一句——没了还能原样取回来。随人走的那些（偏好、图表布局、
/// 自选与分类、画线、搜索历史）一个字节都不许放进来，它们的真身在
/// `Application Support/kanpan/accounts/…`（见 `KanpanAccount.AccountFiles`），
/// 那儿不提供任何清空入口。两类东西**不共用一棵目录**：共用了，「清一个」就成了
/// 「清两个」。
public struct Paths: Sendable {
  public var root: URL

  /// 当前是谁的档案：`u-<账号 uuid>`，或没登录时的 `local/<访客批次 uuid>`。
  /// 和账号目录那一套**逐字相同**（`AccountFiles.directory(user:)`），不另发明一套 id。
  ///
  /// 为什么是一个字符串、而且要**由调用方注入**：这一层是数据层，它不认识账号包，
  /// 也绝不该反过来依赖它。身份从 app 那一层传进来，这儿只负责按它分目录。
  public var profile: String

  public init(root: URL, profile: String = "") { self.root = root; self.profile = profile }

  /// 真机 / 模拟器上的默认位置：`Library/Caches/kanpan`。
  /// 放 Caches 是故意的——系统缺空间可以自动清，app 不依赖它存在。
  ///
  /// UI 测试跑的是同一个 app、同一个沙盒，但 `KANPAN_TEST_PROFILE=1` 会把
  /// 自选表换成内存实现——于是测试里的「自选」是空的。这个缓存目录要是不跟着
  /// 隔开，那一趟结束时 `QuoteBook` 就会拿「测试期间手里的那一两个品种」把
  /// `quotes.json` 原样覆盖掉，把用户真实的几十行快照抹了。下一次冷启动自然
  /// 又是一行行慢慢加载——现象和真的没修一样，但根本不是 app 的问题。
  /// 所以在测试档里另起一棵 `tests/<profile>` 子树，和账号、行情源偏好的做法一致。
  ///
  /// - Parameter profile: 当前档案 id，见 `profile`。不传就是「还没认主」。
  public static func caches(profile: String = "") -> Paths {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    var root = base.appendingPathComponent("kanpan", isDirectory: true)
    // 这条岔路**只在 DEBUG 构建里存在**（审查 C-02）。原来这儿写着「不加 `#if DEBUG`，
    // 因为包目标的编译条件由外层配置决定」——真正的后果是：同一个 Release 包被注入
    // `KANPAN_TEST_PROFILE=1` 之后缓存根就变了，于是「Release 回归」量的是另一棵目录，
    // 而正式启动那条路一次都没被测到。测试档要隔离，靠的是**独立的测试安装沙盒**
    // （测试包自己的容器），不是让正式二进制自己认一个环境变量。
    // `SymbolPrefsStore.deviceStorage()` 同一轮一起收进了 DEBUG，两边仍然一致。
    #if DEBUG
    if ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1" {
      let bucket = ProcessInfo.processInfo.environment["KANPAN_PERSISTENCE_PROFILE"] ?? "normal"
      root = root.appendingPathComponent("tests", isDirectory: true)
                 .appendingPathComponent(bucket, isDirectory: true)
    }
    #endif
    return Paths(root: root, profile: profile)
  }

  /// 旧版快照：磁盘上唯一的一份。现在只用来清理，写入一律走 `series`。
  public var snapshot: URL { root.appendingPathComponent("last.kbar") }
  /// 启动快照目录。按 (品种, 周期) 一对一个文件，条数和总字节都封顶，
  /// 见 `SeriesStore`。放大到十几对是为了换品种、换周期也能第一帧就有图。
  public var series: URL { root.appendingPathComponent("series", isDirectory: true) }
  /// 品种表缓存，24 小时。
  public var exchangeInfo: URL { root.appendingPathComponent("exchangeInfo.json") }
  /// 换过行情源的人盘上会多的那一层：`sources/<行情源>/…`。**清缓存整棵删它**。
  ///
  /// 为什么会有这一层：okx 的 BTCUSDT 不是币安那根，品种表和启动快照跟币安共用一份就串了，
  /// 于是每个非默认行情源自己长一棵和根同构的小树。
  ///
  /// 它装的还是品种表和 K 线快照——**没了重新取一遍就有**，按判据就该归清缓存管。
  /// 之所以要在这儿有个名字，是因为 `MarketCache` 是逐个点名清的（删根会把不该清的
  /// 一起带走）：手拼出来的目录点不到名，那棵树就成了谁也清不掉、用量也算不进的孤儿。
  public var sources: URL { root.appendingPathComponent(Self.sourcesFolder, isDirectory: true) }
  public static let sourcesFolder = "sources"

  /// 某个行情源自己那棵子树，结构和根一模一样（`exchangeInfo.json`、`series/`…）。
  ///
  /// 只收一个名字（调用方传 `MarketSource.rawValue`）而不是收那个枚举：这一层是数据层，
  /// 拼个目录名不值得让它反过来认识上面的路由类型。身份照旧跟着带下去。
  public func source(_ name: String) -> Paths {
    Paths(root: sources.appendingPathComponent(name, isDirectory: true), profile: profile)
  }

  /// 板块页「5 日 / 20 日」那两档要的日线收盘。见 `SectorHistoryFeed`。
  ///
  /// 它原来直接挂在 `Library/Caches` 根上、不问这儿要路径，于是既躲开了「清缓存」，
  /// 也躲开了测试档隔离。板块历史是**取得回来**的数据，归这棵树管。
  public var sectorHistory: URL { root.appendingPathComponent("sector-history.json") }

  // MARK: 内容随当前账号派生的那几份

  /// 按身份分的那一层。**清缓存整棵删它**。
  public var profiles: URL { root.appendingPathComponent(Self.profilesFolder, isDirectory: true) }
  public static let profilesFolder = "profiles"
  /// 身份还没注入时的去处。它不是任何人的档案名，所以**不会串到谁头上**。
  public static let unknownProfile = "unknown"

  /// 这份档案自己的缓存目录。
  ///
  /// 报价和开盘价存的是什么？**当前这个人自选表里的那些品种。** 价格本身是公开数据，
  /// 但「这台机器上刚才关注的是哪几十个品种」是随人走的：共用一个文件的后果是
  /// A 退出、B 登录，第一帧闪的是 A 的那张表。所以按身份分目录，目录结构和账号目录
  /// 逐字对齐（`u-…` / `local/…`），肉眼就能对上是谁的。
  ///
  /// 注意它**仍然是缓存**：照样能被系统清、被「清缓存」整棵删，没了重新取一遍就有。
  /// 分身份只是不再串号，不是把它升格成随人走的状态。
  public var profileRoot: URL {
    var url = profiles
    let id = profile.isEmpty ? Self.unknownProfile : profile
    // `local/<uuid>` 带一层斜杠，逐段拼，别指望 `appendingPathComponent` 替我们拆。
    for part in id.split(separator: "/") where !part.isEmpty {
      url = url.appendingPathComponent(String(part), isDirectory: true)
    }
    return url
  }
  /// 上次看到的自选报价。冷启动第一帧用它，避免整张列表空着等网络。
  public var quotes: URL { profileRoot.appendingPathComponent("quotes.json") }
  /// 上次算涨跌幅用的当日开盘价。见 `BaselineSnapshot`。
  public var opens: URL { profileRoot.appendingPathComponent("opens.json") }
  /// OI 归档切片，按天存，总上限 20 MB。
  public var oi: URL { root.appendingPathComponent("oi", isDirectory: true) }
  public func oiDay(symbol: String, day: String) -> URL {
    oi.appendingPathComponent(symbol, isDirectory: true).appendingPathComponent("\(day).oi")
  }
  /// 已经按图表周期聚好的那一段，一个「品种 + 周期」一份；和日切片同一个目录，
  /// 一起受 20 MB 上限和 LRU 管。
  public func oiSeries(symbol: String, interval: String) -> URL {
    oi.appendingPathComponent(symbol, isDirectory: true).appendingPathComponent("series-\(interval).oi")
  }

  public func ensure(_ dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }
  public func ensureRoot() throws { try ensure(root) }
}
