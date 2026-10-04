/* Hkline Web · 复盘：kanpan-api 的 /v1/native-review 接口
 *
 * 一律同源相对路径（开发时 Vite 把 /v1 代理到线上，部署后网页与接口同域）。
 * 成功回 {"data": …}，失败回 {"error": {"code": "…"}}；改动类请求必须带 Idempotency-Key。
 * 登录着时走账号模块的 authed（续期、被拒重试、被顶掉都由它管）；只有调试令牌才原样带上。
 */
import { session } from '../account/session'
import { ApiError, authed, readStored } from '../account/client'
import { IV_MS } from '../util/format'
import { REST, j } from '../market/rest'
import type { Bar } from '../chart/calc'
import type { NoteDraft } from '../notes/draft'
import type { ChartRange, Match, SavedMatch, SearchResults, SearchStatus, Statistics, TradeRecord, ViewRecord } from './types'
import type { RecordDetail, RecordPage, RecordQuery, RecordRevision, ReviewAttachment, ReviewReflection, SavedPage, TradePage, ViewRecordFull } from './types'

const BASE = '/v1/native-review'
const DEV_TOKEN_KEY = 'hkline-review-dev-token'

/** 访问令牌：账号模块登录后放在 session.accessToken */
export function reviewToken(): string | null {
  const t = session.accessToken
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
    search_busy: '上一次找相似还没找完（一次只跑一个），或一小时内已经找了 20 次，稍后再试',
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
  // 不能直接拿 session.accessToken：浏览器关了一阵再打开，那把 access 早过期了，
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
  /** 收藏：服务端只回 {item}、不带版本号（iOS 也是存完重拉列表），而取消收藏必须带版本，
   *  所以存完从列表里把这一条连版本一起取回来 */
  save: async (searchId: string, matchId: string): Promise<SavedMatch> => {
    const r = await call<{ item: Match; revision?: number }>('POST', '/saved-matches', { searchId, matchId }, true)
    if (typeof r.revision === 'number') return { item: r.item, revision: r.revision }
    const got = (await all<SavedMatch>('/saved-matches', 'items')).find(x => x.item.id === (r.item?.id ?? matchId))
    if (!got) throw new ReviewError('not_found', 404)
    return got
  },
  unsave: (id: string, expectedRevision: number): Promise<unknown> => call('DELETE', `/saved-matches/${id}`, { expectedRevision }, true),
  /** 「当时怎么想」：服务端回 {record}（review_trade.rs note），这里拆开再给调用方——
   *  之前直接把外壳当回合返回，PC 端 Object.assign(t, next) 会把 revision 等字段留成旧值、
   *  再挂一个 record 属性上去，第二次保存必 409 */
  tradeNote: (id: string, expectedRevision: number, text: string): Promise<TradeRecord> =>
    call<{ record: TradeRecord }>('POST', `/trades/${id}/note`, { expectedRevision, text }, true).then(r => r.record),
  /** 记一笔：建一条观点记录。幂等键就用记录编号——断网重发、补传都落在同一条上 */
  createRecord: (draft: NoteDraft): Promise<{ record: ViewRecord }> => call('POST', '/records', draft, draft.id),
  /** 记一笔那张图（PNG / JPEG 的 base64，解码后 ≤ 2 MiB）；重复上传就是覆盖 */
  putShot: (id: string, image: string): Promise<unknown> => call('POST', `/records/${id}/shot`, { image }, true),
  /** 一只品种的交易回合（侧栏「成交」用） */
  tradesOf: (symbol: string): Promise<TradeRecord[]> => all<TradeRecord>(`/records?kind=trade&symbol=${encodeURIComponent(symbol)}`, 'records'),
  /** 交易回合的第一页（只看有没有、最近一次上传）：不翻页 */
  tradesFirstPage: async (): Promise<TradeRecord[]> => ((await call<{ records?: TradeRecord[] }>('GET', '/records?kind=trade')).records ?? []),
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
/** 按账号分开记（换个账号登录不会去问上个账号的搜索、也不会因为 404 把它们删掉）；
 *  没有账号号（调试令牌）时用老键。老版本不分账号记的那份，第一个登录上来的账号认领。 */
const LEGACY_SEARCH_KEY = 'hkline-review-searches'
export function searchKey(): string { return session.userId ? `${LEGACY_SEARCH_KEY}:${session.userId}` : LEGACY_SEARCH_KEY }

export function storedSearches(): StoredSearch[] {
  try {
    const key = searchKey()
    let raw = localStorage.getItem(key)
    if (raw == null && key !== LEGACY_SEARCH_KEY) {
      const legacy = localStorage.getItem(LEGACY_SEARCH_KEY)
      if (legacy != null) { localStorage.setItem(key, legacy); localStorage.removeItem(LEGACY_SEARCH_KEY); raw = legacy }
    }
    const v = JSON.parse(raw || '[]')
    return Array.isArray(v) ? v.filter(x => x && typeof x.id === 'string') : []
  } catch { return [] }
}
export function rememberSearch(s: StoredSearch): void {
  const list = [s, ...storedSearches().filter(x => x.id !== s.id)].slice(0, 8)
  try { localStorage.setItem(searchKey(), JSON.stringify(list)) } catch { /* 存不下就只在这次打开里有 */ }
}
export function forgetSearch(id: string): void {
  try { localStorage.setItem(searchKey(), JSON.stringify(storedSearches().filter(x => x.id !== id))) } catch { /* 同上 */ }
}


// ------------------------------------------------------------ 手机网页版复盘本：按页拉、详情、复盘、作废、归并、图、修订
// 改动类一律带幂等键（call 的第四个参数 true）；冲突码原样抛出（record_revision_changed /
// record_voided / group_already_resolved），由页面决定重拉还是提示。
function query(params: Record<string, string | boolean | null | undefined>): string {
  const out: string[] = []
  for (const [k, v] of Object.entries(params)) {
    if (v == null || v === '' || v === false) continue
    out.push(`${k}=${encodeURIComponent(String(v))}`)
  }
  return out.length ? '?' + out.join('&') : ''
}

export const reviewBookApi = {
  /** 观点记录的一页（50 条）；after 是上一页给的游标 */
  recordsPage: (q: RecordQuery, after?: string | null): Promise<RecordPage> =>
    call<RecordPage>('GET', '/records' + query({ after, symbol: q.symbol, state: q.state, q: q.q?.trim(), todo: q.todo, decided: q.decided }))
      .then(p => ({ records: p?.records ?? [], next: p?.next ?? null })),
  recordDetail: (id: string): Promise<RecordDetail> => call('GET', `/records/${id}`),
  /** 保存草稿 / 完成复盘：服务端把上一份已完成的复盘挪进历史 */
  saveReflection: (id: string, expectedRevision: number, reflection: ReviewReflection, publish: boolean): Promise<{ record: ViewRecordFull }> =>
    call('POST', `/records/${id}/reflection`, { expectedRevision, reflection, publish }, true),
  voidRecord: (id: string, expectedRevision: number): Promise<{ record: ViewRecordFull }> =>
    call('POST', `/records/${id}/void`, { expectedRevision }, true),
  /** 「与最近一笔是同一次判断吗？」 */
  resolveGroup: (id: string, expectedRevision: number, sameEpisode: boolean): Promise<{ record: ViewRecordFull }> =>
    call('POST', `/records/${id}/group`, { expectedRevision, sameEpisode }, true),
  /** 记一笔那一刻的图（base64） */
  recordShot: (id: string): Promise<{ image: string; mime: string }> => call('GET', `/records/${id}/shot`),
  revisions: (id: string): Promise<RecordRevision[]> =>
    call<{ revisions?: RecordRevision[] }>('GET', `/records/${id}/revisions`).then(r => r?.revisions ?? []),
  /** 交易回合的一页（50 条） */
  tradesPage: (after?: string | null): Promise<TradePage> =>
    call<TradePage>('GET', '/records' + query({ kind: 'trade', after }))
      .then(p => ({ records: p?.records ?? [], next: p?.next ?? null })),
  /** 一笔交易的最新一版（409 之后重拉用） */
  tradeDetail: (id: string): Promise<TradeRecord> => call<{ record: TradeRecord }>('GET', `/records/${id}`).then(r => r.record),
  /** 「当时怎么想」：与 reviewApi.tradeNote 同一个接口、同一份拆壳 */
  saveTradeNote: (id: string, expectedRevision: number, text: string): Promise<TradeRecord> => reviewApi.tradeNote(id, expectedRevision, text),

  // —— 找相似（照 iOS ReviewSearchModel：编号由调用方生成，同时当幂等键；离开 / 重找时 DELETE 掉）
  startSearch: (id: string, range: ChartRange, cutoff: number, scope: 'history' | 'private'): Promise<SearchStatus> =>
    call('POST', '/searches', { range, cutoff, scope }, id),
  searchStatus: (id: string): Promise<SearchStatus> => call('GET', `/searches/${id}`),
  /** 取消：服务端把 queued / running 标成 cancelled；还没开始的编号也会占位成 cancelled，免得之后再起 */
  cancelSearch: (id: string): Promise<unknown> => call('DELETE', `/searches/${id}`, undefined, true),
  /** 结果的一页（20 条）；after 是上一页给的偏移 */
  searchResultsPage: (id: string, after?: string | null): Promise<SearchResults> =>
    call<SearchResults>('GET', `/searches/${id}/results` + query({ after })),
  /** 存一条相似案例：服务端回 {item} */
  saveMatch: (searchId: string, matchId: string): Promise<{ item: Match }> =>
    call('POST', '/saved-matches', { searchId, matchId }, true),
  savedPage: (after?: string | null): Promise<SavedPage> =>
    call<SavedPage>('GET', '/saved-matches' + query({ after })).then(p => ({ items: p?.items ?? [], next: p?.next ?? null })),
  unsaveMatch: (id: string, expectedRevision: number): Promise<unknown> =>
    call('DELETE', `/saved-matches/${id}`, { expectedRevision }, true),

  // —— 补图（一条记录最多三张，单张 ≤ 5 MB；编号由调用方生成，同时当幂等键）
  attachments: (recordId: string): Promise<ReviewAttachment[]> =>
    call<{ items?: ReviewAttachment[] }>('GET', `/records/${recordId}/attachments`).then(r => r?.items ?? []),
  attachment: (id: string): Promise<{ image: string; mime: string }> => call('GET', `/attachments/${id}`),
  putAttachment: (id: string, recordId: string, image: string): Promise<unknown> =>
    call('POST', '/attachments', { id, recordId, image }, id),
  deleteAttachment: (id: string): Promise<unknown> => call('DELETE', `/attachments/${id}`, undefined, true),

  // —— 待传队列（手机网页版复盘本）：复盘 / 作废 / 归并共用一个出口，幂等键由队列给（这一次改动的编号），
  //    断网重发、隔离后重试都落在同一次改动上
  pushOperation: (recordId: string, kind: 'reflection' | 'void' | 'group', body: unknown, key: string): Promise<{ record: ViewRecordFull }> =>
    call('POST', `/records/${recordId}/${kind}`, body, key),
}
