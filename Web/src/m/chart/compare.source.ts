// 手机网页版 · 对比行情的数据源。照 KanpanData/Feed/CompareFeed.swift（取数、补齐、重试、按主序列对齐）
// 与 Kanpan/Kanpan/Compare/CompareModel.swift（按键集合起停、对齐缓存）写。
//
// 规矩与 iOS 相同：
//   - 最多三只，主图那只自己不算；认不出的交易所（新版本同步下来的键）留在偏好里，但绝不拿它的代号
//     去别家冒领行情——这里只认注册表里有行情面的那几家（2026-10-08 起：币安 `binance/usd_m/<代号>`、美元指数、
//     okx/usd_m、bybit/usd_m、hyperliquid/usd_m、coinbase/spot，代号形状按那一家的规矩），别的键不取、不画。
//   - 先拉右侧最新一页，够首屏即发布；再向左补到主序列起点。主图往左翻了历史，对比跟着补。
//   - 推送来的根按 openTime 接末根（与主图同一个 kline 流）；断线重连后重拉末页补缺口。
//   - 取不到按 2 s·2ⁿ 退避重试，最长 30 s。
//   - 对齐：按主序列的 openTime 一根一根对，缺根是 null，绝不拿邻根补。
//
// 这一层不碰图表状态；变了就叫 onChange，由 index.ts 节流后揉进 state.input.compare。

import type { Bar, Interval } from './series'
import { BarSeries } from './series'
import type { CompareSeries } from './state'
import type { Hex } from './paint'
import { validSymbol } from '../../sync/codec'
import { symbolOk } from '../../venues'
import { normKey } from './symbolKey'

/** 对比品种最多三只（Prefs.compareSymbols）。 */
export const MAX_COMPARE = 3
/** 一轮向左补历史最多翻几页（loadBars 一页 1500 根；主图也是一页一页往左翻，跟得上）。 */
export const COMPARE_MAX_PAGES = 8
const RETRY_BASE_MS = 2_000
const RETRY_MAX_MS = 30_000

export type CompareLoad = (symbol: string, iv: Interval, endTime: number | null) => Promise<Bar[] | null>

/** 对比键 → 网页里取数用的品种键：`binance/usd_m/ETHUSDT` → `ETHUSDT`、`macro/index/DXY` → `DXY`、
 *  `okx/usd_m/ETHUSDT` → 原样（注册表里那一家认得这个代号形状才算）；不认识的交易所 / 市场、写坏的键回 null。
 *  裸代号按币安合约认（InstrumentID.canonical）。 */
export function compareSymbolOf(key: string): string | null {
  const parts = key.trim().split('/')
  // 代号按币安那条规则（sync/codec.validSymbol，与服务端 binance_symbol 同一条）：「币安人生USDT」这种中文底名也认
  const sym = (s: string): string | null => { const u = s.toUpperCase(); return validSymbol(u) ? u : null }
  // 美元指数：键 macro/index/DXY（服务端 compare_key 白名单认它），网页里用裸代号 DXY 取数
  if (parts.length === 1 && parts[0].toUpperCase() === 'DXY') return 'DXY'
  if (parts.length === 3 && parts[0].toLowerCase() === 'macro' && parts[1].toLowerCase() === 'index') return parts[2].toUpperCase() === 'DXY' ? 'DXY' : null
  if (parts.length === 1) return sym(parts[0])
  if (parts.length !== 3) return null
  const venue = parts[0].toLowerCase(), market = parts[1].toLowerCase()
  if (venue === 'binance' && market === 'usd_m') return sym(parts[2])
  // 别家：venue / market 小写、代号大写（和 identity 的规范写法一致），过那一家登记的代号形状
  const k = `${venue}/${market}/${parts[2].toUpperCase()}`
  return parts[2] && symbolOk(k) ? k : null
}

/** 此刻真要取的几只：认得出、去重、去掉主图那只、最多三只（顺序按偏好）。 */
export function compareTargets(keys: readonly string[], mainSymbol: string): { key: string; symbol: string }[] {
  const out: { key: string; symbol: string }[] = []
  const main = normKey(mainSymbol)
  for (const key of keys) {
    const symbol = compareSymbolOf(key)
    if (!symbol || symbol === main || out.some(x => x.symbol === symbol)) continue
    out.push({ key, symbol })
    if (out.length === MAX_COMPARE) break
  }
  return out
}

/** CompareFeed.Snapshot.aligned(to:)：按主序列 openTime 对齐，缺根 null、非法价 null。 */
export function alignCompare(main: BarSeries, s: BarSeries | null): { open: (number | null)[]; close: (number | null)[] } {
  const n = main.count
  const open = new Array<number | null>(n).fill(null)
  const close = new Array<number | null>(n).fill(null)
  if (!s || s.interval !== main.interval || s.isEmpty) return { open, close }
  let j = s.firstIndexAtOrAfter(main.firstTime)
  for (let i = 0; i < n; i++) {
    const t = main.time(i)
    while (j < s.count && s.time(j) < t) j++
    if (j >= s.count) break
    if (s.time(j) === t) {
      const o = s.open[j], c = s.close[j]
      open[i] = Number.isFinite(o) && o > 0 ? o : null
      close[i] = Number.isFinite(c) && c > 0 ? c : null
    }
  }
  return { open, close }
}

interface Entry {
  key: string
  symbol: string
  series: BarSeries | null
  /** 向左已经翻到头（交易所没有更早的了） */
  historyDone: boolean
  loading: boolean
  /** 取的时候推送又动了末根：合并最新一页时不拿 REST 的旧末根盖掉 */
  liveRevision: number
  failures: number
  retry: ReturnType<typeof setTimeout> | null
}

export class CompareFeed {
  private entries: Entry[] = []
  private interval: Interval | null = null
  private main: BarSeries | null = null
  private generation = 0
  private disposed = false
  /** 对齐缓存（CompareModel.alignment）：主序列的戳或任一只对比序列的戳变了才重算。 */
  private cache: { mainRef: BarSeries; mainRev: number; revs: string; values: Map<string, { open: (number | null)[]; close: (number | null)[] }> } | null = null

  constructor(
    private readonly load: CompareLoad,
    private readonly onChange: () => void,
    private readonly timers: { set: typeof setTimeout; clear: typeof clearTimeout } = browserTimers(),
  ) {}

  /** 此刻在取的代号（大写），按偏好顺序。订推送用。 */
  get symbols(): string[] { return this.entries.map(e => e.symbol) }

  /**
   * 按键集合与主序列起停。keys 为空、主序列为空或还没对上周期就全停（CompareModel.configure）。
   * 同一组键、同一周期再调只按新的主序列往左补。
   */
  configure(keys: readonly string[], main: BarSeries | null, mainSymbol: string, interval: Interval): void {
    if (this.disposed) return
    const wanted = main && main.symbol === normKey(mainSymbol) && main.interval === interval && !main.isEmpty
      ? compareTargets(keys, mainSymbol) : []
    if (interval !== this.interval || !sameTargets(this.entries, wanted)) {
      this.stopAll()
      this.interval = interval
      this.entries = wanted.map(t => ({ ...t, series: null, historyDone: false, loading: false, liveRevision: 0, failures: 0, retry: null }))
      this.onChange()
    }
    this.main = wanted.length ? main : null
    for (const e of this.entries) this.schedule(e)
  }

  /** 推送来一根（与主图共用的 kline 流）。是对比品种的就接上，返回是否接住。 */
  upsert(symbol: string, iv: Interval, bar: Bar): boolean {
    if (iv !== this.interval) return false
    const e = this.entries.find(x => x.symbol === normKey(symbol))
    if (!e || !e.series) return false
    if (!(Number.isFinite(bar.close) && bar.close > 0)) return false
    const s = e.series
    // 断了一截（推送落后）：接不上就等下一次补末页，不拿一根孤零零的新根把中间的空白连起来。
    if (!s.isEmpty && bar.openTime > s.lastTime && s.step > 0 && bar.openTime - s.lastTime > s.step && iv !== '1M' && iv !== '1y') {
      this.refreshTail(e)
      return true
    }
    if (!s.upsert(bar)) return true
    e.liveRevision++
    this.onChange()
    return true
  }

  /** 断线重连 / 从后台回来：每只重拉末页补缺口（CompareFeed 的 pendingTail）。 */
  resync(): void {
    for (const e of this.entries) this.refreshTail(e)
  }

  /** CompareModel.series：按偏好顺序给出对齐好的几条；没取到的给空数组（图例照写名字、数值是「—」）。 */
  series(main: BarSeries, colorOf: (key: string) => Hex, nameOf: (key: string) => string): CompareSeries[] {
    if (!this.entries.length || !this.main || main !== this.main) return []
    const revs = this.entries.map(e => `${e.symbol}:${e.series?.revision ?? 0}`).join('|')
    if (!this.cache || this.cache.mainRef !== main || this.cache.mainRev !== main.revision || this.cache.revs !== revs) {
      const values = new Map<string, { open: (number | null)[]; close: (number | null)[] }>()
      for (const e of this.entries) values.set(e.key, alignCompare(main, e.series))
      this.cache = { mainRef: main, mainRev: main.revision, revs, values }
    }
    const values = this.cache.values
    return this.entries.map(e => {
      const v = values.get(e.key)
      return { key: e.key, name: nameOf(e.key), color: colorOf(e.key), open: v?.open ?? [], close: v?.close ?? [] }
    })
  }

  dispose(): void {
    this.disposed = true
    this.stopAll()
    this.entries = []
    this.main = null
  }

  // ------------------------------------------------------------ 取数

  private stopAll(): void {
    this.generation++
    for (const e of this.entries) if (e.retry) { this.timers.clear(e.retry); e.retry = null }
    this.cache = null
  }

  /** 这一只还缺什么就取什么：先最新一页，再往左补到主序列起点。 */
  private schedule(e: Entry): void {
    if (e.loading || e.retry || this.disposed) return
    const main = this.main
    if (!main || main.isEmpty) return
    if (!e.series) { void this.run(e, null); return }
    if (!e.historyDone && e.series.firstTime > main.firstTime) void this.run(e, e.series.firstTime)
  }

  private refreshTail(e: Entry): void {
    if (e.loading || e.retry || this.disposed || !this.main) return
    void this.run(e, null)
  }

  /** endTime 为 null：最新一页（首取或补末尾）；否则从 endTime 往左翻，最多 COMPARE_MAX_PAGES 页。 */
  private async run(e: Entry, endTime: number | null): Promise<void> {
    const gen = this.generation, iv = this.interval!
    e.loading = true
    let ok = true
    try {
      if (endTime == null) {
        const rev = e.liveRevision
        const bars = await this.load(e.symbol, iv, null)
        if (gen !== this.generation) return
        if (!bars) { ok = false; return }
        this.mergeLatest(e, iv, bars, rev !== e.liveRevision)
        this.onChange()
      } else {
        let end = endTime
        for (let page = 0; page < COMPARE_MAX_PAGES; page++) {
          const main = this.main
          const s = e.series
          if (!main || !s || s.firstTime <= main.firstTime) break
          const bars = await this.load(e.symbol, iv, end)
          if (gen !== this.generation) return
          if (!bars) { ok = false; return }
          const before = s.count
          s.prepend(bars)
          if (!bars.length || s.count === before) { e.historyDone = true; break }
          this.onChange()
          end = s.firstTime
        }
      }
    } finally {
      if (gen === this.generation) {
        e.loading = false
        if (ok) { e.failures = 0; this.schedule(e) } else this.backoff(e)
      }
    }
  }

  private mergeLatest(e: Entry, iv: Interval, bars: Bar[], keepLiveTail: boolean): void {
    const valid = bars.filter(b => Number.isFinite(b.openTime) && Number.isFinite(b.close) && b.close > 0)
    const s = e.series
    if (!valid.length) { if (!s) e.series = BarSeries.empty(e.symbol, iv); return }
    // 取的这一趟里推送已经把末根往前走了：REST 那一根是旧的，推送的为准（整条换与接尾两条路都要守）
    const live = keepLiveTail && s && !s.isEmpty ? s.bar(s.count - 1) : null
    const first = valid[0].openTime
    const gap = s && !s.isEmpty && first > s.lastTime + (iv === '1M' || iv === '1y' ? 32 * 86_400_000 : s.step)
    let out: BarSeries
    if (!s || s.isEmpty || gap || first <= s.firstTime) {
      // 首取、离开太久接不上（中间那段不拿直线连）、或者这一页已经盖住手上的全部：整条换，更早的下一轮再往左补
      out = e.series = BarSeries.fromBars(e.symbol, iv, valid)
      e.historyDone = false
    } else {
      s.replaceSuffix(s.firstIndexAtOrAfter(first), valid)
      out = s
    }
    if (live && live.openTime >= out.lastTime) out.upsert(live)
  }

  private backoff(e: Entry): void {
    const wait = Math.min(RETRY_MAX_MS, RETRY_BASE_MS * 2 ** e.failures)
    e.failures = Math.min(e.failures + 1, 10)
    const gen = this.generation
    e.retry = this.timers.set(() => {
      e.retry = null
      if (gen !== this.generation || this.disposed) return
      if (!e.series) void this.run(e, null)
      else this.schedule(e)
    }, wait)
  }
}

function sameTargets(a: readonly Entry[], b: readonly { key: string; symbol: string }[]): boolean {
  return a.length === b.length && a.every((e, i) => e.key === b[i].key && e.symbol === b[i].symbol)
}

/** 浏览器的 setTimeout / clearTimeout 不能脱离 window 调（`timers.set(...)` 会以 timers 为 this，Safari/Chrome 报 Illegal invocation），包一层箭头。 */
function browserTimers(): { set: typeof setTimeout; clear: typeof clearTimeout } {
  return {
    set: ((fn: () => void, ms?: number) => setTimeout(fn, ms)) as typeof setTimeout,
    clear: ((id?: ReturnType<typeof setTimeout>) => clearTimeout(id)) as typeof clearTimeout,
  }
}
