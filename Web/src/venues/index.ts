/* Hkline Web · 多交易所 · 注册表
 *
 * 订单流（src/orderflow/**）只从这里拿交易所的一切：键、显示名、配色、通道号、序号模型、
 * 连接规格（直连 / 中继 / 网关）、订阅与单本重订、解帧、REST 快照、K 线、参考簿、保底簿。
 * 加一家交易所 = 在这里登记一个 VenueAdapter，订单流不用改（tests/venues-isolation.test.ts 守着）。
 * 顺序就是读数、热力通道、分项的顺序：币安 0 · OKX 1 · Coinbase 2 · Bybit 3 · Hyperliquid 4。
 */
import type { Notional, Product, Venue } from '../orderflow/types'
import { binance } from './binance'
import { okx } from './okx'
import { coinbase } from './coinbase'
import { bybit } from './bybit'
import { hyperliquid } from './hyperliquid'
import type { ConnContext, ConnSpec, DepthBook, VenueAdapter } from './common'

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
