/* Hkline Web · 成交量分布的画法（照 TradingView 的 Volume Profile）
 *
 * 主图「成交量分布」（可见区间，overlays.drawVpvr）与画线「固定区间成交量分布」（drawTools.drawFvp）共用这一套：
 *   · 柱子实色：最长一行 = 区间宽的 30%（至少 16 px）；七成价值区内的行 alpha 0.9，区外同色 alpha 0.35；
 *     行与行之间留 1 px 缝（每行不到 3 px 时不留）。
 *   · 三种看法：买卖分开（每行涨色在左、跌色接在右）、净差（一根，买多涨色 / 卖多跌色，长按 |买−卖|）、合计（单色）。
 *   · 价值区上下沿两条 1 px 实线、控制点一条 1.5 px 橙线，都从区间左沿画到右沿。
 *   · 底板（可选）：整个区间铺一层淡底（固定区间有，可见区间没有）。
 *   · 方向：固定区间从左沿往右长；可见区间（alignRight）贴着右沿（价格轴）往左长。
 * 版式（profileLayout）是纯函数，便于单测几何；drawProfile 只按版式往画布上涂。
 */
import type { Vpvr, VpvrMode } from './overlays'

/** 行数：区间在屏上的像素高 ÷ 4（每行至少 4 px），1–240 行（固定区间与可见区间同一口径） */
export function profileRows(pxH: number): number { return Math.max(1, Math.min(240, Math.floor(Math.abs(pxH) / 4))) }

export const PROFILE = {
  widthFrac: 0.3,
  minW: 16,
  alphaIn: 0.9,
  alphaOut: 0.35,
  baseAlpha: 0.06,
  vaWidth: 1,
  pocWidth: 1.5,
  poc: '#FF9800',
  total: '#5B8DEF',
} as const

export interface ProfileColors {
  up: string
  down: string
  /** 合计看法的单色 */
  total?: string
  /** 价值区上下沿线与底板的颜色（画线的工具色） */
  line: string
  poc?: string
}

export interface ProfileInput {
  /** 区间左右沿（像素） */
  x0: number
  x1: number
  v: Pick<Vpvr, 'lo' | 'step' | 'rows' | 'poc' | 'vaLo' | 'vaHi'>
  mode: VpvrMode
  colors: ProfileColors
  priceToY: (price: number) => number
  /** 贴右沿往左长（可见区间，紧挨价格轴） */
  alignRight?: boolean
  /** 铺底板（固定区间） */
  base?: boolean
  /** 画布上能画的纵向范围（窗格上下沿），范围外的行不画 */
  clipY?: [number, number]
}

export interface ProfileRect { x: number; y: number; w: number; h: number; color: string; alpha: number; row: number }
export interface ProfileLine { y: number; x0: number; x1: number; color: string; width: number; kind: 'poc' | 'vah' | 'val' }
export interface ProfileLayout {
  maxW: number
  rects: ProfileRect[]
  lines: ProfileLine[]
  base: { x: number; y: number; w: number; h: number; color: string; alpha: number } | null
}

/** 版式：每一块柱子、每一条线、底板的像素坐标（纯函数） */
export function profileLayout(inp: ProfileInput): ProfileLayout {
  const { v, mode, priceToY: Y } = inp
  const x0 = Math.min(inp.x0, inp.x1), x1 = Math.max(inp.x0, inp.x1), W = x1 - x0
  const maxW = Math.max(PROFILE.minW, W * PROFILE.widthFrac)
  const up = inp.colors.up, down = inp.colors.down, total = inp.colors.total || PROFILE.total
  const n = v.rows.length
  const out: ProfileLayout = { maxW, rects: [], lines: [], base: null }
  if (!n || !(v.step > 0)) return out
  const hi = v.lo + n * v.step
  const yHi = Y(hi), yLo = Y(v.lo)
  if (inp.base) out.base = { x: x0, y: Math.min(yHi, yLo), w: W, h: Math.abs(yLo - yHi), color: inp.colors.line, alpha: PROFILE.baseAlpha }

  let mx = 0
  for (const r of v.rows) mx = Math.max(mx, mode === 'delta' ? Math.abs(r.buy - r.sell) : r.buy + r.sell)
  if (mx > 0 && Number.isFinite(mx)) {
    // 行的上下沿取整后共用，行与行之间的缝一样宽
    const edge = (k: number) => Math.round(Y(v.lo + k * v.step))
    const rowPx = Math.abs(Y(v.lo + v.step) - Y(v.lo))
    const gap = rowPx >= 3 ? 1 : 0
    const [c0, c1] = inp.clipY ?? [-Infinity, Infinity]
    const R = Math.round(x1), L = Math.round(x0)
    // 从基线起一段段往外接：segs 是 [长度, 颜色]，按顺序从左到右排（贴右时整体靠右）
    const place = (k: number, top: number, h: number, a: number, segs: [number, string][]) => {
      const sum = segs.reduce((s, q) => s + q[0], 0)
      let acc = inp.alignRight ? R - sum : L
      for (const [w, color] of segs) {
        const xa = Math.round(acc), xb = Math.round(acc + w)
        acc += w
        if (xb > xa) out.rects.push({ x: xa, y: top, w: xb - xa, h, color, alpha: a, row: k })
      }
    }
    for (let k = 0; k < n; k++) {
      const row = v.rows[k]
      const ya = edge(k + 1), yb = edge(k)
      const top = Math.min(ya, yb), h = Math.max(1, Math.abs(yb - ya) - gap)
      if (top > c1 || top + h < c0) continue
      const a = k >= v.vaLo && k <= v.vaHi ? PROFILE.alphaIn : PROFILE.alphaOut
      if (mode === 'total') place(k, top, h, a, [[(row.buy + row.sell) / mx * maxW, total]])
      else if (mode === 'delta') { const d = row.buy - row.sell; place(k, top, h, a, [[Math.abs(d) / mx * maxW, d >= 0 ? up : down]]) }
      else place(k, top, h, a, [[row.buy / mx * maxW, up], [row.sell / mx * maxW, down]])
    }
  }
  const ln = (price: number, color: string, width: number, kind: ProfileLine['kind']) =>
    out.lines.push({ y: Math.round(Y(price)) + 0.5, x0, x1, color, width, kind })
  ln(v.lo + (v.vaHi + 1) * v.step, inp.colors.line, PROFILE.vaWidth, 'vah')
  ln(v.lo + v.vaLo * v.step, inp.colors.line, PROFILE.vaWidth, 'val')
  ln(v.lo + (v.poc + 0.5) * v.step, inp.colors.poc || PROFILE.poc, PROFILE.pocWidth, 'poc')
  return out
}

/** 按版式画（颜色用 globalAlpha 叠透明度，CSS 变量给的任何颜色写法都认） */
export function drawProfile(c: CanvasRenderingContext2D, inp: ProfileInput): ProfileLayout {
  const lay = profileLayout(inp)
  c.save()
  if (inp.clipY) { c.beginPath(); c.rect(-1e5, inp.clipY[0], 2e5, inp.clipY[1] - inp.clipY[0]); c.clip() }
  if (lay.base) { c.globalAlpha = lay.base.alpha; c.fillStyle = lay.base.color; c.fillRect(lay.base.x, lay.base.y, lay.base.w, lay.base.h) }
  for (const q of lay.rects) { c.globalAlpha = q.alpha; c.fillStyle = q.color; c.fillRect(q.x, q.y, q.w, q.h) }
  c.globalAlpha = 1; c.setLineDash([]); c.lineCap = 'butt'
  for (const l of lay.lines) { c.strokeStyle = l.color; c.lineWidth = l.width; c.beginPath(); c.moveTo(l.x0, l.y); c.lineTo(l.x1, l.y); c.stroke() }
  c.restore()
  return lay
}
