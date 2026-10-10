import KanpanCore
import KanpanNetwork
import SwiftUI

/// 首页（底栏最左一格，PROJECT.md §79）：「异动 · 榜单」两段。
///
/// - 异动：自选（登录后带上）∪ 服务端热点层里此刻值得看一眼的品种，每只一行、按服务端权重排，打开时定序。
///   点一行 → 去行情页、换到这只、自动升起「盘口要点」半页并展开那一条、图上画带子。
/// - 榜单：持仓变化 / 涨幅 / 跌幅三张卡，各 6 行，「全部」展开；窗口 1 时 / 4 时 / 24 时（只记本机）。
///   点一行只开图，不自动升半页。
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

  @Environment(\.panelTheme) private var t

  /// 访客不带自选（和手机网页一致：自选要登录后才进扫描）。
  private var bases: [String] { signedIn ? HomeModel.favoriteBases(favorites) : [] }

  var body: some View {
    let bases = self.bases
    VStack(spacing: 0) {
      header
      switch model.segment {
      case .moves: HomeMovesView(model: model, bases: bases, signedIn: signedIn, zone: zone, bottomInset: bottomInset,
                                 isFavorite: isFavorite, onStar: onStar, onOpen: onOpenMove,
                                 reload: { await model.load(bases: bases, reorder: true) { await catalog.highlightsBoard(bases: $0) } })
      case .board: HomeBoardView(model: model, bottomInset: bottomInset, onOpen: onOpenBoard,
                                 reload: { await model.loadBoards { await catalog.marketBoard(kind: $0, window: $1) } })
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background { LiuliBackdrop(material: LiuliMaterial(t)) }
    .tint(t.amber)
    .task(id: "\(model.segment.rawValue)|\(bases.joined(separator: ","))|\(model.window.rawValue)") {
      switch model.segment {
      case .moves: await model.pollMoves(bases: bases) { await catalog.highlightsBoard(bases: $0) }
      case .board: await model.pollBoards { await catalog.marketBoard(kind: $0, window: $1) }
      }
    }
  }

  private var header: some View {
    HStack(spacing: Space.s) {
      SectorSegment(options: HomeModel.Segment.allCases.map {
        .init(title: ($0 == .moves ? HighlightTerm.moves : HighlightTerm.board).text, value: $0, id: "home.segment.\($0.rawValue)")
      }, selection: model.segment) { next in
        guard next != model.segment else { return }
        Haptics.tap()
        model.segment = next
      }
      Spacer(minLength: 0)
    }
    .pageHorizontalInset()
    .padding(.top, Space.xs)
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

  // 全部 / 盘口 / 持仓 / 费率，带条数。
  private var chips: some View {
    let items: [(HomeModel.Chip, String, String)] = [
      (.all, HighlightTerm.all.text, "all"), (.cat(.book), HighlightTerm.catBook.text, "book"),
      (.cat(.oi), HighlightTerm.catOi.text, "oi"), (.cat(.funding), HighlightTerm.catFunding.text, "funding"),
    ]
    return HStack(spacing: Space.s) {
      ForEach(items, id: \.2) { chip, title, id in
        let on = model.chip == chip
        Button {
          guard !on else { return }
          Haptics.tap(); model.chip = chip
        } label: {
          HStack(spacing: Space.xs) {
            if case .cat(let c) = chip { Circle().fill(HomeCategory.tint(c, t)).frame(width: 6, height: 6) }
            Text(title).font(on ? TypeScale.controlOn : TypeScale.footnote)
            if model.shown != nil {
              Text("\(model.count(chip))").font(TypeScale.caption2).monospacedDigit().foregroundStyle(on ? t.ink2 : t.ink3)
            }
          }
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
              ForEach(Array(model.visibleRows.enumerated()), id: \.element.base) { i, row in
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
    }
  }

  static func name(_ c: HighlightsBoard.Category) -> String {
    switch c {
    case .book: HighlightTerm.catBook.text
    case .oi: HighlightTerm.catOi.text
    case .funding: HighlightTerm.catFunding.text
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
          .lineLimit(1).minimumScaleFactor(0.8)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .trailing, spacing: 3) {
        Text(row.price.map { HighlightsText.price($0, decimals: nil) } ?? SymbolRowText.missing)
          .font(TypeScale.footnoteEmph).monospacedDigit().foregroundStyle(t.ink).lineLimit(1)
        Text(HighlightsText.ago(row.atMs, now: now)).font(TypeScale.caption2).foregroundStyle(t.ink3).lineLimit(1)
      }
      .fixedSize()
      if let pct = row.changePct {
        ChangePill(value: pct, text: HighlightsText.signedPct(pct, decimals: 2))
      } else {
        ChangePill(value: .nan, text: SymbolRowText.missing)
      }
    }
    .frame(minHeight: 62)
    .pageHorizontalInset()
    .contentShape(Rectangle())
    .onTapGesture { Haptics.tap(); onOpen() }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("home.row.\(row.base)")
  }

  private var tag: some View {
    let tint = HomeCategory.tint(row.cat, t)
    return Text(HomeCategory.name(row.cat)).font(TypeScale.caption2Emph).foregroundStyle(tint)
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

// MARK: - 榜单

private struct HomeBoardView: View {
  let model: HomeModel
  let bottomInset: CGFloat
  let onOpen: (String) -> Void
  let reload: () async -> Void
  @Environment(\.panelTheme) private var t

  var body: some View {
    ScrollView {
      VStack(spacing: Space.m) {
        HStack {
          SectorSegment(options: MarketBoard.Window.allCases.map {
            .init(title: Self.windowName($0), value: $0, id: "home.window.\($0.rawValue)")
          }, selection: model.window) { next in
            guard next != model.window else { return }
            Haptics.tap(); model.window = next
          }
          Spacer(minLength: 0)
        }
        ForEach(MarketBoard.Kind.allCases, id: \.self) { card($0) }
      }
      .pageHorizontalInset()
      .padding(.bottom, bottomInset)
    }
    .scrollIndicators(.hidden)
    .refreshable { await reload() }
  }

  static func windowName(_ w: MarketBoard.Window) -> String {
    switch w {
    case .h1: HighlightTerm.win1h.text
    case .h4: HighlightTerm.win4h.text
    case .h24: HighlightTerm.win24h.text
    }
  }

  private static func title(_ k: MarketBoard.Kind) -> String {
    switch k {
    case .oi: HighlightTerm.boardOi.text
    case .gainers: HighlightTerm.boardGainers.text
    case .losers: HighlightTerm.boardLosers.text
    }
  }

  private func card(_ kind: MarketBoard.Kind) -> some View {
    let rows = model.boards[kind]?.rows ?? []
    let open = model.expanded.contains(kind)
    let shown = open ? rows : Array(rows.prefix(6))
    return HighlightsBlock(title: Self.title(kind)) {
      if rows.count > 6 {
        Button {
          Haptics.tap()
          withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if open { model.expanded.remove(kind) } else { model.expanded.insert(kind) }
          }
        } label: {
          Text((open ? HighlightTerm.collapse : HighlightTerm.all).text).font(TypeScale.captionEmph).foregroundStyle(t.amber)
            .frame(minHeight: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.board.\(kind.rawValue).more")
      }
    } content: {
      if model.boards[kind] == nil {
        if model.boardFailed.contains(kind) {
          Text(HighlightTerm.failed.text).font(TypeScale.caption).foregroundStyle(t.ink3).frame(maxWidth: .infinity, minHeight: 60)
        } else {
          VStack(spacing: Space.s) {
            ForEach(0..<6, id: \.self) { _ in SkeletonBlock(height: 22, fill: LiuliMaterial(t).well, radius: Radius.xs) }
          }
          .skeletonPulse()
        }
      } else if rows.isEmpty {
        Text(HighlightTerm.noRows.text).font(TypeScale.caption).foregroundStyle(t.ink3).frame(maxWidth: .infinity, minHeight: 60)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(shown.enumerated()), id: \.element.base) { i, row in
            boardRow(kind, index: i + 1, row: row)
          }
        }
      }
    }
    .accessibilityIdentifier("home.board.\(kind.rawValue)")
  }

  private func boardRow(_ kind: MarketBoard.Kind, index: Int, row: MarketBoard.Row) -> some View {
    let up = row.changePct >= 0
    return HStack(spacing: Space.s) {
      Text("\(index)").font(TypeScale.caption2).monospacedDigit().foregroundStyle(t.ink3).frame(width: 16, alignment: .leading)
      CoinBadge(base: row.base, size: 22)
      Text(row.base).font(TypeScale.footnoteEmph).foregroundStyle(t.ink).lineLimit(1)
      Spacer(minLength: Space.s)
      if kind == .oi, let oi = row.oiUsd {
        Text(HighlightsText.usd(oi)).font(TypeScale.caption2).monospacedDigit().foregroundStyle(t.ink3)
      } else if let p = row.price {
        Text(HighlightsText.price(p, decimals: nil)).font(TypeScale.caption2).monospacedDigit().foregroundStyle(t.ink3)
      }
      Text(HighlightsText.signedPct(row.changePct, decimals: 2))
        .font(TypeScale.footnoteEmph).monospacedDigit().foregroundStyle(up ? t.up : t.down)
        .frame(minWidth: 64, alignment: .trailing)
        .contentTransition(.numericText(value: row.changePct))
    }
    .frame(minHeight: 36)
    .contentShape(Rectangle())
    .onTapGesture { Haptics.tap(); onOpen(row.base) }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier("home.board.\(kind.rawValue).\(row.base)")
  }
}
