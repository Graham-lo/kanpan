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
 *
 * 对上游的三条硬规矩（违反一条，整条连接被对面掐掉、里面的每一路一起断）：
 *   - 流名先过闸：网关 stream_hub 的 STREAM 正则只认小写 ASCII / 非 ASCII 字母数字的品种段（龙虾usdt 可以，
 *     Coinbase 的 btc-usd 不行），握手 URL 里混一个不认的就是 400、订阅消息里混一个就是 1008 断开；
 *     手机网页自选 / 提醒里可以有 Coinbase 现货，这些名字从不发出去（validStream）。
 *   - 控制消息限速：网关每条连接 4 条/秒（突发 16），币安每条连接每秒 10 条，超了直接断。
 *     每条连接一个令牌桶，桶空时这次对账往后挪、到点按那一刻的名单合并成一次发（reconcile）。
 *   - 订阅回执按 id 对账：发出去的 SUBSCRIBE / UNSUBSCRIBE 记在 pending 里，回执是 error 的那批订阅
 *     记成「被拒」，不再占位、不再重发，也不再让首帧看门狗为它们等帧（被拒的订阅永远不会来帧）。
 */
import type { Bar } from '../chart/calc'
import { S, emit, setWsPart, type Route } from './state'
import { emitTrade } from './trades'
import { isMacroStream, setMacroStreams } from './macroStream'
import { isVenueStream, setVenueStreams, setVenueRoute } from './venueStream'
import { ago, before } from '../util/clock'

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
/** 断线退避最长等多久（藏在后台时至少 10 秒，也不超过它） */
const MAX_BACKOFF_MS = 15000
/** 每条连接的控制消息令牌桶：网关 3/s 突发 12（stream_hub 每条 4/s 突发 16、同一 IP 16/s 突发 64，三条连接也不越线）；
 *  直连 4/s 突发 4（币安每条连接每秒 10 条，桶满时任何 1 秒窗口里最多 8 条） */
export const CONTROL: Record<Route, { rate: number; burst: number }> = { direct: { rate: 4, burst: 4 }, gateway: { rate: 3, burst: 12 } }

/** 网关 stream_hub.py 的 STREAM 正则（`[a-z0-9_]` 或非 ASCII 的 \w，1–30 个，再接认得的流类型）。
 *  Python 的 str \w = 字母（L*）、数字（N*）与下划线，这里用 \p{L}\p{N} 对上 */
const HUB_STREAM = /^(?:(?:[a-z0-9_]|(?![\x00-\x7f])[\p{L}\p{N}_]){1,30}@(?:ticker|markPrice@1s|aggTrade|kline_(?:1m|3m|5m|15m|30m|1h|2h|4h|6h|8h|12h|1d|3d|1w|1M))|!ticker@arr)$/u
/** 直连：币安合约的流名形状（品种段同上，流类型放宽到币安自己的全部写法，不在这里卡类型） */
const BINANCE_STREAM = /^(?:(?:[a-z0-9_]|(?![\x00-\x7f])[\p{L}\p{N}_]){1,40}@[A-Za-z0-9_@]+|![A-Za-z0-9_@]+)$/u
/** 这条线路上的上游认不认这个流名；不认的从不发出去（发出去对面会把整条连接掐掉） */
export function validStream(name: string, route: Route): boolean {
  return (route === 'gateway' ? HUB_STREAM : BINANCE_STREAM).test(name)
}

function gatewayURL(): string | null {
  if (typeof location === 'undefined' || !/^https?:$/.test(location.protocol)) return null
  return `${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/market/stream`
}

// ------------------------------------------------------------ 分配（纯逻辑，单测覆盖）
/**
 * 把想要的流分到连接上。current = 现有各条连接上分着的流；返回每条现有连接的新分配
 * （null = 这条要关掉），以及要新开的几条的分配。want 按轻重排好：前 vital 个是关键流
 * （各格的 K 线与行情、当前格的标记价与逐笔），其后依次是核心、其余（自选报价垫底）。
 *   1. 每条连接只留还想要的流；
 *   2. 连接数多于 ⌈n / cap⌉ 时收掉一条：先收关键流最少的、再收最空的、同样空收后开的那条，
 *      它上面的流算作没分配；
 *   3. 关键流永远坐最早的连接：没分配的关键流按顺序放进最早一条「有空位或有非关键流」的连接，
 *      满了就把那条上排得最靠后的非关键流挤出去重排；已经分着的关键流若坐在后面的连接上，
 *      而前面的连接还有空位 / 非关键流，就和它对调；
 *   4. 没分配的非关键流先填有空位的连接（按轻重顺序），还剩就新开连接，每条至多 cap 路。
 * 后开的连接最容易被网关按同一来源的总上限拒掉——被拒的只会是自选报价，图上的各格照常跟推送。
 * vital = 0 时和原来一样：已经在连接上的流不挪，挪动只发生在要收掉一条连接的时候。
 */
export function assignStreams(current: readonly (readonly string[])[], want: readonly string[], cap: number, vital = 0): { keep: (string[] | null)[]; open: string[][] } {
  const rank = new Map<string, number>()
  want.forEach((x, i) => { if (!rank.has(x)) rank.set(x, i) })
  const isVital = (x: string) => (rank.get(x) ?? Infinity) < vital
  const byRank = (a: string, b: string) => rank.get(a)! - rank.get(b)!
  const need = rank.size ? Math.ceil(rank.size / cap) : 0
  const seen = new Set<string>()
  const sets = current.map(c => c.filter(x => rank.has(x) && !seen.has(x) && (seen.add(x), true)))
  const vitals = (s: readonly string[]) => s.reduce((n, x) => n + (isVital(x) ? 1 : 0), 0)
  const alive = sets.map((_, i) => i)
  while (alive.length > need) {
    let k = 0
    for (let j = 1; j < alive.length; j++) {
      const a = sets[alive[j]], b = sets[alive[k]], va = vitals(a), vb = vitals(b)
      if (va < vb || (va === vb && a.length <= b.length)) k = j
    }
    alive.splice(k, 1)
  }
  const keepSet = new Set(alive)
  const keep: (string[] | null)[] = sets.map((s, i) => keepSet.has(i) ? s.slice(0, cap) : null)
  const live = keep.filter((s): s is string[] => !!s)
  const placed = new Set(live.flat())
  const orphans = want.filter(x => !placed.has(x) && (placed.add(x), true))
  const spill: string[] = orphans.filter(x => !isVital(x))
  /** 这条连接上排得最靠后的非关键流（挤它出去） */
  const worst = (s: string[]): number => {
    let k = -1
    s.forEach((x, i) => { if (!isVital(x) && (k < 0 || rank.get(x)! > rank.get(s[k])!)) k = i })
    return k
  }
  const open: string[][] = []
  if (vital > 0) {
    // 已经分着、却坐在后面的关键流：和前面连接上的非关键流对调（前面有空位就直接挪过去）
    for (let i = 0; i < live.length; i++) {
      for (let j = i + 1; j < live.length; j++) {
        for (let p = 0; p < live[j].length; p++) {
          const x = live[j][p]
          if (!isVital(x)) continue
          if (live[i].length < cap) { live[i].push(x); live[j].splice(p--, 1); continue }
          const w = worst(live[i])
          if (w < 0) break
          live[j][p] = live[i][w]; live[i][w] = x
        }
      }
    }
    // 没分配的关键流：最早一条有空位或有非关键流的连接
    for (const x of orphans) {
      if (!isVital(x)) continue
      let done = false
      for (const s of live) {
        if (s.length < cap) { s.push(x); done = true; break }
        const w = worst(s)
        if (w >= 0) { spill.push(s[w]); s[w] = x; done = true; break }
      }
      if (done) continue
      const last = open[open.length - 1]
      if (last && last.length < cap) last.push(x); else open.push([x])
    }
  }
  spill.sort(byRank)
  for (const s of live) while (s.length < cap && spill.length) s.push(spill.shift()!)
  const last = open[open.length - 1]
  if (last) while (last.length < cap && spill.length) last.push(spill.shift()!)
  while (spill.length) open.push(spill.splice(0, cap))
  return { keep, open }
}

// ------------------------------------------------------------ 同一来源的总上限（纯逻辑，单测覆盖）
/** 网关被拒后至少还留几路（16 格各一路 K 线的量；再往下收就按普通断线退避） */
export const MIN_CAP = 16
/** 被拒后每隔多久试着放宽一档、每档放多少；放宽又被拒，间隔翻倍，最长 10 分钟 */
export const PROBE_MS = 60_000
export const PROBE_MAX_MS = 600_000
export const PROBE_STEP = 16

/**
 * 一条连接收掉了，是「同一来源的总上限满了」还是「断线」：
 *   · 1008 且原因带 limit（stream_hub：subscription limit exceeded）——订阅越线，对面掐的是整条；
 *   · 握手就没成（浏览器只给 1006，看不到 429 / 503），而同一线路上别的连接正好好地在来帧——
 *     网络是通的，被拒的只能是这一条（同一 IP 合计 160 路 / 连接数上限）。
 * 其余（1008 控制消息超速、非法订阅，网络断、对面重启）一律按断线退避。
 */
export function closeKind(code: number, reason: string, opened: boolean, othersHealthy: boolean): 'capacity' | 'down' {
  if (code === 1008) return /limit/i.test(reason) ? 'capacity' : 'down'
  return !opened && othersHealthy ? 'capacity' : 'down'
}

/** 被拒之后的总上限：对面已经收下的路数就是同一来源这一刻还剩的额度；一路都没收下就折半往下试。
 *  返回值不比 current 小（收不动了）就该按普通断线处理 */
export function capAfterReject(accepted: number, current: number): number {
  const next = accepted > 0 ? Math.min(accepted, current - PROBE_STEP) : Math.floor(current / 2)
  return Math.max(MIN_CAP, Math.min(current, next))
}

/** 放宽一档；到了 total 就回到不设限（null） */
export function capAfterProbe(current: number, total: number): number | null {
  const n = current + PROBE_STEP
  return n >= total ? null : n
}

/**
 * 连接点 / 「断线变灰」只看承载关键流的那几条连接：只订自选报价的连接被拒、断开，只影响自选报价自己，
 * 不能把整页判断线（以前一条被拒，16 格全变灰、再也不接推送）。
 *   holders：关键流所在的连接（没有关键流时就是全部连接）；placed：关键流是不是都分到了连接上
 */
export function wsStateOf(want: number, failed: boolean, placed: boolean, holders: readonly { open: boolean }[]): 'idle' | 'connecting' | 'open' | 'closed' {
  if (!want) return 'idle'
  if (failed) return 'closed'
  return placed && holders.length && holders.every(h => h.open) ? 'open' : 'connecting'
}

// ------------------------------------------------------------ 连接池
interface Conn {
  sock: WebSocket
  url: string
  /** 分给这条的流（连上后对账成这组） */
  want: string[]
  /** 这条连接上真正订着的 */
  subscribed: Set<string>
  /** 发出去还没回执的控制消息：id → 那一条的方法与流名 */
  pending: Map<number, { method: 'SUBSCRIBE' | 'UNSUBSCRIBE'; params: string[] }>
  /** 令牌桶 */
  tokens: number
  tokAt: number
  ctlTimer: ReturnType<typeof setTimeout> | null
  /** 握手成了（onopen 来过） */
  opened: boolean
  gotFrame: boolean
  last: number
  firstTimer: ReturnType<typeof setTimeout> | null
}

let conns: Conn[] = []
let all: string[] = []
let core: string[] = []
/** 关键流：断了就要让图变灰的那几路（各格 K 线与行情、当前格标记价与逐笔）；分配时永远排最前、坐最早的连接 */
let vital = new Set<string>()
/** 上游用 error 回执明确拒掉的流（本线路内不再订；换线路清空） */
const rejected = new Set<string>()
let msgId = 1
let retry = 0
/** 断线退避：这之前不开新连接 */
let blockedUntil = 0
/** 承载关键流的连接断了、关键流还没在别的连接上接上 */
let failed = false
/** 网关被拒后摸出来的同一来源总上限（null = 用 TOTAL）：160 路是和同一 IP 的别的标签页、手机合着算的 */
let capLimit: number | null = null
let probeTimer: ReturnType<typeof setTimeout> | null = null
let probeDelay = PROBE_MS
/** 上一次放宽的时刻：放宽后不久又被拒，说明这一档还不行，下一次等更久 */
let probedAt = 0
/** 有新连接要开，但别的连接上的退订还没落地：等落地再开（先退后订） */
let openHeld = false
let debounce: ReturnType<typeof setTimeout> | null = null
let retryTimer: ReturnType<typeof setTimeout> | null = null
let watchdog: ReturnType<typeof setInterval> | null = null
/** 没人要流时，连着的那条先退订干净、空着留一会再关：手机网页「我的」页不订任何流，
 *  我的 ↔ 行情来回点一次就是一次握手（经网关 0.6–1.2 秒才连上、首帧 0.7–2.2 秒，2026-10-05 F 路实测），
 *  留着空连接回来只发一条 SUBSCRIBE。只在前台留；切后台照旧立刻收掉 */
export const LINGER_MS = 20_000
let lingerTimer: ReturnType<typeof setTimeout> | null = null

function offline(): boolean { return typeof navigator !== 'undefined' && navigator.onLine === false }
function hidden(): boolean { return typeof document !== 'undefined' && document.visibilityState === 'hidden' }
/** 这条线路这一刻最多订几路 */
function capOf(route: Route): number { return Math.min(TOTAL[route], capLimit ?? Infinity) }
/** 这一刻该订的，按轻重排：关键 → 核心 → 其余；隐藏时只留核心；超出总上限时从尾巴（自选报价）挤掉 */
function effective(): string[] {
  const route = S.route
  const ok = (x: string) => !rejected.has(x) && validStream(x, route)
  const v = [...vital]
  if (hidden()) { const c = new Set(core); return [...new Set([...v.filter(x => c.has(x)), ...core])].filter(ok).slice(0, capOf(route)) }
  const a = new Set(all)
  return [...new Set([...v.filter(x => a.has(x)), ...core.filter(x => a.has(x)), ...all])].filter(ok).slice(0, capOf(route))
}
/** 这一刻想要的关键流（没有关键流时，任何一条连接都算「承载关键流」，和以前一样） */
function vitalWanted(): string[] { return effective().filter(x => vital.has(x)) }
function holdsVital(c: Conn, v: readonly string[] = vitalWanted()): boolean { return !v.length || c.want.some(x => vital.has(x)) }
/** 关键流都分到了连接上，承载它们的连接都已经来过帧 */
function vitalHealthy(): boolean {
  const v = vitalWanted()
  if (!v.length) return conns.length > 0 && conns.every(c => c.gotFrame)
  const H = conns.filter(c => holdsVital(c, v))
  return v.every(x => H.some(c => c.want.includes(x))) && H.every(c => c.gotFrame)
}
function healthy(c: Conn): boolean { return c.sock.readyState === WebSocket.OPEN && c.gotFrame }

/** all：前台要订的全部；core：页面隐藏时仍保留的；opts.vital：关键流（默认 = core），断了才让整页判断线 */
export function setStreams(list: string[], coreList: string[] = list, opts: { now?: boolean; vital?: string[] } = {}): void {
  // 流名大小写敏感（月线是 kline_1M），品种部分由 streamName 负责转小写
  // 美元指数（dxy@…）走自家服务器那条连接，不进币安的连接池（币安没有这只，发过去整条连接会被掐）
  setMacroStreams(list.filter(isMacroStream))
  // 别家的品种（流名的品种段是完整键 okx/usd_m/BTCUSDT@…）走那一家自己的推送（venueStream.ts），不进币安的连接池
  setVenueStreams(list.filter(isVenueStream), coreList.filter(isVenueStream))
  const mine = (x: string) => !isMacroStream(x) && !isVenueStream(x)
  all = [...new Set(list.filter(mine))]
  core = [...new Set(coreList.filter(mine))]
  vital = new Set((opts.vital ?? coreList).filter(mine))
  if (debounce) clearTimeout(debounce)
  // now：冷启动时和品种表、K 线并行先把连接建起来，不等 150 ms 的合并窗口
  if (opts.now) { debounce = null; apply(); return }
  debounce = setTimeout(apply, 150)
}

function urlFor(route: Route): string | null { return route === 'direct' ? DIRECT : gatewayURL() }

function paint(): void {
  const want = effective(), v = want.filter(x => vital.has(x))
  const H = conns.filter(c => holdsVital(c, v))
  const placed = v.every(x => H.some(c => c.want.includes(x)))
  setWsPart('binance', wsStateOf(want.length, failed, placed, H.map(c => ({ open: c.sock.readyState === WebSocket.OPEN }))))
}

function apply(): void {
  debounce = null
  const want = effective()
  let url = urlFor(S.route)
  if (!url) { S.route = 'direct'; url = DIRECT }
  // 换了线路的连接一律收掉
  for (const c of conns.slice()) if (c.url !== url) drop(c)
  if (lingerTimer) { clearTimeout(lingerTimer); lingerTimer = null }
  if (!want.length && !hidden() && !offline()) {
    // 连着的留一条空着（退订干净），没连上的直接收；LINGER_MS 内没人再要就关
    const keep = conns.find(c => c.sock.readyState === WebSocket.OPEN)
    for (const c of conns.slice()) if (c !== keep) drop(c)
    if (keep) {
      keep.want = []; reconcile(keep)
      lingerTimer = setTimeout(() => { lingerTimer = null; if (!effective().length) { for (const c of conns.slice()) drop(c); paint() } }, LINGER_MS)
    }
    paint()
    return
  }
  const nv = want.filter(x => vital.has(x)).length   // effective() 已把关键流排在最前
  const plan = assignStreams(conns.map(c => c.want), want, PER_CONN[S.route], nv)
  const old = conns
  conns = []
  old.forEach((c, i) => {
    const w = plan.keep[i]
    if (!w) { drop(c); return }
    c.want = w; conns.push(c)
  })
  // 先全部对账（退订先发），再看要不要开新连接
  for (const c of conns.slice()) reconcile(c)
  const t = Date.now()
  openHeld = false
  if (plan.open.length) {
    if (before(blockedUntil, MAX_BACKOFF_MS, t) || offline()) scheduleRetry(Math.max(0, Math.min(blockedUntil - t, MAX_BACKOFF_MS)))
    else if (releasing()) openHeld = true            // 退订落地再开（新连接握手带的流也算进同一来源的总数）
    else plan.open.forEach(w => open(url!, w))
  }
  if (failed && vitalHealthy()) failed = false        // 断掉那条的关键流已经挪到别的连接上
  paint()
}

/** 网关按同一来源合计算总数：别的连接上还有没落地的退订（没发出去 / 发了没回执）。直连没有合计上限，不等 */
function releasing(except?: Conn): boolean {
  if (S.route !== 'gateway') return false
  return conns.some(x => x !== except && x.sock.readyState === WebSocket.OPEN && (
    [...x.pending.values()].some(p => p.method === 'UNSUBSCRIBE') || [...x.subscribed].some(s => !x.want.includes(s))))
}
/** 退订都落地了：压着的订阅补发、压着的新连接开出去 */
function settleReleases(): void {
  if (releasing()) return
  for (const c of conns.slice()) reconcile(c)
  if (openHeld) { openHeld = false; if (debounce) clearTimeout(debounce); debounce = setTimeout(apply, 0) }
}

function reconcile(c: Conn): void {
  if (c.sock.readyState !== WebSocket.OPEN) return   // 连上后 onopen 会对账
  if (c.ctlTimer) return                             // 桶空着、已经约好了下一次：到点按那一刻的名单一起发
  const want = new Set(c.want)
  let add = c.want.filter(x => !c.subscribed.has(x) && !rejected.has(x))
  const del = [...c.subscribed].filter(x => !want.has(x))
  // 先退后订：同一来源合计有上限（网关 160 路），别的连接上的退订没落地时，净新增的订阅先压着，
  // 不让过渡态越线被 1008 掐掉整条连接（同一条连接上的退订排在订阅前面发，对面按顺序处理，不用等）
  if (add.some(x => !conns.some(y => y !== c && y.subscribed.has(x))) && releasing(c)) add = []
  const need = (del.length ? 1 : 0) + (add.length ? 1 : 0)
  if (!need) return
  const { rate, burst } = CONTROL[S.route]
  const now = Date.now()
  c.tokens = Math.min(burst, c.tokens + ago(c.tokAt, now) * rate / 1000); c.tokAt = now
  if (c.tokens < need) {
    const wait = Math.ceil((need - c.tokens) * 1000 / rate)
    c.ctlTimer = setTimeout(() => { c.ctlTimer = null; if (conns.includes(c)) reconcile(c) }, wait)
    return
  }
  c.tokens -= need
  if (del.length) control(c, 'UNSUBSCRIBE', del)
  if (add.length) control(c, 'SUBSCRIBE', add)
}

function control(c: Conn, method: 'SUBSCRIBE' | 'UNSUBSCRIBE', params: string[]): void {
  const id = msgId++
  c.pending.set(id, { method, params })
  c.sock.send(JSON.stringify({ method, params, id }))
  // 乐观记账：回执是 error 时再按 pending 回滚
  if (method === 'SUBSCRIBE') params.forEach(x => c.subscribed.add(x))
  else params.forEach(x => c.subscribed.delete(x))
}

/** 控制消息的回执：成功就销账；SUBSCRIBE 被拒的那批记成被拒、从订阅里拿掉，首帧看门狗不再为它们等 */
function onReply(c: Conn, id: number, error: unknown): void {
  const p = c.pending.get(id)
  if (!p) return
  c.pending.delete(id)
  if (p.method === 'UNSUBSCRIBE') { settleReleases(); return }
  if (!error) return
  for (const x of p.params) { rejected.add(x); c.subscribed.delete(x) }
  c.want = c.want.filter(x => !rejected.has(x))
  if (!c.gotFrame && !c.subscribed.size) settleQuiet(c)
}

/** 这条连接上已经没有在等帧的订阅（全被拒 / 全撤了）：首帧看门狗收掉，不再把它当「连上了却不来帧」 */
function settleQuiet(c: Conn): void {
  if (c.firstTimer) { clearTimeout(c.firstTimer); c.firstTimer = null }
  c.gotFrame = true   // 没有可等的帧了：不再算「还没来首帧」，也不让它把连接点一直钉在红色
  if (failed && vitalHealthy()) { failed = false; paint() }
}

/** 对面确认收下的路数（握手带的 + 回执过的订阅；还在路上的 SUBSCRIBE 不算） */
function confirmed(c: Conn): number {
  if (!c.opened) return 0
  let n = c.subscribed.size
  for (const p of c.pending.values()) if (p.method === 'SUBSCRIBE') n -= p.params.filter(x => c.subscribed.has(x)).length
  return Math.max(0, n)
}

function open(url: string, want: string[]): void {
  const { burst } = CONTROL[S.route]
  const sock = new WebSocket(`${url}?streams=${want.join('/')}`)
  const c: Conn = { sock, url, want, subscribed: new Set(want), pending: new Map(), tokens: burst, tokAt: Date.now(), ctlTimer: null, opened: false, gotFrame: false, last: Date.now(), firstTimer: null }
  conns.push(c)
  sock.onopen = () => {
    if (!conns.includes(c)) return
    c.opened = true
    reconcile(c)
    // 首帧窗口只等还订着的（被拒的永远不会来帧）；到点时一路都没订着就不算失败
    c.firstTimer = setTimeout(() => { c.firstTimer = null; if (conns.includes(c) && !c.gotFrame && c.subscribed.size) fail(c) }, FIRST_FRAME_MS)
    paint()
  }
  sock.onmessage = ev => {
    if (!conns.includes(c)) return
    c.last = S.lastMsg = Date.now()
    let m: Frame
    try { m = JSON.parse(String(ev.data)) } catch { return }
    if (!m || typeof m !== 'object') return
    // 控制消息回执（{result:null,id} / {error:{…},id}）只用来对账，不算「上游在来帧」
    if (!m.stream && ('result' in m || 'error' in m)) { if (typeof m.id === 'number') onReply(c, m.id, m.error); return }
    if (!c.gotFrame) {
      c.gotFrame = true
      if (c.firstTimer) { clearTimeout(c.firstTimer); c.firstTimer = null }
      retry = 0; blockedUntil = 0
      if (failed && vitalHealthy()) { failed = false; paint() }
    }
    handle(m)
  }
  sock.onclose = (ev?: CloseEvent) => {
    if (!conns.includes(c)) return
    const kind = closeKind(ev?.code ?? 1006, ev?.reason ?? '', c.opened, conns.some(x => x !== c && healthy(x)))
    if (kind === 'capacity' && reject(c)) return
    fail(c)
  }
  sock.onerror = () => { /* onclose 会跟着来 */ }
  if (!watchdog) watchdog = setInterval(() => {
    const now = Date.now()
    for (const x of conns.slice()) if (x.sock.readyState === WebSocket.OPEN && x.gotFrame && x.subscribed.size && ago(x.last, now) > SILENCE_MS) fail(x)
  }, 5000)
}

/** 收掉一条连接（不算断线） */
function drop(c: Conn): void {
  if (c.firstTimer) { clearTimeout(c.firstTimer); c.firstTimer = null }
  if (c.ctlTimer) { clearTimeout(c.ctlTimer); c.ctlTimer = null }
  conns = conns.filter(x => x !== c)
  const s = c.sock
  s.onclose = null; s.onmessage = null; s.onopen = null
  try { s.close() } catch { /* 已经关了 */ }
}

/**
 * 同一来源的总上限满了（这条被 1008 掐掉 / 握手被拒）：把总上限收到对面已经收下的路数，
 * 按新上限马上重分——挤掉的是排在最后的自选报价，关键流挪回最早那条连接；不退避、也不再重开
 * 那条注定被拒的连接。之后每 PROBE_MS 放宽一档试试。收不动了（已到 MIN_CAP）返回 false，按普通断线处理
 */
function reject(c: Conn): boolean {
  const cur = capOf(S.route)
  const next = capAfterReject(conns.reduce((n, x) => n + confirmed(x), 0), cur)
  if (next >= cur) return false
  const lostVital = holdsVital(c)
  drop(c)
  capLimit = next
  if (lostVital) failed = true
  if (probedAt && ago(probedAt, Date.now()) < probeDelay) probeDelay = Math.min(PROBE_MAX_MS, probeDelay * 2)
  probedAt = 0
  scheduleProbe()
  paint()
  if (debounce) clearTimeout(debounce)
  debounce = setTimeout(apply, 300)
  return true
}

function scheduleProbe(): void {
  if (probeTimer) clearTimeout(probeTimer)
  probeTimer = capLimit == null ? null : setTimeout(() => {
    probeTimer = null
    if (capLimit == null) return
    capLimit = capAfterProbe(capLimit, TOTAL[S.route])
    probedAt = Date.now()
    if (capLimit == null) probeDelay = PROBE_MS
    scheduleProbe()
    if (!debounce) debounce = setTimeout(apply, 0)
  }, probeDelay)
}

/** 一条连接断了：收掉它，退避一段再把它的流重新分出去。只订非关键流（自选报价）的那条断了不让整页判断线 */
function fail(c: Conn): void {
  if (!conns.includes(c)) return
  const lostVital = holdsVital(c)
  drop(c)
  if (lostVital) failed = true
  const delay = Math.min(MAX_BACKOFF_MS, 1000 * 2 ** retry++)
  const wait = hidden() ? Math.max(delay, 10000) : delay
  blockedUntil = Date.now() + wait
  paint()
  scheduleRetry(wait)
  settleReleases()
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
interface Frame { stream?: string; data?: Record<string, unknown>; result?: unknown; error?: unknown; id?: number }

function handle(m: Frame): void {
  const d = (m.data || m) as Record<string, any>
  if (!d || typeof d !== 'object' || !d.e) return
  switch (d.e) {
    case '24hrTicker': {
      const s = S.symbols.get(d.s); if (!s) return
      const prev = s.price, at = +d.C || +d.E || 0
      // 价格那半只收不比手里旧的（逐笔可能已经推到更后面）；成交额 / 笔数这半照收
      if (!(at < (s.pxAt ?? 0))) Object.assign(s, { price: +d.c, chg: +d.p, pct: +d.P, open: +d.o, hi: +d.h, lo: +d.l, pxAt: at })
      if (!(at < (s.statAt ?? 0))) Object.assign(s, { vol: +d.q, count: +d.n, statAt: at })
      s.lastTick = Date.now()
      emit({ type: 'ticker', symbol: d.s, dir: prev == null || s.price == null ? 0 : Math.sign(s.price - prev) })
      break
    }
    case 'aggTrade': {
      const s = S.symbols.get(d.s); if (!s) return
      const p = +d.p, prev = s.price
      emitTrade(d.s, p, +d.q, +d.T, !!d.m)
      const at = +d.T || 0
      if (at < (s.pxAt ?? 0)) { s.lastTick = Date.now(); return }
      s.pxAt = at
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
      const at = +d.E || 0
      if (at < (s.markAt ?? 0)) return
      Object.assign(s, { fr: d.r === '' ? s.fr : +d.r, nextFunding: d.T || s.nextFunding, mark: +d.p, index: +d.i, markAt: at })
      emit({ type: 'mark', symbol: d.s })
      break
    }
  }
}

/** 流名的品种段：币安 / 美元指数转小写（组合流协议的写法）；别家的完整键原样（大小写算数，venueStream 按它找那一家） */
const streamSym = (sym: string): string => sym.includes('/') ? sym : sym.toLowerCase()
export const streamName = {
  kline: (sym: string, iv: string) => `${streamSym(sym)}@kline_${iv}`,
  ticker: (sym: string) => `${streamSym(sym)}@ticker`,
  mark: (sym: string) => `${streamSym(sym)}@markPrice@1s`,
  trade: (sym: string) => `${streamSym(sym)}@aggTrade`,
}
/** 流名 → 品种键（refreshStreams 拿它对品种表） */
export function symbolOfStream(name: string): string {
  const k = name.split('@')[0]
  return k.includes('/') ? k : k.toUpperCase()
}

/** 换线路：立即按新线路重连 */
export function setRoute(route: Route): void {
  if (route === 'gateway' && !gatewayURL()) route = 'direct'
  if (S.route === route) return
  S.route = route
  for (const c of conns.slice()) drop(c)
  rejected.clear()
  failed = false
  capLimit = null; probeDelay = PROBE_MS; probedAt = 0
  if (probeTimer) { clearTimeout(probeTimer); probeTimer = null }
  reconnectNow()
  setVenueRoute()
}

/** 测试与排障用：当前线路、各条连接与订阅、被拒后摸出来的总上限 */
export function streamDebug(): { route: Route; state: string; subscribed: string[]; conns: number[]; cap: number } {
  return { route: S.route, state: S.wsState, subscribed: conns.flatMap(c => [...c.subscribed]), conns: conns.map(c => c.subscribed.size), cap: capOf(S.route) }
}
