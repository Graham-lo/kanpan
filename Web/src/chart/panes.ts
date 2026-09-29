/* Hkline Web · 图表窗格的高度分配与多图降级（纯逻辑，引擎与测试共用）
 *
 * 主图 / 副图：用户拖出来的副图高按「占画布高的比例」存（窗口变了跟着等比缩放），
 * 主图永远是剩下的全部，但不少于 40%；每个副图不少于 80 px（画布实在太矮时让到装得下为止）。
 * 多图降级：格子太小时收副图、图例只留品种周期、字号小一档，再窄就不画成交量。
 */
const clamp = (v: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, v))

export const MAIN_MIN_FRAC = 0.4
export const SUB_MIN_H = 80
/** 副图默认高：画布高的 11%，夹在 96–136（和之前的固定分配一样） */
export function subDefaultH(H: number): number { return Math.round(clamp(H * 0.11, 96, 136)) }

/**
 * 各窗格高度（H = 画布高去掉时间轴）。ratios 是用户拖出来的副图比例，没有就用默认高。
 * 规则：每个副图 ≥ 80（画布太矮时让到能装下为止），副图合计 ≤ 60%（主图 ≥ 40%）；没拖过时合计 ≤ 55%（和原来一样）。
 * 返回 [主图, ...副图]，合计正好等于 H。
 */
export function paneHeights(H: number, subs: readonly string[], ratios: Readonly<Record<string, number>> | null | undefined): number[] {
  if (!subs.length) return [H]
  const custom = !!ratios && subs.some(id => typeof ratios[id] === 'number')
  const cap = Math.round(H * (custom ? 1 - MAIN_MIN_FRAC : 0.55))
  const floor = Math.min(SUB_MIN_H, Math.floor(cap / subs.length))
  const def = subDefaultH(H)
  let hs = subs.map(id => { const r = ratios?.[id]; return typeof r === 'number' && isFinite(r) && r > 0 ? r * H : def })
  hs = hs.map(h => Math.max(floor, h))
  const sum = hs.reduce((a, b) => a + b, 0)
  if (sum > cap) hs = hs.map(h => Math.max(floor, h * cap / sum))
  const r = hs.map(h => Math.round(h))
  return [H - r.reduce((a, b) => a + b, 0), ...r]
}

/**
 * 拖第 k 条分隔线（第 k-1 格与第 k 格之间，0 是主图）到 dy：两格之间挪高度，其余不动。
 * 返回新的各格高度（主图在前）。
 */
export function dragPane(hs: readonly number[], k: number, dy: number, H: number): number[] {
  const out = hs.slice()
  if (k < 1 || k >= hs.length) return out
  const total = hs[k - 1] + hs[k]
  const subFloor = Math.min(SUB_MIN_H, Math.floor(H * (1 - MAIN_MIN_FRAC) / (hs.length - 1)))
  const lo = k - 1 === 0 ? Math.ceil(H * MAIN_MIN_FRAC) : subFloor
  const top = clamp(hs[k - 1] + dy, lo, total - subFloor)
  out[k - 1] = Math.round(top); out[k] = total - out[k - 1]
  return out
}
/** 各副图高 → 比例（存盘用） */
export function paneRatiosOf(ids: readonly string[], hs: readonly number[], H: number): Record<string, number> {
  const r: Record<string, number> = {}
  ids.forEach((id, i) => { r[id] = Math.round(hs[i + 1] / H * 10000) / 10000 })
  return r
}

// ------------------------------------------------------------ 多图降级
export interface Degrade {
  /** 副图照画；false = 只留主图 */
  subs: boolean
  /** 图例只留品种与周期 */
  compact: boolean
  /** 价格轴等画布字号：12 → 11 */
  font: number
  /** 成交量照画 */
  vol: boolean
}
export const FULL: Degrade = { subs: true, compact: false, font: 12, vol: true }
/** 格子（含底栏）宽 < 640 或高 < 360：收副图、图例只留品种周期、字号小一档；宽 < 420 再去掉成交量 */
export function degradeFor(w: number, h: number): Degrade {
  const small = w < 640 || h < 360
  if (!small) return FULL
  return { subs: false, compact: true, font: 11, vol: w >= 420 }
}

