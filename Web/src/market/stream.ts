/* Hkline Web · 实时推送
 *
 * 币安 U 本位合约的 WebSocket 2026-04 起按数据类型拆了路由：
 *   /market/stream —— kline、ticker、markPrice、aggTrade（这里全用它）
 *   /public/stream —— 深度（本阶段不接）
 * 旧的 wss://fstream.binance.com/stream 已经什么都不推了。
 *
 * 线路两档，用户在「我的 · 通用」里选，选了哪条就走哪条，不自动切换（和手机端同一条规矩）：
 *   直连 —— wss://fstream.binance.com/market/stream（默认）
 *   网关 —— wss://<本站>/market/stream，和手机「网关」那一档是同一个服务
 * 断了按 1 s、2 s、4 s … 最长 15 s 退避重连；连上 8 秒一帧都没有、或中途静默 30 秒，也当断线处理。
 * 一条连接常驻，品种变化时发 SUBSCRIBE / UNSUBSCRIBE，不重连。
 * 页面隐藏时只留「核心」几路（当前图表的 K 线与行情），回到前台再补回来。
 */
import type { Bar } from '../chart/calc'
import { S, emit, type Route } from './state'
import { emitTrade } from './trades'

const DIRECT = 'wss://fstream.binance.com/market/stream'
const MAX_STREAMS = 200
const FIRST_FRAME_MS = 8000
const SILENCE_MS = 30000

function gatewayURL(): string | null {
  if (typeof location === 'undefined' || !/^https?:$/.test(location.protocol)) return null
  return `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/market/stream`
}

let ws: WebSocket | null = null
let all: string[] = []
let core: string[] = []
let subscribed = new Set<string>()     // 当前连接上真正订着的
let msgId = 1
let retry = 0
let gotFrame = false
let debounce: ReturnType<typeof setTimeout> | null = null
let retryTimer: ReturnType<typeof setTimeout> | null = null
let firstFrameTimer: ReturnType<typeof setTimeout> | null = null
let watchdog: ReturnType<typeof setInterval> | null = null

function hidden(): boolean { return typeof document !== 'undefined' && document.visibilityState === 'hidden' }
function effective(): string[] { return (hidden() ? core : all).slice(0, MAX_STREAMS) }

/** all：前台要订的全部；core：页面隐藏时仍保留的 */
export function setStreams(list: string[], coreList: string[] = list): void {
  // 流名大小写敏感（月线是 kline_1M），品种部分由 streamName 负责转小写
  all = [...new Set(list)]
  core = [...new Set(coreList)]
  if (debounce) clearTimeout(debounce)
  debounce = setTimeout(apply, 150)
}

function apply(): void {
  debounce = null
  const want = effective()
  if (!want.length) { close(); return }
  if (!ws) { connect(); return }
  if (ws.readyState !== WebSocket.OPEN) return   // 连上后 onopen 会对账
  reconcile()
}

function reconcile(): void {
  if (!ws || ws.readyState !== WebSocket.OPEN) return
  const want = new Set(effective())
  const add = [...want].filter(x => !subscribed.has(x))
  const del = [...subscribed].filter(x => !want.has(x))
  if (del.length) { ws.send(JSON.stringify({ method: 'UNSUBSCRIBE', params: del, id: msgId++ })); del.forEach(x => subscribed.delete(x)) }
  if (add.length) { ws.send(JSON.stringify({ method: 'SUBSCRIBE', params: add, id: msgId++ })); add.forEach(x => subscribed.add(x)) }
  if (!want.size) close()
}

function urlFor(route: Route): string | null { return route === 'direct' ? DIRECT : gatewayURL() }

function connect(): void {
  close(true)
  const want = effective()
  if (!want.length) return
  let url = urlFor(S.route)
  if (!url) { S.route = 'direct'; url = DIRECT }
  S.wsState = 'connecting'; emit({ type: 'ws' })
  gotFrame = false
  const sock = new WebSocket(`${url}?streams=${want.join('/')}`)
  ws = sock
  subscribed = new Set(want)
  sock.onopen = () => {
    if (ws !== sock) return
    S.wsState = 'open'; emit({ type: 'ws' })
    reconcile()
    firstFrameTimer = setTimeout(() => { if (ws === sock && !gotFrame) fail(sock) }, FIRST_FRAME_MS)
  }
  sock.onmessage = ev => {
    if (ws !== sock) return
    if (!gotFrame) { gotFrame = true; retry = 0 }
    S.lastMsg = Date.now()
    handle(ev.data)
  }
  sock.onclose = () => { if (ws === sock) fail(sock) }
  sock.onerror = () => { /* onclose 会跟着来 */ }
  if (!watchdog) watchdog = setInterval(() => {
    if (ws && ws.readyState === WebSocket.OPEN && gotFrame && subscribed.size && Date.now() - S.lastMsg > SILENCE_MS) fail(ws)
  }, 5000)
}

function fail(sock: WebSocket): void {
  if (ws !== sock) return
  close(true)
  S.wsState = 'closed'; emit({ type: 'ws' })
  const delay = Math.min(15000, 1000 * 2 ** retry++)
  const wait = hidden() ? Math.max(delay, 10000) : delay
  if (retryTimer) clearTimeout(retryTimer)
  retryTimer = setTimeout(() => { retryTimer = null; if (effective().length) connect() }, wait)
}

function close(keepState = false): void {
  if (firstFrameTimer) { clearTimeout(firstFrameTimer); firstFrameTimer = null }
  if (ws) {
    const s = ws; ws = null
    s.onclose = null; s.onmessage = null; s.onopen = null
    try { s.close() } catch { /* 已经关了 */ }
  }
  subscribed.clear()
  if (!keepState) { S.wsState = 'idle'; emit({ type: 'ws' }) }
}

/** 回到前台立刻对账（补回隐藏时撤掉的几路），断着的话马上重连不再等退避 */
if (typeof document !== 'undefined') {
  document.addEventListener('visibilitychange', () => {
    if (!hidden() && !ws && effective().length) { if (retryTimer) { clearTimeout(retryTimer); retryTimer = null } retry = 0; connect(); return }
    if (debounce) clearTimeout(debounce)
    debounce = setTimeout(apply, hidden() ? 1500 : 0)
  })
}

// ------------------------------------------------------------ 消息
interface Frame { stream?: string; data?: Record<string, unknown>; result?: unknown; id?: number }

function handle(raw: unknown): void {
  let m: Frame
  try { m = JSON.parse(String(raw)) } catch { return }
  const d = (m.data || m) as Record<string, any>
  if (!d || typeof d !== 'object' || !d.e) return
  switch (d.e) {
    case '24hrTicker': {
      const s = S.symbols.get(d.s); if (!s) return
      const prev = s.price
      Object.assign(s, { price: +d.c, chg: +d.p, pct: +d.P, vol: +d.q, open: +d.o, hi: +d.h, lo: +d.l, count: +d.n, lastTick: Date.now() })
      emit({ type: 'ticker', symbol: d.s, dir: prev == null ? 0 : Math.sign(+d.c - prev) })
      break
    }
    case 'aggTrade': {
      const s = S.symbols.get(d.s); if (!s) return
      const p = +d.p, prev = s.price
      emitTrade(d.s, p, +d.q, +d.T, !!d.m)
      if (prev === p) { s.lastTick = Date.now(); return }
      s.price = p; s.lastTick = Date.now()
      if (s.open) { s.chg = p - s.open; s.pct = (p / s.open - 1) * 100 }
      if (s.hi != null && p > s.hi) s.hi = p
      if (s.lo != null && p < s.lo) s.lo = p
      emit({ type: 'ticker', symbol: d.s, dir: prev == null ? 0 : Math.sign(p - prev) })
      break
    }
    case 'kline': {
      const k = d.k
      const bar: Bar = { t: k.t, o: +k.o, h: +k.h, l: +k.l, c: +k.c, v: +k.q, tb: +k.Q, bv: +k.v }
      emit({ type: 'kline', symbol: d.s, iv: k.i, bar })
      break
    }
    case 'markPriceUpdate': {
      const s = S.symbols.get(d.s); if (!s) return
      Object.assign(s, { fr: d.r === '' ? s.fr : +d.r, nextFunding: d.T || s.nextFunding, mark: +d.p, index: +d.i })
      emit({ type: 'mark', symbol: d.s })
      break
    }
  }
}

export const streamName = {
  kline: (sym: string, iv: string) => `${sym.toLowerCase()}@kline_${iv}`,
  ticker: (sym: string) => `${sym.toLowerCase()}@ticker`,
  mark: (sym: string) => `${sym.toLowerCase()}@markPrice@1s`,
  trade: (sym: string) => `${sym.toLowerCase()}@aggTrade`,
}

/** 换线路：立即按新线路重连 */
export function setRoute(route: Route): void {
  if (route === 'gateway' && !gatewayURL()) route = 'direct'
  if (S.route === route) return
  S.route = route
  if (retryTimer) { clearTimeout(retryTimer); retryTimer = null }
  retry = 0
  if (effective().length) connect()
}

/** 测试与排障用：当前线路与订阅 */
export function streamDebug(): { route: Route; state: string; subscribed: string[] } {
  return { route: S.route, state: S.wsState, subscribed: [...subscribed] }
}
