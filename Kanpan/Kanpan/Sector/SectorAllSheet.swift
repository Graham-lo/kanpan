import SwiftUI
import KanpanCore

/// 「全部板块」整页清单。
///
/// 气泡场上只站得下十来颗，剩下的都在这儿。它是没上场那些板块**唯一**的去处——
/// 气泡页上不为它们另起一块常驻界面，只有右上角那颗「…」通到这里。
///
/// 兜底桶（分类表没收的品种按交易所标签凑的那些）也列在这张表里，而且和普通板块
/// **画得一模一样**：不去饱和、不加标记、不另起一组、不排到最后，就按涨跌幅落在
/// 它该在的位置上。它们只是没进气泡场的排名而已，不是次等公民。
///
/// 这里没有名次徽章、没有「龙头」「最强」、没有冠军环，排序只按当前口径的涨跌幅。
struct SectorAllSheet: View {
  /// 已按涨跌幅降序排好（含兜底桶）。
  var stats: [SectorStat]
  /// 当前市场。这张清单也是按市场分的，页头那颗胶囊要知道自己亮在哪一档。
  var market: SectorMarket
  var onBack: () -> Void
  var onPick: (SectorStat) -> Void
  /// 在这张清单里换市场。换完清单还留在原处，换的是清单的内容。
  var onPickMarket: (SectorMarket) -> Void

  @Environment(\.panelTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var skin: SectorSkin { SectorSkin(theme: theme) }

  var body: some View {
    VStack(spacing: 0) {
      header
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
            row(stat, first: index == 0)
          }
        }
        .padding(.top, 6).padding(.bottom, 8)
      }
      .scrollIndicators(.hidden)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    // 这一层底下还铺着球场。落在头部空处的点要在这儿吃掉，不然会穿下去点着一颗球。
    .contentShape(Rectangle())
    .onTapGesture { }
    .background { SectorBackdrop(skin: skin, reduceMotion: reduceMotion).ignoresSafeArea() }
    // 先成组再挂 id，否则这个 id 会盖掉底下每一行自己的（见 `SectorPage`）。
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("sector.all")
  }

  /// 页头：返回 ·「全部板块」· 市场硬切换。
  ///
  /// 加密／美股那颗胶囊是这张清单自己的——它和球场是同一个市场，人进了清单照样换得动，
  /// 不用先退回球场再换再进来。右边原来那个「N 个」撤了：一共几个板块不是用户要的数，
  /// 那个位置该留给能按的东西。
  private var header: some View {
    HStack(spacing: 6) {
      SectorBackButton(skin: skin, id: "sector.all.back", action: onBack)
      Text("全部板块").font(skin.serif(19)).tracking(0.76).foregroundStyle(theme.ink)
        .padding(.leading, 5)
      Spacer(minLength: 8)
      SectorMarketSwitch(skin: skin, market: market, onPick: onPickMarket)
    }
    .padding(.leading, 15).padding(.trailing, 20).padding(.top, 6)
  }

  /// 副文案：`18 个品种 · 15/18 跑赢 · 成交额 1.2B`。
  ///
  /// 有行情成员不到 3 个的板块（`desci` 就一只 BIO）没有「广度」可言
  /// ——一只币的涨跌不是板块强弱。这种少写「跑赢」那一段，不解释为什么。
  /// 成交额拿不到时同理：那一段整个不写，不排一列「成交额 —」。
  private func subtitle(_ stat: SectorStat) -> String {
    let head = "\(stat.memberCount) 个品种"
    let tail = sectorVolumeClause(stat.quoteVolume)
    guard stat.memberCount >= SectorAggregator.minEligibleMembers else { return head + tail }
    return head + " · \(stat.outperformCount)/\(stat.memberCount) 跑赢" + tail
  }

  /// 原型 `.srow`：26 的记号 + 名字 + 副文案，右边一列涨跌幅。
  private func row(_ stat: SectorStat, first: Bool) -> some View {
    HStack(spacing: 11) {
      if let art = SectorIcons.art(stat.id) {
        SectorIconView(art: art, size: 26)
      } else {
        // 兜底桶不一定有自己的记号。留出同样的位置，行与行的竖线才不会错开。
        Color.clear.frame(width: 26, height: 26)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(stat.name).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.ink)
          .lineLimit(1).minimumScaleFactor(0.75)
        Text(subtitle(stat))
          .font(.system(size: 10.5)).monospacedDigit().tracking(0.32)
          .foregroundStyle(skin.ink4)
          .lineLimit(1).minimumScaleFactor(0.8)
      }.frame(maxWidth: .infinity, alignment: .leading)
      Text(sectorPctText(stat.pct))
        .font(.system(size: 13.5, weight: .medium)).monospacedDigit()
        .foregroundStyle(stat.pct >= 0 ? theme.up : theme.down)
    }
    .padding(.horizontal, 20)
    .frame(height: 52)
    .contentShape(Rectangle())
    .onTapGesture { onPick(stat) }
    .overlay(alignment: .top) {
      if !first { SectorHairline(skin: skin) }
    }
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isButton)
    .accessibilityIdentifier("sector.all.row." + stat.id)
    .accessibilityAction { onPick(stat) }
  }
}
