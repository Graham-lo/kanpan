// 仅开发：图表压测台（src/m/chart/bench.html）。离线合成一屏「满载」：6000 根 1m、VOL / MACD / RSI、
// 30 条画线、约 2400 单主力订单流；scripts/m-chart-perf.mjs 在手机视口里对它甩、捏、拎十字线，量主线程开销。
// 数据全部本地合成（伪随机、固定种子），不连网、不订推送，每次跑出来的图一模一样。
import '../styles/tokens.css'
import '../styles/base.css'
import type { BigOrder } from '../../orderflow/types'
import type { Bar } from './series'
import type { Drawing, DrawingKind } from './drawing'
import { drawingWith } from './drawing'
import type { OrderFlowSnapshot } from '../../orderflow/group'
import { createChart } from './index'

const N = 6000, STEP = 60_000
const T0 = Date.UTC(2026, 9, 1) - N * STEP
let seed = 7
const rnd = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 }

const bars: Bar[] = []
let px = 60_000
for (let i = 0; i < N; i++) {
  const o = px, c = Math.max(1000, o + (rnd() - 0.5) * 80)
  const h = Math.max(o, c) + rnd() * 40, l = Math.min(o, c) - rnd() * 40
  const v = 50 + rnd() * 400
  bars.push({ openTime: T0 + i * STEP, open: o, high: h, low: l, close: c, volume: v, takerBuy: v * rnd() })
  px = c
}

const at = (i: number) => bars[Math.max(0, Math.min(N - 1, i))]
const kinds: DrawingKind[] = ['hline', 'trend', 'ray', 'rectangle', 'channel', 'fibonacci', 'measure', 'note', 'priceRange', 'position',
  'pitchfork', 'triangle', 'ellipse', 'fibExtension', 'xabcd', 'elliottImpulse', 'priceLabel', 'callout', 'gannBox', 'fibFan',
  'anchoredVWAP', 'fixedVolumeProfile', 'regression', 'dateRange', 'datePriceRange', 'arrowLine', 'crossLine', 'headShoulders', 'abcd', 'vline']
const drawings: Drawing[] = kinds.map((kind, k) => {
  const end = N - 1 - (k % 6) * 25
  const n = kind === 'regression' ? 3 : ({ hline: 1, vline: 1, note: 1, priceLabel: 1, crossLine: 1, anchoredVWAP: 1 } as Record<string, number>)[kind]
    ?? ({ channel: 3, position: 3, fibExtension: 3, pitchfork: 3, triangle: 3, abcd: 4, xabcd: 5, elliottImpulse: 6, headShoulders: 7 } as Record<string, number>)[kind] ?? 2
  const pts = Array.from({ length: n }, (_, j) => {
    const b = at(end - 120 + j * Math.floor(110 / Math.max(1, n - 1)))
    return { t: b.openTime, p: j % 2 ? b.high : b.low }
  })
  const d = drawingWith(kind, pts, `dBENCH-${k}`)
  if (kind === 'note' || kind === 'callout' || kind === 'priceLabel') d.text = '压测标注'
  return d
})

const orders: BigOrder[] = []
for (let k = 0; k < 2400; k++) {
  const live = k % 3 === 0
  const start = T0 + Math.floor(rnd() * N) * STEP
  const b = at(Math.floor((start - T0) / STEP))
  const side = k % 2 ? 'bid' : 'ask'
  const price = Math.round((side === 'bid' ? b.low - rnd() * 300 : b.high + rnd() * 300) / 100) * 100
  const notional = 1_000_000 + rnd() * 20_000_000
  orders.push({
    venueID: k % 4 === 0 ? 'binance-spot' : 'binance-usdtPerp', exchange: 'binance', product: k % 4 === 0 ? 'spot' : 'usdtPerp',
    side, bucket: price / 100, price, firstSeenMs: start, endMs: live ? null : start + (2 + Math.floor(rnd() * 200)) * STEP,
    status: live ? 'live' : k % 5 === 0 ? 'filled' : 'cancelled', initialNotional: notional, notional,
    filledNotional: k % 5 === 0 ? notional * 0.6 : 0, threshold: 1_000_000, vanishedNotional: live ? null : notional,
  })
}
const snapshot: OrderFlowSnapshot = {
  symbol: 'BTCUSDT', phase: 'ready', orders, asOfMs: T0 + N * STEP,
  thresholds: { spot: 1_000_000, usdtPerp: 1_000_000, step: 100 },
}

const chart = createChart(document.getElementById('bench')!, {
  symbol: 'BTCUSDT', interval: '1m', overlays: ['MA'], subs: ['VOL', 'MACD', 'RSI'],
  offline: true, orderFlow: true, drawings,
  symbolInfo: s => ({ symbol: s, base: 'BTC', priceDecimals: 1 }),
  loadBars: async (_s, _iv, end) => (end == null ? bars.slice() : []),
  orderFlowSource: push => {
    let sent = false
    return {
      setWanted(on) { if (on && !sent) { sent = true; setTimeout(() => push(snapshot), 0) } },
      noteView() { /* 合成数据一次给齐 */ },
      dispose() { /* 无 */ },
    }
  },
  depthSource: null,
})
Object.assign(window, { chart, benchReady: () => (chart.state?.input.series.count ?? 0) >= N && chart.state?.overlay.orderFlow != null })
