import Foundation
import Testing
@testable import Kanpan

// 深链的形态是一份契约（`71bd340:docs/提醒与体验细节-实施方案-2026-09-20.md` 第 1 节）：
// 通知、桌面快捷入口、收件箱三边都照着它拼串，客户端照着它解。这儿把唯一的壳子
// `hkline://` 和「认不出来就 nil」一并钉住。分享不发链接，https 通用链接一律不认。

@Suite("深链解析")
struct DeepLinkParseTests {

  private func parse(_ text: String) -> DeepLink? {
    guard let url = URL(string: text) else { return nil }
    return DeepLink.parse(url)
  }

  // ---------------------------------------------------------------- 合法

  @Test("品种：带周期与不带周期")
  func symbol() {
    #expect(parse("hkline://symbol/coinbase/spot/BTC-USD?interval=1h") == .symbol("coinbase/spot/BTC-USD", interval: "1h"))
    #expect(parse("hkline://drawing/coinbase/spot/BTC-USD/d-42") == .drawing(symbol: "coinbase/spot/BTC-USD", drawingID: "d-42"))
    #expect(parse("hkline://symbol/BTCUSDT?interval=1h") == .symbol("binance/usd_m/BTCUSDT", interval: "1h"))
    #expect(parse("hkline://symbol/BTCUSDT") == .symbol("binance/usd_m/BTCUSDT", interval: nil))
    // 代号一律大写；数字开头的（1000PEPEUSDT）是正常品种。
    #expect(parse("hkline://symbol/ethusdt") == .symbol("binance/usd_m/ETHUSDT", interval: nil))
    #expect(parse("hkline://symbol/1000PEPEUSDT") == .symbol("binance/usd_m/1000PEPEUSDT", interval: nil))
  }

  @Test("周期原样保留：1M 是月线，1m 是分钟线")
  func intervalKeepsItsCase() {
    #expect(parse("hkline://symbol/BTCUSDT?interval=1M") == .symbol("binance/usd_m/BTCUSDT", interval: "1M"))
    #expect(parse("hkline://symbol/BTCUSDT?interval=1m") == .symbol("binance/usd_m/BTCUSDT", interval: "1m"))
    // 空的 interval 等于没给。
    #expect(parse("hkline://symbol/BTCUSDT?interval=") == .symbol("binance/usd_m/BTCUSDT", interval: nil))
    // 别的查询参数不算数。
    #expect(parse("hkline://symbol/BTCUSDT?from=push") == .symbol("binance/usd_m/BTCUSDT", interval: nil))
  }

  @Test("画线：品种 + 那条线的 id")
  func drawing() {
    #expect(parse("hkline://drawing/BTCUSDT/d-42") == .drawing(symbol: "binance/usd_m/BTCUSDT", drawingID: "d-42"))
    let uuid = "9F1C0A6E-4B2D-4E0A-9E3B-7C5F2A8D1B44"
    #expect(parse("hkline://drawing/ethusdt/\(uuid)") == .drawing(symbol: "binance/usd_m/ETHUSDT", drawingID: uuid))
  }

  @Test("提醒列表与搜索页：只有去处，没有参数")
  func plainRoutes() {
    #expect(parse("hkline://alerts") == .alerts)
    #expect(parse("hkline://search") == .search)
    // 结尾多一条斜杠还是同一个地方。
    #expect(parse("hkline://alerts/") == .alerts)
    #expect(parse("hkline://search/") == .search)
    // 桌面小号自选那一格点进来。
    #expect(parse("hkline://favorites") == .favorites)
    #expect(parse("hkline://favorites/x") == nil)
  }

  @Test("共享：只有 hkline://share/<id> 一种形态")
  func shareHasOneShape() {
    #expect(parse("hkline://share/abc123") == .share(id: "abc123"))
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

  @Test("https 通用链接一律不认（分享走收件箱，不发链接）")
  func webLinksAreIgnored() {
    #expect(parse("https://kanpan.107-174-172-10.sslip.io/s/abc123") == nil)
    #expect(parse("https://example.com/s/abc123") == nil)
    #expect(parse("https://kanpan.107-174-172-10.sslip.io/ui/") == nil)
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
    #expect(router.consume() == .symbol("binance/usd_m/BTCUSDT", interval: "4h"))
  }
}
