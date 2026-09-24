import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit
@testable import KanpanChart

@MainActor
@Suite("主力订单流 · 图表")
struct OrderFlowChartTests {
  static let size = AxisWidthTests.size

  static func order(_ product: OrderFlowProduct, _ side: BookSide, price: Double, firstSeen: Int64,
                    end: Int64? = nil, status: BigOrder.Status = .live, notional: Double = 10_000_000,
                    initial: Double = 10_000_000, filled: Double = 0, threshold: Double = 5_000_000,
                    bucket: Int64 = 0) -> BigOrder {
    BigOrder(venueID: "binance:\(product.rawValue):X", exchange: "币安", product: product, side: side,
             bucket: bucket, price: price, firstSeenMs: firstSeen, endMs: end, status: status,
             initialNotional: initial, notional: notional, filledNotional: filled, threshold: threshold)
  }

  /// 最新价上下摆几单：U 本位买（挂着）、现货买卖、币本位卖、一条已成交买、一条已撤销卖。
  static func renderer(redUp: Bool = false) -> (ChartRenderer, [BigOrder]) {
    var r = AxisWidthTests.renderer()
    let b = r.state.series
    let price = b.close.last!
    let d = price * 0.002
    let seen = b.time(at: b.count - 10) + 1
    let ended = b.time(at: b.count - 4) + 1
    let orders = [
      order(.usdtPerp, .bid, price: price - d, firstSeen: seen, bucket: 1),
      order(.spot, .bid, price: price - 2 * d, firstSeen: seen, notional: 1_500_000, initial: 1_500_000,
            threshold: 1_000_000, bucket: 2),
      order(.spot, .ask, price: price + 2 * d, firstSeen: seen, notional: 1_500_000, initial: 1_500_000,
            threshold: 1_000_000, bucket: 3),
      // 挂着的单成交比例按此刻名义算：2.014M ÷ 5.3M = 38%。
      order(.coinPerp, .ask, price: price + d, firstSeen: b.firstTime - 60_000, notional: 5_300_000,
            initial: 8_000_000, filled: 2_014_000, bucket: 4),
      order(.usdtPerp, .bid, price: price - 3 * d, firstSeen: seen, end: ended, status: .filled,
            filled: 9_000_000, bucket: 5),
      order(.delivery, .ask, price: price + 3 * d, firstSeen: seen, end: ended, status: .cancelled, bucket: 6),
    ]
    r.state.redUp = redUp
    r.state.orderFlow = OrderFlowSnapshot(symbol: r.state.symbol.symbol, phase: .ready, orders: orders,
                                          asOfMs: seen + 12 * 60_000)
    return (r, orders)
  }

  func frame(_ r: ChartRenderer) -> ChartRenderer.OrderFlowFrame {
    let L = r.layout(size: Self.size)
    return r.orderFlowFrame(pane: L.main, range: r.priceRange(size: Self.size), L: L)
  }

  /// 主图上某一价位的 y，和某一 y 对应的价。
  func y(_ r: ChartRenderer, _ price: Double) -> Double {
    KanpanCore.yOf(price, pane: r.layout(size: Self.size).main, range: r.priceRange(size: Self.size),
                   mode: r.state.effectivePriceMode)
  }
  func price(_ r: ChartRenderer, atY y: Double) -> Double {
    KanpanCore.pOf(y, pane: r.layout(size: Self.size).main, range: r.priceRange(size: Self.size),
                   mode: r.state.effectivePriceMode)
  }

  /// 夹具里一桶一单：按桶号取那条带。
  func bandAt(_ f: ChartRenderer.OrderFlowFrame, bucket: Int64) -> ChartRenderer.OrderFlowBand? {
    f.bands.first { $0.key.bucket == bucket }
  }

  @Test("一桶一单时一单一条：首见那根左缘起，挂着的画到主图右缘、结束的画到结束那根右缘")
  func geometry() throws {
    let (r, orders) = Self.renderer()
    let L = r.layout(size: Self.size)
    let f = frame(r)
    #expect(f.bands.count == orders.count)
    #expect(f.bands.allSatisfy { !$0.thin }, "夹具里各单隔得开，不该有被挤细的")
    let b = r.state.series
    let spacing = r.state.view.barSpacing(step: b.step, plotW: L.plotW)
    let left = r.state.view.x(Double(b.time(at: b.count - 10)), plotW: L.plotW) - spacing / 2
    let endRight = r.state.view.x(Double(b.time(at: b.count - 4)), plotW: L.plotW) + spacing / 2
    for band in f.bands {
      if band.group.firstSeenMs < b.firstTime { #expect(band.frame.minX == 0) }
      else { #expect(abs(band.frame.minX - max(0, left)) < 0.001) }
      if band.group.isLive { #expect(abs(band.frame.maxX - L.plotW) < 0.001) }
      else { #expect(abs(band.frame.maxX - endRight) < 0.001) }
    }
  }

  @Test("细线：主 2 pt（还挂着 2.5）、次 1 pt 70%、底噪 1 pt ≤ 35%、被压 1 pt；墙的淡底 ≤ 12%；线粗不看名义")
  func thickness() {
    typealias R = ChartRenderer
    #expect(R.orderFlowMainLine == 2 && R.orderFlowMainLiveLine == 2.5)
    #expect(R.orderFlowSecondaryLine == 1 && R.orderFlowNoiseLine == 1 && R.orderFlowThinLine == 1)
    #expect(R.orderFlowSecondaryAlpha == 0.7 && R.orderFlowNoiseAlpha <= 0.35 && R.orderFlowRangeAlpha <= 0.12)
    #expect(BigOrder.thicknessTiers == 5)
    let (r, _) = Self.renderer()
    let f = frame(r)
    #expect(f.bands.allSatisfy { $0.frame.height >= 1 && $0.frame.height <= 2.5 })
    for band in f.bands where band.role == .main && !band.thin {
      #expect(band.frame.height == (band.group.isLive ? 2.5 : 2) && band.alpha == 1)
    }
    // 10M 挂着的合约买：主档、还挂着 → 2.5 pt；结束的已成交那条 2 pt。名义翻倍线也不变粗。
    #expect(bandAt(f, bucket: 1)?.frame.height == 2.5)
    #expect(bandAt(f, bucket: 5)?.frame.height == 2)
  }

  @Test("合并：同桶同侧同类、时间上连着的合成一条（四种合约一条、三家现货一条），不同类、不同侧不合；粗细按合计")
  func mergeRules() throws {
    var (r, orders) = Self.renderer()
    let p = orders[0].price
    let seen = orders[0].firstSeenMs
    let b = r.state.series
    let early = b.time(at: b.count - 14) + 1
    let ended = b.time(at: b.count - 6) + 1
    func contract(_ product: OrderFlowProduct, venue: String, exchange: String = "币安", notional: Double = 5_000_000,
                  firstSeen: Int64? = nil, end: Int64? = nil, status: BigOrder.Status = .live,
                  filled: Double = 0) -> BigOrder {
      var o = Self.order(product, .bid, price: p, firstSeen: firstSeen ?? seen, end: end, status: status,
                         notional: notional, initial: notional, filled: filled, bucket: 1)
      o.venueID = venue; o.exchange = exchange
      return o
    }
    func spot(_ side: BookSide, venue: String, exchange: String) -> BigOrder {
      var o = Self.order(.spot, side, price: p, firstSeen: seen, notional: 1_000_000, initial: 1_000_000,
                         threshold: 1_000_000, bucket: 1)
      o.venueID = venue; o.exchange = exchange
      return o
    }
    let merged = [
      contract(.usdtPerp, venue: "binance:usdtPerp:X", firstSeen: early, end: ended, status: .cancelled),
      contract(.coinPerp, venue: "binance:coinPerp:X", filled: 100_000),
      contract(.delivery, venue: "binance:delivery:X"),
      contract(.usdtPerp, venue: "okx:usdtPerp:X", exchange: "OKX"),
      spot(.bid, venue: "binance:spot:X", exchange: "币安"),
      spot(.bid, venue: "okx:spot:X", exchange: "OKX"),
      spot(.bid, venue: "coinbase:spot:X", exchange: "Coinbase"),
      spot(.ask, venue: "binance:spot:X", exchange: "币安"),
    ]
    r.state.orderFlow?.orders = merged
    let f = frame(r)
    #expect(f.bands.count == 3, "合约买一条、现货买一条、现货卖一条")
    let c = try #require(f.bands.first { $0.key == OrderFlowGroupKey(bucket: 1, side: .bid, contract: true, start: early) })
    #expect(c.group.books.count == 4 && c.group.members.count == 4)
    #expect(c.group.notional == 20_000_000)
    // 4 × 1 倍门槛 = 4 倍 → 第 2 档 4.5 pt（一单单画都是 2 pt）。
    #expect(c.group.tier == 2)
    #expect(c.dark, "任何一单被吃过就是深色")
    #expect(c.color == r.orderFlowBaseColor(side: .bid, contract: true) && c.color != r.state.colors.up)
    let L = r.layout(size: Self.size)
    let spacing = r.state.view.barSpacing(step: b.step, plotW: L.plotW)
    #expect(abs(c.frame.minX - (r.state.view.x(Double(b.time(at: b.count - 14)), plotW: L.plotW) - spacing / 2)) < 0.001,
            "起点取最早的首见")
    #expect(abs(c.frame.maxX - L.plotW) < 0.001, "有一单还挂着就画到右缘")
    let sb = try #require(f.bands.first { $0.key == OrderFlowGroupKey(bucket: 1, side: .bid, contract: false, start: seen) })
    #expect(sb.group.books.count == 3 && sb.group.notional == 3_000_000)
    #expect(!sb.dark && sb.color == Palette.orderFlowUnfilled(r.orderFlowBaseColor(side: .bid, contract: false), bg: r.state.colors.bg))
    #expect(f.bands.contains { $0.key == OrderFlowGroupKey(bucket: 1, side: .ask, contract: false, start: seen) })
    // 图例仍按逐单求和（只算挂着的）。
    #expect(f.bidTotal == 15_000_000 + 3_000_000)
    #expect(f.askTotal == 1_000_000)

    // 全结束了：终点取最晚的结束。
    let allEnded = [
      contract(.usdtPerp, venue: "binance:usdtPerp:X", end: ended, status: .cancelled),
      contract(.coinPerp, venue: "binance:coinPerp:X", end: b.time(at: b.count - 3) + 1, status: .filled, filled: 5_000_000),
    ]
    r.state.orderFlow?.orders = allEnded
    let g = try #require(frame(r).bands.first)
    #expect(g.group.endMs == b.time(at: b.count - 3) + 1)
    #expect(abs(g.frame.maxX - (r.state.view.x(Double(b.time(at: b.count - 3)), plotW: L.plotW) + spacing / 2)) < 0.001)

    // 同一本簿撤了又挂回来：两段是同一堵墙，名义取最近那一单、不累加；成交累加。
    let reposted = [
      contract(.usdtPerp, venue: "binance:usdtPerp:X", notional: 10_000_000, firstSeen: early, end: ended,
               status: .cancelled, filled: 1_000_000),
      contract(.usdtPerp, venue: "binance:usdtPerp:X", notional: 6_000_000, filled: 500_000),
    ]
    let group = try #require(OrderFlowGroup.groups(reposted).first)
    #expect(OrderFlowGroup.groups(reposted).count == 1)
    #expect(group.books.count == 1 && group.books[0].orders == 2)
    #expect(group.notional == 6_000_000)
    #expect(group.filledNotional == 1_500_000)
    #expect(group.isLive && group.endMs == nil)
  }

  // ------------------------------------------------------------ 按时间切段（2026-09-24 夜）
  // 真机 BTC：191 条带画出来 572 小时、真有单挂着的 213 小时——同一桶侧类不分时间合成一条，把空档画成了墙。

  /// 同一桶（合约买 1 桶）上的一单。
  func laneOrder(_ venue: String, firstSeen: Int64, end: Int64? = nil, notional: Double = 10_000_000,
                 filled: Double = 0, price: Double) -> BigOrder {
    var o = Self.order(.usdtPerp, .bid, price: price, firstSeen: firstSeen, end: end,
                       status: end == nil ? .live : (filled > 0 ? .filled : .cancelled),
                       notional: notional, initial: notional, filled: filled, bucket: 1)
    o.venueID = venue
    return o
  }

  @Test("切段：同桶两单空档远大于容差时画两条，各自的起止、名义、深浅只在段内算")
  func segmentsSplitOnLongGap() throws {
    var (r, orders) = Self.renderer()
    let b = r.state.series
    let p = orders[0].price
    let L = r.layout(size: Self.size)
    let spacing = r.state.view.barSpacing(step: b.step, plotW: L.plotW)
    let barLeft = { (i: Int) in r.state.view.x(Double(b.time(at: i)), plotW: L.plotW) - spacing / 2 }
    let barRight = { (i: Int) in r.state.view.x(Double(b.time(at: i)), plotW: L.plotW) + spacing / 2 }
    // 早先那单：挂了一根多就撤了、被吃过一口；后来那单隔了十几根才挂上、还挂着、一口没成交。
    let early = laneOrder("binance:usdtPerp:X", firstSeen: b.time(at: b.count - 30) + 1,
                          end: b.time(at: b.count - 29) + 1, notional: 20_000_000, filled: 1_000, price: p)
    let late = laneOrder("okx:usdtPerp:X", firstSeen: b.time(at: b.count - 12) + 1, notional: 6_000_000, price: p)
    #expect(late.firstSeenMs - early.endMs! > OrderFlowGroup.mergeGapMs(barMs: b.step))
    r.state.orderFlow?.orders = [late, early]
    let f = frame(r)
    #expect(f.bands.count == 2, "空档画成墙：\(f.bands.map(\.key.id))")
    let a = try #require(f.bands.first { $0.key == OrderFlowGroupKey(early) })
    let c = try #require(f.bands.first { $0.key == OrderFlowGroupKey(late) })
    #expect(a.group.members == [early] && c.group.members == [late])
    #expect(abs(a.frame.minX - barLeft(b.count - 30)) < 0.001 && abs(a.frame.maxX - barRight(b.count - 29)) < 0.001,
            "早先那段只画它挂着的那两根")
    #expect(abs(c.frame.minX - barLeft(b.count - 12)) < 0.001 && abs(c.frame.maxX - L.plotW) < 0.001)
    #expect(a.group.notional == 20_000_000 && c.group.notional == 6_000_000, "名义只算段内")
    #expect(a.dark && !c.dark, "深浅只看段内有没有被吃过")
    #expect(!a.group.isLive && a.group.endMs == early.endMs)
    #expect(a.key.id != c.key.id && a.key.id.hasSuffix("|\(early.firstSeenMs)"))
    #expect(f.bidTotal == 6_000_000, "图例仍按逐单求和：只算还挂着的")
    // 命中与详情卡按段：点在早先那段上拿到的是早先那段。
    #expect(ChartRenderer.orderFlowHit(f.bands, x: a.frame.midX, y: a.frame.midY)?.key == a.key)
    r.state.orderFlowSelected = a.key
    #expect(r.orderFlowFocus(size: Self.size)?.group.members == [early])

    // 金额签按段，写的是段内名义：挂着的那段贴主图右缘，结束的那段在它结束点右侧（放不下就收回主图右缘以内）。
    let plotW = r.layout(size: Self.size).plotW
    if let lc = f.labels.first(where: { $0.key == c.key }) {
      #expect(lc.text == "6.0M" && abs(lc.frame.maxX - (plotW - ChartRenderer.orderFlowLabelInset)) < 1e-9)
    }
    if let la = f.labels.first(where: { $0.key == a.key }) {
      #expect(la.text == "20.0M")
      let want = min(a.frame.maxX + ChartRenderer.orderFlowLabelInset, plotW - ChartRenderer.orderFlowLabelInset - la.frame.width)
      #expect(abs(la.frame.minX - want) < 1e-9)
    }

    // 切段的边界：空档恰好等于容差还并，多 1 ms 就断。
    let gap = OrderFlowGroup.mergeGapMs(barMs: b.step)
    let x = laneOrder("binance:usdtPerp:X", firstSeen: 1_000, end: 2_000, price: p)
    let y1 = laneOrder("okx:usdtPerp:X", firstSeen: 2_000 + gap, end: 2_000 + gap + 10, price: p)
    let y2 = laneOrder("okx:usdtPerp:X", firstSeen: 2_000 + gap + 1, end: 2_000 + gap + 10, price: p)
    #expect(OrderFlowGroup.segments([x, y1], gapMs: gap).count == 1)
    #expect(OrderFlowGroup.segments([x, y2], gapMs: gap).count == 2)
    #expect(OrderFlowGroup.mergeGapMs(barMs: 1_000) == 60_000, "秒级周期也至少 60 秒")
    #expect(OrderFlowGroup.mergeGapMs(barMs: 3_600_000) == 3_600_000, "一小时图按一根")
  }

  @Test("切段：空档小于容差（撤了马上挂回来、相邻 K 线）并成一条；区间重叠照旧并")
  func segmentsMergeShortGap() throws {
    var (r, orders) = Self.renderer()
    let b = r.state.series
    let p = orders[0].price
    let gap = OrderFlowGroup.mergeGapMs(barMs: b.step)
    let first = laneOrder("binance:usdtPerp:X", firstSeen: b.time(at: b.count - 20) + 1,
                          end: b.time(at: b.count - 16) + 1, notional: 10_000_000, price: p)
    // 同一本簿撤了、隔半个容差又挂回来。
    let again = laneOrder("binance:usdtPerp:X", firstSeen: first.endMs! + gap / 2,
                          end: first.endMs! + gap / 2 + 3 * b.step, notional: 7_000_000, price: p)
    // 别家在它还挂着时挂上（区间重叠），一直挂着。
    let other = laneOrder("okx:usdtPerp:X", firstSeen: again.firstSeenMs + b.step, notional: 5_000_000, price: p)
    r.state.orderFlow?.orders = [other, again, first]
    let f = frame(r)
    #expect(f.bands.count == 1, "\(f.bands.map(\.key.id))")
    let band = try #require(f.bands.first)
    #expect(band.key == OrderFlowGroupKey(first), "段的身份是段里最早的首见")
    #expect(band.group.members.count == 3 && band.group.books.count == 2)
    #expect(band.group.notional == 12_000_000, "同一本簿取最近那一单（7M，不累加前一截的 10M）+ OKX 5M")
    #expect(band.group.isLive)
    let L = r.layout(size: Self.size)
    #expect(abs(band.frame.maxX - L.plotW) < 0.001)
  }

  @Test("切段：挂着的单续长、新单并进来、回填的历史把段起点前移，选中的那条都不跳走不丢")
  func segmentIdentityStable() throws {
    var (r, orders) = Self.renderer()
    let b = r.state.series
    let p = orders[0].price
    let gap = OrderFlowGroup.mergeGapMs(barMs: b.step)
    let wall = laneOrder("binance:usdtPerp:X", firstSeen: b.time(at: b.count - 12) + 1, price: p)
    // 同桶更早的一段（已经撤了，隔得远），不能被选中的那条认成自己。
    let old = laneOrder("binance:usdtPerp:X", firstSeen: b.time(at: b.count - 40) + 1,
                        end: b.time(at: b.count - 39) + 1, price: p)
    r.state.orderFlow?.orders = [old, wall]
    let key = try #require(frame(r).bands.first { $0.group.isLive }).key
    #expect(key == OrderFlowGroupKey(wall))
    r.state.orderFlowSelected = key
    #expect(r.orderFlowFocus(size: Self.size)?.group.key == key)

    // 1. 挂着的单续长：快照时刻往后走、名义在变——还是同一条，id 不变。
    r.state.orderFlow?.asOfMs += 30 * 60_000
    r.state.orderFlow?.orders[1].notional = 14_000_000
    var focus = try #require(r.orderFlowFocus(size: Self.size))
    #expect(focus.group.key == key && focus.selected && focus.group.notional == 14_000_000)
    #expect(frame(r).bands.contains { $0.key == key })

    // 2. 别家新挂一单并进这一段：段的起点不变，选中的还是它，卡上多一本簿。
    let joined = laneOrder("okx:usdtPerp:X", firstSeen: b.time(at: b.count - 3) + 1, notional: 5_000_000, price: p)
    r.state.orderFlow?.orders.append(joined)
    focus = try #require(r.orderFlowFocus(size: Self.size))
    #expect(focus.group.key == key && focus.group.books.count == 2)

    // 3. 原先那单撤了、容差内又挂回来：仍是同一条。
    r.state.orderFlow?.orders[1].status = .cancelled
    r.state.orderFlow?.orders[1].endMs = b.time(at: b.count - 2) + 1
    r.state.orderFlow?.orders.append(laneOrder("binance:usdtPerp:X", firstSeen: b.time(at: b.count - 2) + 1 + gap / 2, price: p))
    focus = try #require(r.orderFlowFocus(size: Self.size))
    #expect(focus.group.key == key && focus.group.members.count == 3)

    // 4. 服务端回填了一单，把早先那段和这一段接上：段的起点前移到早先那段，选中的键旧了，但仍认得回来。
    let bridge = laneOrder("binance:delivery:X", firstSeen: old.endMs! + 1, end: wall.firstSeenMs + 1, price: p)
    r.state.orderFlow?.orders.insert(bridge, at: 1)
    let merged = try #require(frame(r).bands.first { $0.key.sameLane(key) })
    #expect(merged.key == OrderFlowGroupKey(old) && frame(r).bands.filter { $0.key.sameLane(key) }.count == 1)
    focus = try #require(r.orderFlowFocus(size: Self.size))
    #expect(focus.group.key == merged.key && focus.selected)
    #expect(r.orderFlowIsSelected(merged.group), "再点同一条要能收起")
    // 同桶另一段（没接上的时候）不会被认成选中的那条。
    let lone = try #require(OrderFlowGroup.groups([old], gapMs: gap).first)
    #expect(!lone.covers(key))
  }

  // ------------------------------------------------------------ 相邻桶并墙、屏内排名、去碎屑（2026-09-25）
  // 真机 ETH / SOL：步长小，一堵墙摊在相邻几个桶里画成几条各写各的金额；一屏几百条 2 pt 带没有主次。

  /// 按步长摆一单：桶号 `bucket`、价在桶中间；默认合约卖、10M（门槛 5M 的 2 倍）。
  func wallOrder(_ r: ChartRenderer, step: Double, bucket: Int64, side: BookSide = .ask,
                 product: OrderFlowProduct = .usdtPerp, venue: String = "binance:usdtPerp:X",
                 from: Int, to: Int? = nil, notional: Double = 10_000_000) -> BigOrder {
    let b = r.state.series
    var o = Self.order(product, side, price: (Double(bucket) + 0.5) * step, firstSeen: b.time(at: b.count - from) + 1,
                       end: to.map { b.time(at: b.count - $0) + 1 }, status: to == nil ? .live : .cancelled,
                       notional: notional, initial: notional,
                       threshold: product == .spot ? 1_000_000 : 5_000_000, bucket: bucket)
    o.venueID = venue
    return o
  }

  /// 夹具换成按步长摆的一组单；步长取最新价的万分之一（ETH 步长 1 ≈ 价的万分之四，同一量级），
  /// 几十个桶以内都还落在主图里。
  func wallRenderer() -> (ChartRenderer, step: Double, b0: Int64) {
    var (r, _) = Self.renderer()
    let p = r.state.series.close.last!
    let step = p * 0.0001
    r.state.orderFlow?.thresholds.step = step
    return (r, step, Int64((p / step).rounded(.down)))
  }

  @Test("并墙：同侧同类、桶号相邻、时间连着的段并成一堵；隔一桶、不同类、不同侧、时间断开的不并")
  func wallsMergeAdjacentBuckets() throws {
    var (r, step, b0) = wallRenderer()
    let a = wallOrder(r, step: step, bucket: b0 + 5, from: 20)
    let bMid = wallOrder(r, step: step, bucket: b0 + 6, venue: "okx:usdtPerp:X", from: 15, to: 5)
    let c = wallOrder(r, step: step, bucket: b0 + 7, from: 10)
    let skip = wallOrder(r, step: step, bucket: b0 + 9, from: 40, to: 35)  // 隔一桶、时间也不挨着
    let spot = wallOrder(r, step: step, bucket: b0 + 8, product: .spot, venue: "binance:spot:X", from: 10,
                         notional: 2_000_000)                                // 挨着但是现货
    let bid = wallOrder(r, step: step, bucket: b0 + 8, side: .bid, from: 10)  // 挨着但是买单
    let old = wallOrder(r, step: step, bucket: b0 + 4, from: 60, to: 50)       // 挨着但时间断开
    r.state.orderFlow?.orders = [c, skip, spot, a, bid, old, bMid]
    let f = frame(r)
    #expect(f.bands.count == 5, "\(f.bands.map(\.key.id))")
    let wall = try #require(f.bands.first { $0.key == OrderFlowGroupKey(a) }, "墙的键 = 最早起的那一段")
    let g = wall.group
    #expect(g.bucketCount == 3 && g.bucketLow == b0 + 5 && g.bucketHigh == b0 + 7 && g.isRange)
    #expect(abs(g.priceLow - Double(b0 + 5) * step) < 1e-9 && abs(g.priceHigh - Double(b0 + 8) * step) < 1e-9,
            "价位范围：最低桶的桶价 … 最高桶的桶价 + 步长")
    #expect(g.notional == 30_000_000 && g.drawNotional == 30_000_000, "名义按各段相加")
    // 3 × 2 倍 = 6 倍 → 第 2 档 4.5 pt（一段单画都是第 1 档）。
    #expect(g.tier == 2)
    #expect(g.books.count == 3 && Set(g.books.map(\.bucket)) == [b0 + 5, b0 + 6, b0 + 7], "一本簿一桶一行")
    #expect(g.books.allSatisfy { abs($0.price - (Double($0.bucket) + 0.5) * step) < 1e-9 }, "每行带自己那一桶的价")
    #expect(g.isLive && g.endMs == nil)
    // 芯线画在代表价上（主档、还挂着 → 2.5 pt）；整个价位范围垫一层 10% 的淡色（范围比芯窄时不垫）。
    #expect(wall.role == .main && !wall.thin)
    #expect(abs(wall.frame.height - 2.5) < 1e-9 && abs(wall.frame.midY - y(r, g.price)) < 1e-6)
    let rangeHeight = abs(y(r, g.priceLow) - y(r, g.priceHigh))
    if let span = wall.span {
      #expect(span.minY <= y(r, g.priceHigh) + 1e-9 && span.maxY >= y(r, g.priceLow) - 1e-9)
      #expect(span.minX == wall.frame.minX && span.maxX == wall.frame.maxX)
    } else {
      #expect(rangeHeight <= wall.frame.height + 1e-9, "范围比芯线还窄才不垫淡底")
    }
    let L = r.layout(size: Self.size)
    let spacing = r.state.view.barSpacing(step: r.state.series.step, plotW: L.plotW)
    let b = r.state.series
    #expect(abs(wall.frame.minX - (r.state.view.x(Double(b.time(at: b.count - 20)), plotW: L.plotW) - spacing / 2)) < 0.001)
    #expect(abs(wall.frame.maxX - L.plotW) < 0.001)
    // 标签写合计：名义最大、先放，一定有。
    #expect(f.labels.contains { $0.key == wall.key && $0.text == "30.0M" })
    // 不并的几条各自成一条。
    for o in [skip, spot, bid, old] {
      #expect(f.bands.contains { $0.key == OrderFlowGroupKey(o) && $0.group.bucketCount == 1 }, "\(o.id)")
    }
    // 点中、出卡都是整堵墙：点在芯上；点在淡色范围里、离别的带都够远的地方也认这堵墙。
    #expect(ChartRenderer.orderFlowHit(f.bands, x: wall.frame.midX, y: wall.frame.midY)?.key == wall.key)
    if let span = wall.span,
       let yFar = stride(from: span.minY, through: span.maxY, by: 0.5).first(where: { yy in
         f.bands.allSatisfy { max(0, abs(yy - $0.frame.midY) - max($0.frame.height, ChartRenderer.orderFlowHitHeight) / 2) > 8.5 }
       }) {
      #expect(ChartRenderer.orderFlowHit(f.bands, x: wall.frame.midX, y: yFar)?.key == wall.key)
    }
    r.state.orderFlowSelected = wall.key
    #expect(r.orderFlowFocus(size: Self.size)?.group.members.count == 3)

    // 连成串：5–6 重叠、6–7 重叠，5 与 7 不挨着也在同一堵里；空档恰好等于容差还并。
    let gap = OrderFlowGroup.mergeGapMs(barMs: b.step)
    func seg(_ bucket: Int64, _ start: Int64, _ end: Int64?) -> OrderFlowGroup.Segment {
      OrderFlowGroup.Segment(key: OrderFlowGroupKey(bucket: bucket, side: .ask, contract: true, start: start),
                             members: [], endMs: end)
    }
    #expect(OrderFlowGroup.walls([seg(1, 0, 100), seg(2, 100 + gap, 200 + gap)], gapMs: gap).count == 1)
    #expect(OrderFlowGroup.walls([seg(1, 0, 100), seg(2, 101 + gap, 200 + gap)], gapMs: gap).count == 2)
    #expect(OrderFlowGroup.walls([seg(1, 0, 100), seg(2, 50, 400), seg(3, 300, nil)], gapMs: gap).count == 1)
    #expect(OrderFlowGroup.walls([seg(1, 0, 100), seg(3, 0, 100)], gapMs: gap).count == 2, "隔一桶不并")
    // 挂着的段（结束无穷远）够得着之后起的一切；更早起的段结束得够晚才挨上。
    #expect(OrderFlowGroup.walls([seg(1, 100_000_000, nil), seg(2, 500_000_000, 500_000_001)], gapMs: gap).count == 1)
    #expect(OrderFlowGroup.walls([seg(1, 100_000_000, nil), seg(2, 0, 10)], gapMs: gap).count == 2)
    let key = try #require(OrderFlowGroup.walls([seg(2, 50, 400), seg(1, 50, 100), seg(3, 300, nil)], gapMs: gap).first).key
    #expect(key.bucket == 1 && key.start == 50, "起点一样取桶小的")
  }

  @Test("并墙要成块：价格走着走着前后接力的段不链成一片（要有共同在场的时刻），一堵最多 maxWallBuckets 个桶")
  func wallsStayCompact() {
    let gap: Int64 = 60_000
    func seg(_ bucket: Int64, _ start: Int64, _ end: Int64?) -> OrderFlowGroup.Segment {
      OrderFlowGroup.Segment(key: OrderFlowGroupKey(bucket: bucket, side: .ask, contract: true, start: start),
                             members: [], endMs: end)
    }
    let hour: Int64 = 3_600_000
    // 1. 漂移：每桶挂一个半小时、下一桶晚一小时起。两两相邻都挨着，但 0 与 2 从来不同时在——
    //    首版并查集会把 30 个桶链成一堵。现在每堵最多两段。
    let drift = (0..<30).map { i in seg(Int64(i), Int64(i) * hour, Int64(i) * hour + hour * 3 / 2) }
    let driftWalls = OrderFlowGroup.walls(drift, gapMs: gap)
    #expect(driftWalls.allSatisfy { $0.segments.count <= 2 }, "\(driftWalls.map(\.segments.count))")
    #expect(driftWalls.count == 15)
    // 共同时刻：每堵墙最晚的起点 ≤ 最早的结束 + 容差。
    for w in driftWalls {
      let latest = w.segments.map(\.key.start).max()!
      let earliestEnd = w.segments.compactMap(\.endMs).min().map { $0 + gap } ?? .max
      #expect(latest <= earliestEnd)
    }
    // 2. 挂着的一排：12 个相邻桶同时挂着，切成 5 + 5 + 2，每堵不超过 maxWallBuckets。
    let row = (0..<12).map { i in seg(Int64(100 + i), 1_000 + Int64(i), nil) }
    let rowWalls = OrderFlowGroup.walls(row, gapMs: gap)
    #expect(rowWalls.map(\.segments.count).sorted() == [2, 5, 5])
    for w in rowWalls {
      let bs = w.segments.map(\.key.bucket)
      #expect(bs.max()! - bs.min()! + 1 <= Int64(OrderFlowGroup.maxWallBuckets))
    }
    // 3. 与输入顺序无关。
    let shuffled = OrderFlowGroup.walls(row.reversed(), gapMs: gap)
    #expect(Set(shuffled.map(\.key)) == Set(rowWalls.map(\.key)))
    #expect(Set(OrderFlowGroup.walls(drift.reversed(), gapMs: gap).map(\.key)) == Set(driftWalls.map(\.key)))
  }

  @Test("并墙：键跨帧稳定——挂着续长、后来的段并进来键不变；回填更早的段键前移，旧键按 covers 认回来")
  func wallIdentityStable() throws {
    var (r, step, b0) = wallRenderer()
    let a = wallOrder(r, step: step, bucket: b0 + 5, from: 20)
    let c = wallOrder(r, step: step, bucket: b0 + 6, from: 12)
    r.state.orderFlow?.orders = [a, c]
    let key = OrderFlowGroupKey(a)
    #expect(frame(r).bands.map(\.key) == [key])
    r.state.orderFlowSelected = key

    // 1. 续长：快照往后走、名义在变。
    r.state.orderFlow?.asOfMs += 30 * 60_000
    r.state.orderFlow?.orders[0].notional = 14_000_000
    var focus = try #require(r.orderFlowFocus(size: Self.size))
    #expect(focus.group.key == key && focus.group.notional == 24_000_000)

    // 2. 后来的段并进来（上面再挨一桶）：键不变，范围变宽。
    let later = wallOrder(r, step: step, bucket: b0 + 7, venue: "okx:usdtPerp:X", from: 3)
    r.state.orderFlow?.orders.append(later)
    focus = try #require(r.orderFlowFocus(size: Self.size))
    #expect(focus.group.key == key && focus.group.bucketCount == 3)

    // 3. 回填了下面一桶更早的段、和这堵墙时间上接上：键前移到那一段，旧键仍认得回来。
    // （它要一直在到最后那一段起来之后：墙里得有一个所有段都在的时刻。）
    let early = wallOrder(r, step: step, bucket: b0 + 4, venue: "binance:coinPerp:X", from: 30, to: 2)
    r.state.orderFlow?.orders.insert(early, at: 0)
    let bands = frame(r).bands
    #expect(bands.count == 1)
    let merged = try #require(bands.first)
    #expect(merged.key == OrderFlowGroupKey(early) && merged.group.covers(key))
    focus = try #require(r.orderFlowFocus(size: Self.size))
    #expect(focus.group.key == merged.key && focus.selected)
    #expect(r.orderFlowIsSelected(merged.group), "再点同一条要能收起")
    // 同侧同类、别的桶或别的时间的墙不认。
    let other = try #require(OrderFlowGroup.groups([wallOrder(r, step: step, bucket: b0 + 5, from: 60, to: 50)],
                                                   step: step).first)
    #expect(!other.covers(key) && !other.looselyCovers(key))
  }

  @Test("去碎屑：已结束、活不过一根 K 线的段不画（挂着的留，恰好一根的留）；图例不受影响")
  func shortLivedDropped() throws {
    var (r, step, b0) = wallRenderer()
    let b = r.state.series
    var flash = wallOrder(r, step: step, bucket: b0 + 5, from: 10, to: 10)
    flash.endMs = flash.firstSeenMs + b.step - 1
    var oneBar = wallOrder(r, step: step, bucket: b0 + 9, from: 10, to: 9)
    oneBar.endMs = oneBar.firstSeenMs + b.step
    let fresh = wallOrder(r, step: step, bucket: b0 + 13, side: .bid, from: 1)   // 刚挂上，挂着
    r.state.orderFlow?.orders = [flash, oneBar, fresh]
    let f = frame(r)
    #expect(!f.bands.contains { $0.key == OrderFlowGroupKey(flash) })
    #expect(f.bands.contains { $0.key == OrderFlowGroupKey(oneBar) })
    #expect(f.bands.contains { $0.key == OrderFlowGroupKey(fresh) })
    #expect(f.bidTotal == 10_000_000, "图例按逐单还挂着的算")
    // 碎屑不当桥：两段之间一条活不过一根的段，不把它们并成一堵。
    let lo = wallOrder(r, step: step, bucket: b0 + 20, from: 30, to: 20)
    var bridge = wallOrder(r, step: step, bucket: b0 + 21, from: 20, to: 20)
    bridge.endMs = bridge.firstSeenMs + 1
    let hi = wallOrder(r, step: step, bucket: b0 + 22, from: 20, to: 10)
    r.state.orderFlow?.orders = [lo, bridge, hi]
    #expect(frame(r).bands.count == 2)
    #expect(OrderFlowGroup.groups([lo, bridge, hi], step: step).count == 1, "不去碎屑时三段连成一堵")
    #expect(OrderFlowGroup.groups([lo, bridge, hi], minLifeMs: b.step, step: step).count == 2)
  }

  @Test("屏内排名：前 6 名主（2 / 2.5 pt、写金额），7–18 名次（1 pt、70%、不写），其余底噪（1 pt、35%）；挂着的底噪升成次")
  func rankRoles() throws {
    var (r, step, b0) = wallRenderer()
    let pane = r.layout(size: Self.size).main
    let count = 25
    let pitch = (pane.h - 40) / Double(count)
    #expect(pitch >= 9, "主图够高才摆得开：\(pane.h)")
    // 一桶一堵，桶号隔开两格（不并墙）；名义从大到小，价从上往下错开，互不相碍。
    var orders: [BigOrder] = []
    for i in 0..<count {
      let p = price(r, atY: pane.y + 20 + pitch * Double(i))
      var o = wallOrder(r, step: step, bucket: b0 + Int64(3 * i), from: 30, to: i == count - 1 ? nil : 5,
                        notional: Double(40 - i) * 1_250_000)
      o.price = p
      o.threshold = 5_000_000  // 名义正好是门槛四分之一格的整数倍：排名没有并列
      orders.append(o)
    }
    r.state.orderFlow?.orders = orders.shuffled()
    let f = frame(r)
    #expect(f.bands.count == count)
    let byKey = Dictionary(uniqueKeysWithValues: f.bands.map { ($0.key, $0) })
    for (i, o) in orders.enumerated() {
      let band = try #require(byKey[OrderFlowGroupKey(o)])
      let want: ChartRenderer.OrderFlowRole = i < 6 ? .main : i < 18 ? .secondary : i == count - 1 ? .secondary : .noise
      #expect(band.role == want, "第 \(i + 1) 名")
      switch want {
      case .main: #expect(!band.thin && band.frame.height == (o.endMs == nil ? 2.5 : 2) && band.alpha == 1)
      case .secondary: #expect(band.frame.height == 1 && band.alpha == 0.7)
      case .noise: #expect(band.frame.height == 1 && band.alpha == 0.35 && !band.thin)
      }
      #expect(abs(band.frame.midY - y(r, o.price)) < 1e-9, "不挪位")
    }
    #expect(f.labels.allSatisfy { l in byKey[l.key]?.role == .main }, "只有主写金额")
    #expect(!f.labels.isEmpty)
    // 画的先后：底噪在最下面。
    let firstNonNoise = try #require(f.bands.firstIndex { $0.role != .noise })
    #expect(f.bands[..<firstNonNoise].allSatisfy { $0.role == .noise })
    #expect(f.bands[firstNonNoise...].allSatisfy { $0.role != .noise })
    // 名义一样的先起的在前。
    var tieEarly = orders[0]; tieEarly.firstSeenMs -= 60_000
    let e = try #require(OrderFlowGroup(key: OrderFlowGroupKey(tieEarly), members: [tieEarly]))
    let l = try #require(OrderFlowGroup(key: OrderFlowGroupKey(orders[0]), members: [orders[0]]))
    #expect(OrderFlowGroup.drawOrder(e, l) && !OrderFlowGroup.drawOrder(l, e))
    // 每帧现排、结果确定：换个顺序给同一批单，画出来一样。
    let again = frame(r)
    r.state.orderFlow?.orders = orders.reversed()
    #expect(frame(r) == again)
    // 画到像素上：底噪是淡的。
    let L = r.layout(size: Self.size)
    let image = UIGraphicsImageRenderer(size: Self.size).image { context in
      #expect(r.drawOrderFlow(context.cgContext, pane: L.main, range: r.priceRange(size: Self.size), L: L) == count)
    }
    #expect(image.cgImage != nil)
  }

  @Test("纵向去挤：按名义从大到小落线，和已落下的纵向重叠（含 1 pt 间隙）的压成 1 pt 细线、不写金额，不挪位；同价叠着点出大的")
  func thinLines() throws {
    var (r, orders) = Self.renderer()
    let p = orders[0].price
    let seen = orders[0].firstSeenMs
    let cy = y(r, p)
    // 大：合约买 40M（主、挂着 → 2.5 pt）；小：现货买同价 1.5M、合约卖在 3 pt 以外（2.5 pt 线加 1 pt 间隙，重叠）。
    let big = Self.order(.usdtPerp, .bid, price: p, firstSeen: seen, notional: 40_000_000, initial: 40_000_000, bucket: 1)
    let small = Self.order(.spot, .bid, price: p, firstSeen: seen, notional: 1_500_000, initial: 1_500_000,
                           filled: 10, threshold: 1_000_000, bucket: 1)
    let nearPrice = price(r, atY: cy - 3)
    let near = Self.order(.coinPerp, .ask, price: nearPrice, firstSeen: seen, bucket: 2)
    // 远：往上 20 pt，互不相碍。
    let far = Self.order(.delivery, .ask, price: price(r, atY: cy - 20), firstSeen: seen, bucket: 5)
    r.state.orderFlow?.orders = [small, near, big, far]
    let f = frame(r)
    let bigBand = try #require(f.bands.first { $0.key == OrderFlowGroupKey(big) })
    let smallBand = try #require(f.bands.first { $0.key == OrderFlowGroupKey(small) })
    let nearBand = try #require(f.bands.first { $0.key == OrderFlowGroupKey(near) })
    let farBand = try #require(f.bands.first { $0.key == OrderFlowGroupKey(far) })
    #expect(!bigBand.thin && bigBand.frame.height == 2.5)
    #expect(smallBand.thin && smallBand.frame.height == 1)
    #expect(abs(smallBand.frame.midY - cy) < 1e-9, "不挪位")
    #expect(smallBand.dark && smallBand.color == r.orderFlowBaseColor(small), "细线仍是本色深浅")
    #expect(nearBand.thin && abs(nearBand.frame.midY - y(r, nearPrice)) < 1e-9)
    #expect(!farBand.thin && farBand.frame.height == 2.5)
    #expect(!f.labels.contains { $0.key == smallBand.key || $0.key == nearBand.key }, "细线不写金额")
    // 细线画在整条之后（压在上面）。
    let firstThin = try #require(f.bands.firstIndex { $0.thin })
    #expect(f.bands[firstThin...].allSatisfy(\.thin) && f.bands[..<firstThin].allSatisfy { !$0.thin })
    // 细线仍点得中：点在错开的细线上给细线；和大单同价叠着的，点下去给名义大的那条。
    #expect(ChartRenderer.orderFlowHit(f.bands, x: nearBand.frame.midX, y: nearBand.frame.midY)?.key == nearBand.key)
    #expect(ChartRenderer.orderFlowHit(f.bands, x: smallBand.frame.midX, y: smallBand.frame.midY)?.key == bigBand.key)
    #expect(ChartRenderer.orderFlowHit(f.bands, x: bigBand.frame.midX, y: bigBand.frame.maxY + 1)?.key == bigBand.key)
    #expect(r.orderFlowHit(at: CGPoint(x: nearBand.frame.midX, y: nearBand.frame.midY), size: Self.size)?.key == nearBand.key)

    // 横向不交叠就不挤：小的在大的首见之前就结束了。
    let b = r.state.series
    let before = Self.order(.spot, .bid, price: p, firstSeen: b.time(at: b.count - 30) + 1,
                            end: b.time(at: b.count - 20) + 1, status: .cancelled, notional: 1_500_000,
                            initial: 1_500_000, threshold: 1_000_000, bucket: 1)
    r.state.orderFlow?.orders = [big, before]
    #expect(frame(r).bands.allSatisfy { !$0.thin })

    // 纵向隔 1 pt 以上也不挤：2.5 pt 大线下沿 + 1 pt 间隙之外摆一条小线（也是主档、挂着 → 2.5 pt）。
    let gapPrice = price(r, atY: cy + 1.25 + 1 + 1.25 + 0.2)
    let apart = Self.order(.spot, .bid, price: gapPrice, firstSeen: seen, notional: 1_500_000, initial: 1_500_000,
                           threshold: 1_000_000, bucket: 7)
    let touching = Self.order(.spot, .ask, price: price(r, atY: cy - 1.25 - 1 - 1.25 + 0.2), firstSeen: seen,
                              notional: 1_500_000, initial: 1_500_000, threshold: 1_000_000, bucket: 8)
    r.state.orderFlow?.orders = [big, apart, touching]
    let g = frame(r)
    #expect(g.bands.first { $0.key == OrderFlowGroupKey(apart) }?.thin == false)
    #expect(g.bands.first { $0.key == OrderFlowGroupKey(touching) }?.thin == true, "间隙不足 1 pt 算重叠")
  }

  @Test("金额签：只给主档整条；挂着的贴主图右缘、结束的在结束点右侧；纵向撞了名义小的让位（挪 ≤ 32 pt，挪不开就不放）")
  func labels() throws {
    var (r, orders) = Self.renderer()
    let L = r.layout(size: Self.size)
    let inset = ChartRenderer.orderFlowLabelInset, gap = ChartRenderer.orderFlowLabelGap
    let f = frame(r)
    #expect(!f.labels.isEmpty)
    for label in f.labels {
      let band = try #require(f.bands.first { $0.key == label.key })
      #expect(!band.thin && band.role == .main)
      #expect(label.text == ChartRenderer.orderFlowAmount(band.group.notional))
      #expect(label.fill == band.color)
      #expect(label.ink == ChartRenderer.orderFlowLabelInk(mixHex(band.color, r.state.colors.bg, 1 - ChartRenderer.orderFlowLabelAlpha)),
              "签底 80% 不透明，字色按叠出来的颜色算对比")
      #expect(abs(label.frame.height - ChartRenderer.orderFlowLabelHeight) < 1e-6)
      #expect(abs(label.frame.midY - band.frame.midY) <= ChartRenderer.orderFlowLabelMaxShift + 1e-9)
      #expect(label.frame.maxX <= L.plotW - inset + 1e-9, "不进价格刻度列")
      if band.group.isLive { #expect(abs(label.frame.maxX - (L.plotW - inset)) < 1e-9, "挂着的贴主图右缘") }
      else {
        let want = min(band.frame.maxX + inset, L.plotW - inset - label.frame.width)
        #expect(abs(label.frame.minX - want) < 1e-9, "结束的在结束点右侧")
      }
    }
    // 签彼此不叠。
    for (i, a) in f.labels.enumerated() {
      for b in f.labels[(i + 1)...] {
        #expect(a.frame.maxX <= b.frame.minX || b.frame.maxX <= a.frame.minX
                  || a.frame.maxY + gap <= b.frame.minY + 1e-9 || b.frame.maxY + gap <= a.frame.minY + 1e-9)
      }
    }
    #expect(f.labels.contains { $0.text == "5.3M" })
    // 字色取带色的对比色。
    #expect(ChartRenderer.orderFlowLabelInk("#E1D610") == "#141414")
    #expect(ChartRenderer.orderFlowLabelInk("#CF09E7") == "#FFFFFF")

    // 窄段（挂了一根多就撤了）也写：签在结束点右侧，放不下就收回主图右缘以内。
    let b = r.state.series
    let p = orders[0].price, cy = y(r, p)
    let narrow = Self.order(.usdtPerp, .bid, price: p, firstSeen: b.time(at: b.count - 8) + 1,
                            end: b.time(at: b.count - 7) + 2, status: .cancelled, bucket: 1)
    r.state.orderFlow?.orders = [narrow]
    let n = frame(r)
    #expect(n.bands.count == 1 && n.labels.count == 1)
    let nl = try #require(n.labels.first)
    #expect(abs(nl.frame.minX - min(n.bands[0].frame.maxX + inset, L.plotW - inset - nl.frame.width)) < 1e-9)

    // 两条线上下隔 6 pt：线不相碍（都是整条），签 16 pt 高会碰——名义大的居中在自己线上，小的挪到它上方。
    let seen = b.time(at: b.count - 30) + 1
    let big = Self.order(.usdtPerp, .bid, price: p, firstSeen: seen, notional: 20_000_000, initial: 20_000_000, bucket: 1)
    let small = Self.order(.coinPerp, .ask, price: price(r, atY: cy - 6), firstSeen: seen, bucket: 2)
    r.state.orderFlow?.orders = [small, big]
    let c = frame(r)
    #expect(c.bands.allSatisfy { !$0.thin })
    #expect(c.labels.count == 2)
    let bl = try #require(c.labels.first { $0.key == OrderFlowGroupKey(big) })
    let sl = try #require(c.labels.first { $0.key == OrderFlowGroupKey(small) })
    #expect(abs(bl.frame.midY - cy) < 1e-9, "名义大的不挪")
    #expect(sl.frame.maxY <= bl.frame.minY - gap + 1e-9, "小的让到上方")
    #expect(abs(sl.frame.midY - (cy - 6)) <= ChartRenderer.orderFlowLabelMaxShift)

    // 六条主线挤在 20 pt 里：签挪不开的就不放，放了的彼此不叠、离自己的线不超过 32 pt，名义最大的一定有签。
    var crowd: [BigOrder] = []
    for i in 0..<6 {
      let even = i % 2 == 0
      let product: OrderFlowProduct = even ? .usdtPerp : .coinPerp
      let side: BookSide = even ? .bid : .ask
      let at: Double = price(r, atY: cy + 4 * Double(i))
      let amount = Double(30 - i) * 1_000_000
      crowd.append(Self.order(product, side, price: at, firstSeen: seen, notional: amount, initial: amount,
                              bucket: Int64(10 + 3 * i)))
    }
    r.state.orderFlow?.orders = crowd
    let k = frame(r)
    #expect(k.bands.allSatisfy { !$0.thin } && k.bands.count == 6)
    #expect(k.labels.count < 6)
    #expect(k.labels.contains { $0.key == OrderFlowGroupKey(crowd[0]) })
    for (i, a) in k.labels.enumerated() {
      let line = try #require(k.bands.first { $0.key == a.key })
      #expect(abs(a.frame.midY - line.frame.midY) <= ChartRenderer.orderFlowLabelMaxShift + 1e-9)
      for o in k.labels[(i + 1)...] { #expect(a.frame.maxY + gap <= o.frame.minY + 1e-9 || o.frame.maxY + gap <= a.frame.minY + 1e-9) }
    }
    // 挤成细线的不写。
    let thin = Self.order(.spot, .bid, price: p, firstSeen: seen, notional: 1_500_000, initial: 1_500_000,
                          threshold: 1_000_000, bucket: 1)
    r.state.orderFlow?.orders = [big, thin]
    #expect(frame(r).labels.map(\.key) == [OrderFlowGroupKey(big)])
    // 真画到像素上。
    let image = UIGraphicsImageRenderer(size: Self.size).image { context in
      #expect(r.drawOrderFlowLabels(context.cgContext, pane: L.main, range: r.priceRange(size: Self.size), L: L) == 1)
    }
    #expect(image.cgImage != nil)
  }

  @Test("详情卡上限：宽 ≤ 85% 绘图区、高 ≤ 55% 主图且不越过线的命中带（至少 8 pt 高）")
  func cardBudget() throws {
    typealias B = OrderFlowCardBudget
    #expect(B.maxWidth(plotW: 400) == 340)
    // 带在上面：卡摆下面，最高 55% 主图；带在下面：摆上面，最高不越过带。
    let top = B.placement(bandY: 60, bandHalf: 3, top: 20, bottom: 420, mainHeight: 400)
    #expect(top.below && abs(top.maxHeight - 220) < 1e-9)
    let low = B.placement(bandY: 380, bandHalf: 3, top: 20, bottom: 420, mainHeight: 400)
    #expect(!low.below && abs(low.maxHeight - 220) < 1e-9)
    // 带在中间偏上、主图矮：摆下面，最高就是带下沿到主图下沿（140 < 55% × 280）。
    let mid = B.placement(bandY: 150, bandHalf: 4, top: 20, bottom: 300, mainHeight: 280)
    #expect(mid.below && mid.maxHeight == 140)
    // 焦点带出来的上限：宽按绘图区、高按主图；卡躲的是命中带，线细也按 8 pt 高算。
    var (r, orders) = Self.renderer()
    r.state.orderFlowSelected = OrderFlowGroupKey(orders[0])
    let focus = try #require(r.orderFlowFocus(size: Self.size))
    let L = r.layout(size: Self.size)
    #expect(focus.cardMaxWidth == L.plotW * 0.85)
    #expect(focus.mainHeight == L.main.h)
    #expect(focus.bandHalf == ChartRenderer.orderFlowHitHeight / 2)
    let place = focus.cardPlacement
    #expect(place.maxHeight <= L.main.h * 0.55)
    if place.below { #expect(focus.bandY + focus.bandHalf + 6 + place.maxHeight <= focus.mainBottom + 1e-9) }
    else { #expect(focus.bandY - focus.bandHalf - 6 - place.maxHeight >= focus.mainTop - 1e-9) }
  }

  @Test("深浅：被吃过（成交名义 > 0）是本色，一口没成交往底色混 45%；撤单 / 失联不再另画")
  func shades() throws {
    let (r, _) = Self.renderer()
    let t = r.state.colors
    let bid = r.orderFlowBaseColor(side: .bid, contract: true), ask = r.orderFlowBaseColor(side: .ask, contract: true)
    let f = frame(r)
    let fresh = try #require(bandAt(f, bucket: 1))
    #expect(!fresh.dark && fresh.color == Palette.orderFlowUnfilled(bid, bg: t.bg))
    let coin = try #require(bandAt(f, bucket: 4))
    #expect(coin.dark && coin.color == ask, "部分成交也是深色")
    let filled = try #require(bandAt(f, bucket: 5))
    #expect(filled.dark && filled.color == bid)
    let cancelled = try #require(bandAt(f, bucket: 6))
    #expect(!cancelled.dark && cancelled.color == Palette.orderFlowUnfilled(ask, bg: t.bg))
    var eaten = fresh.group.members[0]; eaten.filledNotional = 1
    #expect(r.orderFlowColor(eaten) == bid, "被吃一口就转深")
  }

  @Test("颜色：合约买蓝卖品红、现货买黄绿卖浅紫，一律不用蜡烛涨跌色、不随红涨绿跌翻；按图区底色明暗两套")
  func colors() throws {
    for redUp in [false, true] {
      let (r, orders) = Self.renderer(redUp: redUp)
      let t = r.state.colors
      let p = Palette.orderFlow(bg: t.bg)
      #expect(r.orderFlowBaseColor(orders[0]) == p.contractBid)
      #expect(r.orderFlowBaseColor(orders[3]) == p.contractAsk, "币本位永续和 U 本位同一套")
      #expect(r.orderFlowBaseColor(orders[5]) == p.contractAsk, "交割同一套")
      #expect(r.orderFlowBaseColor(orders[1]) == p.spotBid)
      #expect(r.orderFlowBaseColor(orders[2]) == p.spotAsk)
      #expect(p == Palette.orderFlowOnLight, "默认夹具是浅色底")
      for o in orders {
        let c = r.orderFlowBaseColor(o)
        #expect(c != t.up && c != t.down)
        #expect(Palette.hueDistance(c, t.up) >= 60 && Palette.hueDistance(c, t.down) >= 60, "\(o.product) \(o.side) 和蜡烛撞色")
      }
    }
    #expect(Self.renderer(redUp: true).0.state.colors.up == Palette.chart(Palette.lightSeed, redUp: true).up)
    // 六套皮肤按底色分两套；浅色档和底色、和深色档都拉得开。
    for skin in Skin.allCases {
      for dark in [false, true] {
        var (r, orders) = Self.renderer()
        r.state.paletteSeed = Palette.seed(skin, dark: dark)
        let want = dark ? Palette.orderFlowOnDark : Palette.orderFlowOnLight
        #expect(r.orderFlowBaseColor(orders[0]) == want.contractBid, "\(skin) \(dark)")
        #expect(r.orderFlowBaseColor(orders[1]) == want.spotBid, "\(skin) \(dark)")
        #expect(r.orderFlowBaseColor(orders[2]) == want.spotAsk, "\(skin) \(dark)")
        #expect(r.orderFlowBaseColor(orders[3]) == want.contractAsk, "\(skin) \(dark)")
        let bg = r.state.colors.bg
        for o in orders {
          var light = o; light.filledNotional = 0
          var deep = o; deep.filledNotional = 1
          let lc = r.orderFlowColor(light), dc = r.orderFlowColor(deep)
          #expect(Self.distance(lc, bg) > 0.12, "\(skin) \(dark) \(o.product) 浅色档要和底色拉开：\(lc.value) vs \(bg.value)")
          #expect(Self.distance(lc, dc) > 0.10, "\(skin) \(dark) \(o.product) 深浅两档要分得开")
        }
      }
    }
  }

  /// 两色在 RGB 里的欧氏距离（0…√3）。
  static func distance(_ a: Hex, _ b: Hex) -> Double {
    let x = a.rgba, y = b.rgba
    return ((x.r - y.r) * (x.r - y.r) + (x.g - y.g) * (x.g - y.g) + (x.b - y.b) * (x.b - y.b)).squareRoot()
  }

  @Test("显示开关：关现货 / 合约 / 已成交 / 已撤销各自只藏那一类（逐单过滤后再合并）；合计只算还挂着的")
  func display() {
    var (r, orders) = Self.renderer()
    let live = orders.filter(\.isLive)
    #expect(frame(r).bidTotal == live.filter { $0.side == .bid }.map(\.notional).reduce(0, +))
    #expect(frame(r).askTotal == live.filter { $0.side == .ask }.map(\.notional).reduce(0, +))
    r.state.orderFlowDisplay.spot = false
    #expect(frame(r).bands.allSatisfy { $0.group.contract })
    #expect(frame(r).bands.count == 4)
    r.state.orderFlowDisplay = .all
    r.state.orderFlowDisplay.contract = false
    #expect(frame(r).bands.allSatisfy { !$0.group.contract })
    r.state.orderFlowDisplay = .all
    r.state.orderFlowDisplay.filled = false
    #expect(!frame(r).bands.contains { $0.group.members.contains { $0.status == .filled } })
    r.state.orderFlowDisplay.cancelled = false
    #expect(!frame(r).bands.contains { $0.group.members.contains { $0.status == .cancelled } })
    #expect(frame(r).bands.count == 4)
  }

  @Test("点中判定：线按至少 8 pt 高的带子算，横向两头放 4 pt、竖向再放 8 pt；同价叠着点出名义大的，错开的细线点得中")
  func hitTolerance() throws {
    let (r, _) = Self.renderer()
    let f = frame(r)
    let band = try #require(bandAt(f, bucket: 1))
    let x = band.frame.midX, mid = band.frame.midY
    let half = max(band.frame.height, ChartRenderer.orderFlowHitHeight) / 2
    #expect(half == 4, "2.5 pt 的线按 8 pt 的带子算")
    #expect(ChartRenderer.orderFlowHit(f.bands, x: x, y: mid)?.key == band.key)
    #expect(ChartRenderer.orderFlowHit([band], x: x, y: mid + half + 7.9)?.key == band.key)
    #expect(ChartRenderer.orderFlowHit([band], x: x, y: mid - half - 7.9)?.key == band.key)
    #expect(ChartRenderer.orderFlowHit([band], x: x, y: mid + half + 8.1) == nil)
    #expect(ChartRenderer.orderFlowHit([band], x: band.frame.minX - 3.9, y: mid)?.key == band.key)
    #expect(ChartRenderer.orderFlowHit([band], x: band.frame.minX - 4.1, y: mid) == nil)
    // 一条名义小的细线：和它同价叠着时点下去给大的；错开 3 pt 时点在细线上给细线、点在大线上给大线。
    var small = band.group.members[0]; small.venueID = "binance:spot:X"; small.product = .spot
    small.notional = 1_500_000; small.initialNotional = 1_500_000
    let smallGroup = try #require(OrderFlowGroup(key: OrderFlowGroupKey(small), members: [small]))
    let stacked = ChartRenderer.OrderFlowBand(group: smallGroup, frame: CGRect(x: band.frame.minX, y: mid - 0.5, width: band.frame.width, height: 1),
                                              color: band.color, dark: false, thin: true)
    #expect(ChartRenderer.orderFlowHit([band, stacked], x: x, y: mid)?.key == band.key)
    let offset = ChartRenderer.OrderFlowBand(group: smallGroup, frame: CGRect(x: band.frame.minX, y: mid - 3.5, width: band.frame.width, height: 1),
                                             color: band.color, dark: false, thin: true)
    #expect(ChartRenderer.orderFlowHit([band, offset], x: x, y: mid - 3)?.key == offset.key)
    #expect(ChartRenderer.orderFlowHit([band, offset], x: x, y: mid + 0.5)?.key == band.key)
    // 都没点在带里：离带边最近的；一样近取名义大的。
    #expect(ChartRenderer.orderFlowHit([offset, band], x: x, y: mid + half + 3)?.key == band.key)
    // 轻点：命中区至少 44 pt 高、44 pt 宽（HIG）；十字线仍按 8 pt / 4 pt。
    let reachY = (ChartRenderer.orderFlowTouchTarget - 2 * half) / 2
    #expect(reachY == 18)
    #expect(ChartRenderer.orderFlowHit([band], x: x, y: mid + half + reachY - 0.1, touch: true)?.key == band.key)
    #expect(ChartRenderer.orderFlowHit([band], x: x, y: mid - half - reachY + 0.1, touch: true)?.key == band.key)
    #expect(ChartRenderer.orderFlowHit([band], x: x, y: mid + half + reachY + 0.1, touch: true) == nil)
    let narrow = ChartRenderer.OrderFlowBand(group: band.group,
                                             frame: CGRect(x: band.frame.minX, y: band.frame.minY, width: 4, height: band.frame.height),
                                             color: band.color, dark: false, thin: false)
    #expect(ChartRenderer.orderFlowHit([narrow], x: narrow.frame.midX + 21.9, y: mid, touch: true)?.key == band.key)
    #expect(ChartRenderer.orderFlowHit([narrow], x: narrow.frame.midX + 22.1, y: mid, touch: true) == nil)
    #expect(ChartRenderer.orderFlowHit([narrow], x: narrow.frame.midX + 6.1, y: mid) == nil, "十字线不放宽")
    // 视图坐标版只认主图绘图区。
    #expect(r.orderFlowHit(at: CGPoint(x: x, y: mid), size: Self.size)?.key == band.key)
    #expect(r.orderFlowHit(at: CGPoint(x: r.layout(size: Self.size).plotW + 5, y: mid), size: Self.size) == nil)
  }

  @Test("十字线停在带上：出选中（非点选），开高低收框让位；离开就没有")
  func hoverFocus() throws {
    var (r, orders) = Self.renderer()
    let coin = orders[3]
    r.state.crosshair = Crosshair(index: r.state.series.count - 1, price: coin.price)
    let focus = try #require(r.orderFlowFocus(size: Self.size))
    #expect(focus.group.key == OrderFlowGroupKey(coin) && !focus.selected)
    #expect(focus.group.members == [coin])
    let L = r.layout(size: Self.size), range = r.priceRange(size: Self.size)
    #expect(r.orderFlowHoversBand(L: L, range: range))
    let lit = UIGraphicsImageRenderer(size: Self.size).image { context in
      #expect(r.drawOrderFlowHover(context.cgContext, pane: L.main, range: range, L: L))
    }
    #expect(lit.cgImage != nil)
    var away = r
    away.state.crosshair = Crosshair(index: 0, price: coin.price * 2)
    #expect(away.orderFlowFocus(size: Self.size) == nil)
    #expect(!away.orderFlowHoversBand(L: L, range: range))
    let scratch = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    #expect(!away.drawOrderFlowHover(scratch, pane: L.main, range: range, L: L))
  }

  @Test("轻点选中：选中出卡、再点同一条收起、点别的换过去、点空白收卡；选中时十字线收掉；金额跟着快照走")
  func selectAndDeselect() throws {
    let (r, orders) = Self.renderer()
    let view = ChartView(state: r.state)
    view.frame = CGRect(origin: .zero, size: Self.size)
    view.layoutIfNeeded()
    var reported: [ChartOrderFlowFocus?] = []
    view.onOrderFlowFocusChanged = { reported.append($0) }
    let k0 = OrderFlowGroupKey(orders[0]), k1 = OrderFlowGroupKey(orders[1])

    view.state?.crosshair = Crosshair(index: 3, price: 1)
    let before = try #require(view.state)
    view.selectOrderFlow(k0)
    #expect(view.state?.orderFlowSelected == k0)
    #expect(view.state?.crosshair == nil, "选中时十字线收掉")
    let first = try #require(reported.last ?? nil)
    #expect(first.group.key == k0 && first.selected)
    #expect(ChartView.changed(from: before, to: view.state!) == [.cross], "选中只脏 cross 层")

    // 快照更新了这一单的金额：卡片拿到新数。
    view.state?.orderFlow?.orders[0].notional = 12_345_678
    #expect((reported.last ?? nil)?.group.notional == 12_345_678)

    view.selectOrderFlow(k1)
    #expect((reported.last ?? nil)?.group.key == k1)
    view.selectOrderFlow(nil)
    #expect(view.state?.orderFlowSelected == nil)
    #expect(reported.last! == nil)

    // 选中的那一桶在快照里没单了：等于没选中。
    view.selectOrderFlow(k0)
    view.state?.orderFlow?.orders.removeFirst()
    #expect(reported.last! == nil)

    // 开十字线（长按）会把选中清掉：卡片改由十字线停在哪条带上决定。
    view.selectOrderFlow(k1)
    view.state?.crosshair = Crosshair(index: r.state.series.count - 1, price: 1)
    #expect((reported.last ?? nil)?.selected != true)
  }

  @Test("失联结束：和撤单一样按深浅画，也不归已成交 / 已撤销开关管")
  func lost() throws {
    var (r, _) = Self.renderer()
    r.state.orderFlow?.orders[5].status = .lost
    let band = try #require(bandAt(frame(r), bucket: 6))
    #expect(!band.dark)
    r.state.orderFlowDisplay.cancelled = false
    r.state.orderFlowDisplay.filled = false
    #expect(bandAt(frame(r), bucket: 6) != nil)
  }


  @Test("开关与内容变化脏哪几层；开着主力图例多留一行；拉快照中、别的品种不画")
  func invalidationAndInset() {
    let (r, _) = Self.renderer()
    var off = r.state; off.orderFlow = nil
    #expect(ChartView.changed(from: off, to: r.state) == .all)
    var moved = r.state; moved.orderFlow?.orders.removeLast()
    #expect(ChartView.changed(from: r.state, to: moved) == [.plot, .cross])
    var hidden = r.state; hidden.orderFlowDisplay.spot = false
    #expect(ChartView.changed(from: r.state, to: hidden) == [.plot, .cross])
    // 金额在同一粗细档里抖（BTC 簿几乎每拍都这样）：底图不动，只有图例那一层重画（审查 31）。
    // 合并带的粗细按各单「门槛四分之一格」之和，名义在一格里抖连格数都不变。
    var jitter = r.state; jitter.orderFlow?.orders[0].notional += 1_000_000; jitter.orderFlow?.asOfMs += 500
    #expect(ChartView.changed(from: r.state, to: jitter) == [.cross], "2 倍 → 2.2 倍，同是 8 格")
    var grew = r.state; grew.orderFlow?.orders[0].notional = 15_000_000  // 3 倍，12 格：同档但合并后的格数变了
    #expect(ChartView.changed(from: r.state, to: grew) == [.plot, .cross])
    var eaten = r.state; eaten.orderFlow?.orders[0].filledNotional = 1_000  // 被吃一口：浅转深
    #expect(ChartView.changed(from: r.state, to: eaten) == [.plot, .cross])
    var more = r.state; more.orderFlow?.orders[3].filledNotional += 1_000_000  // 已经深了再多吃：画出来一样
    #expect(ChartView.changed(from: r.state, to: more) == [.cross])
    var hover = r.state; hover.crosshair = Crosshair(index: 3, price: 1)
    #expect(ChartView.changed(from: r.state, to: hover) == [.cross])  // 选中的那一条叠在 cross 层（审查 32）
    var picked = r.state; picked.orderFlowSelected = picked.orderFlow.map { OrderFlowGroupKey($0.orders[0]) }
    #expect(ChartView.changed(from: r.state, to: picked) == [.cross])
    let plain = ChartRenderer(state: off)
    #expect(r.mainLegendInset(plotW: 300) == plain.mainLegendInset(plotW: 300) + 12)

    var loading = r
    loading.state.orderFlow = .loading(r.state.symbol.symbol)
    #expect(frame(loading).bands.isEmpty)
    var other = r
    other.state.orderFlow?.symbol = "ETHUSDT"
    #expect(frame(other).bands.isEmpty)
  }

  @Test("整帧绘制：线真的落到像素上，比价模式不画")
  func pixels() throws {
    let (r, orders) = Self.renderer()
    let L = r.layout(size: Self.size), range = r.priceRange(size: Self.size)
    var bytes = [UInt8](repeating: 0, count: 402 * 520 * 4)
    try bytes.withUnsafeMutableBytes { buffer in
      let ctx = try #require(CGContext(data: buffer.baseAddress, width: 402, height: 520,
        bitsPerComponent: 8, bytesPerRow: 402 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      UIGraphicsPushContext(ctx)
      #expect(r.drawOrderFlow(ctx, pane: L.main, range: range, L: L) == orders.count)
      UIGraphicsPopContext()
    }
    #expect(stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] >= 50 }.count > 500)
    let image = UIGraphicsImageRenderer(size: Self.size).image { context in
      r.draw(in: context.cgContext, size: Self.size, scale: 2)
    }
    #expect(image.cgImage != nil)
    var compare = r
    compare.state.percentAxis = true
    #expect(compare.orderFlowSnapshot == nil)
  }

  // 下面这条秤读 `ChartView.renderCounts`，那份计数只在 DEBUG 下有存储：Release 里读不到，
  // 断言会直接红。所以圈进 DEBUG，并记在 `ReleaseTestRosterTests.debugOnly` 与 Makefile
  // 的 Release 差集清单上。同文件其余用例两种配置都跑。
  #if DEBUG
  /// 审查 32 的秤：十字线在主图上走 50 步、横穿好几块大单，底图（plot 层）真画了几次。
  /// 读 `ChartView.renderCounts`（DEBUG 才有）；每一步都 `redrawNow`，一步一帧。
  @discardableResult
  static func crosshairSweep(steps: Int = 50) -> (plot: Int, cross: Int, hovered: Int) {
    let (r, orders) = renderer()
    let view = ChartView(state: r.state)
    view.frame = CGRect(origin: .zero, size: size)
    view.layoutIfNeeded()
    view.redrawNow()
    let plot0 = view.renderCounts["plot"] ?? 0, cross0 = view.renderCounts["cross"] ?? 0
    let prices = orders.map(\.price)
    let lo = prices.min()!, hi = prices.max()!
    var hovered = 0
    for k in 0..<steps {
      let p = lo + (hi - lo) * Double(k) / Double(steps - 1)
      view.state?.crosshair = Crosshair(index: r.state.series.count - 1, price: p)
      view.redrawNow()
      if view.renderer?.orderFlowDiagnostics(size: size).hovered == true { hovered += 1 }
    }
    let plot = (view.renderCounts["plot"] ?? 0) - plot0, cross = (view.renderCounts["cross"] ?? 0) - cross0
    print("ORDERFLOW-REDRAW crosshair-\(steps) plot=\(plot) cross=\(cross) hovered=\(hovered)")
    return (plot, cross, hovered)
  }

  @Test("十字线在主图上走 50 步：读数（cross 层）每步都画，底图一次不画（审查 32）")
  func crosshairSweepCounts() {
    let c = Self.crosshairSweep()
    #expect(c.cross == 50)
    #expect(c.plot == 0)
    #expect(c.hovered > 0, "扫一遍总该有几步停在大单上")
  }
  #endif

  @Test("色块几何两层共用一份：十字线动不重算，快照一变才重算")
  func frameCache() {
    var (r, orders) = Self.renderer()
    let L = r.layout(size: Self.size), range = r.priceRange(size: Self.size)
    _ = r.orderFlowFrame(pane: L.main, range: range, L: L)
    _ = r.orderFlowBands(pane: L.main, range: range, L: L)
    #expect(r.orderFlowCache.computed == 1)
    r.state.crosshair = Crosshair(index: r.state.series.count - 1, price: orders[3].price)
    #expect(r.orderFlowFocus(size: Self.size)?.group.key == OrderFlowGroupKey(orders[3]))
    r.state.crosshair = nil
    r.state.orderFlowSelected = OrderFlowGroupKey(orders[0])
    #expect(r.orderFlowFocus(size: Self.size)?.group.key == OrderFlowGroupKey(orders[0]))
    #expect(r.orderFlowCache.computed == 1, "十字线动、选中换都不重算几何")
    r.state.orderFlow?.orders.removeLast()
    _ = r.orderFlowFrame(pane: L.main, range: range, L: L)
    #expect(r.orderFlowCache.computed == 1, "快照变了换了新盒子，新盒子里算了一次")
    #expect(r.orderFlowFrame(pane: L.main, range: range, L: L).bands.count == orders.count - 1)
  }

}
