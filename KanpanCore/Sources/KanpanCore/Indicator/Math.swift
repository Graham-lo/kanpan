import Foundation

/// 指标的基础平滑。全部是纯函数，输入列数组、输出等长数组，前导用 `NaN`。
/// 逐行对应原型 `chart.js`，黄金值测试直接拿原型输出比（误差 ≤ 1e-9）。
@inlinable
func nanArray(_ n: Int) -> [Double] { [Double](repeating: .nan, count: n) }

/// 滑动窗均值。窗内含 NaN 则之后一路 NaN（和原型的累加写法一致）。
public func sma(_ src: [Double], _ n: Int) -> [Double] {
  var out = nanArray(src.count)
  guard n >= 1 else { return out }
  var sum = 0.0
  for i in 0..<src.count {
    sum += src[i]
    if i >= n { sum -= src[i - n] }
    if i >= n - 1 { out[i] = sum / Double(n) }
  }
  return out
}

/// 用前 n 根的均值起步，和 TradingView 一个口径。
public func ema(_ src: [Double], _ n: Int) -> [Double] {
  var out = nanArray(src.count)
  guard src.count >= n, n >= 1 else { return out }
  let k = 2 / Double(n + 1)
  var sum = 0.0
  for i in 0..<n { sum += src[i] }
  var prev = sum / Double(n)
  out[n - 1] = prev
  for i in n..<src.count {
    prev = src[i] * k + prev * (1 - k)
    out[i] = prev
  }
  return out
}

/// Wilder 的平滑（RSI、ATR 用的那种，衰减比 EMA 慢一半）。
public func rma(_ src: [Double], _ n: Int) -> [Double] {
  var out = nanArray(src.count)
  guard src.count >= n, n >= 1 else { return out }
  var sum = 0.0
  for i in 0..<n { sum += src[i] }
  var prev = sum / Double(n)
  out[n - 1] = prev
  for i in n..<src.count {
    prev = (prev * Double(n - 1) + src[i]) / Double(n)
    out[i] = prev
  }
  return out
}

/// 会跳过前面 NaN 的简单均线（原型 `smaSkip`）。
public func smaSkip(_ src: [Double], _ n: Int) -> [Double] {
  var out = nanArray(src.count)
  guard let start = src.firstIndex(where: { $0.isFinite }) else { return out }
  let tail = sma(Array(src[start...]), n)
  for i in 0..<tail.count { out[start + i] = tail[i] }
  return out
}

@inlinable
func hhv(_ src: [Double], _ n: Int, _ i: Int) -> Double {
  var m = -Double.infinity
  for j in max(0, i - n + 1)...i where src[j] > m { m = src[j] }
  return m
}

@inlinable
func llv(_ src: [Double], _ n: Int, _ i: Int) -> Double {
  var m = Double.infinity
  for j in max(0, i - n + 1)...i where src[j] < m { m = src[j] }
  return m
}
