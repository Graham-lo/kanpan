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
  /// 系统字号超过默认档时副文案放开到两行、行高跟着长；默认档仍是原来的一行 52pt。
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var skin: SectorSkin { SectorSkin(theme: theme) }

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
          row(stat, first: index == 0)
        }
      }
      .padding(.top, 6).padding(.bottom, 8)
    }
    .scrollIndicators(.hidden)
    // 先成组再挂 id，否则这个 id 会盖掉底下每一行自己的（见 `SectorPage`）。
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("sector.board")
  }

  /// 原型 `.srow`：26 的记号 + 全称 + 副文案，右边一列涨跌幅。
  private func row(_ stat: SectorStat, first: Bool) -> some View {
    HStack(spacing: 11) {
      if let art = SectorIcons.art(stat.id) {
        SectorIconView(art: art, size: 26)
      } else {
        // 兜底桶不一定有自己的记号。留出同样的位置，行与行的竖线才不会错开。
        Color.clear.frame(width: 26, height: 26)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(stat.name).font(.scaled(14, .medium)).foregroundStyle(theme.ink)
          .lineLimit(1).minimumScaleFactor(0.75)
        Text(SectorSubtitle.row(stat))
          .font(.scaled(10.5)).monospacedDigit().tracking(0.32)
          .foregroundStyle(skin.ink4)
          .lineLimit(dynamicTypeSize > .large ? 2 : 1).minimumScaleFactor(0.8)
      }.frame(maxWidth: .infinity, alignment: .leading)
      Text(sectorPctText(stat.pct))
        .font(.scaled(13.5, .medium)).monospacedDigit()
        .foregroundStyle(stat.pct >= 0 ? theme.up : theme.down)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, dynamicTypeSize > .large ? 7 : 0)
    .frame(minHeight: 52)
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
