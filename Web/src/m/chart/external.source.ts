// 移植自 KanpanData/Sources/KanpanData/Feed/OISource.swift（restRange / fetchMetric / downsample / chartSeries 的近期那一段）
//
// 持仓量、多空比、主动买卖比、基差四条副图的外部数据。只走币安 REST 的近 30 天
// （`/futures/data/*` 本来就只给 30 天），iOS 那一段「更早的走网关归档」网页不做：
// 网页版副图的可视范围就是首屏那一页 K 线，30 天够用。
// 取数经 `market.j`：主机在 429 / 418 冷却里就不发，不会把 IP 打进封禁。

import { j, REST } from '../../market'
import type { IndicatorID } from '../indicator/ids'
import type { BarSeries, Interval } from './series'
import { ExternalSeries, bucketStart, stepMs } from './series'

export type ExternalID = 'OI' | 'LSR' | 'TAKER' | 'BASIS'
export const EXTERNAL_IDS: readonly ExternalID[] = ['OI', 'LSR', 'TAKER', 'BASIS']
export const isExternalID = (id: IndicatorID | string): id is ExternalID => (EXTERNAL_IDS as readonly string[]).includes(id)

export interface MetricPoint { time: number; value: number }

/** 币安 `/futures/data/*` 认的周期（Interval.oiPeriod）。更细的退到 5m，日线以上退到 1d。 */
const PERIODS = new Set(['5m', '15m', '30m', '1h', '2h', '4h', '6h', '12h', '1d'])
export function metricPeriod(iv: Interval): string {
  if (PERIODS.has(iv)) return iv
  return stepMs(iv) >= 86_400_000 ? '1d' : '5m'
}

/** 近 30 天（OISource.restWindowMs）。 */
export const REST_WINDOW_MS = 30 * 86_400_000
const PAGE = 500
const MAX_PAGES = 20

/** 同一时刻只留一条（后到为准），时间升序（OISource.dedup）。 */
export function dedup(pts: MetricPoint[]): MetricPoint[] {
  const m = new Map<number, number>()
  for (const p of pts) if (Number.isFinite(p.value)) m.set(p.time, p.value)
  return [...m.entries()].sort((a, b) => a[0] - b[0]).map(([time, value]) => ({ time, value }))
}

/** 降采样到周期：每桶取最后一条，时间戳打在桶头上；1m / 3m 比 5m 还细，原样返回（OISource.downsample）。 */
export function downsample(pts: MetricPoint[], iv: Interval): MetricPoint[] {
  if (!(stepMs(iv) > 5 * 60_000 || iv === '5m')) return pts
  if (!pts.length) return []
  const out: MetricPoint[] = []
  let cur: MetricPoint | null = null
  let curBucket = -Infinity
  for (const p of pts.slice().sort((a, b) => a.time - b.time)) {
    const b = bucketStart(p.time, iv)
    if (b !== curBucket) {
      if (cur) out.push({ time: curBucket, value: cur.value })
      curBucket = b
    }
    cur = p
  }
  if (cur) out.push({ time: curBucket, value: cur.value })
  return out
}

/** OISource.chartSeries：去重、降采样，步长至少 5 分钟、带桶周期。 */
export function chartSeries(raw: MetricPoint[], iv: Interval): ExternalSeries {
  const pts = downsample(dedup(raw), iv)
  return ExternalSeries.fromPoints(pts.map(p => ({ time: p.time, values: [p.value] })), Math.max(300_000, stepMs(iv)), iv)
}

type Row = Record<string, string | number>
function endpoint(id: ExternalID): { path: string; symbolKey: string; extra: string; pick: (r: Row) => number } {
  switch (id) {
    // 取币的个数（sumOpenInterest），和 iOS 同一个单位，副图读法不变
    case 'OI': return { path: '/futures/data/openInterestHist', symbolKey: 'symbol', extra: '', pick: r => +r.sumOpenInterest }
    case 'LSR': return { path: '/futures/data/globalLongShortAccountRatio', symbolKey: 'symbol', extra: '', pick: r => +r.longShortRatio }
    case 'TAKER': return { path: '/futures/data/takerlongshortRatio', symbolKey: 'symbol', extra: '', pick: r => +r.buySellRatio }
    // 基差存百分数
    case 'BASIS': return { path: '/futures/data/basis', symbolKey: 'pair', extra: '&contractType=PERPETUAL', pick: r => +r.basisRate * 100 }
  }
}

/**
 * 取 [from, to] 这一段（截在近 30 天里），从右往左一页 500 条翻，最多 20 页。
 * 半路断了就用已经到手的几页（OISource.restRange 的同一条规矩）。
 * 主动买卖比的「当前这一桶」还没成型，不要（fetchMetric 里 `$0.time < currentBucket`）。
 */
export async function fetchMetric(id: ExternalID, symbol: string, iv: Interval, from: number, to: number,
  now = Date.now(), fetcher: <T>(url: string) => Promise<T> = u => j(u, 10000)): Promise<{ points: MetricPoint[]; complete: boolean }> {
  const lower = Math.max(from, now - REST_WINDOW_MS)
  if (lower > to) return { points: [], complete: true }
  const e = endpoint(id)
  const period = metricPeriod(iv)
  const sampleIv: Interval = stepMs(iv) < 300_000 ? '5m' : stepMs(iv) > 86_400_000 ? '1d' : iv
  const currentBucket = bucketStart(now, sampleIv)
  const out: MetricPoint[] = []
  let end = Math.min(to, now)
  let complete = false
  for (let k = 0; k < MAX_PAGES; k++) {
    let rows: Row[]
    try {
      rows = await fetcher<Row[]>(`${REST}${e.path}?${e.symbolKey}=${symbol}&period=${period}&limit=${PAGE}&endTime=${Math.floor(end)}${e.extra}`)
    } catch { break }
    if (!Array.isArray(rows) || !rows.length) { complete = true; break }
    const page = rows.map(r => ({ time: +r.timestamp, value: e.pick(r) })).filter(p => Number.isFinite(p.time))
    page.sort((a, b) => a.time - b.time)
    out.push(...page.filter(p => p.time >= lower && p.time <= to && (id !== 'TAKER' || p.time < currentBucket)))
    const first = page[0]
    if (!first || page.length < PAGE || first.time <= lower) { complete = true; break }
    end = first.time - 1
  }
  // 和 Swift 一样交回按本周期降采样过的点（OISource.fetchMetric 末尾的 downsample(dedup(points))）：
  // 周线 / 月线 / 年线问的是 1d 档，不降采样就把每天一条的原始点整批存进 ExternalFeed（画图前 chartSeries 还会再降一次，结果不变）。
  return { points: downsample(dedup(out), iv), complete }
}

/**
 * 一只品种一个周期的外部序列簿。宿主开哪几条副图就要哪几条；到货回调里把整份交回去，
 * 宿主按 id 塞进 `state.input.oi / external`。
 */
export class ExternalFeed {
  private raw = new Map<ExternalID, MetricPoint[]>()
  /** 每条已经完整问过的时间段（OISource 的 have）：往左翻只取左边露出来的那截，60 秒续一次只取尾巴。 */
  private covered = new Map<ExternalID, { from: number; to: number }>()
  private inflight = new Set<ExternalID>()
  private lastRefresh = new Map<ExternalID, number>()
  private alive = true

  constructor(readonly symbol: string, readonly interval: Interval,
    private readonly onSeries: (id: ExternalID, s: ExternalSeries) => void,
    private readonly fetch: typeof fetchMetric = fetchMetric) {}

  dispose(): void { this.alive = false }

  /**
   * 这几条要有数（OISource.missingSegments）：没取过、或和手里那段不沾边的整段取；
   * 主图往左翻了就补左边露出来的那截；右边只续尾巴（最后一两桶的统计值还在动）。
   */
  want(ids: readonly ExternalID[], series: BarSeries, now = Date.now()): void {
    if (!this.alive || series.isEmpty) return
    const step = stepMs(this.interval)
    const want = { from: series.firstTime - step, to: series.lastTime + step }
    for (const id of ids) {
      if (this.inflight.has(id)) continue
      const have = this.covered.get(id)
      const segments: { from: number; to: number }[] = []
      if (!have || want.from > have.to || want.to < have.from) segments.push(want)
      else {
        if (want.from < have.from) segments.push({ from: want.from, to: have.from })
        const pts = this.raw.get(id)
        const lastPoint = pts?.length ? pts[pts.length - 1].time : have.to
        segments.push({ from: Math.max(want.from, Math.min(have.to, lastPoint) - step), to: want.to })
      }
      void this.load(id, segments, now)
    }
  }

  /** 心跳里调：每条最多一分钟补一次最近那段（OISource.refreshOIIfNeeded 的节奏）。 */
  refresh(ids: readonly ExternalID[], series: BarSeries, now = Date.now()): void {
    const due = ids.filter(id => this.raw.has(id) && now - (this.lastRefresh.get(id) ?? 0) >= 60_000)
    if (due.length) this.want(due, series, now)
  }

  private async load(id: ExternalID, segments: { from: number; to: number }[], now: number): Promise<void> {
    this.inflight.add(id)
    this.lastRefresh.set(id, now)
    try {
      const points: MetricPoint[] = []
      for (const seg of segments) {
        const r = await this.fetch(id, this.symbol, this.interval, seg.from, seg.to, now)
        if (!this.alive) return
        points.push(...r.points)
        // 只把问完整的段记进 have：断在半路的下次还要再问
        if (r.complete) {
          const have = this.covered.get(id)
          this.covered.set(id, have && seg.from <= have.to && seg.to >= have.from
            ? { from: Math.min(have.from, seg.from), to: Math.max(have.to, seg.to) }
            : have ?? { from: seg.from, to: seg.to })
        }
      }
      const merged = dedup([...(this.raw.get(id) ?? []), ...points])
      const before = this.raw.get(id)
      this.raw.set(id, merged)
      if (!before || before.length !== merged.length || before[before.length - 1]?.value !== merged[merged.length - 1]?.value) {
        this.onSeries(id, chartSeries(merged, this.interval))
      } else if (!before.length && !merged.length) {
        this.onSeries(id, chartSeries([], this.interval))
      }
    } finally {
      this.inflight.delete(id)
    }
  }
}
