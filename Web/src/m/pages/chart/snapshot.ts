/* 手机网页版 · 行情页成片（照 iOS Main/ChartSnapshotRenderer.swift）
 *
 * 「分享图片」与「记一笔」附的那张图是同一张：顶上一条身份条（基础币 /USDT · 周期，右边最新价与涨跌），
 * 中间是眼前这张图（图的几层画布原样合成，十字线先收掉），右下角一个很小的「Hkline」落款。
 * 画布是引擎按设备像素画好的，这里只按 2× 叠一遍，不重描。
 */
import type { ChartHandle } from '../../chart'
import { INTERVAL_SHORT, type Interval } from '../../chart/series'
import { S } from '../../../market'
import { grouped, fmtPrice, changePercentText } from '../../model/rowText'
import { splitPair } from './header'

const SCALE = 2
const cssVar = (name: string, fallback = ''): string =>
  getComputedStyle(document.documentElement).getPropertyValue(name).trim() || fallback

/** 图上现有的几层画布，按叠放顺序、连同各自相对图根的位置 */
function chartLayers(chart: ChartHandle): { root: HTMLElement; layers: { c: HTMLCanvasElement; x: number; y: number; w: number; h: number }[] } {
  const root = (chart.el.querySelector('.m-chart') as HTMLElement | null) ?? chart.el
  const box = root.getBoundingClientRect()
  const layers = [...root.querySelectorAll('canvas')].filter(c => c.width > 0 && c.height > 0 && getComputedStyle(c).display !== 'none').map(c => {
    const r = c.getBoundingClientRect()
    return { c, x: r.left - box.left, y: r.top - box.top, w: r.width, h: r.height }
  })
  return { root, layers }
}

/** 只要图本身（CSS 像素宽高 × scale）；图还没量出尺寸或没数据时返回 null */
export function chartCanvas(chart: ChartHandle, scale = SCALE): HTMLCanvasElement | null {
  const s = chart.state
  if (!s || s.input.series.isEmpty) return null
  chart.clearCrosshair()
  chart.redrawNow()
  const { root, layers } = chartLayers(chart)
  // 滚动容器里内容可能比视口高（副图多时）：只取眼前那一段
  const view = chart.el.getBoundingClientRect()
  const top = chart.el.scrollTop
  const w = Math.round(view.width), h = Math.round(Math.min(view.height, root.getBoundingClientRect().height))
  if (w < 2 || h < 2) return null
  const out = document.createElement('canvas')
  out.width = w * scale; out.height = h * scale
  const g = out.getContext('2d')
  if (!g) return null
  g.fillStyle = cssVar('--k-bg', cssVar('--chart'))
  g.fillRect(0, 0, out.width, out.height)
  g.scale(scale, scale)
  g.translate(0, -top)
  for (const l of layers) g.drawImage(l.c, l.x, l.y, l.w, l.h)
  return out
}

/** 成片：身份条 + 图 + 落款 */
export function shotCanvas(chart: ChartHandle, symbol: string, interval: Interval): HTMLCanvasElement | null {
  const body = chartCanvas(chart)
  if (!body) return null
  const w = body.width / SCALE, chartH = body.height / SCALE
  const stripH = 52, footH = 22
  const out = document.createElement('canvas')
  out.width = w * SCALE; out.height = (stripH + chartH + footH) * SCALE
  const g = out.getContext('2d')!
  g.scale(SCALE, SCALE)
  g.fillStyle = cssVar('--app', cssVar('--k-bg'))
  g.fillRect(0, 0, w, stripH + chartH + footH)
  g.drawImage(body, 0, stripH, w, chartH)

  const ui = cssVar('--font-ui', 'system-ui, sans-serif'), num = cssVar('--font-num', ui)
  const ink = cssVar('--ink'), ink3 = cssVar('--ink3')
  const s = S.symbols.get(symbol)
  const pct = s?.pct ?? null
  const tint = pct == null ? ink : pct >= 0 ? cssVar('--up') : cssVar('--down')
  const { base, quote } = splitPair(symbol)
  const pad = 12, mid = stripH / 2
  g.textBaseline = 'alphabetic'
  // 左：BTC /USDT · 1时
  g.font = `600 17px ${ui}`; g.fillStyle = ink; g.textAlign = 'left'
  g.fillText(base, pad, mid + 6)
  const x = pad + g.measureText(base).width + 4
  g.font = `600 11px ${ui}`; g.fillStyle = ink3
  const tail = `/${quote} · ${INTERVAL_SHORT[interval] ?? interval}`
  g.fillText(tail, x, mid + 6)
  // 右：价格一行、涨跌一行小字
  g.textAlign = 'right'
  g.font = `600 17px ${num}`; g.fillStyle = tint
  g.fillText(s?.price != null ? grouped(fmtPrice(s.price, s.dec ?? 2)) : '—', w - pad, mid + 1)
  g.font = `600 11px ${num}`; g.fillStyle = pct == null ? ink3 : tint
  g.fillText(changePercentText(pct), w - pad, mid + 16)
  // 落款
  g.font = `600 10px ${ui}`; g.fillStyle = ink3; g.globalAlpha = 0.7
  g.fillText('Hkline', w - pad, stripH + chartH + 15)
  g.globalAlpha = 1
  return out
}

export function canvasBlob(c: HTMLCanvasElement, type = 'image/png', quality?: number): Promise<Blob | null> {
  return new Promise(res => c.toBlob(b => res(b), type, quality))
}

/** JPEG 的 base64（不带 data: 前缀），宽封顶 maxW；超过 maxBytes 逐档降质量，降不下来返回 null */
export function jpegBase64(c: HTMLCanvasElement, maxW = 1200, maxBytes = 2 * 1024 * 1024): string | null {
  let src = c
  if (c.width > maxW) {
    src = document.createElement('canvas')
    src.width = maxW; src.height = Math.round(c.height * maxW / c.width)
    src.getContext('2d')!.drawImage(c, 0, 0, src.width, src.height)
  }
  for (const q of [0.85, 0.7, 0.55]) {
    const url = src.toDataURL('image/jpeg', q)
    const b64 = url.slice(url.indexOf(',') + 1)
    if (b64.length * 0.75 <= maxBytes) return b64
  }
  return null
}
