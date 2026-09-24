import Foundation
import Testing
@testable import Kanpan

// 模拟器上同一个 Apple ID 的两台设备之间 Handoff 不可测，所以这一段用单测钉住：
// 行情页登记的 userInfo → NSUserActivity 序列化往返 → 深链，必须落到和
// `hkline://symbol/<S>?interval=` 完全一样的那一条。

@Suite("Handoff → 深链")
struct ChartHandoffTests {

  @Test("品种 + 周期原样接力，周期大小写不丢")
  func symbolAndInterval() {
    // 行情页登记的是完整品种 key，接力端按它开对交易所。
    let info = ChartHandoff.userInfo(symbol: "binance/usd_m/BTCUSDT", interval: "4h")
    #expect(ChartHandoff.url(from: info)?.absoluteString == "hkline://symbol/binance/usd_m/BTCUSDT?interval=4h")
    #expect(ChartHandoff.link(from: info) == .symbol("binance/usd_m/BTCUSDT", interval: "4h"))
    #expect(ChartHandoff.link(from: ChartHandoff.userInfo(symbol: "binance/usd_m/ETHUSDT", interval: "1M")) == .symbol("binance/usd_m/ETHUSDT", interval: "1M"))
    #expect(ChartHandoff.link(from: ChartHandoff.userInfo(symbol: "coinbase/spot/BTC-USD", interval: "1m")) == .symbol("coinbase/spot/BTC-USD", interval: "1m"))
    // 老版本登记的裸代号照样接得住，归到币安合约。
    #expect(ChartHandoff.link(from: ChartHandoff.userInfo(symbol: "1000PEPEUSDT", interval: "1m")) == .symbol("binance/usd_m/1000PEPEUSDT", interval: "1m"))
  }

  @Test("走一遍 NSUserActivity 的序列化再解")
  func survivesUserActivityRoundTrip() throws {
    let sent = NSUserActivity(activityType: ChartHandoff.activityType)
    sent.addUserInfoEntries(from: ChartHandoff.userInfo(symbol: "binance/usd_m/SOLUSDT", interval: "15m"))
    // 系统接力时传过去的是 userInfo 的属性列表形态：按它编解一次。
    let data = try PropertyListSerialization.data(fromPropertyList: sent.userInfo ?? [:], format: .binary, options: 0)
    let received = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [AnyHashable: Any])
    #expect(ChartHandoff.link(from: received) == .symbol("binance/usd_m/SOLUSDT", interval: "15m"))
  }

  @Test("缺品种或形状不对就什么都不做")
  func rejects() {
    #expect(ChartHandoff.link(from: [:]) == nil)
    #expect(ChartHandoff.link(from: ["interval": "1h"]) == nil)
    #expect(ChartHandoff.link(from: ["symbol": "BTC/USDT", "interval": "1h"]) == nil)
    #expect(ChartHandoff.link(from: ["symbol": 42]) == nil)
    // 没有周期也能接：只开品种。
    #expect(ChartHandoff.link(from: ["symbol": "btcusdt"]) == .symbol("binance/usd_m/BTCUSDT", interval: nil))
  }
}
