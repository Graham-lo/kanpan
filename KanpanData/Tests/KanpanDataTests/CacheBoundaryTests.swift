import Testing
import Foundation
@testable import KanpanData

/// 「什么能被清空」这条规矩在路径这一层的样子（M4）。
///
/// 三条规矩，一条也不是注释里的愿望：
///
/// 1. 随人走的（偏好、图表布局、自选与分类、画线、搜索历史）**一个字节都不许**
///    落在 `Library/Caches` 这棵树下——它们的真身在
///    `Application Support/kanpan/accounts/…`，唯一合法的消失方式是卸载 app。
/// 2. 这棵树下只放**没了还能原样重新取回来**的东西。
/// 3. 两类东西不共用一棵目录：共用了，「清一个」就成了「清两个」。
@Suite("缓存边界")
struct CacheBoundaryTests {

  private func paths(_ profile: String = "") -> Paths {
    Paths(root: URL(fileURLWithPath: "/tmp/kanpan-cache-boundary"), profile: profile)
  }

  /// 规矩 1：`Paths` 交出来的每一条路径，名字都不许是随人走的那几份档案。
  ///
  /// 这条守的是「以后也别往这儿加」：下一个往 `Paths` 里加属性的人，加错了这儿就红。
  @Test("缓存树下没有一条路径通向随人走的档案")
  func 缓存树里没有体验类() {
    let p = paths("u-9e1")
    let 随人走 = ["prefs.json", "symbols.json", "draws.json", "search.json",
                "stamp.json", "sentinel.json", "registry.json", "review-v1.json", "sync.json"]
    let 全部 = [p.snapshot, p.series, p.exchangeInfo, p.quotes, p.opens, p.oi,
              p.sectorHistory, p.profiles, p.profileRoot, p.sources,
              p.source("okx").exchangeInfo, p.source("okx").series,
              p.oiDay(symbol: "BTCUSDT", day: "2026-09-19"),
              p.oiSeries(symbol: "BTCUSDT", interval: "1h")]
    for url in 全部 {
      #expect(!随人走.contains(url.lastPathComponent), "\(url.lastPathComponent) 不该出现在缓存树里")
      #expect(url.path.hasPrefix(p.root.path), "\(url.path) 跑到缓存根之外了")
    }
  }

  /// 规矩 3 的正面：板块历史必须在这棵树里，而不是直接挂在 `Library/Caches` 根上。
  /// 挂在根上的那一份既躲开清缓存，也躲开测试档隔离。
  @Test("板块历史在 kanpan 这棵子树里")
  func 板块历史归这棵树管() {
    let p = paths()
    #expect(p.sectorHistory.deletingLastPathComponent().path == p.root.path)
    #expect(p.sectorHistory.lastPathComponent == "sector-history.json")
  }

  /// 规矩 3 的另一面：换过行情源之后长出来的那棵 `sources/<行情源>/` 也得在这棵树里，
  /// 而且要有名字可点——`MarketCache` 是逐个点名清的，手拼出来的目录点不到名，
  /// 那份品种表就成了清缓存清不掉、用量也算不进的孤儿。
  @Test("按行情源分的那棵子树在缓存树里，而且有名字可点")
  func 行情源子树归这棵树管() {
    let p = paths("u-9e1")
    let okx = p.source("okx")
    #expect(p.sources.deletingLastPathComponent().path == p.root.path)
    #expect(p.sources.lastPathComponent == "sources")
    #expect(okx.root.path == p.sources.appendingPathComponent("okx").path)
    // 子树和根同构：品种表、快照都在它底下，一并被 `sources` 这一笔罩住。
    #expect(okx.exchangeInfo.path.hasPrefix(p.sources.path + "/"))
    #expect(okx.series.path.hasPrefix(p.sources.path + "/"))
    // 身份跟着带下去，不会因为换了行情源就掉回 `unknown`。
    #expect(okx.profile == p.profile)
  }

  /// 洞二：报价 / 开盘价的内容由当前账号的自选表派生，所以按身份分目录。
  @Test("两个身份的报价与开盘价不共用一个文件")
  func 按身份分目录() {
    let a = paths("u-aaaaaaaa"), b = paths("local/bbbbbbbb")
    #expect(a.quotes != b.quotes)
    #expect(a.opens != b.opens)
    #expect(a.quotes.path.contains("/profiles/u-aaaaaaaa/"))
    // 访客那一档带一层斜杠，要真的拆成两级目录，不能变成一个带 `%2F` 的文件名。
    #expect(b.quotes.path.contains("/profiles/local/bbbbbbbb/"))
    #expect(!b.quotes.path.contains("%2F"))
    // 两份都在 `profiles/` 底下：清缓存删那一棵就够，不必逐个身份点名。
    #expect(a.quotes.path.hasPrefix(a.profiles.path))
    #expect(b.opens.path.hasPrefix(b.profiles.path))
  }

  /// 身份还没注入时也不许落到共用的地方——`unknown` 不是任何人的档案名。
  @Test("没认主时落在 unknown，不落在共用目录")
  func 没认主也不串号() {
    let p = paths()
    #expect(p.quotes.path.contains("/profiles/unknown/"))
    #expect(p.quotes != paths("u-x").quotes)
    #expect(p.quotes.deletingLastPathComponent().path != p.root.path)
  }

  /// 测试档隔离照旧管着整棵树，分身份那一层也在里面。
  @Test("注入的身份不会把测试档隔离绕开")
  func 隔离照旧() {
    let p = Paths.caches(profile: "u-1")
    #expect(p.profile == "u-1")
    #expect(p.quotes.path.hasPrefix(p.root.path))
  }
}
