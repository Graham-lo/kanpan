/* Hkline Web · 板块成分表的「持仓变化」列（24 小时持仓量变化，%）
 *
 * 没有整表接口：币安只有逐只的 /futures/data/openInterestHist（权重 1，另有 1000 次 / 5 分钟的 IP 限额），
 * 自家服务端 /v1/market/open-interest 也只给单只的当前持仓量、不给变化。所以只取「正在看的那个板块」的成员：
 *   · 取法和口径照图表页详情块的「持仓 24h」（market/rest.ts fetchDetail）：1 小时一点、取 25 个点，
 *     最新一点的持仓价值 / 24 小时前那一点 − 1；那一只刚在图表页取过详情就直接用它的数，不再发请求；
 *   · 一只取到的数留 5 分钟；同时最多 3 个在途，按表上的顺序从上往下取；一个板块最多取前 100 只；
 *   · 换板块 / 离开页面就把还没发出去的作废（alive），已经回来的照样留着下次用；
 *   · 非币安合约、取不到、限流冷却中：记成 null（格子写「—」），5 分钟后再试。
 */
import { REST, j, detailOf, isDefaultVenue, parseKey } from '../market'
import { ago } from '../util/clock'

export const OI_TTL_MS = 5 * 60_000
export const OI_MAX_PER_BOARD = 100
const PARALLEL = 3

/** 一串 openInterestHist 点 → 24 小时变化（%）；点不够、数不对给 null */
export function oiChangePct(rows: readonly { sumOpenInterestValue?: string | number }[] | null | undefined): number | null {
  if (!rows || rows.length < 2) return null
  const a = Number(rows[0].sumOpenInterestValue), b = Number(rows[rows.length - 1].sumOpenInterestValue)
  if (!Number.isFinite(a) || !Number.isFinite(b) || a <= 0) return null
  return (b / a - 1) * 100
}

const cache = new Map<string, { t: number; v: number | null }>()
/** 这一只的持仓变化：数（%）、null = 取不到、undefined = 还没取 */
export function oiChangeOf(symbol: string): number | null | undefined {
  const d = detailOf(symbol)
  const c = cache.get(symbol)
  if (d?.oiChg != null && Number.isFinite(d.oiChg) && (!c || d.t > c.t)) return d.oiChg
  return c?.v
}
const fresh = (symbol: string): boolean => {
  const d = detailOf(symbol)
  if (d?.oiChg != null && ago(d.t) < OI_TTL_MS) return true
  const c = cache.get(symbol)
  return !!c && ago(c.t) < OI_TTL_MS
}

let gen = 0
/** 正在跑的那一批（同一批成员 10 秒一次的重算再调进来时不重开）、在途的品种（新一批不重复发） */
let running = ''
const inflight = new Set<string>()
/** 取这一批（按给的顺序，最多前 100 只）里还没有或已过期的；每回来一只调一次 onUpdate。
 *  成员换了才作废上一批没发出去的；同一批还在跑就什么都不做 */
export function loadOiChanges(symbols: readonly string[], onUpdate: () => void): void {
  const list = symbols.slice(0, OI_MAX_PER_BOARD)
  const key = list.slice().sort().join(',')
  if (key === running) return
  const todo = list.filter(k => !fresh(k) && !inflight.has(k))
  if (!todo.length) return
  const my = ++gen
  running = key
  const alive = (): boolean => gen === my
  const queue: string[] = []
  for (const k of todo) {
    if (isDefaultVenue(k) && parseKey(k).market !== 'spot') queue.push(k)
    else cache.set(k, { t: Date.now(), v: null })
  }
  let left = PARALLEL
  const worker = async (): Promise<void> => {
    while (alive() && queue.length) {
      const k = queue.shift()!
      inflight.add(k)
      try {
        const rows = await j<{ sumOpenInterestValue: string }[]>(`${REST}/futures/data/openInterestHist?symbol=${k}&period=1h&limit=25`, 8000, true, alive)
        cache.set(k, { t: Date.now(), v: oiChangePct(rows) })
      } catch {
        // 排队时作废了（换了板块）：不记，下次轮到再取
        if (alive()) cache.set(k, { t: Date.now(), v: null })
      } finally { inflight.delete(k) }
      if (alive()) onUpdate()
    }
    if (--left === 0 && alive()) running = ''
  }
  for (let i = 0; i < PARALLEL; i++) void worker()
}
/** 离开页面：没发出去的作废 */
export function stopOiChanges(): void { gen++; running = '' }

/** 测试用 */
export function resetOiForTest(): void { gen++; running = ''; cache.clear(); inflight.clear() }
