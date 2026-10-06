/* Hkline 手机网页版 · 画线提醒跟着线挪（不跟着线删）
 *
 * 2026-10-06 起提醒不再依附画线（用户：「画线和警报是不冲突的，我删除画线也不应该删除警报才对」）：
 * - 线挪了 → 提醒的几何跟上、从此刻起算（armedAt 重置；不重置的话刚挪过去就被历史行情判响）；
 * - 线删了、藏了、几何算不出、换进来的这一份里没有它 → 提醒一概不动：照它自己存的 lines 判，
 *   图上用提醒自己的 lines 画一条提醒线（view.drawing.ts 的 alertSignals）；
 * - 线回来了 → 照它现在的样子重算几何、从此刻起算。
 * 提醒只有两条路会没：用户在提醒表里删掉、或者响了（响一次就删）。
 * 从前「本机删线就连提醒一起删」「上一份见过、这一份没了才算删」那套已经撤掉，所以不再记「见过的线」。
 *
 * 整批换进来的画线（云端同步、别的标签页、换账号）由壳层在这里对账（startLineAlerts，启动时就装）；
 * 本机在图上画、改、删（控制器 onChanged）由行情页调 reconcileLineAlerts。
 */
import { save } from './store'
import { drawingBook, onDrawingsChanged } from './drawings'
import type { Drawing } from '../chart/draw/drawing'
import { AlertGeometry } from '../chart/draw/alert'
import { drawingIdOf, MARKET, type Alert } from '../../alerts/shape'
import { MACRO_KEY, MACRO_SYMBOL } from '../../market/macro'
import { activeAlerts, alertsReplaced } from '../model/alerts'

/** 这条线作为提醒几何的样子（点位取整到毫秒）；画不成提醒的线是 null */
export function alertLinesOf(d: Drawing): Alert['lines'] | null {
  const lines = AlertGeometry.lines(d)
  return lines ? lines.map(l => ({ points: l.points.map(p => ({ t: Math.round(p.t), p: p.p })), extendLeft: l.extendLeft, extendRight: l.extendRight })) : null
}

/** 这只品种的线换成了 drawings：线还在、几何变了的，挂在上面的提醒跟着改价位、重新上膛；线不在的提醒不动 */
export function reconcileLineAlerts(sym: string, drawings: readonly Drawing[]): void {
  const byId = new Map(drawings.map(d => [drawingIdOf(sym, d.id), d]))
  let dirty = false
  for (const a of activeAlerts(sym)) {
    if (a.kind !== 'drawing' || !a.drawingID) continue
    const d = byId.get(a.drawingID)
    const lines = d ? alertLinesOf(d) : null
    if (!lines) continue
    if (JSON.stringify(lines) !== JSON.stringify(a.lines)) { a.lines = lines; a.armedAt = Date.now(); dirty = true }
  }
  if (dirty) { save(); alertsReplaced() }
}

/**
 * 整批换进来的画线逐只对账。不止图上正显示的那一只——别的品种的线被别的设备挪了，它上面的提醒一样要跟上。
 * keys 是换了的桶（规范键 binance/usd_m/代号）。
 */
export function reconcileLineAlertsIn(itemsOf: (key: string) => readonly Drawing[], keys: Iterable<string>): void {
  const pre = MARKET + '/'
  for (const k of keys) {
    if (k.startsWith(pre)) reconcileLineAlerts(k.slice(pre.length), itemsOf(k))
    else if (k === MACRO_KEY) reconcileLineAlerts(MACRO_SYMBOL, itemsOf(k))   // 美元指数的桶
  }
}

let stop: (() => void) | null = null

/**
 * 壳启动时调（要在同步开始之前）：按本机那一本对一遍，之后整批换进来的画线随到随对账。
 * 调多次只装一次；返回卸下（测试用）。
 */
export function startLineAlerts(): () => void {
  if (stop) return stop
  const itemsOf = (k: string) => drawingBook.items(k)
  const off = onDrawingsChanged(ch => { if (ch.kind === 'replaced') reconcileLineAlertsIn(itemsOf, ch.keys) })
  reconcileLineAlertsIn(itemsOf, Object.keys(drawingBook.archive.bySymbol))
  stop = () => { off(); stop = null }
  return stop
}

