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
/// 2026-09-18 这一页又收进了整段「指标」（`IndicatorSections`），面板名字也从
/// 「图表」改成了「图表设置」。用户的话是「行情页面的指标放到图表里作为一个子栏目」：
/// 底栏换成常驻标签栏之后，「图表」是标签栏上那一整页的名字，指标不再单独占一格。
/// 同一轮里「画线」那行也走了——它升成了标签栏最左边的一格，直接画当前这张图。
struct ChartPanel: View {
  var store: PrefsStore
  /// 「记一笔」：把当前这张图存进复盘本。复盘回放里没有这回事，调用方传 nil。
  var onRecord: (() -> Void)?
  /// 「分享图片」：把当前这张图离屏画成一张 PNG 交给系统分享面板
  /// （见 `ChartSnapshotRenderer`）。同样地，没有图可分享时调用方传 nil。
  var onShare: (() -> Void)?
  var onSend: (() -> Void)?
  var sendMeta = "把图上的线发过去"

  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  /// 横屏侧栏没有系统 `dismiss`，走主界面递进来的这一条（见 `PanelCloser`）。
  @Environment(\.panelDismiss) private var sideDismiss

  private var prefs: Prefs { store.prefs }

  /// 关自己的唯一出口。设置那些行不连着关（一次调好几项），但顶上那个**动作**
  /// 必须先把面板收掉——记一笔要看见图。竖屏是 sheet、横屏是侧栏，
  /// 面板本身不该知道是哪种，所以一律走这里。
  private var close: PanelCloser { PanelCloser(side: sideDismiss, sheet: dismiss) }

  var body: some View {
    PanelSheet(title: "图表设置", subtitle: nil) {
      if onRecord != nil || onShare != nil || onSend != nil {
        PanelGroupTitle(text: "这张图")
        if let onRecord {
          PanelRow(name: "记一笔", meta: "存进复盘本",
                   divider: onShare != nil || onSend != nil, onTap: { close(); onRecord() })
            .accessibilityIdentifier("chart.record")
        }
        if let onShare {
          PanelRow(name: "分享图片", meta: "存成图片发出去",
                   divider: onSend != nil, onTap: { close(); onShare() })
            .accessibilityIdentifier("chart.share")
        }
        if let onSend {
          PanelRow(name: "发给朋友", meta: sendMeta, divider: false,
                   onTap: { close(); onSend() })
            .accessibilityIdentifier("chart.send")
        }
      }

      // 指标排在设置前面：一天里开关指标的次数远多于改坐标轴和网格，
      // 半屏出场时第一眼要能看见它。
      IndicatorSections(store: store)

      PanelGroupTitle(text: "布局与读数")
      PanelRow(name: "K 线数据") {
        PanelSegment(options: [("K线内", CandleDataDisplay.inside), ("顶部", .top), ("跟随K线", .follow)],
                     selection: prefs.dataDisplay, id: "chart.dataDisplay") { v in store.update { $0.dataDisplay = v } }
      }
      PanelRow(name: "十字线") {
        PanelSegment(options: [("选中价", CrossPriceMode.selected), ("收盘价", .close)], selection: prefs.crossPrice) { v in store.update { $0.crossPrice = v } }
      }
      PanelRow(name: "价格轴") {
        PanelSegment(options: [("线性", PriceMode.linear), ("对数", .log), ("百分比", .percent)], selection: prefs.priceMode) { v in store.update { $0.priceMode = v } }
      }
      switchRow("主轴允许翻转", "双击价格轴上下颠倒", prefs.allowMainInversion,
                id: "chart.allowMainInversion") { $0.allowMainInversion = $1 }
      switchRow("副轴允许翻转", "双击副图坐标轴翻转", prefs.allowSubInversion,
                id: "chart.allowSubInversion") { $0.allowSubInversion = $1 }
      switchRow("指标区域自适应", nil, prefs.adaptiveIndicators) { $0.adaptiveIndicators = $1 }
      switchRow("简化指标数值", "使用万、亿等单位", prefs.compactValues) { $0.compactValues = $1 }

      PanelGroupTitle(text: "类型")
      PanelRow(name: "画法", meta: prefs.candleKind == .heikin ? "平均 K 线使用平滑价格" : nil,
               divider: false) {
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
      switchRow("本根倒计时", nil, prefs.countdown) { $0.countdown = $1 }
        .accessibilityIdentifier("chart.countdown")
      switchRow("至今涨幅", "选中 K 线至今的涨跌幅", prefs.sinceChange) {
        $0.sinceChange = $1
      }
      .accessibilityIdentifier("chart.sinceChange")
      switchRow("显示画线", nil, prefs.showDrawings, divider: false) {
        $0.showDrawings = $1
      }
      .accessibilityIdentifier("chart.showDrawings")

    }
    .sensoryFeedback(.selection, trigger: prefs)
    // 指标那段会弹「副图最多三个」，提示归这一层——面板盖着主界面的 toast。
    .panelToast(store)
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
  static let kinds: [(String, CandleKind)] = [("蜡烛", .candle), ("平均K线", .heikin)]
  static let grids: [(String, GridChoice)] = [("显示", .on), ("隐藏", .off)]
  static let bodies: [(String, BodyChoice)] = [("实心", .solid), ("空心", .hollowUp)]
  static let anchors: [(String, ViewAnchor)] = [("偏左", .left), ("居中", .center), ("靠右", .right)]
  static let biases: [(String, PriceBias)] = [("偏上", .up), ("居中", .center), ("偏下", .down)]
}

#Preview("图表设置") {
  PanelPreviewHost { store in ChartPanel(store: store) }
}
