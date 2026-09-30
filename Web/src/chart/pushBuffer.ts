/* Hkline Web · K 线在路上时先攒着的推送
 *
 * 行情推送和 K 线 REST 并行：格子开始取 K 线时就给「品种 | 推送周期」开一个小缓冲，这期间推来的
 * K 线先存着（同一根只留最新一版，最多 PUSH_CAP 根）；K 线到了之后把缓冲里开盘时间 ≥ 最后一根的
 * 按顺序补上，再切回实时。换品种 / 周期、取失败、被后一次取数顶掉，缓冲都跟着撤。
 *
 * 纯逻辑，不碰 DOM，单测见 tests/push-buffer.test.ts。
 */
import type { Bar } from './calc'

export const PUSH_CAP = 64

export const pushKey = (symbol: string, streamIv: string): string => `${symbol.toUpperCase()}|${streamIv}`

/**
 * 把攒下的推送并进刚取到的 K 线（原地改 bars 并返回它）：
 *   比最后一根早的丢掉；和最后一根同一根的并进去（开高低收量盖掉，持仓量这类推送里没有的字段留着）；
 *   比最后一根晚的接在后面。没有 K 线就什么都不补（和实时时 updateBar 的口径一样）。
 */
export function alignPushes(bars: Bar[], pushes: readonly Bar[]): Bar[] {
  if (!bars.length) return bars
  for (const p of [...pushes].sort((a, b) => a.t - b.t)) {
    const last = bars[bars.length - 1]
    if (p.t < last.t) continue
    if (p.t === last.t) Object.assign(last, p)
    else bars.push({ ...p })
  }
  return bars
}

export class PushBuffer {
  private held = new Map<string, { n: number; bars: Map<number, Bar> }>()

  constructor(private readonly cap = PUSH_CAP) {}

  /** 有人在等这个 key 的 K 线：开始攒（引用计数，两格同品种同周期共用一份） */
  open(key: string): void {
    const h = this.held.get(key)
    if (h) h.n++
    else this.held.set(key, { n: 1, bars: new Map() })
  }

  /** 不等了：最后一个撒手就连缓冲一起扔掉 */
  release(key: string): void {
    const h = this.held.get(key)
    if (!h) return
    if (--h.n <= 0) this.held.delete(key)
  }

  holding(key: string): boolean { return this.held.has(key) }

  /** 推来一根：有人等就攒下（同一根只留最新），没人等就不管 */
  offer(key: string, bar: Bar): boolean {
    const h = this.held.get(key)
    if (!h) return false
    h.bars.delete(bar.t)
    h.bars.set(bar.t, { ...bar })
    while (h.bars.size > this.cap) {
      let oldest = Infinity
      for (const t of h.bars.keys()) if (t < oldest) oldest = t
      h.bars.delete(oldest)
    }
    return true
  }

  /** 取出开盘时间 ≥ fromT 的（按时间排好；不清空，同 key 的另一格还要用） */
  take(key: string, fromT: number): Bar[] {
    const h = this.held.get(key)
    if (!h) return []
    return [...h.bars.values()].filter(b => b.t >= fromT).sort((a, b) => a.t - b.t).map(b => ({ ...b }))
  }

  /** 缓冲里一共攒了几根（诊断用） */
  size(key?: string): number {
    if (key != null) return this.held.get(key)?.bars.size ?? 0
    let n = 0
    for (const h of this.held.values()) n += h.bars.size
    return n
  }

  /** 现在开着几个 key（验「不漏」用） */
  get keys(): number { return this.held.size }
}
