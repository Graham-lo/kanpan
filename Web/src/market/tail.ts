/* Hkline Web · 断线 / 页面藏久了之后，把 K 线尾巴补回来
 *
 * 币安的 K 线推送只推「当前这一根」：断网、休眠、页面藏在后台（藏着时只保留当前格的推送）那段时间里
 * 收线的那几根永远不会再推来。连接回来后直接接着推，图上就会少几根（相邻两根隔了不止一个周期），
 * 断线前那一根也停在半截的开高低收上。手机网页连上即 resync（m/chart/index.ts resyncOnOpen），
 * iOS 也是连上就重取尾巴；PC 这边由页面在「重连」「藏久了回来」两个时机按这里算好的根数补一次。
 *
 * 纯逻辑，不碰 DOM 与网络，单测见 tests/kline-tail.test.ts。
 */
import type { Bar } from '../chart/calc'

/** 补尾巴一次最多取这么多根；断得更久就整段重取（limit ≤ 500 时币安权重 2） */
export const TAIL_MAX = 500
/** 页面藏了这么久再回来就补一次（藏着时非当前格的推送是退订的） */
export const HIDDEN_RESYNC_MS = 30_000

/** 从图上最后一根（它断线时还没收线，要重取）到现在要取几根；两根余量盖住时钟误差与正在收线的那一根 */
export function tailNeed(lastT: number, ivMs: number, now: number): number {
  if (!(ivMs > 0) || !Number.isFinite(lastT)) return 2
  return Math.max(2, Math.ceil((now - lastT) / ivMs) + 2)
}

/** 新取的尾巴里该并进图的那几根：开盘时间 ≥ 图上最后一根（同一根盖掉、晚的接上），按时间排好 */
export function tailFrom(bars: readonly Bar[], fresh: readonly Bar[]): Bar[] {
  const last = bars[bars.length - 1]
  if (!last) return []
  return fresh.filter(b => b.t >= last.t).sort((a, b) => a.t - b.t).map(b => ({ ...b }))
}

/** 什么时候该补：连接从「开着」掉下去又回到「开着」（第一次连上不算，那时各格正在取整段），
 *  或页面藏了 HIDDEN_RESYNC_MS 以上再回来 */
export class TailResync {
  private wasOpen = false
  private dropped = false
  private hiddenAt: number | null = null

  /** 连接状态变了；返回 true = 刚重连上，该补 */
  ws(state: string): boolean {
    if (state === 'open') {
      const again = this.wasOpen && this.dropped
      this.wasOpen = true; this.dropped = false
      return again
    }
    if (this.wasOpen) this.dropped = true
    return false
  }

  /** 页面可见性变了；返回 true = 藏久了刚回来，该补 */
  visibility(visible: boolean, now: number): boolean {
    if (!visible) { if (this.hiddenAt == null) this.hiddenAt = now; return false }
    const at = this.hiddenAt
    this.hiddenAt = null
    return at != null && now - at >= HIDDEN_RESYNC_MS
  }
}
