/* Hkline Web · 美元指数的推送（自家服务器 /v1/market/stream?source=macro）
 *
 * 照 docs/美元指数-协议-2026-10-05.md 第 6 节：帧是币安组合流形状，流名只认 dxy@ticker 与 dxy@kline_<周期>；
 * 一条连接最多 32 路（美元指数最多也就行情 + 几个周期，一条够用）；连上或 SUBSCRIBE 立刻回当前快照；
 * 休市时没有行情帧，服务端每 15 秒一帧心跳——看门狗认心跳，40 秒一帧都没有才当断线。
 * 不论用户选直连还是网关都走这一条（它唯一的来源就是自家服务器）。
 * 由 stream.ts 的 setStreams 把 dxy@ 开头的流名分过来，调用方不用知道它走的是另一条连接。
 */
import type { Bar } from '../chart/calc'
import { S, emit } from './state'
import { apiOrigin } from './rest'
import { MACRO_SYMBOL, applyMacroTicker } from './macro'
import { ago } from '../util/clock'

const MAX_STREAMS = 32
const SILENCE_MS = 40_000
const MAX_BACKOFF_MS = 15_000
const STREAM = /^dxy@(?:ticker|kline_(?:1m|3m|5m|15m|30m|1h|2h|4h|6h|8h|12h|1d|3d|1w|1M))$/

/** 是不是该走美元指数这条连接的流名 */
export function isMacroStream(name: string): boolean { return name.startsWith('dxy@') }
/** 服务端认的流名（别的发过去会回 error） */
export function validMacroStream(name: string): boolean { return STREAM.test(name) }

let sock: WebSocket | null = null
let want: string[] = []
const subscribed = new Set<string>()
let id = 1
let retry = 0
let retryTimer: ReturnType<typeof setTimeout> | null = null
let watchdog: ReturnType<typeof setInterval> | null = null
let last = 0

function url(): string {
  return apiOrigin().replace(/^http/, 'ws') + '/v1/market/stream?source=macro'
}

/** 设定要订的美元指数流（空 = 关掉连接） */
export function setMacroStreams(list: string[]): void {
  want = [...new Set(list.filter(validMacroStream))].slice(0, MAX_STREAMS)
  if (!want.length) { close(); return }
  if (!sock) { open(); return }
  reconcile()
}

function reconcile(): void {
  if (!sock || sock.readyState !== WebSocket.OPEN) return
  const w = new Set(want)
  const add = want.filter(x => !subscribed.has(x))
  const del = [...subscribed].filter(x => !w.has(x))
  if (del.length) { sock.send(JSON.stringify({ method: 'UNSUBSCRIBE', params: del, id: id++ })); del.forEach(x => subscribed.delete(x)) }
  if (add.length) { sock.send(JSON.stringify({ method: 'SUBSCRIBE', params: add, id: id++ })); add.forEach(x => subscribed.add(x)) }
}

function open(): void {
  if (retryTimer) { clearTimeout(retryTimer); retryTimer = null }
  if (typeof WebSocket === 'undefined') return
  const s = new WebSocket(`${url()}&streams=${want.join('/')}`)
  sock = s
  subscribed.clear(); want.forEach(x => subscribed.add(x))
  last = Date.now()
  s.onopen = () => { if (sock !== s) return; last = Date.now(); reconcile() }
  s.onmessage = ev => {
    if (sock !== s) return
    last = Date.now()
    let m: { stream?: string; data?: Record<string, any>; result?: unknown; id?: number }
    try { m = JSON.parse(String(ev.data)) } catch { return }
    if (!m || typeof m !== 'object' || !m.data) return
    retry = 0
    handleMacroFrame(m.data)
  }
  s.onclose = () => { if (sock === s) fail() }
  s.onerror = () => { /* onclose 会跟着来 */ }
  if (!watchdog) watchdog = setInterval(() => {
    if (sock && sock.readyState === WebSocket.OPEN && ago(last) > SILENCE_MS) fail()
  }, 5000)
}

function close(): void {
  if (retryTimer) { clearTimeout(retryTimer); retryTimer = null }
  if (watchdog) { clearInterval(watchdog); watchdog = null }
  const s = sock
  sock = null
  subscribed.clear()
  if (s) { s.onclose = null; s.onmessage = null; s.onopen = null; try { s.close() } catch { /* 已经关了 */ } }
}

function fail(): void {
  const keep = want
  close()
  want = keep
  if (!want.length) return
  const wait = Math.min(MAX_BACKOFF_MS, 1000 * 2 ** retry++)
  retryTimer = setTimeout(() => { retryTimer = null; if (want.length && !sock) open() }, wait)
}

/** 一帧（组合流的 data 部分）落进品种表 / 发事件；单测直接喂 */
export function handleMacroFrame(d: Record<string, any>): void {
  const s = S.symbols.get(MACRO_SYMBOL)
  switch (d?.e) {
    case 'heartbeat':
      // 休市时只有心跳：认它的 marketState（变灰与否），不算一帧行情
      // 心跳也证明链路活着：报价没变不等于行情停住，刷新 lastTick 免得开市时的安静段被判成停住
      if (s) s.lastTick = Date.now()
      if (s && typeof d.marketState === 'string') {
        const closed = d.marketState === 'closed'
        if (s.closed !== closed) { s.closed = closed; emit({ type: 'ticker', symbol: MACRO_SYMBOL, dir: 0 }) }
      }
      break
    case '24hrTicker': {
      if (!s) return
      const prev = s.price
      const ok = applyMacroTicker(s, { lastPrice: d.c, priceChange: d.p, priceChangePercent: d.P, openPrice: d.o, highPrice: d.h, lowPrice: d.l, marketState: d.marketState }, +d.C || +d.E || 0)
      s.lastTick = Date.now()
      emit({ type: 'ticker', symbol: MACRO_SYMBOL, dir: !ok || prev == null || s.price == null ? 0 : Math.sign(s.price - prev) })
      break
    }
    case 'kline': {
      const k = d.k
      if (!k) return
      const bar: Bar = { t: k.t, o: +k.o, h: +k.h, l: +k.l, c: +k.c, v: +k.q || 0, tb: +k.Q || 0, bv: +k.v || 0 }
      emit({ type: 'kline', symbol: MACRO_SYMBOL, iv: k.i, bar })
      break
    }
  }
}

/** 回到前台：断着就立刻重连 */
if (typeof document !== 'undefined') {
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && want.length && !sock) { retry = 0; open() }
  })
}

export function macroStreamDebug(): { want: string[]; subscribed: string[]; open: boolean } {
  return { want, subscribed: [...subscribed], open: !!sock && sock.readyState === WebSocket.OPEN }
}
