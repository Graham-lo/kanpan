// 移植自 KanpanCore/Sources/KanpanCore/Drawing/DrawVolume.swift
//
// 三把「计算型」画线工具的算法：锚定 VWAP、区间成交量分布、锚定成交量分布。
// 它们的形状不在锚点里，在锚点圈住的那段 K 线里。纯函数、只吃 `BarSeries`、不认识像素。
// 三把都只用当前周期的 K 线，不下钻到更小周期。

import type { BarSeries } from '../series'

/** 一条锚定 VWAP 的轨迹。 */
export class VWAPTrail {
  /** @param start 从这一根开始（series 下标）  @param values 每根一个值；累计量还是 0 的那几根是 NaN */
  constructor(public start: number, public values: number[]) {}
  /** 末根那个值（非有限 → null）。 */
  get latest(): number | null {
    const v = this.values[this.values.length - 1]
    return v !== undefined && Number.isFinite(v) ? v : null
  }
}

/** 一段区间里成交量按价格分层的结果。行数固定 24，价值区 70%。 */
export class VolumeProfile {
  static readonly rows = 24
  static readonly valueArea = 0.70

  constructor(
    public lo: number, public hi: number, public rowHeight: number,
    public up: number[], public down: number[],
    public poc: number, public vaLow: number, public vaHigh: number,
    public first: number, public last: number,
  ) {}

  /** 真实行数：正常 24，一字线区间 1。 */
  get rowCount(): number { return this.up.length }
  rowLow(r: number): number { return this.lo + this.rowHeight * r }
  rowHigh(r: number): number { return this.rowHeight > 0 ? this.lo + this.rowHeight * (r + 1) : this.hi }
  rowMid(r: number): number { return (this.rowLow(r) + this.rowHigh(r)) / 2 }
  rowTotal(r: number): number { return this.up[r] + this.down[r] }
  get total(): number {
    let s = 0
    const n = Math.min(this.up.length, this.down.length)
    for (let i = 0; i < n; i++) s = s + this.up[i] + this.down[i]
    return s
  }
  get maxRow(): number {
    let m = 0, any = false
    for (let r = 0; r < this.rowCount; r++) { const v = this.rowTotal(r); if (!any || v > m) { m = v; any = true } }
    return any ? m : 0
  }
  inValueArea(r: number): boolean { return r >= this.vaLow && r <= this.vaHigh }
}

/** 第一根 `openTime >= t` 的下标。整段都早于 t → null。 */
export function firstBarAtOrAfter(t: number, series: BarSeries): number | null {
  if (!(series.count > 0 && series.lastTime >= t)) return null
  let lo = 0, hi = series.count - 1
  while (lo < hi) {
    const mid = (lo + hi) >> 1
    if (series.time(mid) >= t) hi = mid; else lo = mid + 1
  }
  return lo
}

/** 最后一根 `openTime <= t` 的下标。整段都晚于 t → null。 */
export function lastBarAtOrBefore(t: number, series: BarSeries): number | null {
  if (!(series.count > 0 && series.firstTime <= t)) return null
  let lo = 0, hi = series.count - 1
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1
    if (series.time(mid) <= t) lo = mid; else hi = mid - 1
  }
  return lo
}

/**
 * 从第一根 `openTime >= anchorT` 起，把 Σ(hlc3·v)/Σv 一路累到末根。锚点落在末根之后 → null。
 *
 * 一次是 O(n)（n 是锚点到现在的根数）。几何每帧都要它，所以结果按 `series.revision` + 锚点记在
 * ComputedMemo 里：平移、缩放、十字线这类帧序列没变，直接取上一帧算好的；来一笔 tick 序列换了戳，
 * 自然重算（DrawVolume.swift，审查 B·待核实 3）。
 */
export function vwapTrail(anchorT: number, series: BarSeries): VWAPTrail | null {
  return ComputedMemo.trail(series.revision, anchorT, () => computeVWAPTrail(anchorT, series))
}

export function computeVWAPTrail(anchorT: number, series: BarSeries): VWAPTrail | null {
  const start = firstBarAtOrAfter(anchorT, series)
  if (start == null) return null
  let pv = 0, vv = 0
  const values: number[] = []
  for (let i = start; i < series.count; i++) {
    const h = series.high[i], l = series.low[i], c = series.close[i], v = series.volume[i]
    // 坏根跳过，不推进累计。
    if (Number.isFinite(h) && Number.isFinite(l) && Number.isFinite(c) && Number.isFinite(v) && v >= 0) {
      pv += (h + l + c) / 3 * v
      vv += v
    }
    values.push(vv > 0 ? pv / vv : NaN)
  }
  return new VWAPTrail(start, values)
}

/** `[fromT, toT]` 圈住的那段 K 线（含两端）按价格分层的成交量；`toT == null` 表示一直到末根。缓存同 vwapTrail。 */
export function volumeProfile(fromT: number, toT: number | null, series: BarSeries): VolumeProfile | null {
  return ComputedMemo.profile(series.revision, fromT, toT, () => computeVolumeProfile(fromT, toT, series))
}

export function computeVolumeProfile(fromT: number, toT: number | null, series: BarSeries): VolumeProfile | null {
  if (!(series.count > 0)) return null
  const first = firstBarAtOrAfter(fromT, series)
  if (first == null) return null
  let last: number
  if (toT != null) {
    const end = lastBarAtOrBefore(toT, series)
    if (end == null) return null
    last = end
  } else {
    last = series.count - 1
  }
  if (!(first <= last)) return null

  let lo = Infinity, hi = -Infinity
  for (let i = first; i <= last; i++) {
    const l = series.low[i], h = series.high[i]
    if (!(Number.isFinite(l) && Number.isFinite(h) && h >= l)) continue
    lo = Math.min(lo, l); hi = Math.max(hi, h)
  }
  if (!(Number.isFinite(lo) && Number.isFinite(hi) && hi >= lo)) return null

  const count = hi > lo ? VolumeProfile.rows : 1
  const height = hi > lo ? (hi - lo) / VolumeProfile.rows : 0
  const up = new Array<number>(count).fill(0)
  const down = new Array<number>(count).fill(0)
  const rowLow = (r: number): number => lo + height * r
  const rowHigh = (r: number): number => (height > 0 ? lo + height * (r + 1) : hi)
  const rowOf = (price: number): number => (height > 0 ? Math.min(count - 1, Math.max(0, Math.floor((price - lo) / height))) : 0)

  for (let i = first; i <= last; i++) {
    const l = series.low[i], h = series.high[i], v = series.volume[i]
    if (!(Number.isFinite(l) && Number.isFinite(h) && h >= l && Number.isFinite(v) && v > 0)) continue
    const rising = series.close[i] >= series.open[i]
    const add = (amount: number, r: number): void => { if (rising) up[r] += amount; else down[r] += amount }
    const span = h - l
    if (height <= 0 || span <= 0) { add(v, rowOf(l)); continue }
    const r0 = rowOf(l), r1 = rowOf(h)
    if (r0 === r1) { add(v, r0); continue }
    for (let r = r0; r <= r1; r++) {
      const overlap = Math.min(h, rowHigh(r)) - Math.max(l, rowLow(r))
      if (!(overlap > 0)) continue
      add(v * overlap / span, r)
    }
  }

  // POC：量最大的那一行；并列取更靠近区间中价的那一行。
  const mid = (lo + hi) / 2
  let poc = 0
  for (let r = 1; r < count; r++) {
    const total = up[r] + down[r], best = up[poc] + down[poc]
    if (total > best) { poc = r; continue }
    if (total === best && Math.abs((rowLow(r) + rowHigh(r)) / 2 - mid) < Math.abs((rowLow(poc) + rowHigh(poc)) / 2 - mid)) poc = r
  }

  // 价值区：从 POC 起向两侧扩，每步比较上方两行之和与下方两行之和，并入大的一侧，直到够 70%。
  let total = 0
  for (let i = 0; i < count; i++) total = total + up[i] + down[i]
  let vaLow = poc, vaHigh = poc
  let acc = up[poc] + down[poc]
  const target = total * VolumeProfile.valueArea
  const sum = (a: number, b: number): number => {
    let s = 0
    for (const r of [a, b]) if (r >= 0 && r < count) s = s + up[r] + down[r]
    return s
  }
  while (acc < target && (vaLow > 0 || vaHigh < count - 1)) {
    const above = vaHigh < count - 1 ? sum(vaHigh + 1, vaHigh + 2) : -1
    const below = vaLow > 0 ? sum(vaLow - 1, vaLow - 2) : -1
    if (above >= below) {
      if (!(vaHigh < count - 1)) break
      vaHigh += 1; acc += up[vaHigh] + down[vaHigh]
      if (vaHigh < count - 1) { vaHigh += 1; acc += up[vaHigh] + down[vaHigh] }
    } else {
      if (!(vaLow > 0)) break
      vaLow -= 1; acc += up[vaLow] + down[vaLow]
      if (vaLow > 0) { vaLow -= 1; acc += up[vaLow] + down[vaLow] }
    }
  }

  return new VolumeProfile(lo, hi, height, up, down, poc, vaLow, vaHigh, first, last)
}

// ------------------------------------------------------------ 计算型画线的结果缓存

/**
 * 锚定 VWAP / 成交量分布的结果缓存（DrawVolume.swift `ComputedMemo`）。
 *
 * 键是「哪条序列（revision）× 哪种算法 × 锚点」。revision 全局唯一、序列任何一次改动都换新值
 * （BarSeries 的 nextStamp），所以不需要失效规则：序列变了，老键再也不会被问到，只会被容量上限清掉。
 * 存 null 也算命中——锚点落在末根之后那把画线每帧都在问，答案一直是「画不出」。
 */
export const ComputedMemo = {
  /** 一屏同时挂几十把计算型画线也够用；超了整表清掉重来，下一帧就重新填满。 */
  capacity: 64,
  trails: new Map<string, VWAPTrail | null>(),
  profiles: new Map<string, VolumeProfile | null>(),
  trail(revision: number, from: number, compute: () => VWAPTrail | null): VWAPTrail | null {
    return memo(this.trails, `${revision}|${from}`, this.capacity, compute)
  },
  profile(revision: number, from: number, to: number | null, compute: () => VolumeProfile | null): VolumeProfile | null {
    return memo(this.profiles, `${revision}|${from}|${to ?? ''}`, this.capacity, compute)
  },
}

function memo<T>(table: Map<string, T | null>, key: string, capacity: number, compute: () => T | null): T | null {
  const hit = table.get(key)
  if (hit !== undefined) return hit
  const value = compute()
  if (table.size >= capacity) table.clear()
  table.set(key, value)
  return value
}
