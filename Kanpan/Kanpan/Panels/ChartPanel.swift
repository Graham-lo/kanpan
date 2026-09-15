import SwiftUI
import KanpanCore

/// 图表共用设置，改动即时生效并落盘；风格只控制造型。
struct ChartPanel: View {
  var store: PrefsStore

  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss
  /// 横屏侧栏没有系统 `dismiss`，走主界面递进来的这一条（见 `PanelCloser`）。
  @Environment(\.panelDismiss) private var sideDismiss

  private var prefs: Prefs { store.prefs }

  /// 关自己的唯一出口。这一页现在没有哪一行该关掉自己（配置页不连着关），
  /// 但真要加一行时必须走这里——竖屏是 sheet、横屏是侧栏，面板本身不该知道。
  private var close: PanelCloser { PanelCloser(side: sideDismiss, sheet: dismiss) }

  var body: some View {
    PanelSheet(title: "图表", subtitle: nil) {
      CandleStylePicker(store: store)
      PanelRow(name: "外观") {
        PanelSegment(options: ThemeChoice.options, selection: prefs.theme) { value in
          store.update { $0.theme = value }
        }
      }

      PanelGroupTitle(text: "布局与读数")
      PanelRow(name: "竖屏高度") {
        Slider(value: Binding(get: { prefs.portraitHeight }, set: { value in store.update { $0.portraitHeight = value } }), in: 0...1)
          .frame(maxWidth: 180).accessibilityIdentifier("chart.portraitHeight")
      }
      PanelRow(name: "K线数据") {
        PanelSegment(options: [("K线内", CandleDataDisplay.inside), ("顶部", .top), ("跟随K线", .follow)], selection: prefs.dataDisplay) { v in store.update { $0.dataDisplay = v } }
      }.accessibilityIdentifier("chart.dataDisplay")
      PanelRow(name: "十字线") {
        PanelSegment(options: [("选中价", CrossPriceMode.selected), ("收盘价", .close)], selection: prefs.crossPrice) { v in store.update { $0.crossPrice = v } }
      }
      PanelRow(name: "价格坐标") {
        PanelSegment(options: [("线性", PriceMode.linear), ("对数", .log), ("百分比", .percent)], selection: prefs.priceMode) { v in store.update { $0.priceMode = v } }
      }
      switchRow("主轴允许翻转", "轻点价格轴翻转", prefs.allowMainInversion) { $0.allowMainInversion = $1 }
      switchRow("副轴允许翻转", "轻点副图坐标轴翻转", prefs.allowSubInversion) { $0.allowSubInversion = $1 }
      switchRow("指标区域自适应", nil, prefs.adaptiveIndicators) { $0.adaptiveIndicators = $1 }
      switchRow("简化指标数值", "使用万、亿等单位", prefs.compactValues) { $0.compactValues = $1 }

      PanelGroupTitle(text: "类型")
      PanelRow(name: "画法", meta: prefs.candleKind == .heikin ? "平均 K 线使用平滑价格" : nil,
               divider: false) {
        PanelSegment(options: ChartPanel.kinds, selection: prefs.candleKind) { v in
          store.update { $0.candleKind = v }
        }
      }
      .accessibilityIdentifier("chart.candleKind")

      PanelGroupTitle(text: "K 线")
      PanelRow(name: "网格") {
        PanelSegment(options: ChartPanel.grids, selection: prefs.gridChoice) { v in
          store.update { $0.gridChoice = v }
        }
      }
      .accessibilityIdentifier("chart.gridChoice")
      PanelRow(name: "阳线") {
        PanelSegment(options: ChartPanel.bodies, selection: prefs.bodyChoice) { v in
          store.update { $0.bodyChoice = v }
        }
      }
      .accessibilityIdentifier("chart.bodyChoice")
      PanelRow(name: "横向位置") {
        PanelSegment(options: ChartPanel.anchors, selection: prefs.viewAnchor) { v in
          store.update { $0.viewAnchor = v }
        }
      }
      .accessibilityIdentifier("chart.viewAnchor")
      PanelRow(name: "纵向位置", divider: false) {
        PanelSegment(options: ChartPanel.biases, selection: prefs.priceBias) { v in
          store.update { $0.priceBias = v }
        }
      }
      .accessibilityIdentifier("chart.priceBias")

      PanelGroupTitle(text: "显示")
      switchRow("实时价格线", nil, prefs.lastLine) { $0.lastLine = $1 }
        .accessibilityIdentifier("chart.lastLine")
      // 同一个字段在「设置」面板里也有一行。那边留着不动：两处改的是同一个
      // `countdown`，谁改都一样，不会出现两个开关各说各话。
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
  }

  // MARK: - 行

  private func switchRow(_ name: String, _ meta: String?, _ on: Bool, divider: Bool = true,
                         _ set: @escaping (inout Prefs, Bool) -> Void) -> some View {
    PanelRow(name: name, meta: meta, divider: divider) {
      PanelSwitch(isOn: on) { store.update { set(&$0, !on) } }
    }
  }

  // MARK: - 分段选项

  /// 字面写在这儿而不是取枚举的 `display`：面板上要的是短词（「空心」），
  /// 枚举那边给的是完整名字（「阳线空心」），两处用途不同，和 `SettingsPanel` 一个办法。
  static let kinds: [(String, CandleKind)] = [("蜡烛", .candle), ("平均K线", .heikin)]
  static let grids: [(String, GridChoice)] = [("显示", .on), ("隐藏", .off)]
  static let bodies: [(String, BodyChoice)] = [("跟随风格", .style), ("实心", .solid), ("空心", .hollowUp)]
  static let anchors: [(String, ViewAnchor)] = [("偏左", .left), ("居中", .center), ("靠右", .right)]
  static let biases: [(String, PriceBias)] = [("偏上", .up), ("居中", .center), ("偏下", .down)]
}

#Preview("图表") {
  PanelPreviewHost { store in ChartPanel(store: store) }
}
