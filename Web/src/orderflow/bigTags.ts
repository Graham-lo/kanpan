/* Hkline Web · 主力订单流 · 图上「大单签」（2026-10-08，替掉原来逐笔一个的成交圆点）
 *
 * 为什么：原来每笔大额成交在图上打一个点，点存在内存里的成交带（tape）上，换品种 / 藏标签页一分钟 / 刷新就清空，
 * 用户看到的就是「刚打的点下一根就没了」；而且一根 K 线里几十个点叠成一团，看不出这根到底大买多少。
 * 现在改成每根 K 线一枚签：买方合计挂在最高价上方、卖方合计挂在最低价下方，数据来自 chart/tradeFlow.ts 的分钟桶
 * （浏览器实时记的 + 服务端 3 天历史，取法照 whaleFlow），刷新、换品种、多图都还在。
 *
 * 规则：
 *   · 一分钟取哪份：整分钟在覆盖区间里用浏览器的；否则服务端有这行用服务端的；服务端在跟、落在它的历史里却没有行 = 没成交；
 *     再不然用浏览器攒到的那一部分。周期粗于 1 分钟时前端按分钟并；秒级周期只有浏览器的秒桶。
 *   · 笔数、最大一笔、现货 / 合约与三家的占比只有浏览器记（服务端的行没有）：一根里只要有一分钟的大单金额来自服务端，这几项就是 null（界面写「—」或不写）。
 *   · 档位单位 = 门槛 ÷ 5（和成交带的「大额」同一条线）：≥ 1 倍画 6 px 三角，≥ 3 倍画带金额的圆角签，≥ 10 倍画 13 px 粗体大签。
 *   · 两侧都够格时，金额大的那侧实心、另一侧只描边。签不压 K 线（按签横跨的那几根的最高 / 最低让开），
 *     不压图例、不压画线的文字、签与签不叠；放不下就往外挪一格，再不行退回三角，三角也撞上就不画。
 *   · 缓存：每张图一份「根 → 合计」；服务端历史有新行时整份作废，最近 3 分钟内的根在有新大单或每 5 秒重算，其余的根算过就不再算。
 *     多图时非活动格子没有实时桶，拖动缩放只是查表。
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
  /** 大单里现货的买 + 卖、三家各自（买 + 卖） */
  spot: number | null
  ex: [number, number, number] | null
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
    spot: exact ? c.bsb + c.bss : null, ex: exact ? [c.bx[0], c.bx[1], c.bx[2]] : null, exact,
  }
}

/** 档位单位：门槛 ÷ 5。这只的大单线（门槛 ÷ 50）知道就用它 × 10（多图里不是活动格子的那几只也能算），否则用活动那只的 */
export function unitFor(f: SymbolFlow | null, fallback: number): number {
  const c = f?.cut
  return c != null && c > 0 ? c * 10 : fallback
}

export type Tier = 0 | 1 | 2 | 3
export function tierOf(v: number, unit: number): Tier {
  if (!(unit > 0) || !(v > 0)) return 0
  if (v >= unit * 10) return 3
  if (v >= unit * 3) return 2
  if (v >= unit) return 1
  return 0
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
  /** 每次画之前调一次：品种 / 周期变了、服务端历史有新行时整份作废；有新大单或过了 5 秒，把最近 3 分钟内的根放掉重算 */
  begin(f: SymbolFlow, key: string, now: number): void {
    if (key !== this.key || f.srv.ver !== this.srvVer || this.map.size > CACHE_CAP) {
      this.map.clear(); this.key = key; this.srvVer = f.srv.ver; this.live = f.live; this.tick = Math.floor(now / TICK_MS)
      return
    }
    const tk = Math.floor(now / TICK_MS)
    if (f.live === this.live && tk === this.tick) return
    this.live = f.live; this.tick = tk
    for (const [t, e] of this.map) if (e.t1 > now - HOT_MS) this.map.delete(t)
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

// ------------------------------------------------------------ 摆放
export interface Rect { x: number; y: number; w: number; h: number }
export const hit = (a: Rect, b: Rect): boolean => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h

export interface TagIn {
  i: number
  t: number
  x: number
  data: BarBig
}
export interface Tag {
  i: number
  t: number
  side: 'buy' | 'sell'
  kind: 'tri' | 'tag' | 'big'
  filled: boolean
  text: string
  usd: number
  /** 外框（三角也给外框，悬停 / 点用） */
  x: number; y: number; w: number; h: number
  /** 三角的尖 / 签的中心横坐标 */
  cx: number
}
export interface PlanEnv {
  unit: number
  spacing: number
  top: number
  bottom: number
  plotW: number
  /** [x0, x1] 横跨的那几根 K 线里最高价的 y（最小的 y）与最低价的 y（最大的 y）；没有 K 线给 null */
  span: (x0: number, x1: number) => { hiY: number; loY: number } | null
  measure: (text: string, big: boolean) => number
  text: (usd: number) => string
  /** 不许压的：图例、画线文字 */
  avoid: Rect[]
}
export const GAP = 4
export const TRI_W = 7
export const TRI_H = 6
export const TAG_H = 16
export const BIG_H = 20
/** 一根宽不到这么多像素就只画三角（金额签必然横跨十几根，看不出是哪根的） */
export const TEXT_MIN_SPACING = 3

/** 一屏的签：大的先摆（大的先占位置）；返回摆得下的那些 */
export function planTags(list: TagIn[], env: PlanEnv): Tag[] {
  type Cand = { b: TagIn; side: 'buy' | 'sell'; usd: number; tier: Tier; filled: boolean }
  const cands: Cand[] = []
  for (const b of list) {
    const tb = tierOf(b.data.bb, env.unit), ts = tierOf(b.data.bs, env.unit)
    const both = tb > 0 && ts > 0
    if (tb > 0) cands.push({ b, side: 'buy', usd: b.data.bb, tier: tb, filled: !both || b.data.bb >= b.data.bs })
    if (ts > 0) cands.push({ b, side: 'sell', usd: b.data.bs, tier: ts, filled: !both || b.data.bs > b.data.bb })
  }
  cands.sort((p, q) => q.usd - p.usd)
  const placed: Rect[] = []
  const out: Tag[] = []
  const free = (r: Rect): boolean => r.y >= env.top && r.y + r.h <= env.bottom && r.x >= 0 && r.x + r.w <= env.plotW &&
    !env.avoid.some(a => hit(a, r)) && !placed.some(a => hit(a, r))
  for (const c of cands) {
    const up = c.side === 'buy', x = c.b.x
    let kind: Tag['kind'] = c.tier === 3 ? 'big' : c.tier === 2 ? 'tag' : 'tri'
    if (env.spacing < TEXT_MIN_SPACING) kind = 'tri'
    let done: Tag | null = null
    if (kind !== 'tri') {
      const text = env.text(c.usd), big = kind === 'big'
      const w = Math.ceil(env.measure(text, big)) + (big ? 12 : 10), h = big ? BIG_H : TAG_H
      const sp = env.span(x - w / 2, x + w / 2)
      if (sp) {
        let y = up ? sp.hiY - GAP - h : sp.loY + GAP
        for (let k = 0; k < 3 && !done; k++) {
          const r = { x: x - w / 2, y, w, h }
          if (free(r)) { done = { i: c.b.i, t: c.b.t, side: c.side, kind, filled: c.filled, text, usd: c.usd, ...r, cx: x } }
          else {
            // 往外挪：越过挡住它的那块
            const blk = [...env.avoid, ...placed].filter(a => hit(a, r))
            if (!blk.length) break
            y = up ? Math.min(...blk.map(a => a.y)) - 2 - h : Math.max(...blk.map(a => a.y + a.h)) + 2
          }
        }
      }
    }
    if (!done) {
      const sp = env.span(x - TRI_W / 2, x + TRI_W / 2)
      if (sp) {
        const r = { x: x - TRI_W / 2, y: up ? sp.hiY - GAP - TRI_H : sp.loY + GAP, w: TRI_W, h: TRI_H }
        // 三角之间不比（一根一侧只有一个）；只躲文字与已摆的金额签
        if (r.y >= env.top && r.y + r.h <= env.bottom && !env.avoid.some(a => hit(a, r)) && !placed.some(a => a.h > TRI_H && hit(a, r)))
          done = { i: c.b.i, t: c.b.t, side: c.side, kind: 'tri', filled: c.filled, text: '', usd: c.usd, ...r, cx: x }
      }
    }
    if (done) { out.push(done); placed.push(done) }
  }
  return out
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
