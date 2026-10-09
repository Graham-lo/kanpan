import KanpanCore
import KanpanNetwork
import KanpanPresentation
import SwiftUI

private typealias L = OrderFlowInsightLabels

/// Full-page evidence hierarchy. The chart keeps its own gestures; only the entry strip handles upward drags.
struct OrderFlowInsightsContent: View {
  let market: MarketModel
  let store: PrefsStore
  let proxy: ChartProxy
  let nowMs: Int64
  let summary: BigTradeSummary?
  @Environment(\.panelTheme) private var t

  private var link: OrderFlowLink { market.orderFlow }
  private var model: BigTradeSheetModel { link.sheet }
  private var feed: OrderFlowInsightsFeed { link.insights }
  private var instrument: InstrumentID { InstrumentID(market.symbol) }
  private var page: OrderFlowInsightsPage? { feed.symbol == market.symbol ? feed.page : nil }
  private var price: Double? { market.series?.close.last.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
  private var primaryName: String { VenueRegistry.all.first { $0.id == instrument.venue }?.shortName ?? instrument.venue }
  private var fresh: Bool {
    guard let page else { return false }
    return !feed.unavailable && nowMs - page.generatedAtMs < 90_000 && nowMs >= page.generatedAtMs - 60_000
  }
  private var windowEnd: Int64 { page.map { (($0.generatedAtMs - 3_000) / 60_000) * 60_000 } ?? ((nowMs - 3_000) / 60_000) * 60_000 }
  private var snapshot: OrderFlowSnapshot? {
    link.snapshot.flatMap { InstrumentID.canonical($0.symbol) == instrument.key ? $0 : nil }
  }
  private var currentOrders: [BigOrder] {
    OrderFlowInsightDigest.currentOrders(snapshot, symbol: market.symbol, nowMs: nowMs)
  }

  private var walls: (ask: OrderFlowInsightDigest.Wall?, bid: OrderFlowInsightDigest.Wall?) {
    OrderFlowInsightDigest.nearestWalls(currentOrders, instrument: instrument, price: price ?? 0, nowMs: nowMs)
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Space.m) {
        currentCard
        if model.focusT != nil { selectedCard }
        wallCard
        zoneCard
        flowCard
        if !market.isSpotInstrument { liquidationCard }
        eventsCard
        evidenceCard
      }
      .padding(.horizontal, Space.l)
      .padding(.top, Space.s)
      .padding(.bottom, Space.xxl)
    }
    .scrollBounceBehavior(.basedOnSize)
    .accessibilityIdentifier("insights.scroll")
  }

  private func card<C: View>(_ id: String, @ViewBuilder content: () -> C) -> some View {
    VStack(alignment: .leading, spacing: Space.m, content: content)
      .padding(Inset.card)
      .frame(maxWidth: .infinity, alignment: .leading)
      .liuliCard(radius: Radius.l)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier(id)
  }
  private func heading(_ title: String, _ meta: String? = nil) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack { Text(title); Spacer(minLength: Space.s); if let meta { Text(meta).font(TypeScale.caption).foregroundStyle(t.ink3) } }
      VStack(alignment: .leading, spacing: Space.xs) { Text(title); if let meta { Text(meta).font(TypeScale.caption).foregroundStyle(t.ink3) } }
    }
    .font(TypeScale.controlOn).foregroundStyle(t.ink2)
  }
  private func note(_ text: String) -> some View {
    Text(text).font(TypeScale.caption).foregroundStyle(t.ink3).fixedSize(horizontal: false, vertical: true)
  }
  private var divider: some View { Rectangle().fill(t.line).frame(height: LiuliMaterial.hairline) }
  private func money(_ x: Double) -> String { "$" + fmtVol(x) }
  private func px(_ x: Double) -> String { fmtPrice(x, decimals: market.info.priceDecimals) }
  private func pct(_ x: Double) -> String { String(format: "%+.2f%%", x) }
  private func time(_ ms: Int64) -> String { fmtTick(ms: Double(ms), step: 60_000, offsetMinutes: 480) }
  private func span(_ a: Int64, _ b: Int64) -> String { time(a) + "–" + time(b) }
  private func duration(_ ms: Int64) -> String {
    if ms < 60_000 { return "<1m" }
    if ms < 3_600_000 { return "\(ms / 60_000)m" }
    return String(format: "%.1fh", Double(ms) / 3_600_000)
  }
  private func source(_ venueID: String, _ exchange: String, _ product: OrderFlowProduct) -> String {
    let raw = venueID.split(separator: ":", maxSplits: 2).last.map(String.init) ?? ""
    return exchange + " · " + product.shortLabel + " · " + raw
  }
  private func locate(_ ms: Int64, price: Double? = nil) {
    Haptics.tap()
    let series = market.series
    let index = series.map { max(0, min($0.count - 1, $0.firstIndex(atOrAfter: ms + 1) - 1)) }
    let barTime = index.flatMap { i in series.flatMap { $0.count > 0 ? $0.time(at: i) : nil } } ?? ms
    model.close(); proxy.placeCrosshair(atTime: barTime, price: price)
  }
  private func evidencePrice(_ price: Double, venueID: String, product: OrderFlowProduct) -> Double? {
    OrderFlowInsightDigest.isPrimary(venueID: venueID, product: product, instrument: instrument) ? price : nil
  }
  private func primarySource(_ minutes: Int) -> OrderFlowInsightsPage.Source? {
    page?.windows.first { $0.minutes == minutes }?.sources.first {
      OrderFlowInsightDigest.isPrimary(venueID: $0.venueID, product: $0.product, instrument: instrument)
    }
  }
  private func covered(_ minutes: Int) -> Bool {
    guard fresh, page?.tracked == true, let coverage = page?.coverageSinceMs else { return false }
    return coverage <= windowEnd - Int64(minutes) * 60_000
  }
  private func reaction(_ minutes: Int) -> OrderFlowInsightDigest.Reaction? {
    guard feed.symbol == market.symbol else { return nil }
    return OrderFlowInsightDigest.reaction(bars: feed.bars, fromMs: windowEnd - Int64(minutes) * 60_000, toMs: windowEnd)
  }
  private func observation(_ minutes: Int) -> OrderFlowInsightDigest.Observation {
    guard let src = primarySource(minutes) else { return .insufficient }
    return OrderFlowInsightDigest.observation(buy: src.buyUsd, sell: src.sellUsd,
                                             reaction: reaction(minutes), covered: covered(minutes))
  }

  private var currentCard: some View {
    card("bigtrade.hero") {
      heading(L.current, primaryName + " · " + L.endedMinutes)
      Text(L.observation(observation(15))).font(TypeScale.title).foregroundStyle(t.ink)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("bigtrade.hero.title")
      if let src = primarySource(15), let r = reaction(15), covered(15), src.total > 0 {
        note(L.minutes(15) + " · " + L.buyShare + " " + String(format: "%.0f%%", src.buyUsd / src.total * 100)
             + " · " + L.minutePrice + " " + pct(r.percent))
      } else if page?.tracked == false {
        note(L.untracked)
      } else if feed.loading {
        note(L.loading)
      } else {
        note(fresh ? L.insufficient : page.map { L.held + " " + time($0.generatedAtMs) } ?? L.noPrimaryFlow)
      }
      if let a = walls.ask, let b = walls.bid {
        note(L.below + " " + px(b.order.price) + "  /  " + L.above + " " + px(a.order.price))
      }
      note(L.candidate)
    }
  }

  private var selectedCard: some View {
    card("insights.selected") {
      heading(L.selectedBar, model.focusT.map { time($0) + " · " + L.aggregateTrades })
      if let summary, summary.windows.bar.has {
        Text(BigTradeSummary.netText(summary.windows.bar.net, signed: true))
          .font(TypeScale.title).foregroundStyle(t.ink).monospacedDigit()
        note(L.buy + " " + money(summary.windows.bar.buyUsd) + " · " + L.sell + " " + money(summary.windows.bar.sellUsd))
      } else { note(L.evidenceEmpty) }
      Button { model.focusCurrent() } label: {
        Text(L.returnCurrent).font(TypeScale.controlOn).foregroundStyle(t.amber)
          .frame(minHeight: Hit.min).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.plain).accessibilityIdentifier("insights.current")
    }
  }

  private var wallCard: some View {
    card("insights.walls") {
      heading(L.keyLevels, primaryName + " · " + L.primaryOnly)
      wallRow(walls.ask, title: L.above, color: t.down)
      divider
      wallRow(walls.bid, title: L.below, color: t.up)
    }
  }
  @ViewBuilder private func wallRow(_ wall: OrderFlowInsightDigest.Wall?, title: String, color: Color) -> some View {
    if let wall {
      Button { locate(nowMs, price: wall.order.price) } label: {
        VStack(alignment: .leading, spacing: Space.s) {
          HStack {
            Text(title).font(TypeScale.control).foregroundStyle(t.ink2)
            Spacer(minLength: Space.s)
            Text(px(wall.order.price)).font(TypeScale.bodyEmph).foregroundStyle(color).monospacedDigit()
              .accessibilityIdentifier(wall.order.side == .ask ? "insights.wall.ask.price" : "insights.wall.bid.price")
            Text(pct(wall.distancePercent)).font(TypeScale.caption).foregroundStyle(t.ink3).monospacedDigit()
          }
          note(L.remaining + " " + money(wall.order.notional) + " · " + L.duration + " " + duration(wall.durationMs))
          note(L.matched + " " + money(wall.order.filledNotional) + " · " + L.locate)
        }
        .frame(maxWidth: .infinity, minHeight: Hit.min, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.plain)
        .accessibilityIdentifier(wall.order.side == .ask ? "insights.wall.ask" : "insights.wall.bid")
    } else {
      VStack(alignment: .leading, spacing: Space.xs) {
        Text(title).font(TypeScale.control).foregroundStyle(t.ink2)
        note(L.noWall)
      }.frame(minHeight: Hit.min, alignment: .leading)
    }
  }

  private var zoneCard: some View {
    card("insights.zones") {
      heading(L.todayZones, L.actualPrices + " · " + L.beijingTime)
      if let page, page.tracked, page.dayStartMs == BigTradeDigest.dayStart8(nowMs) {
        note(coverageText(page))
        let scale = OrderFlowBase.normalize(market.info.base).scale
        let zones = OrderFlowInsightDigest.rankedZones(page, chartScale: scale)
        if zones.isEmpty { note(page.coverageSinceMs == nil ? L.insufficient : L.noExecutions) }
        ForEach(zones) { zone in
          Button { locate(zone.lastMs, price: evidencePrice((zone.low + zone.high) / 2, venueID: zone.venueID, product: zone.product)) } label: {
            VStack(alignment: .leading, spacing: Space.s) {
              HStack(alignment: .firstTextBaseline) {
                Text(px(zone.low) + "–" + px(zone.high)).font(TypeScale.bodyEmph).foregroundStyle(t.ink).monospacedDigit()
                Spacer(minLength: Space.s)
                Text(money(zone.total)).font(TypeScale.bodyEmph).foregroundStyle(t.ink).monospacedDigit()
              }
              note(source(zone.venueID, zone.exchange, zone.product))
              note(L.buy + " " + money(zone.buyUsd) + " · " + L.sell + " " + money(zone.sellUsd))
              note(L.recent + " " + money(zone.recentTotal) + " · " + span(zone.firstMs, zone.lastMs))
            }.frame(maxWidth: .infinity, minHeight: Hit.min, alignment: .leading).contentShape(Rectangle())
          }.buttonStyle(.plain)
          if zone.id != zones.last?.id { divider }
        }
        if !fresh { note(L.held + " " + time(page.generatedAtMs)) }
      } else { note(page?.tracked == false ? L.untracked : (feed.loading ? L.loading : L.unavailable)) }
    }
  }
  private func coverageText(_ page: OrderFlowInsightsPage) -> String {
    guard let coverage = page.coverageSinceMs else { return L.today + " · " + L.partial }
    if coverage <= page.dayStartMs { return L.today + " · " + L.from + " " + time(page.dayStartMs) + " " + L.since }
    // Earlier zones can survive a reconnect; the latest continuous segment is not the entire day's coverage.
    return L.today + " · " + L.partial + " · " + L.from + " " + time(coverage) + " " + L.since
  }

  private var flowCard: some View {
    card("insights.flow") {
      heading(L.flowReaction, L.endedMinutes)
      ForEach([5, 15], id: \.self) { minutes in
        flowWindow(minutes)
        if minutes == 5 { divider }
      }
      if let page, let cutoff = page.bigUsd { note(L.minimumTrade + " ≥" + money(cutoff)) }
      participantRows
    }
  }
  @ViewBuilder private func flowWindow(_ minutes: Int) -> some View {
    VStack(alignment: .leading, spacing: Space.s) {
      heading(L.minutes(minutes), primaryName)
      if let src = primarySource(minutes) {
        note(L.buy + " " + money(src.buyUsd) + " · " + L.sell + " " + money(src.sellUsd))
        Text(L.observation(observation(minutes))).font(TypeScale.control).foregroundStyle(t.ink2)
          .fixedSize(horizontal: false, vertical: true)
        if let r = reaction(minutes) { note(span(r.fromMs, r.toMs) + " · " + L.minutePrice + " " + pct(r.percent)) }
        else { note(L.priceMissing) }
        if !covered(minutes) { note(L.insufficient) }
      } else { note(page?.tracked == false ? L.untracked : L.noPrimaryFlow) }
    }
  }
  @ViewBuilder private var participantRows: some View {
    if covered(15), let window = page?.windows.first(where: { $0.minutes == 15 }), !window.sources.isEmpty {
      divider
      note(L.observedSources)
      ForEach([true, false], id: \.self) { spot in
        let sources = window.sources.filter { ($0.product == .spot) == spot }
        if !sources.isEmpty {
          let buy = sources.reduce(0) { $0 + $1.buyUsd }
          let sell = sources.reduce(0) { $0 + $1.sellUsd }
          Text(spot ? L.observedSpot : L.observedContract).font(TypeScale.control).foregroundStyle(t.ink2)
          note(L.buy + " " + money(buy) + " · " + L.sell + " " + money(sell))
          note(BigTradeSummary.netText(buy - sell, signed: true))
        }
      }
      DisclosureGroup {
        VStack(alignment: .leading, spacing: Space.s) {
          ForEach(window.sources.indices, id: \.self) { i in
            let src = window.sources[i]
            note(source(src.venueID, src.exchange, src.product))
            note(L.buy + " " + money(src.buyUsd) + " · " + L.sell + " " + money(src.sellUsd))
          }
        }.padding(.top, Space.s)
      } label: { Text(L.minutes(15) + " · " + L.observedSources).font(TypeScale.control).foregroundStyle(t.ink2) }
      .tint(t.amber).frame(minHeight: Hit.min)
    }
  }

  private var liquidationCard: some View {
    card("bigtrade.liq") {
      heading(L.liquidation, L.aggregate)
      if let book = link.liquidationBook(symbol: market.symbol), book.tracked == true,
         let updated = link.liquidations.updatedAtMs {
        let end = fresh ? windowEnd : ((nowMs - 3_000) / 60_000) * 60_000
        ForEach([5, 15], id: \.self) { minutes in
          let sum = book.sum(end - Int64(minutes) * 60_000, end)
          VStack(alignment: .leading, spacing: Space.s) {
            heading(L.minutes(minutes))
            note(L.longLiquidated + " " + money(sum.longUsd) + " · " + L.shortLiquidated + " " + money(sum.shortUsd))
            if sum.total == 0 { note(L.noLiquidation) }
          }
          if minutes == 5 { divider }
        }
        divider
        liquidationReaction(book, end: end, updated: updated)
        if link.liquidations.unavailable || nowMs - updated > 90_000 { note(L.held + " " + time(updated)) }
      } else { note(L.noLiquidationData) }
      note(L.liquidationSampling)
    }
  }
  @ViewBuilder private func liquidationReaction(_ book: LiquidationBook, end: Int64, updated: Int64) -> some View {
    let rows = book.rows.values.filter { $0.minuteMs >= end - 15 * 60_000 && $0.minuteMs < end }
    let peak = rows.filter { $0.longUsd + $0.shortUsd > 0 }.max { $0.longUsd + $0.shortUsd < $1.longUsd + $1.shortUsd }
    if let peak {
      note(time(peak.minuteMs) + " · " + L.longLiquidated + " " + money(peak.longUsd) + " · " + L.shortLiquidated + " " + money(peak.shortUsd))
      if feed.symbol == market.symbol, !link.liquidations.unavailable, nowMs - updated <= 90_000,
         let r = OrderFlowInsightDigest.reaction(bars: feed.bars, fromMs: peak.minuteMs + 60_000, toMs: end) {
        Text(L.afterLiquidation(r.percent, long: peak.longUsd >= peak.shortUsd))
          .font(TypeScale.control).foregroundStyle(t.ink2).fixedSize(horizontal: false, vertical: true)
        note(primaryName + " · " + span(r.fromMs, r.toMs) + " · " + pct(r.percent))
      } else { note(L.noPriceAfter) }
    } else { note(L.noLiquidationAfter) }
  }

  private var eventsCard: some View {
    card("insights.events") {
      heading(L.changes, L.lastHour)
      let events = OrderFlowInsightDigest.recentEvents(snapshot?.orders ?? [], nowMs: nowMs)
      if events.isEmpty { note(L.noChanges) }
      ForEach(events) { order in
        Button { locate(order.endMs ?? order.firstSeenMs, price: evidencePrice(order.price, venueID: order.venueID, product: order.product)) } label: {
          VStack(alignment: .leading, spacing: Space.s) {
            HStack {
              Text(eventTitle(order)).font(TypeScale.control).foregroundStyle(t.ink2)
              Spacer(minLength: Space.s)
              Text(time(order.endMs ?? order.firstSeenMs)).font(TypeScale.caption).foregroundStyle(t.ink3)
            }
            note(px(order.price) + " · " + source(order.venueID, order.exchange, order.product))
            note(L.initialSize + " " + money(order.initialNotional) + " · " + L.matched + " " + money(order.filledNotional))
          }.frame(maxWidth: .infinity, minHeight: Hit.min, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
        if order.id != events.last?.id { divider }
      }
    }
  }
  private func eventTitle(_ order: BigOrder) -> String {
    switch order.status { case .live: L.live; case .filled: L.filled; case .cancelled: L.cancelled; case .lost: L.lost }
  }

  private var evidenceCard: some View {
    card("insights.evidence") {
      DisclosureGroup {
        VStack(alignment: .leading, spacing: Space.m) { note(L.evidenceRule); note(L.wallRule); note(L.zoneRule); note(L.thresholdNote); note(L.timeRule) }
          .padding(.top, Space.s)
      } label: { Text(L.evidence).font(TypeScale.controlOn).foregroundStyle(t.ink2) }
        .tint(t.amber).frame(minHeight: Hit.min)
    }
  }
}

struct OrderFlowInsightEntryStrip: View {
  let open: () -> Void
  @Environment(\.panelTheme) private var t
  var body: some View {
    HStack(spacing: Space.s) {
      Image(systemName: "chevron.up").font(TypeScale.captionEmph)
      Text(L.title).font(TypeScale.controlOn)
      Spacer(minLength: Space.s)
      Text(L.entryHint).font(TypeScale.caption).foregroundStyle(t.ink3).lineLimit(1)
    }
    .foregroundStyle(t.ink2).padding(.horizontal, Space.l)
    .frame(minHeight: Hit.min).contentShape(Rectangle())
    .gesture(TapGesture().exclusively(before: DragGesture(minimumDistance: 20)).onEnded { value in
      switch value {
      case .first: open()
      case .second(let drag):
        if drag.translation.height < -48, abs(drag.translation.height) > abs(drag.translation.width) * 1.8 { open() }
      }
    })
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { open() }
    .accessibilityIdentifier("insights.entry")
    .accessibilityHint(L.entryHint)
  }
}
