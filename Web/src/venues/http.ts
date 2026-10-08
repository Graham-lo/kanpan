/* Hkline Web · 多交易所 · 行情 REST 的取数（各家共用的一层，不认识任何一家）
 *
 * 一家的地址都写成**直连地址**（那一家自己的域名）：
 *   - 限流：按主机名找到那一家唯一的限流器（market/limit.ts registerGate），排队、冷却、429 记账都在那一把上；
 *   - 线路：用户选网关就只走网关——那一家登记的 gateway() 把地址改写成同源 /v1/market/raw/<path>?source=<id>，
 *     改写不了（网关没开这条）就报错，不偷偷走直连；选直连就只直连，失败就报错，不切网关。
 * 浏览器跨域：OKX / Bybit / Hyperliquid / Coinbase 的公开 REST 都带 Access-Control-Allow-Origin；一律不发 Referer。
 */
import { S } from '../market/state'
import { admit, gatewayRewrite, noteStatus } from '../market/limit'
import type { FetchOpts } from './common'

/** 网关线路上这一家没开的地址 */
export class NoGatewayRoute extends Error {
  constructor(readonly url: string) { super(`网关没有这条：${url}`); this.name = 'NoGatewayRoute' }
}

/** 这条地址在这条线路上实际打哪里 */
export function routeUrl(url: string, route = S.route): string {
  if (route !== 'gateway') return url
  const g = gatewayRewrite(url)
  if (!g) throw new NoGatewayRoute(url)
  return g
}

async function send<T>(url: string, init: RequestInit, opts: FetchOpts, body?: unknown): Promise<T> {
  // 网关没开这条：排队之前就报错，不白占额度
  routeUrl(url, opts.route ?? S.route)
  // 限流按那一家官方的口径记（body 给 Hyperliquid 按权重算：candleSnapshot 按要的根数加码）。
  // 发往哪里按 admit 放行时记账的那一道定：原来地址在排队之前就算好了，排队中用户切到网关，这一条照旧打直连
  // （国内直连不通正是要切网关的时候），却又记在网关那一道、直连回的 429 还冷却了网关（2026-10-08 压测）
  const gw = await admit(url, opts.background, opts.alive, opts.onWait, body, opts.route ? opts.route === 'gateway' : undefined)
  const target = routeUrl(url, gw ? 'gateway' : 'direct')
  const ctl = new AbortController()
  const t = setTimeout(() => ctl.abort(), opts.ms ?? 10_000)
  try {
    const r = await fetch(target, { ...init, signal: ctl.signal, referrerPolicy: 'no-referrer', cache: 'no-store', ...(opts.priority ? { priority: opts.priority } : {}) })
    noteStatus(url, r.status, r.headers.get('Retry-After'), Date.now(), gw)
    if (!r.ok) throw new Error(`${r.status} ${url}`)
    return await r.json() as T
  } finally { clearTimeout(t) }
}

/** GET 一个直连地址（线路、限流由这一层管） */
export function vget<T = unknown>(url: string, opts: FetchOpts = {}): Promise<T> {
  return send<T>(url, { method: 'GET' }, opts)
}

/** POST JSON（Hyperliquid 的 /info）。同一个地址不同的 body 是不同的请求，限流按主机记 */
export function vpost<T = unknown>(url: string, body: unknown, opts: FetchOpts = {}): Promise<T> {
  return send<T>(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }, opts, body)
}

/** 同一个请求在途时共用（品种表、整表行情：搜索弹层和自选同一秒都要） */
const inflight = new Map<string, Promise<unknown>>()
export function shared<T>(key: string, make: () => Promise<T>): Promise<T> {
  const hit = inflight.get(key)
  if (hit) return hit as Promise<T>
  const p = make()
  inflight.set(key, p)
  const done = (): void => { if (inflight.get(key) === p) inflight.delete(key) }
  p.then(done, done)
  return p
}

/** 网关改写的通用形：直连地址的某个前缀 → 同源 /v1/market/raw/<余下的 path>?<原 query>&source=<id> */
export function rawRewrite(prefix: string, source: string, origin: () => string): (url: string) => string | null {
  return url => {
    if (!url.startsWith(prefix)) return null
    const rest = url.slice(prefix.length)
    const q = rest.indexOf('?')
    const path = q < 0 ? rest : rest.slice(0, q), query = q < 0 ? '' : rest.slice(q + 1)
    return `${origin()}/v1/market/raw/${path}?${query ? query + '&' : ''}source=${source}`
  }
}
