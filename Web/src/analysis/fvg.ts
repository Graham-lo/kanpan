/* Hkline Web · 公允价值缺口（三根 K 线失衡缺口），手机网页与电脑网页共用这一份
 *
 * 移植自 KanpanCore/Sources/KanpanCore/Analysis/FVG.swift，口径逐条相同；参数唯一一份在
 * KanpanCore/…/Analysis/fvg.json。两边对同一份黄金样例 KanpanCoreTests/Fixtures/fvg.json 逐位一致。
 * 只画几何事实，不下判定。
 */
import fvgJson from '../../../KanpanCore/Sources/KanpanCore/Analysis/fvg.json'

export interface FVGConfig {
  /** 波幅参考：最近这么多根真实波幅的简单平均（不用 Wilder 递归，加载多少历史都一样） */
  trPeriod: number
  /** 缺口高度至少是波幅参考的这么多倍 */
  minTrRatio: number
  /** 只保留第三根落在最近这么多根 K 线里的缺口 */
  maxAgeBars: number
  /** 每边最多留这么多个，留最近的 */
  perSide: number
}

/** 出厂参数（三端共用 fvg.json） */
export const FVG_CONFIG: Readonly<FVGConfig> = fvgJson

/** 自动分析图层白名单（iOS AutoLayer 的 rawValue）；偏好里读到不认识的名字一律丢弃 */
export const AUTO_LAYERS = ['FVG'] as const
export type AutoLayerId = (typeof AUTO_LAYERS)[number]

export type FVGSide = 'bull' | 'bear'

export interface FVGZone {
  side: FVGSide
  /** 中间那根的开盘时间；盒子从它的左沿画起 */
  startMs: number
  /** 回补收缩后剩下的上沿 / 下沿 */
  top: number
  bottom: number
  /** 原始缺口的 50% 位置，收缩时不动 */
  mid: number
  /** 中线还在剩下的盒子里面 */
  midVisible: boolean
}

/** 电脑网页 chart/calc 的 Bar 直接能传（结构类型，只用这四列） */
export interface FVGBar { t: number; h: number; l: number; c: number }

/** 手机网页 m/chart/series 的 BarSeries（列式）直接能传 */
export interface FVGSeries {
  readonly count: number
  time(i: number): number
  high: number[]
  low: number[]
  close: number[]
}

/**
 * 算当前还在的缺口。closedCount：前多少根已收线——只有收线的能生成缺口（正在走的那根不参与生成），
 * 之后每一根（含正在走的那根）都参与回补。返回按 startMs 升序（同一时刻多头在前）。
 */
export function fvgZones(bars: readonly FVGBar[], closedCount: number, config: Readonly<FVGConfig> = FVG_CONFIG): FVGZone[] {
  const n = bars.length
  const h = new Array<number>(n), l = new Array<number>(n), c = new Array<number>(n)
  for (let i = 0; i < n; i++) { const b = bars[i]; h[i] = b.h; l[i] = b.l; c[i] = b.c }
  return scan(n, closedCount, config, i => bars[i].t, h, l, c)
}

/** 同上，直接吃手机网页的列式序列 */
export function fvgZonesOfSeries(s: FVGSeries, closedCount: number, config: Readonly<FVGConfig> = FVG_CONFIG): FVGZone[] {
  return scan(s.count, closedCount, config, i => s.time(i), s.high, s.low, s.close)
}

/** 一遍扫：到第 j 根先让它回补已有的缺口，再看它（作为第三根）能不能生成新缺口。O(根数 × 在场缺口数) */
function scan(
  n: number, closedCount: number, config: Readonly<FVGConfig>,
  time: (i: number) => number, h: readonly number[], l: readonly number[], c: readonly number[],
): FVGZone[] {
  if (config.perSide <= 0) return []
  const p = Math.max(1, config.trPeriod)
  const closed = Math.min(Math.max(closedCount, 0), n)
  // 波幅参考要第 i-p … i 根（第 i-p+1 根的真实波幅要用前一根收盘），所以 i ≥ p
  const genStart = Math.max(2, p, n - config.maxAgeBars)
  if (genStart >= closed) return []

  const trueRange = (k: number): number =>
    k === 0 ? h[0] - l[0] : Math.max(h[k] - l[k], Math.abs(h[k] - c[k - 1]), Math.abs(l[k] - c[k - 1]))

  let active: FVGZone[] = []
  for (let j = genStart; j < n; j++) {
    // 回补：价格进到盒子里就收缩到剩下没补的部分，穿过去就删掉
    if (active.length) {
      const hj = h[j], lj = l[j]
      let w = 0
      for (const z of active) {
        let filled: boolean
        if (z.side === 'bull') {
          if (lj < z.top) z.top = lj
          filled = lj <= z.bottom
        } else {
          if (hj > z.bottom) z.bottom = hj
          filled = hj >= z.top
        }
        if (!filled) active[w++] = z
      }
      active.length = w
    }
    if (j >= closed) continue
    // 生成：第 j 根是第三根
    const i = j
    let z: FVGZone | null = null
    if (l[i] > h[i - 2]) z = { side: 'bull', startMs: time(i - 1), top: l[i], bottom: h[i - 2], mid: 0, midVisible: true }
    else if (h[i] < l[i - 2]) z = { side: 'bear', startMs: time(i - 1), top: l[i - 2], bottom: h[i], mid: 0, midVisible: true }
    if (!z) continue
    // 波幅参考就地按下标升序累加，不用前缀和（前缀和相减的舍入会随加载的历史长短变）；与 Swift 逐位一致
    let sum = 0
    for (let k = i - p + 1; k <= i; k++) sum += trueRange(k)
    const ref = sum / p
    if (!(z.top - z.bottom >= config.minTrRatio * ref)) continue
    z.mid = (z.top + z.bottom) / 2
    active.push(z)
  }

  // 在场列表按生成先后排，也就是 startMs 升序；每边留最后 perSide 个
  const bulls: FVGZone[] = [], bears: FVGZone[] = []
  for (const z of active) {
    z.midVisible = z.bottom < z.mid && z.mid < z.top
    ;(z.side === 'bull' ? bulls : bears).push(z)
  }
  const kb = bulls.slice(-config.perSide), ke = bears.slice(-config.perSide)
  const out: FVGZone[] = []
  let a = 0, b = 0
  while (a < kb.length || b < ke.length) {
    if (b === ke.length || (a < kb.length && kb[a].startMs <= ke[b].startMs)) out.push(kb[a++])
    else out.push(ke[b++])
  }
  return out
}
