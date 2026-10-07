/* Hkline Web · 主力订单流 · 刚看过的几只先留着（PC 与手机网页共用）
 *
 * 换品种原来是把旧的数据层整个停掉、状态清空，切回来又从头问品种表、连三家盘口、等快照、取历史。
 * 来回看两三只是常事：最近换走的那 1–2 只留着（连接不断、簿照常同步、只是不出帧，见 feed.park），
 * 切回来 take 出来接着用。上限写死：最多留 LIMIT 只、每只最多留 TTL_MS，过期的到点就停；
 * 页面藏到后台的那条「一分钟就停」规矩不变——调用方在那时 clear() 全停。
 */
export interface Parkable { park(): void; stop(): void }

/** 最多留几只（不算正在看的那只） */
export const KEEP_LIMIT = 2
/** 每只换走后最多留多久 */
export const KEEP_TTL_MS = 3 * 60_000

export interface KeeperOptions<T> {
  limit?: number
  ttlMs?: number
  now?: () => number
  /** 留着的那只被丢掉（挤出去 / 过期 / clear）时：已经 stop 过了，调用方顺手清它的附带状态 */
  onDrop?: (feed: T, key: string) => void
}

export class FeedKeeper<T extends Parkable> {
  private readonly kept = new Map<string, { feed: T; at: number }>()
  private timer: ReturnType<typeof setTimeout> | null = null
  private readonly limit: number
  private readonly ttl: number
  private readonly now: () => number
  constructor(private readonly opts: KeeperOptions<T> = {}) {
    this.limit = Math.max(0, opts.limit ?? KEEP_LIMIT)
    this.ttl = Math.max(0, opts.ttlMs ?? KEEP_TTL_MS)
    this.now = opts.now ?? Date.now
  }

  get size(): number { return this.kept.size }
  keys(): string[] { return [...this.kept.keys()] }
  has(key: string): boolean { return this.kept.has(key) }

  /** 换走了：先留着。同一个键已经留着一只（不该有）就把旧的停掉；超了上限停掉最早留下的。 */
  park(key: string, feed: T): void {
    const old = this.kept.get(key)
    if (old && old.feed !== feed) this.drop(key, old.feed)
    this.kept.delete(key)
    if (this.limit === 0) { feed.stop(); this.opts.onDrop?.(feed, key); return }
    feed.park()
    this.kept.set(key, { feed, at: this.now() })
    while (this.kept.size > this.limit) {
      const [k, e] = this.kept.entries().next().value as [string, { feed: T; at: number }]
      this.kept.delete(k)
      this.drop(k, e.feed)
    }
    this.arm()
  }

  /** 换回来：留着、没过期就交出来（不再归这里管）；没有是 null */
  take(key: string): T | null {
    this.sweep()
    const e = this.kept.get(key)
    if (!e) return null
    this.kept.delete(key)
    this.arm()
    return e.feed
  }

  /** 过期的停掉 */
  sweep(): void {
    const now = this.now()
    for (const [k, e] of [...this.kept]) {
      if (now - e.at >= this.ttl) { this.kept.delete(k); this.drop(k, e.feed) }
    }
  }

  /** 全停（数据层整体收掉：藏到后台满一分钟、指标关掉、页面走了） */
  clear(): void {
    if (this.timer) { clearTimeout(this.timer); this.timer = null }
    for (const [k, e] of [...this.kept]) { this.kept.delete(k); this.drop(k, e.feed) }
  }

  private drop(key: string, feed: T): void {
    feed.stop()
    this.opts.onDrop?.(feed, key)
  }

  /** 到最早那只过期的时刻再扫一次（没有留着的就不挂定时器） */
  private arm(): void {
    if (this.timer) { clearTimeout(this.timer); this.timer = null }
    if (!this.kept.size) return
    let first = Infinity
    for (const e of this.kept.values()) first = Math.min(first, e.at + this.ttl)
    this.timer = setTimeout(() => { this.timer = null; this.sweep(); this.arm() }, Math.max(0, first - this.now()) + 5)
  }
}
