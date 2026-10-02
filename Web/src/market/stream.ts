/* Hkline Web · 实时推送
 *
 * 币安 U 本位合约在 `fstream.binance.com` 上的 WebSocket 2026-04 起按数据类型拆了路由
 * （/market/stream 行情、/public/stream 深度，/stream 什么都不推了）；`dstream.binance.me` 没拆，
 * `/stream` 上行情与深度都在，而且是国内能直连的那一台（见下面 DIRECT 的注释）。
 *
 * 线路两档，用户在「我的 · 通用」里选，选了哪条就走哪条，不自动切换（和手机端同一条规矩）：
 *   直连 —— wss://dstream.binance.me/stream（和 iOS 出厂同一台）
 *   网关 —— wss://<本站>/market/stream，和手机「网关」那一档是同一个服务（网页版出厂是它：
 *           REST 也要经新加坡透传，国内不开代理 fapi.binance.com 连不上，见 rest.ts 的 viaRoute）
 *
 * 连接池（多图布局最多 16 格，每格 K 线 + 行情两路，再加自选、提醒）：
 *   每条连接订的流有上限——直连按币安合约文档一条 200 路，网关按 stream_hub 的规矩一条 64 路、
 *   同一来源合计 160 路。不够就多开一条；流变少了先把最空的那条上的流挪到别的连接上、再关掉它，
 *   所以连接数始终是 ⌈流数 / 上限⌉，快速换布局、换品种不会越开越多。
 *   已经在某条连接上的流不挪（换一只品种只动它自己的两路），挪动只发生在要收掉一条连接的时候。
 * 每条连接各自判活：断了按 1 s、2 s、4 s … 最长 15 s 退避（退避期间不开新连接，已连着的照常订）；
 * 连上 8 秒一帧都没有、或中途静默 30 秒，也当断线处理。
 * 页面隐藏时只留「核心」几路（当前图表的 K 线与行情、提醒），回到前台再补回来。
 */
import type { Bar } from '../chart/calc'
import { S, emit, type Route } from './state'
import { emitTrade } from './trades'

/**
 * 直连的推送域名照 iOS 出厂的 `dstream.binance.me`（`KanpanNetwork/Binance/BinanceProvider.swift`
 * `defaultStreamHost`）：生产盘、国内不开代理能直连，`/stream` 上 kline / ticker / markPrice / aggTrade
 * 四族都在发（2026-10-03 实测 12 秒 21 帧，其中 kline 15 帧）。旧的 `fstream.binance.com` 在国内解析被污染、
 * 握手就被重置（Surge 的 BinanceDirect.list 也只放 dstream.binance.me / fstream.binance.me / *.binance.vision 直连）。
 */
const DIRECT = 'wss://dstream.binance.me/stream'
/** 每条连接最多订几路 */
export const PER_CONN: Record<Route, number> = { direct: 200, gateway: 64 }
/** 一共最多订几路（网关同一来源 160 路；直连给一个宽松的保险） */
export const TOTAL: Record<Route, number> = { direct: 1000, gateway: 160 }
const FIRST_FRAME_MS = 8000
const SILENCE_MS = 30000

function gatewayURL(): string | null {
  if (typeof location === 'undefined' || !/^https?:$/.test(location.protocol)) return null
  return `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/market/stream`
}

// ------------------------------------------------------------ 分配（纯逻辑，单测覆盖）
/**
 * 把想要的流分到连接上。current = 现有各条连接上分着的流；返回每条现有连接的新分配
 * （null = 这条要关掉），以及要新开的几条的分配。
 *   1. 每条连接只留还想要的流；
 *   2. 连接数多于 ⌈n / cap⌉ 时，从最空的那条开始收，它上面的流算作没分配；
 *   3. 没分配的流先填有空位的连接（按原顺序），还剩就新开连接，每条至多 cap 路。
 */
export function assignStreams(current: readonly (readonly string[])[], want: readonly string[], cap: number): { keep: (string[] | null)[]; open: string[][] } {
  const W = new Set(want)
  const need = W.size ? Math.ceil(W.size / cap) : 0
  const sets = current.map(c => c.filter(x => W.has(x)))
  const alive = sets.map((_, i) => i)
  while (alive.length > need) {
    let k = 0
    for (let j = 1; j < alive.length; j++) if (sets[alive[j]].length < sets[alive[k]].length) k = j
    alive.splice(k, 1)
  }
  const keepSet = new Set(alive)
  const placed = new Set<string>()
  for (const i of alive) for (const x of sets[i]) placed.add(x)
  const orphans = want.filter(x => !placed.has(x) && (placed.add(x), true))
  const keep: (string[] | null)[] = sets.map((s, i) => keepSet.has(i) ? s.slice(0, cap) : null)
  for (const s of keep) if (s) while (s.length < cap && orphans.length) s.push(orphans.shift()!)
  const open: string[][] = []
  while (orphans.length) open.push(orphans.splice(0, cap))
  return { keep, open }
}

// ------------------------------------------------------------ 连接池
interface Conn {
  sock: WebSocket
  url: string
  /** 分给这条的流（连上后对账成这组） */
  want: string[]
  /** 这条连接上真正订着的 */
  subscribed: Set<string>
  gotFrame: boolean
  last: number
  firstTimer: ReturnType<typeof setTimeout> | null
}

let conns: Conn[] = []
let all: string[] = []
let core: string[] = []
let msgId = 1
let retry = 0
/** 断线退避：这之前不开新连接 */
let blockedUntil = 0
let failed = false
let debounce: ReturnType<typeof setTimeout> | null = null
let retryTimer: ReturnType<typeof setTimeout> | null = null
let watchdog: ReturnType<typeof setInterval> | null = null

function offline(): boolean { return typeof navigator !== 'undefined' && navigator.onLine === false }
function hidden(): boolean { return typeof document !== 'undefined' && document.visibilityState === 'hidden' }
/** 这一刻该订的：隐藏时只留核心；超出总上限时核心优先 */
function effective(): string[] {
  if (hidden()) return core.slice(0, TOTAL[S.route])
  const c = new Set(core)
  return [...core.filter(x => all.includes(x)), ...all.filter(x => !c.has(x))].slice(0, TOTAL[S.route])
}

/** all：前台要订的全部；core：页面隐藏时仍保留的 */
export function setStreams(list: string[], coreList: string[] = list, opts: { now?: boolean } = {}): void {
  // 流名大小写敏感（月线是 kline_1M），品种部分由 streamName 负责转小写
  all = [...new Set(list)]
  core = [...new Set(coreList)]
  if (debounce) clearTimeout(debounce)
  // now：冷启动时和品种表、K 线并行先把连接建起来，不等 150 ms 的合并窗口
  if (opts.now) { debounce = null; apply(); return }
  debounce = setTimeout(apply, 150)
}

function urlFor(route: Route): string | null { return route === 'direct' ? DIRECT : gatewayURL() }

function paint(): void {
  const want = effective().length
  const st: typeof S.wsState = !want && !conns.length ? 'idle'
    : failed ? 'closed'
    : conns.length && conns.every(c => c.sock.readyState === WebSocket.OPEN) ? 'open' : 'connecting'
  if (S.wsState !== st) { S.wsState = st; emit({ type: 'ws' }) }
}

function apply(): void {
  debounce = null
  const want = effective()
  let url = urlFor(S.route)
  if (!url) { S.route = 'direct'; url = DIRECT }
  // 换了线路的连接一律收掉
  for (const c of conns.slice()) if (c.url !== url) drop(c)
  const plan = assignStreams(conns.map(c => c.want), want, PER_CONN[S.route])
  const old = conns
  conns = []
  old.forEach((c, i) => {
    const w = plan.keep[i]
    if (!w) { drop(c); return }
    c.want = w; conns.push(c); reconcile(c)
  })
  const t = Date.now()
  if (plan.open.length) {
    if (t < blockedUntil || offline()) scheduleRetry(Math.max(0, blockedUntil - t))
    else plan.open.forEach(w => open(url!, w))
  } else if (failed && conns.every(c => c.gotFrame)) failed = false   // 断掉那条的流已经挪到别的连接上
  paint()
}

function reconcile(c: Conn): void {
  if (c.sock.readyState !== WebSocket.OPEN) return   // 连上后 onopen 会对账
  const want = new Set(c.want)
  const add = c.want.filter(x => !c.subscribed.has(x))
  const del = [...c.subscribed].filter(x => !want.has(x))
  if (del.length) { c.sock.send(JSON.stringify({ method: 'UNSUBSCRIBE', params: del, id: msgId++ })); del.forEach(x => c.subscribed.delete(x)) }
  if (add.length) { c.sock.send(JSON.stringify({ method: 'SUBSCRIBE', params: add, id: msgId++ })); add.forEach(x => c.subscribed.add(x)) }
}

function open(url: string, want: string[]): void {
  const sock = new WebSocket(`${url}?streams=${want.join('/')}`)
  const c: Conn = { sock, url, want, subscribed: new Set(want), gotFrame: false, last: Date.now(), firstTimer: null }
  conns.push(c)
  sock.onopen = () => {
    if (!conns.includes(c)) return
    reconcile(c)
    c.firstTimer = setTimeout(() => { if (conns.includes(c) && !c.gotFrame) fail(c) }, FIRST_FRAME_MS)
    paint()
  }
  sock.onmessage = ev => {
    if (!conns.includes(c)) return
    if (!c.gotFrame) {
      c.gotFrame = true
      if (c.firstTimer) { clearTimeout(c.firstTimer); c.firstTimer = null }
      retry = 0; blockedUntil = 0
      if (failed && conns.every(x => x.gotFrame)) { failed = false; paint() }
    }
    c.last = S.lastMsg = Date.now()
    handle(ev.data)
  }
  sock.onclose = () => { if (conns.includes(c)) fail(c) }
  sock.onerror = () => { /* onclose 会跟着来 */ }
  if (!watchdog) watchdog = setInterval(() => {
    const now = Date.now()
    for (const x of conns.slice()) if (x.sock.readyState === WebSocket.OPEN && x.gotFrame && x.subscribed.size && now - x.last > SILENCE_MS) fail(x)
  }, 5000)
}

/** 收掉一条连接（不算断线） */
function drop(c: Conn): void {
  if (c.firstTimer) { clearTimeout(c.firstTimer); c.firstTimer = null }
  conns = conns.filter(x => x !== c)
  const s = c.sock
  s.onclose = null; s.onmessage = null; s.onopen = null
  try { s.close() } catch { /* 已经关了 */ }
}

/** 一条连接断了：收掉它，退避一段再把它的流重新分出去 */
function fail(c: Conn): void {
  if (!conns.includes(c)) return
  drop(c)
  failed = true
  const delay = Math.min(15000, 1000 * 2 ** retry++)
  const wait = hidden() ? Math.max(delay, 10000) : delay
  blockedUntil = Date.now() + wait
  paint()
  scheduleRetry(wait)
}

function scheduleRetry(ms: number): void {
  if (retryTimer) return
  // 系统说断着网就不空连（连也是 ERR_INTERNET_DISCONNECTED），等 online 事件再连
  retryTimer = setTimeout(() => { retryTimer = null; if (!offline()) apply() }, ms)
}

/** 立刻重连，不等退避（回到前台、联网、换线路） */
function reconnectNow(): void {
  if (retryTimer) { clearTimeout(retryTimer); retryTimer = null }
  retry = 0; blockedUntil = 0
  if (debounce) { clearTimeout(debounce); debounce = null }
  apply()
}

/** 回到前台立刻对账（补回隐藏时撤掉的几路），断着的话马上重连不再等退避 */
if (typeof document !== 'undefined') {
  document.addEventListener('visibilitychange', () => {
    if (!hidden() && (failed || !conns.length) && effective().length) { reconnectNow(); return }
    if (debounce) clearTimeout(debounce)
    debounce = setTimeout(apply, hidden() ? 1500 : 0)
  })
}

/** 系统报断网：不等 30 秒静默看门狗，马上判断线（连接点变红、价格变灰）；报联网就立刻重连，不等退避 */
if (typeof window !== 'undefined' && typeof window.addEventListener === 'function') {
  window.addEventListener('offline', () => { for (const c of conns.slice()) fail(c) })
  window.addEventListener('online', () => {
    if (effective().length && !(conns.length && conns.every(c => c.sock.readyState === WebSocket.OPEN && c.gotFrame))) {
      for (const c of conns.slice()) drop(c)
      reconnectNow()
    }
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
  for (const c of conns.slice()) drop(c)
  failed = false
  reconnectNow()
}

/** 测试与排障用：当前线路、各条连接与订阅 */
export function streamDebug(): { route: Route; state: string; subscribed: string[]; conns: number[] } {
  return { route: S.route, state: S.wsState, subscribed: conns.flatMap(c => [...c.subscribed]), conns: conns.map(c => c.subscribed.size) }
}
