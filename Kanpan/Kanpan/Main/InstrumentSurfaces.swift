import Foundation
import KanpanCore
import KanpanNetwork

/// 一只品种的行情页上**哪几块该摆出来**——只看能力位与品种类别，不看眼前有没有数。
///
/// 两条规则都是「永远给不出的东西干脆不摆」，和「这一刻还没到 / 断流了」分开：
/// 后者照常摆着写「—」（新数据一到就亮回来），前者摆出来只是一块噪音。
///
/// 指标布局（`prefs.subs` / `prefs.overlays`）跟人走，这儿只过滤画出来的那一帧，
/// 一个字不改——切回有这类数据的品种，它们原样回来。
enum InstrumentSurfaces {
  /// 头部右侧那块（仓 / 额 · 市值 / 费率 · 结算 / 估值）有没有**哪一格可能有数**。
  ///
  /// * 仓：要有持仓量；额：要有成交量；费率、结算：要有资金费率；
  /// * 市值、估值：只有币和股票有（总供应量、估值底数都是后端按这两类给的）。
  ///
  /// 一格都给不出（美元指数）就整块不摆，左边价格区照常、图表把这块高度收回去。
  /// 只按能力判，不按眼前的值判：币在加载中、断流时那几格是「—」，块照样在。
  static func showsHeaderStats(capabilities caps: ProviderCapabilities,
                               asset: SymbolClassification.Asset) -> Bool {
    if caps.hasVolume || caps.hasFunding || caps.hasOpenInterest { return true }
    switch asset {
    case .crypto, .equity: return true
    case .preciousMetal, .commodity, .index, .preMarket, .other: return false
    }
  }

  /// 画出来的副图。
  ///
  /// * 整个市场没有持仓量、也没有任何衍生统计（现货、指数）：外部指标那几格不画；
  /// * 没有成交量（指数）：成交量（连均量）、量差不画。
  ///
  /// 其余顺序原样。线路暂时给不了的外部指标不在这儿管，那是空态。
  static func subs(_ subs: [IndicatorID], capabilities caps: ProviderCapabilities) -> [IndicatorID] {
    let noExternal = !caps.hasOpenInterest && !caps.hasOpenInterestHistory && !caps.hasDerivativeMetrics
    return subs.filter { id in
      if noExternal, id.isExternal { return false }
      if !caps.hasVolume, id.needsVolume { return false }
      return true
    }
  }

  /// 画出来的主图叠加：没有成交量时均价线（VWAP）不画，其余原样。
  static func overlays(_ overlays: [IndicatorID], capabilities caps: ProviderCapabilities) -> [IndicatorID] {
    caps.hasVolume ? overlays : overlays.filter { !$0.needsVolume }
  }
}
