// 移植自 KanpanCore/Sources/KanpanCore/Indicator/Math.swift
//
// 指标的基础平滑。全部是纯函数，输入列数组、输出等长数组，前导用 NaN。
// 逐行对应原型 chart.js，黄金值测试直接拿原型输出比（误差 ≤ 1e-9）。
//
// Swift 的 Int 在这里是 number；Swift 的区间循环（a..<b、a...b）在 a > b 时会崩，
// 原代码处处有 guard 挡着，TS 里同样的 guard 照抄，循环本身在 a > b 时就是空转。

export function nanArray(n: number): number[] {
  return new Array<number>(Math.max(0, n)).fill(NaN)
}

/**
 * Swift 标准库的 `min(x, y)`：`y < x ? y : x`。
 * 和 `Math.min` 不同，遇到 NaN 时不一定传播（取决于参数位置），原算法依赖的是 Swift 的这一种。
 */
export function swiftMin(x: number, y: number, ...rest: number[]): number {
  let m = y < x ? y : x
  for (const v of rest) if (v < m) m = v
  return m
}

/** Swift 标准库的 `max(x, y)`：`y >= x ? y : x`（多参数时 `value >= maxValue` 才换）。 */
export function swiftMax(x: number, y: number, ...rest: number[]): number {
  let m = y >= x ? y : x
  for (const v of rest) if (v >= m) m = v
  return m
}

/** Double.isFinite。 */
export const isFiniteNum = (x: number): boolean => Number.isFinite(x)

/** 滑动窗均值。窗内含 NaN 则之后一路 NaN（和原型的累加写法一致）。 */
export function sma(src: number[], n: number): number[] {
  const out = nanArray(src.length)
  if (!(n >= 1)) return out
  let sum = 0.0
  for (let i = 0; i < src.length; i++) {
    sum += src[i]
    if (i >= n) sum -= src[i - n]
    if (i >= n - 1) out[i] = sum / n
  }
  return out
}

/** 用前 n 根的均值起步，和 TradingView 一个口径。 */
export function ema(src: number[], n: number): number[] {
  const out = nanArray(src.length)
  if (!(src.length >= n && n >= 1)) return out
  const k = 2 / (n + 1)
  let sum = 0.0
  for (let i = 0; i < n; i++) sum += src[i]
  let prev = sum / n
  out[n - 1] = prev
  for (let i = n; i < src.length; i++) {
    prev = src[i] * k + prev * (1 - k)
    out[i] = prev
  }
  return out
}

/** Wilder 的平滑（RSI、ATR 用的那种，衰减比 EMA 慢一半）。 */
export function rma(src: number[], n: number): number[] {
  const out = nanArray(src.length)
  if (!(src.length >= n && n >= 1)) return out
  let sum = 0.0
  for (let i = 0; i < n; i++) sum += src[i]
  let prev = sum / n
  out[n - 1] = prev
  for (let i = n; i < src.length; i++) {
    prev = (prev * (n - 1) + src[i]) / n
    out[i] = prev
  }
  return out
}

/** 会跳过前面 NaN 的简单均线（原型 smaSkip）。 */
export function smaSkip(src: number[], n: number): number[] {
  const out = nanArray(src.length)
  const start = src.findIndex(Number.isFinite)
  if (start < 0) return out
  const tail = sma(src.slice(start), n)
  for (let i = 0; i < tail.length; i++) out[start + i] = tail[i]
  return out
}

/** 最近 n 根（含第 i 根）的最高值。调用方保证 n ≥ 1（Swift 里 n ≤ 0 会让区间倒置而崩）。 */
export function hhv(src: number[], n: number, i: number): number {
  let m = -Infinity
  for (let j = Math.max(0, i - n + 1); j <= i; j++) if (src[j] > m) m = src[j]
  return m
}

/** 最近 n 根（含第 i 根）的最低值。 */
export function llv(src: number[], n: number, i: number): number {
  let m = Infinity
  for (let j = Math.max(0, i - n + 1); j <= i; j++) if (src[j] < m) m = src[j]
  return m
}
