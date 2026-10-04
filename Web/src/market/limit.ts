/* Hkline Web · 交易所 REST 限流闸（整站唯一的一套）
 *
 * 币安按出口 IP 计权重（U 本位 / 币本位合约 2400 / 分钟、现货 6000 / 分钟），超了回 429；429 之后还接着打，
 * 就升级成 418 封 IP——这台电脑和用户的手机常常是同一个出口 IP，封了连 iOS 端也取不到行情。
 * 浏览器跨域读不到 X-MBX-USED-WEIGHT-1M 与 Retry-After，所以只能本地自己管两件事：
 *
 * 0. 两条线路各记一道：直连记的是这台电脑出口 IP 在币安那边的额度，网关（rest.ts viaRoute）记的是新加坡那台
 *    服务端的共用额度。同一个币安地址走哪条线路，冷却与预算就记在哪一道，互不连累（下面 1、2 都按道分）。
 * 1. 冷却（按主机名分，fapi / dapi / 现货 / OKX 各有各的额度，一家限流不连累别家）：
 *    任何主机回了 429 / 418，冷却期内这个主机的请求一律在本地直接失败，不再发出去。
 *    冷却按 Retry-After（读得到的话）；读不到时 429 记 60 秒、418 记 5 分钟，冷却一结束就再犯的翻倍
 *    （429 封顶 5 分钟、418 封顶 30 分钟）；冷却期间才回来的 429（冷却前就发出去的那批）只续一轮、不翻倍；
 *    冷却过后成功一次就清掉「再犯」计数。
 * 2. 预算（只管币安三族）：发之前按官方权重表记一笔，一分钟滚动窗口里超过官方上限的一半
 *    （另一半留给同一出口的手机 app 与别的页）就排队等最早的几笔滚出窗口，而不是先打出 429 再冷却。
 *
 * 冷却与账本都放在 localStorage 里，同一浏览器的各标签页与每次刷新共用一份：币安按 IP 记，不按页记。
 * 2026-09-29 A 路压测：只放在内存里时，刷新一次页面冷却就清零、预算重新算，连开 24 次页面一分钟回了 26 个 429，
 * 两个标签页也各记各的。
 * 纯逻辑在 Limiter 里（不碰网络与计时器），vitest 直接测；模块级函数是给 fetch 包装用的那一层。
 */

export const COOL_429_MS = 60_000
export const COOL_418_MS = 300_000
const CAP_429_MS = 300_000
const CAP_418_MS = 1_800_000
const WINDOW = 60_000

export type Family = 'fapi' | 'dapi' | 'spot'
/** 每族一分钟的本地预算（官方上限的一半） */
export const BUDGET: Record<Family, number> = { fapi: 1200, dapi: 1200, spot: 3000 }

function hostOf(url: string): string {
  try { return new URL(url, 'http://localhost').host } catch { return url }
}

export function familyOf(url: string): Family | null {
  const h = /^https:\/\/([a-z0-9.-]+)\//.exec(url)?.[1]
  if (!h) return null
  if (h === 'fapi.binance.com') return 'fapi'
  if (h === 'dapi.binance.com') return 'dapi'
  if (h === 'api.binance.com' || /^api\d\.binance\.com$/.test(h) || h === 'data-api.binance.vision') return 'spot'
  return null
}

function param(url: string, k: string): string | null {
  const m = new RegExp(`[?&]${k}=([^&]*)`).exec(url)
  return m ? decodeURIComponent(m[1]) : null
}

/** 官方权重表（2026-09 的现行文档）；表里没有的合约记 1、现货记 2，不是币安的记 0 */
export function weightOf(url: string): number {
  const fam = familyOf(url)
  if (!fam) return 0
  const path = /^https:\/\/[^/]+(\/[^?]*)/.exec(url)?.[1] || ''
  const limit = Number(param(url, 'limit'))
  const hasSym = param(url, 'symbol') != null
  if (fam === 'spot') {
    if (path === '/api/v3/depth') { const n = limit > 0 ? limit : 100; return n <= 100 ? 5 : n <= 500 ? 25 : n <= 1000 ? 50 : 250 }
    if (path === '/api/v3/ticker/24hr') return hasSym ? 2 : 80
    return 2
  }
  if (/\/(klines|continuousKlines|indexPriceKlines|markPriceKlines|premiumIndexKlines)$/.test(path)) {
    const n = limit > 0 ? limit : 500
    return n < 100 ? 1 : n < 500 ? 2 : n <= 1000 ? 5 : 10
  }
  if (/\/ticker\/24hr$/.test(path)) return hasSym ? 1 : 40
  if (/\/premiumIndex$/.test(path)) return hasSym ? 1 : 10
  if (/\/ticker\/price$/.test(path)) return hasSym ? 1 : 2
  if (/\/ticker\/bookTicker$/.test(path)) return hasSym ? 2 : 5
  if (/\/depth$/.test(path)) { const n = limit > 0 ? limit : 500; return n <= 50 ? 2 : n <= 100 ? 5 : n <= 500 ? 10 : 20 }
  if (/\/(aggTrades|trades)$/.test(path)) return 20
  return 1
}

interface Cool { until: number; strikes: number }
/** 落盘的那一份：各道各主机的冷却、各道各族一分钟内的 [时间, 权重]。
 *  键：直连就是主机名 / 族名（与 2026-10-05 之前落盘的格式一致，老数据照读）；网关那一道加「@gw」后缀。 */
export interface LimitSnap { cool: Record<string, Cool>; used: Record<string, [number, number][]> }
/** raw：可选，返回盘上那一份的原文；给了就按原文判断「别的页动过没有」，没动过不再解析 */
export interface LimitStore { load(): unknown; save(s: LimitSnap): void; raw?(): string | null }

const num = (x: unknown): x is number => typeof x === 'number' && Number.isFinite(x)
/** 网关线路的那一道：同一个币安地址，走网关时出口是新加坡那台、额度是服务端那份，冷却与预算都和直连分开记 */
const GW = '@gw'
const laneOf = (key: string, gw: boolean): string => gw ? key + GW : key
const LANE_KEY = /^(fapi|dapi|spot)(@gw)?$/

/** 网关线路下合约 REST 由新加坡那台转发（见 rest.ts viaRoute），出口 IP 是全站网页用户共用的一个，
 *  服务端给网页透传一分钟 1600 权重（venues/binance.rs BUDGET）。每个浏览器只用其中的 800：
 *  两台电脑同时开十六图也排得下，不会有一台把共用额度吃光、另一台整片 429。
 *  原来照直连的 1200 放行，服务端只有 1000：一台开十六图加高频切换就能把服务端排队挤爆，
 *  回来的 429 把整个 fapi 主机冷却掉，几格当场空着（2026-10-03 压测）。 */
export const GATEWAY_SHARE = 2 / 3

export class Limiter {
  private cool = new Map<string, Cool>()
  private used = new Map<string, { t: number; w: number }[]>()
  /** 上一次读到 / 写下的盘上原文；没变就不再解析（原来每次 admit 都把一两千笔的账本整份 JSON.parse 两遍、排序一遍） */
  private seen: string | null | undefined = undefined
  constructor(private budget: Record<Family, number> = BUDGET, private store?: LimitStore) {}

  /** 有共用的一份时：每次读写前先读回别的页 / 上一次页面记的；盘上写坏了当没记过 */
  private pull(): void {
    if (!this.store) return
    let text: string | null | undefined
    try { text = this.store.raw?.() } catch { text = undefined }
    if (text !== undefined && text === this.seen) return
    let raw: unknown = null
    try { raw = text !== undefined ? (text ? JSON.parse(text) : null) : this.store.load() } catch { raw = null }
    this.seen = text
    const snap = raw && typeof raw === 'object' ? raw as Partial<LimitSnap> : {}
    this.cool.clear()
    if (snap.cool && typeof snap.cool === 'object') {
      for (const [h, c] of Object.entries(snap.cool)) if (c && num(c.until) && num(c.strikes)) this.cool.set(h, { until: c.until, strikes: c.strikes })
    }
    this.used.clear()
    if (snap.used && typeof snap.used === 'object') {
      for (const [k, v] of Object.entries(snap.used)) {
        if (!LANE_KEY.test(k) || !Array.isArray(v)) continue
        this.used.set(k, v.filter(x => Array.isArray(x) && num(x[0]) && num(x[1])).map(([t, w]) => ({ t, w })).sort((a, b) => a.t - b.t))
      }
    }
  }
  private push(now: number): void {
    if (!this.store) return
    const snap: LimitSnap = { cool: {}, used: {} }
    for (const [h, c] of this.cool) if (c.until > now || c.strikes) snap.cool[h] = c
    for (const [k, all] of this.used) {
      const list = all.filter(x => now - x.t < WINDOW)
      if (list.length) snap.used[k] = list.map(x => [x.t, x.w])
    }
    try { this.store.save(snap) } catch { /* 存不下就只记本页 */ }
    try { this.seen = this.store.raw?.() } catch { this.seen = undefined }
  }

  /** 这个地址的主机还要冷却多久（毫秒）；0 = 可以发。gw：这一次是不是走网关（走网关看网关那一道） */
  coolingFor(url: string, now: number, gw = false): number {
    this.pull()
    const c = this.cool.get(laneOf(hostOf(url), gw))
    return c && c.until > now ? c.until - now : 0
  }

  /** 记一次响应：429 / 418 把主机关进冷却（再犯翻倍）；冷却过后的成功清掉再犯计数；其它状态什么都不做。
   *  gw：这一次走的是网关——网关回的 429 是服务端那份额度满了，只冷却网关这一道，不连累直连；反过来直连被封
   *  （418 封的是这台电脑的出口 IP）也不连累网关，用户切到网关就是绕开封禁的办法，原来切过去照样被本地冷却拦着几分钟 */
  noteStatus(url: string, status: number, retryAfter: string | null | undefined, now: number, gw = false): void {
    const hit = status === 429 || status === 418
    if (!hit && !(status >= 200 && status < 300)) return
    this.pull()
    const host = laneOf(hostOf(url), gw)
    const c = this.cool.get(host)
    if (!hit) {
      if (!c?.strikes || c.until > now) return
      this.cool.delete(host)
    } else {
      const next: Cool = c ? { ...c } : { until: 0, strikes: 0 }
      if (next.until <= now) next.strikes++
      const sec = retryAfter != null && retryAfter !== '' ? Number(retryAfter) : NaN
      const base = status === 418 ? COOL_418_MS : COOL_429_MS, cap = status === 418 ? CAP_418_MS : CAP_429_MS
      const ms = Number.isFinite(sec) && sec > 0 ? sec * 1000 : Math.min(cap, base * 2 ** Math.max(0, next.strikes - 1))
      next.until = Math.max(next.until, now + ms)
      this.cool.set(host, next)
    }
    this.push(now)
  }

  /** 这一族（这一道）现在一分钟内记了多少权重 */
  usedOf(fam: Family, now: number, gw = false): number { this.pull(); return this.sum(laneOf(fam, gw), now) }
  private sum(lane: string, now: number): number {
    const list = this.used.get(lane) || []
    let k = 0
    while (k < list.length && now - list[k].t >= WINDOW) k++
    if (k) list.splice(0, k)
    let s = 0
    for (const x of list) s += x.w
    return s
  }

  /** 预算：还要等多久才能发（0 = 现在就发，并且已经记了账）；不是币安的地址不管。
   *  share < 1 是后台请求（板块迷你走势这类一次一大批的）：只许用到预算的这一截，剩下的留给图表自己的 K 线，
   *  免得 180 只小走势把预算吃满、正在看的那一格排在它们后面干等（2026-09-30 regress themes 段）。
   *  gw：走网关的记在网关那一道，上限是这一族预算的 GATEWAY_SHARE（fapi 800）；直连那一道仍是 1200，
   *  两道互不挤占（直连记的是这台电脑出口 IP 的权重，网关记的是服务端那份共用额度） */
  take(url: string, now: number, share = 1, gw = false): number {
    const fam = familyOf(url)
    if (!fam) return 0
    this.pull()
    const lane = laneOf(fam, gw)
    const cap = Math.max(1, Math.floor(this.budget[fam] * (gw ? GATEWAY_SHARE : 1) * Math.min(1, Math.max(0, share))))
    const w = Math.min(weightOf(url), cap)
    const list = this.used.get(lane) || []
    this.used.set(lane, list)
    let sum = this.sum(lane, now)
    if (sum + w > cap) {
      // 等到最早的几笔滚出窗口、腾出 w 为止
      let k = 0
      while (k < list.length && sum + w > cap) { sum -= list[k].w; k++ }
      return k ? Math.max(1, list[k - 1].t + WINDOW - now) : 1
    }
    list.push({ t: now, w })
    this.push(now)
    return 0
  }

  reset(): void { this.cool.clear(); this.used.clear(); this.push(0) }
}

export const LIMIT_KEY = 'hkline-web-rate-limit'
const lsStore: LimitStore | undefined = typeof localStorage === 'undefined' ? undefined : {
  load: () => { const t = localStorage.getItem(LIMIT_KEY); return t ? JSON.parse(t) : null },
  save: s => localStorage.setItem(LIMIT_KEY, JSON.stringify(s)),
  raw: () => localStorage.getItem(LIMIT_KEY),
}
const limiter = new Limiter(BUDGET, lsStore)

let viaGateway: (url: string) => boolean = () => false
/** rest.ts 告诉这里「这个地址现在是不是走网关」（limit 不直接读线路状态，免得循环引用） */
export function setGatewayProbe(f: (url: string) => boolean): void { viaGateway = f }

/** 这个地址的主机还要冷却多久（毫秒）；0 = 可以发。默认按现在的线路看那一道 */
export function coolingFor(url: string, now = Date.now(), gw = viaGateway(url)): number { return limiter.coolingFor(url, now, gw) }

/** 记一次响应（成功的也要记，用来清掉再犯计数）。gw 由发请求的那一刻定（发出去之后才切线路的，仍记在发出时那一道） */
export function noteStatus(url: string, status: number, retryAfter?: string | null, now = Date.now(), gw = viaGateway(url)): void {
  limiter.noteStatus(url, status, retryAfter, now, gw)
}

/** 冷却中的请求抛的错；消息带状态码开头，和真的 429 一样好认 */
export class RateLimited extends Error {
  constructor(readonly url: string, readonly waitMs: number) {
    super(`429 限流冷却中（${Math.ceil(waitMs / 1000)} 秒） ${url}`)
  }
}

export const isRateLimit = (e: unknown): boolean =>
  e instanceof RateLimited || /^(429|418)\b/.test(String((e as Error)?.message ?? e))

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms))

/** 后台请求能用的那一截预算 */
export const BACKGROUND_SHARE = 0.6

/** 排队期间要的人已经不要了（换了品种 / 周期）：不发、不记账 */
export class Superseded extends Error {
  constructor(readonly url: string) { super(`已作废 ${url}`) }
}

/** 发之前：排进这一族（这一道）的一分钟预算；排队中主机进了冷却就抛 RateLimited。不是币安的地址直接放行。
 *  background：一次一大批、晚一点到也无妨的请求，只用预算的 BACKGROUND_SHARE。
 *  alive：排队中每醒一次问一下还要不要，不要了就抛 Superseded。原来作废的请求照样排着、轮到了照样发、照样记账，
 *  连着换几十次品种之后预算全被作废的 K 线占满，最后要的那只反而排在最后（2026-09-29 A 路压测：300 次高频切换后
 *  16 格里一半是空的或还画着上一只）。
 *  返回这一次记在哪一道（true = 网关），发出去之后 noteStatus 记回同一道。 */
export async function admit(url: string, background = false, alive?: () => boolean): Promise<boolean> {
  for (;;) {
    if (alive && !alive()) throw new Superseded(url)
    const gw = viaGateway(url)
    const cool = limiter.coolingFor(url, Date.now(), gw)
    if (cool > 0) throw new RateLimited(url, cool)
    const w = limiter.take(url, Date.now(), background ? BACKGROUND_SHARE : 1, gw)
    if (!w) return gw
    await sleep(Math.min(w, alive ? 1000 : 5000))
  }
}

/** 测试用 */
export function resetLimits(): void { limiter.reset() }

// 压测脚本读：各族这一分钟记了多少权重、各主机的冷却（网关那一道带 Gw 后缀）
;(globalThis as unknown as { __limit?: () => unknown }).__limit = () => {
  const now = Date.now()
  const F = 'https://fapi.binance.com/'
  return {
    fapi: limiter.usedOf('fapi', now), dapi: limiter.usedOf('dapi', now), spot: limiter.usedOf('spot', now),
    fapiGw: limiter.usedOf('fapi', now, true), dapiGw: limiter.usedOf('dapi', now, true),
    coolFapi: limiter.coolingFor(F, now), coolFapiGw: limiter.coolingFor(F, now, true),
    coolSpot: limiter.coolingFor('https://data-api.binance.vision/', now),
  }
}
