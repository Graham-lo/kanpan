/* 手机网页版 · 自选（照 iOS SymbolPrefs.swift / SymbolPickerModel 自选段 / FavoriteCategory.swift）
 *
 * 纯函数都吃一份 SymbolPrefs（就是 st.symbols），改完由调用方 save()。
 * 顺序永远是用户自己的顺序，不排序；分类只是过滤。
 */
import type { FavoriteGroup, SymbolPrefs } from '../app/store'
import { DEFAULT_WATCH, type Kind } from '../../market/symbols'

export const RECENT_LIMIT = 10
export const PRESETS = ['加密', '美股', '贵金属'] as const
const PRECIOUS = new Set(['XAU', 'XAG', 'XPT', 'XPD'])

export const key = (symbol: string): string => symbol.trim().toUpperCase()

/** 分类名（FavoriteCategory.name）：币 → 加密；美股 → 美股；贵金属 → 贵金属；其余大宗 → 其他 */
export function categoryName(kind: Kind | undefined, base: string): string | null {
  if (!kind) return null
  if (kind === 'crypto') return '加密'
  if (kind === 'us') return '美股'
  if (kind === 'idx') return '指数'
  return PRECIOUS.has(base.toUpperCase()) ? '贵金属' : '其他'
}

export interface Snapshot { symbol: string; index: number; group: string | null }

export const isFavorite = (p: SymbolPrefs, symbol: string): boolean => p.favorites.includes(key(symbol))

let seq = 0
function newId(): string {
  const c = (globalThis as { crypto?: { randomUUID?: () => string } }).crypto
  return c?.randomUUID ? c.randomUUID().toUpperCase() : `G${Date.now().toString(36)}${(++seq).toString(36)}`.toUpperCase()
}
const identity = (name: string): string => name.trim()

/** 按名字开一个分类（同名就用已有的）；名字截到 24 个字。
 *  after：新开的排在这个名字的分类后面（没有它就接在最后），照 iOS createGroup(name, after:) */
export function createGroup(p: SymbolPrefs, name: string, after?: string): string | null {
  const trimmed = [...name.trim()].slice(0, 24).join('')
  if (!trimmed) return null
  const hit = p.groups.find(g => identity(g.name) === trimmed)
  if (hit) return hit.id
  const id = newId()
  const at = after ? p.groups.findIndex(g => identity(g.name) === after) : -1
  if (at >= 0) p.groups.splice(at + 1, 0, { id, name: trimmed })
  else p.groups.push({ id, name: trimmed })
  return id
}

/** 偏好的分类在就用它，不在就第一个（没有分类返回 null） */
export function group(p: SymbolPrefs, preferred: string | null | undefined): string | null {
  if (preferred && p.groups.some(g => g.id === preferred)) return preferred
  return p.groups[0]?.id ?? null
}

export function favoritesIn(p: SymbolPrefs, groupId: string | null): string[] {
  return p.favorites.filter(s => (p.groupForSymbol[s] ?? null) === groupId)
}

/** 分类页此刻显示哪些：有分类时按当前分类过滤；一个分类都没有时就是全部 */
export function visible(p: SymbolPrefs, current: string | null): string[] {
  if (!p.groups.length) return p.favorites.slice()
  return favoritesIn(p, group(p, current))
}

export function assign(p: SymbolPrefs, symbol: string, groupId: string | null): void {
  const s = key(symbol)
  if (!p.favorites.includes(s)) return
  if (groupId && p.groups.some(g => g.id === groupId)) p.groupForSymbol[s] = groupId
  else delete p.groupForSymbol[s]
}

/** 加自选：落进他此刻站着的分类；一个分类都没有时按资产类型开第一类 */
export function addFavorite(p: SymbolPrefs, symbol: string, current: string | null, facts?: { kind?: Kind; base?: string }): void {
  const s = key(symbol)
  if (!s || p.favorites.includes(s)) return
  p.favorites.push(s)
  // 交易所自带分类的品种（美元指数 → 「指数」）不管他站在哪一类都落进自己那一类，分类排在「美股」后面
  // （照 iOS SymbolPickerModel.assignVenueCategory）
  if (facts?.kind === 'idx' || s === 'DXY') {
    const id = createGroup(p, '指数', '美股')
    if (id) p.groupForSymbol[s] = id
    return
  }
  const g = group(p, current)
  if (g) { p.groupForSymbol[s] = g; return }
  const name = categoryName(facts?.kind, facts?.base ?? s.replace(/USDT$|USDC$/, ''))
  if (!name) return
  const id = createGroup(p, name)
  if (id) p.groupForSymbol[s] = id
}

export function removeFavorite(p: SymbolPrefs, symbol: string): void {
  const s = key(symbol)
  p.favorites = p.favorites.filter(x => x !== s)
  delete p.groupForSymbol[s]
}

/** 切换；返回切换后是否在自选里 */
export function toggleFavorite(p: SymbolPrefs, symbol: string, current: string | null, facts?: { kind?: Kind; base?: string }): boolean {
  if (isFavorite(p, symbol)) { removeFavorite(p, symbol); return false }
  addFavorite(p, symbol, current, facts)
  return true
}

export function snapshot(p: SymbolPrefs, symbol: string): Snapshot | null {
  const s = key(symbol)
  const index = p.favorites.indexOf(s)
  return index < 0 ? null : { symbol: s, index, group: p.groupForSymbol[s] ?? null }
}

/** 撤销：按原位置插回，原分类没了就放进 fallback */
export function restore(p: SymbolPrefs, items: Snapshot[], fallback: string | null): void {
  for (const it of items.slice().sort((a, b) => a.index - b.index)) {
    const s = key(it.symbol)
    if (!s || p.favorites.includes(s)) continue
    p.favorites.splice(Math.min(Math.max(it.index, 0), p.favorites.length), 0, s)
    if (it.group && p.groups.some(g => g.id === it.group)) p.groupForSymbol[s] = it.group
    else if (it.group != null) { const g = group(p, fallback); if (g) p.groupForSymbol[s] = g; else delete p.groupForSymbol[s] }
    else delete p.groupForSymbol[s]
  }
}

/** 整张表里挪：from 的那一项挪完之后落在下标 to（和 m/ui/reorder 的 onMove 口径一致） */
export function moveList(list: string[], from: number, to: number): string[] {
  const out = list.slice()
  if (from < 0 || from >= out.length || from === to) return out
  const [m] = out.splice(from, 1)
  out.splice(Math.min(Math.max(0, to), out.length), 0, m)
  return out
}

/** 只在可见的那几行之间挪，其它分类的位置不动（SymbolPrefs.moveVisible） */
export function moveVisible(p: SymbolPrefs, shown: string[], from: number, to: number): void {
  // from / to 是画出来的那几行（shown）的下标。拖动途中同步删掉了上面某一行、列表还没重画时，
  // 先按自选过滤再按下标挪会整体错一位、挪走的是别人（与 iOS 深度审查 D 线 V-4 同一个坑）：
  // 先在 shown 上原样挪，再丢掉已不在自选里的。
  const favs = new Set(p.favorites)
  const ordered = moveList(shown.map(key), from, to).filter(s => favs.has(s))
  const members = new Set(ordered)
  let i = 0
  p.favorites = p.favorites.map(s => members.has(s) ? ordered[i++] : s)
}

/** 删分类：成员回到未分类，再归进 selected（照 deleteGroup + classifyUnassigned） */
export function deleteGroup(p: SymbolPrefs, id: string, selected: string | null): void {
  p.groups = p.groups.filter(g => g.id !== id)
  for (const [s, g] of Object.entries(p.groupForSymbol)) if (g === id) delete p.groupForSymbol[s]
  const into = group(p, selected)
  if (!into) return
  for (const s of p.favorites) if (p.groupForSymbol[s] == null) p.groupForSymbol[s] = into
}

/** 「移到分类」的候选：已有的分类 + 还没开的预设 */
export function moveTargets(p: SymbolPrefs): string[] {
  const names = p.groups.map(g => g.name)
  return [...names, ...PRESETS.filter(n => !names.includes(n))]
}

/** 移到某个名字的分类（没有就开） */
export function assignToCategory(p: SymbolPrefs, symbols: string[], name: string): string | null {
  const id = createGroup(p, name)
  if (!id) return null
  symbols.forEach(s => assign(p, s, id))
  return id
}

/** 最近打开 */
export function visit(p: SymbolPrefs, symbol: string): void {
  const s = key(symbol)
  if (!s) return
  p.recents = [s, ...p.recents.filter(x => x !== s)].slice(0, RECENT_LIMIT)
}

/** 访客第一次打开：按 DEFAULT_WATCH 三类各开一个分类落进去。只给一次。
 *  exists 用来滤掉交易所已经下架的代号（表还没到时传 null，全收）。 */
export function seedDefaults(p: SymbolPrefs, exists: ((symbol: string) => boolean) | null = null): boolean {
  if (p.seeded) return false
  p.seeded = true
  if (p.favorites.length) return true
  for (const kind of Object.keys(DEFAULT_WATCH) as Kind[]) {
    for (const sym of DEFAULT_WATCH[kind]) {
      if (exists && !exists(sym)) continue
      const s = key(sym)
      if (p.favorites.includes(s)) continue
      const name = categoryName(kind, s.replace(/USDT$/, ''))
      const id = name ? createGroup(p, name) : null
      p.favorites.push(s)
      if (id) p.groupForSymbol[s] = id
    }
  }
  return true
}

export const groupName = (p: SymbolPrefs, id: string | null): string => p.groups.find((g: FavoriteGroup) => g.id === id)?.name ?? ''
