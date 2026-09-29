// 移植自 KanpanCore/Sources/KanpanCore/Drawing/DrawingBook.swift
//
// 画线的唯一真值：所有品种的线、每个品种的撤销栈、每品种条数上限，都在这一本里。
// 图绑上它之后，图上的线只是它按当前品种投影出来的那一桶；每一笔编辑都先写进这里，再投影回图。
//
// 两类改动分得很清：本地编辑（commit / add / undo / redo）进撤销栈、报 edited；
// 整批外部替换（replace）清掉真变了那几桶的撤销栈、报 replaced。

import { type Drawing, drawingIsValid, drawingsEqual } from './drawing'
import { DrawHistory } from './edit'
import { DrawArchive, type DrawingPreferences } from './archive'
import { canonicalInstrument } from './instrument'

export type DrawingBookChange =
  | { kind: 'edited'; key: string }
  | { kind: 'replaced'; keys: Set<string> }

interface Observer { owner: object; handler: (c: DrawingBookChange) => void }

export class DrawingBook {
  archive: DrawArchive
  private histories = new Map<string, DrawHistory>()
  /** 按订阅先后排：通知顺序确定。 */
  private observers: Observer[] = []

  constructor(archive: DrawArchive = new DrawArchive()) {
    this.archive = archive
  }

  // ---------------------------------------------------------- 读

  items(symbol: string): Drawing[] { return this.archive.get(symbol) }

  history(symbol: string): DrawHistory {
    return this.histories.get(canonicalInstrument(symbol)) ?? new DrawHistory()
  }

  /** 撤销栈整摞换掉；空栈不占格子。 */
  setHistory(history: DrawHistory, symbol: string): void {
    const key = canonicalInstrument(symbol)
    if (history.canUndo || history.canRedo) this.histories.set(key, history)
    else this.histories.delete(key)
  }

  /** 画线偏好跟着存档走，但改它不算「画线被编辑了」，不发通知。 */
  get preferences(): DrawingPreferences { return this.archive.preferences }
  set preferences(v: DrawingPreferences) { this.archive.preferences = v }

  // ---------------------------------------------------------- 上限

  hasRoom(symbol: string, adding = 1): boolean {
    return this.archive.get(symbol).length + adding <= DrawArchive.perSymbolLimit
  }

  // ---------------------------------------------------------- 本地编辑

  /** 把这一桶改成 next，改之前那份进撤销栈。没变就返回 false。 */
  commit(next: Drawing[], symbol: string): boolean {
    const key = canonicalInstrument(symbol)
    const before = this.archive.get(key)
    if (drawingsEqual(next, before)) return false
    const h = this.histories.get(key) ?? new DrawHistory()
    h.commit(before)
    this.histories.set(key, h)
    this.archive.set(key, next)
    this.post({ kind: 'edited', key })
    return true
  }

  /** 追加几条新线：一步撤销。容量不够时整批不写返回 false；已有的 id 跳过。 */
  add(incoming: readonly Drawing[], symbol: string): boolean {
    const before = this.archive.get(symbol)
    const known = new Set(before.map(d => d.id))
    const added = incoming.filter(d => !known.has(d.id))
    if (!added.every(drawingIsValid) || !this.hasRoom(symbol, added.length)) return false
    if (added.length === 0) return true
    this.commit(before.concat(added), symbol)
    return true
  }

  undo(symbol: string): boolean {
    const key = canonicalInstrument(symbol)
    const h = this.histories.get(key)
    if (!h) return false
    const prev = h.undo(this.archive.get(key))
    if (prev == null) return false
    this.archive.set(key, prev)
    this.post({ kind: 'edited', key })
    return true
  }

  redo(symbol: string): boolean {
    const key = canonicalInstrument(symbol)
    const h = this.histories.get(key)
    if (!h) return false
    const next = h.redo(this.archive.get(key))
    if (next == null) return false
    this.archive.set(key, next)
    this.post({ kind: 'edited', key })
    return true
  }

  // ---------------------------------------------------------- 整批外部替换

  /** 整本换掉：只有真变了的桶清撤销栈、进 replaced；resetAllHistory 给换账号用。 */
  replace(next: DrawArchive, resetAllHistory = false): void {
    const keys = new Set([...Object.keys(this.archive.bySymbol), ...Object.keys(next.bySymbol)])
    const changed = new Set<string>()
    for (const k of keys) {
      const a = this.archive.bySymbol[k], b = next.bySymbol[k]
      if (a === undefined || b === undefined ? a !== b : !drawingsEqual(a, b)) changed.add(k)
    }
    if (resetAllHistory) {
      for (const k of this.histories.keys()) changed.add(k)
      this.histories.clear()
    } else {
      for (const k of changed) this.histories.delete(k)
    }
    this.archive = next
    if (changed.size > 0) this.post({ kind: 'replaced', keys: changed })
  }

  /** 单独换一桶，撤销栈清掉；不管值变没变都算一次替换。 */
  replaceBucket(items: Drawing[], symbol: string): void {
    const key = canonicalInstrument(symbol)
    this.archive.set(key, items)
    this.histories.delete(key)
    this.post({ kind: 'replaced', keys: new Set([key]) })
  }

  /** 不进撤销栈、不发通知地把一桶摆成 items（只给没绑宿主的图用）。 */
  mirror(items: Drawing[], symbol: string): void {
    this.archive.set(canonicalInstrument(symbol), items)
  }

  // ---------------------------------------------------------- 观察

  /** 订阅变化；同一个 owner 再订一次会覆盖上一次。 */
  observe(owner: object, handler: (c: DrawingBookChange) => void): void {
    this.stopObserving(owner)
    this.observers.push({ owner, handler })
  }

  stopObserving(owner: object): void {
    this.observers = this.observers.filter(o => o.owner !== owner)
  }

  private post(change: DrawingBookChange): void {
    for (const o of this.observers.slice()) o.handler(change)
  }
}
