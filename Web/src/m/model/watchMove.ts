/* 手机网页版 · 自选波动提醒的判定（照 iOS Alerts/WatchMove.swift 逐条移植，纯函数 / 纯状态，单测直接造）
 *
 * 「自选里的品种短时间内涨跌得特别快时，发一条通知」：
 * - 每只品种按 1 分钟收盘价攒对数收益，最近 1440 根（一天）的绝对值取中位数，按 MAD 换成 5 分钟的 σ，
 *   门槛 = 5σ（百分数），夹在 0.5%…10%；不到 30 根时先用 1.5%。
 * - 看的是「现价比 5 分钟前那根的收盘价」，过了门槛响一次；回到门槛以内才重新上膛，
 *   同一个 5 分钟窗口里同一方向只响一次。
 * - 灵敏度倍数（个性化学习学到的，0.5…2）乘在门槛上。
 * 后台那一半在服务端（watch_move.rs，走推送）；网页没有推送，页面开着时由这里判。
 */

export const WM = {
  barMs: 60_000,
  windowMs: 300_000,
  fallback: 1.5,
  min: 0.5,
  max: 10,
  minReturns: 30,
  maxReturns: 1440,
  madScale: 1.4826,
} as const

export type MoveDirection = 'up' | 'down'

/** 一串 1 分钟对数收益 → 5 分钟门槛（百分数） */
export function autoThreshold(returns: readonly number[]): number {
  const tail = returns.slice(-WM.maxReturns).filter(Number.isFinite).map(Math.abs).sort((a, b) => a - b)
  if (tail.length < WM.minReturns) return WM.fallback
  const mid = tail.length >> 1
  const median = tail.length % 2 === 0 ? (tail[mid - 1] + tail[mid]) / 2 : tail[mid]
  const sigma5 = Math.sqrt(WM.windowMs / WM.barMs) * WM.madScale * median
  const percent = 5 * sigma5 * 100
  if (!Number.isFinite(percent)) return WM.fallback
  return Math.min(WM.max, Math.max(WM.min, percent))
}

/** 一只品种：分钟收盘、当前那根、收益序列、门槛 */
export class MoveSeries {
  closes = new Map<number, number>()
  currentOpen: number | null = null
  currentClose: number | null = null
  returns: number[] = []
  threshold: number = WM.fallback

  private commit(open: number, close: number): void {
    const fresh = !this.closes.has(open)
    this.closes.set(open, close)
    const prev = this.closes.get(open - WM.barMs)
    if (fresh && prev != null && prev > 0) {
      this.returns.push(Math.log(close / prev))
      if (this.returns.length > WM.maxReturns) this.returns.splice(0, this.returns.length - WM.maxReturns)
      this.threshold = autoThreshold(this.returns)
    }
  }

  /** 一笔价。返回「现价比 5 分钟前那根收盘」的涨跌（小数），没有参照就是 null */
  observe(barOpen: number, price: number, closed: boolean): number | null {
    if (!Number.isFinite(price) || price <= 0) return null
    if (this.currentOpen != null && barOpen < this.currentOpen) return null
    if (this.currentOpen != null && barOpen > this.currentOpen && this.currentClose != null) this.commit(this.currentOpen, this.currentClose)
    this.currentOpen = barOpen
    this.currentClose = price
    if (closed) this.commit(barOpen, price)
    const keepFrom = barOpen - 7 * WM.barMs
    for (const k of [...this.closes.keys()]) if (k < keepFrom) this.closes.delete(k)
    const ref = this.closes.get(barOpen - WM.windowMs)
    if (ref == null || !(ref > 0)) return null
    return price / ref - 1
  }

  /** 切后台：价断了，分钟收盘不再连续；收益序列留着（门槛不用重攒） */
  forgetPrices(): void {
    this.closes.clear()
    this.currentOpen = null
    this.currentClose = null
  }
}

/** 一只品种一个方向的闸：过门槛响一次，回到门槛以内才重新上膛；同一窗口只响一次 */
export class MoveGate {
  armed = true
  lastWindow: number | null = null
  pass(signed: number, threshold: number, window: number): boolean {
    if (signed < threshold) { this.armed = true; return false }
    if (!this.armed || this.lastWindow === window) return false
    this.armed = false
    this.lastWindow = window
    return true
  }
}

export interface MoveEvent { symbol: string; direction: MoveDirection; change: number; price: number; window: number }

export class MoveTracker {
  series = new Map<string, MoveSeries>()
  gates = new Map<string, MoveGate>()

  /** symbol 用规范键；sensitivity = 学到的倍数（没学到 1） */
  observe(symbol: string, barOpen: number, price: number, closed: boolean, sensitivity = 1): MoveEvent | null {
    let s = this.series.get(symbol)
    if (!s) { s = new MoveSeries(); this.series.set(symbol, s) }
    const change = s.observe(barOpen, price, closed)
    if (change == null) return null
    const factor = Number.isFinite(sensitivity) ? Math.min(2, Math.max(0.5, sensitivity)) : 1
    const limit = s.threshold * factor / 100
    const window = barOpen - (barOpen % WM.windowMs)
    let event: MoveEvent | null = null
    for (const direction of ['up', 'down'] as const) {
      const signed = direction === 'up' ? change : -change
      const key = symbol + '|' + direction
      let g = this.gates.get(key)
      if (!g) { g = new MoveGate(); this.gates.set(key, g) }
      // 两个方向的闸都要走一遍（回到门槛以内的那一侧要重新上膛），第一个过的出事件
      if (g.pass(signed, limit, window) && !event) event = { symbol, direction, change, price, window }
    }
    return event
  }

  /** 自选变了：不在里面的丢掉 */
  keep(symbols: Iterable<string>): void {
    const set = new Set(symbols)
    for (const k of [...this.series.keys()]) if (!set.has(k)) this.series.delete(k)
    for (const k of [...this.gates.keys()]) if (!set.has(k.slice(0, k.lastIndexOf('|')))) this.gates.delete(k)
  }

  forgetPrices(): void { this.series.forEach(s => s.forgetPrices()) }
}

/** 通知标题（照 iOS WatchMoveMonitor）：「BTC 五分钟涨 3.21%」 */
export function moveTitle(name: string, e: Pick<MoveEvent, 'direction' | 'change'>): string {
  return `${name} 五分钟${e.direction === 'up' ? '涨' : '跌'} ${Math.abs(e.change * 100).toFixed(2)}%`
}
export const moveNotifyId = (e: Pick<MoveEvent, 'symbol' | 'direction' | 'window'>): string => `move.${e.symbol}.${e.direction}.${e.window}`
