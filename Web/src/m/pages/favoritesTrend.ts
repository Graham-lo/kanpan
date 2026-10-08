/* 手机网页版 · 自选行 24 小时走势的取数与缓存（照 iOS QuoteBook.onTrend / SymbolPickerModel.setTrend）
 *
 * 只取露面那几行：自选页用 IntersectionObserver 盯着行，进了视口（上下各多看半屏）才排进队列。
 * 一只品种一份 97 根 15 分钟线截出来的走势（不到 1KB），最多记 40 只（照 iOS historyCapacity），挤掉的下次露面再取。
 * 十五分钟内不重取（尾点本来就接实时价，十五分钟只是让窗口往前挪一格）；没取成的 30 秒后再试。
 * 同时最多 3 趟在途，走限流预算的后台那一截（background），不跟图表抢额度。
 * 和图表那份 K 线缓存（m/chart/barCache.ts）分开记：那是 12 格的 LRU，塞走势进去会把图挤掉。
 */
import { klines } from '../../market'
import { ago } from '../../util/clock'
import { makeTrend, TREND_CAPACITY, TREND_IV, type FavoriteTrend } from '../model/favoriteTrend'

interface Entry { at: number; trend: FavoriteTrend }
const book = new Map<string, Entry>()
/** 上一趟发出去的时刻（成没成都记）：控制重取间隔 */
const asked = new Map<string, number>()
const inflight = new Set<string>()
const queue: string[] = []
export const TREND_FRESH_MS = 15 * 60_000
const RETRY_MS = 30_000
const CAPACITY = 40
const CONCURRENCY = 3

/** 记着的走势（过了新鲜期也照样给：总比空着好，下一趟取回来原地换掉） */
export function trendOf(sym: string): FavoriteTrend | null { return book.get(sym)?.trend ?? null }

function due(sym: string, now = Date.now()): boolean {
  if (inflight.has(sym)) return false
  const at = asked.get(sym)
  if (at == null) return true
  return ago(at, now) >= (book.has(sym) ? TREND_FRESH_MS : RETRY_MS)
}

/** 把这几只排进队列（已经新鲜 / 在途的跳过）。wanted：排到它时还要不要（滚出视口、页面收起、开关关了就不发）；
 *  loaded：取到一份新的走势时回调 */
export function requestTrends(syms: readonly string[], wanted: (sym: string) => boolean, loaded: (sym: string) => void): void {
  for (const s of syms) if (due(s) && !queue.includes(s)) queue.push(s)
  pump(wanted, loaded)
}

function pump(wanted: (sym: string) => boolean, loaded: (sym: string) => void): void {
  while (inflight.size < CONCURRENCY && queue.length) {
    const sym = queue.shift()!
    if (!wanted(sym) || !due(sym)) continue
    inflight.add(sym)
    asked.set(sym, Date.now())
    void klines(sym, TREND_IV, undefined, TREND_CAPACITY, false, true, () => wanted(sym)).then(r => {
      inflight.delete(sym)
      const t = r.ok ? makeTrend(r.bars, Date.now()) : null
      if (t) {
        book.delete(sym)
        book.set(sym, { at: Date.now(), trend: t })
        while (book.size > CAPACITY) { const k = book.keys().next().value!; book.delete(k); asked.delete(k) }
        loaded(sym)
      } else if (!r.ok && !wanted(sym)) {
        // 排队时被作废（滚走了 / 页面收起）：不算一次失败，下次露面立刻再取
        asked.delete(sym)
      }
      pump(wanted, loaded)
    })
  }
}

/** 测试用 */
export function _resetTrends(): void { book.clear(); asked.clear(); inflight.clear(); queue.length = 0 }

// ---------------------------------------------------------------- 药丸闪（iOS ChangePill.flash）
const flashTimers = new WeakMap<Element, number>()
/** 这一行的药丸按这一口的方向闪一下：底上垫一层 25% 的涨 / 跌色，PILL_FLASH_MS 后摘掉、CSS 淡回去 */
export function flashPill(row: Element, dir: 'up' | 'down', ms: number): void {
  const pill = row.querySelector('.m-pill'); if (!pill) return
  pill.classList.remove('fl-up', 'fl-down')
  pill.classList.add('fl-' + dir)
  clearTimeout(flashTimers.get(pill))
  flashTimers.set(pill, window.setTimeout(() => pill.classList.remove('fl-up', 'fl-down'), ms))
}
