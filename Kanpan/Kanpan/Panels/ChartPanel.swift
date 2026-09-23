import SwiftUI
import KanpanCore

/// 图表共用设置，改动即时生效并落盘。
///
/// 和「设置」的分界：**画在图上的东西归这儿，其余归设置**。以前两边各有一份
/// 外观、一份价格轴、一份本根倒计时，同一个字段两个入口两种叫法（「价格坐标」
/// 和「价格轴」是同一个 `priceMode`），改了一处回头在另一处看见旧位置，人就开始
/// 怀疑自己有没有改成功。现在外观留在设置（那边有配色卡片，能看见效果），
/// 价格轴和本根倒计时留在这儿。
///
/// 「竖屏高度」那根滑块也撤了：主图和副图的高度比例在图上直接拖副图上沿那条把手
/// 就能改，边拖边看。滑块是同一件事的第二个入口，而且它在面板里——拖的时候图被
/// 面板盖着，等于蒙着眼调。
///
/// 头一块原来是那张四选一的「K 线风格」卡（经典 / 圆角 / 空心 / 轮廓）。风格表收成
/// AICoin 一套之后（见 `CandleStyle`）它没有可选项了，整块撤掉；下面「阳线」那行
/// 的「跟随风格」也一并撤了，剩实心 / 空心两档。
/// 顶上那一组「这张图」是动作而不是设置：「记一笔」。它原来常驻在周期条右端，
/// 用户的话是「这个功能不是经常用到啊」「记和画线都放到图表栏目里」——周期条是
/// 一路要点的地方，一天用不到一次的东西不该在那儿占格。放这一页也讲得通：这一页
/// 管的就是「画在图上的东西」，取景本来就是往图上添东西。
///
/// 2026-09-18 这一页又收进了整段「指标」，面板名字也从「图表」改成了「图表设置」。
/// 用户的话是「行情页面的指标放到图表里作为一个子栏目」：底栏换成常驻标签栏之后，
/// 「图表」是标签栏上那一整页的名字，指标不再单独占一格。
/// 同一轮里「画线」那行也走了——它升成了标签栏最左边的一格，直接画当前这张图。
///
/// 2026-09-23 又收了两处：
///
/// - **指标收成一行。** 十三个开关连同参数块铺在这一页上，开得越多，下面的设置被推得越远。
///   现在这儿只有一行「指标」，右边写着开着哪几个，点进去是面板里推进去的一层
///   （`IndicatorPage`），「‹」回到这一页，不关面板。
/// - **「分享图片」和「发给朋友」并成一行「分享」。** 两者都是「把这张图给别人」，
///   差别只在对方收到的是一张图还是能在自己图上看的线。点「分享」底下弹一块二选一
///   （`ShareChooser`）；只有一种能用时（复盘回放里没有「发线」）直接走那一种，不弹。
///   画线页上那颗纸飞机一并撤了：同一个动作只留一个入口。
struct ChartPanel: View {
  var store: PrefsStore
  /// 「记一笔」：把当前这张图存进复盘本。复盘回放里没有这回事，调用方传 nil。
  var onRecord: (() -> Void)?
  /// 分享成图片：把当前这张图离屏画成一张 PNG 交给系统分享面板
  /// （见 `ChartSnapshotRenderer`）。同样地，没有图可分享时调用方传 nil。
  var onShare: (() -> Void)?
  /// 分享画线：发给账号里的朋友。复盘回放和预览别人的线时传 nil。
  var onSend: (() -> Void)?
  /// 发线此刻为什么发不了（没登录 / 图上没线）；nil 表示能发。
  var sendBlocked: String? = nil
  var onAddCompare: (() -> Void)? = nil
  var compareNames: [String: String] = [:]

  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  /// 横屏侧栏没有系统 `dismiss`，走主界面递进来的这一条（见 `PanelCloser`）。
  @Environment(\.panelDismiss) private var sideDismiss
  @State private var showIndicators = false
  @State private var choosingShare = false

  private var prefs: Prefs { store.prefs }

  /// 关自己的唯一出口。设置那些行不连着关（一次调好几项），但顶上那个**动作**
  /// 必须先把面板收掉——记一笔要看见图。竖屏是 sheet、横屏是侧栏，
  /// 面板本身不该知道是哪种，所以一律走这里。
  private var close: PanelCloser { PanelCloser(side: sideDismiss, sheet: dismiss) }

  var body: some View {
    ZStack {
      if showIndicators {
        IndicatorPage(store: store, onBack: { showIndicators = false })
          .transition(.move(edge: .trailing))
      } else {
        settings
          .transition(.move(edge: .leading))
      }
    }
    .animation(.easeOut(duration: 0.22), value: showIndicators)
    .clipped()
    .overlay {
      if choosingShare, let onShare, let onSend {
        ShareChooser(onImage: { choosingShare = false; close(); onShare() },
                     onLines: { choosingShare = false; close(); onSend() },
                     linesBlocked: sendBlocked,
                     onCancel: { choosingShare = false })
      }
    }
    .animation(.easeOut(duration: 0.18), value: choosingShare)
    .sensoryFeedback(.selection, trigger: prefs)
  }

  private var settings: some View {
    PanelSheet(title: "图表设置", subtitle: nil) {
      if onRecord != nil || onShare != nil || onSend != nil {
        PanelGroupTitle(text: "这张图")
        if let onRecord {
          PanelRow(name: "记一笔", meta: "存进复盘本",
                   divider: onShare != nil || onSend != nil, onTap: { close(); onRecord() })
            .accessibilityIdentifier("chart.record")
        }
        if onShare != nil || onSend != nil {
          PanelRow(name: "分享", meta: "发图片，或把线发给朋友", divider: false,
                   onTap: share) { chevron }
            .accessibilityIdentifier("chart.share")
        }
      }

      // 对比 K 线（`Kanpan/Kanpan/Compare/`）：最多三只，颜色跟皮肤色板走，不给选。
      if let onAddCompare {
        PanelGroupTitle(text: "对比")
        PanelRow(name: "添加对比品种", onTap: { close(); onAddCompare() })
          .disabled(prefs.compareSymbols.count >= 3)
          .accessibilityIdentifier("compare.add")
        ForEach(prefs.compareSymbols, id: \.self) { key in
          PanelRow(name: compareNames[key] ?? String(key.split(separator: "/").last ?? "")) {
            Button("移除") { store.update { $0.compareSymbols.removeAll { $0 == key } }; close() }
              .font(PanelFont.meta).foregroundStyle(t.ink2)
              .accessibilityIdentifier("compare.remove." + key)
          }
        }
        if !prefs.compareSymbols.isEmpty {
          PanelRow(name: "清除对比", divider: false, onTap: { store.update { $0.compareSymbols = [] }; close() })
            .accessibilityIdentifier("compare.clear")
        }
      }

      // 指标排在设置前面：一天里开关指标的次数远多于改坐标轴和网格。
      PanelGroupTitle(text: "指标")
      PanelRow(name: "指标", divider: false, onTap: { showIndicators = true }) {
        HStack(spacing: 6) {
          Text(IndicatorPage.summary(prefs))
            .font(PanelFont.meta).foregroundStyle(t.ink3)
            .lineLimit(1).truncationMode(.tail)
          chevron
        }
      }
      .accessibilityIdentifier("chart.indicators")

      PanelGroupTitle(text: "布局与读数")
      PanelRow(name: "K 线数据") {
        PanelSegment(options: [("K线内", CandleDataDisplay.inside), ("顶部", .top), ("跟随K线", .follow)],
                     selection: prefs.dataDisplay, id: "chart.dataDisplay") { v in store.update { $0.dataDisplay = v } }
      }
      PanelRow(name: "十字线") {
        PanelSegment(options: [("选中价", CrossPriceMode.selected), ("收盘价", .close)], selection: prefs.crossPrice,
                     id: "chart.crossPrice") { v in store.update { $0.crossPrice = v } }
      }
      PanelRow(name: "价格轴") {
        PanelSegment(options: [("线性", PriceMode.linear), ("对数", .log), ("百分比", .percent)], selection: prefs.priceMode) { v in store.update { $0.priceMode = v } }
      }
      switchRow("主轴允许翻转", nil, prefs.allowMainInversion,
                id: "chart.allowMainInversion") { $0.allowMainInversion = $1 }
      switchRow("副轴允许翻转", nil, prefs.allowSubInversion,
                id: "chart.allowSubInversion") { $0.allowSubInversion = $1 }
      switchRow("指标区域自适应", nil, prefs.adaptiveIndicators) { $0.adaptiveIndicators = $1 }

      PanelGroupTitle(text: "类型")
      PanelRow(name: "画法", divider: false) {
        PanelSegment(options: ChartPanel.kinds, selection: prefs.candleKind,
                     id: "chart.candleKind") { v in
          store.update { $0.candleKind = v }
        }
      }

      PanelGroupTitle(text: "K 线")
      PanelRow(name: "网格") {
        PanelSegment(options: ChartPanel.grids, selection: prefs.gridChoice,
                     id: "chart.gridChoice") { v in
          store.update { $0.gridChoice = v }
        }
      }
      PanelRow(name: "阳线") {
        PanelSegment(options: ChartPanel.bodies, selection: prefs.bodyChoice,
                     id: "chart.bodyChoice") { v in
          store.update { $0.bodyChoice = v }
        }
      }
      PanelRow(name: "横向位置") {
        PanelSegment(options: ChartPanel.anchors, selection: prefs.viewAnchor,
                     id: "chart.viewAnchor") { v in
          store.update { $0.viewAnchor = v }
        }
      }
      PanelRow(name: "纵向位置", divider: false) {
        PanelSegment(options: ChartPanel.biases, selection: prefs.priceBias,
                     id: "chart.priceBias") { v in
          store.update { $0.priceBias = v }
        }
      }

      PanelGroupTitle(text: "显示")
      switchRow("实时价格线", nil, prefs.lastLine) { $0.lastLine = $1 }
        .accessibilityIdentifier("chart.lastLine")
      // 「设置」里原来也有一行同名开关，已经去掉了：那是画在图上的东西，归这儿。
      switchRow("盘口", nil, prefs.depth, id: "chart.depth") { $0.depth = $1 }
      switchRow("本根倒计时", nil, prefs.countdown) { $0.countdown = $1 }
        .accessibilityIdentifier("chart.countdown")
      // 「显示画线」那一行 2026-09-23 撤了：画线页「更多」里有「全部隐藏」，两颗开关管同一件事。
      switchRow("至今涨幅", nil, prefs.sinceChange, divider: false) {
        $0.sinceChange = $1
      }
      .accessibilityIdentifier("chart.sinceChange")
    }
    .sensoryFeedback(.selection, trigger: prefs)
  }

  private var chevron: some View {
    VectorIcon.chevron(9, w: 1.7).rotationEffect(.degrees(-90)).foregroundStyle(t.ink3)
  }

  /// 只有一种分享能用时直接走那一种，两种都在才弹二选一。
  private func share() {
    switch (onShare, onSend) {
    case (let image?, nil): close(); image()
    case (nil, let send?): close(); send()
    default: choosingShare = true
    }
  }

  // MARK: - 行

  /// `id` 给用例一个把手：这几个开关控制的是「双击轴翻不翻转」这类默认关掉的行为，
  /// 没有把手就只能靠点坐标去猜哪一行是哪一行。
  private func switchRow(_ name: String, _ meta: String?, _ on: Bool, divider: Bool = true,
                         id: String? = nil,
                         _ set: @escaping (inout Prefs, Bool) -> Void) -> some View {
    PanelRow(name: name, meta: meta, divider: divider) {
      PanelSwitch(isOn: on) { store.update { set(&$0, !on) } }
        .accessibilityIdentifier(id ?? "")
    }
  }

  // MARK: - 分段选项

  /// 字面写在这儿而不是取枚举的 `display`：面板上要的是短词（「空心」），
  /// 枚举那边给的是完整名字（「阳线空心」），两处用途不同，和 `SettingsPanel` 一个办法。
  static let kinds: [(String, CandleKind)] = [("蜡烛", .candle), ("平均K线", .heikin), ("收盘价", .line)]
  static let grids: [(String, GridChoice)] = [("显示", .on), ("隐藏", .off)]
  static let bodies: [(String, BodyChoice)] = [("实心", .solid), ("空心", .hollowUp)]
  static let anchors: [(String, ViewAnchor)] = [("偏左", .left), ("居中", .center), ("靠右", .right)]
  static let biases: [(String, PriceBias)] = [("偏上", .up), ("居中", .center), ("偏下", .down)]
}

#if DEBUG
#Preview("图表设置") {
  PanelPreviewHost { store in ChartPanel(store: store) }
}
#endif
