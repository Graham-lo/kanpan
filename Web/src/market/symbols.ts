/* Hkline Web · 品种表
 *
 * 品种全集来自币安 U 本位合约 exchangeInfo（只取 USDT 计价、正在交易的永续与 TradFi 永续），
 * 分类按交易所自己给的 underlyingType：
 *   COIN / INDEX → 加密；EQUITY 及各地股票 / PREMARKET → 美股；COMMODITY / FX → 大宗。
 * 另有一只不在币安的「美元指数」（DXY，macro/index，见 market/macro.ts），分类「指数」（idx），排在美股后面。
 * 中文名：大宗与美股用对照表，加密只给常见的几个，其余留空。
 */
import SECTORS from '../data/sectors.json'
import { normalize, matchOne, Tier } from './searchText'

export type Kind = 'crypto' | 'us' | 'com' | 'idx'

export interface Sym {
  symbol: string
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
const US_EXTRA: Record<string, string> = { SPY: '标普 500 ETF', QQQ: '纳指 100 ETF' }
const CRYPTO_CN: Record<string, string> = { BTC: '比特币', ETH: '以太坊', SOL: 'Solana', XRP: '瑞波币', BNB: '币安币', DOGE: '狗狗币', HYPE: 'Hyperliquid', ZEC: '大零币', LINK: 'Chainlink', SUI: 'Sui', NEAR: 'NEAR', QNT: 'Quant', HBAR: 'Hedera', ADA: '艾达币', TRX: '波场', AVAX: '雪崩', LTC: '莱特币', TON: 'Toncoin', DOT: '波卡', PEPE: '佩佩', ENA: 'Ethena', AAVE: 'Aave', UNI: 'Uniswap', BCH: '比特币现金', ETC: '以太经典', FIL: '文件币', APT: 'Aptos', ARB: 'Arbitrum', OP: 'Optimism', WLD: 'Worldcoin', TAO: 'Bittensor', ONDO: 'Ondo', XLM: '恒星币', XMR: '门罗币', PENGU: 'Pudgy Penguins', TRUMP: '特朗普币', FARTCOIN: 'Fartcoin', VIRTUAL: 'Virtuals', XAUT: 'Tether 黄金' }

export const DEFAULT_WATCH: Record<Kind, string[]> = {
  crypto: ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XRPUSDT', 'HYPEUSDT', 'DOGEUSDT', 'ZECUSDT', 'LINKUSDT', 'SUIUSDT', 'NEARUSDT', 'QNTUSDT', 'HBARUSDT'],
  us: ['NVDAUSDT', 'TSLAUSDT', 'SNDKUSDT', 'MUUSDT', 'AMDUSDT', 'TSMUSDT', 'COINUSDT', 'MSTRUSDT'],
  com: ['XAUUSDT', 'XAGUSDT', 'CLUSDT'],
  idx: [],   // 美元指数不进出厂默认自选
}

// 徽标：网页版用「一只品种一个颜色 + 首字母」的圆片，这是网页版自己的定稿画法（手机端的矢量记号不搬过来）
const BADGE: Record<string, string> = { BTC: '#F7931A', ETH: '#627EEA', SOL: '#9945FF', XRP: '#23292F', HYPE: '#50D2C1', DOGE: '#C2A633', ZEC: '#E5A93D', LINK: '#2A5ADA', SUI: '#4DA2FF', NEAR: '#1E1E1E', QNT: '#585E63', HBAR: '#222222', BNB: '#F0B90B', NVDA: '#76B900', TSLA: '#CC0000', SNDK: '#E4002B', MU: '#0073CF', AMD: '#1B1B1B', TSM: '#C8102E', COIN: '#0052FF', MSTR: '#D9232E', XAU: '#C9A227', XAG: '#9EA7B3', CL: '#3D3D3D' }
export function badgeColor(base: string): string {
  if (BADGE[base]) return BADGE[base]
  let h = 0
  for (const ch of base) h = (h * 31 + ch.charCodeAt(0)) % 360
  return `hsl(${h} 55% 45%)`
}

export function baseOf(symbol: string, baseAsset?: string): string {
  const b = baseAsset || symbol.replace(/USDT$|USDC$/, '')
  return b.replace(/^1000+(?=[A-Z])/, '').replace(/^1M(?=[A-Z])/, '')
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

export function kindName(s: Pick<Sym, 'kind'> | null | undefined): string {
  return s?.kind === 'us' ? '美股永续' : s?.kind === 'com' ? '大宗永续' : s?.kind === 'idx' ? '指数' : '永续'
}

/** 品种所在板块：加密按成员表、美股按板块代号表 */
export function sectorsOf(s: Sym): { id: string; cn: string }[] {
  if (s.kind === 'us') return SEC.us.filter(x => x[2].includes(s.base)).map(x => ({ id: 'u:' + x[0], cn: x[1] }))
  if (s.kind !== 'crypto') return []
  // 成员表按合约名的底（保留 1000 前缀，如 1000BONK），s.base 已去掉前缀，两个都查
  return (SEC.members[s.symbol.replace(/USDT$|USDC$/, '')] || SEC.members[s.base] || []).map(id => SEC.crypto.find(x => x[0] === id)).filter((x): x is [string, string] => !!x).map(x => ({ id: 'c:' + x[0], cn: x[1] }))
}

/** 搜索打分（越大越靠前，0 = 不命中）：和手机网页 / iOS 同一套归一与分档（market/searchText）——
 *  查询先全角折半角、剥分隔符（BTC/USDT、btc usdt、ＢＴＣ 都认），中文常用叫法与全拼 / 首字母（大饼、longxia、hj）也认；
 *  电脑这边多两条：去掉 1000 前缀的代号（PEPE）按代号算，品种表里的中文名（cn）按别名算 */
export function matchScore(s: Pick<Sym, 'symbol' | 'code' | 'cn'>, q: string): number {
  const Q = normalize(q)
  if (!Q) return 1
  let tier: number | null = matchOne(s.symbol, s.symbol.replace(/USDT$|USDC$/, ''), Q)?.tier ?? null
  const better = (t: number) => { if (tier == null || t < tier) tier = t }
  const code = normalize(s.code)
  if (code === Q) better(Tier.exact)
  else if (code.startsWith(Q)) better(Tier.basePrefix)
  else if (code.includes(Q)) better(Tier.baseContains)
  const cn = s.cn ? normalize(s.cn) : ''
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
