/* Hkline 手机网页 · 图上大单签：纯几何（2026-10-08，照手机原型 docs/原型-手机大单与爆仓-2026-10-08.html §08 / §09）
 *
 * 只管「一根 → 画不画、画成哪一档、画在哪」，不碰画布、不碰数据源：数据（每根大买 / 大卖合计、三档金额线）由
 * orderflow/bigTags.ts 的 BigBarCache / TierCache 给，画法在 bigTradeLayer.ts。
 *
 * 规则与 iOS KanpanChart/BigTradeSigns.swift 逐条同一份（两端一起改）：
 *   · 一根最多一枚，只画主导方向（买卖里大的那一侧）：买挂最高价上方、尖朝上；卖挂最低价下方、尖朝下（翻面也不变）。
 *   · 一档 = 直径 5 的圆点（方向色 70%），离高 / 低点 3；二档 = 8 × 7 实心三角，离高 / 低点 4；
 *     三档 = 三角 + 金额胶囊（高 16、左右各 5、11 / 600 白字、方向色底，离三角尖 2）。
 *     一根窄于 3 一律不出胶囊（金额签会横跨十几根，看不出是哪根）；一根宽到 9（日线这类稀的周期）二档也出胶囊。
 *   · 胶囊进了图例带（主图顶上 24）/ 掉出主图 / 压到画线文字或别的签：先只把胶囊翻到 K 线另一侧，
 *     再整枚翻过去，两侧都不行就退成三角（先本侧后另一侧），三角也放不下就不画——不往外挪。
 *   · 金额大的先排（大的先占位），挤的时候留下的是大签；输出按根序。
 *   · 命中区 44 × 44（以记号为心；胶囊整块再向外扩到 44），几枚都中取离手指最近的那枚。
 */
import type { Rect, Tiers } from '../../orderflow/bigTags'
import { hit, tierOf } from '../../orderflow/bigTags'

export type SignShape = 'dot' | 'tri' | 'cap'
export type SignSide = 'buy' | 'sell'

/** 尺寸（pt），与 iOS 同值 */
export const SIGN = {
  dot: 5,
  dotAlpha: 0.7,
  dotGap: 3,
  triW: 8,
  triH: 7,
  triGap: 4,
  capH: 16,
  capPadX: 5,
  capGap: 2,
  capFont: 11,
  /** 一根窄于这么多一律不出胶囊 */
  textMinSpacing: 3,
  /** 一根宽到这么多二档也出胶囊 */
  sparseCapsuleSpacing: 9,
  /** 胶囊离主图左右边至少留这么多 */
  capEdge: 2,
  legendBand: 24,
  hit: 44,
} as const

/** 一根的输入：x = 蜡烛中心，yHigh / yLow = 高 / 低点的纵坐标（屏幕向下为正） */
export interface SignBar {
  i: number
  t: number
  x: number
  yHigh: number
  yLow: number
  bb: number
  bs: number
}

export interface SignEnv {
  /** 签能落的竖直范围：top = 图例带下沿（主图顶 + max(24, 图例内缩)），bottom = 主图下沿 */
  top: number
  bottom: number
  /** 图宽（价格轴左沿） */
  plotW: number
  /** 一根的宽（决定出不出胶囊） */
  spacing: number
  tiers: Tiers | null
  /** 要躲的字框（画线文字） */
  avoid: readonly Rect[]
  /** 量金额签上的字宽 */
  measure: (text: string) => number
  fmt: (usd: number) => string
  /** 胶囊横跨 [x0, x1] 的那几根里的最高 / 最低（y）；给了就让开它们 */
  span?: (x0: number, x1: number) => { hiY: number; loY: number } | null
}

export interface Sign {
  i: number
  t: number
  side: SignSide
  tier: 1 | 2 | 3
  /** 'cap' = 三角 + 胶囊 */
  shape: SignShape
  usd: number
  /** 记号（点 / 三角）是否翻到了 K 线另一侧 */
  flipped: boolean
  /** 记号落在最高价上方（true）还是最低价下方 */
  above: boolean
  /** 点 / 三角的外框 */
  mark: Rect
  /** 金额胶囊的外框（shape === 'cap' 才有） */
  cap: Rect | null
  /** 胶囊是否在 K 线上方（无胶囊时同 above） */
  capAbove: boolean
  /** 金额文案（没胶囊也给，读屏用） */
  text: string
  /** 记号中心（命中与光环的圆心） */
  cx: number
  cy: number
  /** 整枚签外框（记号 ∪ 胶囊） */
  bounds: Rect
}

const unionRect = (a: Rect, b: Rect | null): Rect => {
  if (!b) return a
  const x = Math.min(a.x, b.x), y = Math.min(a.y, b.y)
  return { x, y, w: Math.max(a.x + a.w, b.x + b.w) - x, h: Math.max(a.y + a.h, b.y + b.h) - y }
}

export function dotRect(b: SignBar, above: boolean): Rect {
  const d = SIGN.dot
  return { x: b.x - d / 2, y: above ? b.yHigh - SIGN.dotGap - d : b.yLow + SIGN.dotGap, w: d, h: d }
}

export function triRect(b: SignBar, above: boolean): Rect {
  return {
    x: b.x - SIGN.triW / 2,
    y: above ? b.yHigh - SIGN.triGap - SIGN.triH : b.yLow + SIGN.triGap,
    w: SIGN.triW, h: SIGN.triH,
  }
}

/** 胶囊和三角同侧时贴在三角外沿（离尖 2）；三角在另一侧时胶囊照样离 K 线 4 + 7 + 2。
 *  胶囊横跨的那几根若比本根更高 / 更低，让开它们（env.span）。横向夹在主图里（左右各留 2） */
export function capRect(b: SignBar, w: number, tri: Rect, triAbove: boolean, above: boolean, env: Pick<SignEnv, 'plotW' | 'span'>): Rect | null {
  const lo = SIGN.capEdge + w / 2, hi = env.plotW - SIGN.capEdge - w / 2
  if (hi < lo) return null
  const cx = Math.min(Math.max(b.x, lo), hi)
  const span = env.span?.(cx - w / 2, cx + w / 2) ?? null
  const off = SIGN.triGap + SIGN.triH + SIGN.capGap
  if (above) {
    let bottom = (triAbove ? tri.y : b.yHigh - off + SIGN.capGap) - SIGN.capGap
    if (span) bottom = Math.min(bottom, span.hiY - SIGN.capGap)
    return { x: cx - w / 2, y: bottom - SIGN.capH, w, h: SIGN.capH }
  }
  let top = (triAbove ? b.yLow + off - SIGN.capGap : tri.y + tri.h) + SIGN.capGap
  if (span) top = Math.max(top, span.loY + SIGN.capGap)
  return { x: cx - w / 2, y: top, w, h: SIGN.capH }
}

const EPS = 0.001

/**
 * 排一屏的签。bars 只给这一屏看得见的根（顺序随意）；返回按根序。
 */
export function planSigns(bars: readonly SignBar[], env: SignEnv): Sign[] {
  if (!env.tiers) return []
  const cand: { b: SignBar; side: SignSide; usd: number; tier: 1 | 2 | 3 }[] = []
  for (const b of bars) {
    const side: SignSide = b.bb >= b.bs ? 'buy' : 'sell'
    const usd = side === 'buy' ? b.bb : b.bs
    const tier = tierOf(usd, env.tiers)
    if (tier === 0) continue
    if (!Number.isFinite(b.x) || !Number.isFinite(b.yHigh) || !Number.isFinite(b.yLow)) continue
    cand.push({ b, side, usd, tier })
  }
  cand.sort((a, z) => z.usd - a.usd || z.b.i - a.b.i)

  const caps: Rect[] = [], marks: Rect[] = []
  const insideV = (r: Rect) => r.y >= env.top - EPS && r.y + r.h <= env.bottom + EPS
  const insideH = (r: Rect) => r.x >= -EPS && r.x + r.w <= env.plotW + EPS
  const clear = (r: Rect) => !env.avoid.some(a => hit(a, r))
  const markOK = (r: Rect) => insideV(r) && clear(r) && !caps.some(c => hit(c, r))
  const capOK = (r: Rect) => insideV(r) && insideH(r) && clear(r) && !caps.some(c => hit(c, r)) && !marks.some(m => hit(m, r))

  const out: Sign[] = []
  for (const c of cand) {
    const pref = c.side === 'buy'
    const text = env.fmt(c.usd)
    const wantsCap = c.tier >= 3 ? env.spacing >= SIGN.textMinSpacing : c.tier === 2 ? env.spacing >= SIGN.sparseCapsuleSpacing : false
    const make = (shape: SignShape, mark: Rect, above: boolean, cap: Rect | null, capAbove: boolean): Sign => ({
      i: c.b.i, t: c.b.t, side: c.side, tier: c.tier, shape, usd: c.usd, flipped: above !== pref, above,
      mark, cap, capAbove, text, cx: mark.x + mark.w / 2, cy: mark.y + mark.h / 2, bounds: unionRect(mark, cap),
    })
    let sign: Sign | null = null
    if (c.tier === 1) {
      for (const above of [pref, !pref]) {
        const r = dotRect(c.b, above)
        if (markOK(r)) { sign = make('dot', r, above, null, above); break }
      }
    } else {
      if (wantsCap) {
        const w = Math.ceil(env.measure(text) + 2 * SIGN.capPadX)
        // 候选：（三角在哪侧，胶囊在哪侧）——先都在本侧，再只翻胶囊，再整枚翻
        const combos: [boolean, boolean][] = [[pref, pref], [pref, !pref], [!pref, !pref]]
        for (const [triAbove, capAbove] of combos) {
          const tri = triRect(c.b, triAbove)
          if (!markOK(tri)) continue
          const cap = capRect(c.b, w, tri, triAbove, capAbove, env)
          if (!cap || !capOK(cap) || hit(cap, tri)) continue
          sign = make('cap', tri, triAbove, cap, capAbove)
          break
        }
      }
      if (!sign) {
        for (const above of [pref, !pref]) {
          const r = triRect(c.b, above)
          if (markOK(r)) { sign = make('tri', r, above, null, above); break }
        }
      }
    }
    if (sign) {
      out.push(sign)
      marks.push(sign.mark)
      if (sign.cap) caps.push(sign.cap)
    }
  }
  return out.sort((a, z) => a.i - z.i)
}

/** 命中：记号中心 44 × 44；胶囊整块再各向外扩到 44。几枚都中取离手指最近的那枚（胶囊按到外框的距离） */
export function hitSign(signs: readonly Sign[], x: number, y: number): Sign | null {
  const half = SIGN.hit / 2
  let best: Sign | null = null, bd = Infinity
  for (const s of signs) {
    let d = Math.hypot(x - s.cx, y - s.cy)
    let ok = Math.abs(x - s.cx) <= half && Math.abs(y - s.cy) <= half
    const c = s.cap
    if (c) {
      const px = Math.max(0, (SIGN.hit - c.w) / 2), py = Math.max(0, (SIGN.hit - c.h) / 2)
      if (x >= c.x - px && x <= c.x + c.w + px && y >= c.y - py && y <= c.y + c.h + py) ok = true
      const dx = Math.max(c.x - x, 0, x - c.x - c.w), dy = Math.max(c.y - y, 0, y - c.y - c.h)
      d = Math.min(d, Math.hypot(dx, dy))
    }
    if (ok && d < bd) { bd = d; best = s }
  }
  return best
}

/** 读屏：「买方大单 1.2M，12:30 这根」（日线及以上写「10月8日 这根」） */
export function signLabel(s: Pick<Sign, 'side' | 'usd'>, fmt: (usd: number) => string, when: string): string {
  return `${s.side === 'buy' ? '买方' : '卖方'}大单 ${fmt(s.usd)}，${when} 这根`
}
