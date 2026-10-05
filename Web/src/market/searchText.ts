/* 搜品种的命中规则（照 iOS SymbolQuery.swift / SymbolAliases.swift），手机网页与电脑网页共用。
 *
 * 归一：全角折半角、转大写、剥分隔符（BTC/USDT、btc usdt、ＢＴＣ、eth-usdt 都等于连写）。
 * 名次：最匹配（打全了）→ 中文名前缀 / 全拼前缀 → 中文名包含 / 首字母前缀 → 代号前缀 → 合约名前缀 → 代号包含 → 合约名包含。
 * 拼音（bitebi / btb / tsl）浏览器里没有字典，用 scripts/gen-pinyin.swift 在 Mac 上照 iOS 同一套
 * CFStringTransform 把别名表算成 m/model/pinyin.json 提交进来；别名表改了要重跑它。
 * 这里不从 market/symbols 取板块表（symbols 反过来要用这里的匹配），美股中文名直接读 sectors.json。
 */
import SECTORS from '../data/sectors.json'
import PINYIN from '../m/model/pinyin.json'

const US_NAMES: Record<string, string> = (SECTORS as unknown as { usNames?: Record<string, string> }).usNames || {}

export const Tier = { exact: 0, cnPrefix: 1, cnContains: 2, basePrefix: 3, symbolPrefix: 4, baseContains: 5, symbolContains: 6 } as const
export type Tier = typeof Tier[keyof typeof Tier]

const SEPARATORS = new Set([' ', '\t', '\n', '\r', '/', '\\', '-', '_', '$', '.', '·', ':', ',', ' ', '／', '－', '：', '，', '、', '　'])
/** 全角 ASCII（ＢＴＣ、１０００、／）折成半角：网页锁不住英文键盘（鸿蒙、iOS Safari 都不认 inputmode=latin），
 *  中文输入法全角状态下打出来的字母数字照样要认 */
export function foldWidth(raw: string): string {
  return raw.replace(/[\uFF01-\uFF5E]/g, c => String.fromCharCode(c.charCodeAt(0) - 0xFEE0))
}
export function normalize(raw: string): string {
  let out = ''
  for (const c of foldWidth(raw).toUpperCase()) if (!SEPARATORS.has(c)) out += c
  return out
}

/** SymbolAliases.key：剥倍数前缀（1000… / 1M…），其余原样 */
export function aliasKey(base: string): string {
  const up = base.toUpperCase()
  const m = /^(\d+)(.*)$/.exec(up)
  if (!m) return up
  const [, digits, rest0] = m
  let rest = rest0
  if (digits === '1' && rest.startsWith('M') && rest.length >= 3) rest = rest.slice(1)
  else if (!(digits.length >= 4 && /^10+$/.test(digits))) return up
  return rest || up
}

/** 中文名与常用叫法（iOS SymbolAliases.cryptoNames 原样；美股的从 sectors.json 的 usNames 读） */
export const CRYPTO_NAMES: Record<string, string[]> = {
  BTC: ['比特币', '大饼'], ETH: ['以太坊', '以太', '二饼'], BNB: ['币安币', '币安'], SOL: ['索拉纳'], XRP: ['瑞波币', '瑞波'],
  DOGE: ['狗狗币', '狗币'], ADA: ['艾达币', '卡尔达诺'], TRX: ['波场币', '波场'], AVAX: ['雪崩币', '雪崩'], LINK: ['预言机'],
  DOT: ['波卡币', '波卡'], POL: ['马蹄链', '马蹄'], MATIC: ['马蹄链', '马蹄'], LTC: ['莱特币', '莱特'], BCH: ['比特现金'],
  ETC: ['以太经典'], XLM: ['恒星币', '恒星'], SHIB: ['柴犬币', '屎币'], UNI: ['独角兽'], AAVE: ['阿威'], ATOM: ['阿童木', '宇宙'],
  FIL: ['文件币', '菲尔币'], APT: ['阿普托斯'], SUI: ['苏伊'], TON: ['电报币'], ICP: ['互联网计算机'], HBAR: ['海博'], VET: ['唯链'],
  RUNE: ['雷神'], ALGO: ['阿尔戈'], SAND: ['沙盒'], AXS: ['阿蟹'], CRV: ['曲线'], EOS: ['柚子币', '柚子'], XMR: ['门罗币', '门罗'],
  ZEC: ['大零币', '零币'], DASH: ['达世币'], NEO: ['小蚁币', '小蚁'], QTUM: ['量子链'], IOTA: ['埃欧塔'], THETA: ['希塔'], FTM: ['范特姆'],
  S: ['索尼克'], KAS: ['卡斯帕'], TIA: ['天体'], ORDI: ['铭文'], PEPE: ['佩佩', '佩佩蛙', '青蛙'], WIF: ['帽子狗', '狗帽'], BONK: ['邦克'],
  FLOKI: ['弗洛基'], JUP: ['木星'], CAKE: ['薄饼'], APE: ['猿币', '无聊猿'], WLD: ['世界币'], TRUMP: ['特朗普币', '川普币'], CFX: ['树图'],
  ONT: ['本体'], RENDER: ['渲染币'], HMSTR: ['仓鼠'], PENGU: ['企鹅'],
  XAU: ['黄金'], PAXG: ['黄金'], XAUT: ['黄金'], XAG: ['白银'], XPT: ['铂金'], XPD: ['钯金'],
  DXY: ['美元指数', '美指', '美元'],
}
/** 整词打全就算「最匹配」的英文关键词（照 iOS SymbolAliases.asciiKeywords）：
 *  美元指数没有计价币，打「USD」时要排在所有 xxxUSDT 前面；只认整词，打「US」不算 */
export const ASCII_KEYWORDS: Record<string, string[]> = { DXY: ['USD'] }
let aliasIndex: Map<string, string[]> | null = null
export function aliasNames(base: string): string[] {
  if (!aliasIndex) {
    aliasIndex = new Map(Object.entries(CRYPTO_NAMES))
    for (const [code, name] of Object.entries(US_NAMES)) {
      const k = code.toUpperCase(), cur = aliasIndex.get(k) ?? []
      if (!cur.includes(name)) aliasIndex.set(k, [...cur, name])
    }
  }
  return aliasIndex.get(aliasKey(base)) ?? []
}
const HAN = /[㐀-䶿一-鿿]/

/** 中文名 → [全拼, 首字母]，都是大写（SymbolAliases.pinyin） */
export const pinyinOf = (name: string): readonly [string, string] | undefined => (PINYIN as unknown as Record<string, [string, string]>)[name]

export function aliasTier(base: string, q: string): Tier | null {
  if (!q) return null
  if (ASCII_KEYWORDS[aliasKey(base)]?.includes(q)) return Tier.exact
  const names = aliasNames(base)
  if (HAN.test(q)) {
    let best: Tier | null = null
    for (const name of names) {
      const n = name.toUpperCase()
      const t = n === q ? Tier.exact : n.startsWith(q) ? Tier.cnPrefix : n.includes(q) ? Tier.cnContains : null
      if (t != null && (best == null || t < best)) best = t
    }
    return best
  }
  // 一个字母的拼音没有意义（「b」会把中文名以 b 开头的币全顶上来），两个字母起才认；
  // 一个字的名字首字母只有一位，同理不进首字母那一档
  if (q.length < 2) return null
  let initials = false
  for (const name of names) {
    const p = pinyinOf(name)
    if (!p) continue
    if (p[0].startsWith(q)) return Tier.cnPrefix
    if (p[1].length >= 2 && p[1].startsWith(q)) initials = true
  }
  return initials ? Tier.cnContains : null
}

export interface Hit { tier: Tier; /** 高亮落在合约名（BTCUSDT）上的 [起, 止)，别名命中时为 null */ hl: [number, number] | null }

/** 单只品种的命中；base 是未剥倍数前缀的底（1000PEPE） */
export function matchOne(symbol: string, base: string, q: string): Hit | null {
  if (!q) return { tier: Tier.exact, hl: null }
  const sym = normalize(symbol), b = base.toUpperCase()
  const inBase = b.indexOf(q), inSym = sym.indexOf(q)
  const alias = aliasTier(base, q)
  if (inBase < 0 && inSym < 0) return alias == null ? null : { tier: alias, hl: null }
  let tier: Tier = q === b || q === sym ? Tier.exact : inBase === 0 ? Tier.basePrefix : inSym === 0 ? Tier.symbolPrefix : inBase >= 0 ? Tier.baseContains : Tier.symbolContains
  if (alias != null && alias < tier) tier = alias
  const at = inBase >= 0 ? inBase : inSym
  return { tier, hl: [at, at + q.length] }
}
