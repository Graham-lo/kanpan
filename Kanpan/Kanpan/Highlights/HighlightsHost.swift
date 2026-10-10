import KanpanCore
import KanpanNetwork
import SwiftUI
import UIKit

// 「盘口要点」挂到行情页上的两块接线。都是非泛型 struct：`MainScreen` 那条 body 链有类型嵌套上限
// （见 `MainScreen.swift` 文件头），观察者和测量不许接回 `chartPage` 上。

/// 行情画布下沿的入口条 + 轮询。入口条在才拉（行情页、竖屏、非复盘非画线、这只有订单流）。
struct HighlightsEntryHost: View {
  let model: HighlightsModel
  let market: MarketModel
  let open: () -> Void

  var body: some View {
    let norm = OrderFlowBase.normalize(market.info.base)
    HighlightsEntryStrip(model: model, price: market.ticker.map { $0.last / norm.scale }, open: open)
      // 半页开关也进 id：一打开就立刻拉一轮新的，节奏换成 30 秒。
      .task(id: "\(norm.base)|\(model.open)") {
        model.scale = norm.scale
        model.decimals = market.info.priceDecimals
        let catalog = market.highlightsCatalog
        await model.poll(base: norm.base) { await catalog.highlights(base: $0) }
      }
  }

  /// 图上那条带子只画在出它的那只品种上（换到没有订单流的品种时入口条不在、轮询不跑，旧带子不能留着）。
  @MainActor static func band(_ model: HighlightsModel, market: MarketModel) -> HighlightBand? {
    guard model.band != nil, model.base == OrderFlowBase.normalize(market.info.base).base else { return nil }
    return model.band
  }
}

/// 行情头：量它的下沿（泛型只多套一层 `HighlightsHeaderGuard<…>`，修饰符在它自己的 body 里，不进主链）定半页高度（屏高 − 头部下沿，价格、涨跌、六格一直露着）；半页开着时点头部只收半页
/// （头部上的按钮此刻不接，免得在半页上面再叠一层）。
struct HighlightsHeaderGuard<Header: View>: View {
  let header: Header
  let model: HighlightsModel

  var body: some View {
    header
      .onGeometryChange(for: CGFloat.self) { g in g.frame(in: .global).maxY } action: { bottom in
        model.noteHeader(bottom: bottom, screen: Self.screenHeight)
      }
      .overlay {
        if model.open {
          Color.clear.contentShape(Rectangle())
            .onTapGesture { model.open = false }
            .accessibilityHidden(true)
        }
      }
  }

  @MainActor private static var screenHeight: CGFloat {
    let scene = UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first
    guard let bounds = scene?.screen.bounds else { return 0 }
    return max(bounds.width, bounds.height)
  }
}
