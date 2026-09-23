import KanpanCore

/// 「涨到 A 或跌到 B」这句话怎么拼。拆出来是为了能单测，也免得视图里堆算术。
struct LineAlertPhrase: Equatable {
  /// 这条线此刻所在的价（通道、矩形、回撤会有好几条）。线段已经走完或还没开始时为空。
  var targets: [Double]
  var current: Double?
  var decimals: Int?

  /// 现价上方最近的那一条。
  var above: Double? {
    guard let current else { return nil }
    return targets.filter { $0 >= current }.min()
  }

  /// 现价下方最近的那一条。
  var below: Double? {
    guard let current else { return nil }
    return targets.filter { $0 < current }.max()
  }

  /// 不带「叫我 / 叫你」的那半句：「跌到 64,000」「涨到 A 或跌到 B」「碰到这条线」。
  var target: String {
    guard !targets.isEmpty else { return "碰到这条线" }
    guard current != nil else {
      return targets.count == 1 ? "到 \(text(targets[0]))" : "碰到这条线"
    }
    switch (above, below) {
    case let (a?, b?): return "涨到 \(text(a)) 或跌到 \(text(b))"
    case let (a?, nil): return "涨到 \(text(a))"
    case let (nil, b?): return "跌到 \(text(b))"
    default: return "碰到这条线"
    }
  }

  /// 离现价最近的那条还差多少，按现价的百分比；两头都有线时不写（写哪一头都偏）。
  var distance: String? {
    guard let current, current > 0 else { return nil }
    let near: Double
    switch (above, below) {
    case let (a?, nil): near = a
    case let (nil, b?): near = b
    default: return nil
    }
    let pct = abs(near - current) / current * 100
    return pct < 0.01 ? "就在现价" : String(format: "还差 %.2f%%", pct)
  }

  /// 千分位和头部那口价一个写法（`HeaderStats.grouped`）：胶囊是给人读的一句话，
  /// 不是价格轴那种密排读数；同一屏上头部写 86,781.5、胶囊写 84379.2 就对不上眼。
  /// 这个文件也编进 KanpanAlerts 的测试包，那边够不着 app 里的 `grouped`，所以就地插。
  private func text(_ v: Double) -> String {
    let raw = ReviewLabels.price(v, decimals: decimals)
    let parts = raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    guard let head = parts.first else { return raw }
    let neg = head.hasPrefix("-")
    let digits = Array(neg ? head.dropFirst() : head)
    guard digits.count > 3, digits.allSatisfy(\.isNumber) else { return raw }
    var out = ""
    for (i, d) in digits.enumerated() {
      if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
      out.append(d)
    }
    return (neg ? "-" : "") + out + (parts.count > 1 ? "." + parts[1] : "")
  }
}
