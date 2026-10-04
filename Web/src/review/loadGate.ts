/* Hkline Web · 复盘页整页取数的闸
 *
 * - 同一时刻只取一份；取的途中又被要求重取（从侧栏成交 / 记一笔跳进来要看刚传上的那条），
 *   记一笔「再来一次」，这一份回来后立刻再取，不把这次要求吞掉。
 * - 换账号（reset）就换一代：上一个账号在途的那份回来时作废，不往页面里写。
 */
export type GateEnd = 'stale' | 'again' | 'ok'

export interface LoadGate {
  /** 开始取：返回这一代的号；已经在取时返回 null（并记下回来后再取一次） */
  begin(): number | null
  /** 取回来了：stale = 换过账号，丢掉；again = 途中又被要求重取，丢掉这份马上再取；ok = 用它 */
  end(ep: number): GateEnd
  /** 这一代还作数吗（搜索进度这类边取边写的用） */
  live(ep: number): boolean
  readonly epoch: number
  readonly busy: boolean
  /** 换账号：作废在途的、清掉「再来一次」 */
  reset(): void
}

export function createLoadGate(): LoadGate {
  let epoch = 0, busy = false, again = false
  return {
    begin() { if (busy) { again = true; return null } busy = true; return epoch },
    end(ep) {
      if (ep !== epoch) return 'stale'
      busy = false
      if (again) { again = false; return 'again' }
      return 'ok'
    },
    live: ep => ep === epoch,
    get epoch() { return epoch },
    get busy() { return busy },
    reset() { epoch++; busy = false; again = false },
  }
}
