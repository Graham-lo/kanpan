/* Hkline Web · 从 TradingView 导入自选（纯函数，不碰状态）
 *
 * TradingView 的自选列表导出是一份 .txt：代号之间用逗号分隔，分区写成「###名字」，例如
 *   ###加密,BINANCE:BTCUSDT.P,BINANCE:ETHUSDT.P,###美股,NASDAQ:NVDA,OANDA:XAUUSD
 * 用户也可能手抄一串，换行、分号、空格分隔都认。
 *
 * 匹配只看币安 U 本位合约表：
 *   去掉「交易所:」前缀和 .P / PERP 这类永续后缀 → 依次试原样、USD/USDC 换成 USDT、补 USDT、
 *   1000 / 1000000 / 1M 前缀（PEPE、SHIB 这类在合约上是 1000PEPEUSDT）；再加几个大宗俗名（GOLD → XAU）。
 *   都对不上的原样列出来。
 *
 * 分区：「###加密 / 美股 / 大宗」这类名字映射到现有的三个自选分类，映射不上的并进加密。
 * 但品种最终进哪一类由它自己的类别决定——自选同步按品种类别编码，放错类别的品种经云端往返会被挪回去，
 * 所以分区映射只用于汇报「这一区对应哪个分类」。
 */
import type { Kind } from '../market/symbols'

export interface TvUniverse {
  /** 合约表里有没有这只（USDT 永续代号，如 BTCUSDT） */
  has(symbol: string): boolean
  /** 这只属于哪一类；表里没有返回 undefined */
  kindOf(symbol: string): Kind | undefined
}

export interface TvToken { raw: string; section: string }
export interface TvSection { name: string; kind: Kind; mapped: boolean; count: number }
export interface TvResult {
  /** 新加进自选的，按类别 */
  added: Record<Kind, string[]>
  /** 已经在自选里的 */
  already: string[]
  /** 匹配不上的原始代号 */
  unmatched: string[]
  /** 输入里出现的分区（没有分区时为空） */
  sections: TvSection[]
  /** 认出来的代号总数（含重复前的去重） */
  total: number
}

const KINDS: Kind[] = ['crypto', 'us', 'com']

/** 分区名 → 自选分类；映射不上返回 null（调用方并进加密） */
export function sectionKind(name: string): Kind | null {
  const n = name.trim().toLowerCase().replace(/\s+/g, '')
  if (!n) return null
  if (/^(加密|加密货币|数字货币|币|币圈|crypto|cryptos|cryptocurrency|coins?)$/.test(n)) return 'crypto'
  if (/^(美股|股票|美国股票|us|usa|stocks?|equit(y|ies)|usstocks?)$/.test(n)) return 'us'
  if (/^(大宗|大宗商品|商品|期货|金属|贵金属|外汇|commodit(y|ies)|metals?|futures|forex|fx)$/.test(n)) return 'com'
  return null
}

/** 把一段文本切成「代号 + 所在分区」 */
export function parseTv(text: string): TvToken[] {
  const out: TvToken[] = []
  let section = ''
  for (const part of text.split(/[,\n\r;，；\t ]+/)) {
    const p = part.trim()
    if (!p) continue
    if (p.startsWith('###')) { section = p.slice(3).trim(); continue }
    out.push({ raw: p, section })
  }
  return out
}

// 大宗在 TradingView 上常用的俗名 → 币安合约的代号主体
const ALIAS: Record<string, string> = {
  GOLD: 'XAU', SILVER: 'XAG', PLATINUM: 'XPT', PALLADIUM: 'XPD',
  USOIL: 'CL', WTI: 'CL', UKOIL: 'BZ', BRENT: 'BZ', NATURALGAS: 'NATGAS', NG: 'NATGAS', COPPER: 'COPPER', HG: 'COPPER',
}

/** 去前缀、去永续后缀、大写，得到代号主体（如 BTCUSDT、NVDA、XAUUSD） */
export function stripTv(raw: string): string {
  let s = raw.trim().toUpperCase().replace(/^["']|["']$/g, '')
  const colon = s.lastIndexOf(':'); if (colon >= 0) s = s.slice(colon + 1)
  s = s.replace(/\.P$/, '').replace(/\.PERP$/, '').replace(/PERP$/, '').replace(/[-_/]/g, '')
  return s
}

/** 这个代号在合约表里对应哪一只；对不上返回 null */
export function matchTv(raw: string, u: TvUniverse): string | null {
  const s = stripTv(raw)
  if (!s || !/^[A-Z0-9]+$/.test(s)) return null
  const bases: string[] = []
  const quote = s.match(/^(.+?)(USDT|USDC|BUSD|USD)$/)
  if (quote) bases.push(quote[1]); else bases.push(s)
  const b0 = bases[0]
  if (ALIAS[b0]) bases.push(ALIAS[b0])
  const cand: string[] = [s]
  for (const b of bases) {
    cand.push(b + 'USDT', '1000' + b + 'USDT', '1000000' + b + 'USDT', '1M' + b + 'USDT')
    // TradingView 上 1000PEPE 这类有时写全称带前缀，有时不带：带了而表里没有就去掉再试
    const bare = b.replace(/^(1000000|1000|1M)/, '')
    if (bare !== b && bare) cand.push(bare + 'USDT')
  }
  for (const c of cand) if (u.has(c)) return c
  return null
}

/** 算出导入结果；不改传进来的自选 */
export function importTv(text: string, u: TvUniverse, watch: Record<Kind, string[]>): TvResult {
  const tokens = parseTv(text)
  const added: Record<Kind, string[]> = { crypto: [], us: [], com: [] }
  const already: string[] = [], unmatched: string[] = []
  const seen = new Set<string>(), seenBad = new Set<string>()
  const secs = new Map<string, TvSection>()
  const have = new Set(KINDS.flatMap(k => watch[k] || []))
  for (const t of tokens) {
    if (t.section && !secs.has(t.section)) {
      const k = sectionKind(t.section)
      secs.set(t.section, { name: t.section, kind: k || 'crypto', mapped: k != null, count: 0 })
    }
    const m = matchTv(t.raw, u)
    if (!m) { const key = stripTv(t.raw) || t.raw; if (!seenBad.has(key)) { seenBad.add(key); unmatched.push(t.raw) } continue }
    if (seen.has(m)) continue
    seen.add(m)
    const sec = t.section ? secs.get(t.section) : undefined
    if (sec) sec.count++
    if (have.has(m)) { already.push(m); continue }
    added[u.kindOf(m) || 'crypto'].push(m)
  }
  return { added, already, unmatched, sections: [...secs.values()], total: seen.size }
}

/** 把导入结果并进自选（原地追加到各类末尾） */
export function applyTv(watch: Record<Kind, string[]>, r: TvResult): number {
  let n = 0
  for (const k of KINDS) for (const s of r.added[k]) if (!watch[k].includes(s)) { watch[k].push(s); n++ }
  return n
}
