/* 手机网页版 · 首页分段（异动 · 涨跌 · 持仓 · 板块）
 *
 * 2026-10-10 起「板块分类」不再占底栏一格，并进首页成第四段：深链 #sectors、旧档里记的 sectors 页、
 * 来路回 sectors 都落到首页的「板块」段。分段只在这一次打开里记（冷启动回到「异动」，照 iOS HomeModel.segment），
 * 不落盘、不同步。壳（go）与习惯学习（板块今日 / 5 日）都从这里读写，首页订阅它换段。
 */
export type HomeSeg = 'moves' | 'change' | 'oi' | 'sectors'
export const HOME_SEGS: readonly HomeSeg[] = ['moves', 'change', 'oi', 'sectors']

let seg: HomeSeg = 'moves'
const subs = new Set<(s: HomeSeg) => void>()
let sectorsRefresh: (() => void) | null = null

export const homeSeg = (): HomeSeg => seg

export function setHomeSeg(next: HomeSeg): void {
  if (!HOME_SEGS.includes(next) || next === seg) return
  seg = next
  for (const f of [...subs]) { try { f(seg) } catch (e) { console.error(e) } }
}

export function onHomeSeg(fn: (s: HomeSeg) => void): () => void {
  subs.add(fn)
  return () => { subs.delete(fn) }
}

/** 地址 / 旧页名 → 首页哪一段：sectors（旧的板块分类页）→ 板块段；不是首页的返回 null */
export function segOfRoute(page: string): HomeSeg | null {
  if (page === 'sectors') return 'sectors'
  return null
}

/** 板块段挂好后登记它的重画（习惯学习改了今日 / 5 日要它重画）；refreshSectors 在没挂时什么都不做 */
export function registerSectorsRefresh(fn: (() => void) | null): void { sectorsRefresh = fn }
export function refreshSectors(): void { sectorsRefresh?.() }

/** 测试用：回到冷启动状态 */
export function resetHomeSeg(): void { seg = 'moves'; subs.clear(); sectorsRefresh = null }
