/* Hkline Web · 最近取过的整段 K 线（换布局集 / 切格数 / 来回换品种时复用，只补尾巴）
 *
 * 2026-10-07 压测（§50 第二节）：十六图与九图两套布局集来回切，每切一次十几格各取一整段 1500 根（币安权重 10），
 * 一分钟切七八次就把本地预算（fapi 1200 / 分钟，limit.ts）用完，后面几次有 7 格空着排队 35 秒。
 * 交易软件的通行做法（TradingView 的 series cache 同理）：同一只同一周期刚取过的整段留在内存里，
 * 再要时只向交易所补「从那份最后一根到现在」的尾巴（几根，权重 1），并进去就是一份完整的最新 K 线。
 *
 * · 只管「取最新一段」（没有 endTime）；往前翻页、回放取历史不走这里。
 * · 进出都拷一份：图会就地改最后一根（推送），缓存里的那份不能跟着变。
 * · 有上限（条数）与有效期；过期的、尾巴断得太长（超过 TAIL_MAX 根）的整段重取。
 * 纯逻辑（不碰网络），单测见 tests/kline-cache.test.ts；取数在 pages/chart.ts barsFor。
 */
import type { Bar } from '../chart/calc'
import { TAIL_MAX, tailFrom, tailNeed } from './tail'

/** 最多记几份（十六图两套布局集正好 32 只 × 周期；一份 1500 根约 0.2 MB） */
export const CACHE_MAX = 32
/** 多久之内的算「刚取过」 */
export const CACHE_TTL_MS = 10 * 60_000

const copy = (bars: readonly Bar[]): Bar[] => bars.map(b => ({ ...b }))

export class KlineCache {
  private m = new Map<string, { bars: Bar[]; at: number }>()
  constructor(private max = CACHE_MAX, private ttl = CACHE_TTL_MS) {}

  /** 记下一整段（拷一份）；超过上限丢最久没用的 */
  put(key: string, bars: readonly Bar[], now: number): void {
    if (!bars.length) return
    this.m.delete(key)
    this.m.set(key, { bars: copy(bars), at: now })
    while (this.m.size > this.max) this.m.delete(this.m.keys().next().value as string)
  }

  /** 还能用的那份要补几根尾巴；没有、过期、断得太长回 null（整段重取） */
  need(key: string, ivMs: number, now: number): number | null {
    const e = this.m.get(key)
    if (!e) return null
    if (now - e.at > this.ttl) { this.m.delete(key); return null }
    const n = tailNeed(e.bars[e.bars.length - 1].t, ivMs, now)
    return n > TAIL_MAX ? null : n
  }

  /** 把新取的尾巴并进缓存那份，返回拼好的整段（拷一份给图）。尾巴接不上（第一根比缓存最后一根还晚）回 null */
  merge(key: string, tail: readonly Bar[], now: number): Bar[] | null {
    const e = this.m.get(key)
    if (!e || !tail.length) return null
    const bars = e.bars, last = bars[bars.length - 1], len0 = bars.length
    if (Math.min(...tail.map(b => b.t)) > last.t) { this.m.delete(key); return null }
    for (const b of tailFrom(bars, tail)) {
      if (b.t === bars[bars.length - 1].t) bars[bars.length - 1] = b
      else bars.push(b)
    }
    // 留住原来的长度：只往后滚，不越攒越长
    if (bars.length > len0) bars.splice(0, bars.length - len0)
    this.m.delete(key)
    this.m.set(key, { bars, at: now })
    return copy(bars)
  }

  drop(key: string): void { this.m.delete(key) }
  get size(): number { return this.m.size }
}
