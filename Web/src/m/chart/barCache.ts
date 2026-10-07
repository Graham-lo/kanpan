/* 手机网页版 · K 线：先取一小页、后台补满，与一份共用的最近几只缓存（体感：开图、换回来先有图）
 *
 * 1. 首屏只取 FIRST_PAGE（300）根：一屏最多也就画一两百根，1500 根的那一页在慢网上要多等好几百毫秒；
 *    上图之后再在后台往左补到 HISTORY_PAGE（1500），用户往左翻时多半已经补好了。
 * 2. 共用缓存（BarCache）：本页里各台引擎共用，按「品种|周期」记最近 BAR_MEM_KEYS 只的末段；
 *    其中最近 BAR_DISK_KEYS 只的末 FIRST_PAGE 根落盘（几十 KB），重开页先拿它画出来，再取最新一页接上。
 *    落盘那份只在「和马上要取的那一小页接得上」时才拿来用（离开太久的不拿：接不上要整条换，图会跳）。
 * 只给默认取数（币安 REST）用；复盘、测试换了 loadBars 的不碰。
 */
import type { Bar, Interval } from './series'
import { INTERVAL_STEP } from './series'

/** 首屏那一页 */
export const FIRST_PAGE = 300
/** 往左翻一页 / 后台补满到的根数 */
export const HISTORY_PAGE = 1500
export const BAR_CACHE_KEY = 'hkline-m-bars-v1'
/** 内存里记几只 */
export const BAR_MEM_KEYS = 12
/** 落盘几只 */
export const BAR_DISK_KEYS = 4

// ---------------------------------------------------------------- 取页规则（纯函数，测试直接测）

/** 这一页取到的比要的少：左边到头了 */
export const pageExhausted = (got: number, asked: number): boolean => got < asked

/**
 * 首屏那页上图之后要不要在后台往左补、补多少根：已有的不到 HISTORY_PAGE、左边还没到头就补到 HISTORY_PAGE。
 * firstPage 为 null（换了取数口的引擎）不补。
 */
export function backfillLimit(count: number, historyDone: boolean, firstPage: number | null): number | null {
  if (firstPage == null || historyDone || count <= 0 || count >= HISTORY_PAGE) return null
  return HISTORY_PAGE - count
}

/**
 * 缓存的末根离现在多远还拿来先画：马上要取的那一小页（limit 根）盖得住它的末根，才接得上（mergeLatest 走 replaceSuffix，不整条换）。
 * 留 20 根余量（取数路上又走了几根）。
 */
export function cacheConnects(lastOpenTime: number, iv: Interval, now: number, limit = FIRST_PAGE): boolean {
  const step = INTERVAL_STEP[iv]
  if (!(step > 0) || !(lastOpenTime > 0)) return false
  return now - lastOpenTime < step * Math.max(1, limit - 20)
}

// ---------------------------------------------------------------- 共用缓存

type Row = [number, number, number, number, number, number, number]
interface Disk { v: 1; at: number; e: { k: string; r: Row[] }[] }
type KV = Pick<Storage, 'getItem' | 'setItem'>

const toRow = (b: Bar): Row => [b.openTime, b.open, b.high, b.low, b.close, b.volume, Number.isFinite(b.takerBuy) ? b.takerBuy : -1]
const fromRow = (r: Row): Bar => ({ openTime: r[0], open: r[1], high: r[2], low: r[3], close: r[4], volume: r[5], takerBuy: r[6] < 0 ? NaN : r[6] })
const keyOf = (symbol: string, iv: Interval): string => `${symbol.toUpperCase()}|${iv}`

export class BarCache {
  /** 最近用的排在最后 */
  private mem = new Map<string, Bar[]>()
  private diskRead = false
  private timer: ReturnType<typeof setTimeout> | null = null

  constructor(
    private readonly store: () => KV | null = () => { try { return globalThis.localStorage ?? null } catch { return null } },
    private readonly clock: () => number = Date.now,
    /** 记下后多久落盘一次（连着换品种只写最后那次） */
    private readonly saveDelayMs = 1500,
  ) {}

  /** 记下一只的末段（拷一份：引擎手里那条序列还会被推送改） */
  put(symbol: string, iv: Interval, bars: readonly Bar[]): void {
    if (!bars.length) return
    this.loadDisk()
    const k = keyOf(symbol, iv)
    this.mem.delete(k)
    this.mem.set(k, bars.slice(-HISTORY_PAGE).map(b => ({ ...b })))
    while (this.mem.size > BAR_MEM_KEYS) this.mem.delete(this.mem.keys().next().value as string)
    this.scheduleSave()
  }

  /** 拿一份能先画的（拷一份）；接不上现在的不给 */
  take(symbol: string, iv: Interval, limit = FIRST_PAGE): Bar[] | null {
    this.loadDisk()
    const k = keyOf(symbol, iv)
    const bars = this.mem.get(k)
    if (!bars?.length) return null
    if (!cacheConnects(bars[bars.length - 1].openTime, iv, this.clock(), limit)) return null
    this.mem.delete(k)
    this.mem.set(k, bars)
    return bars.map(b => ({ ...b }))
  }

  has(symbol: string, iv: Interval): boolean { this.loadDisk(); return this.mem.has(keyOf(symbol, iv)) }

  /** 立刻落盘：最近 BAR_DISK_KEYS 只、各末 FIRST_PAGE 根 */
  saveNow(): void {
    if (this.timer) { clearTimeout(this.timer); this.timer = null }
    const kv = this.store()
    if (!kv || !this.mem.size) return
    const keys = [...this.mem.keys()].slice(-BAR_DISK_KEYS)
    const d: Disk = { v: 1, at: this.clock(), e: keys.map(k => ({ k, r: this.mem.get(k)!.slice(-FIRST_PAGE).map(toRow) })) }
    try { kv.setItem(BAR_CACHE_KEY, JSON.stringify(d)) } catch { /* 存满了：不落盘也照常能用 */ }
  }

  clear(): void { this.mem.clear(); if (this.timer) clearTimeout(this.timer); this.timer = null }

  private scheduleSave(): void {
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => { this.timer = null; this.saveNow() }, this.saveDelayMs)
  }

  /** 第一次用时把落盘那份读进来（内存里已有的更新，不被盖） */
  private loadDisk(): void {
    if (this.diskRead) return
    this.diskRead = true
    try {
      const raw = this.store()?.getItem(BAR_CACHE_KEY)
      if (!raw) return
      const d = JSON.parse(raw) as Disk
      if (d?.v !== 1 || !Array.isArray(d.e)) return
      const old = new Map(this.mem)
      this.mem.clear()
      for (const x of d.e) if (typeof x?.k === 'string' && Array.isArray(x.r) && x.r.length) this.mem.set(x.k, x.r.map(fromRow))
      for (const [k, v] of old) { this.mem.delete(k); this.mem.set(k, v) }
    } catch { /* 坏了就当没有 */ }
  }
}

/** 本页共用的那一份 */
export const sharedBars = new BarCache()
if (typeof addEventListener === 'function') {
  addEventListener('pagehide', () => sharedBars.saveNow())
}
