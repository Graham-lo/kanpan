import SwiftUI
import KanpanCore

/// 板块页的正文：当前市场的全部板块，一行一个。
///
/// 2026-09-24 起板块页不再有气泡场，底栏第四格进来就是这张清单（用户：「现在不再展示
/// 气泡，一律用页面即可」）。它原来是右上角「…」通到的「全部板块」那一层，内容和画法
/// 原样升成整页，只是没有了自己的页头——标题、市场切换和窗口药丸归 `SectorPage` 管。
///
/// 兜底桶（分类表没收的品种按交易所标签凑的那些）也列在这里，而且和普通板块
/// **画得一模一样**：不去饱和、不加标记、不另起一组、不排到最后，就按涨跌幅落在
/// 它该在的位置上。
///
/// 这里没有名次徽章、没有「龙头」「最强」，排序只按当前窗口的涨跌幅
/// （`SectorBoardOrder`）。
struct SectorBoardList: View {
  /// 已按 `SectorBoardOrder` 排好（含兜底桶）。
  var stats: [SectorStat]
  var onPick: (SectorStat) -> Void

  @Environment(\.panelTheme) private var theme
  /// 系统字号超过默认档时副文案放开到两行、行高跟着长。
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var skin: SectorSkin { SectorSkin(theme: theme) }

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
          row(stat, first: index == 0)
        }
      }
      .padding(.top, Space.xs).padding(.bottom, Space.s)
    }
    // 底栏身后铺着一道渐变（`TabBar.fade`），最后一行要停在它上沿以上。
    .contentMargins(.bottom, TabBar.fadeClearance, for: .scrollContent)
    .scrollIndicators(.hidden)
    // 先成组再挂 id，否则这个 id 会盖掉底下每一行自己的（见 `SectorPage`）。
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("sector.board")
  }

  /// 原型 `.srow`：记号 + 全称 + 副文案，右边一列涨跌幅。
  ///
  /// 字号照 HIG 阶梯（UI 审查 2026-09-24 P1b）：行名 15 regular、涨跌 13 medium 等宽、
  /// 说明 12；记号与列表徽章同一个 32，行至少 44 高，左右边距跟页面走（16 / 20）。
  private func row(_ stat: SectorStat, first: Bool) -> some View {
    HStack(spacing: Space.m) {
      if let art = SectorIcons.art(stat.id) {
        SectorIconView(art: art, size: ControlMetrics.listBadge)
      } else {
        // 兜底桶不一定有自己的记号。留出同样的位置，行与行的竖线才不会错开。
        Color.clear.frame(width: ControlMetrics.listBadge, height: ControlMetrics.listBadge)
      }
      VStack(alignment: .leading, spacing: Space.xxs) {
        Text(stat.name).font(TypeScale.body).foregroundStyle(theme.ink)
          .lineLimit(1).minimumScaleFactor(0.85)
        let subtitle = SectorSubtitle.row(stat)
        if !subtitle.isEmpty {
          Text(subtitle)
            .font(TypeScale.caption).monospacedDigit()
            .foregroundStyle(theme.ink3)
            .lineLimit(dynamicTypeSize > .large ? 2 : 1).minimumScaleFactor(0.9)
            .accessibilityIdentifier("sector.board.breadth." + stat.id)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
      Text(sectorPctText(stat.pct))
        .font(TypeScale.footnoteEmph).monospacedDigit()
        .foregroundStyle(theme.sectorPct(stat.pct))
    }
    .pageHorizontalInset()
    .padding(.vertical, Space.s)
    .frame(minHeight: Inset.rowMin)
    .contentShape(Rectangle())
    .onTapGesture { onPick(stat) }
    .overlay(alignment: .top) {
      if !first { SectorHairline(skin: skin) }
    }
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier("sector.row." + stat.id)
    .accessibilityAction { onPick(stat) }
  }
}

extension PanelTheme {
  /// 板块页涨跌幅的颜色。口径在 `SectorPctTone`：算不出来的是中性色，不是下跌色。
  func sectorPct(_ value: Double) -> Color {
    switch SectorPctTone.of(value) {
    case .up: up
    case .down: down
    case .neutral: ink3
    }
  }
}

// MARK: - 第一趟还在路上

/// 板块页第一次装好、第一趟行情还没回来时那几行骨架（体感优化 2026-10-07）。
///
/// 原来这儿整块留白（`Color.clear`）：不闪「暂无行情」、不写「加载中」都对，可一整页空着
/// 看起来像坏了。现在照 `SectorBoardList` 一行的版式摆几行浅色块——记号一枚圆、
/// 行名一条、副文案一条、右边涨跌一条，分隔线与真行同一根——数据一到原地换成真行，
/// 版面不跳。仍旧不写任何字。
struct SectorBoardSkeleton: View {
  /// 摆几行：一屏上半截够了，不必铺满（6–8 行的中间值）。
  static let rowCount = 7

  @Environment(\.panelTheme) private var theme
  private var skin: SectorSkin { SectorSkin(theme: theme) }

  var body: some View {
    VStack(spacing: 0) {
      ForEach(0..<Self.rowCount, id: \.self) { index in
        row(index)
      }
      Spacer(minLength: 0)
    }
    .padding(.top, Space.xs)
    .skeletonPulse()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .allowsHitTesting(false)
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier("sector.skeleton")
  }

  private func row(_ index: Int) -> some View {
    let ink = skin.rule
    return HStack(spacing: Space.m) {
      Circle().fill(ink).frame(width: ControlMetrics.listBadge, height: ControlMetrics.listBadge)
      VStack(alignment: .leading, spacing: Space.xs) {
        SkeletonBlock(width: Skeleton.width(index, base: 52, spread: 44), height: 13, fill: ink)
        SkeletonBlock(width: Skeleton.width(index + 3, base: 96, spread: 60), height: 10, fill: ink)
      }.frame(maxWidth: .infinity, alignment: .leading)
      SkeletonBlock(width: 48, height: 13, fill: ink)
    }
    .pageHorizontalInset()
    .padding(.vertical, Space.s)
    .frame(minHeight: Inset.rowMin)
    .overlay(alignment: .top) {
      if index > 0 { SectorHairline(skin: skin) }
    }
  }
}

/// 板块页第一层此刻摆什么：取数确实失败了的空态、第一趟在路上的骨架、还是真表。
enum SectorBoardContent: Equatable {
  case failed, skeleton, list

  static func of(showsEmptyState: Bool, hasStats: Bool) -> SectorBoardContent {
    if showsEmptyState { return .failed }
    return hasStats ? .list : .skeleton
  }
}
