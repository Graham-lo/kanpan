import Combine
import KanpanCore
import SwiftUI

/// 选中一条线时，画线栏上那句「跌到 64,000 叫我」。
///
/// 2026-09-23 起给线加提醒只有这一个入口，取代原来那句「画完线问一下、六秒后自己消失」：
///
/// - **不问。** 画完线什么都不弹。做分析的人连画五条也不会被打断，不想要提醒就别点它。
/// - **随时能加。** 任何一条旧线，点选中之后这句话都在。原来错过那六秒，这条线就再也
///   加不上提醒了。
/// - **用人话说清到哪个价会响。** 线在现价上面写「涨到」，在下面写「跌到」，打开之后
///   再补一句「还差 1.8%」。拖线的时候这个价跟着手指实时变（`dragging`）。
/// - **点一下开，再点一下关。** 关就是把这条提醒删掉；「已响过」或「已暂停」的
///   按关着显示，再点一下就重新布防，从现在起算。
///
/// 「价格达到 / 收盘穿过」这里不加选项（默认价格达到）；响过一次就删（2026-09-25 v3，`AlertWatcher`），
/// 没有「再次提醒」——要再盯就再点一下铃铛重新挂。
@MainActor
final class LineAlertModel: ObservableObject {
  /// 手指正拖着的那条线（画线控制器逐帧喂进来），抬手回到 nil。
  @Published private(set) var dragging: Drawing?
  /// 图上那只品种的最新价。只存一只：胶囊只在那只品种的图上出现。
  @Published private(set) var quote: (symbol: String, price: Double)?

  /// 品种要几位小数，问不到就按价格自己猜。
  var decimals: (String) -> Int? = { _ in nil }
  /// 第一次打开提醒时要通知权限。问不到也照样建，只是后台不会弹。
  var onArmed: () -> Void = {}

  private(set) weak var store: AlertStore?
  private var storeChange: AnyCancellable?

  func attach(_ store: AlertStore) {
    self.store = store
    // 提醒存档变了（包括云端推下来的、提醒总表里删掉的），胶囊的开关状态要跟着变。
    storeChange = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
  }

  func observe(symbol: String, price: Double) {
    guard price.isFinite, price > 0 else { return }
    if let quote, quote.symbol == symbol, quote.price == price { return }
    quote = (symbol, price)
  }

  func drag(_ item: Drawing?) {
    guard dragging != item else { return }
    dragging = item
  }

  /// 这条线此刻按什么几何算：正在拖就用拖到的那一版。
  func live(_ drawing: Drawing) -> Drawing {
    if let dragging, dragging.id == drawing.id { return dragging }
    return drawing
  }

  func isOn(_ drawing: Drawing, symbol: String) -> Bool {
    store?.alert(symbol: symbol, drawingID: drawing.id)?.status == .active
  }

  func toggle(_ drawing: Drawing, symbol: String) {
    guard let store, !symbol.isEmpty else { return }
    if isOn(drawing, symbol: symbol) {
      store.remove(symbol: symbol, drawingID: drawing.id)
    } else {
      guard store.add(drawing: drawing, symbol: symbol) != nil else { return }
      onArmed()
    }
  }

  /// 胶囊上那句话。`nil` 表示这种线不能设提醒，胶囊不出现。
  func phrase(for drawing: Drawing, symbol: String, now: Date = Date()) -> LineAlertPhrase? {
    guard let lines = AlertGeometry.lines(for: live(drawing)) else { return nil }
    let t = now.timeIntervalSince1970 * 1000
    let current = quote?.symbol == symbol ? quote?.price : nil
    return LineAlertPhrase(targets: lines.compactMap { $0.price(at: t) }, current: current,
                           decimals: decimals(symbol))
  }
}

/// 胶囊本身。竖屏它顶替画线栏下排的收藏工具（选中期间），横屏顶替选中栏左边的线名。
struct LineAlertChip: View {
  @ObservedObject var model: LineAlertModel
  var drawing: Drawing
  var symbol: String
  @Environment(\.panelTheme) private var theme

  var body: some View {
    // 趋势线的价随时间走，现价随行情走——一秒刷一次就够，胶囊不在场时这条时间线也不跑。
    TimelineView(.periodic(from: .now, by: 1)) { context in
      if let phrase = model.phrase(for: drawing, symbol: symbol, now: context.date) {
        chip(phrase, on: model.isOn(drawing, symbol: symbol))
      }
    }
  }

  private func chip(_ phrase: LineAlertPhrase, on: Bool) -> some View {
    Button { model.toggle(drawing, symbol: symbol) } label: {
      // 「还差 x%」放得下才带；放不下整段不要，不留半截「还差 3.…」。
      ViewThatFits(in: .horizontal) {
        chipLine(phrase, on: on, distance: on ? phrase.distance : nil)
        chipLine(phrase, on: on, distance: nil)
      }
      .foregroundStyle(on ? theme.badgeInk : theme.amber)
      .padding(.horizontal, 12)
      .frame(height: 32)
      .background(Capsule().fill(on ? theme.amber : theme.amberSoft))
      .overlay(Capsule().strokeBorder(on ? .clear : theme.amberLine, lineWidth: 0.5))
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .animation(.easeOut(duration: 0.15), value: on)
    .sensoryFeedback(.selection, trigger: on)
    .accessibilityLabel(phrase.target + (on ? " 会提醒" : " 提醒我"))
    .accessibilityValue(on ? "on" : "off")
    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    .accessibilityIdentifier("alert.line")
  }

  private func chipLine(_ phrase: LineAlertPhrase, on: Bool, distance: String?) -> some View {
    HStack(spacing: 6) {
      Image(systemName: on ? "bell.fill" : "bell")
        .font(.system(size: 12, weight: .semibold))
      Text(phrase.target + (on ? " 会叫你" : " 叫我"))
        .font(.system(size: 13, weight: on ? .semibold : .regular))
        .lineLimit(1).minimumScaleFactor(0.8)
      if let distance {
        Text("· " + distance)
          .font(.system(size: 12).monospacedDigit())
          .opacity(0.8)
          .lineLimit(1).fixedSize()
      }
    }
  }
}
