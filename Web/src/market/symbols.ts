/* Hkline Web · 品种表
 *
 * 品种全集来自币安 U 本位合约 exchangeInfo（只取 USDT 计价、正在交易的永续与 TradFi 永续），
 * 分类按交易所自己给的 underlyingType：
 *   COIN / INDEX → 加密；EQUITY 及各地股票 / PREMARKET → 美股；COMMODITY / FX → 大宗。
 * 另有一只不在币安的「美元指数」（DXY，macro/index，见 market/macro.ts），分类「指数」（idx），排在美股后面。
 * 中文名：大宗与美股用对照表，加密只给常见的几个，其余留空。
 *
 * 2026-10-08 起 S.symbols 装所有交易所的品种：键是身份键（market/identity.ts——币安裸代号、美元指数 DXY、
 * 别家 venue/market/SYMBOL），Sym.venue / Sym.quote 说它是哪一家、什么计价。别家的品种表由各家的行情面
 * （src/venues/<id>.ts market.instruments）给，按需懒拉（rest.ts loadVenue）。
 */
import SECTORS from '../data/sectors.json'
import { normalize, matchOne, Tier } from './searchText'
import { parseKey, wireSymbol } from './identity'

export type Kind = 'crypto' | 'us' | 'com' | 'idx'

export interface Sym {
  /** 身份键（币安裸代号、DXY、别家 venue/market/SYMBOL），S.symbols 的键 */
  symbol: string
  /** 哪一家：binance / okx / bybit / hyperliquid / coinbase / macro */
  venue: string
  /** 计价币：USDT / USDC / USD；美元指数是空串 */
  quote: string
  /** 交易所原生代号（OKX 的 BTC-USDT-SWAP、Hyperliquid 的 kPEPE、Coinbase 的 BTC-USD）；币安与键相同时不给 */
  raw?: string
  /** 图表头部的品种名（带交易所自己的倍数前缀，如 1000PEPE、kPEPE）；不给就按代号去掉计价币（headName） */
  title?: string
  base: string          // 去掉 1000 前缀后的代号，搜索与展示用
  code: string          // 展示用代号
  kind: Kind
  cn: string
  dec: number           // 价格小数位（由 tickSize 推）
  color: string         // 徽标底色
  price: number | null
  chg: number
  pct: number | null
  vol: number           // 24h 成交额（USDT）
  open?: number
  hi?: number
  lo?: number
  count?: number        // 24h 成交笔数
  fr: number | null     // 资金费率（小数）
  nextFunding: number | null
  mark?: number
  index?: number
  lastTick?: number
  /** 价格这一组（price / chg / pct / open / hi / lo）对应的交易所时间：WS 24h 行情的 C、逐笔的 T、REST 24h 的 closeTime。
   *  晚到的 REST 全市场表比它旧就不覆盖（rest.ts loadUniverse），和 iOS QuoteState 按时间/成交号拒旧帧同一条规矩 */
  pxAt?: number
  /** 24h 成交额 / 笔数对应的交易所时间（WS 24h 行情的 C、REST 24h 的 closeTime） */
  statAt?: number
  /** 标记价 / 指数价 / 资金费率对应的交易所时间（WS markPriceUpdate 的 E、REST premiumIndex 的 time） */
  markAt?: number
  supply?: number       // 总供应量（/v1/market/meta）
  oi?: number           // 持仓量（币；整表行情里带的那几家才有：Bybit、Hyperliquid）
  ut?: string           // 交易所给的 underlyingType 原文（COIN / EQUITY / HK_EQUITY / COMMODITY …），市场筛选用
  tags?: string[]       // underlyingSubType 小写去重（layer-1 / meme / ai …），板块筛选用
  onboard?: number      // 上线时间（毫秒），「新」字记号用
  /** 美元指数这类自家服务器给的品种（macro 交易所）：没有计价币、没有费率 / 持仓 / 盘口，成交量恒为 0 */
  macro?: boolean
  /** 休市（服务端 marketState = closed）：价格文字变灰，不加状态字段 */
  closed?: boolean
}

export interface SectorData {
  crypto: [string, string][]
  us: [string, string, string[]][]
  usNames: Record<string, string>
  members: Record<string, string[]>
}
export const SEC = SECTORS as unknown as SectorData

export const TABS: [Kind, string][] = [['crypto', '加密'], ['us', '美股'], ['idx', '指数'], ['com', '大宗']]

export const IV_LABEL: Record<string, string> = { '1m': '1分', '3m': '3分', '5m': '5分', '15m': '15分', '30m': '30分', '1h': '1小时', '2h': '2小时', '4h': '4小时', '6h': '6小时', '8h': '8小时', '12h': '12小时', '1d': '日线', '1w': '周线', '1M': '月线' }
export const IV_SHORT: Record<string, string> = { '1m': '1分', '3m': '3分', '5m': '5分', '15m': '15分', '30m': '30分', '1h': '1时', '2h': '2时', '4h': '4时', '6h': '6时', '8h': '8时', '12h': '12时', '1d': '日', '1w': '周', '1M': '月' }
export const INTERVALS = Object.keys(IV_LABEL)

const COMMODITY: Record<string, string> = { XAU: '黄金', XAG: '白银', XPT: '铂金', XPD: '钯金', COPPER: '铜', CL: 'WTI 原油', BZ: '布伦特原油', NATGAS: '天然气', EURUSD: '欧元兑美元', USDJPY: '美元兑日元', GBPUSD: '英镑兑美元' }
const US_EXTRA: Record<string, string> = { SPY: '标普 500 ETF', QQQ: '纳指 100 ETF', SOXL: '三倍做多半导体 ETF' }
const CRYPTO_CN: Record<string, string> = { BTC: '比特币', ETH: '以太坊', SOL: 'Solana', XRP: '瑞波币', BNB: '币安币', DOGE: '狗狗币', HYPE: 'Hyperliquid', ZEC: '大零币', LINK: 'Chainlink', SUI: 'Sui', NEAR: 'NEAR', QNT: 'Quant', HBAR: 'Hedera', ADA: '艾达币', TRX: '波场', AVAX: '雪崩', LTC: '莱特币', TON: 'Toncoin', DOT: '波卡', PEPE: '佩佩', ENA: 'Ethena', AAVE: 'Aave', UNI: 'Uniswap', BCH: '比特币现金', ETC: '以太经典', FIL: '文件币', APT: 'Aptos', ARB: 'Arbitrum', OP: 'Optimism', WLD: 'Worldcoin', TAO: 'Bittensor', ONDO: 'Ondo', XLM: '恒星币', XMR: '门罗币', PENGU: 'Pudgy Penguins', TRUMP: '特朗普币', FARTCOIN: 'Fartcoin', VIRTUAL: 'Virtuals', XAUT: 'Tether 黄金' }

// 出厂默认自选（2026-10-07 用户定的名单，访客与账号一样，和 iOS DefaultFavorites 同一份点名）。
// 电脑网页按资产类型分页签、同步编码也按类型重排，所以金银留在「大宗」页签的最前面；
// 手机网页（m/model/favorites.ts seedDefaults）照 iOS 把金银放进「加密」最上面。
export const DEFAULT_WATCH: Record<Kind, string[]> = {
  crypto: ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XRPUSDT', 'DOGEUSDT', 'ZECUSDT', 'HYPEUSDT', 'LINKUSDT', 'SUIUSDT', 'NEARUSDT', 'QNTUSDT', 'HBARUSDT'],
  us: ['NVDAUSDT', 'QQQUSDT', 'SOXLUSDT', 'SKHYUSDT', 'SKHYNIXUSDT', 'MUUSDT', 'SNDKUSDT', 'MRVLUSDT', 'ARMUSDT', 'SPCXUSDT', 'INTCUSDT', 'AVGOUSDT'],
  com: ['XAUUSDT', 'XAGUSDT', 'CLUSDT'],
  idx: [],   // 美元指数不进出厂默认自选
}

// 品种主色：图表对比线、迷你走势等要一个代表色的地方用；徽标本身画法见 ui/common.ts badge()（和手机同一套记号）
const BADGE: Record<string, string> = { BTC: '#F7931A', ETH: '#627EEA', SOL: '#9945FF', XRP: '#23292F', HYPE: '#50D2C1', DOGE: '#C2A633', ZEC: '#E5A93D', LINK: '#2A5ADA', SUI: '#4DA2FF', NEAR: '#1E1E1E', QNT: '#585E63', HBAR: '#222222', BNB: '#F0B90B', NVDA: '#76B900', TSLA: '#CC0000', SNDK: '#E4002B', MU: '#0073CF', AMD: '#1B1B1B', TSM: '#C8102E', COIN: '#0052FF', MSTR: '#D9232E', QQQ: '#2E6FD8', SOXL: '#5B3FA8', SKHY: '#EA002C', SKHYNIX: '#EA002C', MRVL: '#C8102E', ARM: '#0091BD', INTC: '#0071C5', AVGO: '#CC092F', XAU: '#C9A227', XAG: '#9EA7B3', CL: '#3D3D3D' }
export function badgeColor(base: string): string {
  if (BADGE[base]) return BADGE[base]
  let h = 0
  for (const ch of base) h = (h * 31 + ch.charCodeAt(0)) % 360
  return `hsl(${h} 55% 45%)`
}

/** 代号的底：去掉计价币与 1000 / 1M 前缀（BTCUSDT → BTC、1000PEPEUSDT → PEPE、okx/usd_m/BTCUSDT → BTC、coinbase/spot/BTC-USD → BTC） */
export function baseOf(symbol: string, baseAsset?: string): string {
  const b = baseAsset || wireSymbol(symbol).replace(/-USD[CT]?$|USDT$|USDC$/, '')
  return b.replace(/^1000+(?=[A-Z])/, '').replace(/^1M(?=[A-Z])/, '')
}
/** 图表头部的品种名：基础币（带交易所自己的倍数前缀：1000PEPE、kPEPE），不带计价币 */
export function headName(s: Pick<Sym, 'symbol'> & Partial<Pick<Sym, 'title' | 'macro' | 'code'>>): string {
  if (s.title) return s.title
  if (s.macro) return s.code || s.symbol
  return wireSymbol(s.symbol).replace(/-USD[CT]?$|USDT$|USDC$/, '') || s.symbol
}

export function kindOfUnderlying(u: string | undefined, base: string): Kind {
  if (u === 'COMMODITY' || u === 'FX') return 'com'
  if (u && (/EQUITY$/.test(u) || u === 'PREMARKET')) return 'us'
  if (u) return 'crypto'
  // 交易所没给类型时的兜底：按对照表猜
  if (COMMODITY[base]) return 'com'
  if (US_EXTRA[base] || SEC.usNames[base]) return 'us'
  return 'crypto'
}

export function cnOf(base: string, kind: Kind): string {
  if (kind === 'idx') return base === 'DXY' ? '美元指数' : ''
  if (kind === 'com') return COMMODITY[base] || ''
  if (kind === 'us') return SEC.usNames[base] || US_EXTRA[base] || ''
  return CRYPTO_CN[base] || ''
}

/** "0.01000" → 2；"1" → 0；"0.0000001" → 7 */
export function decOfTick(tick: string | number): number {
  const s = typeof tick === 'number' ? tick.toFixed(10) : tick
  const i = s.indexOf('.')
  if (i < 0) return 0
  const frac = s.slice(i + 1).replace(/0+$/, '')
  return Math.min(8, frac.length)
}

export function kindName(s: (Pick<Sym, 'kind'> & Partial<Pick<Sym, 'symbol'>>) | null | undefined): string {
  if (s?.symbol && parseKey(s.symbol).market === 'spot') return '现货'
  return s?.kind === 'us' ? '美股永续' : s?.kind === 'com' ? '大宗永续' : s?.kind === 'idx' ? '指数' : '永续'
}

/** 品种所在板块：加密按成员表、美股按板块代号表 */
export function sectorsOf(s: Sym): { id: string; cn: string }[] {
  if (s.kind === 'us') return SEC.us.filter(x => x[2].includes(s.base)).map(x => ({ id: 'u:' + x[0], cn: x[1] }))
  if (s.kind !== 'crypto') return []
  // 成员表按合约名的底（保留 1000 前缀，如 1000BONK），s.base 已去掉前缀，两个都查
  return (SEC.members[wireSymbol(s.symbol).replace(/USDT$|USDC$/, '')] || SEC.members[s.base] || []).map(id => SEC.crypto.find(x => x[0] === id)).filter((x): x is [string, string] => !!x).map(x => ({ id: 'c:' + x[0], cn: x[1] }))
}

const HAN = /[㐀-䶿一-鿿]/
/** 搜索打分（越大越靠前，0 = 不命中）：和手机网页 / iOS 同一套归一与分档（market/searchText）——
 *  查询先全角折半角、剥分隔符（BTC/USDT、btc usdt、ＢＴＣ 都认），中文常用叫法与全拼 / 首字母（大饼、longxia、hj）也认；
 *  电脑这边多两条：去掉 1000 前缀的代号（PEPE）按代号算，品种表里的中文名（cn）按别名算 */
export function matchScore(s: Pick<Sym, 'symbol' | 'code' | 'cn'>, q: string): number {
  const Q = normalize(q)
  if (!Q) return 1
  const w = wireSymbol(s.symbol)
  let tier: number | null = matchOne(w, w.replace(/-USD[CT]?$|USDT$|USDC$/, ''), Q)?.tier ?? null
  const better = (t: number) => { if (tier == null || t < tier) tier = t }
  const code = normalize(s.code)
  if (code === Q) better(Tier.exact)
  else if (code.startsWith(Q)) better(Tier.basePrefix)
  else if (code.includes(Q)) better(Tier.baseContains)
  // 中文名只认带汉字的查询：品种表里有的「中文名」其实是英文（HYPE 的 Hyperliquid、SOL 的 Solana），
  // 拿英文查询去包含它，打一个「E」HYPE 就排到所有 E 开头的前面（2026-10-08 搜索交叉测试；手机 / iOS 的中文名也只认汉字）
  const cn = s.cn && HAN.test(Q) ? normalize(s.cn) : ''
  if (cn) {
    if (cn === Q) better(Tier.exact)
    else if (cn.startsWith(Q)) better(Tier.cnPrefix)
    else if (cn.includes(Q)) better(Tier.cnContains)
  }
  return tier == null ? 0 : 7 - tier
}

/** 搜索排序：先按匹配档，同档按 24h 成交额降序；空查询时自选在前 */
export function rankSearch<T extends Pick<Sym, 'symbol' | 'code' | 'cn' | 'vol'>>(list: T[], q: string, watched: (k: string) => boolean = () => false, limit = 80): T[] {
  const blank = !normalize(q)
  const scored = list.map(s => ({ s, m: matchScore(s, q) })).filter(x => x.m > 0)
  scored.sort((a, b) => (b.m - a.m) || (blank ? (+watched(b.s.symbol) - +watched(a.s.symbol)) : 0) || ((b.s.vol || 0) - (a.s.vol || 0)))
  return scored.slice(0, limit).map(x => x.s)
}

// ------------------------------------------------------------ 搜索按交易所分组
/** 一组搜索结果：一家一组 */
export interface SearchGroup<T> { venue: string; items: T[]; best: number }

/**
 * 搜索结果按交易所分区（像 TradingView / AICoin：同一个币在不同交易所是不同品种）：
 *   一家一组；组内按现有排序（匹配档 → 空查询时自选在前 → 没有价的沉底 → 24h 成交额）；
 *   组序先按组内最好的匹配档、同档按 order（注册表顺序，美元指数这类不在注册表里的排最后）；每组各自封顶 perGroup。
 * venueOf：这一行属于哪一组（默认 Sym.venue）。
 */
export function groupSearch<T extends Pick<Sym, 'symbol' | 'code' | 'cn' | 'vol'> & { venue?: string; price?: number | null }>(list: T[], q: string, order: readonly string[],
  watched: (k: string) => boolean = () => false, perGroup = 40): SearchGroup<T>[] {
  const blank = !normalize(q)
  const by = new Map<string, { s: T; m: number }[]>()
  for (const s of list) {
    const m = matchScore(s, q)
    if (m <= 0) continue
    const v = s.venue ?? parseKey(s.symbol).venue
    let g = by.get(v); if (!g) by.set(v, g = [])
    g.push({ s, m })
  }
  const rank = (v: string): number => { const i = order.indexOf(v); return i < 0 ? order.length : i }
  const out: SearchGroup<T>[] = []
  for (const [venue, xs] of by) {
    // 同档：空查询时自选在前；没有价的（停牌、行情没到）沉底（同手机 / iOS）；再按成交额
    xs.sort((a, b) => (b.m - a.m) || (blank ? (+watched(b.s.symbol) - +watched(a.s.symbol)) : 0) || (+(a.s.price === null) - +(b.s.price === null)) || ((b.s.vol || 0) - (a.s.vol || 0)))
    out.push({ venue, items: xs.slice(0, perGroup).map(x => x.s), best: xs[0].m })
  }
  return out.sort((a, b) => (b.best - a.best) || (rank(a.venue) - rank(b.venue)))
}
