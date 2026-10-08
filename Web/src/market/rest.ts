/* Hkline Web · 币安 U 本位合约 REST
 *
 * 直连线路：浏览器直接取 fapi.binance.com（它对 /fapi/* 与 /futures/data/* 都回 Access-Control-Allow-Origin: *）。
 * 一律不发 Referer：币安 CloudFront 对来源页是 sslip.io 的请求回 403 且不带跨域头。
 * 网关线路：同样的地址改走新加坡那台的 /v1/market/raw/<path>?source=binance（viaRoute）——国内不开代理
 * 根本连不上 fapi.binance.com，2026-10-02 之前「网关」只管 WebSocket，手机 4G 上 K 线、品种表全是空的。
 * 限流闸（limit.ts）按币安的原地址认族与权重，但两条线路各记一道：直连花的是这台电脑出口 IP 的额度，
 * 网关花的是服务端那份共用额度，一边被限流不连累另一边（切到网关正是直连被封时的出路）。
 * 取不到就是取不到——不造演示数据，界面显示空态。
 */
import type { Bar } from '../chart/calc'
import { S, emit } from './state'
import { Superseded, admit, coolingFor, isRateLimit, noteStatus, setGatewayProbe } from './limit'
import { baseOf, badgeColor, cnOf, decOfTick, kindOfUnderlying, type Sym } from './symbols'
import { supplyOf } from './meta'
import { MACRO_SYMBOL, applyMacroTicker, isMacro, macroFallback, macroRewrite, type MacroTicker } from './macro'
import { ago } from '../util/clock'
import { IV_MS } from '../util/format'

export const REST = 'https://fapi.binance.com'

/** 自家服务器的根：线上与页面同源；本机开发（localhost）直接打线上那台。 */
export function apiOrigin(): string {
  if (typeof location !== 'undefined' && /^https:$/.test(location.protocol) && !/^localhost$|^127\./.test(location.hostname)) return location.origin
  return 'https://kanpan.43-160-232-253.sslip.io'
}
/** 网关线路下，币安合约的 REST 地址改成经新加坡透传的地址；别的地址与直连线路原样返回。 */
export function viaRoute(url: string): string {
  if (S.route !== 'gateway') return url
  const m = /^https:\/\/(?:fapi|dapi)\.binance\.com\/([^?#]+)(\?[^#]*)?$/.exec(url)
  if (!m) return url
  return `${apiOrigin()}/v1/market/raw/${m[1]}${m[2] ? `${m[2]}&` : '?'}source=binance`
}

// 走网关的合约 REST 只用网关那份共用额度里属于这个浏览器的一截（见 limit.ts GATEWAY_SHARE）
setGatewayProbe(url => viaRoute(url) !== url)

/** priority：给浏览器的取数优先级（同一条 HTTP/2 连接上谁先拿带宽）；冷启动并行预取的 K 线用 'low'，让品种表先到 */
/** onWait：限流闸里要排队时回调一次（排多久），界面可以先在格子里写「排队取数…」 */
export async function j<T = unknown>(url: string, ms = 8000, background = false, alive?: () => boolean, priority?: RequestPriority,
  onWait?: (ms: number) => void): Promise<T> {
  // 主机在限流冷却里就不发（抛 RateLimited）：429 之后接着打会被升级成 418 封 IP；
  // 一分钟权重快满了就先排队（见 limit.ts）；排队期间 alive() 说不要了就不发（抛 Superseded）
  // 美元指数：币安形状的 K 线 / 24h 行情改走自家服务器（不占币安额度），它没有的数据本地就抛（见 macro.ts）
  url = macroRewrite(url, apiOrigin()) ?? url
  const gw = await admit(url, background, alive, onWait)
  const ctl = new AbortController()
  const t = setTimeout(() => ctl.abort(), ms)
  try {
    const r = await fetch(viaRoute(url), { signal: ctl.signal, referrerPolicy: 'no-referrer', cache: 'no-store', ...(priority ? { priority } : {}) })
    noteStatus(url, r.status, r.headers.get('Retry-After'), Date.now(), gw)
    if (!r.ok) throw new Error(`${r.status} ${url}`)
    return await r.json() as T
  } finally { clearTimeout(t) }
}

export interface ExSymbol {
  symbol: string; baseAsset: string; quoteAsset: string; contractType: string; status: string
  underlyingType?: string; underlyingSubType?: string[]; onboardDate?: number
  filters: { filterType: string; tickSize?: string }[]; pricePrecision: number
}
export interface Ticker24 { symbol: string; lastPrice: string; priceChange: string; priceChangePercent: string; quoteVolume: string; openPrice: string; highPrice: string; lowPrice: string; count: number; closeTime: number }
interface Premium { symbol: string; lastFundingRate: string; nextFundingTime: number; markPrice: string; indexPrice: string; time?: number }

function blank(e: ExSymbol): Sym {
  const base = baseOf(e.symbol, e.baseAsset)
  const kind = kindOfUnderlying(e.underlyingType, base)
  const tick = e.filters.find(f => f.filterType === 'PRICE_FILTER')?.tickSize
  return {
    symbol: e.symbol, base, code: base, kind, cn: cnOf(base, kind),
    dec: tick ? decOfTick(tick) : Math.min(8, e.pricePrecision),
    color: badgeColor(base), price: null, chg: 0, pct: null, vol: 0, fr: null, nextFunding: null,
    ut: e.underlyingType, onboard: e.onboardDate || undefined,
    tags: e.underlyingSubType?.length ? [...new Set(e.underlyingSubType.map(t => t.toLowerCase()))].sort() : undefined,
  }
}

// ------------------------------------------------------------ exchangeInfo / ticker/24hr 全站共用一次
/** 全市场表、板块页的品种目录与行情都要 exchangeInfo（权重 1）与全量 ticker/24hr（权重 40）：
 *  在途的那一次大家共用，冷启动时不再各发一遍（以前进板块页会再取一次 exchangeInfo）。回来之后再要就是新的一次。 */
const shared = new Map<string, Promise<unknown>>()
function sharedGet<T>(path: string, ms: number, seen?: (v: T) => void): Promise<T> {
  const hit = shared.get(path)
  if (hit) return hit as Promise<T>
  const p = j<T>(`${REST}${path}`, ms).then(v => { seen?.(v); return v })
  shared.set(path, p)
  const done = (): void => { if (shared.get(path) === p) shared.delete(path) }
  p.then(done, done)
  return p
}
/** 币安合约 exchangeInfo（共用在途的那一次） */
export function fetchExchangeInfo(): Promise<{ symbols: ExSymbol[] }> { return sharedGet('/fapi/v1/exchangeInfo', 12000, noteExchange) }
/** 全量 ticker/24hr（共用在途的那一次） */
export function fetchTicker24(): Promise<Ticker24[]> { return sharedGet('/fapi/v1/ticker/24hr', 10000) }

/** 本会话最近一次取到的 exchangeInfo 里全部在交易的永续（各计价币都留，板块页挑合约要用）；没取到过是 null */
export interface ExchangeRow { symbol: string; baseAsset: string; quoteAsset: string; underlyingType?: string; underlyingSubType?: string[] }
let exchangeRowsSeen: ExchangeRow[] | null = null
export function exchangeRows(): ExchangeRow[] | null { return exchangeRowsSeen }
function noteExchange(ex: { symbols: ExSymbol[] }): void {
  const rows: ExchangeRow[] = []
  for (const e of ex.symbols) {
    if (e.status !== 'TRADING') continue
    if (e.contractType !== 'PERPETUAL' && e.contractType !== 'TRADIFI_PERPETUAL') continue
    rows.push({ symbol: e.symbol, baseAsset: e.baseAsset, quoteAsset: e.quoteAsset, underlyingType: e.underlyingType, underlyingSubType: e.underlyingSubType })
  }
  if (rows.length) exchangeRowsSeen = rows
}

// ------------------------------------------------------------ 全市场表的本机副本
/** 上次取到的全市场表（只留界面要的字段，几百条约 100 KB）：冷启动先拿它出画面，网络回来再换成新的。
 *  价格就是上次的价格，不另加状态字样。最多认 7 天，再老的不用（上新、下架差太多）。 */
export const UNIVERSE_CACHE_KEY = 'hkline-universe-v1'
export const UNIVERSE_CACHE_MAX_AGE = 7 * 86_400_000
function lsOf(): Storage | null {
  try { return typeof localStorage === 'undefined' ? null : localStorage } catch { return null }
}
const numOr = (v: unknown): number | null => typeof v === 'number' && Number.isFinite(v) ? v : null
function encodeSym(s: Sym): unknown[] {
  return [s.symbol, s.base, s.ut ?? '', s.dec, s.onboard ?? 0, s.tags?.join(',') ?? '', s.price, s.chg, s.pct,
    s.open ?? null, s.hi ?? null, s.lo ?? null, s.vol, s.count ?? null, s.fr, s.nextFunding, s.mark ?? null, s.index ?? null,
    s.pxAt ?? 0, s.statAt ?? 0, s.markAt ?? 0, s.supply ?? null, s.macro ? s.cn : '']
}
function decodeSym(r: unknown, now: number): Sym | null {
  if (!Array.isArray(r) || typeof r[0] !== 'string' || typeof r[1] !== 'string' || typeof r[3] !== 'number') return null
  const [symbol, base, ut, dec, onboard, tags] = r as [string, string, unknown, number, unknown, unknown]
  let s: Sym
  if (symbol === MACRO_SYMBOL) {
    s = macroFallback()
    if (typeof r[22] === 'string' && r[22]) s.cn = r[22]
    s.dec = dec
  } else {
    const u = typeof ut === 'string' && ut ? ut : undefined
    const kind = kindOfUnderlying(u, base)
    s = {
      symbol, base, code: base, kind, cn: cnOf(base, kind), dec, color: badgeColor(base),
      price: null, chg: 0, pct: null, vol: 0, fr: null, nextFunding: null, ut: u,
      onboard: numOr(onboard) || undefined,
      tags: typeof tags === 'string' && tags ? tags.split(',') : undefined,
    }
  }
  s.price = numOr(r[6]); s.chg = numOr(r[7]) ?? 0; s.pct = numOr(r[8])
  const opt = (k: 'open' | 'hi' | 'lo' | 'count' | 'mark' | 'index' | 'supply', v: unknown): void => { const x = numOr(v); if (x != null) s[k] = x }
  opt('open', r[9]); opt('hi', r[10]); opt('lo', r[11]); s.vol = numOr(r[12]) ?? 0; opt('count', r[13])
  s.fr = numOr(r[14])
  const nf = numOr(r[15]); s.nextFunding = nf != null && nf > now ? nf : null   // 过了的结算时刻不要（倒计时会是负的）
  opt('mark', r[16]); opt('index', r[17])
  s.pxAt = numOr(r[18]) ?? 0; s.statAt = numOr(r[19]) ?? 0; s.markAt = numOr(r[20]) ?? 0
  opt('supply', r[21])
  if (s.supply == null) { const sup = supplyOf(symbol); if (sup != null) s.supply = sup }
  return s
}
/** 把全市场表写进本机（写不下就算了：它只是让下次开得快一点） */
export function saveUniverse(map: Map<string, Sym> = S.symbols, store: Storage | null = lsOf()): boolean {
  if (!store || !map.size) return false
  try {
    store.setItem(UNIVERSE_CACHE_KEY, JSON.stringify({ v: 1, at: Date.now(), rows: [...map.values()].map(encodeSym) }))
    return true
  } catch { return false }
}
/** 读本机的全市场表；没有、坏了、太老都是 null */
export function readUniverse(store: Storage | null = lsOf(), now = Date.now()): Map<string, Sym> | null {
  if (!store) return null
  try {
    const v = JSON.parse(store.getItem(UNIVERSE_CACHE_KEY) ?? 'null') as { v?: unknown; at?: unknown; rows?: unknown } | null
    if (!v || v.v !== 1 || typeof v.at !== 'number' || now - v.at > UNIVERSE_CACHE_MAX_AGE || !Array.isArray(v.rows)) return null
    const m = new Map<string, Sym>()
    for (const r of v.rows) { const s = decodeSym(r, now); if (s) m.set(s.symbol, s) }
    return m.size ? m : null
  } catch { return null }
}
/** 关页、切走时把手里（推送刷过的）最新价写一份；10 秒内只写一次 */
let savedAt = 0
let saveHooked = false
function hookSave(): void {
  if (saveHooked || typeof addEventListener !== 'function' || typeof document === 'undefined') return
  saveHooked = true
  const flush = (): void => {
    if (!S.symbols.size || S.live === false && !S.universeAt || ago(savedAt) < 10_000) return
    savedAt = Date.now(); saveUniverse()
  }
  addEventListener('pagehide', flush)
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') flush() })
}

/** 全市场：exchangeInfo（品种与分类）+ ticker/24hr（价与量）+ premiumIndex（费率、标记价、指数价）。
 *  本会话第一次取、手里还没有表时：本机有上次的表就先用它（S.live 仍是 null、照常发 universe 事件）、马上返回，
 *  网络那一份在后台取，回来再发一次 universe；后台这次失败了自己隔一会儿再试（冷却或 30 秒起、逐次加长）。
 *  同一时刻多处要表只取一次（在途的共用）。 */
let netP: Promise<Map<string, Sym>> | null = null
let diskTried = false
let diskRetry = 0
export function loadUniverse(): Promise<Map<string, Sym>> {
  hookSave()
  if (!diskTried) {
    diskTried = true
    const disk = !S.symbols.size && S.live == null ? readUniverse() : null
    if (disk) {
      S.symbols = disk
      S.error = ''
      emit({ type: 'universe' })
      void fetchUniverse().then(retryAfterDisk)
      return Promise.resolve(S.symbols)
    }
  }
  return fetchUniverse()
}
function fetchUniverse(): Promise<Map<string, Sym>> {
  return netP ??= netUniverse().finally(() => { netP = null })
}
/** 先摆了本机那份、网络一直没取到：自己再取（不等哪一页来要） */
function retryAfterDisk(): void {
  if (S.live !== false || S.universeAt) { diskRetry = 0; return }
  const wait = S.limited ? Math.max(coolingFor(REST), 1000) + 500 : Math.min(30_000 * 2 ** diskRetry, 240_000)
  diskRetry++
  setTimeout(() => { if (!S.universeAt) void fetchUniverse().then(retryAfterDisk) }, wait)
}
/** 测试用：回到「本会话还没读过本机表」 */
export function resetUniverseForTest(): void { netP = null; diskTried = false; diskRetry = 0; savedAt = 0; shared.clear(); exchangeRowsSeen = null }

async function netUniverse(): Promise<Map<string, Sym>> {
  try {
    const [ex, tk, pi] = await Promise.all([
      fetchExchangeInfo(),
      fetchTicker24(),
      j<Premium[]>(`${REST}/fapi/v1/premiumIndex`),
    ])
    const next = new Map<string, Sym>()
    for (const e of ex.symbols) {
      if (e.quoteAsset !== 'USDT' || e.status !== 'TRADING') continue
      if (e.contractType !== 'PERPETUAL' && e.contractType !== 'TRADIFI_PERPETUAL') continue
      let s = S.symbols.get(e.symbol)
      if (!s) { s = blank(e); const sup = supplyOf(e.symbol); if (sup != null) s.supply = sup }   // 元数据先于全市场表到了
      else if (!S.universeAt) { const b = blank(e); Object.assign(s, { kind: b.kind, dec: b.dec, ut: b.ut, tags: b.tags, onboard: b.onboard }) }   // 本机那份的分类、精度以交易所这次的为准
      next.set(e.symbol, s)
    }
    // 美元指数不在币安的表里：手里有就原样带过来，没有就放内置的一行（价格等 loadMacro / 推送来填）
    next.set(MACRO_SYMBOL, S.symbols.get(MACRO_SYMBOL) ?? macroFallback())
    // 三个请求要几百毫秒到几秒才回来，这期间推送已经把手里的价格、标记价刷新过了：
    // 交易所时间比手里旧的那一组不覆盖（否则价格回跳一下、涨跌幅闪回旧值，直到下一帧推送再改回来）
    for (const t of tk) {
      const s = next.get(t.symbol); if (!s) continue
      const at = +t.closeTime || 0
      if (!(at < (s.pxAt ?? 0))) Object.assign(s, { price: +t.lastPrice, chg: +t.priceChange, pct: +t.priceChangePercent, open: +t.openPrice, hi: +t.highPrice, lo: +t.lowPrice, pxAt: at })
      if (!(at < (s.statAt ?? 0))) Object.assign(s, { vol: +t.quoteVolume, count: +t.count, statAt: at })
    }
    for (const p of pi) {
      const s = next.get(p.symbol); if (!s) continue
      const at = +(p.time ?? 0) || 0
      if (at < (s.markAt ?? 0)) continue
      Object.assign(s, { fr: p.lastFundingRate === '' ? null : +p.lastFundingRate, nextFunding: p.nextFundingTime || null, mark: +p.markPrice, index: +p.indexPrice, markAt: at })
    }
    S.symbols = next
    S.universeAt = Date.now()
    S.live = true
    S.limited = false
    S.error = ''
    savedAt = Date.now()
    setTimeout(() => saveUniverse(), 1500)   // 不和首屏抢这一拍
  } catch (e) {
    console.warn('[hkline] 币安合约接口不可达', e)
    S.live = false
    S.limited = isRateLimit(e)
    S.error = S.limited ? `请求太密，${Math.ceil(Math.max(coolingFor(REST), 1000) / 1000)} 秒后自动重试` : String((e as Error)?.message || e)
  }
  emit({ type: 'universe' })
  if (S.symbols.has(MACRO_SYMBOL)) void loadMacro()
  return S.symbols
}

/** 美元指数的品种信息与 24h 行情（自家服务器，两条线路同一台）。取不到就留着内置那一行，不报错 */
let macroAt = 0
export async function loadMacro(): Promise<void> {
  if (Date.now() - macroAt < 5000) return
  macroAt = Date.now()
  const s = S.symbols.get(MACRO_SYMBOL)
  if (!s) return
  const origin = apiOrigin()
  const [ins, tk] = await Promise.all([
    j<{ symbols?: { key?: string; displayName?: string; tickSize?: string; pricePrecision?: number }[] }>(`${origin}/v1/market/raw/instruments?source=macro`, 8000).catch(() => null),
    j<MacroTicker>(`${REST}/fapi/v1/ticker/24hr?symbol=${MACRO_SYMBOL}`, 8000).catch(() => null),
  ])
  const row = ins?.symbols?.find(x => x.key === 'macro/index/DXY')
  if (row) {
    if (row.displayName) s.cn = row.displayName
    if (row.tickSize) s.dec = decOfTick(row.tickSize)
  }
  if (tk && applyMacroTicker(s, tk, +(tk.closeTime ?? 0) || Date.now())) {
    s.lastTick = Date.now()
    emit({ type: 'ticker', symbol: MACRO_SYMBOL, dir: 0 })
  }
}

type Row = [number, string, string, string, string, string, number, string, ...unknown[]]
function parse(rows: Row[]): Bar[] {
  // 成交量用成交额（USDT），和手机端一致；r[10] 主动买入成交额、r[5] 成交量（币）给 CVD / VWAP / 成交量分布用
  return rows.map(r => ({ t: r[0], o: +r[1], h: +r[2], l: +r[3], c: +r[4], v: +r[7], tb: +(r[10] as string), bv: +r[5] }))
}

export interface KlineResult { bars: Bar[]; ok: boolean; error?: string }

/** 一页 K 线（最多 1500 根）；带 endTime 时是向左翻页，取严格早于它的那一页 */
/** background：后台一大批取的（板块迷你走势），只用限流预算的一截，见 limit.ts */
export async function klines(symbol: string, iv: string, endTime?: number, limit = 1500, withOI = true, background = false, alive?: () => boolean, priority?: RequestPriority,
  onWait?: (ms: number) => void): Promise<KlineResult> {
  try {
    const u = `${REST}/fapi/v1/klines?symbol=${symbol}&interval=${iv}&limit=${limit}${endTime ? `&endTime=${endTime - 1}` : ''}`
    const bars = parse(await j<Row[]>(u, 10000, background, alive, priority, onWait))
    if (withOI) void attachOI(symbol, iv, bars)
    return { bars, ok: true }
  } catch (e) {
    return { bars: [], ok: false, error: String((e as Error)?.message || e) }
  }
}

/** 非当前格首次取的根数：limit < 500 权重 2，1500 根是 10（见 limit.ts 的 K 线权重表）。十六格同时进来时
 *  15 个非当前格各省 8 点权重；往左翻历史照常由 loadMore 一页 1500 根补 */
export const SIDE_LIMIT = 499

/** 持仓量副图：币安只给最近 30 天的历史，周期只有 5 分钟到 1 天。更细的周期（1m / 3m）把 5 分钟那一桶的值铺到桶里每根，
 *  更粗的（1w / 1M）取那根里最后一个日点；对不齐的根留空。
 *  走着的那一桶币安也给点、值还在变，新开的一桶要等它的第一个点出来——所以装载取整段（500 个点）之后，
 *  露着副图的格子每分钟再拿最近两桶补一次尾巴（limit 只要几个点），线才跟着 K 线一路延长。
 *  alive：排队期间这一格不要了（换品种 / 周期 / 格子没了 / 持仓量副图被收起）就不发 */
const OI_PERIOD = new Set(['5m', '15m', '30m', '1h', '2h', '4h', '6h', '12h', '1d'])
/** 这个周期取持仓量用币安的哪个 period；秒级 / 自定义分钟没有 */
export function oiPeriod(iv: string): string | null {
  if (OI_PERIOD.has(iv)) return iv
  const ms = IV_MS[iv]
  if (!(ms > 0)) return null
  return ms < 300e3 ? '5m' : '1d'
}
/** 返回 false = 没取成（排队时被作废、网络 / 限流失败），调用方下次还该再取；不支持的周期 / 品种算取过了 */
export async function attachOI(symbol: string, iv: string, bars: Bar[], alive?: () => boolean, limit = 500): Promise<boolean> {
  const period = oiPeriod(iv)
  if (!period || !bars.length || isMacro(symbol)) return true
  const pms = IV_MS[period], ims = IV_MS[iv], last = bars[bars.length - 1]
  try {
    // 细周期：桶头 ≤ 最后一根的开盘时刻；粗周期：要到这根收线前的最后一个日点
    const endTime = ims <= pms ? last.t + 1 : Math.min(last.t + ims, Date.now())
    const rows = await j<{ timestamp: number; sumOpenInterestValue: string }[]>(`${REST}/futures/data/openInterestHist?symbol=${symbol}&period=${period}&limit=${limit}&endTime=${endTime}`, 8000, false, alive)
    if (!rows.length) return true
    let hit = 0
    if (ims <= pms) {
      const m = new Map(rows.map(r => [r.timestamp, +r.sumOpenInterestValue]))
      for (const b of bars) { const v = m.get(Math.floor(b.t / pms) * pms); if (v != null) { b.oi = v; hit++ } }
    } else {
      const pts = rows.map(r => [r.timestamp, +r.sumOpenInterestValue] as const).sort((a, b) => a[0] - b[0])
      for (let i = 0; i < bars.length; i++) {
        const b = bars[i], until = i + 1 < bars.length ? bars[i + 1].t : b.t + ims
        let v: number | undefined
        for (const [t, x] of pts) { if (t >= until) break; if (t >= b.t) v = x }
        if (v != null) { b.oi = v; hit++ }
      }
    }
    if (hit) emit({ type: 'oi', symbol, iv })
    return true
  } catch { return false /* 取不到持仓量就留空 */ }
}

export interface Detail {
  t: number
  oiValue?: number      // 持仓量（美元）
  oiChg?: number        // 持仓量 24h 变化（%）
  ls?: number           // 多空人数比
  top?: number          // 大户持仓比
  taker?: number        // 主动买卖比
}
const detailCache = new Map<string, Detail>()

/** 单只的未平仓量（原文，张数）。PC 详情块和自选宽列的持仓额都要它，冷启动时两边在同一秒各发一次同一个请求；
 *  没带 alive 的那次在途或取到不满 10 秒时大家共用。带 alive 的可能排队时被作废（Superseded），只给自己用 */
const oiShared = new Map<string, { t: number; p: Promise<string | undefined> }>()
export function fetchOpenInterest(symbol: string, alive?: () => boolean): Promise<string | undefined> {
  // 美元指数没有持仓量：不发请求（发了也只会在本地被 macroRewrite 拦下）
  if (isMacro(symbol)) return Promise.resolve(undefined)
  const hit = oiShared.get(symbol)
  if (hit && (hit.t === 0 || ago(hit.t) < 10e3)) return hit.p
  const p = j<{ openInterest?: string }>(`${REST}/fapi/v1/openInterest?symbol=${symbol}`, 8000, false, alive).then(r => r?.openInterest)
  if (alive) return p
  const e = { t: 0, p }
  oiShared.set(symbol, e)
  p.then(() => { e.t = Date.now() }, () => { if (oiShared.get(symbol) === e) oiShared.delete(symbol) })
  return p
}
export function detailOf(symbol: string): Detail | undefined { return detailCache.get(symbol) }

/** 一分钟最多取一次。alive：排在限流队列里时问一下还要不要（扫图划过去的那只不要了就不发、不记这一分钟） */
export async function fetchDetail(symbol: string, alive?: () => boolean): Promise<void> {
  if (isMacro(symbol)) return
  const prev = detailCache.get(symbol)
  if (prev && ago(prev.t) < 60e3) return
  const d: Detail = { ...(prev || {}), t: Date.now() }
  detailCache.set(symbol, d)
  let dropped = false
  const get = <T,>(path: string, q: string) => j<T>(`${REST}${path}?symbol=${symbol}${q ? '&' + q : ''}`, 8000, false, alive)
    .catch(e => { if (e instanceof Superseded) dropped = true; return null })
  const [oi, hist, ls, top, taker] = await Promise.all([
    fetchOpenInterest(symbol, alive).catch(e => { if (e instanceof Superseded) dropped = true; return null }),
    get<{ sumOpenInterestValue: string }[]>('/futures/data/openInterestHist', 'period=1h&limit=25'),
    get<{ longShortRatio: string }[]>('/futures/data/globalLongShortAccountRatio', 'period=5m&limit=1'),
    get<{ longShortRatio: string }[]>('/futures/data/topLongShortPositionRatio', 'period=5m&limit=1'),
    get<{ buySellRatio: string }[]>('/futures/data/takerlongshortRatio', 'period=5m&limit=1'),
  ])
  // 排队时作废了：这一分钟不算取过，回到这只时照常取
  if (dropped && detailCache.get(symbol) === d) { if (prev) detailCache.set(symbol, prev); else detailCache.delete(symbol) }
  if (dropped) return
  const px = S.symbols.get(symbol)?.price
  if (oi != null && px) d.oiValue = +oi * px
  if (hist && hist.length > 1) d.oiChg = (+hist[hist.length - 1].sumOpenInterestValue / +hist[0].sumOpenInterestValue - 1) * 100
  if (ls?.[0]) d.ls = +ls[0].longShortRatio
  if (top?.[0]) d.top = +top[0].longShortRatio
  if (taker?.[0]) d.taker = +taker[0].buySellRatio
  emit({ type: 'detail', symbol })
}

/**
 * 自家服务器上的历史接口（足迹图的分钟价位、秒级 K 线）：同源相对地址（本机开发经 vite 转发到线上），两条线路一样走。
 * 接口还没上线时回 404——和空回包一样当「没有历史」：ok 为真、body 为 null，不报错；
 * 只有网络断、超时、其余非 2xx 才算失败（ok 为假，调用方 30 秒内不再试）。base 给测试用（指到本机假服务器）。
 */
export async function serverHistory(path: string, ms = 12_000, base = ''): Promise<{ ok: boolean; body: unknown }> {
  if (typeof fetch === 'undefined') return { ok: false, body: null }
  const ctl = new AbortController(), t = setTimeout(() => ctl.abort(), ms)
  try {
    const r = await fetch(base + path, { signal: ctl.signal, referrerPolicy: 'no-referrer', cache: 'no-store' })
    if (r.status === 404 || r.status === 204) return { ok: true, body: null }
    if (!r.ok) return { ok: false, body: null }
    const text = await r.text()
    if (!text.trim()) return { ok: true, body: null }
    try { return { ok: true, body: JSON.parse(text) as unknown } } catch { return { ok: true, body: null } }
  } catch { return { ok: false, body: null } } finally { clearTimeout(t) }
}
