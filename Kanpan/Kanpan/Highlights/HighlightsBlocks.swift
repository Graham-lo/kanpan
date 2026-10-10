import KanpanCore
import SwiftUI

// 半页四块（原型 §9–§11 尺寸令牌）。只摆事实：数、方向色、分位，不打分、不写多空。

typealias HT = HighlightTerm

// MARK: - ① 流向

struct HighlightsFlowBlock: View {
  let page: HighlightsPage
  @Environment(\.panelTheme) private var t

  private var rows: [FlowRow] { page.flow?.rows ?? [] }

  var body: some View {
    HighlightsBlock(title: HT.flow.text) {
      Text(HT.flowCaption.text).font(TypeScale.caption2).foregroundStyle(t.ink3).lineLimit(1)
    } content: {
      let peak = rows.compactMap { $0.netUsd.map(abs) }.max() ?? 0
      Grid(alignment: .leading, horizontalSpacing: Space.s, verticalSpacing: 0) {
        GridRow {
          Text(verbatim: "")
          Text(HT.netTaker.text)
          Text(HT.price.text).gridColumnAlignment(.trailing)
          Text(HT.oi.text).gridColumnAlignment(.trailing)
        }
        .font(TypeScale.caption2).foregroundStyle(t.ink3)
        .frame(height: 20)
        ForEach(rows) { row in
          GridRow {
            name(row)
            net(row, peak: peak)
            Text(HighlightsText.flowPct(row.pxPct)).frame(minWidth: 50, alignment: .trailing)
            Text(HighlightsText.flowPct(row.oiPct)).frame(minWidth: 50, alignment: .trailing)
          }
          .font(TypeScale.caption).monospacedDigit().foregroundStyle(t.ink2)
          .frame(height: 26)
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("highlights.flow.\(row.w.rawValue)")
        }
      }
    }
  }

  private func name(_ row: FlowRow) -> some View {
    let long = HighlightsText.isLongRow(row)
    return HStack(spacing: Space.xs) {
      Text(HighlightsText.windowName(row, nowMs: page.generatedAtMs))
        .fontWeight(long ? .semibold : .regular)
        .foregroundStyle(long ? t.ink : t.ink2)
      if row.diverge {
        Text(HT.diverge.text).font(TypeScale.caption2Emph).foregroundStyle(Color(hex: t.seed.amber))
          .padding(.horizontal, Space.xs).padding(.vertical, 1)
          .background(Color(hex: t.seed.amber).opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
      }
    }
    .lineLimit(1).fixedSize()
  }

  private func net(_ row: FlowRow, peak: Double) -> some View {
    HStack(spacing: Space.s) {
      DivergingBar(value: row.netUsd, peak: peak).frame(height: 8)
      Text(HighlightsText.flowNet(row))
        .fontWeight(row.netUsd == nil ? .regular : .semibold)
        .foregroundStyle(row.netUsd.map { $0 >= 0 ? t.up : t.down } ?? t.ink3)
        .frame(minWidth: 44, alignment: .trailing)
        .contentTransition(.numericText())
    }
    .frame(maxWidth: .infinity)
  }
}

/// 以零为中线、向左右分叉的一根条。没有数时只画底槽与中线。
private struct DivergingBar: View {
  let value: Double?
  let peak: Double
  @Environment(\.panelTheme) private var t

  var body: some View {
    GeometryReader { g in
      let half = g.size.width / 2
      let m = LiuliMaterial(t)
      ZStack(alignment: .leading) {
        Capsule().fill(m.well)
        Rectangle().fill(t.ink3.opacity(0.4)).frame(width: 1).offset(x: half - 0.5)
        if let v = value, peak > 0, v != 0 {
          let w = max(2, half * min(1, abs(v) / peak))
          Capsule().fill(v >= 0 ? t.up : t.down)
            .frame(width: w)
            .offset(x: v >= 0 ? half : half - w)
        }
      }
    }
  }
}

// MARK: - ② 关键价位

struct HighlightsLevelsBlock: View {
  let model: HighlightsModel
  let market: MarketModel
  let page: HighlightsPage
  let zone: TZOffset
  let onBack: (HighlightLevel) -> Void
  @Environment(\.panelTheme) private var t
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    // 现价按每枚币（价位都是每枚币的）。价区包住现价的那几条紧贴现价线下面。
    let price = market.ticker.map { $0.last / max(model.scale, 1e-12) }
    let above = Array(page.above(price: price).reversed()), inside = page.atPrice(price), below = page.below(price: price)
    let shown = above + inside + below
    let peak = shown.map { $0.wallUsd + $0.fillUsd + $0.liqUsd }.max() ?? 0
    HighlightsBlock(title: HT.levels.text) {
      legend
    } content: {
      VStack(spacing: 0) {
        if let r = page.range { rangeRow(r).padding(.bottom, Space.xs) }
        ForEach(above) { row($0, peak: peak) }
        nowDivider
        ForEach(inside) { row($0, peak: peak) }
        ForEach(below) { row($0, peak: peak) }
      }
    }
  }

  private var legend: some View {
    HStack(spacing: Space.s) {
      swatch(.solid); Text(HT.wall.text)
      swatch(.soft); Text(HT.fill.text)
      swatch(.hatch); Text(HT.liq.text)
    }
    .font(TypeScale.caption2).foregroundStyle(t.ink3)
  }

  private func swatch(_ kind: LevelBarSegment.Kind) -> some View {
    LevelBarSegment(kind: kind, color: t.ink3).frame(width: 8, height: 8).clipShape(RoundedRectangle(cornerRadius: 2))
  }

  private func rangeRow(_ r: HighlightRange) -> some View {
    let line = HighlightsText.rangeLine(r, nowMs: page.generatedAtMs, decimals: model.decimals, scale: model.scale)
    let last = market.ticker?.last ?? 0
    let pos = HighlightsText.rangePosition(r, price: last / max(model.scale, 1e-12))
    return VStack(alignment: .leading, spacing: Space.xs) {
      HStack(spacing: Space.s) {
        highlightText(line.runs, strong: t.ink).font(TypeScale.caption2).foregroundStyle(t.ink2)
          .monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
        Spacer(minLength: Space.s)
        GeometryReader { g in
          ZStack(alignment: .leading) {
            Capsule().fill(t.ink3.opacity(0.25)).frame(height: 4)
            Circle().fill(t.amber).frame(width: 10, height: 10).offset(x: (g.size.width - 10) * pos)
          }
          .frame(maxHeight: .infinity)
        }
        .frame(width: 56, height: 10)
      }
      Text(line.edges).font(TypeScale.caption2).foregroundStyle(t.ink3).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.8)
    }
    .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
    .background(LiuliMaterial(t).well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("highlights.range")
  }

  private var nowDivider: some View {
    let last = market.ticker?.last
    return HStack(spacing: Space.s) {
      dashed
      if let last, last > 0 {
        Text(HT.now.fill(["p": AlertMessage.groupedPrice(last, decimals: model.decimals)]))
          .font(TypeScale.caption2).monospacedDigit().foregroundStyle(t.ink3)
          .contentTransition(.numericText(value: last))
      }
      dashed
    }
    .frame(height: 20)
  }

  private var dashed: some View {
    Line().stroke(t.ink3.opacity(0.5), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).frame(height: 1)
  }

  private func row(_ l: HighlightLevel, peak: Double) -> some View {
    let open = model.expanded == l.id
    let side = l.side == .bid ? t.up : t.down
    let meta = HighlightsText.levelMeta(l)
    return VStack(spacing: 0) {
      // 价区 · 叠条 · 墙/吃单；有爆仓时在右侧补一行。
      VStack(spacing: 2) {
        HStack(spacing: Space.s) {
          Text(HighlightsText.band(low: l.low * model.scale, high: l.high * model.scale, decimals: model.decimals))
            .font(TypeScale.controlOn).monospacedDigit().foregroundStyle(t.ink)
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(width: 112, alignment: .leading)
          LevelBar(level: l, peak: peak, color: side).frame(height: 10)
          highlightText(meta.top, strong: t.ink).foregroundStyle(t.ink2)
            .font(TypeScale.caption2).monospacedDigit().lineLimit(1).fixedSize()
        }
        if !meta.bottom.isEmpty {
          Text(meta.bottom).foregroundStyle(t.ink3)
            .font(TypeScale.caption2).monospacedDigit().lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
      }
      .padding(.vertical, 3)
      .frame(minHeight: 38)
      .contentShape(Rectangle())
      .onTapGesture {
        Haptics.step()
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.35, dampingFraction: 0.85)) { model.toggle(level: l) }
      }
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isButton)
      .accessibilityIdentifier("highlights.level.\(l.id)")
      if open { evidence(l) }
    }
    .padding(.horizontal, open ? Space.s : 0)
    .background {
      if open {
        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.amber.opacity(0.08))
          .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(t.amber, lineWidth: 1))
      }
    }
    .id(l.id)
  }

  private func evidence(_ l: HighlightLevel) -> some View {
    VStack(alignment: .leading, spacing: Space.xs) {
      Grid(alignment: .leading, horizontalSpacing: Space.s, verticalSpacing: Space.xs) {
        ForEach(Array(HighlightsText.evidence(l, zone: zone).enumerated()), id: \.offset) { _, e in
          GridRow {
            Text(e.label).foregroundStyle(t.ink3).frame(minWidth: 30, alignment: .leading)
            highlightText(e.runs, strong: t.ink).foregroundStyle(t.ink2).lineLimit(1).minimumScaleFactor(0.85)
          }
        }
      }
      .font(TypeScale.caption).monospacedDigit()
      Button { onBack(l) } label: {
        Label(HT.back.text, systemImage: "scope").font(TypeScale.captionEmph).foregroundStyle(t.amber)
          .frame(minHeight: 32)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("highlights.back")
    }
    .padding(.bottom, Space.s)
    .frame(maxWidth: .infinity, alignment: .leading)
    .transition(.opacity.combined(with: .move(edge: .top)))
  }
}

private struct Line: Shape {
  func path(in rect: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: 0, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) } }
}

/// 价位那根叠条：墙（实）+ 吃单（淡）+ 爆仓（斜纹），按这一块里最长那条的总量缩放。
private struct LevelBar: View {
  let level: HighlightLevel
  let peak: Double
  let color: Color

  var body: some View {
    GeometryReader { g in
      let parts: [(Double, LevelBarSegment.Kind)] = [(level.wallUsd, .solid), (level.fillUsd, .soft), (level.liqUsd, .hatch)]
        .filter { $0.0 > 0 }
      let gaps = CGFloat(max(0, parts.count - 1)) * 1.5
      let usable = max(0, g.size.width - gaps)
      HStack(spacing: 1.5) {
        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
          LevelBarSegment(kind: part.1, color: color)
            .frame(width: peak > 0 ? max(2, usable * CGFloat(part.0 / peak)) : 0)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
  }
}

struct LevelBarSegment: View {
  enum Kind { case solid, soft, hatch }
  let kind: Kind
  let color: Color

  var body: some View {
    switch kind {
    case .solid: Rectangle().fill(color)
    case .soft: Rectangle().fill(color.opacity(0.5))
    case .hatch:
      Canvas { ctx, size in
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(0.18)))
        var p = Path()
        var x: CGFloat = -size.height
        while x < size.width { p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0)); x += 3 }
        ctx.stroke(p, with: .color(color), lineWidth: 1)
      }
    }
  }
}

// MARK: - ③ 持仓 · 费率 · 现货溢价

struct HighlightsPositionBlock: View {
  let position: HighlightPosition
  @Environment(\.panelTheme) private var t

  var body: some View {
    HighlightsBlock(title: HT.position.text) {
      Text(HT.positionCaption.text).font(TypeScale.caption2).foregroundStyle(t.ink3).lineLimit(1).minimumScaleFactor(0.8)
    } content: {
      HStack(spacing: Space.s) {
        ForEach(Array(HighlightsText.tiles(position).enumerated()), id: \.offset) { _, tile in cell(tile) }
      }
    }
    .accessibilityIdentifier("highlights.position")
  }

  private func cell(_ tile: HighlightsText.Tile) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(tile.label).font(TypeScale.caption2).foregroundStyle(t.ink3).lineLimit(1)
      Text(tile.value).font(TypeScale.bodyEmph).monospacedDigit().foregroundStyle(t.ink)
        .lineLimit(1).minimumScaleFactor(0.75).contentTransition(.numericText())
      Text(tile.fact.isEmpty ? " " : tile.fact).font(TypeScale.caption2).foregroundStyle(t.ink2).lineLimit(1).minimumScaleFactor(0.8)
      PercentileTrack(pctile: tile.pctile).frame(height: 8).padding(.top, 2)
    }
    .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(LiuliMaterial(t).well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}

/// 30 天分位轨道：两头 10% 刷琥珀，点落在这一刻的分位上。
private struct PercentileTrack: View {
  let pctile: Int?
  @Environment(\.panelTheme) private var t

  var body: some View {
    GeometryReader { g in
      let w = g.size.width
      let amber = Color(hex: t.seed.amber).opacity(0.45)
      ZStack(alignment: .leading) {
        Capsule().fill(t.ink3.opacity(0.2)).frame(height: 3)
        Capsule().fill(amber).frame(width: w * 0.1, height: 3)
        Capsule().fill(amber).frame(width: w * 0.1, height: 3).offset(x: w * 0.9)
        if let p = pctile {
          Circle().fill(t.amber).frame(width: 8, height: 8).offset(x: (w - 8) * CGFloat(min(100, max(0, p))) / 100)
        }
      }
      .frame(maxHeight: .infinity)
    }
  }
}

// MARK: - ④ 近 4 小时

struct HighlightsEventsBlock: View {
  let page: HighlightsPage
  let model: HighlightsModel
  let zone: TZOffset
  let onBack: (HighlightEvent) -> Void
  @Environment(\.panelTheme) private var t

  var body: some View {
    HighlightsBlock(title: HT.events.text) {
      Text(HT.eventsCaption.text).font(TypeScale.caption2).foregroundStyle(t.ink3)
    } content: {
      VStack(spacing: 0) {
        // 服务端同一分钟可能报两条同 id 的事（如两侧同时破位），行身份带上序号免得撞。
        ForEach(Array(page.events.prefix(4).enumerated()), id: \.offset) { i, e in
          if i > 0 { Rectangle().fill(LiuliMaterial(t).rule).frame(height: 0.5) }
          row(e)
        }
      }
    }
  }

  private func row(_ e: HighlightEvent) -> some View {
    Button { onBack(e) } label: {
      HStack(spacing: Space.s) {
        Text(HighlightsText.eventTime(e, zone: zone)).font(TypeScale.caption2).monospacedDigit().foregroundStyle(t.ink3)
          .frame(minWidth: 60, alignment: .leading)
        Image(systemName: Self.glyph(e.t)).font(TypeScale.caption2).foregroundStyle(t.ink3).frame(width: 14)
        highlightText(HighlightsText.eventSentence(e, decimals: model.decimals, scale: model.scale), strong: t.ink)
          .font(TypeScale.caption).monospacedDigit().foregroundStyle(t.ink2)
          .lineLimit(1).minimumScaleFactor(0.8)
        Spacer(minLength: Space.xs)
        Image(systemName: "scope").font(TypeScale.caption2).foregroundStyle(t.amber)
      }
      .frame(minHeight: 30)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .id(e.id)
    .accessibilityIdentifier("highlights.event.\(e.id)")
  }

  static func glyph(_ kind: HighlightEvent.Kind) -> String {
    switch kind {
    case .wallEaten, .wallCancel, .levelBroken: "rectangle.split.1x2"
    case .liqWave: "bolt"
    case .flowBurst: "arrow.left.arrow.right"
    case .oiJump: "chart.bar"
    }
  }
}
