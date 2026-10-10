import KanpanCore
import SwiftUI

// MARK: - 挂到主界面

extension View {
  /// 「盘口要点」半页：系统 sheet，一档高度 = 屏高 − 行情头下沿（价格与涨跌一直露着、照常跳），
  /// 头部那一截照常可点（点它收起半页由宿主接）。`enabled == false`（横屏、复盘、画线、不在行情页）时收掉。
  func highlightsSheet(model: HighlightsModel, market: MarketModel, proxy: ChartProxy, theme: PanelTheme,
                       scheme: ColorScheme?, zone: TZOffset, enabled: Bool) -> some View {
    modifier(HighlightsSheetModifier(model: model, market: market, proxy: proxy, theme: theme, scheme: scheme,
                                     zone: zone, enabled: enabled))
  }
}

private struct HighlightsSheetModifier: ViewModifier {
  let model: HighlightsModel
  let market: MarketModel
  let proxy: ChartProxy
  let theme: PanelTheme
  let scheme: ColorScheme?
  let zone: TZOffset
  let enabled: Bool

  func body(content: Content) -> some View {
    let shown = enabled && model.open
    let detent = PresentationDetent.height(max(320, model.sheetHeight))
    content
      .sheet(isPresented: Binding(get: { shown }, set: { if !$0 { model.open = false } })) {
        HighlightsSheet(model: model, market: market, proxy: proxy, zone: zone)
          .environment(\.panelTheme, theme)
          .presentationDetents([detent])
          .presentationDragIndicator(.visible)
          .presentationCornerRadius(28)
          .presentationBackgroundInteraction(.enabled(upThrough: detent))
          .presentationContentInteraction(.scrolls)
          .presentationBackground { LiuliBackdrop(material: LiuliMaterial(theme), lobes: true) }
          .preferredColorScheme(scheme)
      }
      .onChange(of: enabled) { _, on in if !on { model.open = false } }
  }
}

// MARK: - 半页

/// 「盘口要点」四块，固定顺序：① 流向（永远在）② 关键价位 ③ 持仓 · 费率 · 现货溢价 ④ 近 4 小时。
/// 没内容的块整块不出；没跟踪的品种写「打开后开始观察」。
struct HighlightsSheet: View {
  let model: HighlightsModel
  let market: MarketModel
  let proxy: ChartProxy
  let zone: TZOffset
  @Environment(\.panelTheme) private var t
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var m: LiuliMaterial { LiuliMaterial(t) }

  var body: some View {
    VStack(spacing: 0) {
      head
      content
    }
    .onGeometryChange(for: CGFloat.self) { g in g.frame(in: .global).minY } action: { model.noteSheetTop($0) }
    .accessibilityIdentifier("highlights.sheet")
  }

  // MARK: 头

  private var head: some View {
    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
      Text(HighlightTerm.title.text).font(TypeScale.title).foregroundStyle(t.ink)
      Spacer(minLength: Space.s)
      if let page = model.page, page.tracked {
        if let stopped = model.stoppedAtMs {
          Text(HighlightTerm.staleSince.fill(["t": HighlightsText.clock(stopped, zone: zone)]))
            .font(TypeScale.caption).foregroundStyle(t.ink3)
            .accessibilityIdentifier("highlights.stale")
        } else {
          HStack(spacing: Space.xs) {
            Circle().fill(t.up).frame(width: 6, height: 6)
            Text(HighlightsText.clock(page.generatedAtMs, zone: zone))
              .font(TypeScale.caption).monospacedDigit().foregroundStyle(t.ink3)
              .contentTransition(.numericText())
          }
        }
      }
    }
    .padding(.horizontal, Space.xl)
    .padding(.top, Space.xl + Space.xs)
    .padding(.bottom, Space.m)
  }

  // MARK: 内容

  @ViewBuilder private var content: some View {
    if let page = model.page {
      if !page.tracked {
        calm(icon: "dot.radiowaves.left.and.right", text: HighlightTerm.untracked.text, id: "highlights.untracked")
      } else {
        blocks(page)
      }
    } else if model.failed {
      calm(icon: "wifi.slash", text: HighlightTerm.offline.text, id: "highlights.offline")
    } else {
      skeleton
    }
  }

  private func blocks(_ page: HighlightsPage) -> some View {
    ScrollViewReader { reader in
      ScrollView {
        let quiet = page.quietState(nowMs: Int64(Date().timeIntervalSince1970 * 1000))
        VStack(spacing: Space.s) {
          HighlightsFlowBlock(page: page)
          // 刚开盯、价位与事件还没攒出来：紧跟在流向下面说一句「观察中」，不说「平静」。
          if case .observing(let n) = quiet { quietLine(HighlightTerm.observing.fill(["n": "\(n)"]), id: "highlights.observing") }
          if !page.levels.isEmpty || page.range != nil {
            HighlightsLevelsBlock(model: model, market: market, page: page, zone: zone, onBack: back(level:))
          }
          if let position = page.position, position.show {
            HighlightsPositionBlock(position: position)
          }
          if !page.events.isEmpty {
            HighlightsEventsBlock(page: page, model: model, zone: zone, onBack: back(event:))
          }
          if quiet == .calm { quietLine(HighlightTerm.quiet.text, id: "highlights.quiet") }
        }
        .padding(.horizontal, Space.m)
        .padding(.bottom, Space.xxl)
        .grayscale(model.stale ? 1 : 0)
        .opacity(model.stale ? 0.62 : 1)
      }
      .scrollIndicators(.hidden)
      .onChange(of: model.scrollTarget, initial: true) { _, id in
        guard let id else { return }
        // 不给锚点 = 只挪到刚好露出来：已经在眼前就不动，免得把第一块「流向」的标题推到头底下。
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { reader.scrollTo(id) }
        model.consumedScroll()
      }
    }
  }

  private func quietLine(_ text: String, id: String) -> some View {
    Text(text).font(TypeScale.caption).foregroundStyle(t.ink3)
      .frame(maxWidth: .infinity).padding(.vertical, Space.l)
      .accessibilityIdentifier(id)
  }

  private func calm(icon: String, text: String, id: String) -> some View {
    VStack(spacing: Space.s) {
      Image(systemName: icon).font(.system(size: ControlMetrics.emptyGlyph * 0.7, weight: .regular)).foregroundStyle(t.ink3)
      Text(text).font(TypeScale.footnoteEmph).foregroundStyle(t.ink2)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, Space.section)
    .frame(maxHeight: .infinity, alignment: .top)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(id)
  }

  private var skeleton: some View {
    VStack(spacing: Space.s) {
      SkeletonBlock(height: 148, fill: m.well, radius: Radius.l)
      SkeletonBlock(height: 210, fill: m.well, radius: Radius.l)
    }
    .skeletonPulse()
    .padding(.horizontal, Space.m)
    .frame(maxHeight: .infinity, alignment: .top)
  }

  // MARK: 回图

  /// 回图：收起半页，带子留在图上；价位不在当前价格范围里时把图挪过去（十字线落在最近一次触及上）。
  private func back(level: HighlightLevel) {
    Haptics.step()
    if model.band?.sourceID != level.id { model.toggle(level: level) }
    let mid = (level.low + level.high) / 2 * model.scale
    if let range = proxy.box?.chart.chartPriceRange, mid >= range.lo, mid <= range.hi {
      // 已经在眼前：只收半页。
    } else if let t = level.touchMs.compactMap({ $0 }).last ?? proxy.box?.chart.state?.series.lastTime {
      proxy.placeCrosshair(atTime: t, price: mid)
    }
    model.open = false
  }

  private func back(event: HighlightEvent) {
    Haptics.step()
    model.show(event: event)
    if let t = event.startMs {
      let price = (event.price ?? event.low).map { $0 * model.scale }
      proxy.placeCrosshair(atTime: t, price: price)
    }
    model.open = false
  }
}

// MARK: - 块的外壳

/// 一块：圆角 16 的琉璃卡，标题 13 semibold `ink2` + 右边一行小字。
struct HighlightsBlock<Trailing: View, Content: View>: View {
  let title: String
  @ViewBuilder var trailing: Trailing
  @ViewBuilder var content: Content
  @Environment(\.panelTheme) private var t

  var body: some View {
    VStack(alignment: .leading, spacing: Space.s) {
      HStack(alignment: .firstTextBaseline, spacing: Space.s) {
        Text(title).font(TypeScale.controlOn).foregroundStyle(t.ink2)
        Spacer(minLength: Space.s)
        trailing
      }
      content
    }
    .padding(EdgeInsets(top: 11, leading: 14, bottom: 12, trailing: 14))
    .frame(maxWidth: .infinity, alignment: .leading)
    .liuliCard(radius: Radius.l)
  }
}
