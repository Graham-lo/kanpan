/* Hkline Web · 自选按分类分节（不碰 DOM 的那几步，tests/watch-sections.test.ts）
 *
 * 2026-10-10 用户定版（docs/prototypes/web-layout-2026-10-10.html §3）：自选栏按分类分节连续列出，组头可折叠、带数量、吸顶；
 * 分类胶囊只做跳转。折叠状态只记本机（localStorage 一个键），不进设置、不同步。 */
import type { Kind } from '../market'

export interface WatchSection { tab: Kind; label: string; rows: string[]; count: number; folded: boolean }

/** 本机记哪几节收起了 */
export const FOLD_KEY = 'hkline-web-watch-fold-v1'

const KINDS: readonly Kind[] = ['crypto', 'us', 'idx', 'com']
export function loadFold(store: Pick<Storage, 'getItem'> | undefined = globalThis.localStorage): Set<Kind> {
  try {
    const v = JSON.parse(store?.getItem(FOLD_KEY) || '[]') as unknown
    return new Set(Array.isArray(v) ? v.filter((x): x is Kind => KINDS.includes(x as Kind)) : [])
  } catch { return new Set() }
}
export function saveFold(fold: ReadonlySet<Kind>, store: Pick<Storage, 'setItem'> | undefined = globalThis.localStorage): void {
  try { store?.setItem(FOLD_KEY, JSON.stringify([...fold])) } catch { /* 存不下就只在这一页记着 */ }
}

/**
 * 各节：按分类顺序，空的不出（全空由调用方画空态）；
 * ghost = 空格取消后淡着留在原位的那一行（还算在它那一节里，数量不算它）。
 */
export function watchSections(
  watch: Readonly<Record<Kind, readonly string[]>>, tabs: readonly (readonly [Kind, string])[],
  ghost: { k: string; i: number; tab: Kind } | null, fold: ReadonlySet<Kind>,
): WatchSection[] {
  const out: WatchSection[] = []
  for (const [tab, label] of tabs) {
    const rows = [...(watch[tab] ?? [])]
    const count = rows.length
    if (ghost && ghost.tab === tab && !rows.includes(ghost.k)) rows.splice(Math.min(ghost.i, rows.length), 0, ghost.k)
    if (!rows.length) continue
    out.push({ tab, label, rows, count, folded: fold.has(tab) })
  }
  return out
}

/** 键盘 ↑ ↓ 走的那一串：收起的节跳过 */
export function navRows(sections: readonly WatchSection[]): string[] {
  return sections.flatMap(s => s.folded ? [] : s.rows)
}

/** 滚动到哪一节了：组头离滚动区上沿最近、且已经到顶（或在顶上）的那一节；都还没到就是第一节 */
export function sectionAt(heads: readonly { tab: Kind; top: number }[], scrollTop: number, end?: { viewH: number; scrollH: number; keep: Kind | null }): Kind | null {
  let cur: Kind | null = heads[0]?.tab ?? null
  for (const h of heads) if (h.top <= scrollTop + 1) cur = h.tab
  // 滚到底了：最后几节的组头到不了顶（点「大宗」跳过去也只能停在底），
  // 这时刚点的那一节只要组头露在视口里就留着它亮；否则亮视口里最后一个组头那一节（文档目录的通行做法：到底亮最后一节）
  if (end && scrollTop + end.viewH >= end.scrollH - 1) {
    const inView = heads.filter(h => h.top >= scrollTop - 1 && h.top < scrollTop + end.viewH)
    if (end.keep && inView.some(h => h.tab === end.keep)) return end.keep
    if (inView.length) return inView[inView.length - 1].tab
  }
  return cur
}

/**
 * 拖动松手（可以跨节）：被拖的 moved 落到 target 那一行的上 / 下面。
 * 同一节里只是重排；拖到别的节 = 移到那个分类、落在那个位置。返回改过的两份（或一份）；挪不了返回 null。
 * rendered = 目标那一节画出来的顺序（含淡行）。
 */
export function dropAcross(
  watch: Readonly<Record<Kind, readonly string[]>>, from: Kind, to: Kind, rendered: readonly string[],
  moved: string, target: string, below: boolean,
): Partial<Record<Kind, string[]>> | null {
  if (moved === target || !watch[from]?.includes(moved)) return null
  const src = watch[from].filter(k => k !== moved)
  const r = rendered.filter(k => k !== moved)
  let i = r.indexOf(target)
  if (i < 0) return null
  if (below) i++
  r.splice(i, 0, moved)
  const base = from === to ? src : (watch[to] ?? []).filter(k => k !== moved)
  const keep = new Set([...base, moved])
  const dst = r.filter(k => keep.has(k))
  base.forEach((k, at) => { if (!dst.includes(k)) dst.splice(Math.min(at, dst.length), 0, k) })
  return from === to ? { [to]: dst } : { [from]: src, [to]: dst }
}

/** 右键「移到分类」：从原分类拿掉、接到目标分类末尾（已经在那里就只拿掉原来的） */
export function moveToTab(watch: Readonly<Record<Kind, readonly string[]>>, k: string, from: Kind, to: Kind): Partial<Record<Kind, string[]>> | null {
  if (from === to || !watch[from]?.includes(k)) return null
  const dst = [...(watch[to] ?? [])]
  if (!dst.includes(k)) dst.push(k)
  return { [from]: watch[from].filter(x => x !== k), [to]: dst }
}
