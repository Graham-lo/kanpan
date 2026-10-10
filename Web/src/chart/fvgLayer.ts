/* Hkline Web · 电脑网页主图的「公允价值缺口」层（2026-10-10）
 *
 * 算法与参数三端共用（src/analysis/fvg.ts ← KanpanCore/…/Analysis/fvg.json），这里只管画：
 *   · 盒子从中间那根 K 线的左沿画到图的右缘，填充 0.12、不描边；中线（原始缺口 50%）0.5px 虚线 0.35，
 *     回补到不再包含中线时不画。
 *   · 层级：主力订单流的色块之上、K 线之下（和 iOS 同序）——走 ChartLayer.beforeCandles。
 *   · 颜色不用涨跌色（和订单流的方向色撞）：多头取布林那抹蓝、空头取琥珀，深浅两套各一份。
 *   · 对比模式、等幅 K 线下不画；不参与价格范围；不响应悬停与点击。
 * 开关只读 getter（st.autoLayers 里有没有 'FVG'），切开关不重建图层，标脏重画即可。
 */
import { fvgZones, type FVGZone } from '../analysis/fvg'
import type { Bar } from './calc'
import type { ChartGeometry, ChartLayer } from './chart'

/** 图层要用到的那点图表状态（TVChart 结构上满足；测试里给个桩） */
export interface FVGChartLike {
  bars: readonly Bar[]
  /** 一根 K 线的毫秒数 */
  iv: number
  compareOn(): boolean
}

export interface FVGLayerOptions {
  chart: FVGChartLike
  /** 开没开（读 st.autoLayers） */
  on: () => boolean
  /** 另外不画的场合（等幅 K 线：K 线不按时间走，「正在走的那根」无从判定） */
  hidden?: () => boolean
  now?: () => number
}

export interface FVGLayer extends ChartLayer {
  /** 当前的缺口（带缓存；测试与调试用） */
  zones(): FVGZone[]
  /** 实际做过几次整段扫描（测试看缓存有没有命中） */
  readonly scans: number
}

/** 填充 / 中线的透明度（照 iOS ChartRenderer+FVG） */
export const FVG_FILL_ALPHA = 0.12
export const FVG_MID_ALPHA = 0.35
/** 多头：布林那抹蓝（电脑网页布林中轨 #2962FF，深色提亮一档）；空头：琥珀。浅色底不是纯白，0.12 的透明照样分得开 */
export const FVG_COLORS = {
  light: { bull: '#2962FF', bear: '#D97706' },
  dark: { bull: '#5B8CFF', bear: '#F59E0B' },
} as const

/** 最后一根还没走完（开盘时间 + 一根的时长 > 现在）就不算收线：它只参与回补、不参与生成 */
export function closedCountOf(bars: readonly Bar[], iv: number, now: number): number {
  const n = bars.length
  if (!n) return 0
  return bars[n - 1].t + iv > now ? n - 1 : n
}

/** 画布底色深不深（图表设置能改底色，不能只看页面主题） */
export function isDarkColor(css: string): boolean {
  let r = 255, g = 255, b = 255
  const s = css.trim()
  if (s.startsWith('rgb')) { const m = s.match(/[\d.]+/g); if (m && m.length >= 3) { r = +m[0]; g = +m[1]; b = +m[2] } }
  else if (s[0] === '#') {
    const h = s.length === 4 ? s.slice(1).split('').map(ch => ch + ch).join('') : s.slice(1, 7)
    const n = parseInt(h, 16)
    if (Number.isFinite(n)) { r = n >> 16 & 255; g = n >> 8 & 255; b = n & 255 }
  } else return typeof document !== 'undefined' && document.documentElement.dataset.theme === 'dark'
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 < 0.35
}

const rgba = (hex: string, a: number): string => {
  const n = parseInt(hex.slice(1, 7), 16)
  return `rgba(${n >> 16 & 255},${n >> 8 & 255},${n & 255},${a})`
}

export function createFVGLayer(opts: FVGLayerOptions): FVGLayer {
  const { chart } = opts
  const now = opts.now ?? Date.now
  // 缓存键：K 线数组本身（setData / prependData 换新数组）+ 根数（推送新开一根是 push）
  // + 最后一根的时间与高低收（推送改同一根是原地改）+ 收线根数（到点收线但还没来新推送）
  let kArr: readonly Bar[] | null = null, kN = -1, kT = NaN, kH = NaN, kL = NaN, kC = NaN, kClosed = -1
  let cache: FVGZone[] = []
  let scans = 0

  function zones(): FVGZone[] {
    const bars = chart.bars, n = bars.length
    const closed = closedCountOf(bars, chart.iv, now())
    const last = bars[n - 1]
    if (bars === kArr && n === kN && closed === kClosed && (!last || (last.t === kT && last.h === kH && last.l === kL && last.c === kC))) return cache
    kArr = bars; kN = n; kClosed = closed
    kT = last?.t ?? NaN; kH = last?.h ?? NaN; kL = last?.l ?? NaN; kC = last?.c ?? NaN
    scans++
    cache = n ? fvgZones(bars, closed) : []
    return cache
  }

  function draw(c: CanvasRenderingContext2D, g: ChartGeometry): void {
    if (!opts.on() || opts.hidden?.() || chart.compareOn()) return
    const list = zones()
    if (!list.length) return
    const pal = isDarkColor(g.colors.bg) ? FVG_COLORS.dark : FVG_COLORS.light
    const right = g.plotW, top = g.pane.y, bottom = g.pane.y + g.pane.h, half = g.spacing / 2
    const mids: [string, number, number][] = []
    for (const z of list) {
      const x0 = Math.max(0, g.timeToX(z.startMs) - half)
      if (!(x0 < right)) continue
      const yT = g.priceToY(z.top), yB = g.priceToY(z.bottom)
      const y0 = Math.min(yT, yB), y1 = Math.max(yT, yB)
      if (y1 < top || y0 > bottom) continue
      const hex = z.side === 'bull' ? pal.bull : pal.bear
      c.fillStyle = rgba(hex, FVG_FILL_ALPHA)
      // 不足 1px 高的也留一道细条，不至于整个看不见
      c.fillRect(x0, y0, right - x0, Math.max(1, y1 - y0))
      if (z.midVisible) {
        const ym = g.priceToY(z.mid)
        if (ym >= top && ym <= bottom) mids.push([hex, x0, ym])
      }
    }
    if (!mids.length) return
    c.lineWidth = 0.5
    c.setLineDash([4, 3])
    for (const [hex, x0, ym] of mids) {
      c.strokeStyle = rgba(hex, FVG_MID_ALPHA)
      c.beginPath(); c.moveTo(x0, ym); c.lineTo(right, ym); c.stroke()
    }
    c.setLineDash([])
  }

  return {
    beforeCandles: draw,
    zones,
    get scans() { return scans },
  }
}
