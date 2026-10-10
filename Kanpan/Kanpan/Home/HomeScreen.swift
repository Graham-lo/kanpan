import KanpanCore
import KanpanNetwork
import SwiftUI

/// 首页（底栏最左一格，PROJECT.md §79）：「异动 · 涨跌 · 持仓 · 板块」四段，顶上一排胶囊（照自选页分类条）。
/// 「板块」就是原底栏「板块分类」那一整页（`SectorPage`，宿主传进来），下钻进品种列表时顶上这排胶囊收起。
///
/// - 异动：自选（登录后带上）∪ 服务端热点层里此刻值得看一眼的品种，每只一行、按服务端权重排，打开时定序。
///   点一行 → 去行情页、换到这只、自动升起「盘口要点」半页并展开那一条、图上画带子。
/// - 涨跌：涨幅榜 / 跌幅榜；持仓：增仓榜 / 减仓榜。各 6 行，「全部」展开；两段各有自己的
///   1 时 / 4 时 / 24 时小胶囊（只记本机）。点一行只开图，不自动升半页。波动行同样只开图。
struct HomeScreen: View {
  let model: HomeModel
  let catalog: OrderFlowCatalog
  let favorites: [String]
  let signedIn: Bool
  let zone: TZOffset
  let bottomInset: CGFloat
  let isFavorite: (String) -> Bool
  let onStar: (String) -> Void
  let onOpenMove: (HighlightsBoard.Row) -> Void
  let onOpenBoard: (String) -> Void
  /// 「板块」段的整页（宿主拼好的 `SectorPage`）。
  let sectors: AnyView
  /// 板块段已下钻进某个板块的品种列表：顶上的胶囊让给那一层自己的返回行。
  let drilled: Bool

  @Environment(\.panelTheme) private var t

  /// 访客不带自选（和手机网页一致：自选要登录后才进扫描）。
  private var bases: [String] { signedIn ? HomeModel.favoriteBases(favorites) : [] }

  var body: some View {
    let bases = self.bases
    VStack(spacing: 0) {
      if !(model.segment == .sectors && drilled) { header }
      switch model.segment {
      case .moves: HomeMovesView(model: model, bases: bases, signedIn: signedIn, zone: zone, bottomInset: bottomInset,
                                 isFavorite: isFavorite, onStar: onStar, onOpen: open(row:),
                                 reload: { await model.load(bases: bases, reorder: true) { await catalog.highlightsBoard(bases: $0) } })
      case .change, .oi:
        let segment = model.segment
        HomeBoardView(model: model, segment: segment, bottomInset: bottomInset, onOpen: onOpenBoard,
                      reload: { await model.loadBoards(segment: segment) { await catalog.marketBoard(kind: $0, window: $1) } })
      case .sectors: sectors
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background { LiuliBackdrop(material: LiuliMaterial(t)) }
    .tint(t.amber)
    .task(id: "\(model.segment.rawValue)|\(bases.joined(separator: ","))|\(model.window(for: model.segment).rawValue)") {
      let segment = model.segment
      switch segment {
      case .moves: await model.pollMoves(bases: bases) { await catalog.highlightsBoard(bases: $0) }
      case .change, .oi: await model.pollBoards(segment: segment) { await catalog.marketBoard(kind: $0, window: $1) }
      case .sectors: break  // 板块页自己在出现 / 消失时开关行情轮询
      }
    }
  }

  /// 异动行：盘口 / 持仓 / 费率开图并升半页展开那条；波动行只开图。
  private func open(row: HighlightsBoard.Row) {
    if HomeModel.opensSheet(row) { onOpenMove(row) } else { onOpenBoard(row.base) }
  }

  static func segmentName(_ s: HomeModel.Segment) -> String {
    switch s {
    case .moves: HighlightTerm.moves.text
    case .change: HighlightTerm.segChange.text
    case .oi: HighlightTerm.segOi.text
    case .sectors: HighlightTerm.segSectors.text
    }
  }

  /// 顶上一排胶囊（照自选页分类条：选中 = 釉面强调色胶囊，没选 = 透明 + 0.5 描边），靠左一行。
  private var header: some View {
    HStack(spacing: Space.s) {
      ForEach(HomeModel.Segment.allCases, id: \.self) { seg in
        HomeCapsule(title: Self.segmentName(seg), on: model.segment == seg, size: .regular, id: "home.segment.\(seg.rawValue)") {
          guard seg != model.segment else { return }
          Haptics.tap()
          model.segment = seg
        }
      }
      Spacer(minLength: 0)
    }
    .pageHorizontalInset()
    .padding(.top, Space.xs)
  }
}

/// 首页的胶囊：段（高 30、13 号）与窗口（高 24、11 号）两档。
/// 选中 = 强调色渐变 + 顶上一线高光 + 同色投影，字走 `badgeInk`；没选 = 透明底 + 0.5 描边。
struct HomeCapsule: View {
  enum Size { case regular, small }
  let title: String
  let on: Bool
  let size: Size
  let id: String
  let action: () -> Void
  @Environment(\.panelTheme) private var t

  /// 小胶囊走字阶下限 11 medium（字阶里没有 11.5，也没有 11 semibold，选中只靠底色区分）。
  private static let small = TypeScale.caption2Emph
  private static let smallOn = TypeScale.caption2Emph

  var body: some View {
    let m = LiuliMaterial(t)
    let regular = size == .regular
    Button(action: action) {
      ZStack {
        // 选中换 semibold 会宽一点：底下垫一份看不见的 semibold，选中与否一样宽，切换不抖。
        Text(title).font(regular ? TypeScale.controlOn : Self.smallOn).hidden()
        Text(title).font(regular ? (on ? TypeScale.controlOn : TypeScale.control) : (on ? Self.smallOn : Self.small))
          .foregroundStyle(on ? t.badgeInk : t.ink2)
      }
      .lineLimit(1)
      .fixedSize()
      .padding(.horizontal, regular ? Space.l : Space.s + 1)
      .frame(height: regular ? 30 : 24)
      .background {
        if on {
          Capsule().fill(m.accentGradient)
            .overlay(alignment: .top) { m.topHighlight(inset: Space.s) }
            .shadow(color: m.accent.opacity(m.dark ? 0.5 : 0.35), radius: regular ? 6 : 4, x: 0, y: regular ? 3 : 2)
        } else {
          Capsule().strokeBorder(t.ink3.opacity(m.dark ? 0.4 : 0.32), lineWidth: 0.5)
        }
      }
      .frame(minHeight: Hit.min)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(on ? .isSelected : [])
    .accessibilityIdentifier(id)
  }
}

// MARK: - 异动

private struct HomeMovesView: View {
  let model: HomeModel
  let bases: [String]
  let signedIn: Bool
  let zone: TZOffset
  let bottomInset: CGFloat
  let isFavorite: (String) -> Bool
  let onStar: (String) -> Void
  let onOpen: (HighlightsBoard.Row) -> Void
  let reload: () async -> Void
  @Environment(\.panelTheme) private var t
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 0) {
      chips
      if let shown = model.shown, !shown.isEmpty { sub(shown) }
      ZStack(alignment: .top) {
        list
        if model.fresh > 0 { pill.padding(.top, Space.s).transition(.move(edge: .top).combined(with: .opacity)) }
      }
      .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: model.fresh > 0)
    }
  }

  // 全部 / 盘口 / 持仓 / 费率 / 波动，只放字。
  private var chips: some View {
    let items: [(HomeModel.Chip, String, String)] = [
      (.all, HighlightTerm.all.text, "all"), (.cat(.book), HighlightTerm.catBook.text, "book"),
      (.cat(.oi), HighlightTerm.catOi.text, "oi"), (.cat(.funding), HighlightTerm.catFunding.text, "funding"),
      (.cat(.move), HighlightTerm.catMove.text, "move"),
    ]
    return HStack(spacing: Space.s) {
      ForEach(items, id: \.2) { chip, title, id in
        let on = model.chip == chip
        Button {
          guard !on else { return }
          Haptics.tap(); model.chip = chip
        } label: {
          // 只放字：不带条数、不带色点（用户 10-10 真机反馈）。
          Text(title).font(on ? TypeScale.controlOn : TypeScale.footnote)
          .foregroundStyle(on ? t.ink : t.ink2)
          .padding(.horizontal, Space.m)
          .frame(height: 30)
          .background {
            Capsule().fill(on ? t.segOn : LiuliMaterial(t).glassThin)
              .overlay(Capsule().strokeBorder(LiuliMaterial(t).cardEdge, lineWidth: LiuliMaterial.hairline))
          }
          .frame(minHeight: Hit.min)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("home.chip.\(id)")
      }
      Spacer(minLength: 0)
    }
    .pageHorizontalInset()
  }

  // 自选 N 只 · 热门 M 只（访客写「登录后自选也会扫」）｜HH:MM 更新 / 停于 HH:MM。
  private func sub(_ shown: [HighlightsBoard.Row]) -> some View {
    let hot = shown.lazy.filter { !$0.favorite }.count
    let left = (signedIn ? HighlightTerm.favScope.fill(["n": "\(bases.count)"]) : HighlightTerm.guestHint.text)
      + " · " + HighlightTerm.hotScope.fill(["n": "\(hot)"])
    let clock = HighlightsText.clock(model.generatedAtMs, zone: zone)
    let right = model.failed ? HighlightTerm.stoppedAt.fill(["t": clock]) : HighlightTerm.updatedAt.fill(["t": clock])
    return HStack(spacing: Space.s) {
      Text(left).lineLimit(1).minimumScaleFactor(0.85)
      Spacer(minLength: Space.s)
      Text(right).monospacedDigit().accessibilityIdentifier(model.failed ? "home.stopped" : "home.updated")
    }
    .font(TypeScale.caption2).foregroundStyle(t.ink3)
    .pageHorizontalInset()
    .padding(.bottom, Space.xs)
  }

  @ViewBuilder private var list: some View {
    if let shown = model.shown {
      ScrollViewReader { reader in
        ScrollView {
          LazyVStack(spacing: 0) {
            Color.clear.frame(height: 0).id("home.top")
            if shown.isEmpty {
              HomeCalm(icon: "checkmark.seal", title: HighlightTerm.calmTitle.text,
                       sub: HighlightTerm.calmSub.text + " · "
                         + HighlightTerm.updatedAt.fill(["t": HighlightsText.clock(model.generatedAtMs, zone: zone)]),
                       id: "home.calm")
            } else if model.visibleRows.isEmpty {
              HomeCalm(icon: "line.3.horizontal.decrease", title: HighlightTerm.noRows.text, sub: nil, id: "home.noRows")
            } else {
              let now = Int64(Date().timeIntervalSince1970 * 1000)
              ForEach(Array(model.visibleRows.enumerated()), id: \.element.id) { i, row in
                if i > 0 { Rectangle().fill(LiuliMaterial(t).rule).frame(height: 0.5).padding(.leading, 61).pageHorizontalInset() }
                HomeMoveRow(row: row, zone: zone, now: now, favorite: row.favorite || isFavorite(row.base),
                            onStar: { onStar(row.base) }, onOpen: { onOpen(row) })
              }
            }
          }
          .padding(.bottom, bottomInset)
          .grayscale(model.failed ? 1 : 0)
          .opacity(model.failed ? 0.62 : 1)
        }
        .scrollIndicators(.hidden)
        .refreshable { await reload() }
        .onChange(of: model.reorderToken) { _, _ in
          withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { reader.scrollTo("home.top", anchor: .top) }
        }
      }
    } else if model.failed {
      VStack(spacing: Space.m) {
        HomeCalm(icon: "wifi.slash", title: HighlightTerm.failed.text, sub: nil, id: "home.failed")
        Button { Task { await reload() } } label: {
          Text(HighlightTerm.retry.text).font(TypeScale.controlOn).foregroundStyle(t.amber).frame(minWidth: 88, minHeight: Hit.min)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.retry")
      }
      .frame(maxHeight: .infinity, alignment: .top)
    } else {
      HomeSkeleton()
    }
  }

  private var pill: some View {
    Button {
      Haptics.tap()
      withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { model.reorderNow() }
    } label: {
      HStack(spacing: Space.xs) {
        Image(systemName: "arrow.up").font(TypeScale.caption2Emph)
        Text(HighlightTerm.newMoves.fill(["n": "\(model.fresh)"])).font(TypeScale.controlOn).monospacedDigit()
      }
      .foregroundStyle(t.badgeInk)
      .padding(.horizontal, Space.m)
      .frame(height: 32)
      .background(t.amber, in: Capsule())
      .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
      .frame(minHeight: Hit.min)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("home.newMoves")
  }
}

/// 分类的那一点颜色：盘口走强调色、持仓走暖金、费率走次墨。色相不多开。
enum HomeCategory {
  static func tint(_ c: HighlightsBoard.Category, _ t: PanelTheme) -> Color {
    switch c {
    case .book: t.amber
    case .oi: Color(hex: t.seed.amber)
    case .funding: t.ink2
    case .move: t.up
    }
  }

  static func name(_ c: HighlightsBoard.Category) -> String {
    switch c {
    case .book: HighlightTerm.catBook.text
    case .oi: HighlightTerm.catOi.text
    case .funding: HighlightTerm.catFunding.text
    case .move: HighlightTerm.catMove.text
    }
  }
}

/// 异动一行：徽章 · 名 · 分类 · 三档强度 · 事实句 ｜ 价格 · 涨跌 · 多久前（还有别的要点写「+N」）。
/// 不在自选里的行名字后面一颗空心星，点一下加自选。
private struct HomeMoveRow: View {
  let row: HighlightsBoard.Row
  let zone: TZOffset
  let now: Int64
  let favorite: Bool
  let onStar: () -> Void
  let onOpen: () -> Void
  @Environment(\.panelTheme) private var t

  var body: some View {
    HStack(spacing: Space.s) {
      LiuliBadge(base: row.base).frame(width: 40, height: 40)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: Space.xs + 2) {
          Text(row.base).font(SymbolRowFont.liuliName).foregroundStyle(t.ink).lineLimit(1)
          if !favorite {
            Button(action: onStar) {
              Image(systemName: "star").font(TypeScale.caption2Emph).foregroundStyle(t.ink3)
                .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, -8)
            .accessibilityLabel(HighlightTerm.addFavorite.text)
            .accessibilityIdentifier("home.star.\(row.base)")
          }
          tag
          strength
          if row.count > 1 {
            Text("+\(row.count - 1)").font(TypeScale.caption2).monospacedDigit().foregroundStyle(t.ink3)
          }
        }
        highlightText(HighlightsText.homeFact(row, zone: zone), strong: t.ink)
          .font(TypeScale.caption).monospacedDigit().foregroundStyle(t.ink2)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .trailing, spacing: 3) {
        Text(row.price.map { HighlightsText.price($0, decimals: nil) } ?? SymbolRowText.missing)
          .font(TypeScale.footnoteEmph).monospacedDigit().foregroundStyle(t.ink).lineLimit(1)
        Text(HighlightsText.ago(row.atMs, now: now)).font(TypeScale.caption2).foregroundStyle(t.ink3).lineLimit(1)
      }
      .fixedSize()
      // 波动行写这次急涨 / 急跌本身的幅度、按方向着色；其余行写 24 小时涨跌。
      if let pill = HighlightsText.homePill(row) {
        ChangePill(value: pill.pct, text: pill.text)
      } else {
        ChangePill(value: .nan, text: SymbolRowText.missing)
      }
    }
    .frame(minHeight: 62)
    .pageHorizontalInset()
    .contentShape(Rectangle())
    .onTapGesture { Haptics.tap(); onOpen() }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("home.row.\(row.cat.rawValue).\(row.base)")
  }

  private var tag: some View {
    var tint = HomeCategory.tint(row.cat, t)
    var name = HomeCategory.name(row.cat)
    // 波动行写「急涨 / 急跌」，按方向着色。
    if case .move(let m) = row.top { tint = m.up ? t.up : t.down; name = HighlightsText.moveTag(m) }
    return Text(name).font(TypeScale.caption2Emph).foregroundStyle(tint)
      .padding(.horizontal, 5).frame(height: 16)
      .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
  }

  /// 三档强度：三根由低到高的小柱，亮几根就是几档。
  private var strength: some View {
    HStack(alignment: .bottom, spacing: 1.5) {
      ForEach(1...3, id: \.self) { i in
        RoundedRectangle(cornerRadius: 1, style: .continuous)
          .fill(i <= row.tier ? t.amber : t.ink3.opacity(0.28))
          .frame(width: 3, height: CGFloat(4 + i * 2))
      }
    }
    .accessibilityHidden(true)
  }
}

private struct HomeCalm: View {
  let icon: String
  let title: String
  let sub: String?
  let id: String
  @Environment(\.panelTheme) private var t

  var body: some View {
    VStack(spacing: Space.s) {
      Image(systemName: icon).font(.system(size: ControlMetrics.emptyGlyph * 0.8)).foregroundStyle(t.ink3)
      Text(title).font(TypeScale.footnoteEmph).foregroundStyle(t.ink2)
      if let sub { Text(sub).font(TypeScale.caption).foregroundStyle(t.ink3).multilineTextAlignment(.center) }
    }
    .frame(maxWidth: .infinity)
    .padding(.top, Space.section * 2)
    .pageHorizontalInset()
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(id)
  }
}

private struct HomeSkeleton: View {
  @Environment(\.panelTheme) private var t

  var body: some View {
    let fill = LiuliMaterial(t).well
    VStack(spacing: Space.l) {
      ForEach(0..<7, id: \.self) { _ in
        HStack(spacing: Space.s) {
          SkeletonBlock(width: 33, height: 33, fill: fill, radius: 12)
          VStack(alignment: .leading, spacing: 6) {
            SkeletonBlock(width: 120, height: 12, fill: fill, radius: Radius.xs)
            SkeletonBlock(width: 180, height: 10, fill: fill, radius: Radius.xs)
          }
          Spacer(minLength: 0)
          SkeletonBlock(width: 72, height: ControlMetrics.pillHeight, fill: fill, radius: Radius.s)
        }
      }
    }
    .skeletonPulse()
    .pageHorizontalInset()
    .padding(.top, Space.m)
    .frame(maxHeight: .infinity, alignment: .top)
    .accessibilityIdentifier("home.skeleton")
  }
}

// MARK: - 涨跌 / 持仓

/// 一段两张榜，不再是大方卡：每张 = 一行小标题（13 semibold `ink2`，右边纯文字「全部 / 收起」）+ 照自选页的行
/// （名次 · 徽章 28 · 名 · 数 · 涨跌药丸，行高 58，发丝线）。第一张标题行右端是这一段的 1 时 / 4 时 / 24 时小胶囊。
private struct HomeBoardView: View {
  let model: HomeModel
  let segment: HomeModel.Segment
  let bottomInset: CGFloat
  let onOpen: (String) -> Void
  let reload: () async -> Void
  @Environment(\.panelTheme) private var t

  var body: some View {
    let kinds = segment.kinds
    ScrollView {
      VStack(spacing: Space.xl) {
        ForEach(Array(kinds.enumerated()), id: \.element) { i, kind in
          section(kind, windows: i == 0)
        }
      }
      .padding(.top, Space.s)
      .padding(.bottom, bottomInset)
    }
    .scrollIndicators(.hidden)
    .refreshable { await reload() }
    .accessibilityIdentifier("home.page.\(segment.rawValue)")
  }

  static func windowName(_ w: MarketBoard.Window) -> String {
    switch w {
    case .h1: HighlightTerm.win1h.text
    case .h4: HighlightTerm.win4h.text
    case .h24: HighlightTerm.win24h.text
    }
  }

  static func title(_ k: MarketBoard.Kind) -> String {
    switch k {
    case .oi: HighlightTerm.rankOiUp.text
    case .oidown: HighlightTerm.rankOiDown.text
    case .gainers: HighlightTerm.rankGainers.text
    case .losers: HighlightTerm.rankLosers.text
    }
  }

  private func section(_ kind: MarketBoard.Kind, windows: Bool) -> some View {
    let rows = model.boards[kind]?.rows ?? []
    let open = model.expanded.contains(kind)
    let shown = open ? rows : Array(rows.prefix(6))
    return VStack(spacing: 0) {
      HStack(spacing: Space.s) {
        Text(Self.title(kind)).font(TypeScale.controlOn).foregroundStyle(t.ink2)
        Spacer(minLength: Space.s)
        if windows { windowPicker }
        if rows.count > 6 {
          Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
              if open { model.expanded.remove(kind) } else { model.expanded.insert(kind) }
            }
          } label: {
            Text((open ? HighlightTerm.collapse : HighlightTerm.all).text).font(TypeScale.captionEmph).foregroundStyle(t.amber)
              .frame(minWidth: 32, minHeight: Hit.min).contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("home.board.\(kind.rawValue).more")
        }
      }
      .frame(minHeight: Hit.min)
      .pageHorizontalInset()
      if model.boards[kind] == nil {
        if model.boardFailed.contains(kind) {
          note(HighlightTerm.failed.text)
        } else {
          VStack(spacing: Space.l) {
            ForEach(0..<6, id: \.self) { _ in
              HStack(spacing: Space.m) {
                SkeletonBlock(width: 28, height: 28, fill: LiuliMaterial(t).well, radius: 10)
                SkeletonBlock(width: 90, height: 12, fill: LiuliMaterial(t).well, radius: Radius.xs)
                Spacer(minLength: 0)
                SkeletonBlock(width: 72, height: ControlMetrics.pillHeight, fill: LiuliMaterial(t).well, radius: Radius.s)
              }
            }
          }
          .skeletonPulse()
          .padding(.vertical, Space.m)
          .pageHorizontalInset()
        }
      } else if rows.isEmpty {
        note(HighlightTerm.noRows.text)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(shown.enumerated()), id: \.element.base) { i, row in
            boardRow(kind, index: i + 1, row: row)
          }
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("home.board.\(kind.rawValue)")
  }

  private var windowPicker: some View {
    HStack(spacing: Space.xs) {
      ForEach(MarketBoard.Window.allCases, id: \.self) { w in
        HomeCapsule(title: Self.windowName(w), on: model.window(for: segment) == w, size: .small,
                    id: "home.window.\(segment.rawValue).\(w.rawValue)") {
          guard w != model.window(for: segment) else { return }
          Haptics.tap(); model.setWindow(w, for: segment)
        }
      }
    }
  }

  private func note(_ text: String) -> some View {
    Text(text).font(TypeScale.caption).foregroundStyle(t.ink3).frame(maxWidth: .infinity, minHeight: 72)
  }

  /// 照自选页那一行：名次（小号 `ink3`）· 徽章 28 · 名 13 semibold ｜ 价（涨跌榜）或持仓额（持仓榜）· 涨跌药丸。
  private func boardRow(_ kind: MarketBoard.Kind, index: Int, row: MarketBoard.Row) -> some View {
    let oi = kind == .oi || kind == .oidown
    let value: String? = oi ? row.oiUsd.map(HighlightsText.usd) : row.price.map { HighlightsText.price($0, decimals: nil) }
    return HStack(spacing: Space.m) {
      Text("\(index)").font(TypeScale.caption2).monospacedDigit().foregroundStyle(t.ink3)
        .frame(width: 16, alignment: .trailing)
      CoinBadge(base: row.base, size: 28)
      Text(row.base).font(TypeScale.controlOn).foregroundStyle(t.ink).lineLimit(1)
      Spacer(minLength: Space.s)
      if let value {
        Text(value).font(SymbolRowFont.liuliPrice).monospacedDigit().foregroundStyle(oi ? t.ink2 : t.ink).lineLimit(1)
      }
      ChangePill(value: row.changePct, text: HighlightsText.signedPct(row.changePct, decimals: 2))
    }
    .pageHorizontalInset()
    .frame(minHeight: 58)
    .contentShape(Rectangle())
    .overlay(alignment: .top) {
      if index > 1 {
        LinearGradient(colors: [.clear, SymbolRowInk.rule(t), SymbolRowInk.rule(t), .clear], startPoint: .leading, endPoint: .trailing)
          .frame(height: 0.5)
          .pageHorizontalInset()
          .accessibilityHidden(true)
      }
    }
    .onTapGesture { Haptics.tap(); onOpen(row.base) }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier("home.board.\(kind.rawValue).\(row.base)")
  }
}
