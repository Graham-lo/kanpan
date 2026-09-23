import KanpanCore
import SwiftUI

/// 某只品种此刻的价，新建价格提醒时用。宿主按用户打的代号查出来（`MainScreen.alertQuote`）。
struct PriceAlertQuote: Equatable {
  /// 规范键（`binance/usd_m/ETHUSDT`；「ETH」会被认成这一只）。框里给人看的是代号，
  /// 提交时交出去的是它。
  var symbol: String
  var price: Double?
  var decimals: Int?

  func label(_ value: Double) -> String { ReviewLabels.price(value, decimals: decimals) }
  /// 页上「当前 xxx」那口现价：和行情页头部那口价同一个写法——小数位由品种说
  /// （`decimals`），整数部分插千分位（`grouped`，头部 `TopBar.lastText` 用的就是它）。
  /// 同一只 BTC，头部写 86,781.5、这里写 86781.50 就对不上眼（审查 D3）。
  /// 提醒标题（`label`）不插千分位：它和用户手打的那串数要一眼对得上。
  func current(_ value: Double) -> String { grouped(label(value)) }
}

/// 提醒总表右上「新建」进来的那一页（P3.1）：一只品种、一个价，别的都不问。
///
/// - 品种默认就是图上那只，框里填的是给人看的代号（`BTCUSDT`、`BTC/USD`），不是内部的规范键
///   （`binance/usd_m/BTCUSDT`）；规范键只在宿主解析、提交时才出现。能改（打「ETH」就认成
///   `ETHUSDT`），点进框里整串全选，直接打就是覆盖；锁英文键盘（`kanpan-symbol-search-keyboard`）。
/// - 价格是手动输入框、等宽数字，不给加减步进器（`kanpan-no-steppers-use-text-fields`）。
/// - **方向不让选**：比现价高就是「涨到」，低就是「跌到」，由 `Alert.price` 按建的那一刻的
///   现价定；这页上只有一行小字「当前 xxx」让人知道自己在跟谁比。
struct PriceAlertForm: View {
  /// 图上那只给人看的代号（宿主交的是 `InstrumentID.display`）。
  var initialSymbol: String
  /// 按用户打的字查品种与现价；查不到这只品种返回 nil。
  var resolve: (String) -> PriceAlertQuote?
  /// 品种定下来之后叫一声：宿主去要一口价（不在自选里的品种报价簿手上没有）。
  var prepare: (String) -> Void = { _ in }
  var onCreate: (PriceAlertQuote, Double) -> Void

  @State private var symbolText = ""
  @State private var symbolSelection: TextSelection?
  @State private var priceText = ""
  @FocusState private var focus: Field?
  @Environment(\.panelTheme) private var t
  @Environment(\.dismiss) private var dismiss

  private enum Field: Hashable { case symbol, price }

  var body: some View {
    let quote = resolve(symbolText)
    PanelSheet(title: "新建提醒", subtitle: nil) {
      field("品种") {
        TextField("", text: $symbolText, selection: $symbolSelection)
          .keyboardType(.asciiCapable)
          .textInputAutocapitalization(.characters)
          .autocorrectionDisabled()
          .focused($focus, equals: .symbol)
          .accessibilityIdentifier("alerts.new.symbol")
          .accessibilityLabel("品种")
      }
      field("价格") {
        TextField("", text: $priceText)
          .keyboardType(.decimalPad)
          .focused($focus, equals: .price)
          .accessibilityIdentifier("alerts.new.price")
          .accessibilityLabel("价格")
      }
      HStack {
        Text(currentLine(quote))
          .font(PanelFont.meta).monospacedDigit()
          .foregroundStyle(t.ink3)
          .accessibilityIdentifier("alerts.new.current")
        Spacer(minLength: 0)
      }
      .padding(.horizontal, PanelMetrics.hPad)
      .padding(.top, 8)
      Button {
        guard let quote, let target else { return }
        onCreate(quote, target)
        dismiss()
      } label: {
        Text("加提醒")
          .font(.scaled(15, .semibold))
          .foregroundStyle(t.badgeInk)
          .frame(maxWidth: .infinity)
          .frame(height: 42)
          .background(Capsule().fill(t.amber))
          .opacity(quote != nil && target != nil ? 1 : 0.4)
      }
      .buttonStyle(.plain)
      .disabled(quote == nil || target == nil)
      .padding(.horizontal, PanelMetrics.hPad)
      .padding(.top, 16)
      .accessibilityIdentifier("alerts.new.create")
    }
    .toolbar(.hidden, for: .navigationBar)
    .onAppear {
      if symbolText.isEmpty { symbolText = initialSymbol }
      // 要价按宿主解析出来的规范键要；框里的代号（尤其 `BTC/USD`）直接交出去会被当成币安的裸代号。
      prepare(resolve(symbolText)?.symbol ?? initialSymbol)
      focus = .price
    }
    // 点进品种框就把整串选中：想换一只直接打，不用先删。等这一拍的光标落定再选，
    // 否则点按落下的插入点会把选区盖掉。
    .onChange(of: focus) { _, field in
      guard field == .symbol else { return }
      Task { @MainActor in
        symbolSelection = TextSelection(range: symbolText.startIndex..<symbolText.endIndex)
      }
    }
    .onChange(of: quote?.symbol) { _, symbol in if let symbol { prepare(symbol) } }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("alerts.new.page")
  }

  /// 用户打的价。逗号当千分位扔掉；非正数、读不出来的都不算。
  private var target: Double? {
    let text = priceText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
    guard let value = Double(text), value.isFinite, value > 0 else { return nil }
    return value
  }

  private func currentLine(_ quote: PriceAlertQuote?) -> String {
    guard let quote else { return symbolText.isEmpty ? " " : "没有这只品种" }
    guard let price = quote.price else { return "当前 —" }
    return "当前 " + quote.current(price)
  }

  private func field<Input: View>(_ label: String, @ViewBuilder input: () -> Input) -> some View {
    HStack(spacing: 12) {
      Text(label).font(PanelFont.name).foregroundStyle(t.ink)
      Spacer(minLength: 8)
      input()
        .multilineTextAlignment(.trailing)
        .font(.body.monospacedDigit())
        .foregroundStyle(t.ink)
        .frame(width: 150)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(t.raised2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    .padding(.horizontal, PanelMetrics.hPad)
    .frame(minHeight: 48)
    .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 0.5).padding(.leading, PanelMetrics.hPad) }
  }
}
