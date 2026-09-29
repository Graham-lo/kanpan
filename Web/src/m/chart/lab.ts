// 仅开发：图表实验台（/web/m/lab.html）。整屏一张真数据图，参数见 lab.html 顶部注释。
import '../styles/tokens.css'
import '../styles/base.css'
import { loadUniverse, setStreams, setRoute } from '../../market'
import type { IndicatorID } from '../indicator/ids'
import type { PriceMode } from './geometry'
import type { Interval } from './series'
import { withOverlay } from './state'
import { createChart, type ChartHandle } from './index'

const q = new URLSearchParams(location.search)
const list = (k: string, d: string) => (q.get(k) ?? d).split(',').map(s => s.trim().toUpperCase()).filter(Boolean) as IndicatorID[]
const host = document.getElementById('lab')!
const statusEl = document.getElementById('lab-status')!

setRoute('direct')
void loadUniverse()

const chart: ChartHandle = createChart(host, {
  symbol: q.get('sym') ?? 'BTCUSDT',
  interval: (q.get('iv') ?? '1h') as Interval,
  overlays: list('main', 'MA'),
  subs: list('subs', 'VOL,MACD'),
  orderFlow: q.get('of') === '1',
  landscape: q.get('land') === '1',
  // cmp=ETHUSDT,SOLUSDT（对比，最多三只）；depth=1（盘口五档）；pm=linear|log|percent（价格轴）
  compareSymbols: (q.get('cmp') ?? '').split(',').map(s => s.trim().toUpperCase()).filter(Boolean).map(s => 'binance/usd_m/' + s),
  depth: q.get('depth') === '1',
  priceMode: (['linear', 'log', 'percent'] as const).includes(q.get('pm') as PriceMode) ? q.get('pm') as PriceMode : 'log',
  streams: names => setStreams(names, names),
})

let crossed = false
chart.on('status', e => {
  statusEl.textContent = e.error ?? (e.loading ? '加载中…' : '')
  const f = Number(q.get('cross'))
  if (crossed || e.loading || !e.bars || !(f > 0 && f < 1)) return
  crossed = true
  // 等首帧量完再放十字线（验收截图用）
  requestAnimationFrame(() => requestAnimationFrame(() => {
    const st = chart.state, L = chart.view.chartLayout
    if (!st || !L) return
    const v = st.viewport.view, s = st.input.series
    const t = v.from + (v.to - v.from) * f
    const index = Math.max(0, Math.min(s.count - 1, s.index(t)))
    chart.view.state = withOverlay(st, { crosshair: { index, pane: null, t: s.time(index), price: s.close[index] } })
  }))
})

Object.assign(window, { chart })
