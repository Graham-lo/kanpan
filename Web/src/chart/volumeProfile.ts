/* Hkline Web · 成交量分布的画法（照 TradingView 的 Fixed Range Volume Profile，按 TV 源码的 HHist 渲染逐条对齐）
 *
 * 主图「成交量分布」（可见区间，overlays.drawVpvr）与画线「固定区间 / 锚定成交量分布」（drawTools.drawFvp）共用这一套：
 *   · 只有成交量分布不画框住区间的边框实线（选中也只多手柄圆点）；区间底色只铺一层 fillRect（#26C6DA α 0.05，可改色、可关）。
 *   · 柱子四色，与 K 线涨跌色脱钩、深浅同一套：价值区外 涨 #26C6DA / 跌 #EC407A α 0.5，价值区内同色 α 0.75。
 *   · 最长一行 = 区间宽 × 宽度%（出厂 30%）− 这一行的段数（px）；放左从左沿往右长，放右从右沿往左长，
 *     每段从基线起依次往外接（买卖分开：涨段贴基线、跌段接在后面）；短于 0.5 px 的段不画。
 *   · 行与行之间的缝：平均行高 ≥ 1 CSS px 时留 1 个物理像素（floor(像素比)），否则不留；坐标按物理像素取整。
 *   · 三种看法：买卖分开 [买, 卖]；合计 [买 + 卖]；净差 [多的 − 少的, 少的, 少的]，都用占优那一方的颜色，
 *     透明度依次原样 / 一半 / 四分之一（三种看法一行总长都是买 + 卖）。
 *   · 横线：价值区上沿 / 下沿（浅粉 1 px，出厂开）、控制点（紫，出厂关），从区间左沿画到右沿，打开「向右延伸」画到绘图区右沿；
 *     发展中的控制点（灰）/ 价值区（#00BCD4）是逐根阶梯折线（出厂关）。每条线各有开关、颜色、线型、粗细。
 *   · 数值（出厂关）：每行「涨量 × 跌量」（放右时倒过来），写在基线内侧 3 px、行顶下 0.7 行高处；最底下再多一行合计（颜色提亮 1.5 倍）。
 *     字号 = min(round(1.7 × 区间宽 ÷ 字数), round(0.6 × 行高))，全部行统一取最小的那个，小于 7.5 px 就一行都不写。
 * 版式（profileLayout）是纯函数，便于单测几何；drawProfile 只按版式往画布上涂。
 */
import type { Developing, Vpvr, VpvrMode } from './overlays'

/** 主图可见区间分布的行数：可见价格区间的像素高 ÷ 4（每行至少 4 px），1–240 行 */
export function profileRows(pxH: number): number { return Math.max(1, Math.min(240, Math.floor(Math.abs(pxH) / 4))) }

export const PROFILE = {
  widthPct: 30,
  /** 画线分布的出厂行数（TV「行布局：行数 24」） */
  rows: 24,
  /** 数值字号下限：比它小就一行都不写 */
  minFont: 7.5,
} as const

export type LineDash = 'solid' | 'dashed' | 'dotted'
export interface ProfileLine { on: boolean; color: string; width: number; dash: LineDash; /** 向右延伸到绘图区右沿 */ extend?: boolean }
/** 一张分布图的全部外观（画线的 style 叠在出厂值上得到它） */
export interface ProfileLook {
  /** 画不画柱子 */
  vp: boolean
  /** 最长一行占区间宽的百分比 */
  widthPct: number
  placement: 'left' | 'right'
  up: string
  down: string
  vaUp: string
  vaDown: string
  /** 每行标量 */
  values: boolean
  valuesColor: string
  vah: ProfileLine
  val: ProfileLine
  poc: ProfileLine
  devPoc: ProfileLine
  devVa: ProfileLine
  /** 区间底色 */
  bg: { on: boolean; color: string }
}

/** 出厂外观（TV 源码值）：柱子、底色、发展中价值区深浅同一套；灰的（数值、发展中控制点）浅底 #0F0F0F、深底 #DBDBDB；
 *  价值区上下沿浅粉、控制点紫是用户定的（浅底上压深一档才看得清） */
export function profileDefaults(dark: boolean): ProfileLook {
  const L = (on: boolean, color: string, width = 1, dash: LineDash = 'solid'): ProfileLine => ({ on, color, width, dash, extend: false })
  const gray = dark ? '#DBDBDB' : '#0F0F0F'
  return {
    vp: true, widthPct: PROFILE.widthPct, placement: 'left',
    up: '#26C6DA80', down: '#EC407A80', vaUp: '#26C6DABF', vaDown: '#EC407ABF',
    values: false, valuesColor: gray,
    vah: L(true, dark ? '#F8BBD0' : '#F48FB1'), val: L(true, dark ? '#F8BBD0' : '#F48FB1'), poc: L(false, dark ? '#B388FF' : '#9575CD', 2),
    devPoc: L(false, gray), devVa: L(false, '#00BCD4'),
    bg: { on: true, color: '#26C6DA0D' },
  }
}

/** 底色深不深（读 K 线区底色的亮度；读不出按深色） */
export function isDarkBg(bg: string): boolean {
  const s = (bg || '').trim()
  let r = 0, g = 0, b = 0
  const h = /^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.exec(s)
  if (h) {
    const x = h[1].length === 3 ? h[1].split('').map(c => c + c).join('') : h[1].slice(0, 6)
    const n = parseInt(x, 16); r = n >> 16 & 255; g = n >> 8 & 255; b = n & 255
  } else {
    const m = /rgba?\(\s*([\d.]+)[\s,]+([\d.]+)[\s,]+([\d.]+)/i.exec(s)
    if (!m) return true
    r = +m[1]; g = +m[2]; b = +m[3]
  }
  return 0.2126 * r + 0.7152 * g + 0.0722 * b < 128
}

/** #RRGGBBAA → [#RRGGBB, α]；不带透明度的照原样、α 1 */
export function splitAlpha(c: string): [string, number] {
  if (/^#[0-9a-f]{8}$/i.test(c)) return ['#' + c.slice(1, 7), Math.round(parseInt(c.slice(7, 9), 16) / 255 * 100) / 100]
  return [c, 1]
}

export interface ProfileInput {
  /** 区间左右沿（像素） */
  x0: number
  x1: number
  v: Pick<Vpvr, 'lo' | 'step' | 'rows' | 'poc' | 'vaLo' | 'vaHi'>
  mode: VpvrMode
  look: ProfileLook
  priceToY: (price: number) => number
  /** 画布上能画的纵向范围（窗格上下沿），范围外的行不画 */
  clipY?: [number, number]
  /** 发展中的控制点 / 价值区（逐根价），xs[k] 是第 k 根的横坐标 */
  dev?: Developing & { xs: number[] }
  /** 横线「向右延伸」延到这里（绘图区右沿） */
  extendTo?: number
  /** 物理像素比（缝宽与取整按它算），缺省 1 */
  pr?: number
  /** 数值格式（缺省 TV 成交量格式） */
  fmt?: (v: number) => string
}

export interface ProfileRect { x: number; y: number; w: number; h: number; color: string; alpha: number; row: number }
export interface ProfileHLine { y: number; x0: number; x1: number; color: string; alpha: number; width: number; dash: LineDash; kind: 'poc' | 'vah' | 'val' }
export interface ProfilePath { kind: 'devPoc' | 'devVah' | 'devVal'; pts: ({ x: number; y: number } | null)[]; color: string; alpha: number; width: number; dash: LineDash }
/** 一行数值；row = -1 是最底下的合计行 */
export interface ProfileValue { x: number; y: number; align: 'left' | 'right'; text: string; color: string; row: number }
export interface ProfileLayout {
  /** 最长一行的长度（区间宽 × 宽度% − 段数） */
  maxW: number
  rects: ProfileRect[]
  lines: ProfileHLine[]
  paths: ProfilePath[]
  values: ProfileValue[]
  /** 数值统一字号（0 = 不写） */
  font: number
  base: { x: number; y: number; w: number; h: number; color: string; alpha: number } | null
}

/** TV 成交量格式：K / M / B / T，三位有效数字，单位前空一格 */
export function fmtVolume(v: number): string {
  if (!Number.isFinite(v)) return '—'
  const a = Math.abs(v)
  const U: [number, string][] = [[1e12, 'T'], [1e9, 'B'], [1e6, 'M'], [1e3, 'K']]
  const sig = (x: number) => String(+x.toPrecision(3))
  for (const [u, n] of U) if (a >= u * 0.9995) return sig(v / u) + ' ' + n
  return a >= 100 ? String(Math.round(v)) : sig(v)
}

/** 颜色提亮（TV shiftColor：各通道 × k，封顶 255；透明度不变） */
export function shiftColor(c: string, k: number): string {
  const m = /^#([0-9a-f]{6})([0-9a-f]{2})?$/i.exec(c)
  if (!m) return c
  const n = parseInt(m[1], 16)
  const ch = (x: number) => Math.min(255, Math.round(x * k)).toString(16).padStart(2, '0')
  return '#' + ch(n >> 16 & 255) + ch(n >> 8 & 255) + ch(n & 255) + (m[2] ?? '')
}

const scaleAlpha = ([c, a]: [string, number], k: number): [string, number] => [c, Math.round(a * k * 1000) / 1000]

/** 版式：每一块柱子、每一条线、底色、数值的像素坐标（纯函数） */
export function profileLayout(inp: ProfileInput): ProfileLayout {
  const { v, mode, priceToY: Y, look } = inp
  const pr = inp.pr && inp.pr > 0 ? inp.pr : 1
  const dev2css = (x: number) => x / pr
  const x0 = Math.min(inp.x0, inp.x1), x1 = Math.max(inp.x0, inp.x1), W = x1 - x0
  const pct = Number.isFinite(look.widthPct) ? Math.max(1, Math.min(100, look.widthPct)) : PROFILE.widthPct
  const segN = mode === 'split' ? 2 : mode === 'delta' ? 3 : 1
  const maxW = Math.max(pct * W / 100 - segN, 0)
  const right = look.placement === 'right'
  const UP = splitAlpha(look.up), DN = splitAlpha(look.down), VUP = splitAlpha(look.vaUp), VDN = splitAlpha(look.vaDown)
  const n = v.rows.length
  const out: ProfileLayout = { maxW, rects: [], lines: [], paths: [], values: [], font: 0, base: null }
  if (!n || !(v.step > 0)) return out
  const hi = v.lo + n * v.step
  const yHi = Y(hi), yLo = Y(v.lo)
  if (look.bg.on) {
    const [bc, ba] = splitAlpha(look.bg.color)
    if (ba > 0) {
      const bx = Math.round(x0 * pr), by = Math.round(Math.min(yHi, yLo) * pr)
      out.base = { x: dev2css(bx), y: dev2css(by), w: dev2css(Math.round(x1 * pr) - bx), h: dev2css(Math.round(Math.max(yHi, yLo) * pr) - by), color: bc, alpha: ba }
    }
  }

  // 每行的段：[量, 颜色]；三种看法一行的总量都是买 + 卖，最长一行按它定
  const segsOf = (k: number): { vals: number[]; cols: [string, number][]; shown: number[] } => {
    const row = v.rows[k], inVa = k >= v.vaLo && k <= v.vaHi
    const U = inVa ? VUP : UP, D = inVa ? VDN : DN
    if (mode === 'total') return { vals: [row.buy + row.sell], cols: [U], shown: [row.buy + row.sell] }
    if (mode === 'delta') {
      const mx = Math.max(row.buy, row.sell), mn = Math.min(row.buy, row.sell), c = row.buy >= row.sell ? U : D
      return { vals: [mx - mn, mn, mn], cols: [c, scaleAlpha(c, 0.5), scaleAlpha(c, 0.25)], shown: [mx - mn] }
    }
    return { vals: [row.buy, row.sell], cols: [U, D], shown: [row.buy, row.sell] }
  }
  let mx = 0, sumH = 0
  for (let k = 0; k < n; k++) { const r = v.rows[k]; mx = Math.max(mx, r.buy + r.sell); sumH += Math.abs(Y(v.lo + (k + 1) * v.step) - Y(v.lo + k * v.step)) }
  const avgH = sumH / n
  const gap = Math.floor(avgH * pr) >= pr ? Math.floor(pr) : 0
  const fmt = inp.fmt ?? fmtVolume
  const sign = right ? -1 : 1, xBase = right ? x1 : x0
  const texts: { text: string; y: number; h: number; color: string; row: number }[] = []
  const totals: number[] = []
  const [c0, c1] = inp.clipY ?? [-Infinity, Infinity]
  if (look.vp && mx > 0 && Number.isFinite(mx)) {
    for (let k = n - 1; k >= 0; k--) {   // 从上往下（TV 的 bars 顺序），合计行落在最底下一行之下
      const s = segsOf(k)
      if (look.values) for (let t = 0; t < s.vals.length; t++) totals[t] = (totals[t] || 0) + s.vals[t]
      const ya = Y(v.lo + (k + 1) * v.step), yb = Y(v.lo + k * v.step)
      const top = Math.min(ya, yb), bot = Math.max(ya, yb)
      if (top > c1 || bot < c0) continue
      let x = xBase
      for (let t = 0; t < s.vals.length; t++) {
        const u = x + sign * (maxW * s.vals[t] / mx)
        if (Math.abs(u - x) < 0.5) continue
        const m0 = Math.round(x * pr), m1 = Math.round(u * pr), f = Math.round(top * pr)
        const g = Math.max(Math.round(bot * pr) - f - gap, 1)
        out.rects.push({ x: dev2css(Math.min(m0, m1)), y: dev2css(f), w: dev2css(Math.abs(m1 - m0)), h: dev2css(g), color: s.cols[t][0], alpha: s.cols[t][1], row: k })
        x = u
      }
      if (look.values) {
        const arr = right ? s.shown.slice().reverse() : s.shown
        texts.push({ text: arr.map(fmt).join(' × '), y: top, h: bot - top, color: look.valuesColor, row: k })
      }
    }
    if (look.values && totals.length) {
      const arr = right ? totals.slice().reverse() : totals
      texts.push({ text: arr.map(fmt).join(' × '), y: Math.max(yHi, yLo), h: avgH, color: shiftColor(look.valuesColor, 1.5), row: -1 })
    }
  }
  if (texts.length) {
    const size = Math.min(...texts.map(q => Math.min(Math.round(1.7 * W / Math.max(1, q.text.length)), Math.round(0.6 * q.h))))
    if (size >= PROFILE.minFont) {
      out.font = size
      for (const q of texts) out.values.push({ x: xBase + 3 * sign, y: q.y + 0.7 * q.h, align: right ? 'right' : 'left', text: q.text, color: q.color, row: q.row })
    }
  }
  const xEnd = (o: ProfileLine) => o.extend && inp.extendTo != null && inp.extendTo > x1 ? inp.extendTo : x1
  const snapY = (y: number, w: number) => { const d = Math.max(1, Math.round(w * pr)); return (Math.round(y * pr) + (d % 2 ? 0.5 : 0)) / pr }
  const ln = (o: ProfileLine, price: number, kind: ProfileHLine['kind']) => {
    if (!o.on) return
    const [color, alpha] = splitAlpha(o.color)
    out.lines.push({ y: snapY(Y(price), o.width), x0, x1: xEnd(o), color, alpha, width: o.width, dash: o.dash, kind })
  }
  ln(look.vah, v.lo + (v.vaHi + 1) * v.step, 'vah')
  ln(look.val, v.lo + v.vaLo * v.step, 'val')
  ln(look.poc, v.lo + (v.poc + 0.5) * v.step, 'poc')
  const dev = inp.dev
  if (dev) {
    const path = (o: ProfileLine, s: number[], kind: ProfilePath['kind']) => {
      if (!o.on) return
      const [color, alpha] = splitAlpha(o.color)
      // 阶梯折线：每根内价位不变，换根时竖着接上（照 TradingView 的发展中控制点）
      const pts: ProfilePath['pts'] = []
      for (let k = 0; k < s.length; k++) {
        const p = s[k], x = dev.xs[k]
        if (!Number.isFinite(p) || x == null) { pts.push(null); continue }
        const y = Y(p)
        if (k > 0 && Number.isFinite(s[k - 1])) pts.push({ x, y: Y(s[k - 1]) })
        pts.push({ x, y })
      }
      if (pts.length) out.paths.push({ kind, pts, color, alpha, width: o.width, dash: o.dash })
    }
    path(look.devPoc, dev.poc, 'devPoc')
    path(look.devVa, dev.vah, 'devVah')
    path(look.devVa, dev.val, 'devVal')
  }
  return out
}

export function linePattern(dash: LineDash, w: number): number[] {
  return dash === 'dashed' ? [w * 3 + 2, w * 2.5 + 1] : dash === 'dotted' ? [Math.max(1, w * 0.5), w * 2 + 1] : []
}

/** 按版式画（颜色用 globalAlpha 叠透明度，CSS 变量给的任何颜色写法都认）；fontFamily 是数值的字体 */
export function drawProfile(c: CanvasRenderingContext2D, inp: ProfileInput, fontFamily = 'sans-serif'): ProfileLayout {
  const lay = profileLayout(inp)
  c.save()
  if (inp.clipY) { c.beginPath(); c.rect(-1e5, inp.clipY[0], 2e5, inp.clipY[1] - inp.clipY[0]); c.clip() }
  if (lay.base) { c.globalAlpha = lay.base.alpha; c.fillStyle = lay.base.color; c.fillRect(lay.base.x, lay.base.y, lay.base.w, lay.base.h) }
  for (const q of lay.rects) { c.globalAlpha = q.alpha; c.fillStyle = q.color; c.fillRect(q.x, q.y, q.w, q.h) }
  c.lineCap = 'butt'; c.lineJoin = 'round'
  for (const l of lay.lines) {
    c.globalAlpha = l.alpha; c.strokeStyle = l.color; c.lineWidth = l.width; c.setLineDash(linePattern(l.dash, l.width))
    c.beginPath(); c.moveTo(l.x0, l.y); c.lineTo(l.x1, l.y); c.stroke()
  }
  for (const pth of lay.paths) {
    c.globalAlpha = pth.alpha; c.strokeStyle = pth.color; c.lineWidth = pth.width; c.setLineDash(linePattern(pth.dash, pth.width))
    c.beginPath()
    let st = false
    for (const q of pth.pts) { if (!q) { st = false; continue } if (st) c.lineTo(q.x, q.y); else { c.moveTo(q.x, q.y); st = true } }
    c.stroke()
  }
  c.setLineDash([])
  if (lay.font) {
    c.font = `${lay.font}px ${fontFamily}`; c.textBaseline = 'alphabetic'
    for (const q of lay.values) { const [col, a] = splitAlpha(q.color); c.globalAlpha = a; c.fillStyle = col; c.textAlign = q.align; c.fillText(q.text, q.x, q.y) }
  }
  c.restore()
  return lay
}
