import Foundation
import Testing
@testable import KanpanDeepLink

// 深链的形态是一份契约（`docs/提醒与体验细节-实施方案-2026-09-20.md` 第 1 节）：
// 通知、桌面快捷入口、共享链接三边都照着它拼串，客户端照着它解。这儿把两种壳子
// （`hkline://` 与 `https://<webHost>/s/<id>`）和「认不出来就 nil」一并钉住。

@Suite("深链解析")
struct DeepLinkParseTests {

  private func parse(_ text: String) -> DeepLink? {
    guard let url = URL(string: text) else { return nil }
    return DeepLink.parse(url)
  }

  // ---------------------------------------------------------------- 合法

  @Test("品种：带周期与不带周期")
  func symbol() {
    #expect(parse("hkline://symbol/BTCUSDT?interval=1h") == .symbol("BTCUSDT", interval: "1h"))
    #expect(parse("hkline://symbol/BTCUSDT") == .symbol("BTCUSDT", interval: nil))
    // 代号一律大写；数字开头的（1000PEPEUSDT）是正常品种。
    #expect(parse("hkline://symbol/ethusdt") == .symbol("ETHUSDT", interval: nil))
    #expect(parse("hkline://symbol/1000PEPEUSDT") == .symbol("1000PEPEUSDT", interval: nil))
  }

  @Test("周期原样保留：1M 是月线，1m 是分钟线")
  func intervalKeepsItsCase() {
    #expect(parse("hkline://symbol/BTCUSDT?interval=1M") == .symbol("BTCUSDT", interval: "1M"))
    #expect(parse("hkline://symbol/BTCUSDT?interval=1m") == .symbol("BTCUSDT", interval: "1m"))
    // 空的 interval 等于没给。
    #expect(parse("hkline://symbol/BTCUSDT?interval=") == .symbol("BTCUSDT", interval: nil))
    // 别的查询参数不算数。
    #expect(parse("hkline://symbol/BTCUSDT?from=push") == .symbol("BTCUSDT", interval: nil))
  }

  @Test("画线：品种 + 那条线的 id")
  func drawing() {
    #expect(parse("hkline://drawing/BTCUSDT/d-42") == .drawing(symbol: "BTCUSDT", drawingID: "d-42"))
    let uuid = "9F1C0A6E-4B2D-4E0A-9E3B-7C5F2A8D1B44"
    #expect(parse("hkline://drawing/ethusdt/\(uuid)") == .drawing(symbol: "ETHUSDT", drawingID: uuid))
  }

  @Test("提醒列表与搜索页：只有去处，没有参数")
  func plainRoutes() {
    #expect(parse("hkline://alerts") == .alerts)
    #expect(parse("hkline://search") == .search)
    // 结尾多一条斜杠还是同一个地方。
    #expect(parse("hkline://alerts/") == .alerts)
    #expect(parse("hkline://search/") == .search)
  }

  @Test("共享：两种 host 形态解析到同一条")
  func shareHasTwoShapes() {
    let app = parse("hkline://share/abc123")
    let web = parse("https://kanpan.107-174-172-10.sslip.io/s/abc123")
    #expect(app == .share(id: "abc123"))
    #expect(web == .share(id: "abc123"))
    #expect(app == web)
    // 域名大小写不敏感。
    #expect(parse("https://KANPAN.107-174-172-10.sslip.io/s/abc123") == .share(id: "abc123"))
  }

  // ---------------------------------------------------------------- 非法

  @Test("不认识的 scheme 一律 nil")
  func foreignSchemes() {
    #expect(parse("hntcoin://alerts") == nil)
    #expect(parse("http://kanpan.107-174-172-10.sslip.io/s/abc123") == nil)
    #expect(parse("file:///tmp/x") == nil)
  }

  @Test("段数不对、去处不认识：nil，不猜")
  func malformedRoutes() {
    #expect(parse("hkline://symbol") == nil)
    #expect(parse("hkline://symbol/") == nil)
    #expect(parse("hkline://symbol/BTCUSDT/1h") == nil)
    #expect(parse("hkline://drawing/BTCUSDT") == nil)
    #expect(parse("hkline://drawing/BTCUSDT/d-1/extra") == nil)
    #expect(parse("hkline://share") == nil)
    #expect(parse("hkline://alerts/42") == nil)
    #expect(parse("hkline://settings") == nil)
    #expect(parse("hkline://") == nil)
  }

  @Test("代号收不住的形状不当品种")
  func badSymbols() {
    // 带点、带下划线、超长的一律认不出来。
    #expect(parse("hkline://symbol/BTC.USDT") == nil)
    #expect(parse("hkline://symbol/BTC_USDT") == nil)
    #expect(parse("hkline://symbol/" + String(repeating: "A", count: 33)) == nil)
  }

  @Test("共享的通用链接只认自己的域名和 /s/ 那条路")
  func webHostIsStrict() {
    #expect(parse("https://example.com/s/abc123") == nil)
    #expect(parse("https://kanpan.107-174-172-10.sslip.io/ui/") == nil)
    #expect(parse("https://kanpan.107-174-172-10.sslip.io/s/") == nil)
    #expect(parse("https://kanpan.107-174-172-10.sslip.io/s/abc/def") == nil)
  }

  // ---------------------------------------------------------------- 路由

  @MainActor
  @Test("路由：后来的顶掉先来的，取走就清空")
  func routerHoldsOnePending() {
    let router = DeepLinkRouter()
    #expect(router.pending == nil)
    #expect(router.consume() == nil)

    router.open(.alerts)
    router.open(.search)
    #expect(router.pending == .search)
    #expect(router.consume() == .search)
    #expect(router.pending == nil)
  }

  @MainActor
  @Test("路由：认不出来的 URL 不留待办")
  func routerRejectsJunk() {
    let router = DeepLinkRouter()
    #expect(router.open(URL(string: "hkline://nowhere")!) == false)
    #expect(router.pending == nil)
    #expect(router.open(URL(string: "hkline://symbol/BTCUSDT?interval=4h")!) == true)
    #expect(router.consume() == .symbol("BTCUSDT", interval: "4h"))
  }
}
