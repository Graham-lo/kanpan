import Foundation

/// 增量重算的几条基础线。
///
/// 末根一变就整段重算是浪费：一屏 2000 根、十几条线，120 Hz 下每帧都算不划算。
/// 这里的每种线都记住了自己的递推状态（滑动窗的累加和、EMA 的前一个值），
/// 所以「只重算最后 N 根」和「从头算一遍」得到的是**同一串浮点数**，不是近似值。

/// 滑动窗均值。累加和逐根存下来，尾部重算才能接着上一根的和继续，和全量逐位相同。
struct SMALine: Sendable, Equatable {
  var n: Int
  /// 跳过前导 NaN 用：从这一根开始才是真正的输入（`smaSkip`）。
  var offset: Int
  var out: [Double]
  var sum: [Double]

  init(_ src: [Double], _ n: Int, offset: Int = 0) {
    self.n = n
    self.offset = offset
    out = nanArray(src.count)
    sum = nanArray(src.count)
    recompute(src, from: offset)
  }

  /// 从 `start` 往后重算。`start <= offset` 就是全量。
  mutating func recompute(_ src: [Double], from start: Int) {
    if out.count < src.count {
      out.append(contentsOf: nanArray(src.count - out.count))
      sum.append(contentsOf: nanArray(src.count - sum.count))
    }
    guard n >= 1, offset < src.count else { return }
    let begin = max(offset, start)
    var s = begin > offset ? sum[begin - 1] : 0
    for i in begin..<src.count {
      s += src[i]
      let k = i - offset
      if k >= n { s -= src[i - n] }
      sum[i] = s
      out[i] = k >= n - 1 ? s / Double(n) : .nan
    }
  }

  /// 尾部重算的最早起点：要能拿到上一根的累加和。
  ///
  /// `start - 1` 必须真的在已算好的那段里：起点是 0（首根就是被改的那根）时没有上一根，
  /// 起点跑到 `sum` 之外时（序列一次长了好几根，状态还停在旧长度）那个种子也不存在。
  /// 两种都返回假，调用方会整条重建。
  func canTail(from start: Int) -> Bool {
    start > offset && start >= 1 && start - 1 < sum.count && sum[start - 1].isFinite
  }
}

/// EMA / RMA 这类一阶递推线。
struct RecursiveLine: Sendable, Equatable {
  enum Kind: Sendable { case ema, rma }
  var kind: Kind
  var n: Int
  var offset: Int
  var out: [Double]

  init(_ src: [Double], _ n: Int, kind: Kind, offset: Int = 0) {
    self.kind = kind
    self.n = n
    self.offset = offset
    out = nanArray(src.count)
    full(src)
  }

  private mutating func full(_ src: [Double]) {
    let count = src.count - offset
    guard count >= n, n >= 1 else { return }
    var sum = 0.0
    for i in 0..<n { sum += src[offset + i] }
    var prev = sum / Double(n)
    out[offset + n - 1] = prev
    for i in (offset + n)..<src.count {
      prev = step(prev, src[i])
      out[i] = prev
    }
  }

  private func step(_ prev: Double, _ x: Double) -> Double {
    switch kind {
    case .ema:
      let k = 2 / Double(n + 1)
      return x * k + prev * (1 - k)
    case .rma:
      return (prev * Double(n - 1) + x) / Double(n)
    }
  }

  mutating func recompute(_ src: [Double], from start: Int) {
    if out.count < src.count { out.append(contentsOf: nanArray(src.count - out.count)) }
    guard canTail(from: start) else { out = nanArray(src.count); full(src); return }
    var prev = out[start - 1]
    for i in start..<src.count {
      prev = step(prev, src[i])
      out[i] = prev
    }
  }

  /// 同 `SMALine.canTail`。这里还多挡一层：`n <= 0` 这种脏参数会让 `start > offset + n - 1`
  /// 对起点 0 成立，接着 `out[start - 1]` 就是 `out[-1]`。
  func canTail(from start: Int) -> Bool {
    start > offset + n - 1 && start >= 1 && start - 1 < out.count && out[start - 1].isFinite
  }
}
