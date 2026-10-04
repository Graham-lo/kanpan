// 移植自 KanpanCore/Sources/KanpanCore/Indicator/IndicatorEngine.swift + IncrementalLines.swift
//
// 指标的算与缓存（§5.7、§8）。
//
// 缓存键 = 数据键 | 品种 | 周期 | 指标集合 + 参数 | 外部输入戳 | 根数。末根变化只重算最后 N 根
// （N = tailBars），整段换了才全量。增量与全量逐位相同：每种线都把自己的递推状态
// （滑动窗累加和、EMA/RMA 的前值、KDJ 的 K/D、VWAP/CVD 的累计量、超级趋势的轨、SAR 的极值点）
// 逐根存着，不是近似。
//
// 与 Swift 的一处语义差别（有意为之）：Swift 的结果是值类型，调用方攥着的旧快照不会被改；
// 这里结果里的数组就是状态里的那几条缓冲，`updateTail` 就地改尾巴——这正是 Swift 那边费力
// 做「先放手再改」想得到的效果（尾部重算不随历史长度变慢）。调用方如果要留旧快照，自己 slice。

import { BarSeries, ExternalSeries } from '../chart/series'
import type { Interval } from '../chart/series'
import { hhv, llv, nanArray, swiftMax, swiftMin } from './math'
import { IndicatorResult, defaultParams, externalColumns, isExternal, normalizedParams, tailBars } from './ids'
import type { IndicatorID } from './ids'

export type IndicatorParams = Partial<Record<IndicatorID, readonly number[]>>
export type ExternalMap = Partial<Record<IndicatorID, ExternalSeries>>

const isFin = Number.isFinite

/** 追长到 n，补的都是 NaN（Swift `grow(to:_:)`，就地改）。 */
export function grow(n: number, ...arrays: number[][]): void {
  for (const a of arrays) while (a.length < n) a.push(NaN)
}

// ================================================================ IncrementalLines.swift

/** 滑动窗均值。累加和逐根存下来，尾部重算才能接着上一根的和继续，和全量逐位相同。 */
export class SMALine {
  n: number
  /** 跳过前导 NaN 用：从这一根开始才是真正的输入（smaSkip）。 */
  offset: number
  out: number[]
  sum: number[]

  constructor(src: number[], n: number, offset = 0) {
    this.n = n
    this.offset = offset
    this.out = nanArray(src.length)
    this.sum = nanArray(src.length)
    this.recompute(src, offset)
  }

  /** 从 start 往后重算。start <= offset 就是全量。 */
  recompute(src: number[], start: number): void {
    if (this.out.length < src.length) grow(src.length, this.out, this.sum)
    const { n, offset, out, sum } = this
    if (!(n >= 1 && offset < src.length)) return
    const begin = Math.max(offset, start)
    let s = begin > offset ? sum[begin - 1] : 0
    for (let i = begin; i < src.length; i++) {
      s += src[i]
      const k = i - offset
      if (k >= n) s -= src[i - n]
      sum[i] = s
      out[i] = k >= n - 1 ? s / n : NaN
    }
  }

  /** 尾部重算的最早起点：要能拿到上一根的累加和；拿不到返回假，调用方整条重建。 */
  canTail(start: number): boolean {
    return start > this.offset && start >= 1 && start - 1 < this.sum.length && isFin(this.sum[start - 1])
  }
}

export type RecursiveKind = 'ema' | 'rma'

/** EMA / RMA 这类一阶递推线。 */
export class RecursiveLine {
  kind: RecursiveKind
  n: number
  offset: number
  out: number[]

  constructor(src: number[], n: number, kind: RecursiveKind, offset = 0) {
    this.kind = kind
    this.n = n
    this.offset = offset
    this.out = nanArray(src.length)
    this.full(src)
  }

  private full(src: number[]): void {
    const { n, offset, out } = this
    const count = src.length - offset
    if (!(count >= n && n >= 1)) return
    let sum = 0.0
    for (let i = 0; i < n; i++) sum += src[offset + i]
    let prev = sum / n
    out[offset + n - 1] = prev
    for (let i = offset + n; i < src.length; i++) {
      prev = this.step(prev, src[i])
      out[i] = prev
    }
  }

  private step(prev: number, x: number): number {
    const n = this.n
    if (this.kind === 'ema') {
      const k = 2 / (n + 1)
      return x * k + prev * (1 - k)
    }
    return (prev * (n - 1) + x) / n
  }

  recompute(src: number[], start: number): void {
    if (this.out.length < src.length) grow(src.length, this.out)
    if (!this.canTail(start)) { this.out = nanArray(src.length); this.full(src); return }
    const out = this.out
    let prev = out[start - 1]
    for (let i = start; i < src.length; i++) {
      prev = this.step(prev, src[i])
      out[i] = prev
    }
  }

  /** 同 SMALine.canTail；另挡 n <= 0 时起点 0 读 out[-1]。 */
  canTail(start: number): boolean {
    return start > this.offset + this.n - 1 && start >= 1 && start - 1 < this.out.length && isFin(this.out[start - 1])
  }
}

// ================================================================ 各指标状态

/** 布林：mid 是滑动窗均值（能增量），上下轨是窗内标准差，只能从 start 往后重扫。 */
export class BollState {
  n: number
  k: number
  mid: SMALine
  up: number[]
  dn: number[]

  constructor(close: number[], n: number, k: number) {
    this.n = n
    this.k = k
    this.mid = new SMALine(close, n)
    this.up = nanArray(close.length)
    this.dn = nanArray(close.length)
    this.band(close, 0)
  }

  private band(close: number[], start: number): void {
    grow(close.length, this.up, this.dn)
    const { n, k, up, dn } = this
    if (!(n >= 1 && close.length >= n)) return
    const mid = this.mid.out
    for (let i = Math.max(n - 1, start); i < close.length; i++) {
      let s = 0.0
      for (let j = i - n + 1; j <= i; j++) {
        const d = close[j] - mid[i]
        s += d * d
      }
      const sd = Math.sqrt(s / n)
      up[i] = mid[i] + k * sd
      dn[i] = mid[i] - k * sd
    }
  }

  update(close: number[], start: number): void {
    if (this.mid.canTail(start)) {
      this.mid.recompute(close, start)
      this.band(close, start)
    } else {
      this.mid = new SMALine(close, this.n)
      this.up = nanArray(close.length); this.dn = nanArray(close.length)
      this.band(close, 0)
    }
  }
}

/** MACD：两条 EMA 差出 DIF，DEA 是 DIF 的 EMA（从 DIF 第一个有值处起算）。 */
export class MACDState {
  fast: number; slow: number; sig: number
  f: RecursiveLine; s: RecursiveLine
  dea: RecursiveLine
  dif: number[]; hist: number[]

  constructor(close: number[], fast: number, slow: number, sig: number) {
    this.fast = fast; this.slow = slow; this.sig = sig
    this.f = new RecursiveLine(close, fast, 'ema')
    this.s = new RecursiveLine(close, slow, 'ema')
    this.dif = nanArray(close.length)
    this.hist = nanArray(close.length)
    this.dea = new RecursiveLine([], sig, 'ema')
    this.full(close)
  }

  private full(close: number[]): void {
    const dif = nanArray(close.length)
    const f = this.f.out, s = this.s.out
    for (let i = 0; i < close.length; i++) if (isFin(f[i]) && isFin(s[i])) dif[i] = f[i] - s[i]
    this.dif = dif
    const first = dif.findIndex(isFin)
    const start = first < 0 ? dif.length : first
    this.dea = new RecursiveLine(dif, this.sig, 'ema', start)
    this.fillHist(0)
  }

  private fillHist(start: number): void {
    grow(this.dif.length, this.hist)
    const { dif, hist } = this, dea = this.dea.out
    for (let i = Math.max(0, start); i < dif.length; i++) {
      hist[i] = (isFin(dif[i]) && isFin(dea[i])) ? (dif[i] - dea[i]) * 2 : NaN
    }
  }

  update(close: number[], start: number): void {
    if (!(this.f.canTail(start) && this.s.canTail(start) && this.dea.canTail(start))) {
      this.f = new RecursiveLine(close, this.fast, 'ema')
      this.s = new RecursiveLine(close, this.slow, 'ema')
      this.full(close)
      return
    }
    this.f.recompute(close, start)
    this.s.recompute(close, start)
    grow(close.length, this.dif)
    const dif = this.dif, f = this.f.out, s = this.s.out
    for (let i = start; i < close.length; i++) {
      dif[i] = (isFin(f[i]) && isFin(s[i])) ? f[i] - s[i] : NaN
    }
    this.dea.recompute(dif, start)
    this.fillHist(start)
  }
}

/** RSI：涨跌两列各走 RMA，再合成。 */
export class RSIState {
  n: number
  up: number[]; dn: number[]
  au: RecursiveLine; ad: RecursiveLine
  out: number[]

  constructor(close: number[], n: number) {
    this.n = n
    ;[this.up, this.dn] = RSIState.deltas(close)
    this.au = new RecursiveLine(this.up, n, 'rma')
    this.ad = new RecursiveLine(this.dn, n, 'rma')
    this.out = nanArray(close.length)
    this.fill(0)
  }

  private static deltas(close: number[]): [number[], number[]] {
    const up = nanArray(close.length), dn = nanArray(close.length)
    if (!close.length) return [up, dn]
    up[0] = 0; dn[0] = 0
    for (let i = 1; i < close.length; i++) {
      const d = close[i] - close[i - 1]
      up[i] = d > 0 ? d : 0
      dn[i] = d < 0 ? -d : 0
    }
    return [up, dn]
  }

  private fill(start: number): void {
    grow(this.up.length, this.out)
    const out = this.out, au = this.au.out, ad = this.ad.out
    for (let i = Math.max(0, start); i < this.up.length; i++) {
      out[i] = isFin(au[i])
        ? (ad[i] === 0 ? 100 : 100 - 100 / (1 + au[i] / ad[i]))
        : NaN
    }
  }

  /** 只补 [start, count) 这一段的涨跌幅；列比收盘还长（序列缩短了）就退回整列。 */
  private tailDeltas(close: number[], start: number): void {
    if (!(this.up.length <= close.length && this.dn.length <= close.length)) {
      ;[this.up, this.dn] = RSIState.deltas(close)
      return
    }
    grow(close.length, this.up, this.dn)
    if (!close.length) return
    const up = this.up, dn = this.dn
    const s = Math.max(0, Math.min(start, close.length))
    if (s === 0) { up[0] = 0; dn[0] = 0 }
    for (let i = Math.max(1, s); i < close.length; i++) {
      const d = close[i] - close[i - 1]
      up[i] = d > 0 ? d : 0
      dn[i] = d < 0 ? -d : 0
    }
  }

  update(close: number[], start: number): void {
    this.tailDeltas(close, start)
    if (this.au.canTail(start) && this.ad.canTail(start)) {
      this.au.recompute(this.up, start)
      this.ad.recompute(this.dn, start)
      this.fill(start)
    } else {
      this.au = new RecursiveLine(this.up, this.n, 'rma')
      this.ad = new RecursiveLine(this.dn, this.n, 'rma')
      this.out = nanArray(close.length)
      this.fill(0)
    }
  }
}

/** KDJ：K/D 从 50 起步一路递推，尾部重算得拿上一根的 K/D 当种子。 */
export class KDJState {
  n: number; kn: number; dn: number
  k: number[]; d: number[]; j: number[]

  constructor(b: BarSeries, n: number, kn: number, dn: number) {
    this.n = n; this.kn = kn; this.dn = dn
    this.k = nanArray(b.count); this.d = nanArray(b.count); this.j = nanArray(b.count)
    this.run(b, 0, 50, 50)
  }

  private run(b: BarSeries, start: number, seedK: number, seedD: number): void {
    grow(b.count, this.k, this.d, this.j)
    const { n, kn, dn, k, d, j } = this
    if (!(b.count > 0 && n >= 1 && kn >= 1 && dn >= 1)) return
    let kk = seedK, dd = seedD
    const high = b.high, low = b.low, close = b.close
    for (let i = start; i < b.count; i++) {
      const hi = hhv(high, n, i), lo = llv(low, n, i)
      const rsv = hi === lo ? 50 : ((close[i] - lo) / (hi - lo)) * 100
      kk = ((kn - 1) * kk + rsv) / kn
      dd = ((dn - 1) * dd + kk) / dn
      if (i >= n - 1) { k[i] = kk; d[i] = dd; j[i] = 3 * kk - 2 * dd }
    }
  }

  update(b: BarSeries, start: number): void {
    if (start > 0 && start - 1 < this.k.length && isFin(this.k[start - 1]) && isFin(this.d[start - 1])) {
      this.run(b, start, this.k[start - 1], this.d[start - 1])
    } else {
      this.k = nanArray(b.count); this.d = nanArray(b.count); this.j = nanArray(b.count)
      this.run(b, 0, 50, 50)
    }
  }
}

/** StochRSI：RSI → Stoch → 两条跳过前导 NaN 的均线。 */
export class SRSIState {
  rlen: number; slen: number; kn: number; dn: number
  r: RSIState
  raw: number[]
  k: SMALine; d: SMALine

  constructor(close: number[], rlen: number, slen: number, kn: number, dn: number) {
    this.rlen = rlen; this.slen = slen; this.kn = kn; this.dn = dn
    this.r = new RSIState(close, rlen)
    this.raw = nanArray(close.length)
    this.k = new SMALine([], kn); this.d = new SMALine([], dn)
    this.full()
  }

  private stoch(start: number): void {
    const r = this.r.out
    grow(r.length, this.raw)
    const raw = this.raw, slen = this.slen
    for (let i = Math.max(0, start); i < r.length; i++) {
      raw[i] = NaN
      if (!isFin(r[i])) continue
      let hi = -Infinity, lo = Infinity, ok = true
      let j = i - slen + 1
      while (j <= i) {
        if (j < 0 || !isFin(r[j])) { ok = false; break }
        if (r[j] > hi) hi = r[j]
        if (r[j] < lo) lo = r[j]
        j += 1
      }
      if (!ok) continue
      raw[i] = hi === lo ? 0 : ((r[i] - lo) / (hi - lo)) * 100
    }
  }

  private full(): void {
    this.raw = nanArray(this.r.out.length)
    this.stoch(0)
    const rf = this.raw.findIndex(isFin)
    this.k = new SMALine(this.raw, this.kn, rf < 0 ? this.raw.length : rf)
    const kf = this.k.out.findIndex(isFin)
    this.d = new SMALine(this.k.out, this.dn, kf < 0 ? this.k.out.length : kf)
  }

  update(close: number[], start: number): void {
    this.r.update(close, start)
    if (start > 0 && this.k.canTail(start) && this.d.canTail(start)) {
      this.stoch(start)
      this.k.recompute(this.raw, start)
      this.d.recompute(this.k.out, start)
    } else {
      this.full()
    }
  }
}

function trueRangeAt(b: BarSeries, i: number): number {
  const h = b.high, l = b.low, c = b.close
  return swiftMax(h[i] - l[i], swiftMax(Math.abs(h[i] - c[i - 1]), Math.abs(l[i] - c[i - 1])))
}

/** ATR：真实波幅再 RMA。 */
export class ATRState {
  n: number
  tr: number[]
  line: RecursiveLine

  constructor(b: BarSeries, n: number) {
    this.n = n
    this.tr = ATRState.trueRange(b)
    this.line = new RecursiveLine(this.tr, n, 'rma')
  }

  private static trueRange(b: BarSeries): number[] {
    const tr = nanArray(b.count)
    if (!(b.count > 0)) return tr
    tr[0] = b.high[0] - b.low[0]
    for (let i = 1; i < b.count; i++) tr[i] = trueRangeAt(b, i)
    return tr
  }

  /** 只补 [start, count) 这一段的真实波幅。 */
  private tailTrueRange(b: BarSeries, start: number): void {
    if (!(this.tr.length <= b.count)) {
      this.tr = ATRState.trueRange(b)
      return
    }
    grow(b.count, this.tr)
    if (!(b.count > 0)) return
    const tr = this.tr
    const s = Math.max(0, Math.min(start, b.count))
    if (s === 0) tr[0] = b.high[0] - b.low[0]
    for (let i = Math.max(1, s); i < b.count; i++) tr[i] = trueRangeAt(b, i)
  }

  update(b: BarSeries, start: number): void {
    this.tailTrueRange(b, start)
    if (this.line.canTail(start)) this.line.recompute(this.tr, start)
    else this.line = new RecursiveLine(this.tr, this.n, 'rma')
  }
}

// ---------------------------------------------------------------- 累计周期

/** Swift Int 除法（向零截断）。 */
const idiv = (a: number, b: number): number => Math.trunc(a / b)

/** 毫秒时间戳 → UTC 的月序号（年×12+月），整数算术（civil-from-days），不走 Date。 */
export function utcMonthIndex(ms: number): number {
  const dayMs = 86_400_000
  let z = idiv(ms, dayMs)
  if (ms < 0 && ms % dayMs !== 0) z -= 1
  z += 719_468
  const era = idiv(z >= 0 ? z : z - 146_096, 146_097)
  const doe = z - era * 146_097
  const yoe = idiv(doe - idiv(doe, 1460) + idiv(doe, 36_524) - idiv(doe, 146_096), 365)
  const y = yoe + era * 400
  const doy = doe - (365 * yoe + idiv(yoe, 4) - idiv(yoe, 100))
  const mp = idiv(5 * doy + 2, 153)
  const m = mp < 10 ? mp + 3 : mp - 9
  return (m <= 2 ? y + 1 : y) * 12 + m
}

/**
 * 第 i 根是不是一个新累计周期的头一根：日内周期按 UTC 零点归零，日线按自然月，
 * 周线、月线按自然年，年线不归零（年线一次载齐全部历史）。和 iOS `startsAnchorPeriod`
 * 同一张表——从前日线以上一律按自然月，月线上每根都清零，VWAP / CVD 等于没有。
 */
export function startsAnchorPeriod(b: BarSeries, i: number): boolean {
  if (!(i > 0)) return true
  const dayMs = 86_400_000
  const now = b.time(i), prev = b.time(i - 1)
  if (b.step < dayMs) return idiv(now, dayMs) !== idiv(prev, dayMs)
  if (b.step < 7 * dayMs) return utcMonthIndex(now) !== utcMonthIndex(prev)
  if (b.step < 365 * dayMs) return idiv(utcMonthIndex(now) - 1, 12) !== idiv(utcMonthIndex(prev) - 1, 12)
  return false
}

/** 当日VWAP：成交量加权均价，每天零点归零。逐根的累加和存下来，尾部重算才接得上。 */
export class VWAPState {
  out: number[]
  pv: number[]
  vv: number[]

  constructor(b: BarSeries) {
    this.out = nanArray(b.count); this.pv = nanArray(b.count); this.vv = nanArray(b.count)
    this.run(b, 0, 0, 0)
  }

  private run(b: BarSeries, start: number, seedPV: number, seedVV: number): void {
    grow(b.count, this.out, this.pv, this.vv)
    if (!(b.count > 0 && start < b.count)) return
    const { out, pv, vv } = this
    let sp = seedPV, sv = seedVV
    for (let i = start; i < b.count; i++) {
      if (startsAnchorPeriod(b, i)) { sp = 0; sv = 0 }
      // 典型价（高+低+收）/3。
      const tp = (b.high[i] + b.low[i] + b.close[i]) / 3
      // 价或量不是有限数：留白、累计值原样往下传（和 CVD 一个写法，与 iOS 同步）。
      if (!isFin(tp) || !isFin(b.volume[i])) { pv[i] = sp; vv[i] = sv; out[i] = NaN; continue }
      sp += tp * b.volume[i]
      sv += b.volume[i]
      pv[i] = sp; vv[i] = sv
      // 一整天零成交时退回典型价，不出 NaN 也不除零。
      out[i] = sv > 0 ? sp / sv : tp
    }
  }

  update(b: BarSeries, start: number): void {
    if (start > 0 && start - 1 < this.pv.length && isFin(this.pv[start - 1]) && isFin(this.vv[start - 1])) {
      this.run(b, start, this.pv[start - 1], this.vv[start - 1])
    } else {
      this.out = nanArray(b.count); this.pv = nanArray(b.count); this.vv = nanArray(b.count)
      this.run(b, 0, 0, 0)
    }
  }
}

/**
 * 累计成交量差（CVD）：逐根「2×主动买 − 成交量」累加，与当日VWAP 同一个锚归零。
 * 主动买量缺失的那一根留白，累计值原样往下传。
 */
export class CVDState {
  out: number[]
  /** 到第 i 根为止的累计值；这一根不知道主动买量时沿用上一根。 */
  sum: number[]

  constructor(b: BarSeries) {
    this.out = nanArray(b.count); this.sum = nanArray(b.count)
    this.run(b, 0, 0)
  }

  private run(b: BarSeries, start: number, seed: number): void {
    grow(b.count, this.out, this.sum)
    if (!(b.count > 0 && start < b.count)) return
    const { out, sum } = this
    let s = seed
    for (let i = start; i < b.count; i++) {
      if (startsAnchorPeriod(b, i)) s = 0
      const buy = b.takerBuy[i], vol = b.volume[i]
      if (isFin(buy) && isFin(vol)) {
        s += 2 * buy - vol
        out[i] = s
      } else {
        out[i] = NaN
      }
      sum[i] = s
    }
  }

  update(b: BarSeries, start: number): void {
    if (start > 0 && start - 1 < this.sum.length && isFin(this.sum[start - 1])) {
      this.run(b, start, this.sum[start - 1])
    } else {
      this.out = nanArray(b.count); this.sum = nanArray(b.count)
      this.run(b, 0, 0)
    }
  }
}

/** 超级趋势：ATR 通道加一条只会往趋势方向收紧的轨，翻向那一根直接跳到价格另一侧。 */
export class SuperTrendState {
  n: number
  mult: number
  a: ATRState
  up: number[]
  dn: number[]
  line: number[]
  dir: number[]

  constructor(b: BarSeries, n: number, mult: number) {
    this.n = n
    this.mult = mult
    this.a = new ATRState(b, n)
    this.up = nanArray(b.count); this.dn = nanArray(b.count)
    this.line = nanArray(b.count); this.dir = nanArray(b.count)
    this.run(b, 0, NaN, NaN, true)
  }

  private run(b: BarSeries, start: number, seedUp: number, seedDn: number, seedLong: boolean): void {
    grow(b.count, this.up, this.dn); grow(b.count, this.line, this.dir)
    if (!(b.count > 0 && start < b.count)) return
    const { up, dn, line, dir, mult } = this
    let fUp = seedUp, fDn = seedDn, long = seedLong
    for (let i = start; i < b.count; i++) {
      const width = this.a.line.out[i]
      if (!isFin(width)) {
        up[i] = NaN; dn[i] = NaN; line[i] = NaN; dir[i] = NaN
        continue
      }
      const mid = (b.high[i] + b.low[i]) / 2
      const basicUp = mid + mult * width
      const basicDn = mid - mult * width
      const prevClose = i > 0 ? b.close[i - 1] : b.close[i]
      // 轨只往「夹紧」的方向走；价格穿出去了才允许松开重来。
      fUp = (!isFin(fUp) || basicUp < fUp || prevClose > fUp) ? basicUp : fUp
      fDn = (!isFin(fDn) || basicDn > fDn || prevClose < fDn) ? basicDn : fDn
      if (long) {
        if (b.close[i] < fDn) long = false
      } else if (b.close[i] > fUp) {
        long = true
      }
      up[i] = fUp; dn[i] = fDn
      line[i] = long ? fDn : fUp
      dir[i] = long ? 1 : -1
    }
  }

  update(b: BarSeries, start: number): void {
    this.a.update(b, start)
    if (start > 0 && start - 1 < this.dir.length
      && isFin(this.up[start - 1]) && isFin(this.dn[start - 1]) && isFin(this.dir[start - 1])) {
      this.run(b, start, this.up[start - 1], this.dn[start - 1], this.dir[start - 1] > 0)
    } else {
      this.up = nanArray(b.count); this.dn = nanArray(b.count)
      this.line = nanArray(b.count); this.dir = nanArray(b.count)
      this.run(b, 0, NaN, NaN, true)
    }
  }
}

/** 抛物线转向（Wilder）。加速因子从 0.02 起、每创一次新高加 0.02、封顶 0.20。 */
export class SARState {
  /** 加速步长与上限。 */
  static readonly step = 0.02
  static readonly maxAF = 0.20

  out: number[]
  dir: number[]
  ep: number[]
  af: number[]

  constructor(b: BarSeries) {
    this.out = nanArray(b.count); this.dir = nanArray(b.count)
    this.ep = nanArray(b.count); this.af = nanArray(b.count)
    this.full(b)
  }

  private full(b: BarSeries): void {
    this.out = nanArray(b.count); this.dir = nanArray(b.count)
    this.ep = nanArray(b.count); this.af = nanArray(b.count)
    if (!(b.count >= 2)) return
    // 头一根没有上一根可比，拿第二根的方向当种子。
    const long = b.close[1] >= b.close[0]
    this.out[0] = long ? b.low[0] : b.high[0]
    this.ep[0] = long ? b.high[0] : b.low[0]
    this.af[0] = SARState.step
    this.dir[0] = long ? 1 : -1
    this.run(b, 1)
  }

  private run(b: BarSeries, start: number): void {
    grow(b.count, this.out, this.dir); grow(b.count, this.ep, this.af)
    if (!(start >= 1 && start < b.count)) return
    const { out, dir, ep, af } = this
    const high = b.high, low = b.low
    let sar = out[start - 1], e = ep[start - 1], a = af[start - 1]
    let long = dir[start - 1] > 0
    for (let i = start; i < b.count; i++) {
      sar += a * (e - sar)
      if (long) {
        // 轨不许进到前两根的最低价里面去。
        sar = swiftMin(sar, low[i - 1], low[Math.max(0, i - 2)])
        if (low[i] < sar) {
          long = false; sar = swiftMax(e, high[i]); e = low[i]; a = SARState.step
        } else if (high[i] > e) {
          e = high[i]; a = swiftMin(a + SARState.step, SARState.maxAF)
        }
      } else {
        sar = swiftMax(sar, high[i - 1], high[Math.max(0, i - 2)])
        if (high[i] > sar) {
          long = true; sar = swiftMin(e, low[i]); e = high[i]; a = SARState.step
        } else if (low[i] < e) {
          e = low[i]; a = swiftMin(a + SARState.step, SARState.maxAF)
        }
      }
      out[i] = sar; ep[i] = e; af[i] = a; dir[i] = long ? 1 : -1
    }
  }

  update(b: BarSeries, start: number): void {
    if (start >= 1 && start - 1 < this.out.length
      && isFin(this.out[start - 1]) && isFin(this.ep[start - 1])
      && isFin(this.af[start - 1]) && isFin(this.dir[start - 1])) {
      this.run(b, start)
    } else {
      this.full(b)
    }
  }
}

/** 动向指标：+DI / -DI 两条方向线，加一条趋势强度 ADX。 */
export class DMIState {
  n: number
  pdm: number[]; mdm: number[]; tr: number[]
  spdm: RecursiveLine; smdm: RecursiveLine; str: RecursiveLine
  pdi: number[]; mdi: number[]; dx: number[]
  adx: RecursiveLine

  constructor(b: BarSeries, n: number) {
    this.n = n
    ;[this.pdm, this.mdm, this.tr] = DMIState.raw(b)
    this.spdm = new RecursiveLine(this.pdm, n, 'rma')
    this.smdm = new RecursiveLine(this.mdm, n, 'rma')
    this.str = new RecursiveLine(this.tr, n, 'rma')
    this.pdi = nanArray(b.count); this.mdi = nanArray(b.count); this.dx = nanArray(b.count)
    this.adx = new RecursiveLine([], n, 'rma')
    this.full()
  }

  private static raw(b: BarSeries): [number[], number[], number[]] {
    const pdm = nanArray(b.count), mdm = nanArray(b.count), tr = nanArray(b.count)
    if (!(b.count > 0)) return [pdm, mdm, tr]
    pdm[0] = 0; mdm[0] = 0
    tr[0] = b.high[0] - b.low[0]
    for (let i = 1; i < b.count; i++) DMIState.fill(b, i, pdm, mdm, tr)
    return [pdm, mdm, tr]
  }

  private static fill(b: BarSeries, i: number, pdm: number[], mdm: number[], tr: number[]): void {
    const up = b.high[i] - b.high[i - 1]
    const down = b.low[i - 1] - b.low[i]
    // 只有「明显更大的那一边」才算一次动向；两边一样大或者都在收缩，两边都记 0。
    pdm[i] = (up > down && up > 0) ? up : 0
    mdm[i] = (down > up && down > 0) ? down : 0
    tr[i] = trueRangeAt(b, i)
  }

  private full(): void {
    this.pdi = nanArray(this.tr.length); this.mdi = nanArray(this.tr.length); this.dx = nanArray(this.tr.length)
    this.fillDI(0)
    const first = this.dx.findIndex(isFin)
    this.adx = new RecursiveLine(this.dx, this.n, 'rma', first < 0 ? this.dx.length : first)
  }

  private fillDI(start: number): void {
    grow(this.tr.length, this.pdi, this.mdi, this.dx)
    const { pdi, mdi, dx } = this
    const str = this.str.out, spdm = this.spdm.out, smdm = this.smdm.out
    for (let i = Math.max(0, start); i < this.tr.length; i++) {
      if (!(isFin(str[i]) && str[i] !== 0 && isFin(spdm[i]) && isFin(smdm[i]))) {
        pdi[i] = NaN; mdi[i] = NaN; dx[i] = NaN
        continue
      }
      const p = 100 * spdm[i] / str[i]
      const m = 100 * smdm[i] / str[i]
      pdi[i] = p; mdi[i] = m
      const sum = p + m
      // 两条方向线都是 0 时强度记 0，不是 NaN。
      dx[i] = sum === 0 ? 0 : 100 * Math.abs(p - m) / sum
    }
  }

  private tailRaw(b: BarSeries, start: number): void {
    if (!(this.pdm.length <= b.count && this.mdm.length <= b.count && this.tr.length <= b.count)) {
      ;[this.pdm, this.mdm, this.tr] = DMIState.raw(b)
      return
    }
    grow(b.count, this.pdm, this.mdm, this.tr)
    if (!(b.count > 0)) return
    const { pdm, mdm, tr } = this
    const s = Math.max(0, Math.min(start, b.count))
    if (s === 0) { pdm[0] = 0; mdm[0] = 0; tr[0] = b.high[0] - b.low[0] }
    for (let i = Math.max(1, s); i < b.count; i++) DMIState.fill(b, i, pdm, mdm, tr)
  }

  update(b: BarSeries, start: number): void {
    this.tailRaw(b, start)
    if (!(this.spdm.canTail(start) && this.smdm.canTail(start) && this.str.canTail(start) && this.adx.canTail(start))) {
      this.spdm = new RecursiveLine(this.pdm, this.n, 'rma')
      this.smdm = new RecursiveLine(this.mdm, this.n, 'rma')
      this.str = new RecursiveLine(this.tr, this.n, 'rma')
      this.full()
      return
    }
    this.spdm.recompute(this.pdm, start)
    this.smdm.recompute(this.mdm, start)
    this.str.recompute(this.tr, start)
    this.fillDI(start)
    this.adx.recompute(this.dx, start)
  }
}

// ================================================================ State（Swift 的 enum State）

type Source = 'close' | 'volume'
const column = (src: Source, b: BarSeries): number[] => (src === 'close' ? b.close : b.volume)

/** 一个指标的递推状态：出结果、只重算尾巴。 */
export interface IndicatorState {
  readonly result: IndicatorResult
  update(b: BarSeries, start: number, external: ExternalSeries | undefined): void
}

/** `.sma`：MA（收盘）与 VOL（成交量）。 */
class SMAListState implements IndicatorState {
  constructor(public lines: SMALine[], public src: Source) {}
  get result(): IndicatorResult { return new IndicatorResult(this.lines.map(l => l.out)) }
  update(b: BarSeries, start: number): void {
    const col = column(this.src, b), l = this.lines
    for (let i = 0; i < l.length; i++) {
      if (l[i].canTail(start)) l[i].recompute(col, start)
      else l[i] = new SMALine(col, l[i].n, l[i].offset)
    }
  }
}

/** `.ema` */
class EMAListState implements IndicatorState {
  constructor(public lines: RecursiveLine[]) {}
  get result(): IndicatorResult { return new IndicatorResult(this.lines.map(l => l.out)) }
  update(b: BarSeries, start: number): void {
    for (const l of this.lines) l.recompute(b.close, start)
  }
}

/** `.rsi` */
class RSIListState implements IndicatorState {
  constructor(public lines: RSIState[]) {}
  get result(): IndicatorResult { return new IndicatorResult(this.lines.map(l => l.out)) }
  update(b: BarSeries, start: number): void {
    for (const l of this.lines) l.update(b.close, start)
  }
}

/** 单个结构体状态的包装：告诉它怎么出结果、怎么喂列。 */
class Wrapped<S> implements IndicatorState {
  constructor(
    public s: S,
    private res: (s: S) => IndicatorResult,
    private upd: (s: S, b: BarSeries, start: number) => void,
  ) {}
  get result(): IndicatorResult { return this.res(this.s) }
  update(b: BarSeries, start: number): void { this.upd(this.s, b, start) }
}

/** `.external`：对齐好的那几列，外加它是从哪一份外部序列来的（revision，没喂到时 0）。 */
class ExternalState implements IndicatorState {
  constructor(public cols: number[][], public rev: number) {}
  get result(): IndicatorResult { return new IndicatorResult(this.cols) }
  update(b: BarSeries, start: number, ext: ExternalSeries | undefined): void {
    const prev = this.cols
    if (!ext || ext.revision === 0) {
      // 没喂到数据：上次也没有的话，那几列已经全是 NaN，追长就行。
      if (this.rev === 0 && prev.every(c => c.length <= b.count)) {
        for (const c of prev) grow(b.count, c)
        this.rev = 0
      } else {
        this.cols = ExternalSeries.blank(Math.max(prev.length, 1), b.count)
        this.rev = 0
      }
      return
    }
    // 还是同一份、列数没变、前缀也没动：只对齐尾巴，结果逐位相同。换了一份就整列重来。
    if (ext.revision === this.rev && prev.length === ext.columnCount
      && prev.every(c => c.length <= b.count && start <= c.length)) {
      this.cols = ext.alignedFrom(b, start, prev)
    } else {
      this.cols = ext.aligned(b)
    }
    this.rev = ext.revision
  }
}

function build(id: IndicatorID, p: readonly number[], b: BarSeries, external: ExternalSeries | undefined): IndicatorState {
  switch (id) {
    case 'MA': return new SMAListState(p.map(n => new SMALine(b.close, n)), 'close')
    case 'VOL': return new SMAListState(p.map(n => new SMALine(b.volume, n)), 'volume')
    case 'EMA': return new EMAListState(p.map(n => new RecursiveLine(b.close, n, 'ema')))
    case 'BOLL': return new Wrapped(new BollState(b.close, p[0], p[1]),
      s => new IndicatorResult([s.mid.out, s.up, s.dn]), (s, bb, st) => s.update(bb.close, st))
    case 'MACD': return new Wrapped(new MACDState(b.close, p[0], p[1], p[2]),
      s => new IndicatorResult([s.dif, s.dea.out], s.hist), (s, bb, st) => s.update(bb.close, st))
    case 'RSI': return new RSIListState(p.map(n => new RSIState(b.close, n)))
    case 'KDJ': return new Wrapped(new KDJState(b, p[0], p[1], p[2]),
      s => new IndicatorResult([s.k, s.d, s.j]), (s, bb, st) => s.update(bb, st))
    case 'SRSI': return new Wrapped(new SRSIState(b.close, p[0], p[1], p[2], p[3]),
      s => new IndicatorResult([s.k.out, s.d.out]), (s, bb, st) => s.update(bb.close, st))
    case 'ATR': return new Wrapped(new ATRState(b, p[0]),
      s => new IndicatorResult([s.line.out]), (s, bb, st) => s.update(bb, st))
    case 'VWAP': return new Wrapped(new VWAPState(b),
      s => new IndicatorResult([s.out]), (s, bb, st) => s.update(bb, st))
    // 超级趋势与抛物线转向都只出一条线，多空靠 dir 那一列分段着色。
    case 'ST': return new Wrapped(new SuperTrendState(b, p[0], p[1]),
      s => new IndicatorResult([s.line], null, s.dir), (s, bb, st) => s.update(bb, st))
    case 'SAR': return new Wrapped(new SARState(b),
      s => new IndicatorResult([s.out], null, s.dir), (s, bb, st) => s.update(bb, st))
    // 主力订单流不从 K 线算，给一列 NaN 占位（和没喂到的外部指标同一种写法）。
    case 'ORDERFLOW': return new ExternalState(ExternalSeries.blank(1, b.count), 0)
    case 'DMI': return new Wrapped(new DMIState(b, p[0]),
      s => new IndicatorResult([s.pdi, s.mdi, s.adx.out]), (s, bb, st) => s.update(bb, st))
    case 'CVD': return new Wrapped(new CVDState(b),
      s => new IndicatorResult([s.out]), (s, bb, st) => s.update(bb, st))
    case 'OI': case 'LSR': case 'TAKER': case 'BASIS':
      return new ExternalState(
        external ? external.aligned(b) : ExternalSeries.blank(externalColumns(id) ?? 1, b.count),
        external ? external.revision : 0)
  }
}

// ================================================================ 缓存键

const sameInts = (a: readonly number[] | undefined, b: readonly number[] | undefined): boolean => {
  if (a === b) return true
  if (!a || !b || a.length !== b.length) return false
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
  return true
}

/**
 * 缓存键。字段逐个比；指标集合就是 params 的键集合。外部输入按 revision 记进来：
 * K 线一个字没动它们也会变，键里没有它们的影子 ensure 就会短路、画面停在旧值上。
 */
export class CacheKey {
  readonly dataKey: string
  readonly symbol: string
  readonly interval: Interval
  readonly params: ReadonlyMap<IndicatorID, readonly number[]>
  readonly external: ReadonlyMap<IndicatorID, number>
  readonly count: number

  constructor(series: BarSeries, params: ReadonlyMap<IndicatorID, readonly number[]>, external: ExternalMap, dataKey: string) {
    this.dataKey = dataKey
    this.symbol = series.symbol
    this.interval = series.interval
    this.params = new Map(params)
    const ext = new Map<IndicatorID, number>()
    for (const [id, s] of Object.entries(external) as [IndicatorID, ExternalSeries | undefined][]) {
      if (s) ext.set(id, s.revision)
    }
    this.external = ext
    this.count = series.count
  }

  equals(o: CacheKey | null): boolean {
    if (!o) return false
    if (this.dataKey !== o.dataKey || this.symbol !== o.symbol || this.interval !== o.interval || this.count !== o.count) return false
    if (this.params.size !== o.params.size || this.external.size !== o.external.size) return false
    for (const [id, p] of this.params) if (!o.params.has(id) || !sameInts(p, o.params.get(id))) return false
    for (const [id, r] of this.external) if (o.external.get(id) !== r) return false
    return true
  }
}

// ================================================================ 引擎

export interface EnsureOptions {
  series: BarSeries
  wanted: readonly IndicatorID[]
  params?: IndicatorParams
  /** 不从 K 线算的输入（持仓量、多空比、主动买卖比、基差），按指标索引。 */
  external?: ExternalMap
  /** 只有持仓量时的便捷写法（Swift 的 `oi:` 重载）：给了它就忽略 external。null 等于没喂。 */
  oi?: ExternalSeries | null
  dataKey?: string
}

export interface UpdateTailOptions {
  series: BarSeries
  external?: ExternalMap
  /** 同 EnsureOptions.oi。 */
  oi?: ExternalSeries | null
  dataKey?: string
}

const resolveExternal = (o: { external?: ExternalMap; oi?: ExternalSeries | null }): ExternalMap =>
  o.oi !== undefined ? IndicatorEngine.externalMap(o.oi) : (o.external ?? {})

export class IndicatorEngine {
  /** 当前算出来的值，按指标取。数组是活的：updateTail 会就地改尾巴。 */
  private _values = new Map<IndicatorID, IndicatorResult>()
  private states = new Map<IndicatorID, IndicatorState>()
  private params = new Map<IndicatorID, number[]>()
  private key: CacheKey | null = null
  /** 现有这些状态是照着哪一份 K 线算出来的（BarSeries.revision）。0 是「还没算过」。 */
  private dataRevision = 0

  get values(): ReadonlyMap<IndicatorID, IndicatorResult> { return this._values }

  /** Swift 的 `engine[id]`。 */
  get(id: IndicatorID): IndicatorResult | undefined { return this._values.get(id) }

  /**
   * 保证 wanted 里的指标都是算好的。键没变就直接返回 false，什么都不做；算了返回 true。
   * 没喂到外部数据的外部指标画一列 NaN，不是报错。
   */
  ensure(o: EnsureOptions): boolean {
    const series = o.series
    const external = resolveExternal(o)
    const dataKey = o.dataKey ?? ''
    const ids = [...new Set(o.wanted)]
    // 参数先理一遍再用：build 按下标取固定个数的参数。
    const resolved = new Map<IndicatorID, number[]>()
    for (const id of ids) resolved.set(id, normalizedParams(id, o.params?.[id]))
    const k = new CacheKey(series, resolved, external, dataKey)
    if (k.equals(this.key)) return false
    this.key = k

    // 按指标失效：这份 K 线还是刚才那份、这个指标自己的参数没动，才留用。
    const sameData = this.dataRevision === series.revision && this.dataRevision !== 0
    const oldParams = this.params
    const keptStates = new Map<IndicatorID, IndicatorState>()
    const keptValues = new Map<IndicatorID, IndicatorResult>()
    for (const id of ids) {
      const p = resolved.get(id) ?? defaultParams(id)
      const st = this.states.get(id), v = this._values.get(id)
      // 吃外部数据的指标一律不留用：series.revision 管不着那一路外部序列。
      if (sameData && !isExternal(id) && sameInts(oldParams.get(id), p) && st && v) {
        keptStates.set(id, st)
        keptValues.set(id, v)
      } else {
        const built = build(id, p, series, external[id])
        keptStates.set(id, built)
        keptValues.set(id, built.result)
      }
    }
    this.params = resolved
    this.states = keptStates
    this._values = keptValues
    this.dataRevision = series.revision
    return true
  }

  /** 末根改了或者新追了一根：只重算尾巴，结果与全量逐位相同。 */
  updateTail(o: UpdateTailOptions): void {
    const series = o.series
    const external = resolveExternal(o)
    // 空序列没有末根可更（WS 事件可能比 REST 历史先到），直接放过。
    if (!(this.states.size > 0 && series.count > 0)) return
    this._values.clear()
    for (const [id, st] of this.states) {
      const p = this.params.get(id) ?? defaultParams(id)
      // 下限是 0 而不是 1：序列短到 count <= tailBars 时首根也是末根，起点 0 让各条线的
      // canTail 返回假、退回全量重建。
      const start = Math.max(0, series.count - tailBars(id, p))
      st.update(series, start, external[id])
      this._values.set(id, st.result)
    }
    this.key = new CacheKey(series, this.params, external, o.dataKey ?? '')
    this.dataRevision = series.revision
  }

  /** 单列持仓量 → 外部序列表。null / undefined 给空表，OI 那一列就画成 NaN。 */
  static externalMap(oi: ExternalSeries | null | undefined): ExternalMap {
    return oi ? { OI: oi } : {}
  }
}
