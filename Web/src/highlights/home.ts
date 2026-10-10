/* Hkline Web · 首页异动筛选、定位与本机偏好。 */
import type { BoardCat, BoardRow, BoardTop, MarketKind, MarketWindow } from './api'

export type Chip = 'all' | BoardCat
/** 行情页半页要展开的那张卡（与 m/pages/chart/highlightsSheet 的 Focus 同形） */
export type RowFocus = { kind: 'level'; id: string } | { kind: 'event'; id: string } | { kind: 'position' }

// 电脑首页仍使用待确认重排；手机首页直接采用最新列表。
/** 新拉到的一份并进正在显示的列表：顺序不动，已有的换成新数据；没了的留着旧数据；新来的只计数 */
export function mergeBoard(shown: readonly BoardRow[], latest: readonly BoardRow[]): { rows: BoardRow[]; fresh: number } {
  const byKey = new Map(latest.map(r => [r.key, r]))
  const had = new Map(shown.map(r => [r.key, r]))
  let fresh = 0
  for (const r of latest) {
    const old = had.get(r.key)
    if (!old || r.atMs > old.atMs) fresh++
  }
  return { rows: shown.map(r => byKey.get(r.key) ?? r), fresh }
}

export function chipCounts(rows: readonly BoardRow[]): Record<Chip, number> {
  const c: Record<Chip, number> = { all: rows.length, book: 0, oi: 0, funding: 0, move: 0 }
  for (const r of rows) c[r.cat]++
  return c
}

export const filterRows = (rows: readonly BoardRow[], chip: Chip): BoardRow[] => (chip === 'all' ? [...rows] : rows.filter(r => r.cat === chip))

/** 点一行带去行情页要展开哪张卡；波动行只进图、不升半页（null） */
export function focusOf(top: BoardTop): RowFocus | null {
  if (top.kind === 'level') return { kind: 'level', id: top.id }
  if (top.kind === 'event') return { kind: 'event', id: top.id }
  if (top.kind === 'move') return null
  return { kind: 'position' }
}

// ───────── 首页本机记的（分类胶囊、两页各自的窗口；不同步） ─────────

/** 涨跌 / 持仓两页：各自一个窗口，各自两张榜 */
export type RankPage = 'change' | 'oi'
export const RANK_KINDS: Record<RankPage, readonly [MarketKind, MarketKind]> = { change: ['gainers', 'losers'], oi: ['oi', 'oidown'] }
export interface HomeLocal { chip: Chip; win: Record<RankPage, MarketWindow> }

const CHIPS: readonly Chip[] = ['all', 'book', 'oi', 'funding', 'move']
const isWin = (w: unknown): w is MarketWindow => w === '1h' || w === '4h' || w === '24h'

/** 读本机那份：认得的才用；旧档（榜单一页三张卡各自一个窗口 win.gainers / win.oi）迁成涨跌页、持仓页各自的窗口。
 *  分段不从这里读：冷启动一律回「异动」 */
export function parseHomeLocal(raw: unknown): HomeLocal {
  const d: HomeLocal = { chip: 'all', win: { change: '4h', oi: '4h' } }
  if (!raw || typeof raw !== 'object') return d
  const v = raw as { chip?: unknown; win?: Record<string, unknown> }
  if (CHIPS.includes(v.chip as Chip)) d.chip = v.chip as Chip
  const w = v.win && typeof v.win === 'object' ? v.win : {}
  const change = isWin(w.change) ? w.change : isWin(w.gainers) ? w.gainers : isWin(w.losers) ? w.losers : null
  if (change) d.win.change = change
  if (isWin(w.oi)) d.win.oi = w.oi
  return d
}

/** 币名 → 打开哪只：自选里同币的那只优先；否则币安 <币>USDT，没有就 1000<币>USDT（千枚计价），都没有照 <币>USDT */
export function symbolFor(base: string, favorites: readonly string[], baseOf: (symbol: string) => string, has: (symbol: string) => boolean): string {
  const fav = favorites.find(k => baseOf(k) === base)
  if (fav) return fav
  const plain = `${base}USDT`
  if (has(plain)) return plain
  const scaled = `1000${base}USDT`
  return has(scaled) ? scaled : plain
}

/** 自选里的币名（去重、保序，最多 60 只——服务端只收这么多） */
export function favoriteBases(favorites: readonly string[], baseOf: (symbol: string) => string, max = 60): string[] {
  const out: string[] = []
  for (const k of favorites) {
    const b = baseOf(k)
    if (b && !out.includes(b)) out.push(b)
    if (out.length >= max) break
  }
  return out
}
