/* Hkline Web · 别家交易所的推送（OKX / Bybit / Hyperliquid / Coinbase）
 *
 * 币安的推送是 stream.ts 的连接池；别家由这里按注册表（venues/<id>.ts market.stream，MarketWire）管：
 *   - 流名和币安同样的后缀，只是品种段是完整键：`okx/usd_m/BTCUSDT@ticker`、`…@kline_1h`、`…@markPrice@1s`、`…@aggTrade`
 *     （streamName 生成；setStreams 把带「/」的分到这里）。
 *   - 一家一条连接多订阅（OKX 的 K 线在 business 端点，另一条）；同一个上行 topic 被几路共用时只订一次
 *     （Bybit tickers、Hyperliquid activeAssetCtx 同时给行情与标记价）；每条连接最多 maxTopics 个（网关中继的上限），
 *     超出的排在最后的（自选报价）不订。
 *   - 线路：用户选网关就只连中继、选直连只连交易所，失败按 1 s、2 s、4 s … 最长 15 s 重连，不换线路；
 *     连上 8 秒一帧都没有、或静默 silenceMs（默认 30 秒）当断线；保活帧按那一家的 ping。
 *   - 上行按各家官方的 WS 规矩（和 REST 的限流器分开计）：控制帧默认每 250 ms 一条（Coinbase 每 IP ≤ 8 条 / 秒、
 *     Hyperliquid 每分钟 ≤ 2000 条）；OKX 每条连接订 / 退合计 ≤ 480 条 / 小时（满了排到窗口滚出再发）、新连接按 IP
 *     3 次 / 秒（两条之间隔 400 ms）；Bybit 一帧 ≤ 10 个 args、每 20 秒 ping；Hyperliquid 每 IP ≤ 10 条连接（这里一条）。
 *   - 页面隐藏时只留核心几路（当前格的 K 线与行情、提醒），回到前台补回来。
 * 推来的统一事件（venues/common Push）：
 *   quote → 落进 S.symbols（market/quote.ts，按交易所时间拒旧）并发 ticker / mark 事件；
 *   trade → 逐笔旁路（秒级 K 线）+ 当前价；kline → 发 kline 事件。
 *   那一家没有的周期（OKX / Bybit 8 时、HL 6 时、Coinbase 3 分 / 8 时 / 12 时 / 周 / 月）：订原生档，这里并出当前格
 *   （先用 REST 取一次这一格已经走完的原生档垫底）；Coinbase 没有任意周期的 K 线推送（klineFromTrades）：
 *   用 REST 取当前这根垫底，再拿逐笔往上并。
 */
import type { Bar } from '../chart/calc'
import type { MarketWire, Push, StreamSub } from '../venues/common'
import { intervalPlan, marketKlines, marketOf, venueAdapter } from '../venues'
import { bucketOf, ratioOf } from '../venues/bars'
import { S, emit, setWsPart, type Route } from './state'
import { emitTrade } from './trades'
import { applyQuote } from './quote'
import { gatewayWs } from './origin'
import { parseKey } from './identity'
import { ago } from '../util/clock'

const FIRST_FRAME_MS = 8000
const SILENCE_MS = 30_000
const MAX_BACKOFF_MS = 15_000
const CONTROL_GAP_MS = 250

/** 流名的品种段带「/」= 别家（币安是裸代号、美元指数是 dxy@…） */
export function isVenueStream(name: string): boolean {
  const at = name.indexOf('@')
  return at > 0 && name.slice(0, at).includes('/')
}
/** 流名 → 订阅的一路；认不出的回 null */
export function parseStream(name: string): StreamSub | null {
  const at = name.indexOf('@')
  if (at <= 0) return null
  const key = name.slice(0, at), rest = name.slice(at + 1)
  if (rest === 'ticker') return { key, kind: 'ticker' }
  if (rest === 'aggTrade') return { key, kind: 'trade' }
  if (rest.startsWith('markPrice')) return { key, kind: 'mark' }
  if (rest.startsWith('kline_')) return { key, kind: 'kline', iv: rest.slice(6) }
  return null
}

// ------------------------------------------------------------ 要订什么（纯逻辑，单测覆盖）
/** 一路网页想要的流在这一家要订哪个原生的东西；并线的周期记在 agg（键|周期 → 原生档），逐笔拼的记在 fromTrades */
export interface Plan {
  /** venue → endpoint → 有序去重的 topic */
  topics: Map<string, Map<string, string[]>>
  /** 键|网页周期 → 原生周期（要并的） */
  agg: Map<string, string>
  /** 键|网页周期（拿逐笔拼的） */
  fromTrades: Set<string>
}
export function planStreams(names: readonly string[]): Plan {
  const plan: Plan = { topics: new Map(), agg: new Map(), fromTrades: new Set() }
  const add = (venue: string, wire: MarketWire, sub: StreamSub): void => {
    const ep = wire.endpoint(sub)
    if (ep == null) return
    let byEp = plan.topics.get(venue); if (!byEp) plan.topics.set(venue, byEp = new Map())
    let list = byEp.get(ep); if (!list) byEp.set(ep, list = [])
    for (const t of wire.topics(sub)) if (!list.includes(t) && list.length < wire.maxTopics) list.push(t)
  }
  for (const name of names) {
    const sub = parseStream(name)
    if (!sub) continue
    const m = marketOf(sub.key), wire = m?.stream
    if (!m || !wire) continue
    const venue = parseKey(sub.key).venue
    if (sub.kind !== 'kline') { add(venue, wire, sub); continue }
    const iv = sub.iv ?? ''
    const p = intervalPlan(m, iv)
    if (!p) continue
    if (wire.klineFromTrades) { plan.fromTrades.add(`${sub.key}|${iv}`); add(venue, wire, { key: sub.key, kind: 'trade' }); continue }
    if ('native' in p) { add(venue, wire, sub); continue }
    plan.agg.set(`${sub.key}|${iv}`, p.base)
    add(venue, wire, { key: sub.key, kind: 'kline', iv: p.base })
  }
  return plan
}

// ------------------------------------------------------------ 并线（纯逻辑，单测覆盖）
/** 一格并线周期的当前格：原生档按开盘时刻记着，合成这一格（开取最早、收取最晚、高低极值、量相加） */
export class AggBar {
  bucket = -1
  private subs = new Map<number, Bar>()
  seeded = false
  constructor(readonly iv: string) {}
  /** 来了一根原生档：新的一格就清掉上一格；返回合成的这一格（还没垫底时回 null） */
  push(b: Bar): Bar | null {
    const k = bucketOf(b.t, this.iv)
    if (k < this.bucket) return null
    if (k > this.bucket) { if (this.bucket >= 0) this.seeded = true; this.bucket = k; this.subs.clear() }
    this.subs.set(b.t, { ...b })
    return this.seeded ? this.bar() : null
  }
  /** REST 垫底：这一格已经走完的原生档（推送来过的同一根以推送为准） */
  seed(bars: readonly Bar[]): Bar | null {
    for (const b of bars) {
      const k = bucketOf(b.t, this.iv)
      if (this.bucket >= 0 && k !== this.bucket) continue
      if (this.bucket < 0) this.bucket = k
      if (!this.subs.has(b.t)) this.subs.set(b.t, { ...b })
    }
    this.seeded = true
    return this.subs.size ? this.bar() : null
  }
  bar(): Bar {
    const xs = [...this.subs.values()].sort((a, b) => a.t - b.t)
    const out: Bar = { t: this.bucket, o: xs[0].o, h: -Infinity, l: Infinity, c: xs[xs.length - 1].c, v: 0 }
    for (const x of xs) {
      out.h = Math.max(out.h, x.h); out.l = Math.min(out.l, x.l); out.v += x.v
      if (x.tb != null) out.tb = (out.tb ?? 0) + x.tb
      if (x.bv != null) out.bv = (out.bv ?? 0) + x.bv
    }
    return out
  }
}

/** 逐笔拼当前这根（没有 K 线推送的那一家）：REST 取的当前这根垫底，之后的逐笔往上并 */
export class TradeBar {
  bar: Bar | null = null
  seeded = false
  private early: { price: number; qty: number; t: number }[] = []
  constructor(readonly iv: string) {}
  seed(last: Bar | null): Bar | null {
    if (last && (!this.bar || last.t >= this.bar.t)) this.bar = { ...last }
    this.seeded = true
    const early = this.early; this.early = []
    let out: Bar | null = this.bar ? { ...this.bar } : null
    for (const x of early) out = this.trade(x.price, x.qty, x.t) ?? out
    return out
  }
  trade(price: number, qty: number, t: number): Bar | null {
    if (!this.seeded) { this.early.push({ price, qty, t }); return null }
    const k = bucketOf(t, this.iv)
    const b = this.bar
    if (b && k < b.t) return null
    if (!b || k > b.t) this.bar = { t: k, o: price, h: price, l: price, c: price, v: price * qty, bv: qty }
    else { b.h = Math.max(b.h, price); b.l = Math.min(b.l, price); b.c = price; b.v += price * qty; b.bv = (b.bv ?? 0) + qty }
    return { ...this.bar! }
  }
}

// ------------------------------------------------------------ 连接
interface Conn {
  venue: string
  endpoint: string
  wire: MarketWire
  url: string
  sock: WebSocket
  want: string[]
  subscribed: Set<string>
  decode: (text: string) => Push[]
  opened: boolean
  gotFrame: boolean
  last: number
  queue: string[]
  /** 这条连接最近一小时发过的控制帧时刻（OKX 每连接每小时 480 条） */
  sentAt: number[]
  sendTimer: ReturnType<typeof setTimeout> | null
  pingTimer: ReturnType<typeof setInterval> | null
  firstTimer: ReturnType<typeof setTimeout> | null
}

const conns = new Map<string, Conn>()            // venue|endpoint → 连接
const failedAt = new Map<string, number>()       // venue|endpoint → 断开时刻（退避中）
const retries = new Map<string, number>()
const retryTimers = new Map<string, ReturnType<typeof setTimeout>>()
let plan: Plan = { topics: new Map(), agg: new Map(), fromTrades: new Set() }
let allNames: string[] = []
let coreNames: string[] = []
const aggs = new Map<string, AggBar>()
const tradeBars = new Map<string, TradeBar>()
let watchdog: ReturnType<typeof setInterval> | null = null
/** 每家上一次新开连接的时刻（openGapMs） */
const openedAt = new Map<string, number>()
let openTimer: ReturnType<typeof setTimeout> | null = null

function hidden(): boolean { return typeof document !== 'undefined' && document.visibilityState === 'hidden' }
const connKey = (venue: string, ep: string): string => `${venue}|${ep}`

/** stream.ts setStreams 分过来的别家的流（all：前台要的全部；core：隐藏时仍留的） */
export function setVenueStreams(all: readonly string[], core: readonly string[] = all): void {
  allNames = [...new Set(all)]
  coreNames = [...new Set(core)]
  apply()
}

function apply(): void {
  plan = planStreams(hidden() ? coreNames : allNames)
  // 并线 / 逐笔拼的状态：不要了的撤掉，新要的建起来并垫底
  for (const k of [...aggs.keys()]) if (!plan.agg.has(k)) aggs.delete(k)
  for (const k of [...tradeBars.keys()]) if (!plan.fromTrades.has(k)) tradeBars.delete(k)
  for (const [k, base] of plan.agg) if (!aggs.has(k)) { const [key, iv] = split(k); const a = new AggBar(iv); aggs.set(k, a); void seedAgg(key, iv, base, a) }
  for (const k of plan.fromTrades) if (!tradeBars.has(k)) { const [key, iv] = split(k); const t = new TradeBar(iv); tradeBars.set(k, t); void seedTrades(key, iv, t) }
  // 连接：不要的关掉，要的对账或新开
  const wanted = new Set<string>()
  for (const [venue, byEp] of plan.topics) for (const [ep, topics] of byEp) {
    const ck = connKey(venue, ep)
    if (!topics.length) continue
    wanted.add(ck)
    const c = conns.get(ck)
    if (c) { c.want = topics; reconcile(c); continue }
    if (retryTimers.has(ck)) continue           // 退避中：到点 apply 再开
    // 这一家新开连接有间隔（OKX 按 IP 3 次 / 秒）：没到点就约一次 apply
    const gap = venueAdapter(venue)?.market.stream?.openGapMs ?? 0, since = Date.now() - (openedAt.get(venue) ?? 0)
    if (gap && since >= 0 && since < gap) { if (!openTimer) openTimer = setTimeout(() => { openTimer = null; apply() }, gap - since); continue }
    openedAt.set(venue, Date.now())
    open(venue, ep, topics)
  }
  for (const [ck, c] of [...conns]) if (!wanted.has(ck)) { drop(c); conns.delete(ck) }
  for (const [ck, t] of [...retryTimers]) if (!wanted.has(ck)) { clearTimeout(t); retryTimers.delete(ck); failedAt.delete(ck); retries.delete(ck) }
  paint()
}
const split = (k: string): [string, string] => { const i = k.lastIndexOf('|'); return [k.slice(0, i), k.slice(i + 1)] }

async function seedAgg(key: string, iv: string, base: string, a: AggBar): Promise<void> {
  try {
    const now = Date.now()
    const bars = await marketKlines(key, base, { limit: ratioOf(iv, base), start: bucketOf(now, iv) }, { background: true })
    if (aggs.get(`${key}|${iv}`) !== a) return
    const bar = a.seed(bars)
    if (bar) emit({ type: 'kline', symbol: key, iv, bar })
  } catch { a.seed([]) }
}
async function seedTrades(key: string, iv: string, t: TradeBar): Promise<void> {
  let last: Bar | null = null
  try { const bars = await marketKlines(key, iv, { limit: 2 }, { background: true }); last = bars[bars.length - 1] ?? null } catch { /* 没有垫底就从下一笔起 */ }
  if (tradeBars.get(`${key}|${iv}`) !== t) return
  const bar = t.seed(last)
  if (bar) emit({ type: 'kline', symbol: key, iv, bar })
}

function urlOf(wire: MarketWire, ep: string, route: Route): string { return wire.url(ep, route, gatewayWs()) }

function open(venue: string, ep: string, topics: string[]): void {
  if (typeof WebSocket === 'undefined') return
  const wire = venueAdapter(venue)?.market.stream
  if (!wire) return
  const url = urlOf(wire, ep, S.route)
  const sock = new WebSocket(url)
  const c: Conn = { venue, endpoint: ep, wire, url, sock, want: topics, subscribed: new Set(), decode: wire.decoder(ep), opened: false, gotFrame: false, last: Date.now(), queue: [], sentAt: [], sendTimer: null, pingTimer: null, firstTimer: null }
  conns.set(connKey(venue, ep), c)
  sock.onopen = () => {
    if (conns.get(connKey(venue, ep)) !== c) return
    c.opened = true; c.last = Date.now()
    for (const f of wire.hello ?? []) send(c, f)
    reconcile(c)
    if (wire.ping) c.pingTimer = setInterval(() => { if (sock.readyState === WebSocket.OPEN) sock.send(wire.ping!.text) }, wire.ping.everyMs)
    c.firstTimer = setTimeout(() => { c.firstTimer = null; if (conns.get(connKey(venue, ep)) === c && !c.gotFrame && c.subscribed.size) fail(c) }, FIRST_FRAME_MS)
    paint()
  }
  sock.onmessage = ev => {
    if (conns.get(connKey(venue, ep)) !== c) return
    c.last = S.lastMsg = Date.now()
    const pushes = c.decode(String(ev.data))
    if (pushes.length && !c.gotFrame) {
      c.gotFrame = true
      if (c.firstTimer) { clearTimeout(c.firstTimer); c.firstTimer = null }
      retries.delete(connKey(venue, ep)); failedAt.delete(connKey(venue, ep))
      paint()
    }
    for (const p of pushes) handle(p)
  }
  sock.onclose = () => { if (conns.get(connKey(venue, ep)) === c) fail(c) }
  sock.onerror = () => { /* onclose 会跟着来 */ }
  if (!watchdog) watchdog = setInterval(() => {
    const now = Date.now()
    for (const x of [...conns.values()]) if (x.sock.readyState === WebSocket.OPEN && x.gotFrame && x.subscribed.size && ago(x.last, now) > (x.wire.silenceMs ?? SILENCE_MS)) fail(x)
  }, 5000)
}

/** 控制帧排队，一条连接每 CONTROL_GAP_MS 最多发一条 */
function send(c: Conn, frame: string): void {
  c.queue.push(frame)
  pump(c)
}
function pump(c: Conn): void {
  if (c.sendTimer || !c.queue.length || c.sock.readyState !== WebSocket.OPEN) return
  const now = Date.now(), cap = c.wire.controlPerHour
  if (cap) {
    while (c.sentAt.length && now - c.sentAt[0] >= 3_600_000) c.sentAt.shift()
    // 这一小时的订 / 退额度用完了：等最早那条滚出窗口再发（不重连、不丢，到点按顺序补发）
    if (c.sentAt.length >= cap) { c.sendTimer = setTimeout(() => { c.sendTimer = null; pump(c) }, c.sentAt[0] + 3_600_000 - now); return }
  }
  c.sock.send(c.queue.shift()!)
  c.sentAt.push(now)
  c.sendTimer = setTimeout(() => { c.sendTimer = null; pump(c) }, c.wire.controlGapMs ?? CONTROL_GAP_MS)
}
function reconcile(c: Conn): void {
  if (c.sock.readyState !== WebSocket.OPEN) return
  const want = new Set(c.want)
  const del = [...c.subscribed].filter(t => !want.has(t))
  const add = c.want.filter(t => !c.subscribed.has(t))
  if (del.length) { for (const f of c.wire.frames(c.endpoint, del, false)) send(c, f); del.forEach(t => c.subscribed.delete(t)) }
  if (add.length) { for (const f of c.wire.frames(c.endpoint, add, true)) send(c, f); add.forEach(t => c.subscribed.add(t)) }
}

function drop(c: Conn): void {
  if (c.sendTimer) clearTimeout(c.sendTimer)
  if (c.pingTimer) clearInterval(c.pingTimer)
  if (c.firstTimer) clearTimeout(c.firstTimer)
  const s = c.sock
  s.onclose = null; s.onmessage = null; s.onopen = null
  try { s.close() } catch { /* 已经关了 */ }
}
function fail(c: Conn): void {
  const ck = connKey(c.venue, c.endpoint)
  if (conns.get(ck) !== c) return
  drop(c); conns.delete(ck)
  const n = retries.get(ck) ?? 0
  retries.set(ck, n + 1)
  failedAt.set(ck, Date.now())
  const wait = Math.min(MAX_BACKOFF_MS, 1000 * 2 ** n)
  retryTimers.set(ck, setTimeout(() => { retryTimers.delete(ck); apply() }, hidden() ? Math.max(wait, 10_000) : wait))
  paint()
}

/** 每一家的连接状态并进 S.wsState（state.ts setWsPart） */
function paint(): void {
  const venues = new Set<string>([...plan.topics.keys(), ...[...conns.values()].map(c => c.venue)])
  for (const v of venues) {
    const eps = [...(plan.topics.get(v)?.entries() ?? [])].filter(([, t]) => t.length).map(([ep]) => connKey(v, ep))
    const st = !eps.length ? 'idle' as const
      : eps.some(k => failedAt.has(k)) ? 'closed' as const
      : eps.every(k => { const c = conns.get(k); return c && c.sock.readyState === WebSocket.OPEN && (c.gotFrame || !c.subscribed.size) }) ? 'open' as const : 'connecting' as const
    setWsPart('venue:' + v, st)
  }
  for (const v of lastPainted) if (!venues.has(v)) setWsPart('venue:' + v, 'idle')
  lastPainted = venues
}
let lastPainted = new Set<string>()

// ------------------------------------------------------------ 推送落地
/** 一条统一事件落进品种表、发事件（单测直接喂） */
export function handle(p: Push): void {
  if (p.type === 'quote') {
    const s = S.symbols.get(p.quote.key)
    if (!s) return
    const dir = applyQuote(s, p.quote)
    s.lastTick = Date.now()
    if (p.quote.price != null || p.quote.vol != null) emit({ type: 'ticker', symbol: s.symbol, dir })
    if (p.quote.mark != null || p.quote.fr !== undefined || p.quote.index != null) emit({ type: 'mark', symbol: s.symbol })
    return
  }
  if (p.type === 'trade') {
    emitTrade(p.key, p.price, p.qty, p.t, p.sell)
    for (const [k, tb] of tradeBars) {
      if (!k.startsWith(p.key + '|')) continue
      const bar = tb.trade(p.price, p.qty, p.t)
      if (bar) emit({ type: 'kline', symbol: p.key, iv: tb.iv, bar })
    }
    const s = S.symbols.get(p.key)
    if (!s || p.t < (s.pxAt ?? 0)) return
    const prev = s.price
    s.pxAt = p.t; s.lastTick = Date.now()
    if (prev === p.price) return
    s.price = p.price
    if (s.open) { s.chg = p.price - s.open; s.pct = (p.price / s.open - 1) * 100 }
    if (s.hi != null && p.price > s.hi) s.hi = p.price
    if (s.lo != null && p.price < s.lo) s.lo = p.price
    emit({ type: 'ticker', symbol: p.key, dir: prev == null ? 0 : Math.sign(p.price - prev) })
    return
  }
  // K 线：原生档原样发；这一档是别的周期的底的，并出那一格再发
  emit({ type: 'kline', symbol: p.key, iv: p.iv, bar: p.bar })
  for (const [k, base] of plan.agg) {
    if (base !== p.iv || !k.startsWith(p.key + '|')) continue
    const a = aggs.get(k)
    const bar = a?.push(p.bar)
    if (bar) emit({ type: 'kline', symbol: p.key, iv: a!.iv, bar })
  }
}

/** 换线路：全部按新线路重连 */
export function setVenueRoute(): void {
  for (const c of conns.values()) drop(c)
  conns.clear()
  for (const t of retryTimers.values()) clearTimeout(t)
  retryTimers.clear(); retries.clear(); failedAt.clear()
  apply()
}

if (typeof document !== 'undefined') {
  document.addEventListener('visibilitychange', () => {
    if (!hidden()) { for (const t of retryTimers.values()) clearTimeout(t); retryTimers.clear(); retries.clear() }
    apply()
  })
}

/** 测试与排障用：各条连接订着什么 */
export function venueStreamDebug(): { conns: { venue: string; endpoint: string; url: string; subscribed: string[] }[]; agg: string[]; fromTrades: string[] } {
  return { conns: [...conns.values()].map(c => ({ venue: c.venue, endpoint: c.endpoint, url: c.url, subscribed: [...c.subscribed] })), agg: [...plan.agg.keys()], fromTrades: [...plan.fromTrades] }
}
