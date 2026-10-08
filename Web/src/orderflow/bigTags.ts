/* Hkline Web · 主力订单流 · 图上「大单与爆仓」气泡（2026-10-08 二稿，规格 docs/design/大单爆仓气泡-三端规格-2026-10-08.md，
 * 设计源 docs/prototypes/web-bigtrade-bubbles-2026-10-08.html 的 one()；电脑网页与手机网页共用这一份几何）
 *
 * 为什么：原来每笔大额成交在图上打一个点，存在内存里的成交带上，换品种 / 藏标签页 / 刷新就清空，一根里几十个点叠成一团。
 * 现在每根 K 线只剩两个数：向上 U = 大买 + 空单爆仓、向下 D = 大卖 + 多单爆仓（空爆是被动买、多爆是被动卖，和主动大单同向），
 * 一种样子的透明气泡：U 挂最高价之上、D 挂最低价之下，只分涨跌两色；图上不区分大单还是爆仓，拆分只在悬停 / 点开的卡里给。
 * 大买 / 大卖来自 chart/tradeFlow.ts 的分钟桶（浏览器实时记的 + 服务端 3 天历史，取法照 whaleFlow），爆仓来自 liquidation.ts 的分钟行。
 *
 * 规则：
 *   · 一分钟取哪份：整分钟在覆盖区间里用浏览器的；否则服务端有这行用服务端的；服务端在跟、落在它的历史里却没有行 = 没成交；
 *     再不然用浏览器攒到的那一部分。周期粗于 1 分钟时前端按分钟并；秒级周期只有浏览器的秒桶（爆仓按分钟，秒级周期不并）。
 *   · 笔数、最大一笔、现货 / 合约与各家的占比只有浏览器记（服务端的行没有）：一根里只要有一分钟的大单金额来自服务端，这几项就是 null。
 *   · 门槛两级：最近 300 根（TIER_BARS）每根 max(U, D) 的非零分布，点线 = P90、泡线 = P97，各垫一道绝对下限 = 门槛 ÷ 5；
 *     只在数据版本（缓存作废 / 新开一根 / 爆仓新数据 / 下限）变了才重算。不到点线不画，点线到泡线之间画小圆点，过泡线画带字的泡。
 *   · 一屏带字的泡最多 6 枚：候选（每根 U、D 各一枚）按金额降序，大的先占位，第 7 枚起退成点；一根宽不到 4 一律只画点。
 *   · 几何：点 r = clamp(根宽 × 0.4, 1.5, 2.8)、离高 / 低点 2；泡 r = max(11 + 6 × min(1, (v − 泡线) / (泡线 × 2)), 字宽 / 2 + 4)、柄 4；
 *     圆心 = 锚点 ∓ (柄 + r)。同侧已摆的（点和泡都算）挨上了就往外推一层（最多 6 次）；泡还会被图例、画线文字框推开。
 *     泡推完出了窗格（上沿 / 下沿各留 4）、横向出了主图、或还压着字 → 退成点（不占 6 枚配额）；点出了窗格或压着字就不画。
 *   · 缓存：每张图一份「根 → 大单合计」；服务端历史有新行时整份作废，最近 3 分钟内的根在有新大单或每 5 秒重算，其余的根算过就不再算。
 * 只聚合、门槛过滤、展示，不做判定。
 */
import { addCell, cell, type Cell, type Print, type SymbolFlow } from '../chart/tradeFlow'

/** 一根 K 线的大单合计 */
export interface BarBig {
  t: number
  t1: number
  bb: number
  bs: number
  /** 以下只有整根的大单金额都来自浏览器时才有（exact），否则 null */
  bn: number | null
  sn: number | null
  bmax: Print | null
  smax: Print | null
  /** 大单里现货的买 + 卖、各家各自（买 + 卖） */
  spot: number | null
  ex: number[] | null
  exact: boolean
}

/** 一段 [a, b) 的大单合计（按分钟 / 秒桶并，取法见文件头）。没有任何数据时 null */
export function sumBig(f: SymbolFlow, a: number, b: number, now: number, fine = false): { c: Cell; exact: boolean; has: boolean } {
  const step = fine ? 1000 : 60_000
  const src = fine ? f.sec : f.min, srv = f.srv
  const out = cell()
  let exact = true, has = false
  let start = Infinity
  for (const k of src.keys()) { start = k; break }
  if (!fine && srv.tracked && srv.lo < start) start = srv.lo
  if (!isFinite(start)) return { c: out, exact, has }
  const firstCover = f.cover.length ? f.cover[0][0] : Infinity
  const m0 = Math.max(Math.floor(a / step) * step, Math.floor(start / step) * step)
  for (let m = m0; m < b && m <= now; m += step) {
    const x = src.get(m)
    if (m >= firstCover && f.covered(m, m + step, now)) { if (x) { addCell(out, x); has = true } continue }
    if (!fine) {
      const r = srv.rows.get(m)
      if (r) { has = true; if (r[0] > 0 || r[1] > 0) { out.bb += r[0]; out.bs += r[1]; exact = false } continue }
      if (srv.tracked && m >= srv.lo && m <= srv.hi) { has = true; continue }
    }
    if (x) { addCell(out, x); has = true }
  }
  return { c: out, exact, has }
}

export function barBig(f: SymbolFlow, t0: number, t1: number, now: number): BarBig | null {
  const fine = t1 - t0 < 60_000
  const { c, exact, has } = sumBig(f, t0, t1, now, fine)
  if (!has || (c.bb <= 0 && c.bs <= 0)) return null
  return {
    t: t0, t1, bb: c.bb, bs: c.bs,
    bn: exact ? c.bn : null, sn: exact ? c.sn : null, bmax: exact ? c.bmax : null, smax: exact ? c.smax : null,
    spot: exact ? c.bsb + c.bss : null, ex: exact ? [...c.bx] : null, exact,
  }
}

/** 档位单位：门槛 ÷ 5。这只的大单线（门槛 ÷ 50）知道就用它 × 10（多图里不是活动格子的那几只也能算），否则用活动那只的 */
export function unitFor(f: SymbolFlow | null, fallback: number): number {
  const c = f?.cut
  return c != null && c > 0 ? c * 10 : fallback
}

/** 一根的爆仓（并好的分钟行）：long = 多单爆仓（被动卖，算向下），short = 空单爆仓（被动买，算向上） */
export interface BarLiq { long: number; short: number }
/** 一张图这一刻的爆仓并根口：key 变了（品种 / 周期 / 新数据）档位就重算；没有爆仓数据的品种给 null */
export interface LiqBars { key: string; at(t0: number, t1: number): BarLiq | null }
/** 一根的向上 / 向下：U = 大买 + 空爆，D = 大卖 + 多爆 */
export interface BarUD { up: number; down: number }
export function udOf(d: { bb: number; bs: number } | null, l: BarLiq | null): BarUD {
  return { up: (d?.bb ?? 0) + (l?.short ?? 0), down: (d?.bs ?? 0) + (l?.long ?? 0) }
}

/** 两级金额线（已垫过绝对下限）：dot = 小圆点，bubble = 带字的泡 */
export interface Levels { dot: number; bubble: number }
/** 分位：点线 P90、泡线 P97（原型「少」档） */
export const LEVEL_Q = { dot: 0.9, bubble: 0.97 } as const
/** 0 = 不画，1 = 点，2 = 泡（泡还要过根宽与 6 枚配额，见 planBubbles） */
export function levelOf(v: number, k: Levels | null): 0 | 1 | 2 {
  if (!k || !(v > 0)) return 0
  if (v >= k.bubble) return 2
  if (v >= k.dot) return 1
  return 0
}

/** 分布取多少根 */
export const TIER_BARS = 300
/** 已排好序（升序）的分位数，线性插值（同 numpy 默认） */
export function quantile(sorted: readonly number[], q: number): number {
  const n = sorted.length
  if (!n) return 0
  const pos = (n - 1) * Math.min(1, Math.max(0, q)), i = Math.floor(pos), fr = pos - i
  return i + 1 < n ? sorted[i] + (sorted[i + 1] - sorted[i]) * fr : sorted[i]
}
/** 非零的每根 max(U, D) → 两级；floor = 绝对下限（门槛 ÷ 5）。一根有数的都没有给 null */
export function levelsFrom(vals: readonly number[], floor: number): Levels | null {
  const v = vals.filter(x => x > 0).sort((a, b) => a - b)
  if (!v.length) return null
  const f = floor > 0 ? floor : 0
  const dot = Math.max(quantile(v, LEVEL_Q.dot), f)
  return { dot, bubble: Math.max(quantile(v, LEVEL_Q.bubble), f, dot) }
}

/** 一张图的 K 线（只要时间）：bars 升序、timeAt(n) 给最后一根之后那根的开盘时间 */
export interface BarsLike { bars: readonly { t: number }[]; timeAt: (i: number) => number }
/** 最近 TIER_BARS 根 max(U, D) 的分布 → 两级。结果按「缓存代数 + 最后一根 + 下限 + 爆仓版本」记住，数据没变就不重算 */
export class LevelCache {
  private key = ''
  private val: Levels | null = null
  /** 重算过几次（测试看缓存有没有生效） */
  computed = 0
  get(cache: BigBarCache, f: SymbolFlow, ch: BarsLike, now: number, floor: number, liq: LiqBars | null = null): Levels | null {
    const n = ch.bars.length
    if (!n) return null
    const key = `${cache.gen}|${ch.bars[n - 1].t}|${n}|${floor}|${liq?.key ?? ''}`
    if (key === this.key) return this.val
    this.key = key; this.computed++
    const vals: number[] = []
    for (let i = n - 1; i >= Math.max(0, n - TIER_BARS); i--) {
      const t0 = ch.bars[i].t, t1 = i + 1 < n ? ch.bars[i + 1].t : ch.timeAt(n)
      const d = cache.get(f, t0, t1, now), l = liq ? liq.at(t0, t1) : null
      if (!d && !l) continue
      const u = udOf(d, l)
      vals.push(Math.max(u.up, u.down))
    }
    this.val = levelsFrom(vals, floor)
    return this.val
  }
}

/** 每张图一份：根的开盘时间 → 合计（null = 这根没有大单） */
const HOT_MS = 3 * 60_000
const TICK_MS = 5_000
const CACHE_CAP = 20_000
export class BigBarCache {
  private key = ''
  private srvVer = -1
  private live = -1
  private tick = -1
  private map = new Map<number, { v: BarBig | null; t1: number }>()
  /** 算过多少根（测试与压测看缓存有没有生效） */
  computed = 0
  /** 每作废一次加一（档位的分布据此重算） */
  gen = 0
  /** 每次画之前调一次：品种 / 周期变了、服务端历史有新行时整份作废；有新大单或过了 5 秒，把最近 3 分钟内的根放掉重算 */
  begin(f: SymbolFlow, key: string, now: number): void {
    if (key !== this.key || f.srv.ver !== this.srvVer || this.map.size > CACHE_CAP) {
      this.map.clear(); this.key = key; this.srvVer = f.srv.ver; this.live = f.live; this.tick = Math.floor(now / TICK_MS); this.gen++
      return
    }
    const tk = Math.floor(now / TICK_MS)
    if (f.live === this.live && tk === this.tick) return
    this.live = f.live; this.tick = tk
    let n = 0
    for (const [t, e] of this.map) if (e.t1 > now - HOT_MS) { this.map.delete(t); n++ }
    if (n) this.gen++
  }
  get(f: SymbolFlow, t0: number, t1: number, now: number): BarBig | null {
    const e = this.map.get(t0)
    if (e) return e.v
    const v = t0 > now ? null : barBig(f, t0, t1, now)
    this.computed++
    this.map.set(t0, { v, t1 })
    return v
  }
  size(): number { return this.map.size }
}

// ------------------------------------------------------------ 摆放（原型 one() 的同一套）
export interface Rect { x: number; y: number; w: number; h: number }
export const hit = (a: Rect, b: Rect): boolean => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
/** 圆与矩形相交（矩形上离圆心最近的点在圆内） */
export function circleHitsRect(x: number, y: number, r: number, a: Rect): boolean {
  const dx = x - Math.max(a.x, Math.min(x, a.x + a.w)), dy = y - Math.max(a.y, Math.min(y, a.y + a.h))
  return dx * dx + dy * dy < r * r
}

/** 尺寸与画法（px / pt），三端同值 */
export const BUBBLE = {
  /** 一屏带字的泡最多几枚 */
  cap: 6,
  /** 一根窄于这么多一律只画点 */
  minBw: 4,
  font: 11,
  dotK: 0.4, dotMin: 1.5, dotMax: 2.8, dotStem: 2, dotAlpha: 0.85,
  r0: 11, rGrow: 6, textPad: 4, stem: 4,
  /** 同侧两枚之间至少留这么多 */
  gap: 2,
  /** 往外推最多几次 */
  pushes: 6,
  /** 泡离窗格上下沿至少留这么多，不然退成点 */
  edge: 4,
  fill: 0.16, fillDark: 0.22, fillHover: 0.32, stroke: 1.4,
  stemW: 1.2, stemAlpha: 0.6,
  hoverScale: 1.1,
} as const

export type BubbleSide = 'up' | 'down'
/** 一根的输入：x = 根中心，yHigh / yLow = 高 / 低点的纵坐标（屏幕向下为正），up / down = U / D */
export interface BubbleIn { i: number; t: number; x: number; yHigh: number; yLow: number; up: number; down: number }
export interface BubbleEnv {
  levels: Levels | null
  /** 一根 K 线宽 */
  bw: number
  /** 能落的竖直范围（主图窗格里，电脑让开成交量那一截，手机让开图例带）与横向右界（价格轴左沿） */
  top: number
  bottom: number
  plotW: number
  /** 不许压的：图例、画线文字 */
  avoid: readonly Rect[]
  /** 量泡里的字宽（11 号半粗、等宽数字） */
  measure: (text: string) => number
  /** 金额短写（1.2M / 860K），泡里再去掉末尾的 M */
  text: (usd: number) => string
}
export interface Bubble {
  i: number
  t: number
  side: BubbleSide
  usd: number
  /** 圆心与半径 */
  x: number
  cy: number
  r: number
  /** 柄的起点：上侧 = 最高价的 y，下侧 = 最低价的 y */
  anchor: number
  /** 泡里的字（点为空） */
  text: string
  /** true = 带字的泡，false = 小圆点 */
  bubble: boolean
}

/** 点的半径：clamp(根宽 × 0.4, 1.5, 2.8) */
export const dotRadius = (bw: number): number => Math.min(BUBBLE.dotMax, Math.max(BUBBLE.dotMin, bw * BUBBLE.dotK))
/** 泡里的字：金额短写去掉 M（1.2M → 1.2；K、B 保留） */
export const bubbleText = (s: string): string => s.replace(/M$/, '')
/** 柄的终点（泡近边）：上侧 cy + r，下侧 cy − r */
export const stemEnd = (b: Bubble): number => (b.side === 'up' ? b.cy + b.r : b.cy - b.r)

/** 排一屏：候选 = 每根 U（上）与 D（下）过点线的各一枚，按金额降序，大的先占位；返回按根序（同根上侧在前） */
export function planBubbles(list: readonly BubbleIn[], env: BubbleEnv): Bubble[] {
  const K = env.levels
  if (!K) return []
  type Cand = { b: BubbleIn; side: BubbleSide; v: number }
  const cands: Cand[] = []
  for (const b of list) {
    if (!Number.isFinite(b.x) || !Number.isFinite(b.yHigh) || !Number.isFinite(b.yLow)) continue
    if (b.up >= K.dot && b.up > 0) cands.push({ b, side: 'up', v: b.up })
    if (b.down >= K.dot && b.down > 0) cands.push({ b, side: 'down', v: b.down })
  }
  cands.sort((p, q) => q.v - p.v || q.b.i - p.b.i)
  const placed: Record<BubbleSide, { x: number; y: number; r: number }[]> = { up: [], down: [] }
  const rd = dotRadius(env.bw)
  const onScreen = (x: number): boolean => x >= 0 && x <= env.plotW
  const blocked = (x: number, y: number, r: number): Rect | undefined => env.avoid.find(a => circleHitsRect(x, y, r, a))
  const out: Bubble[] = []
  let nb = 0
  for (const c of cands) {
    const up = c.side === 'up', X = c.b.x, anchor = up ? c.b.yHigh : c.b.yLow
    let bubble = c.v >= K.bubble && env.bw >= BUBBLE.minBw && nb < BUBBLE.cap && onScreen(X)
    let r = rd, text = ''
    if (bubble) {
      text = bubbleText(env.text(c.v))
      r = Math.max(BUBBLE.r0 + BUBBLE.rGrow * Math.min(1, (c.v - K.bubble) / (K.bubble * 2)), env.measure(text) / 2 + BUBBLE.textPad)
    }
    const stem = bubble ? BUBBLE.stem : BUBBLE.dotStem
    let cy = up ? anchor - stem - r : anchor + stem + r
    // 错层：同侧已摆的挨上了就往外推一层；泡还被图例 / 画线文字推开（点不推：推远了看不出是哪根的，压字就不画）
    for (let k = 0; k < BUBBLE.pushes; k++) {
      const p = placed[c.side].find(q => Math.hypot(q.x - X, q.y - cy) < q.r + r + BUBBLE.gap)
      if (p) { cy = up ? p.y - p.r - r - BUBBLE.gap : p.y + p.r + r + BUBBLE.gap; continue }
      const a = bubble ? blocked(X, cy, r) : undefined
      if (a) { cy = up ? a.y - r - BUBBLE.gap : a.y + a.h + r + BUBBLE.gap; continue }
      break
    }
    if (bubble) {
      const outV = up ? cy - r < env.top + BUBBLE.edge : cy + r > env.bottom - BUBBLE.edge
      if (outV || X - r < 0 || X + r > env.plotW || blocked(X, cy, r)) {
        bubble = false; r = rd; text = ''
        cy = up ? anchor - BUBBLE.dotStem - r : anchor + BUBBLE.dotStem + r
      }
    }
    if (!bubble && (!onScreen(X) || cy - r < env.top || cy + r > env.bottom || blocked(X, cy, r))) continue
    if (bubble) nb++
    placed[c.side].push({ x: X, y: cy, r })
    out.push({ i: c.b.i, t: c.b.t, side: c.side, usd: c.v, x: X, cy, r, anchor, text, bubble })
  }
  return out.sort((p, q) => p.i - q.i || (p.side === q.side ? 0 : p.side === 'up' ? -1 : 1))
}

/** 周期的中文名：5 分钟 / 1 小时 / 日线 */
export function ivName(ms: number): string {
  if (ms < 60_000) return `${Math.round(ms / 1000)} 秒`
  if (ms < 3_600_000) return `${Math.round(ms / 60_000)} 分钟`
  if (ms < 86_400_000) return `${Math.round(ms / 3_600_000)} 小时`
  if (ms < 7 * 86_400_000) return ms === 86_400_000 ? '日线' : `${Math.round(ms / 86_400_000)} 日`
  if (ms < 28 * 86_400_000) return '周线'
  return '月线'
}
