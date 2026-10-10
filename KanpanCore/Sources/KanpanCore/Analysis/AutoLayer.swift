/// 自动分析图层的白名单：由算法自动画在图上、用户只管开关的那几样（不是指标，不进 `IndicatorID`）。
/// rawValue 是偏好与同步里存的名字，三端一致；读到不认识的名字一律丢弃。
public enum AutoLayer: String, CaseIterable, Codable, Sendable {
  /// 公允价值缺口。
  case fvg = "FVG"
}
