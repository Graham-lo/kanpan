/* Hkline Web · 复盘：kanpan-api 的 /v1/native-review 接口
 *
 * 一律同源相对路径（开发时 Vite 把 /v1 代理到线上，部署后网页与接口同域）。
 * 成功回 {"data": …}，失败回 {"error": {"code": "…"}}；改动类请求必须带 Idempotency-Key。
 * 登录着时走账号模块的 authed（续期、被拒重试、被顶掉都由它管）；只有调试令牌才原样带上。
 */
import { st } from '../app/store'
import { ApiError, authed, readStored } from '../account/client'
import { IV_MS } from '../util/format'
import { REST, j } from '../market/rest'
import type { Bar } from '../chart/calc'
import type { ChartRange, SavedMatch, SearchResults, SearchStatus, Statistics, TradeRecord, ViewRecord } from './types'

const BASE = '/v1/native-review'
const DEV_TOKEN_KEY = 'hkline-review-dev-token'

/** 访问令牌：账号模块登录后放在 st.account.accessToken */
export function reviewToken(): string | null {
  const t = (st as unknown as { account?: { accessToken?: string } }).account?.accessToken
  if (t) return t
  // —— 调试入口（只在 store 里没有令牌时才看）——
  // 网页版登录接好之前，开发与验收截图用：地址栏带 ?reviewToken=…，或在 localStorage 里放
  // hkline-review-dev-token。正式用户走账号模块登录，不会碰到这里。
  try {
    const q = new URLSearchParams(location.search).get('reviewToken')
    if (q) return q
    return localStorage.getItem(DEV_TOKEN_KEY)
  } catch { return null }
}

export class ReviewError extends Error {
  code: string
  status: number
  constructor(code: string, status: number) { super(code); this.code = code; this.status = status }
}

/** 错误码 → 给人看的话 */
export function errorText(e: unknown): string {
  const code = e instanceof ReviewError ? e.code : ''
  const status = e instanceof ReviewError ? e.status : 0
  const M: Record<string, string> = {
    not_logged_in: '还没登录',
    network: '连不上服务器，检查网络后再试',
    timeout: '服务器响应太慢，稍后再试',
    search_busy: '找相似一小时最多 20 次，稍后再试',
    search_not_ready: '还在找，稍等一下',
    record_revision_changed: '这条记录刚在别的设备上改过，已刷新，再保存一次',
    invalid_chart_range: '这段图表区间不完整，找不了相似',
    idempotency_key_required: '请求缺少幂等键',
  }
  if (M[code]) return M[code]
  if (status === 401) return '登录已过期，重新登录后再看'
  if (status === 404) return '服务器上没有这条'
  if (status === 429) return '操作太频繁，稍后再试'
  if (status >= 500) return '服务器出错了，稍后再试'
  return code ? `出错了（${code}）` : '出错了'
}

export function uuid(): string {
  const c = globalThis.crypto
  if (c?.randomUUID) return c.randomUUID()
  const b = new Uint8Array(16)
  if (c?.getRandomValues) c.getRandomValues(b); else for (let i = 0; i < 16; i++) b[i] = Math.floor(Math.random() * 256)
  b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80
  const h = [...b].map(x => x.toString(16).padStart(2, '0')).join('')
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
}

const TIMEOUT = 15000

async function call<T>(method: string, path: string, body?: unknown, idem?: string | boolean): Promise<T> {
  const idemHeaders: Record<string, string> = idem ? { 'Idempotency-Key': typeof idem === 'string' ? idem : uuid() } : {}
  // 账号模块登录着：走它的 authed（access 到期先换、被拒换一次再试、被顶掉收尾）。
  // 不能直接拿 st.account.accessToken：浏览器关了一阵再打开，那把 access 早过期了，
  // 页面第一时间进复盘就会被判「登录已过期」，而 refresh 其实还有效。
  if (readStored()) {
    let timer: ReturnType<typeof setTimeout> | undefined
    try {
      return await Promise.race([
        authed<T>(method, BASE + path, body, idemHeaders),
        new Promise<never>((_, rej) => { timer = setTimeout(() => rej(new ReviewError('timeout', 0)), TIMEOUT) }),
      ])
    } catch (e) {
      if (e instanceof ApiError) throw new ReviewError(e.code === 'authentication_failed' ? 'not_logged_in' : e.code, e.status)
      throw e
    } finally { clearTimeout(timer) }
  }
  // 调试入口（地址栏 / localStorage 放的令牌）：原样带上
  const tok = reviewToken()
  if (!tok) throw new ReviewError('not_logged_in', 401)
  const headers: Record<string, string> = { authorization: 'Bearer ' + tok, ...idemHeaders }
  if (body !== undefined) headers['content-type'] = 'application/json'
  const ctl = new AbortController()
  const timer = setTimeout(() => ctl.abort(), TIMEOUT)
  let r: Response
  try {
    r = await fetch(BASE + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), cache: 'no-store', signal: ctl.signal })
  } catch (e) {
    throw new ReviewError((e as Error)?.name === 'AbortError' ? 'timeout' : 'network', 0)
  } finally { clearTimeout(timer) }
  const txt = await r.text()
  let v: { data?: T; error?: { code?: string } } | null = null
  try { v = txt ? JSON.parse(txt) : null } catch { v = null }
  if (!r.ok) throw new ReviewError(v?.error?.code || `http_${r.status}`, r.status)
  return (v && 'data' in v ? v.data : v) as T
}

/** 翻页拉全：每页 50 条，游标 after；最多 40 页（2000 条）防止死循环 */
async function all<T>(path: string, key: 'records' | 'items'): Promise<T[]> {
  const out: T[] = []
  let after: string | null = null
  for (let i = 0; i < 40; i++) {
    const sep = path.includes('?') ? '&' : '?'
    const page: Record<string, unknown> = await call('GET', after ? `${path}${sep}after=${encodeURIComponent(after)}` : path)
    out.push(...((page[key] as T[]) || []))
    after = (page.next as string | null) ?? null
    if (!after) break
  }
  return out
}

export const reviewApi = {
  views: (): Promise<ViewRecord[]> => all<ViewRecord>('/records', 'records'),
  trades: (): Promise<TradeRecord[]> => all<TradeRecord>('/records?kind=trade', 'records'),
  statistics: (): Promise<Statistics> => call('GET', '/statistics'),
  saved: (): Promise<SavedMatch[]> => all<SavedMatch>('/saved-matches', 'items'),
  /** 发起找相似：幂等键就是这次搜索的编号 */
  startSearch: (range: ChartRange, cutoff: number, scope: 'history' | 'private' = 'history'): Promise<{ id: string; status: string }> => {
    const id = uuid()
    return call('POST', '/searches', { range, cutoff, scope }, id)
  },
  search: (id: string): Promise<SearchStatus> => call('GET', `/searches/${id}`),
  results: async (id: string): Promise<SearchResults> => {
    const first = await call<SearchResults>('GET', `/searches/${id}/results`)
    let next = first.next
    for (let i = 0; i < 10 && next; i++) {
      const p = await call<SearchResults>('GET', `/searches/${id}/results?after=${encodeURIComponent(next)}`)
      first.items.push(...p.items); next = p.next
    }
    return first
  },
  save: (searchId: string, matchId: string): Promise<SavedMatch> => call('POST', '/saved-matches', { searchId, matchId }, true),
  unsave: (id: string, expectedRevision: number): Promise<unknown> => call('DELETE', `/saved-matches/${id}`, { expectedRevision }, true),
  tradeNote: (id: string, expectedRevision: number, text: string): Promise<TradeRecord> => call('POST', `/trades/${id}/note`, { expectedRevision, text }, true),
}

// ------------------------------------------------------------ K 线（回放用，直连币安）
type Row = [number, string, string, string, string, string, number, string, ...unknown[]]

/** 拉一段 [from, to] 的 K 线（按开盘时间），1500 根一页，最多 6000 根 */
export async function fetchWindow(symbol: string, iv: string, from: number, to: number): Promise<Bar[]> {
  const step = IV_MS[iv]
  const out: Bar[] = []
  let s = from
  while (s <= to && out.length < 6000) {
    const rows = await j<Row[]>(`${REST}/fapi/v1/klines?symbol=${encodeURIComponent(symbol)}&interval=${iv}&startTime=${s}&endTime=${to}&limit=1500`, 10000)
    if (!rows.length) break
    for (const r of rows) out.push({ t: r[0], o: +r[1], h: +r[2], l: +r[3], c: +r[4], v: +r[7] })
    if (rows.length < 1500) break
    s = rows[rows.length - 1][0] + step
  }
  return out
}

// ------------------------------------------------------------ 找过的相似（服务端没有「列出我的搜索」接口，编号记在本机）
export interface StoredSearch { id: string; symbol: string; iv: string; bars: number; label: string; created: number }
const SEARCH_KEY = 'hkline-review-searches'

export function storedSearches(): StoredSearch[] {
  try {
    const v = JSON.parse(localStorage.getItem(SEARCH_KEY) || '[]')
    return Array.isArray(v) ? v.filter(x => x && typeof x.id === 'string') : []
  } catch { return [] }
}
export function rememberSearch(s: StoredSearch): void {
  const list = [s, ...storedSearches().filter(x => x.id !== s.id)].slice(0, 8)
  try { localStorage.setItem(SEARCH_KEY, JSON.stringify(list)) } catch { /* 存不下就只在这次打开里有 */ }
}
export function forgetSearch(id: string): void {
  try { localStorage.setItem(SEARCH_KEY, JSON.stringify(storedSearches().filter(x => x.id !== id))) } catch { /* 同上 */ }
}

