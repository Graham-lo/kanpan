/* Hkline Web · 多交易所 · 各家适配器共用的件
 *
 * 一家交易所 = 一个文件（src/venues/<id>.ts）：地址表、唯一的限流器（market/limit.ts registerGate）、一套报文解码；
 * 行情（品种表 / K 线 / 24h / 推送，VenueAdapter.market）与主力订单流（盘口 / 逐笔，VenueAdapter 其余字段）
 * 只是它的两个使用面，不许各写一份域名或解码。
 *
 * 订单流（src/orderflow/**）只认这里导出的通用描述：一本簿（DepthBook）、一条连接的规格（ConnSpec）、
 * REST 快照与 30 分钟 K 线的请求。价与量在解码时就乘上 priceFactor / quantityFactor 换成图上的单位
 * （1000PEPE / kPEPE 一格是 1000 个币）。
 * 行情层（src/market/**）只认 VenueMarket：品种表、整表行情、K 线、费率 / 持仓量、推送（MarketWire）、周期表。
 */
import type { BookLevel, BookSide, DepthMessage, Product, SequenceModel, Venue } from '../orderflow/types'
import type { Bar } from '../chart/calc'
import type { Sym } from '../market/symbols'

export type Route = 'direct' | 'gateway'

export interface DepthBook {
  id: string
  venue: Venue
  /** 本家价格 × priceFactor = 图上的价格 */
  priceFactor: number
  expiryMs: number | null
  tick: number | null
}
export const quantityFactor = (b: DepthBook): number => (b.venue.notional.kind === 'linear' ? 1 / b.priceFactor : 1)

/** 解出来的一条：[簿 id, 消息] */
export type Out = [string, DepthMessage]

export const n = (v: unknown): number => (typeof v === 'number' ? v : typeof v === 'string' ? parseFloat(v) : NaN)

/** [[价, 量], …] → 图上单位的档位 */
export function levels(raw: unknown, b: DepthBook): BookLevel[] {
  if (!Array.isArray(raw)) return []
  const pf = b.priceFactor, qf = quantityFactor(b)
  const out: BookLevel[] = []
  for (const r of raw as unknown[][]) {
    const p = n(r?.[0]), q = n(r?.[1])
    if (Number.isFinite(p) && Number.isFinite(q)) out.push({ price: p * pf, quantity: q * qf })
  }
  return out
}

export const trade = (b: DepthBook, price: number, qty: number, hit: BookSide, t: number): DepthMessage =>
  ({ type: 'trade', trade: { price: price * b.priceFactor, quantity: qty * quantityFactor(b), hitSide: hit, timeMs: t } })

export const chunk = <T>(a: T[], size: number): T[][] => { const o: T[][] = []; for (let i = 0; i < a.length; i += size) o.push(a.slice(i, i + size)); return o }

export const parseJSON = (text: string): Record<string, unknown> | null => {
  try { const v = JSON.parse(text) as unknown; return v && typeof v === 'object' ? v as Record<string, unknown> : null } catch { return null }
}

/** 一条连接：依次尝试 urls（还没打开就断了换下一个）；开了发 subscribe()，每帧过 decode。 */
export interface ConnSpec {
  key: string
  urls: string[]
  /** 这条连接负责的簿（开 / 断时通知它们）；只收成交的连接是空 */
  books: DepthBook[]
  subscribe: () => string[]
  decode: (text: string) => Out[]
  ping?: { text: string; everyMs: number }
  /** 多久没有任何帧当它死了重连（默认 30 秒） */
  silenceMs?: number
  /** 一本簿断档时只退订重订它（同连接其它簿不动）；没有就整条重连 */
  resubscribe?: (b: DepthBook) => string[]
}

export interface ConnContext {
  route: Route
  /** 网关的 WebSocket 根：wss://主机 */
  gw: string
}

/** 30 分钟 K 线一根（价已是图上单位；quote 是美元计价额，buy 是主动买计价额，K 线不带就是 null） */
export interface Kline { t: number; h: number; l: number; c: number; quote: number; buy: number | null }
export interface KlineReq { url: string; parse: (body: unknown) => Kline[] }

export interface SnapshotReq { url: string; parse: (json: unknown, b: DepthBook) => DepthMessage | null }

/** 保底簿（服务端品种表查不到时）：priceScale 是这本簿一单位是几个币（和品种表同一口径，priceFactor = 图的倍数 ÷ 它） */
export interface FallbackBook { product: Product; instrument: string; priceScale: number }

/** 一家交易所在注册表里登记的全部东西 */
export interface VenueAdapter {
  /** 稳定键（簿 id、品种表 exchange 字段） */
  key: string
  /** 显示名（读数分项、历史行的 exchange） */
  label: string
  /** 读数配色（CSS 变量） */
  color: string
  sequenceModel: (product: Product) => SequenceModel
  /** 快照在流里（不用另拉 REST） */
  snapshotInBand: boolean
  /** 一条连接最多装几本簿 */
  maxBooksPerConn: number
  /** 这家的簿该怎么分连接 */
  connections: (books: DepthBook[], ctx: ConnContext) => ConnSpec[]
  /** REST 快照（不在流里的才有） */
  snapshot?: (b: DepthBook, route: Route) => SnapshotReq
  /** 30 分钟 K 线（侧栏「24 小时成交」）；只给现货与 U 本位永续 */
  klines30m?: (b: DepthBook, now: number, slots: number) => KlineReq | null
  /** K 线带主动买额，能拆买卖 */
  takerSplit?: boolean
  /** 参考簿所在的家：图上那只合约自己（推步长的前一日收盘、中间价都以它为准） */
  primary?: { referenceCloseUrl: (symbol: string, day: number) => string; parseReferenceClose: (body: unknown, day: number) => number }
  /** 品种表查不到时的保底簿 */
  fallback?: (symbol: string, base: string, chartScale: number) => FallbackBook[]
  /** 行情面：品种表、K 线、24h、费率 / 持仓量、推送。见 VenueMarket */
  market: VenueMarket
}

// ============================================================ 行情面（2026-10-08）

/** 取数时的附带要求（都可以不给）：alive 排队时问还要不要；background 只用限流器的一截；route 默认用户当前选的线路 */
export interface FetchOpts {
  alive?: () => boolean
  background?: boolean
  priority?: RequestPriority
  onWait?: (ms: number) => void
  /** 超时（毫秒） */
  ms?: number
  route?: Route
}

/** 一只品种的 24h 行情 / 标记价 / 费率 / 持仓量：各家报文解出来的中立形状，没有的字段不给 */
export interface Quote {
  /** 网页键（okx/usd_m/BTCUSDT……） */
  key: string
  price?: number
  open?: number
  hi?: number
  lo?: number
  /** 24h 涨跌幅（%） */
  pct?: number
  chg?: number
  /** 24h 成交额（计价币） */
  vol?: number
  count?: number
  mark?: number
  index?: number
  /** 资金费率（小数）；null = 这家明说没有 */
  fr?: number | null
  nextFunding?: number | null
  /** 持仓量（币） */
  oi?: number
  /** 交易所时间（毫秒）；报文里没有就是本机收到的时刻 */
  at: number
}

/** 推送解出来的统一事件 */
export type Push =
  | { type: 'kline'; key: string; iv: string; bar: Bar }
  | { type: 'quote'; quote: Quote }
  /** 逐笔：sell = 主动卖（买方是挂单方） */
  | { type: 'trade'; key: string; price: number; qty: number; t: number; sell: boolean }

/** 订阅的一路：哪只、什么。kline 的 iv 是网页周期（原生档；聚合档由行情层拿原生档并） */
export interface StreamSub { key: string; kind: 'kline' | 'ticker' | 'mark' | 'trade'; iv?: string }

/** 一家的推送协议：按品种集合订阅，一条连接多订阅（OKX 的 K 线在 business 端点，另一条）。网关档只连中继 */
export interface MarketWire {
  /** 这一路走哪条连接；这家不推这一路回 null（不订，行情层也不等它） */
  endpoint(sub: StreamSub): string | null
  /** 这条连接拨哪个地址（gw = 网关的 wss 根，如 wss://主机） */
  url(endpoint: string, route: Route, gw: string): string
  /** 这一路在上行协议里是哪几个 topic：几路共用同一个 topic 时（Bybit tickers 同时给行情与标记价）只订一次 */
  topics(sub: StreamSub): string[]
  /** 订 / 退这些 topic 的上行帧（自己按交易所一条消息的上限拆条） */
  frames(endpoint: string, topics: string[], on: boolean): string[]
  /** 新开一条连接时建一个解码器（Bybit tickers 的增量要按连接留一份快照合并） */
  decoder(endpoint: string): (text: string) => Push[]
  ping?: { text: string; everyMs: number }
  /** 连上就发的帧（Coinbase 要订 heartbeats，不然空闲连接会被对面收掉） */
  hello?: string[]
  /** 多久一帧都没有当断线（默认 30 秒） */
  silenceMs?: number
  /** 一条连接最多订几个 topic（网关中继的上限） */
  maxTopics: number
  /** 上行控制帧（订 / 退 / hello）两条之间至少隔多久（默认 250 ms；Coinbase 每 IP ≤ 8 条 / 秒、HL 每分钟 ≤ 2000 条） */
  controlGapMs?: number
  /** 一条连接每小时最多几条订 / 退帧（OKX 480） */
  controlPerHour?: number
  /** 这一家新开两条连接之间至少隔多久（OKX 按 IP 3 次 / 秒） */
  openGapMs?: number
  /** 没有 K 线推送：K 线由行情层拿逐笔并出来（先用 REST 取一根垫底） */
  klineFromTrades?: boolean
}

/** 一页 K 线的范围：end 不含（开盘时间严格早于它），start 含 */
export interface KlineQuery { limit: number; end?: number; start?: number }

/** 周期表：native 网页周期 → 交易所写法；derived 网页周期 → 从哪个原生网页周期并（n 根一组，周线按周一、月线按自然月） */
export interface Intervals { native: Record<string, string>; derived: Record<string, string> }

/** 一家交易所的行情面。上层（market/**、pages/**）不写 if venue ===，能力看字段有没有 */
export interface VenueMarket {
  /** 列表、图表角标里的缩写：币安 / OKX / Bybit / HL / CB */
  shortName: string
  /** 搜索组头里的全名 */
  displayName: string
  /** usd_m（U 本位永续，Hyperliquid 的 USDC 保证金也记 usd_m）/ spot */
  market: string
  /** 计价币 */
  quote: string
  /** 键代号的形状（服务端 sync_validation identity 同一规则）：自选 / 提醒 / 画线能不能上云 */
  symbolOk(symbol: string): boolean
  /** 品种表（Sym 已带 venue / quote / raw；价格等由 tickers 填） */
  instruments(route?: Route): Promise<Sym[]>
  /** 整表 24h 行情（一次请求） */
  tickers(route?: Route): Promise<Quote[]>
  /** 单只 24h 行情（没有就用整表） */
  ticker?(key: string, opts?: FetchOpts): Promise<Quote | null>
  /** 一页原生周期的 K 线（升序）；聚合周期由注册表 marketKlines 拿原生档并 */
  klines(key: string, iv: string, q: KlineQuery, opts?: FetchOpts): Promise<Bar[]>
  /** 一次最多给几根（翻页按它算） */
  maxKlines: number
  /** 资金费率（整表行情里没有的那几家才给） */
  funding?(key: string, opts?: FetchOpts): Promise<{ fr: number | null; nextFunding: number | null } | null>
  /** 持仓量（币） */
  openInterest?(key: string, opts?: FetchOpts): Promise<number | null>
  /** 推送；币安走 market/stream.ts 自己的连接池（组合流、按路数分池、网关 stream_hub），这里不给 */
  stream?: MarketWire
  intervals: Intervals
}

/** 解码共用：字符串 / 数 → 有限数，否则 undefined */
export const num = (v: unknown): number | undefined => { const x = n(v); return Number.isFinite(x) ? x : undefined }
/** 去掉 undefined 的字段（Quote 里没有的不给） */
export function compact<T extends object>(o: T): T {
  for (const k of Object.keys(o) as (keyof T)[]) if (o[k] === undefined) delete o[k]
  return o
}
