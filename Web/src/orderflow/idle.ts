/* Hkline Web · 订单流数据层什么时候收掉（PC 与手机网页共用）
 *
 * 数据层一开就是三家交易所的簿与成交好几条 WebSocket、外加每 500 ms 一次评估。
 * 离开图表页、或者整个标签页藏到后台（切了别的标签、锁了屏），过一分钟还没回来就收掉；
 * 一分钟之内回来不用重连。只认「离开」本身，不认停留多久之外的任何东西。
 */

/** 离开多久后停掉数据层 */
export const IDLE_STOP_MS = 60_000

/** 每一拍报一次「人在不在」，它说这一拍还要不要数据层 */
export class IdleGate {
  private since: number | null = null
  constructor(private readonly ms = IDLE_STOP_MS) {}
  /** away：不在图表页，或标签页藏着 */
  want(away: boolean, now: number): boolean {
    if (!away) { this.since = null; return true }
    if (this.since == null) this.since = now
    return now - this.since < this.ms
  }
}

const hiddenNow = (): boolean => typeof document !== 'undefined' && document.visibilityState === 'hidden'

/**
 * 标签页藏起来超过 ms 就调 stop()；之后回到前台调 back()（只有真停过才调）。返回解除监听的函数。
 * 手机网页的订单流口用它：页内切走由宿主 suspend / resume 管，这里只管整页藏到后台。
 */
export function stopWhenHiddenLong(stop: () => void, back: () => void, ms = IDLE_STOP_MS): () => void {
  if (typeof document === 'undefined' || typeof document.addEventListener !== 'function') return () => {}
  let timer: ReturnType<typeof setTimeout> | null = null
  let stopped = false
  const onVis = (): void => {
    if (hiddenNow()) {
      if (!timer && !stopped) timer = setTimeout(() => { timer = null; if (hiddenNow()) { stopped = true; stop() } }, ms)
      return
    }
    if (timer) { clearTimeout(timer); timer = null }
    if (stopped) { stopped = false; back() }
  }
  document.addEventListener('visibilitychange', onVis)
  if (hiddenNow()) onVis()
  return () => { document.removeEventListener('visibilitychange', onVis); if (timer) clearTimeout(timer) }
}
