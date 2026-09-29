// 移植自 KanpanCore/Sources/KanpanCore/Indicator/Indicators.swift
//
// 裸函数版的五把指标（全量算，不带增量状态）。引擎里各 State 的全量路径与这些逐位相同，
// 黄金值测试两边都比。

import { ema, hhv, llv, nanArray, rma, sma, swiftMax } from './math'

/** 布林：mid = SMA(n)，上下轨 = mid ± k·σ（总体标准差）。 */
export function boll(close: number[], n: number, k: number): { mid: number[]; up: number[]; dn: number[] } {
  const mid = sma(close, n)
  const up = nanArray(close.length)
  const dn = nanArray(close.length)
  if (!(n >= 1 && close.length >= n)) return { mid, up, dn }
  for (let i = n - 1; i < close.length; i++) {
    let s = 0.0
    for (let j = i - n + 1; j <= i; j++) {
      const d = close[j] - mid[i]
      s += d * d
    }
    const sd = Math.sqrt(s / n)
    up[i] = mid[i] + k * sd
    dn[i] = mid[i] - k * sd
  }
  return { mid, up, dn }
}

/**
 * MACD：dif = EMA(f) - EMA(s)，dea = EMA(dif, sig)，柱 = 2·(dif - dea)。
 * DEA 从 DIF 真正开始的地方起算，否则前面一段 NaN 会把均线拖坏。
 */
export function macd(close: number[], fast: number, slow: number, sig: number): { dif: number[]; dea: number[]; hist: number[] } {
  const f = ema(close, fast)
  const s = ema(close, slow)
  const dif = nanArray(close.length)
  for (let i = 0; i < close.length; i++) if (Number.isFinite(f[i]) && Number.isFinite(s[i])) dif[i] = f[i] - s[i]
  const dea = nanArray(close.length)
  const start = dif.findIndex(Number.isFinite)
  if (start >= 0) {
    const tail = ema(dif.slice(start), sig)
    for (let i = 0; i < tail.length; i++) dea[start + i] = tail[i]
  }
  const hist = nanArray(close.length)
  for (let i = 0; i < close.length; i++) if (Number.isFinite(dif[i]) && Number.isFinite(dea[i])) hist[i] = (dif[i] - dea[i]) * 2
  return { dif, dea, hist }
}

/** RSI：`100 - 100/(1 + RMA(gain)/RMA(loss))`。 */
export function rsi(close: number[], n: number): number[] {
  if (!close.length) return []
  const up = nanArray(close.length)
  const dn = nanArray(close.length)
  up[0] = 0; dn[0] = 0
  for (let i = 1; i < close.length; i++) {
    const d = close[i] - close[i - 1]
    up[i] = d > 0 ? d : 0
    dn[i] = d < 0 ? -d : 0
  }
  const au = rma(up, n)
  const ad = rma(dn, n)
  const out = nanArray(close.length)
  for (let i = 0; i < close.length; i++) {
    if (Number.isFinite(au[i])) out[i] = ad[i] === 0 ? 100 : 100 - 100 / (1 + au[i] / ad[i])
  }
  return out
}

/** KDJ：RSV 用 1/3 递推平滑，K、D 从 50 起步，前 n-1 根不出值。 */
export function kdj(high: number[], low: number[], close: number[], n: number, kn: number, dn2: number): { k: number[]; d: number[]; j: number[] } {
  const K = nanArray(close.length), D = nanArray(close.length), J = nanArray(close.length)
  let k = 50.0, d = 50.0
  if (!(close.length > 0 && n >= 1 && kn >= 1 && dn2 >= 1)) return { k: K, d: D, j: J }
  for (let i = 0; i < close.length; i++) {
    const hi = hhv(high, n, i), lo = llv(low, n, i)
    const rsv = hi === lo ? 50 : ((close[i] - lo) / (hi - lo)) * 100
    k = ((kn - 1) * k + rsv) / kn
    d = ((dn2 - 1) * d + k) / dn2
    if (i >= n - 1) { K[i] = k; D[i] = d; J[i] = 3 * k - 2 * d }
  }
  return { k: K, d: D, j: J }
}

/** ATR：`TR = max(h-l, |h-c₋₁|, |l-c₋₁|)` 再 RMA(n)。 */
export function atr(high: number[], low: number[], close: number[], n: number): number[] {
  if (!close.length) return []
  const tr = nanArray(close.length)
  tr[0] = high[0] - low[0]
  for (let i = 1; i < close.length; i++) {
    tr[i] = swiftMax(high[i] - low[i], swiftMax(Math.abs(high[i] - close[i - 1]), Math.abs(low[i] - close[i - 1])))
  }
  return rma(tr, n)
}
