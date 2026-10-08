/* Hkline Web · 多交易所 · 注册表（行情 + 订单流一张表）
 *
 * 一家交易所 = src/venues/<id>.ts 里一个 VenueAdapter：地址表、唯一的限流器、一套报文解码，
 * 订单流（盘口 / 逐笔）与行情（VenueAdapter.market：品种表 / 整表行情 / K 线 / 费率 / 持仓量 / 推送 / 周期表）是它的两个使用面。
 * 加一家 = 写它自己的文件 + 在这里登记一行；订单流（tests/venues-isolation.test.ts 守着）与行情层（market/**）都不用改。
 *
 * 订单流（src/orderflow/**）只从这里拿交易所的一切：键、显示名、配色、通道号、序号模型、
 * 连接规格（直连 / 中继 / 网关）、订阅与单本重订、解帧、REST 快照、K 线、参考簿、保底簿。
 * 顺序就是读数、热力通道、分项的顺序：币安 0 · OKX 1 · Coinbase 2 · Bybit 3 · Hyperliquid 4；
 * 搜索结果的交易所分组同档时也按这个顺序。
 *
 * 行情层用的（给电脑版与手机网页版，API 稳定）：
 *   marketOf(sym)        这只品种那一家的行情面（美元指数 / 不认识的回 undefined）
 *   venueLabel(sym)      列表 / 角标里的缩写：币安 / OKX / Bybit / HL / CB；美元指数回 ''
 *   venueName(venue)     搜索组头的全名
 *   marketKlines(...)    一页 K 线：原生档直接要，没有的周期拿原生档并（venues/bars.ts）
 *   symbolOk(sym)        这只的键能不能上云（各家的代号形状）
 *   MARKET_VENUES        有行情面的几家（注册表顺序），loadVenue / 搜索分组按它走
 */
import type { Notional, Product, Venue } from '../orderflow/types'
import { binance } from './binance'
import { okx } from './okx'
import { coinbase } from './coinbase'
import { bybit } from './bybit'
import { hyperliquid } from './hyperliquid'
import type { ConnContext, ConnSpec, DepthBook, FetchOpts, KlineQuery, VenueAdapter, VenueMarket } from './common'
import type { Bar } from '../chart/calc'
import { parseKey } from '../market/identity'
import { aggregateBars, bucketOf, ratioOf } from './bars'

export * from './common'

export const VENUE_LIST: readonly VenueAdapter[] = [binance, okx, coinbase, bybit, hyperliquid]
const BY_KEY = new Map(VENUE_LIST.map(v => [v.key, v]))

export const venueAdapter = (key: string): VenueAdapter | undefined => BY_KEY.get(key)
export const isKnownExchange = (key: string): boolean => BY_KEY.has(key)

/** 交易所在热力 / 成交分项里的通道号（stride = EXCHANGE_COUNT） */
export const EXCHANGE_COUNT = VENUE_LIST.length
export const EXCHANGE_CH: Readonly<Record<string, number>> = Object.fromEntries(VENUE_LIST.map((v, i) => [v.key, i]))
export const EXCHANGE_NAMES: readonly string[] = VENUE_LIST.map(v => v.label)
export const EXCHANGE_COLORS: readonly string[] = VENUE_LIST.map(v => v.color)
/** 键或显示名 → 通道号（历史行里的 exchange 是显示名） */
export function exchangeIndex(keyOrLabel: string): number {
  const i = EXCHANGE_CH[keyOrLabel]
  return i ?? VENUE_LIST.findIndex(v => v.label === keyOrLabel)
}
/** 键 → 显示名；本来就是显示名或不认识的原样回 */
export const exName = (e: string): string => BY_KEY.get(e)?.label ?? e

/** 参考簿所在的家（图上那只合约自己：推步长的前一日收盘、中间价以它为准） */
export const PRIMARY: VenueAdapter = VENUE_LIST.find(v => v.primary) ?? VENUE_LIST[0]
export const isPrimary = (exchange: string): boolean => exchange === PRIMARY.key

/** 爆仓（服务端 /liq 行里的「哪家」下标）：0 币安 / 1 OKX / 2 Bybit */
export const LIQ_EX = [binance.label, okx.label, bybit.label] as const

export function makeVenue(exchange: string, product: Product, instrument: string, notional: Notional): Venue {
  const a = BY_KEY.get(exchange)
  return {
    exchange, label: a?.label ?? exchange, product, instrument, notional,
    sequenceModel: a ? a.sequenceModel(product) : 'strictIncrementing',
    snapshotInBand: a?.snapshotInBand ?? true,
  }
}

/** 按注册表把簿分到各家，各家自己出连接规格 */
export function connectionSpecs(books: DepthBook[], ctx: ConnContext): ConnSpec[] {
  const out: ConnSpec[] = []
  for (const a of VENUE_LIST) {
    const mine = books.filter(b => b.venue.exchange === a.key)
    if (mine.length) out.push(...a.connections(mine, ctx))
  }
  return out
}

/** 品种表查不到时的保底簿（各家登记的，按注册表顺序） */
export function fallbackBooks(symbol: string, base: string, chartScale: number): DepthBook[] {
  const out: DepthBook[] = []
  for (const a of VENUE_LIST) for (const f of a.fallback?.(symbol, base, chartScale) ?? []) {
    const venue = makeVenue(a.key, f.product, f.instrument, { kind: 'linear', multiplier: 1 })
    out.push({ id: `${a.key}:${f.product}:${f.instrument}`, venue, priceFactor: chartScale / f.priceScale, expiryMs: null, tick: null })
  }
  return out
}

/** 参考中间价的优先次序：注册表顺序，同一家永续在前、现货在后 */
export function midRank(exchange: string, product: string): number {
  const i = EXCHANGE_CH[exchange]
  if (i == null) return 1e6
  return i * 2 + (product === 'usdtPerp' ? 0 : product === 'spot' ? 1 : 1e3)
}

// ============================================================ 行情面

/** 有行情面的几家（注册表顺序；币安在最前） */
/** 行情交易所的顺序（搜索分组同档时的先后、自选分类条的先后），和 iOS `VenueRegistry.all` 一致：
 *  币安 · OKX · Bybit · Hyperliquid · Coinbase。订单流的合并顺序是 `VENUE_LIST`（服务端读数 / 热力通道的下标），两者不是一回事。 */
export const MARKET_VENUES: readonly VenueAdapter[] = [binance, okx, bybit, hyperliquid, coinbase].filter(v => !!v.market)

/** 这只品种那一家的行情面：按身份键的 venue 找，且 market 段要对得上（coinbase/usd_m/… 这种不存在的组合回 undefined）；
 *  美元指数（macro）不在注册表里，回 undefined */
export function marketOf(sym: string): VenueMarket | undefined {
  const k = parseKey(sym)
  const m = BY_KEY.get(k.venue)?.market
  return m && m.market === k.market ? m : undefined
}
/** 那一家的键（venue 字段） */
export const venueKeyOf = (sym: string): string => parseKey(sym).venue
/** 列表行 / 图表角标里的缩写：币安 / OKX / Bybit / HL / CB；美元指数与不认识的回 '' */
export const venueLabel = (sym: string): string => marketOf(sym)?.shortName ?? ''
/** 搜索组头里的全名（按 venue 键） */
export const venueName = (venue: string): string => BY_KEY.get(venue)?.market.displayName ?? venue
/** 这只的键形状过不过那一家的规矩（服务端 sync_validation identity 同一规则） */
export function symbolOk(sym: string): boolean {
  const k = parseKey(sym), m = marketOf(sym)
  return !!m && m.symbolOk(k.symbol)
}

/** 这一家这个周期怎么来：native 原生、derived 从哪个原生档并、null 没有 */
export function intervalPlan(m: VenueMarket, iv: string): { native: true } | { base: string } | null {
  if (m.intervals.native[iv]) return { native: true }
  const base = m.intervals.derived[iv]
  return base && m.intervals.native[base] ? { base } : null
}

/**
 * 一页 K 线（升序），注册表里唯一的入口：原生档直接要那一家；没有的周期拿原生档并（OKX / Bybit 的 8 时 ← 4 时、
 * Hyperliquid 的 6 时 ← 2 时、Coinbase 的 3 分 / 8 时 / 12 时 / 周 / 月）。并出来的：往前翻的那页第一格要是从半截开始的
 * 就丢掉（下一页会补全）。这家没有这个周期回空数组。
 */
export async function marketKlines(sym: string, iv: string, q: KlineQuery, opts?: FetchOpts): Promise<Bar[]> {
  const m = marketOf(sym)
  if (!m) throw new Error(`没有这家交易所的行情：${sym}`)
  const plan = intervalPlan(m, iv)
  if (!plan) return []
  if ('native' in plan) return m.klines(sym, iv, q, opts)
  const per = ratioOf(iv, plan.base)
  const raw = await m.klines(sym, plan.base, { ...q, limit: Math.min(m.maxKlines, Math.max(per, q.limit * per)) }, opts)
  let out = aggregateBars(raw, iv)
  if (out.length > 1 && raw.length && raw[0].t !== bucketOf(raw[0].t, iv)) out = out.slice(1)
  return out
}
