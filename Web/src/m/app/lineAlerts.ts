/* Hkline 手机网页版 · 画线提醒跟着线走（照 iOS AlertStore.seenDrawings / AlertArchive.reconcile）
 *
 * 线挪了，挂在它上面的提醒跟着改价位、重新上膛；线删了，提醒跟着撤——不然成了孤儿照样响。
 * 「删了」要和「说不清来历的缺线」分开：同步逐页拉时提醒先到、线还在下一页，本机存档读坏时整本是空的，
 * 这些缺线不能当删。所以记着「上一次见过的线」（品种 → 线的提醒 id），只有上一份里有、这一份里没有才算删。
 *
 * 这本「见过的线」是壳层的：启动时（同步开始之前）按本机那一本画线记下基线，之后整批换进来的画线
 * （云端同步、别的标签页、换账号）不管行情页挂没挂上都在这里对账。行情页是空闲时才挂的，
 * 基线原来建在它挂上的那一刻——首次同步先到、整桶换了线，那次删线就比不出来，被删线上的提醒留着照响。
 * 本机在图上画、改、删（控制器 onChanged）由行情页调 reconcileLineAlerts。
 */
import { save } from './store'
import { drawingBook, onDrawingsChanged } from './drawings'
import type { Drawing } from '../chart/draw/drawing'
import { AlertGeometry } from '../chart/draw/alert'
import { drawingIdOf, MARKET, type Alert } from '../../alerts/shape'
import { activeAlerts, alertsReplaced, deleteAlert } from '../model/alerts'

/** 这条线作为提醒几何的样子（点位取整到毫秒）；画不成提醒的线是 null */
export function alertLinesOf(d: Drawing): Alert['lines'] | null {
  const lines = AlertGeometry.lines(d)
  return lines ? lines.map(l => ({ points: l.points.map(p => ({ t: Math.round(p.t), p: p.p })), extendLeft: l.extendLeft, extendRight: l.extendRight })) : null
}

/** 上一次对账见过的线（品种 → 画线提醒 id 形状的线 id），当「删之前」 */
const seenLines = new Map<string, Set<string>>()

/** 这只品种的线换成了 drawings：挂在线上的提醒跟着改 / 摘 */
export function reconcileLineAlerts(sym: string, drawings: readonly Drawing[]): void {
  const prior = seenLines.get(sym)
  const byId = new Map(drawings.map(d => [drawingIdOf(sym, d.id), d]))
  seenLines.set(sym, new Set(byId.keys()))
  let dirty = false
  for (const a of activeAlerts(sym)) {
    if (a.kind !== 'drawing' || !a.drawingID) continue
    const d = byId.get(a.drawingID)
    if (!d) { if (prior?.has(a.drawingID)) deleteAlert(a.id); continue }
    const lines = alertLinesOf(d)
    if (!lines) { deleteAlert(a.id); continue }
    if (JSON.stringify(lines) !== JSON.stringify(a.lines)) { a.lines = lines; a.armedAt = Date.now(); dirty = true }
  }
  if (dirty) { save(); alertsReplaced() }
}

/**
 * 整批换进来的画线逐只对账。不止图上正显示的那一只——别的品种的线被别的设备删了，它上面的提醒一样要撤。
 * keys 是换了的桶（规范键 binance/usd_m/代号）。
 */
export function reconcileLineAlertsIn(itemsOf: (key: string) => readonly Drawing[], keys: Iterable<string>): void {
  const pre = MARKET + '/'
  for (const k of keys) if (k.startsWith(pre)) reconcileLineAlerts(k.slice(pre.length), itemsOf(k))
}

let stop: (() => void) | null = null

/**
 * 壳启动时调（要在同步开始之前）：按本机那一本记下基线，之后整批换进来的画线随到随对账。
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

/** 测试用：忘掉见过的线 */
export function resetSeenLines(): void { seenLines.clear() }
