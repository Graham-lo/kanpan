/* Hkline Web · 首页「异动」列表的纯逻辑（测试直接测）
 *
 * 列表打开时定序，之后每 60 s 拉一次：已在列表里的行就地换数、不换位；新出现的、或同一只又有了更新的异动
 * 只计数（浮「有 N 条新异动」药丸），点药丸 / 下拉刷新才按服务端顺序重排。
 */
import type { BoardCat, BoardRow, BoardTop } from './api'

export type Chip = 'all' | BoardCat
/** 行情页半页要展开的那张卡（与 m/pages/chart/highlightsSheet 的 Focus 同形） */
export type RowFocus = { kind: 'level'; id: string } | { kind: 'event'; id: string } | { kind: 'position' }

/** 新拉到的一份并进正在显示的列表：顺序不动，已有的换成新数据；没了的留着旧数据；新来的只计数 */
export function mergeBoard(shown: readonly BoardRow[], latest: readonly BoardRow[]): { rows: BoardRow[]; fresh: number } {
  const byBase = new Map(latest.map(r => [r.base, r]))
  const had = new Map(shown.map(r => [r.base, r]))
  let fresh = 0
  for (const r of latest) {
    const old = had.get(r.base)
    if (!old || r.atMs > old.atMs) fresh++
  }
  return { rows: shown.map(r => byBase.get(r.base) ?? r), fresh }
}

export function chipCounts(rows: readonly BoardRow[]): Record<Chip, number> {
  const c: Record<Chip, number> = { all: rows.length, book: 0, oi: 0, funding: 0 }
  for (const r of rows) c[r.cat]++
  return c
}

export const filterRows = (rows: readonly BoardRow[], chip: Chip): BoardRow[] => (chip === 'all' ? [...rows] : rows.filter(r => r.cat === chip))

/** 点一行带去行情页要展开哪张卡 */
export function focusOf(top: BoardTop): RowFocus {
  if (top.kind === 'level') return { kind: 'level', id: top.id }
  if (top.kind === 'event') return { kind: 'event', id: top.id }
  return { kind: 'position' }
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
