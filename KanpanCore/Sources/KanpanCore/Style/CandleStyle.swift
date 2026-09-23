import Foundation

/// 蜡烛的造型。尺寸、坐标轴、布局与手势都在共用的图表基座里，这里只管「长什么样」。
///
/// 这里原来摆着十二套：AICoin 一套，加上从原型带过来的十一款（墩／靛／辉／阔／砖／针／
/// 芯／纸／描／骨／密），「图表」面板上还有一张四选一的风格卡。用户 2026-09-15 定了：
/// 「k 线风格直接默认 aicoin 那套就行了，不用搞那么多套」。于是只剩 AICoin 这一套：
/// 影线与实体同色、平头、实体直角、默认不画网格（审查 2026-09-24 §3.1 把风格表的
/// 圆角 / 描边 / 刻度网格 / 影线兑淡分支一并删掉）。剩下的两个维度都是「图表」面板上
/// 用户自己选的：阳线实心还是空心（`BodyChoice`），网格开还是关（`GridChoice`）。
public enum CandleStyle {
  /// 实体画法。`hollowUp` 是阳线描边、阴线实心。
  public enum Shape: String, Sendable, Codable { case solid, hollowUp }
  /// 价格网格。`both` 横竖都画，`none` 不画。
  public enum Grid: String, Sendable, Codable { case both, none }
}
