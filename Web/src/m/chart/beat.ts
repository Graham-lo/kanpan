// 图的一秒心跳（Kanpan/Kanpan/Main/ChartSession.swift 的 heartbeat）：倒计时时钟、外部副图（持仓量 / 多空比 / 主动买卖比 / 基差）
// 的到点刷新都挂在这一拍上。
//
// 两种情况下停：整个网页藏到后台（document.hidden），以及宿主把这张图收起来（行情页切到自选 / 板块 / 我的，
// 宿主调 pause）。之前只认前一种——切到别的页，图每秒照样 feed.refresh、重算覆盖层。
// 回来（两种都解除）时立刻补一拍，不等下一秒；离开超过 AWAY_RESYNC_MS 再叫一次 onReturn 补缺口
// （藏着的时候 K 线推送是退订的，最后一根停在离开那一刻）。

export const AWAY_RESYNC_MS = 5_000

export interface ChartBeatHooks {
  /** 每一拍。 */
  tick: () => void
  /** 停下来时（清掉倒计时用的 nowMs）。 */
  stopped: () => void
  /** 离开够久回来：补主图与对比的缺口。 */
  onReturn: () => void
  now?: () => number
}

export class ChartBeat {
  private timer: ReturnType<typeof setInterval> | null = null
  private paused = false
  private disposed = false
  private awayAt = 0

  constructor(private readonly hooks: ChartBeatHooks, private hidden: boolean, private readonly enabled = true) {
    this.sync()
  }

  get running(): boolean { return this.timer != null }
  get isPaused(): boolean { return this.paused }

  /** document.visibilitychange */
  setHidden(hidden: boolean): void { this.hidden = hidden; this.sync() }
  /** 宿主把图收起来（页面切走）。 */
  pause(): void { this.paused = true; this.sync() }
  /** 宿主把图亮出来：立刻补一拍。 */
  resume(): void { this.paused = false; this.sync() }

  dispose(): void {
    this.disposed = true
    this.stop()
  }

  private now(): number { return this.hooks.now?.() ?? Date.now() }

  private sync(): void {
    const want = this.enabled && !this.disposed && !this.paused && !this.hidden
    if (want) {
      if (this.timer != null) return
      const away = this.awayAt
      this.awayAt = 0
      this.hooks.tick()
      this.timer = setInterval(this.hooks.tick, 1000)
      if (away && this.now() - away > AWAY_RESYNC_MS) this.hooks.onReturn()
    } else {
      if (this.enabled && !this.disposed && !this.awayAt) this.awayAt = this.now()
      this.stop()
    }
  }

  private stop(): void {
    if (this.timer == null) return
    clearInterval(this.timer)
    this.timer = null
    this.hooks.stopped()
  }
}
