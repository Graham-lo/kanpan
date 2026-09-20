import KanpanCore
import SwiftUI

/// 「绘图」面板：一个搜索框、一条分类标签、下面三列图标格子（§2E5，照 TradingView 手机版）。
///
/// 之前这块是照 AICoin 做的——右边一竖列分类图标，点一个向左弹出一小条那类工具的清单。
/// 用户看过之后要 TV 这一套：入口收成**一个笔形图标**，点开是一整块面板，里面自带搜索
/// 和分类切换。差别不只是好看：工具全量对齐 TV 之后有 41 把，AICoin 那种「一类一格」的
/// 竖栏要摆九格分类，栏子本身就占掉横屏一条，而真正想找某一把线时还是得一类一类地翻；
/// 搜索框直接按名字命中，才是三十多把工具该有的找法。
///
/// 横竖屏共用这一个视图：竖屏它是一张 `.large` 的半屏表单，横屏是贴着左边的一块卡片
/// （TV 横屏也是从边上推出来的一块，图还露着大半）。所以它自己不带 `NavigationStack`，
/// 标题和关闭都画在里面——两种呈现方式下长得一模一样。
struct DrawingToolPicker: View {
  @ObservedObject var controller: DrawingController
  /// 「上次停在哪个分类」「上次用的是哪把工具」存在哪。见 `group` 和 `tile(_:)`。
  var store: PrefsStore
  var onClose: () -> Void
  @Environment(\.panelTheme) private var theme
  @Environment(\.displayScale) private var displayScale
  @State private var query = ""

  /// 上次停在哪个分类。
  ///
  /// 原来是纯 `@State`，面板每关一次就回到第一个分类——常用「斐波那契」的人每次
  /// 开面板都得先再点一次分类。按「他用手改过的状态跟着人走」，2026-09-19 搬进
  /// `Prefs.drawToolGroup`，随账号同步。空串 = 还没挑过，按出厂第一个分类开；
  /// 存回来的分类要是已经不在了（收藏清空了，「收藏」那一格就没了），
  /// 走 `body` 里 `onAppear` 那条既有的兜底。
  private var group: String {
    get {
      let saved = store.prefs.drawToolGroup
      return saved.isEmpty ? (Drawing.Kind.groups.first ?? "") : saved
    }
    nonmutating set { store.update { $0.drawToolGroup = newValue } }
  }

  /// 收藏排在分类前面，和竖栏那一截同一个道理：用户自己挑出来的那几把最该先够到。
  private var tabs: [String] {
    controller.preferences.favorites.isEmpty ? Drawing.Kind.groups : ["收藏"] + Drawing.Kind.groups
  }
  private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
  private var shown: [Drawing.Kind] {
    let key = query.trimmingCharacters(in: .whitespaces)
    guard !key.isEmpty else {
      return group == "收藏" ? controller.preferences.favorites : Drawing.Kind.all(in: group)
    }
    // 名字里带上就算命中：搜「斐波」能一次看全五把斐波那契，搜「通道」能同时看到
    // 平行通道和回归通道。全名和短名都认，短名是竖屏那排 chip 上写的那个说法。
    return Drawing.Kind.allCases.filter {
      $0.title.localizedCaseInsensitiveContains(key) || $0.shortTitle.localizedCaseInsensitiveContains(key)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      searchField
      if !searching { tabStrip }
      grid
    }
    .background(theme.raised)
    .onAppear { if !tabs.contains(group) { group = tabs.first ?? "" } }
  }

  private var header: some View {
    HStack {
      Text("绘图").font(.system(size: 20, weight: .semibold)).foregroundStyle(theme.ink)
      Spacer()
      Button(action: onClose) {
        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
          .frame(width: 30, height: 30)
          .background(theme.raised2, in: Circle())
      }
      .buttonStyle(.plain).foregroundStyle(theme.ink2)
      .accessibilityLabel("关闭").accessibilityIdentifier("draw.sheet.done")
    }
    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
  }

  private var searchField: some View {
    HStack(spacing: 7) {
      Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(theme.ink3)
      TextField("搜索", text: $query)
        .textFieldStyle(.plain).font(.system(size: 15))
        .foregroundStyle(theme.ink)
        .autocorrectionDisabled()
        .accessibilityIdentifier("draw.tools.search")
      if searching {
        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 14)) }
          .buttonStyle(.plain).foregroundStyle(theme.ink3)
          .accessibilityLabel("清空搜索")
      }
    }
    .padding(.horizontal, 12).frame(height: 40)
    .background(theme.raised2, in: RoundedRectangle(cornerRadius: 10))
    .padding(.horizontal, 16)
  }

  private var tabStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 4) {
        ForEach(tabs, id: \.self) { name in
          let on = group == name
          Button { group = name } label: {
            Text(name).font(.system(size: 14, weight: on ? .semibold : .regular))
              .padding(.horizontal, 12).frame(height: 32)
              .background(on ? theme.amberSoft : .clear, in: Capsule())
          }
          .buttonStyle(.plain)
          .foregroundStyle(on ? theme.amber : theme.ink2)
          .accessibilityIdentifier("draw.group.\(name)")
        }
      }.padding(.horizontal, 16)
    }
    .padding(.vertical, 12)
  }

  private var grid: some View {
    ScrollView {
      if shown.isEmpty {
        Text("没有匹配的工具").font(.system(size: 13)).foregroundStyle(theme.ink3)
          .frame(maxWidth: .infinity).padding(.top, 40)
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
        ForEach(shown) { kind in tile(kind) }
      }
      .padding(.horizontal, 16).padding(.top, searching ? 12 : 0).padding(.bottom, 20)
    }
  }

  /// 一格：图形在上、全名在下。名字写全不缩写——三十多把工具里靠「斐扩」认线太费劲，
  /// 短名留给竖屏那排一眼扫过去的 chip。右上角那颗星就是收藏开关，按一下不关面板。
  private func tile(_ kind: Drawing.Kind) -> some View {
    // 手上正举着的那把优先；空着手的时候把「上次用的那把」预选高亮出来。
    //
    // 这两件事必须分清：**待画状态**换品种就该清掉（`ChartView+Drawing.setDrawings`
    // 里那行 `d.tool = nil` 保持不动），冷启动更不许一进来就举着笔；而**上次用的是
    // 哪把**是习惯，该记住并跨启动保留，只体现在这一格的高亮上（见 `Prefs.lastDrawTool`）。
    let picked = controller.tool == kind
      || (controller.tool == nil && store.prefs.lastDrawTool == kind.rawValue)
    let fav = controller.preferences.favorites.contains(kind)
    return Button { controller.pick(kind) } label: {
      VStack(spacing: 8) {
        DrawKindGlyph(kind: kind, size: 30)
        Text(kind.title).font(.system(size: 11)).multilineTextAlignment(.center)
          .lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, 4).padding(.vertical, 12)
      .frame(maxWidth: .infinity, minHeight: 86)
      .contentShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .foregroundStyle(picked ? theme.amber : theme.ink)
    .background(RoundedRectangle(cornerRadius: 12).fill(picked ? theme.amberSoft : theme.raised2))
    .accessibilityIdentifier("draw.tool.\(kind.rawValue)")
    .drawRepeatOnLongPress(controller, kind)
    .overlay(alignment: .topTrailing) {
      Button { controller.toggleFavorite(kind) } label: {
        Image(systemName: fav ? "star.fill" : "star").font(.system(size: 11))
          .frame(width: 28, height: 28).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(fav ? theme.amber : theme.ink3.opacity(0.5))
      .accessibilityLabel((fav ? "取消收藏" : "收藏") + kind.title)
      .accessibilityIdentifier("draw.favorite.\(kind.rawValue)")
    }
  }
}
