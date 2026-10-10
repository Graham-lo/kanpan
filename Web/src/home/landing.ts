/* Hkline Web · 冷启动落哪一页
 *
 * 地址不带 #页名 时：带了图表参数（品种、周期、布局、侧栏、梯子、抽屉）的深链照旧进图表，其余一律落「首页」。
 * 地址栏参数在 main.ts 一开头就由 app/query.ts 落进 st 并从地址栏拿掉，所以那边顺手把用过的键记在这里，
 * 外壳（app/shell.ts installShell）摆首屏时来读。只有 #页名 为空才看这一项——#chart、#sectors 等照旧。
 */
import type { PageId } from '../app/store'

/** 这些参数是冲着图表来的：带了就落图表 */
const CHART_KEYS: readonly string[] = ['s', 'i', 'layout', 'panel', 'ladder', 'drawer']

let used: readonly string[] = []

/** app/query.ts 落完参数后记一下用过哪些键 */
export function noteQueryKeys(keys: readonly string[]): void { used = [...keys] }

/** 地址不带 #页名 时落哪页：图表深链 → 图表；其余（含只带 theme / skin 的）→ 首页 */
export function landingPage(keys: readonly string[] = used): PageId {
  return keys.some(k => CHART_KEYS.includes(k)) ? 'chart' : 'home'
}
