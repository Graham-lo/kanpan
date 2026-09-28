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

  /// 视野往右多留 `px` 的空白（最新那根离主图右缘 `px`）：贴右缘的金额签底下没有 K 线，不触发「挂着的签躲 K 线」
  /// （那条规则另有用例 `liveLabelDodgesLatestCandles`）。要在第一次取 `frame` 之前调。
  static func clearRight(_ r: inout ChartRenderer, px: Double = 140) {
    let plotW = r.layout(size: size).plotW
    r.state.view.to += px / plotW * r.state.view.span
  }

  /// 画出来的蜡烛（含影线，3 倍屏尺寸，实体与影线取宽的那个）里和 `rect` 相交的那些根的下标。
  static func candlesUnder(_ r: ChartRenderer, _ rect: CGRect) -> [Int] {
    let L = r.layout(size: size), b = r.state.series, range = r.priceRange(size: size)
    let m = candleMetrics(spacing: r.state.view.barSpacing(step: b.step, plotW: L.plotW), scale: 3)
    let halfW = max(m.bodyW, m.wickW) / 2
    return (0..<b.count).filter { i in
      let cx = r.state.view.x(Double(b.time(at: i)), plotW: L.plotW)
      let hiY = KanpanCore.yOf(b.high[i], pane: L.main, range: range, mode: r.state.effectivePriceMode)
      let loY = KanpanCore.yOf(b.low[i], pane: L.main, range: range, mode: r.state.effectivePriceMode)
      return cx + halfW > Double(rect.minX) && cx - halfW < Double(rect.maxX)
        && hiY < Double(rect.maxY) && loY > Double(rect.minY)
    }
  }

  /// 已结束的签落在规则允许的几处之一：结束点右侧（居中 / 线上方 / 线下方）、结束点左侧线的范围里（线上方 / 线下方）、
  /// 或从右侧居中往右让过去（居中在线上、左缘更靠右）。
  static func endedLabelAtAllowedSpot(_ label: ChartRenderer.OrderFlowLabel, band: ChartRenderer.OrderFlowBand, plotW: Double) -> Bool {
    let inset = ChartRenderer.orderFlowLabelInset, lift = ChartRenderer.orderFlowLabelLineGap
    let f = label.frame, l = band.frame
    let xR = min(l.maxX + inset, plotW - inset - f.width), xL = l.maxX - inset - f.width
    let centered = abs(f.midY - l.midY) < 1e-9
    let offLine = abs(f.maxY - (l.minY - lift)) < 1e-9 || abs(f.minY - (l.maxY + lift)) < 1e-9
    if abs(f.minX - xR) < 1e-9 { return centered || offLine }
    if abs(f.minX - xL) < 1e-9, xL >= l.minX { return offLine }
    return f.minX > xR && centered
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

  @Test("细线：主 2 pt（还挂着 2.5）、次 1 pt 70%、底噪 1 pt ≤ 35%、被压 1 pt；墙的范围括号宽 3 pt、70%；线粗不看名义")
  func thickness() {
    typealias R = ChartRenderer
    #expect(R.orderFlowMainLine == 2 && R.orderFlowMainLiveLine == 2.5)
    #expect(R.orderFlowSecondaryLine == 1 && R.orderFlowNoiseLine == 1 && R.orderFlowThinLine == 1)
    #expect(R.orderFlowSecondaryAlpha == 0.7 && R.orderFlowNoiseAlpha <= 0.35)
    #expect(R.orderFlowBracketWidth == 3 && R.orderFlowBracketAlpha == 0.7)
    #expect(R.orderFlowLabelAlpha == 0.85 && R.orderFlowLabelMax == 6)
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
    Self.clearRight(&r)
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
    // 芯线画在代表价上（主档、还挂着 → 2.5 pt）；不铺范围底色，价位范围是段右端一枚 3 pt 宽的括号
    // （挂着的紧贴金额签左侧，范围比芯窄时不立）。
    #expect(wall.role == .main && !wall.thin)
    #expect(abs(wall.frame.height - 2.5) < 1e-9 && abs(wall.frame.midY - y(r, g.price)) < 1e-6)
    let rangeHeight = abs(y(r, g.priceLow) - y(r, g.priceHigh))
    let L = r.layout(size: Self.size)
    if let bracket = wall.bracket {
      #expect(abs(bracket.minY - y(r, g.priceHigh)) < 1e-6 && abs(bracket.maxY - y(r, g.priceLow)) < 1e-6,
              "括号高 = 范围在屏上的高度")
      #expect(abs(bracket.width - 3) < 1e-9)
      let label = try #require(f.labels.first { $0.key == wall.key })
      #expect(abs(bracket.maxX - (label.frame.minX - ChartRenderer.orderFlowBracketGap)) < 1e-6, "挂着的括号紧贴金额签左侧")
    } else {
      let pane = r.layout(size: Self.size).main
      #expect(rangeHeight <= wall.frame.height + 1e-9 || y(r, g.priceHigh) < pane.y || y(r, g.priceLow) > pane.y + pane.h,
              "范围比芯线还窄、或出了主图才不立括号")
    }
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
    // 点中、出卡都是整堵墙：点在芯上；点在范围括号上、离别的带都够远的地方也认这堵墙；范围里的空白处不再算。
    #expect(ChartRenderer.orderFlowHit(f.bands, x: wall.frame.midX, y: wall.frame.midY)?.key == wall.key)
    let clearOf = { (yy: Double) in
      f.bands.allSatisfy { max(0, abs(yy - $0.frame.midY) - max($0.frame.height, ChartRenderer.orderFlowHitHeight) / 2) > 8.5 }
    }
    if let bracket = wall.bracket,
       let yFar = stride(from: bracket.minY, through: bracket.maxY, by: 0.5).first(where: clearOf) {
      #expect(ChartRenderer.orderFlowHit(f.bands, x: bracket.midX, y: yFar)?.key == wall.key)
      #expect(ChartRenderer.orderFlowHit(f.bands, x: bracket.midX, y: yFar, touch: true)?.key == wall.key)
      #expect(ChartRenderer.orderFlowHit(f.bands, x: bracket.minX - 40, y: yFar) == nil, "范围里的空白处不认墙")
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

  @Test("范围括号：整段范围出了主图（哪怕只出一端）整枚不画、不裁一截；芯线、金额签、详情卡的区间照旧")
  func bracketNeedsWholeRangeOnScreen() throws {
    var (r, _) = Self.renderer()
    let p = r.state.series.close.last!
    let step = p * 0.001
    r.state.orderFlow?.thresholds.step = step
    let pane = r.layout(size: Self.size).main
    let perBucket = abs(y(r, p) - y(r, p + step))
    try #require(perBucket > 3, "一桶在屏上要比芯线高，括号才有意义：\(perBucket)")
    // 最低那桶压在主图顶上一格：代表价（加大的那桶）在主图里，最高那桶的上沿出了主图顶。
    let top = Int64((price(r, atY: pane.y) / step).rounded(.down))
    let lo = top - 2
    let orders = (lo...(lo + 3)).map { bk in
      wallOrder(r, step: step, bucket: bk, from: 20, notional: bk == lo ? 14_000_000 : 10_000_000)
    }
    r.state.orderFlow?.orders = orders
    let f = frame(r)
    let wall = try #require(f.bands.first { $0.group.bucketCount == 4 }, "\(f.bands.map(\.key.id))")
    #expect(y(r, wall.group.priceHigh) < pane.y, "夹具：范围上沿要出主图顶")
    #expect(wall.frame.midY >= pane.y, "夹具：芯线在主图里")
    #expect(wall.role == .main && !wall.thin && wall.group.isRange)
    #expect(wall.bracket == nil, "范围一端出了主图，括号整枚不画")
    // 金额签照旧——除非芯线在顶上图例那几行里、签夹到图例下沿要挪超过 32 pt（见 `labelsStayBelowLegend`）。
    let legendBottom = pane.y + r.mainLegendInset(plotW: r.layout(size: Self.size).plotW)
    let shift = legendBottom + ChartRenderer.orderFlowLabelHeight / 2 - wall.frame.midY
    if shift <= ChartRenderer.orderFlowLabelMaxShift {
      #expect(f.labels.contains { $0.key == wall.key }, "金额签照旧")
    } else {
      #expect(!f.labels.contains { $0.key == wall.key }, "芯线在图例里、离下沿 \(shift) pt：不放签")
    }
    r.state.orderFlowSelected = wall.key
    let focus = try #require(r.orderFlowFocus(size: Self.size))
    #expect(focus.group.isRange && focus.group.bucketCount == 4, "详情卡照旧给区间")

    // 同一堵墙整段挪回主图中间：括号立起来，上下沿就是范围的屏上高度、都在主图里。
    let mid = Int64((p / step).rounded(.down)) - 2
    let moved = (mid...(mid + 3)).map { bk in
      wallOrder(r, step: step, bucket: bk, from: 20, notional: bk == mid ? 14_000_000 : 10_000_000)
    }
    r.state.orderFlow?.orders = moved
    let g = frame(r)
    let inside = try #require(g.bands.first { $0.group.bucketCount == 4 })
    let bracket = try #require(inside.bracket, "整段在主图里就立括号")
    #expect(bracket.minY >= pane.y && bracket.maxY <= pane.y + pane.h)
  }

  @Test("代表价出了主图的墙不占排名：线被裁掉看不见，不能把看得见的墙挤出「主」那 6 位")
  func offscreenLineDoesNotTakeMainSlot() throws {
    var (r, _) = Self.renderer()
    let p = r.state.series.close.last!
    let step = p * 0.001
    r.state.orderFlow?.thresholds.step = step
    let pane = r.layout(size: Self.size).main
    try #require(abs(y(r, p) - y(r, p + step)) > 3, "一桶在屏上要够高")
    // 一堵 4 桶的墙跨过主图顶：下面两桶在主图里，名义最大的那桶（代表价）在主图顶外。
    let top = Int64((price(r, atY: pane.y) / step).rounded(.down))
    let wall = ((top - 2)...(top + 1)).map { bk in
      wallOrder(r, step: step, bucket: bk, from: 20, notional: bk == top + 1 ? 40_000_000 : 10_000_000)
    }
    // 主图中间六堵小的，各隔开几桶。
    let small = (0..<6).map { i in
      let bk = Int64((price(r, atY: pane.y + pane.h * (0.3 + 0.08 * Double(i))) / step).rounded(.down))
      return wallOrder(r, step: step, bucket: bk, side: .bid, from: 20 + i, notional: 6_000_000)
    }
    try #require(Set(small.map(\.bucket)).count == 6)
    r.state.orderFlow?.orders = wall + small
    let f = frame(r)
    #expect(y(r, (Double(top + 1) + 0.5) * step) < pane.y, "夹具：代表价在主图顶外")
    #expect(!f.bands.contains { $0.group.bucketCount == 4 }, "线看不见的墙不进这一屏：\(f.bands.map(\.key.id))")
    #expect(f.bands.count == 6)
    #expect(f.bands.allSatisfy { $0.role == .main }, "看得见的六堵都是主：\(f.bands.map(\.role))")
    #expect(f.bands.allSatisfy { $0.frame.midY >= pane.y && $0.frame.midY <= pane.y + pane.h })
  }

  @Test("金额：K / M / B / T 一位小数")
  func amountUnits() {
    #expect(ChartRenderer.orderFlowAmount(950) == "950")
    #expect(ChartRenderer.orderFlowAmount(5_300_000) == "5.3M")
    #expect(ChartRenderer.orderFlowAmount(1e9) == "1.0B")
    #expect(ChartRenderer.orderFlowAmount(999e9) == "999.0B")
    #expect(ChartRenderer.orderFlowAmount(1.2e12) == "1.2T")
  }

  @Test("开着盘口：挂着的签不压盘口梯，挪到梯子左边、纵向不动；跨桶墙的括号跟着签走；没开盘口照旧贴右缘")
  func labelsDodgeDepthLadder() throws {
    var (r, step, b0) = wallRenderer()
    Self.clearRight(&r)
    let L = r.layout(size: Self.size)
    let px = r.state.series.close.last!
    // 贴着最新价挂一堵 3 桶的卖墙（名义最大，一定是主、一定写签）、再挂一单远离盘口的。
    let wall = (b0...(b0 + 2)).map { wallOrder(r, step: step, bucket: $0, from: 20, notional: 30_000_000) }
    let farY = L.main.y + L.main.h * 0.85
    let far = wallOrder(r, step: step, bucket: Int64((price(r, atY: farY) / step).rounded(.down)), side: .bid, from: 20)
    r.state.depth = OrderBook(symbol: r.state.symbol.symbol, time: r.state.series.lastTime,
                              bids: (1...5).map { .init(price: px - Double($0) * step, quantity: 1) },
                              asks: (1...5).map { .init(price: px + Double($0) * step, quantity: 1) })
    r.state.orderFlow?.orders = wall + [far]
    let ladder = try #require(r.depthEnvelope(pane: L.main, range: r.priceRange(size: Self.size), L: L))
    #expect(abs(ladder.width - 64) < 1e-9 && abs(ladder.maxX - L.plotW) < 1e-9)
    let f = frame(r)
    let w = try #require(f.bands.first { $0.group.bucketCount == 3 })
    let label = try #require(f.labels.first { $0.key == w.key })
    #expect(!label.frame.intersects(ladder), "签 \(label.frame) 压在盘口梯 \(ladder) 上")
    #expect(abs(label.frame.maxX - (ladder.minX - ChartRenderer.orderFlowLabelGap)) < 1e-6, "挪到梯子左边、留 2 pt")
    if let bracket = w.bracket {
      #expect(abs(bracket.maxX - (label.frame.minX - ChartRenderer.orderFlowBracketGap)) < 1e-6, "括号跟着签")
    }
    let farLabel = try #require(f.labels.first { $0.key == OrderFlowGroupKey(far) })
    #expect(abs(farLabel.frame.maxX - (L.plotW - ChartRenderer.orderFlowLabelInset)) < 1e-6, "离盘口远的照旧贴右缘")
    // 关掉盘口：签回到主图右缘。
    r.state.depth = nil
    // 深度变了 `recalc` 不换订单流的盒子：梯子那一块进了缓存键，照样重算。
    let g = frame(r)
    let back = try #require(g.labels.first { $0.key == w.key })
    #expect(abs(back.frame.maxX - (L.plotW - ChartRenderer.orderFlowLabelInset)) < 1e-6)
  }

  @Test("范围括号：同一 x 上两枚纵向重叠只留名义大的那枚，不错开 x；两堵墙的芯线、金额签都照旧")
  func overlappingBracketsKeepLarger() throws {
    var (r, _) = Self.renderer()
    Self.clearRight(&r)
    let p = r.state.series.close.last!
    let step = p * 0.001
    r.state.orderFlow?.thresholds.step = step
    let perBucket = abs(y(r, p) - y(r, p + step))
    try #require(perBucket > 3, "\(perBucket)")
    let b0 = Int64((p / step).rounded(.down)) - 4
    // 卖墙 b0 … b0+4 合计 54M（代表价在 b0+1）；买墙 b0+3 … b0+7 合计 36M（代表价在 b0+6）：
    // 芯线隔 5 桶不挤，范围在 b0+3 … b0+5 重叠；两枚签宽一样（等宽字「54.0M」「36.0M」）→ 括号同一 x。
    let ask = (b0...(b0 + 4)).map { bk in
      wallOrder(r, step: step, bucket: bk, side: .ask, from: 20, notional: bk == b0 + 1 ? 14_000_000 : 10_000_000)
    }
    let bid = ((b0 + 3)...(b0 + 7)).map { bk in
      wallOrder(r, step: step, bucket: bk, side: .bid, from: 20, notional: bk == b0 + 6 ? 12_000_000 : 6_000_000)
    }
    r.state.orderFlow?.orders = ask + bid
    let f = frame(r)
    let big = try #require(f.bands.first { $0.group.side == .ask && $0.group.bucketCount == 5 }, "\(f.bands.map(\.key.id))")
    let small = try #require(f.bands.first { $0.group.side == .bid && $0.group.bucketCount == 5 })
    #expect(big.group.notional > small.group.notional)
    #expect(big.role == .main && small.role == .main && !big.thin && !small.thin, "芯线隔得开，都不压细")
    let kept = try #require(big.bracket, "名义大的那枚留下")
    #expect(small.bracket == nil, "同一 x 上纵向重叠的后一枚不画")
    // 不错开 x：留下的那枚仍紧贴自己的签；两枚签都在，落点同一 x。
    let bigLabel = try #require(f.labels.first { $0.key == big.key })
    let smallLabel = try #require(f.labels.first { $0.key == small.key })
    #expect(abs(kept.maxX - (bigLabel.frame.minX - ChartRenderer.orderFlowBracketGap)) < 1e-6)
    #expect(abs(bigLabel.frame.minX - smallLabel.frame.minX) < 1e-6, "夹具：两枚签同一 x")
    // 小的那堵单独在场时自己的括号是立得起来的——没画只是因为重叠。
    r.state.orderFlow?.orders = bid
    #expect(frame(r).bands.first { $0.group.bucketCount == 5 }?.bracket != nil)
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

  @Test("轻点只认主档与次档：底噪点不中（十字线照旧认），44 pt 放宽只给主档，次档按 8 / 4 pt")
  func touchIgnoresNoise() throws {
    var (r, step, b0) = wallRenderer()
    let pane = r.layout(size: Self.size).main
    let count = 25
    let pitch = (pane.h - 40) / Double(count)
    var orders: [BigOrder] = []
    for i in 0..<count {
      let p = price(r, atY: pane.y + 20 + pitch * Double(i))
      var o = wallOrder(r, step: step, bucket: b0 + Int64(3 * i), from: 30, to: 5, notional: Double(40 - i) * 1_250_000)
      o.price = p
      o.threshold = 5_000_000
      orders.append(o)
    }
    r.state.orderFlow?.orders = orders
    let f = frame(r)
    // 第 22 名：上下邻居也都是底噪。
    let noise = try #require(f.bands.first { $0.key == OrderFlowGroupKey(orders[21]) })
    #expect(noise.role == .noise)
    let secondary = try #require(f.bands.first { $0.role == .secondary })
    let main = try #require(f.bands.first { $0.role == .main })
    // 底噪：点正中也不出卡；十字线（非轻点）照旧认得。
    #expect(ChartRenderer.orderFlowHit(f.bands, x: noise.frame.midX, y: noise.frame.midY, touch: true)?.role != .noise)
    #expect(ChartRenderer.orderFlowHit([noise], x: noise.frame.midX, y: noise.frame.midY, touch: true) == nil)
    #expect(ChartRenderer.orderFlowHit([noise], x: noise.frame.midX, y: noise.frame.midY)?.key == noise.key)
    #expect(r.orderFlowHit(at: CGPoint(x: noise.frame.midX, y: noise.frame.midY), size: Self.size)?.key != noise.key)
    // 次档：点在线上认，离开超过 4 + 8 pt 就不认（不再放到 44 pt）。
    let sh = max(secondary.frame.height, ChartRenderer.orderFlowHitHeight) / 2
    #expect(ChartRenderer.orderFlowHit([secondary], x: secondary.frame.midX, y: secondary.frame.midY, touch: true)?.key == secondary.key)
    #expect(ChartRenderer.orderFlowHit([secondary], x: secondary.frame.midX, y: secondary.frame.midY + sh + 7.9, touch: true)?.key == secondary.key)
    #expect(ChartRenderer.orderFlowHit([secondary], x: secondary.frame.midX, y: secondary.frame.midY + sh + 8.1, touch: true) == nil)
    // 主档：仍放到 44 pt。
    let mh = max(main.frame.height, ChartRenderer.orderFlowHitHeight) / 2
    let reach = (ChartRenderer.orderFlowTouchTarget - 2 * mh) / 2
    #expect(ChartRenderer.orderFlowHit([main], x: main.frame.midX, y: main.frame.midY + mh + reach - 0.1, touch: true)?.key == main.key)
    // 整张主图不再铺满命中区：竖着每 2 pt 扫一遍，底噪那几行上点不出卡的比例要过半。
    var misses = 0, total = 0
    var yy = noise.frame.midY - pitch / 2
    while yy < noise.frame.midY + pitch / 2 {
      total += 1
      if r.orderFlowHit(at: CGPoint(x: noise.frame.midX, y: yy), size: Self.size) == nil { misses += 1 }
      yy += 2
    }
    #expect(misses * 2 > total, "底噪那一行 \(misses)/\(total) 点不中")
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
    Self.clearRight(&r)
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
              "签底 85% 不透明，字色按叠出来的颜色算对比")
      #expect(abs(label.frame.height - ChartRenderer.orderFlowLabelHeight) < 1e-6)
      #expect(abs(label.frame.midY - band.frame.midY) <= ChartRenderer.orderFlowLabelMaxShift + 1e-9)
      #expect(label.frame.maxX <= L.plotW - inset + 1e-9, "不进价格刻度列")
      if band.group.isLive { #expect(abs(label.frame.maxX - (L.plotW - inset)) < 1e-9, "挂着的贴主图右缘") }
      else {
        let want = min(band.frame.maxX + inset, L.plotW - inset - label.frame.width)
        // 结束点上有蜡烛时抬到线上下方、或收到结束点左侧线的上下方、再不行往右让（居中在线上）；否则贴在结束点右侧。
        #expect(abs(label.frame.minX - want) < 1e-9 && abs(label.frame.midY - band.frame.midY) < 1e-9
                  || Self.endedLabelAtAllowedSpot(label, band: band, plotW: L.plotW),
                "结束的在结束点旁：\(label.frame)，本该 \(want)")
      }
    }
    // 签彼此不叠。
    for (i, a) in f.labels.enumerated() {
      for b in f.labels[(i + 1)...] {
        #expect(a.frame.maxX <= b.frame.minX || b.frame.maxX <= a.frame.minX
                  || a.frame.maxY + gap <= b.frame.minY + 1e-9 || b.frame.maxY + gap <= a.frame.minY + 1e-9)
      }
    }
    // 5.3M 那条（挂着）夹在 10M 挂单与 10M 已结束两条之间、各隔 10 pt：第二轮 D3 起挂着的签坐在线上方，
    // 10M 的签占住了它上下两处和夹缝，名义小的让位不放。单拿出来照旧写「5.3M」。
    do {
      var one = r
      one.state.orderFlow?.orders = [orders[3]]
      #expect(frame(one).labels.map(\.text) == ["5.3M"])
    }
    // 字色取近黑与白里对比度高的那个；深底蔚蓝按亮度一刀切会取到白（3.6:1），按对比度取近黑；两个都不到 4.5 用纯黑。
    #expect(ChartRenderer.orderFlowLabelInk("#E1D610") == "#141414")
    #expect(ChartRenderer.orderFlowLabelInk("#8A149F") == "#FFFFFF")
    #expect(ChartRenderer.orderFlowLabelInk("#CF09E7") == "#000000")
    #expect(ChartRenderer.orderFlowLabelInk("#5A7DFF") == "#141414")
    #expect(f.labels.count <= ChartRenderer.orderFlowLabelMax)

    // 窄段（挂了一根多就撤了）也写：签在结束点右侧，放不下就收回主图右缘以内。
    let b = r.state.series
    let p = orders[0].price, cy = y(r, p)
    let narrow = Self.order(.usdtPerp, .bid, price: p, firstSeen: b.time(at: b.count - 8) + 1,
                            end: b.time(at: b.count - 7) + 2, status: .cancelled, bucket: 1)
    r.state.orderFlow?.orders = [narrow]
    let n = frame(r)
    #expect(n.bands.count == 1 && n.labels.count == 1)
    let nl = try #require(n.labels.first)
    let nlWant = min(n.bands[0].frame.maxX + inset, L.plotW - inset - nl.frame.width)
    #expect(nl.frame.minX >= nlWant - 1e-9 && Self.endedLabelAtAllowedSpot(nl, band: n.bands[0], plotW: L.plotW),
            "窄段的签只有结束点右侧那几处（左侧放不进一根宽的线里）：\(nl.frame)")

    // 两条线上下隔 6 pt：线不相碍（都是整条），签 16 pt 高会碰——名义大的坐在自己线上方 2 pt，小的挪到它上方。
    let seen = b.time(at: b.count - 30) + 1
    let big = Self.order(.usdtPerp, .bid, price: p, firstSeen: seen, notional: 20_000_000, initial: 20_000_000, bucket: 1)
    let small = Self.order(.coinPerp, .ask, price: price(r, atY: cy - 6), firstSeen: seen, bucket: 2)
    r.state.orderFlow?.orders = [small, big]
    let c = frame(r)
    #expect(c.bands.allSatisfy { !$0.thin })
    #expect(c.labels.count == 2)
    let bl = try #require(c.labels.first { $0.key == OrderFlowGroupKey(big) })
    let sl = try #require(c.labels.first { $0.key == OrderFlowGroupKey(small) })
    let bigLine = try #require(c.bands.first { $0.key == OrderFlowGroupKey(big) })
    #expect(abs(bl.frame.maxY - (bigLine.frame.minY - ChartRenderer.orderFlowLabelLineGap)) < 1e-9, "名义大的不挪：签底在线上方 2 pt")
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

  @Test("D3 挂着的签坐在线上方 2 pt、贴右缘，不压线；已结束的照旧在结束点右侧居中；上方会进图例就翻到线下方 2 pt")
  func liveLabelSitsAboveLine() throws {
    var (r, _) = Self.renderer()
    let L = r.layout(size: Self.size)
    let legend = r.mainLegendInset(plotW: L.plotW)
    let lift = ChartRenderer.orderFlowLabelLineGap, inset = ChartRenderer.orderFlowLabelInset
    let b = r.state.series
    let seen = b.time(at: b.count - 30) + 1
    let midY = L.main.y + L.main.h * 0.5
    let live = Self.order(.usdtPerp, .bid, price: price(r, atY: midY), firstSeen: seen, bucket: 1)
    let ended = Self.order(.usdtPerp, .ask, price: price(r, atY: midY + 60), firstSeen: seen,
                           end: b.time(at: b.count - 10) + 1, status: .cancelled, bucket: 2)
    r.state.orderFlow?.orders = [live, ended]
    let f = frame(r)
    let line = try #require(f.bands.first { $0.key == OrderFlowGroupKey(live) })
    let label = try #require(f.labels.first { $0.key == line.key })
    #expect(abs(label.frame.maxY - (line.frame.minY - lift)) < 1e-9, "签底在线上沿上方 2 pt：\(label.frame) 线 \(line.frame)")
    #expect(!label.frame.intersects(line.frame), "不压线")
    #expect(abs(label.frame.maxX - (L.plotW - inset)) < 1e-9, "右对齐贴主图右缘")
    let endLine = try #require(f.bands.first { $0.key == OrderFlowGroupKey(ended) })
    let endLabel = try #require(f.labels.first { $0.key == endLine.key })
    #expect(Self.endedLabelAtAllowedSpot(endLabel, band: endLine, plotW: L.plotW),
            "已结束的签居中在线上；压着蜡烛才抬到线上方 / 下方或让开：\(endLabel.frame) 线 \(endLine.frame)")

    // 线在图例下沿下方 8 pt：上方放不下（会进图例），翻到线下方 2 pt。
    let high = Self.order(.usdtPerp, .bid, price: price(r, atY: L.main.y + legend + 8), firstSeen: seen, bucket: 3)
    r.state.orderFlow?.orders = [high]
    let g = frame(r)
    let hl = try #require(g.bands.first)
    let hLabel = try #require(g.labels.first)
    #expect(abs(hLabel.frame.minY - (hl.frame.maxY + lift)) < 1e-9, "翻到线下方 2 pt：\(hLabel.frame) 线 \(hl.frame)")
    #expect(hLabel.frame.minY >= L.main.y + legend - 1e-9)
    // 线离图例下沿够远（签高 16 + 2 + 线半宽）：照旧在上方。
    let roomy = Self.order(.usdtPerp, .bid, price: price(r, atY: L.main.y + legend + 24), firstSeen: seen, bucket: 4)
    r.state.orderFlow?.orders = [roomy]
    let k = frame(r)
    let kl = try #require(k.bands.first), kLabel = try #require(k.labels.first)
    #expect(abs(kLabel.frame.maxY - (kl.frame.minY - lift)) < 1e-9)
    #expect(kLabel.frame.minY >= L.main.y + legend - 1e-9)
  }

  @Test("金额签不进顶上图例那几行（压测 2026-09-28）：线在图例带里，签夹到图例下沿；夹下来离线超过 32 pt 就不放")
  func labelsStayBelowLegend() throws {
    var (r, _) = Self.renderer()
    let L = r.layout(size: Self.size)
    let legend = r.mainLegendInset(plotW: L.plotW)
    #expect(legend > ChartRenderer.orderFlowLabelHeight, "开着主力，图例至少两行")
    let b = r.state.series
    let seen = b.time(at: b.count - 30) + 1
    // 线在图例下沿上方 4 pt：原来签居中在线上、上半截伸进图例；现在贴图例下沿。
    let near = Self.order(.usdtPerp, .ask, price: price(r, atY: L.main.y + legend - 4), firstSeen: seen, bucket: 1)
    r.state.orderFlow?.orders = [near]
    let f = frame(r)
    #expect(f.bands.count == 1)
    let l = try #require(f.labels.first, "离下沿不远的仍写金额")
    #expect(l.frame.minY >= L.main.y + legend - 1e-9, "签不进图例：\(l.frame) 图例下沿 \(legend)")
    #expect(abs(l.frame.midY - f.bands[0].frame.midY) <= ChartRenderer.orderFlowLabelMaxShift + 1e-9)
    // 线在图例最上沿：夹到下沿要挪 legend + 6 pt，超过 32 就不放（签认错线比没有签更糟）。
    let top = Self.order(.usdtPerp, .ask, price: price(r, atY: L.main.y + 2), firstSeen: seen, bucket: 2)
    r.state.orderFlow?.orders = [top]
    let g = frame(r)
    #expect(g.bands.count == 1, "线照画（垫在图例文字底下）")
    let shift = L.main.y + legend + ChartRenderer.orderFlowLabelHeight / 2 - (L.main.y + 2)
    if shift > ChartRenderer.orderFlowLabelMaxShift {
      #expect(g.labels.isEmpty, "离线 \(shift) pt，不放签")
    } else {
      #expect(g.labels.allSatisfy { $0.frame.minY >= L.main.y + legend - 1e-9 })
    }
  }

  @Test("挂着的签贴右缘会压到最新那几根 K 线（含影线）：往左让到压着的最右一根左侧 2 pt、不压任何一根、仍在线上方；墙离最新 K 线远照旧贴右缘")
  func liveLabelDodgesLatestCandles() throws {
    var (r, _) = Self.renderer()
    let L = r.layout(size: Self.size)
    let b = r.state.series
    let seen = b.time(at: b.count - 30) + 1
    let inset = ChartRenderer.orderFlowLabelInset, lift = ChartRenderer.orderFlowLabelLineGap
    let spacing = r.state.view.barSpacing(step: b.step, plotW: L.plotW)
    // 蜡烛画出来的左右缘：照 `drawCandles` 同一套尺寸（3 倍屏），实体与影线取宽的那个。
    let m = candleMetrics(spacing: spacing, scale: 3)
    let halfW = max(m.bodyW, m.wickW) / 2
    let cx = { (i: Int) in r.state.view.x(Double(b.time(at: i)), plotW: L.plotW) }
    let hiY = { (i: Int) in self.y(r, b.high[i]) }, loY = { (i: Int) in self.y(r, b.low[i]) }
    let covers = { (rect: CGRect, i: Int) in
      cx(i) + halfW > Double(rect.minX) && cx(i) - halfW < Double(rect.maxX)
        && hiY(i) < Double(rect.maxY) && loY(i) > Double(rect.minY)
    }
    // 签贴右缘时的横向范围里的那几根，取最高的那根（影线最长），墙挂在它高低价正中。
    let w = ChartRenderer.orderFlowLabelWidth(ChartRenderer.orderFlowAmount(10_000_000))
    let right = L.plotW - inset
    let under = (0..<b.count).filter { cx($0) + halfW > right - w && cx($0) - halfW < right }
    let tall = try #require(under.max { loY($0) - hiY($0) < loY($1) - hiY($1) }, "最新那几根落在贴右缘的签底下")
    #expect(loY(tall) - hiY(tall) > 8, "夹具里最新那几根要有一根够高：\(loY(tall) - hiY(tall)) pt")
    let near = Self.order(.usdtPerp, .bid, price: (b.high[tall] + b.low[tall]) / 2, firstSeen: seen, bucket: 1)
    r.state.orderFlow?.orders = [near]
    let f = frame(r)
    let line = try #require(f.bands.first)
    // 不躲的话签在哪：贴右缘、签底在线上方 2 pt。它确实压着蜡烛。
    let naive = CGRect(x: right - w, y: Double(line.frame.minY) - lift - ChartRenderer.orderFlowLabelHeight,
                       width: w, height: ChartRenderer.orderFlowLabelHeight)
    let hit = try #require(under.filter { covers(naive, $0) }.max(), "贴右缘的签压着最新那几根")
    let label = try #require(f.labels.first, "躲开 K 线后仍写金额")
    #expect(label.frame.maxX < cx(hit) - halfW, "签 \(label.frame) 在压着的最右一根（#\(hit)，左缘 \(cx(hit) - halfW)）左侧")
    #expect(abs(label.frame.maxY - (line.frame.minY - lift)) < 1e-9, "仍坐在线上方 2 pt：\(label.frame) 线 \(line.frame)")
    let still = (0..<b.count).filter { covers(label.frame, $0) }
    #expect(still.isEmpty, "挪完不再压任何一根：\(still)")
    // 签右缘紧贴它让开的那一根（纵向压着签原位置的某一根）左侧 2 pt（实体按像素取整，容差 1 pt）。
    let gapToBlocker = (0..<b.count).filter { hiY($0) < Double(label.frame.maxY) && loY($0) > Double(label.frame.minY) }
      .map { cx($0) - halfW - Double(label.frame.maxX) }.filter { $0 > 0 }.min()
    #expect(gapToBlocker.map { $0 >= ChartRenderer.orderFlowLabelCandleGap && $0 <= ChartRenderer.orderFlowLabelCandleGap + 1 } == true,
            "签右缘离右边压着的那根留 2 pt：\(String(describing: gapToBlocker))")

    // 同一夹具，墙挪到签底下那几根够不着的地方（签在线上方：签框 = 线 y − 19.25 … 线 y − 3.25）：
    // 最高价以上（签底在最高那根影线以上）放得下就放上面，否则放最低价以下（签顶在最低那根以下）。签不压蜡烛，照旧贴右缘。
    let ceil = under.map(hiY).min()!, floor = under.map(loY).max()!
    let legendBottom = L.main.y + r.mainLegendInset(plotW: L.plotW)
    let aboveY = ceil - 4, belowY = floor + 22
    let farY = try #require(aboveY - 20 >= legendBottom ? aboveY : belowY + 4 <= L.main.y + L.main.h ? belowY : nil,
                            "夹具主图里放得下一条不压蜡烛的线：影线 \(ceil) … \(floor)，主图 \(legendBottom) … \(L.main.y + L.main.h)")
    let far = Self.order(.usdtPerp, .bid, price: price(r, atY: farY), firstSeen: seen, bucket: 2)
    r.state.orderFlow?.orders = [far]
    let g = frame(r)
    let farLine = try #require(g.bands.first)
    let farLabel = try #require(g.labels.first)
    #expect(abs(farLabel.frame.maxX - right) < 1e-9, "不压蜡烛就贴右缘：\(farLabel.frame)")
    #expect(abs(farLabel.frame.maxY - (farLine.frame.minY - lift)) < 1e-9)
    // 跨桶的墙：括号跟着让开的签走（右缘仍紧贴签左侧 1 pt），不留在贴右缘时的名义落点。
    let mid = (b.high[tall] + b.low[tall]) / 2, step = mid * 0.001
    r.state.orderFlow?.thresholds.step = step
    let b0 = Int64((mid / step).rounded(.down)) - 1
    let wallOrders = (b0...(b0 + 2)).map { wallOrder(r, step: step, bucket: $0, from: 20) }
    r.state.orderFlow?.orders = wallOrders
    let wf = frame(r)
    let wall = try #require(wf.bands.first { $0.group.bucketCount == 3 }, "\(wf.bands.map(\.key.id))")
    let wallLabel = try #require(wf.labels.first { $0.key == wall.key })
    let bracket = try #require(wall.bracket, "三桶的主墙立括号")
    #expect(wallLabel.frame.maxX < right - 1, "夹具：签让开了 K 线 \(wallLabel.frame)")
    #expect((0..<b.count).allSatisfy { !covers(wallLabel.frame, $0) })
    #expect(abs(bracket.maxX - (wallLabel.frame.minX - ChartRenderer.orderFlowBracketGap)) < 1e-6,
            "括号 \(bracket) 跟着签 \(wallLabel.frame)")
    r.state.orderFlow?.thresholds.step = nil
  }

  @Test("已结束的签在结束点右侧压到蜡烛：先看结束点两侧线上方 / 下方能不能不挪就放下，都压着就往右让到压着的最右一根右侧 2 pt、居中在线上；跨桶的括号跟着签走；哪儿都压着就取盖得最少的")
  func endedLabelDodgesCandles() throws {
    var (r, _) = Self.renderer()
    // 放大三倍（格宽 4 → 12 pt）：默认密度下签底下十根挨着的蜡烛总有一根够到签，让到哪儿都压着；放大后才有空档可让。
    r.state.view.span /= 3
    let L = r.layout(size: Self.size)
    let b = r.state.series
    let inset = ChartRenderer.orderFlowLabelInset, gap = ChartRenderer.orderFlowLabelCandleGap
    let h = ChartRenderer.orderFlowLabelHeight, lift = ChartRenderer.orderFlowLabelLineGap
    let spacing = r.state.view.barSpacing(step: b.step, plotW: L.plotW)
    let cx = { (i: Int) in r.state.view.x(Double(b.time(at: i)), plotW: L.plotW) }
    let hiY = { (i: Int) in self.y(r, b.high[i]) }, loY = { (i: Int) in self.y(r, b.low[i]) }
    // 墙的价位放在某根蜡烛顶端往下 7 pt：签居中（顶 = 影线顶 − 1）、线上方、线下方三处都压着这根（它得高过 10 pt）；
    // 线只有两根宽，结束点左侧放不下签；让到这根右侧 2 pt 处（签居中在线上）不再压别的蜡烛——夹具里挑满足这些的最靠左一根。
    let half = max(1, spacing / 3 + 0.5)
    let w = ChartRenderer.orderFlowLabelWidth(ChartRenderer.orderFlowAmount(10_000_000))
    let candidates = (b.count - 40)..<(b.count - 12)
    let tall = try #require(candidates.first { i in
      let landing = CGRect(x: cx(i) + half + gap, y: hiY(i) - 1, width: w, height: h)
      return loY(i) - hiY(i) > 10 && cx(i - 3) - spacing / 2 >= 0 && Self.candlesUnder(r, landing).isEmpty
        && landing.maxX <= L.plotW - inset
    }, "夹具里要有这么一根")
    let level = price(r, atY: hiY(tall) + h / 2 - 1)
    let seen = b.time(at: tall - 3) + 1, end = b.time(at: tall - 1) + 1
    let ended = Self.order(.usdtPerp, .ask, price: level, firstSeen: seen, end: end, status: .cancelled, bucket: 3)
    r.state.orderFlow?.orders = [ended]
    let f = frame(r)
    let line = try #require(f.bands.first), label = try #require(f.labels.first, "让开后仍写金额")
    #expect(abs(line.frame.maxX - (cx(tall) - spacing / 2)) < 1, "夹具：线在那根高蜡烛左缘结束 \(line.frame.maxX) vs \(cx(tall) - spacing / 2)")
    #expect(label.frame.minX > line.frame.maxX + inset, "签往右让开了：\(label.frame)")
    #expect(abs(label.frame.midY - line.frame.midY) < 1e-9, "居中在线上")
    #expect(Self.candlesUnder(r, label.frame).isEmpty, "不压任何一根：\(Self.candlesUnder(r, label.frame))")
    #expect(label.frame.maxX <= L.plotW - inset + 1e-9)
    #expect(abs(Double(label.frame.minX) - (cx(tall) + half + gap)) < 1e-6, "签左缘 = 那根右缘 + 2 pt：\(label.frame)")
    // 那根之上还有一小截空：线上方放得下就不横向挪（签仍在结束点右侧、抬到线上方 2 pt）。
    let low = price(r, atY: hiY(tall) + h + lift + 1 + 4)
    r.state.orderFlow?.orders = [Self.order(.usdtPerp, .ask, price: low, firstSeen: seen, end: end, status: .cancelled, bucket: 3)]
    let g = frame(r)
    let sLine = try #require(g.bands.first), sLabel = try #require(g.labels.first)
    let aboveRect = CGRect(x: sLine.frame.maxX + inset, y: sLine.frame.minY - lift - h, width: w, height: h)
    if Self.candlesUnder(r, aboveRect).isEmpty {
      #expect(abs(sLabel.frame.minX - (sLine.frame.maxX + inset)) < 1e-9 && abs(sLabel.frame.maxY - (sLine.frame.minY - lift)) < 1e-9,
              "上方放得下就不横向挪：\(sLabel.frame) 线 \(sLine.frame)")
    }
    #expect(Self.endedLabelAtAllowedSpot(sLabel, band: sLine, plotW: L.plotW))
    // 哪儿都压着（视野里全是蜡烛、让到右缘外）：签照样有，落在五处里盖蜡烛最少的那处。
    var dense = r
    dense.state.view.to = Double(b.time(at: tall)) + Double(b.step) / 2
    let dLine0 = Self.order(.usdtPerp, .ask, price: level, firstSeen: seen, end: end, status: .cancelled, bucket: 3)
    dense.state.orderFlow?.orders = [dLine0]
    let dL = dense.layout(size: Self.size)
    let df = dense.orderFlowFrame(pane: dL.main, range: dense.priceRange(size: Self.size), L: dL)
    let dLine = try #require(df.bands.first), dLabel = try #require(df.labels.first, "让不开也要有签")
    #expect(Self.endedLabelAtAllowedSpot(dLabel, band: dLine, plotW: dL.plotW), "\(dLabel.frame) 线 \(dLine.frame)")
    // 跨桶的已结束墙：括号跟着让开的签走（右缘仍紧贴签左侧 1 pt）。
    let step = level * 0.001
    r.state.orderFlow?.thresholds.step = step
    let b0 = Int64((level / step).rounded(.down)) - 1
    let wallOrders = (b0...(b0 + 2)).map { wallOrder(r, step: step, bucket: $0, from: b.count - tall + 3, to: b.count - tall + 1) }
    r.state.orderFlow?.orders = wallOrders
    let wf = frame(r)
    let wall = try #require(wf.bands.first { $0.group.bucketCount == 3 }, "\(wf.bands.map(\.key.id))")
    let wallLabel = try #require(wf.labels.first { $0.key == wall.key })
    let bracket = try #require(wall.bracket, "三桶的主墙立括号")
    #expect(!wall.group.isLive && Self.endedLabelAtAllowedSpot(wallLabel, band: wall, plotW: L.plotW), "\(wallLabel.frame)")
    #expect(abs(bracket.maxX - (wallLabel.frame.minX - ChartRenderer.orderFlowBracketGap)) < 1e-6,
            "括号 \(bracket) 跟着签 \(wallLabel.frame)")
    r.state.orderFlow?.thresholds.step = nil
  }

  /// 把 `body` 画进一张和图一样大的位图（1 倍、y 朝下，行号 = 视图坐标 y），返回 RGBA。
  static func bitmap(_ body: (CGContext) -> Void) throws -> [UInt8] {
    let w = Int(size.width), h = Int(size.height)
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    try bytes.withUnsafeMutableBytes { buffer in
      let ctx = try #require(CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                       bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      ctx.translateBy(x: 0, y: CGFloat(h))
      ctx.scaleBy(x: 1, y: -1)
      UIGraphicsPushContext(ctx)
      body(ctx)
      UIGraphicsPopContext()
    }
    return bytes
  }

  /// 位图里 y ∈ [y0, y1)、x ∈ [0, plotW) 画上了东西的像素数。
  static func inked(_ bytes: [UInt8], rows y0: Double, _ y1: Double, plotW: Double) -> Int {
    let w = Int(size.width)
    var count = 0
    for row in max(0, Int(y0.rounded(.up)))..<min(Int(size.height), Int(y1.rounded(.down))) {
      for col in 0..<min(w, Int(plotW)) where bytes[(row * w + col) * 4 + 3] > 0 { count += 1 }
    }
    return count
  }

  @Test("墙的价位落进主图图例区：线（含选中重画的那一条）不画进图例那几行，图例下沿以下照画；几何、点选、图例合计照旧")
  func linesStayOutOfLegend() throws {
    var (r, _) = Self.renderer()
    let L = r.layout(size: Self.size), range = r.priceRange(size: Self.size)
    let legend = r.mainLegendInset(plotW: L.plotW)
    #expect(legend > 12, "开着主力，图例至少两行")
    let b = r.state.series
    let seen = b.time(at: b.count - 30) + 1
    let inY = L.main.y + legend / 2, outY = L.main.y + legend + 40
    let inside = Self.order(.usdtPerp, .bid, price: price(r, atY: inY), firstSeen: seen, bucket: 1)
    let below = Self.order(.usdtPerp, .ask, price: price(r, atY: outY), firstSeen: seen, notional: 8_000_000, bucket: 2)
    r.state.orderFlow?.orders = [inside, below]
    let f = frame(r)
    let inBand = try #require(f.bands.first { $0.key == OrderFlowGroupKey(inside) }, "图例区里的墙照样有几何")
    let outBand = try #require(f.bands.first { $0.key == OrderFlowGroupKey(below) })
    #expect(inBand.frame.maxY < L.main.y + legend && inBand.frame.minY > L.main.y, "线在图例区里：\(inBand.frame)")
    #expect(outBand.frame.minY > L.main.y + legend)
    #expect(ChartRenderer.orderFlowHit(f.bands, x: Double(inBand.frame.midX), y: Double(inBand.frame.midY))?.key == inBand.key,
            "点选照旧认得图例区里的那条")
    #expect(f.bidTotal == inside.notional && f.askTotal == below.notional, "图例合计照旧")

    let bytes = try Self.bitmap { ctx in
      #expect(r.drawOrderFlow(ctx, pane: L.main, range: range, L: L) == 2)
    }
    #expect(Self.inked(bytes, rows: L.main.y, L.main.y + legend, plotW: L.plotW) == 0, "图例区里一个像素都不画")
    let outInk = Self.inked(bytes, rows: Double(outBand.frame.minY) - 1, Double(outBand.frame.maxY) + 1, plotW: L.plotW)
    #expect(outInk > Int(outBand.frame.width), "图例下沿以下的线照画：\(outInk) 像素")

    // 选中图例区里那一条：crossLayer 上的描边重画也不进图例区。
    r.state.orderFlowSelected = inBand.key
    var drew = false
    let hover = try Self.bitmap { ctx in drew = r.drawOrderFlowHover(ctx, pane: L.main, range: range, L: L) }
    #expect(drew)
    #expect(Self.inked(hover, rows: L.main.y, L.main.y + legend, plotW: L.plotW) == 0)
    // 选中图例下沿以下那一条照画。
    r.state.orderFlowSelected = outBand.key
    let hover2 = try Self.bitmap { ctx in _ = r.drawOrderFlowHover(ctx, pane: L.main, range: range, L: L) }
    #expect(Self.inked(hover2, rows: Double(outBand.frame.minY) - 2, Double(outBand.frame.maxY) + 2, plotW: L.plotW) > 0)
  }

  @Test("详情卡上限：宽 ≤ 85% 绘图区、高 ≤ 55% 主图且不越过线的命中带（至少 8 pt 高）")
  func cardBudget() throws {
    typealias B = OrderFlowCardBudget
    #expect(B.maxWidth(plotW: 400) == 340)
    let place = { (bandY: Double, top: Double, bottom: Double, main: Double) in
      B.placement(bandY: bandY, bandHalf: 3, top: top, bottom: bottom, mainHeight: main, plotW: 400, anchorX: 100, candle: nil)
    }
    // 带在上面：卡在下半边、贴主图下沿，最高 55% 主图；带在下面：卡在上半边、贴上沿。
    let top = place(60, 20, 420, 400)
    #expect(top.below && abs(top.maxHeight - 220) < 1e-9 && abs(top.top - 200) < 1e-9)
    #expect(!top.leading && top.maxWidth == 340 && !top.compact && !top.coversCandle)
    let low = place(380, 20, 420, 400)
    #expect(!low.below && abs(low.maxHeight - 220) < 1e-9 && low.top == 20)
    // 带在中间偏上、主图矮：摆下面，最高就是带下沿到主图下沿（140 < 55% × 280）。
    let mid = B.placement(bandY: 150, bandHalf: 4, top: 20, bottom: 300, mainHeight: 280, plotW: 400, anchorX: 300, candle: nil)
    #expect(mid.below && mid.maxHeight == 140 && mid.top == 160 && mid.leading)
    // 焦点带出来的上限：宽按绘图区、高按主图；卡躲的是命中带，线细也按 8 pt 高算。轻点选中没有十字线那根 K 线。
    var (r, orders) = Self.renderer()
    r.state.orderFlowSelected = OrderFlowGroupKey(orders[0])
    let focus = try #require(r.orderFlowFocus(size: Self.size))
    let L = r.layout(size: Self.size)
    #expect(focus.candle == nil)
    #expect(focus.cardMaxWidth == L.plotW * 0.85)
    #expect(focus.mainHeight == L.main.h)
    #expect(focus.bandHalf == ChartRenderer.orderFlowHitHeight / 2)
    let p = focus.cardPlacement
    #expect(p.maxHeight <= L.main.h * 0.55)
    if p.below {
      #expect(focus.bandY + focus.bandHalf + 6 <= p.top + 1e-9)
      #expect(abs(p.top + p.maxHeight - focus.mainBottom) < 1e-9, "贴主图下沿")
    } else {
      #expect(p.top + p.maxHeight <= focus.bandY - focus.bandHalf - 6 + 1e-9)
      #expect(p.top == focus.mainTop, "贴图例下的上沿")
    }
  }

  @Test("D4 详情卡在带的对面那一半、贴远端，不盖住十字线那根 K 线")
  func cardAvoidsCrosshairCandle() throws {
    typealias B = OrderFlowCardBudget
    typealias C = B.Candle
    // 主图 20…420（高 400），带在上半边 y = 100：卡在下半边贴下沿，高度段按三行卡 340…420。
    func place(anchorX: Double, candle: C?, bandY: Double = 100, top: Double = 20, bottom: Double = 420) -> B.Placement {
      B.placement(bandY: bandY, bandHalf: 4, top: top, bottom: bottom, mainHeight: bottom - top, plotW: 360,
                  anchorX: anchorX, candle: candle)
    }
    // K 线在上半边（影线 60…150），碰不着下沿那一段：卡照常 85% 宽。
    let clear = place(anchorX: 60, candle: C(left: 56, right: 64, top: 60, bottom: 150))
    #expect(clear.below && !clear.leading && clear.maxWidth == 306 && !clear.coversCandle)
    // K 线在左边、影线伸到下沿那一段（300…400）：卡在右侧收窄到 K 线右边以外（360 - 8 - (64 + 4) = 284）。
    let narrow = place(anchorX: 60, candle: C(left: 56, right: 64, top: 300, bottom: 400))
    #expect(narrow.below && !narrow.leading && abs(narrow.maxWidth - 284) < 1e-9 && !narrow.coversCandle)
    #expect(360 - B.sideInset - narrow.maxWidth >= 64 + B.candleGap - 1e-9, "卡的左缘在 K 线右边以外")
    // K 线在正中（右侧只剩 ~ 160 pt，窄过 minWidth）、影线伸进下沿那一段：换到带这一半的上沿；
    // 带上方只有 100 - 4 - 6 - 20 = 70 pt，放不下三行卡（80），出两行卡（60）。
    let center = place(anchorX: 180, candle: C(left: 176, right: 184, top: 300, bottom: 400))
    #expect(!center.below && center.top == 20 && center.compact && !center.coversCandle)
    // 带上方也放不下两行卡（带在 y = 80：上方 50 pt）：躲不开，照旧摆在对面、标出来。
    let stuck = place(anchorX: 180, candle: C(left: 176, right: 184, top: 300, bottom: 400), bandY: 80)
    #expect(stuck.below && stuck.coversCandle && stuck.maxWidth == 306)
    // 带压得低一点（y = 180，仍在上半边），带上方 20…170 放得下：卡换到上沿，K 线在下面碰不着。
    let flipped = place(anchorX: 180, candle: C(left: 176, right: 184, top: 300, bottom: 400), bandY: 180)
    #expect(!flipped.below && flipped.top == 20 && !flipped.coversCandle && flipped.maxWidth == 306)
    // 影线离下沿那一段还有空（K 线低点 330，卡顶 340，差 10 ≥ 4）：不用收窄。
    let gap = place(anchorX: 180, candle: C(left: 176, right: 184, top: 250, bottom: 330))
    #expect(gap.below && gap.maxWidth == 306 && !gap.coversCandle)
  }

  @Test("D4 十字线停在线上：卡的高度段与那根 K 线不重叠，或横向躲开")
  func crosshairCardSkipsCandle() throws {
    var (r, _) = Self.renderer()
    let L = r.layout(size: Self.size)
    let f = frame(r)
    // 每条带都按一遍十字线，焦点在的时候卡不能和那根 K 线的影线范围相交（躲不开的会标出来）。
    var checked = 0
    for band in f.bands {
      let x = Double(band.frame.minX + band.frame.width * 0.3)
      let t = r.state.view.t(atX: x, plotW: L.plotW)
      let i = r.state.series.index(atTime: t)
      r.state.crosshair = Crosshair(index: i, price: price(r, atY: Double(band.frame.midY)))
      guard let focus = r.orderFlowFocus(size: Self.size), let c = focus.candle else { continue }
      checked += 1
      #expect(c.top <= c.bottom && c.left < c.right)
      let p = focus.cardPlacement
      let h = min(p.maxHeight, p.compact ? OrderFlowCardBudget.compactHeight : OrderFlowCardBudget.fullHeight)
      let lo = p.below ? p.top + p.maxHeight - h : p.top, hi = lo + h
      let x0 = p.leading ? OrderFlowCardBudget.sideInset : L.plotW - OrderFlowCardBudget.sideInset - p.maxWidth
      let x1 = x0 + p.maxWidth
      let overlap = c.top < hi && c.bottom > lo && c.left < x1 && c.right > x0
      #expect(!overlap || p.coversCandle, "卡 \(x0)…\(x1) × \(lo)…\(hi) 盖住了 K 线 \(c)")
      // 卡不越过命中带。
      if p.below { #expect(p.top >= focus.bandY + focus.bandHalf + OrderFlowCardBudget.bandGap - 1e-9) }
      else { #expect(p.top + p.maxHeight <= focus.bandY - focus.bandHalf - OrderFlowCardBudget.bandGap + 1e-9) }
    }
    #expect(checked > 0)
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
          // 金额签：签底 85% 叠到图区底色上，字对它 ≥ 4.5:1。
          for c in [lc, dc] {
            let shown = mixHex(c, bg, 1 - ChartRenderer.orderFlowLabelAlpha)
            let ink = ChartRenderer.orderFlowLabelInk(shown)
            #expect(Palette.contrast(ink, shown) >= 4.5,
                    "\(skin) \(dark) \(c.value) 签字 \(ink.value) 对签底 \(shown.value) 只有 \(Palette.contrast(ink, shown))")
          }
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


  @Test("轻点：点在蜡烛高低范围内是 K 线的（出十字线），哪怕底下垫着一条大单带子；点在蜡烛外的带子上才出详情卡")
  func tapOnCandleBeatsOrderFlowBand() throws {
    let (r, _) = Self.renderer()
    let L = r.layout(size: Self.size)
    let b = r.state.series
    let bands = frame(r).bands
    var overlap: CGPoint?
    var clear: CGPoint?
    for band in bands {
      let by = Double(band.frame.midY)
      for i in 0..<b.count {
        let cx = r.state.view.x(Double(b.time(at: i)), plotW: L.plotW)
        guard cx > Double(band.frame.minX) + 1, cx < Double(band.frame.maxX) - 1, cx > 0, cx < L.plotW else { continue }
        let yHi = y(r, b.high[i]), yLo = y(r, b.low[i])
        if by > yHi + 1, by < yLo - 1, overlap == nil { overlap = CGPoint(x: cx, y: by) }
        if (by < yHi - ChartRenderer.candleHitSlop - 2 || by > yLo + ChartRenderer.candleHitSlop + 2), clear == nil {
          clear = CGPoint(x: cx, y: by)
        }
      }
    }
    // 夹具里 ±0.2% 的单必然横穿最近几根蜡烛，也必然有一段落在蜡烛外。
    let onCandle = try #require(overlap)
    let offCandle = try #require(clear)
    // 冲突点：两边都认——带子的 44pt 命中区盖住了蜡烛，以前这里出的是详情卡。
    #expect(r.orderFlowHit(at: onCandle, size: Self.size) != nil)
    #expect(r.candleHit(at: onCandle, size: Self.size))
    // 蜡烛外的带子上：不是 K 线，照旧出卡片。
    #expect(!r.candleHit(at: offCandle, size: Self.size))
    #expect(r.orderFlowHit(at: offCandle, size: Self.size) != nil)
    // 主图外（价格轴上）不算蜡烛。
    #expect(!r.candleHit(at: CGPoint(x: L.plotW + 5, y: onCandle.y), size: Self.size))
  }
}

// MARK: - 渲染压测 · 2 万单（2026-09-28）
//
// 一只热门币三天里攒出来的量级：2 万单、现价 ±2% 以内、按步长分桶（同一桶上前后挂了又撤很多回），
// 一成挂着、两成成交、七成撤单，寿命 30 秒到 4 小时。1 分钟与日线两种密度（日线上三天的单全挤在最后三根里），
// 各看一屏 30 / 300 / 1500 根。量四样：
//
// - `bands.cold`：并墙 + 排名 + 落带算一遍（清缓存后 `orderFlowFrame`）；
// - `frame.static`：缓存热着画一帧三层（十字线动、盘口跳时就是这样）；
// - `frame.pan`：视野挪一根再画一帧三层（拖图、捏合的每一帧）；
// - `frame.pan.selected_offscreen`：同上，另有一堵选中的墙已经滚出屏，照 ChartView 那样每帧再问一次 `orderFlowFocus`；
// 以及基线 `frame.pan.no_orderflow`（同一屏不开订单流）。
//
// 只打 `ORDERFLOW-PERF` 行（p50 / p95，毫秒），不做墙钟断言——模拟器上抖得厉害；结构性判据另有单测。
@MainActor
@Suite("主力订单流 · 渲染压测", .serialized)
struct OrderFlowPerfBenchTests {
  static let size = CGSize(width: 402, height: 620)
  static let scale: CGFloat = 3
  static let orderCount = 20_000

  static func p95(_ xs: [Double]) -> Double {
    let s = xs.sorted()
    guard !s.isEmpty else { return .nan }
    return s[min(s.count - 1, max(0, Int((0.95 * Double(s.count)).rounded(.up)) - 1))]
  }

  static func report(_ name: String, _ samples: [Double], extra: String = "") {
    print(String(format: "ORDERFLOW-PERF %@ p50_ms=%.3f p95_ms=%.3f rounds=%d %@",
                 name, benchMedian(samples), p95(samples), samples.count, extra))
  }

  /// 2 万单，全落在最近三天（服务端历史上限）里，价位贴着当时那根的收盘。
  static func orders(series: BarSeries, count: Int = orderCount, seed: UInt64 = 20260928) -> (orders: [BigOrder], step: Double) {
    var r = BenchRNG(seed: seed)
    let last = series.time(at: series.count - 1)
    let span: Int64 = 3 * 86_400_000
    let t0 = max(series.firstTime, last - span)
    let step = (series.close.last! * 0.001).rounded()
    let products: [OrderFlowProduct] = [.spot, .usdtPerp, .usdtPerp, .coinPerp, .delivery]
    var out: [BigOrder] = []
    out.reserveCapacity(count)
    for i in 0..<count {
      let seen = t0 + Int64(r.unit() * Double(last - t0))
      let idx = series.index(atTime: Double(seen))
      let side: BookSide = r.unit() < 0.5 ? .bid : .ask
      let off = series.close[idx] * r.range(0.0005, 0.02)
      let bucket = Int64(((side == .bid ? series.close[idx] - off : series.close[idx] + off) / step).rounded())
      let roll = r.unit()
      let status: BigOrder.Status = roll < 0.1 ? .live : roll < 0.3 ? .filled : .cancelled
      let life = Int64(exp(r.range(log(30_000), log(4 * 3_600_000))))
      let end: Int64? = status == .live ? nil : min(last + 30_000, seen + life)
      let n = exp(r.range(log(1_000_000), log(80_000_000)))
      let filled = status == .filled ? n : (status == .cancelled && r.unit() < 0.3 ? n * r.range(0.05, 0.9) : 0)
      out.append(BigOrder(venueID: "binance:\(products[i % products.count].rawValue):\(i)", exchange: "币安",
                          product: products[i % products.count], side: side, bucket: bucket,
                          price: Double(bucket) * step, firstSeenMs: seen, endMs: end, status: status,
                          initialNotional: n, notional: n, filledNotional: filled, threshold: 1_000_000))
    }
    out.sort { $0.firstSeenMs < $1.firstSeenMs }
    return (out, step)
  }

  static func state(interval: Interval, visible: Int, orderFlow: Bool = true) -> ChartState {
    let series = benchSeries(count: interval == .d1 ? 1000 : 6000, interval: interval)
    let subs: [IndicatorID] = [.vol, .macd]
    let layout = Layout(width: Double(size.width), height: Double(size.height), subs: subs)
    let view = ViewMath.reset(series: series, plotW: layout.plotW, spacing: layout.plotW / Double(visible))
    var s = ChartState(series: series, symbol: benchSymbol(), view: view, overlays: [.ma], subs: subs,
                       params: IndicatorID.factoryParams)
    if orderFlow {
      let (orders, step) = Self.orders(series: series)
      s.orderFlow = OrderFlowSnapshot(symbol: s.symbol.symbol, phase: .ready, orders: orders,
                                      asOfMs: series.time(at: series.count - 1) + 30_000,
                                      thresholds: OrderFlowThresholds(spot: 1_000_000, usdtPerp: 1_000_000,
                                                                      coinPerp: 1_000_000, delivery: 1_000_000,
                                                                      step: step))
      let px = series.close.last!
      s.depth = OrderBook(symbol: s.symbol.symbol, time: series.lastTime,
                          bids: (1...5).map { .init(price: px - Double($0) * 0.1, quantity: Double(6 - $0) * 3) },
                          asks: (1...5).map { .init(price: px + Double($0) * 0.1, quantity: Double($0) * 2) })
    }
    return s
  }

  func draw(_ r: ChartRenderer, _ ctx: CGContext) {
    ctx.saveGState(); r.drawPlot(in: ctx, size: Self.size, scale: Self.scale); ctx.restoreGState()
    ctx.saveGState(); r.drawLive(in: ctx, size: Self.size, scale: Self.scale); ctx.restoreGState()
    ctx.saveGState(); r.drawCross(in: ctx, size: Self.size, scale: Self.scale); ctx.restoreGState()
  }

  func bandsCold(_ r: ChartRenderer) -> ChartRenderer.OrderFlowFrame {
    let L = r.layout(size: Self.size)
    return r.orderFlowFrame(pane: L.main, range: r.priceRange(size: Self.size), L: L)
  }

  static let cases: [(Interval, Int)] = [(.m1, 300), (.m1, 30), (.m1, 1500), (.d1, 300), (.d1, 30), (.d1, 1500)]

  @Test("拖图、捏合不重算并墙：视野一动只重排这一屏，切段 / 并墙 / 建组那一半走缓存")
  func panDoesNotRegroup() {
    let base = Self.state(interval: .m1, visible: 300)
    var r = ChartRenderer(state: base)
    _ = bandsCold(r)
    let before = ChartRenderer.OrderFlowWallCache.shared.computed
    var next = base
    for i in 1...20 {
      next.view = ViewWindow(to: base.view.to - Double(base.series.step) * Double(i), span: base.view.span * (1 + 0.01 * Double(i)))
      r.state = next
      _ = bandsCold(r)
    }
    #expect(ChartRenderer.OrderFlowWallCache.shared.computed == before)
    // 快照一变（换一份单子）才重算。
    var other = next
    other.orderFlow?.orders.removeLast()
    r.state = other
    _ = bandsCold(r)
    #expect(ChartRenderer.OrderFlowWallCache.shared.computed == before + 1)
  }

  @Test("缓存的墙与直接 groups() 逐堵相同；按侧、类挑出来的与只拿那一类单现算的逐堵相同、先后相同（屏外选中认回来靠它）")
  func cachedWallsMatchDirectGrouping() throws {
    let base = Self.state(interval: .m1, visible: 300)
    let r = ChartRenderer(state: base)
    let flow = try #require(base.orderFlow)
    let cached = r.orderFlowWalls(flow).map(\.group)
    let gap = r.orderFlowMergeGapMs, life = r.orderFlowMinLifeMs, step = flow.thresholds.step
    #expect(cached == OrderFlowGroup.groups(flow.orders, gapMs: gap, minLifeMs: life, step: step))
    for side in [BookSide.bid, .ask] {
      for contract in [false, true] {
        let probe = try #require(cached.first { $0.side == side && $0.contract == contract })
        let kind = flow.orders.filter { OrderFlowGroupKey($0).sameKind(probe.key) }
        #expect(cached.filter { $0.key.sameKind(probe.key) }
                == OrderFlowGroup.groups(kind, gapMs: gap, minLifeMs: life, step: step))
      }
    }
  }

  @Test("派生量建组时算一次：与逐行 / 逐单现算的结果逐位相同，字段被改后跟着更新")
  func derivedMatchesNaive() throws {
    let base = Self.state(interval: .m1, visible: 300)
    let r = ChartRenderer(state: base)
    let groups = r.orderFlowWalls(try #require(base.orderFlow)).map(\.group)
    for g in groups.prefix(400) {
      #expect(g.notional == g.books.reduce(0) { $0 + $1.notional })
      #expect(g.drawNotional == g.books.reduce(0) { $0 + Double($1.latest.thicknessQuarters) * $1.latest.threshold / 4 })
      #expect(g.quarters == g.books.reduce(0) { $0 + $1.latest.thicknessQuarters })
      #expect(g.firstSeenMs == g.members.map(\.firstSeenMs).min())
      #expect(g.isLive == g.members.contains(where: \.isLive))
      #expect(g.endMs == (g.isLive ? nil : g.members.compactMap(\.endMs).max()))
      #expect(g.hasFill == g.books.contains { $0.hasFill })
      #expect(g.bucketCount == Set(g.spans.map(\.bucket)).count)
      let top = g.books.map(\.latest).max { a, b in
        a.thicknessQuarters != b.thicknessQuarters ? a.thicknessQuarters < b.thicknessQuarters : a.id > b.id
      }
      #expect(g.price == top?.price)
    }
    var g = try #require(groups.first { $0.books.count > 1 })
    let dropped = g.books.removeLast()
    #expect(g.notional == g.books.reduce(0) { $0 + $1.notional })
    #expect(dropped.notional > 0)
  }

  // ---------------------------------------------------------------- D2：并墙挪到后台

  typealias WallCache = ChartRenderer.OrderFlowWallCache

  static func wallKey(_ symbol: String, _ orders: [BigOrder], step: Double) -> WallCache.Key {
    .init(symbol: symbol, orders: orders, display: OrderFlowDisplay(), step: step, gapMs: 60_000, minLifeMs: 60_000)
  }

  static func smallOrders(_ n: Int = 3000) -> (orders: [BigOrder], step: Double) {
    orders(series: benchSeries(count: 2000, interval: .m1), count: n)
  }

  @Test("后台并墙：没算好先给同一只的上一份（不给别的品种的），算好之后与同步算的逐堵相同")
  func backgroundLookupServesSameLaneOnly() {
    let cache = WallCache(capacity: 3)
    let (orders, step) = Self.smallOrders()
    let a = Self.wallKey("BTCUSDT", orders, step: step)
    // 一份都没有：不给、不阻塞，交给后台。
    #expect(cache.lookup(a) == nil)
    cache.waitUntilIdle()
    let hitA = cache.lookup(a)
    #expect(hitA?.exact == true)
    var changed = orders
    changed[0].notional *= 2
    let b = Self.wallKey("BTCUSDT", changed, step: step)
    // 同一只换了快照：先给 a 那份顶着。
    let stale = cache.lookup(b)
    #expect(stale?.exact == false)
    #expect(stale?.entry.walls.map(\.group) == hitA?.entry.walls.map(\.group))
    // 别的品种、同一份单子：旧品种的那份不能顶到它头上。
    let c = Self.wallKey("ETHUSDT", changed, step: step)
    #expect(cache.lookup(c) == nil)
    // 换了显示开关也是另一条道。
    var hidden = b; hidden.display.spot = false
    #expect(cache.lookup(hidden) == nil)
    cache.waitUntilIdle()
    let exact = cache.lookup(b)
    #expect(exact?.exact == true)
    #expect(exact?.entry.walls.map(\.group) == WallCache.compute(b).walls.map(\.group))
    #expect(exact?.entry.live == WallCache.compute(b).live)
  }

  @Test("同一份快照只算一次：连着问几遍、后台还没算完也不重复排队")
  func backgroundSameSnapshotComputedOnce() {
    let cache = WallCache(capacity: 3)
    let (orders, step) = Self.smallOrders()
    let a = Self.wallKey("BTCUSDT", orders, step: step)
    for _ in 0..<5 { _ = cache.lookup(a) }
    cache.waitUntilIdle()
    for _ in 0..<5 { #expect(cache.lookup(a)?.exact == true) }
    #expect(cache.computed == 1)
    // 同步取同一把也不再算。
    _ = cache.entry(a)
    #expect(cache.computed == 1)
  }

  @Test("排队只留最新一把；先请求的那份晚算完也不会被当成更新的那份顶上去")
  func backgroundLatestWins() {
    let cache = WallCache(capacity: 3)
    let (orders, step) = Self.smallOrders()
    var keys: [WallCache.Key] = []
    for i in 0..<6 {
      var o = orders
      o[i].notional *= 3
      keys.append(Self.wallKey("BTCUSDT", o, step: step))
    }
    for k in keys.prefix(5) { _ = cache.lookup(k) }
    cache.waitUntilIdle()
    // 最后请求的那一把一定算了；中间还没开算的被顶掉，不白算。
    #expect(cache.lookup(keys[4])?.exact == true)
    #expect(cache.computed <= 3)
    // 拿旧的顶着时给的是最后请求的那一份。
    #expect(cache.lookup(keys[5])?.entry.walls.map(\.group) == WallCache.compute(keys[4]).walls.map(\.group))

    // 模拟晚到：代数 20 的先存进来，代数 10 的（先请求的）后存进来。
    let fresh = WallCache(capacity: 3)
    fresh.store(keys[1], WallCache.compute(keys[1]), generation: 20)
    fresh.store(keys[0], WallCache.compute(keys[0]), generation: 10)
    #expect(fresh.lookup(keys[5])?.entry.walls.map(\.group) == WallCache.compute(keys[1]).walls.map(\.group))
    // 满了踢代数最小的，不是最后存进来的。
    fresh.store(keys[2], WallCache.compute(keys[2]), generation: 30)
    fresh.store(keys[3], WallCache.compute(keys[3]), generation: 40)
    #expect(fresh.lookup(keys[0])?.exact != true)
    #expect(fresh.lookup(keys[3])?.exact == true)
    fresh.waitUntilIdle()
  }

  @Test("图表视图那条路：快照换了这一帧不在主线程上并墙，先按上一份画、记下「顶着的」，后台算好换盒子后与同步画的逐条相同")
  func rendererServesStaleThenCatchesUp() {
    var base = Self.state(interval: .m1, visible: 300)
    let sym = "D2STALEUSDT"
    base.symbol = benchSymbol(sym)
    base.orderFlow?.symbol = sym
    var r = ChartRenderer(state: base)
    r.orderFlowPrepareInBackground = true
    _ = bandsCold(r)
    WallCache.shared.waitUntilIdle()
    r.orderFlowCache = ChartRenderer.OrderFlowCache()
    let first = bandsCold(r)
    #expect(!r.orderFlowCache.servedStale)
    #expect(first == bandsCold(ChartRenderer(state: base)))

    var next = base
    next.orderFlow?.orders.removeLast(500)
    next.orderFlow?.asOfMs += 1000
    r.state = next
    let during = bandsCold(r)
    #expect(r.orderFlowCache.servedStale)
    #expect(!during.bands.isEmpty)
    WallCache.shared.waitUntilIdle()
    r.orderFlowCache = ChartRenderer.OrderFlowCache()
    #expect(bandsCold(r) == bandsCold(ChartRenderer(state: next)))
    #expect(!r.orderFlowCache.servedStale)

    // 换品种：旧品种那份不顶到新品种上，先空着。
    var other = next
    other.symbol = benchSymbol("D2OTHERUSDT")
    other.orderFlow?.symbol = "D2OTHERUSDT"
    other.orderFlow?.asOfMs += 1
    r.state = other
    #expect(bandsCold(r).bands.isEmpty)
    #expect(r.orderFlowCache.servedStale)
    WallCache.shared.waitUntilIdle()
    r.orderFlowCache = ChartRenderer.OrderFlowCache()
    #expect(bandsCold(r) == bandsCold(ChartRenderer(state: other)))
  }

  @Test("D1 底噪按像素行并：同行同色相邻的并成一条，不同色 / 不同行 / 隔开的不并，封顶时留名次最前的")
  func noiseMergeRules() throws {
    let r = ChartRenderer(state: Self.state(interval: .m1, visible: 300))
    let g = try #require(bandsCold(r).bands.first).group
    let band = { (x0: Double, x1: Double, y: Double, color: Hex) in
      ChartRenderer.OrderFlowBand(group: g, frame: CGRect(x: x0, y: y - 0.5, width: x1 - x0, height: 1), color: color,
                                  dark: false, thin: false, role: .noise, alpha: ChartRenderer.orderFlowNoiseAlpha)
    }
    let a: Hex = "#112233", b: Hex = "#445566"
    // 0、1 同行同色重叠 → 一条；2 同行同色隔 0.4 pt → 也并；3 同行不同色；4 下一行；5 同行同色隔 3 pt。
    let noise = [band(10, 40, 100.2, a), band(30, 60, 100.4, a), band(60.4, 70, 100.1, a), band(10, 40, 100.2, b),
                 band(10, 40, 101.6, a), band(73, 80, 100.2, a)]
    let out = ChartRenderer.orderFlowMergeNoise(noise, colorIndex: [0, 0, 0, 1, 0, 0], max: 200)
    #expect(out.count == 4)
    let first = try #require(out.first)
    #expect(first.rank == 0)
    #expect(first.frame == CGRect(x: 10, y: 100, width: 60, height: 1))
    #expect(out.map(\.rank) == [0, 3, 4, 5])
    #expect(out.allSatisfy { $0.frame.height == 1 && $0.frame.minY == $0.frame.minY.rounded() })
    // 封顶：留名次最前的两条。
    let capped = ChartRenderer.orderFlowMergeNoise(noise, colorIndex: [0, 0, 0, 1, 0, 0], max: 2)
    #expect(capped.map(\.rank) == [0, 3])
  }

  @Test("D1 1 分钟 2 万单：底噪画的条数封在 200 以内且比逐条少，名义最大的那条在画，丢的只有名次靠后的；最小的那条仍选得中")
  func noiseMergedOnDenseMinuteChart() throws {
    for visible in [300, 1500] {
      var r = ChartRenderer(state: Self.state(interval: .m1, visible: visible))
      let frame = bandsCold(r)
      let noise = frame.bands.filter { $0.role == .noise }
      let strokes = frame.noiseStrokes
      #expect(noise.count > ChartRenderer.orderFlowNoiseDrawMax)
      #expect(strokes.count <= ChartRenderer.orderFlowNoiseDrawMax)
      #expect(strokes.count < noise.count)
      let covered = { (b: ChartRenderer.OrderFlowBand) in
        strokes.contains { s in
          s.color == b.color && abs(Double(s.frame.midY) - Double(b.frame.midY)) <= 0.5
            && s.frame.minX <= b.frame.minX && s.frame.maxX >= b.frame.maxX
        }
      }
      #expect(covered(try #require(noise.first)))
      for (rank, b) in noise.enumerated() where !covered(b) {
        #expect(strokes.count == ChartRenderer.orderFlowNoiseDrawMax)
        #expect(try #require(strokes.last).rank < rank)
      }
      // 命中 / 选中仍按逐条的带：名义最小的一条底噪（多半没画出来）选中后照样找得到、详情卡照出。
      let smallest = try #require(noise.last)
      var sel = r.state
      sel.orderFlowSelected = smallest.key
      r.state = sel
      let focus = try #require(r.orderFlowFocus(size: Self.size))
      #expect(focus.group.key == smallest.key)
    }
  }

  @Test("D1 按时间粗筛不改结果：拖到最左、最右、中间，筛过的与整份逐条算的一样（与日线同一把尺）")
  func visibleTimeFilterKeepsFrames() {
    for interval in [Interval.m1, .d1] {
      let base = Self.state(interval: interval, visible: 300)
      let step = Double(base.series.step)
      for shift in [0.0, -150, -2990, -5990, 40] {
        var s = base
        s.view = ViewWindow(to: base.view.to + step * shift, span: base.view.span)
        let r = ChartRenderer(state: s)
        let frame = bandsCold(r)
        // 逐墙核对：每一条带都在主图横向范围里、并且没有一堵落在屏里的墙被丢（数条数与不筛时一致）。
        #expect(frame.bands.allSatisfy { $0.frame.maxX > 0 && $0.frame.minX < r.layout(size: Self.size).plotW })
        #expect(frame.bands.count == r.orderFlowFrameUnfiltered(size: Self.size))
      }
    }
  }

  @Test("2 万单：并墙 + 排名 + 落带、静止一帧、拖动一帧、选中墙在屏外时拖动一帧")
  func bench() {
    let ctx = benchContext(size: Self.size, scale: Self.scale)
    // 热身（首个档位会吃到进程冷启动的抖动），不记。原来只画 5 帧，第一个档位（1m.v300）的
    // p95 常年比后面的档位高一截；改成拖着图连画 2 秒，把 CPU 频率与缓存都热起来。
    do {
      let base = Self.state(interval: .m1, visible: 300)
      var r = ChartRenderer(state: base)
      var next = base
      let t0 = ContinuousClock.now
      var i = 0
      while t0.duration(to: .now) < .seconds(2) {
        i += 1
        next.view = ViewWindow(to: base.view.to - Double(base.series.step) * Double(i % 20 + 1), span: base.view.span)
        r.state = next
        draw(r, ctx)
      }
    }
    for (interval, visible) in Self.cases {
      let tag = "\(interval.rawValue).v\(visible)"
      let base = Self.state(interval: interval, visible: visible)
      var r = ChartRenderer(state: base)
      let first = bandsCold(r)
      let extra = "bands=\(first.bands.count) labels=\(first.labels.count)"

      // 分段：切段 / 去碎屑 / 并墙 / 建组 + 排序（全量，不按屏筛）。
      let flow = base.orderFlow!
      let gap = r.orderFlowMergeGapMs, minLife = r.orderFlowMinLifeMs
      var segs: [OrderFlowGroup.Segment] = [], kept: [OrderFlowGroup.Segment] = [], walls: [OrderFlowGroup.Wall] = []
      Self.report("\(tag).phase.segments", benchRun(rounds: 10, warmup: 1) { _ in
        segs = OrderFlowGroup.segments(flow.orders, gapMs: gap) })
      Self.report("\(tag).phase.drop_short", benchRun(rounds: 10, warmup: 1) { _ in
        kept = OrderFlowGroup.dropShortLived(segs, minLifeMs: minLife) })
      Self.report("\(tag).phase.walls", benchRun(rounds: 10, warmup: 1) { _ in
        walls = OrderFlowGroup.walls(kept, gapMs: gap) })
      Self.report("\(tag).phase.group_sort", benchRun(rounds: 10, warmup: 1) { _ in
        var g = walls.compactMap { $0.group(step: flow.thresholds.step) }
        g.sort { OrderFlowGroup.drawOrder($0, $1) } },
        extra: "segments=\(segs.count) kept=\(kept.count) walls=\(walls.count)")

      Self.report("\(tag).bands.cold", benchRun(rounds: 20) { _ in
        r.orderFlowCache = ChartRenderer.OrderFlowCache(); _ = bandsCold(r) }, extra: extra)

      draw(r, ctx)
      Self.report("\(tag).frame.static", benchRun(rounds: 30) { _ in draw(r, ctx) })
      do {
        let L = r.layout(size: Self.size), range = r.priceRange(size: Self.size)
        Self.report("\(tag).draw.bands_only", benchRun(rounds: 30) { _ in
          ctx.saveGState(); _ = r.drawOrderFlow(ctx, pane: L.main, range: range, L: L); ctx.restoreGState() })
        Self.report("\(tag).draw.labels_only", benchRun(rounds: 30) { _ in
          ctx.saveGState(); _ = r.drawOrderFlowLabels(ctx, pane: L.main, range: range, L: L); ctx.restoreGState() })
      }
      Self.report("\(tag).frame.static.no_orderflow", {
        let rp = ChartRenderer(state: Self.state(interval: interval, visible: visible, orderFlow: false))
        return benchRun(rounds: 30) { _ in draw(rp, ctx) }
      }())

      let step = Double(base.series.step)
      var next = base
      Self.report("\(tag).frame.pan", benchRun(rounds: 30) { i in
        next.view = ViewWindow(to: base.view.to - step * Double(i % 20 + 1), span: base.view.span)
        r.state = next
        draw(r, ctx)
      })

      // 拖动一帧拆成四段：换 state（recalc）、plot、live、cross 各自多少。
      do {
        var parts: [[Double]] = [[], [], [], []]
        for i in 0..<30 {
          next.view = ViewWindow(to: base.view.to - step * Double(i % 20 + 21), span: base.view.span)
          var t = ContinuousClock.now
          r.state = next
          parts[0].append(benchMs(t.duration(to: .now))); t = .now
          ctx.saveGState(); r.drawPlot(in: ctx, size: Self.size, scale: Self.scale); ctx.restoreGState()
          parts[1].append(benchMs(t.duration(to: .now))); t = .now
          ctx.saveGState(); r.drawLive(in: ctx, size: Self.size, scale: Self.scale); ctx.restoreGState()
          parts[2].append(benchMs(t.duration(to: .now))); t = .now
          ctx.saveGState(); r.drawCross(in: ctx, size: Self.size, scale: Self.scale); ctx.restoreGState()
          parts[3].append(benchMs(t.duration(to: .now)))
        }
        for (name, xs) in zip(["recalc", "plot", "live", "cross"], parts) { Self.report("\(tag).frame.pan.\(name)", xs) }
      }

      // 快照更新一帧：订单流推来一份新快照（内容变了、数组是新的），换 state + 画一帧。
      // `.sync`：原来的做法，并墙（切段 / 去碎屑 / 并墙 / 建组 + 排序）同步做在这一帧里。
      // 不带后缀的：图表视图的做法（`orderFlowPrepareInBackground`），这一帧先拿上一份顶着画，并墙交给后台；
      // `.ready`：后台算好之后那一帧（换盒子、按新的一份重画三层）。每轮之间等后台排空（实盘快照一秒一份，
      // 早就算完了），等的时间不计。
      do {
        var snap = base
        var counter = 0
        func bump() {
          counter += 1
          var f = flow
          f.orders[counter % f.orders.count].notional *= 1.01
          f.asOfMs += Int64(counter) * 1000
          snap.orderFlow = f
        }
        Self.report("\(tag).frame.snapshot_update.sync", benchRun(rounds: 15) { _ in
          bump(); r.state = snap; draw(r, ctx)
        })
        r.orderFlowPrepareInBackground = true
        var update: [Double] = [], ready: [Double] = []
        for i in -3..<20 {
          ChartRenderer.OrderFlowWallCache.shared.waitUntilIdle()
          r.orderFlowCache = ChartRenderer.OrderFlowCache()  // 上一轮「算好了」那一下（与计时无关）
          bump()
          var t = ContinuousClock.now
          r.state = snap
          draw(r, ctx)
          let u = benchMs(t.duration(to: .now))
          ChartRenderer.OrderFlowWallCache.shared.waitUntilIdle()
          t = .now
          r.orderFlowCache = ChartRenderer.OrderFlowCache()
          draw(r, ctx)
          let d = benchMs(t.duration(to: .now))
          if i >= 0 { update.append(u); ready.append(d) }
        }
        Self.report("\(tag).frame.snapshot_update", update)
        Self.report("\(tag).frame.snapshot_ready", ready)
        r.orderFlowPrepareInBackground = false
        r.state = base
      }

      // 选中一堵墙，再把视野往左挪到它起点之前（它完全看不见，屏里照旧是满屏的单）。
      r.state = base
      if let wall = bandsCold(r).bands.first(where: { $0.role == .main && Double($0.group.firstSeenMs) - base.view.span * 1.5 > Double(flow.orders[0].firstSeenMs) }) {
        var sel = base
        sel.orderFlowSelected = wall.key
        let shift = Double(wall.group.firstSeenMs) - step * 25 - base.view.to
        sel.view = ViewWindow(to: base.view.to + shift, span: base.view.span)
        r.state = sel
        let found = r.orderFlowFocus(size: Self.size) != nil
        Self.report("\(tag).frame.pan.selected_offscreen", benchRun(rounds: 30) { i in
          sel.view = ViewWindow(to: base.view.to + shift - step * Double(i % 20 + 1), span: base.view.span)
          r.state = sel
          _ = r.orderFlowFocus(size: Self.size)
          draw(r, ctx)
        }, extra: "focus_found=\(found)")
        Self.report("\(tag).focus.offscreen_only", benchRun(rounds: 20) { _ in _ = r.orderFlowFocus(size: Self.size) })
      }

      var plain = Self.state(interval: interval, visible: visible, orderFlow: false)
      var rp = ChartRenderer(state: plain)
      let viewBase = plain.view
      Self.report("\(tag).frame.pan.no_orderflow", benchRun(rounds: 30) { i in
        plain.view = ViewWindow(to: viewBase.to - step * Double(i % 20 + 1), span: viewBase.span)
        rp.state = plain
        draw(rp, ctx)
      })
    }
  }
}
