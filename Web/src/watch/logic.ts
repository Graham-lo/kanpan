/* Hkline Web · 自选小部件里不碰 DOM 的那几步（拖动排序落点、清空撤销、持仓额格） */

/** 拖动松手：在「画出来的那份」（含空格取消后淡着留下的那一行）上按落点挪，再丢掉已不在自选里的。
 *  落点那一行可能是淡行（不在自选里），也可能拖动途中同步把别的行删了、加了：
 *  按画出来的相对位置算，不会因为落点不在自选里就把它甩到最后。
 *  返回新的自选顺序；挪不了（被拖的那只已不在自选里、落点已不在画面上）返回 null。 */
export function reorderWatch(list: readonly string[], rendered: readonly string[], moved: string, target: string, below: boolean): string[] | null {
  if (moved === target || !list.includes(moved)) return null
  const r = rendered.filter(k => k !== moved)
  let i = r.indexOf(target)
  if (i < 0) return null
  if (below) i++
  r.splice(i, 0, moved)
  const keep = new Set(list)
  const out = r.filter(k => keep.has(k))
  // 画完之后才同步进来的（画面上没有）：按它在自选里的位置插回
  list.forEach((k, at) => { if (!out.includes(k)) out.splice(Math.min(at, out.length), 0, k) })
  return out
}

/** 清空后 ⌘Z：清空前那份原样回来，清空之后新加的（别处同步进来、或搜索刚加的）接在后面，不被覆盖掉 */
export function undoClear(before: readonly string[], now: readonly string[]): string[] {
  const out = [...before]
  for (const k of now) if (!out.includes(k)) out.push(k)
  return out
}

/** 跳价闪色的四个类：涨 / 跌各两套同样的关键帧（app.css 的 wvFlashUp / wvFlashUp2 …） */
export const FLASH_CLASSES = ['wv-flash-up', 'wv-flash-up2', 'wv-flash-down', 'wv-flash-down2'] as const
/** 这一次该挂哪个闪色类：和上一次的动画名错开（上次是第一套就挂第二套），浏览器见到新的动画名就从头播，
 *  不用先摘类、读一次 offsetWidth 逼它重算样式再挂回去 */
export function flashClass(prev: string, dir: number): string {
  const was = prev.split(/\s+/).find(c => (FLASH_CLASSES as readonly string[]).includes(c))
  const second = !!was && !was.endsWith('2')
  return (dir > 0 ? 'wv-flash-up' : 'wv-flash-down') + (second ? '2' : '')
}

/** 自选表里哪些行此刻在滚动区里看得见：看不见的行推送来了只记一笔「欠着」、不碰 DOM，滚进来时一次补上（不闪色）。
 *  300 只自选的表格里，滚出去的行每跳一次价都要整张表重新排版、整块侧栏重画——挂机时这一项占了主线程的一半
 *  （2026-10-07 C15 实测：把表藏掉，主线程从 12.8% 掉到 5.3%）。
 *  还没报过可见性的行（刚画出来、观察器还没回调）当看得见，照常改字。 */
export class RowGate {
  private hidden = new Set<string>()
  private owed = new Set<string>()
  /** 推送来了：true = 现在就改这一行；false = 先欠着 */
  offer(k: string): boolean {
    if (!this.hidden.has(k)) return true
    this.owed.add(k)
    return false
  }
  /** 观察器报了这一行的可见性；返回 true = 它刚滚进来、之前欠着推送，要补一次 */
  seen(k: string, visible: boolean): boolean {
    if (!visible) { this.hidden.add(k); return false }
    this.hidden.delete(k)
    return this.owed.delete(k)
  }
  /** 表整张重画了（行都按最新数画好）：之前记的都作废 */
  reset(): void { this.hidden.clear(); this.owed.clear() }
  /** 诊断：看不见的行数、欠着的行数 */
  stats(): { hidden: number; owed: number } { return { hidden: this.hidden.size, owed: this.owed.size } }
}
