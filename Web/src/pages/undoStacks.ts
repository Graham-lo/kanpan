/* Hkline Web · 画线撤销栈：一只品种一份（同 TradingView：⌘Z 只退当前格这只品种的改动，
 * 不会跨品种把别的格子刚画的线退掉）。纯数据结构，页面（pages/chart.ts）负责快照与恢复 */

/** 每只品种最多记这么多步，再早的丢掉 */
export const UNDO_CAP = 200

export class UndoBySymbol<T extends { s: string }> {
  private m = new Map<string, { undo: T[]; redo: T[] }>()
  private of(s: string): { undo: T[]; redo: T[] } {
    let x = this.m.get(s)
    if (!x) this.m.set(s, x = { undo: [], redo: [] })
    return x
  }
  /** 记一步改动（改之前的样子）；这只品种的重做清空，别的品种不动 */
  push(u: T): void {
    const x = this.of(u.s)
    x.undo.push(u)
    if (x.undo.length > UNDO_CAP) x.undo.splice(0, x.undo.length - UNDO_CAP)
    x.redo.length = 0
  }
  /** 撤销这只品种的上一步：apply 把快照装回去并返回装之前的样子（进重做栈）。没得撤返回 false */
  undo(s: string, apply: (u: T) => T): boolean {
    const x = this.m.get(s), u = x?.undo.pop()
    if (!x || !u) return false
    x.redo.push(apply(u))
    return true
  }
  redo(s: string, apply: (u: T) => T): boolean {
    const x = this.m.get(s), u = x?.redo.pop()
    if (!x || !u) return false
    x.undo.push(apply(u))
    return true
  }
  depth(s: string): { undo: number; redo: number } {
    const x = this.m.get(s)
    return { undo: x?.undo.length ?? 0, redo: x?.redo.length ?? 0 }
  }
}
