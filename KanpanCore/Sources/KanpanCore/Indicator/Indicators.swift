import Foundation

/// 布林：mid = SMA(n)，上下轨 = mid ± k·σ（总体标准差）。
public func boll(_ close: [Double], _ n: Int, _ k: Double) -> (mid: [Double], up: [Double], dn: [Double]) {
  let mid = sma(close, n)
  var up = nanArray(close.count)
  var dn = nanArray(close.count)
  guard n >= 1, close.count >= n else { return (mid, up, dn) }
  for i in (n - 1)..<close.count {
    var s = 0.0
    for j in (i - n + 1)...i {
      let d = close[j] - mid[i]
      s += d * d
    }
    let sd = (s / Double(n)).squareRoot()
    up[i] = mid[i] + k * sd
    dn[i] = mid[i] - k * sd
  }
  return (mid, up, dn)
}

/// MACD：dif = EMA(f) - EMA(s)，dea = EMA(dif, sig)，柱 = 2·(dif - dea)。
/// DEA 从 DIF 真正开始的地方起算，否则前面一段 NaN 会把均线拖坏。
public func macd(_ close: [Double], _ fast: Int, _ slow: Int, _ sig: Int)
  -> (dif: [Double], dea: [Double], hist: [Double]) {
  let f = ema(close, fast)
  let s = ema(close, slow)
  var dif = nanArray(close.count)
  for i in 0..<close.count where f[i].isFinite && s[i].isFinite { dif[i] = f[i] - s[i] }
  var dea = nanArray(close.count)
  if let start = dif.firstIndex(where: { $0.isFinite }) {
    let tail = ema(Array(dif[start...]), sig)
    for i in 0..<tail.count { dea[start + i] = tail[i] }
  }
  var hist = nanArray(close.count)
  for i in 0..<close.count where dif[i].isFinite && dea[i].isFinite { hist[i] = (dif[i] - dea[i]) * 2 }
  return (dif, dea, hist)
}

/// RSI：`100 - 100/(1 + RMA(gain)/RMA(loss))`。
public func rsi(_ close: [Double], _ n: Int) -> [Double] {
  guard !close.isEmpty else { return [] }
  var up = nanArray(close.count)
  var dn = nanArray(close.count)
  up[0] = 0; dn[0] = 0
  for i in 1..<close.count {
    let d = close[i] - close[i - 1]
    up[i] = d > 0 ? d : 0
    dn[i] = d < 0 ? -d : 0
  }
  let au = rma(up, n)
  let ad = rma(dn, n)
  var out = nanArray(close.count)
  for i in 0..<close.count where au[i].isFinite {
    out[i] = ad[i] == 0 ? 100 : 100 - 100 / (1 + au[i] / ad[i])
  }
  return out
}

/// KDJ：RSV 用 1/3 递推平滑，K、D 从 50 起步，前 n-1 根不出值。
public func kdj(_ high: [Double], _ low: [Double], _ close: [Double], _ n: Int, _ kn: Int, _ dn2: Int)
  -> (k: [Double], d: [Double], j: [Double]) {
  var K = nanArray(close.count), D = nanArray(close.count), J = nanArray(close.count)
  var k = 50.0, d = 50.0
  guard !close.isEmpty, n >= 1, kn >= 1, dn2 >= 1 else { return (K, D, J) }
  for i in 0..<close.count {
    let hi = hhv(high, n, i), lo = llv(low, n, i)
    let rsv = hi == lo ? 50 : ((close[i] - lo) / (hi - lo)) * 100
    k = (Double(kn - 1) * k + rsv) / Double(kn)
    d = (Double(dn2 - 1) * d + k) / Double(dn2)
    if i >= n - 1 { K[i] = k; D[i] = d; J[i] = 3 * k - 2 * d }
  }
  return (K, D, J)
}

/// ATR：`TR = max(h-l, |h-c₋₁|, |l-c₋₁|)` 再 RMA(n)。
public func atr(_ high: [Double], _ low: [Double], _ close: [Double], _ n: Int) -> [Double] {
  guard !close.isEmpty else { return [] }
  var tr = nanArray(close.count)
  tr[0] = high[0] - low[0]
  for i in 1..<close.count {
    tr[i] = max(high[i] - low[i], max(abs(high[i] - close[i - 1]), abs(low[i] - close[i - 1])))
  }
  return rma(tr, n)
}
