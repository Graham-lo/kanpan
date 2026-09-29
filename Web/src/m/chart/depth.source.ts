// 手机网页版 · 盘口（主图右缘五档）的数据源。照 iOS 的 MarketFeed（`.depth` 那一支）与
// KanpanNetwork/Binance/DTO.swift 的 DepthSnapshot 写。
//
// - 流：币安合约 `<symbol>@depth5@100ms`，走 `/public/stream`（2026-04 起深度类单独一条路由，
//   `/market/stream` 不推深度）。每一帧就是完整的前五档，不是增量——不拉 REST 快照、不合并本地簿，
//   照增量流去叠只会把同一份快照叠成越来越厚的假盘口。
// - 线路：只在「直连」上有。iOS 的网关线路（OKX 替身，hasMicrostructure = false）没有盘口，
//   网页版的网关 `/public/stream` 也不转深度（实测 1006），所以网关上照 iOS 不画、不连。
// - 帧按撮合时间 `T`（没有退 `E`）只收不比手上旧的；断线、换品种、关掉、切后台立刻交 null，
//   图上不留一份过期的盘口。
// - 断线按 1 s、2 s、4 s … 最长 15 s 退避重连；连上 8 秒一帧没有、或中途静默 10 秒也当断线。
//
// 它自己开一条小连接（一只品种一路流），不进共用的行情连接池：那边只处理 `/market/stream`。

import type { BookLevel, OrderBook } from './state'
import { makeOrderBook } from './state'

export const DEPTH_HOST = 'wss://fstream.binance.com/public/stream'
export const depthStream = (symbol: string): string => `${symbol.toLowerCase()}@depth5@100ms`
export const depthURL = (symbol: string): string => `${DEPTH_HOST}?streams=${depthStream(symbol)}`

const FIRST_FRAME_MS = 8_000
const SILENCE_MS = 10_000
const RETRY_BASE_MS = 1_000
const RETRY_MAX_MS = 15_000

const levels = (raw: unknown): BookLevel[] => {
  if (!Array.isArray(raw)) return []
  const out: BookLevel[] = []
  for (const row of raw) {
    if (!Array.isArray(row) || row.length < 2) continue
    out.push({ price: Number(row[0]), quantity: Number(row[1]) })
  }
  return out
}

/** 一帧推送（组合流外壳 `{stream, data}` 或裸事件都认）→ 五档；不是这只、不是深度帧回 null。 */
export function parseDepthFrame(symbol: string, raw: unknown): OrderBook | null {
  if (!raw || typeof raw !== 'object') return null
  const outer = raw as { stream?: unknown; data?: unknown }
  const d = (outer.data && typeof outer.data === 'object' ? outer.data : raw) as { e?: unknown; s?: unknown; b?: unknown; a?: unknown; T?: unknown; E?: unknown }
  if (d.e !== undefined && d.e !== 'depthUpdate') return null
  if (!Array.isArray(d.b) && !Array.isArray(d.a)) return null
  const sym = symbol.toUpperCase()
  if (typeof d.s === 'string' && d.s.toUpperCase() !== sym) return null
  const time = Number.isFinite(Number(d.T)) && Number(d.T) > 0 ? Number(d.T) : Number.isFinite(Number(d.E)) ? Number(d.E) : 0
  return makeOrderBook(sym, time, levels(d.b), levels(d.a))
}

export interface DepthSocket {
  onopen: ((ev: unknown) => void) | null
  onmessage: ((ev: { data: unknown }) => void) | null
  onclose: ((ev: unknown) => void) | null
  onerror: ((ev: unknown) => void) | null
  close(): void
}

export interface DepthFeedOptions {
  /** 造连接（测试换成假的）；默认浏览器 WebSocket。 */
  connect?: (url: string) => DepthSocket
  timers?: { set: typeof setTimeout; clear: typeof clearTimeout }
  now?: () => number
}

export class DepthFeed {
  private symbol: string | null = null
  private on = false
  private direct = true
  private visible = true
  private sock: DepthSocket | null = null
  private book: OrderBook | null = null
  private failures = 0
  private retry: ReturnType<typeof setTimeout> | null = null
  private watchdog: ReturnType<typeof setTimeout> | null = null
  private lastFrame = 0
  private gotFrame = false
  private disposed = false
  private readonly connect: (url: string) => DepthSocket
  private readonly timers: { set: typeof setTimeout; clear: typeof clearTimeout }
  private readonly now: () => number

  constructor(private readonly onBook: (b: OrderBook | null) => void, o: DepthFeedOptions = {}) {
    this.connect = o.connect ?? (url => new WebSocket(url) as unknown as DepthSocket)
    this.timers = o.timers ?? browserTimers()
    this.now = o.now ?? Date.now
  }

  /** 此刻手上的五档（没有是 null）。 */
  get current(): OrderBook | null { return this.book }
  /** 是不是正连着（测试与排障用）。 */
  get connected(): boolean { return this.sock != null }

  /** 要不要、哪只；direct = 此刻是不是直连线路。 */
  setWanted(on: boolean, symbol: string, direct: boolean): void {
    const sym = symbol.toUpperCase()
    const changed = on !== this.on || sym !== this.symbol || direct !== this.direct
    this.on = on; this.symbol = sym; this.direct = direct
    if (changed) this.restart()
  }

  /** 页面切后台：断开并清掉；回前台重连。 */
  setVisible(visible: boolean): void {
    if (visible === this.visible) return
    this.visible = visible
    this.restart()
  }

  dispose(): void {
    this.disposed = true
    this.teardown()
    this.book = null
  }

  // ------------------------------------------------------------

  private get active(): boolean { return !this.disposed && this.on && this.direct && this.visible && !!this.symbol }

  private restart(): void {
    this.teardown()
    this.failures = 0
    this.publish(null)
    if (this.active) this.open()
  }

  private publish(b: OrderBook | null): void {
    if (b === this.book) return
    this.book = b
    this.onBook(b)
  }

  private teardown(): void {
    if (this.retry) { this.timers.clear(this.retry); this.retry = null }
    if (this.watchdog) { this.timers.clear(this.watchdog); this.watchdog = null }
    const s = this.sock
    this.sock = null
    if (s) {
      s.onopen = s.onmessage = s.onclose = s.onerror = null
      try { s.close() } catch { /* 已经关了 */ }
    }
  }

  private open(): void {
    const sym = this.symbol!
    let sock: DepthSocket
    try { sock = this.connect(depthURL(sym)) } catch { this.scheduleRetry(); return }
    this.sock = sock
    this.gotFrame = false
    this.lastFrame = this.now()
    sock.onmessage = ev => {
      if (this.sock !== sock) return
      let raw: unknown
      try { raw = typeof ev.data === 'string' ? JSON.parse(ev.data) : null } catch { return }
      const b = parseDepthFrame(sym, raw)
      if (!b) return
      this.gotFrame = true
      this.failures = 0
      this.lastFrame = this.now()
      // 乱序帧：比手上旧的不收（MarketModel：time >= depth.time）
      if (this.book && this.book.symbol === b.symbol && b.time < this.book.time) return
      this.publish(b)
    }
    sock.onclose = () => { if (this.sock === sock) this.lost() }
    sock.onerror = () => { if (this.sock === sock) this.lost() }
    this.arm()
  }

  /** 看门狗：首帧 8 s、之后静默 10 s 算断。时限按醒来那一刻「收没收到过帧」取，下一次掐在最后一帧 + 时限上。 */
  private arm(): void {
    if (this.watchdog) this.timers.clear(this.watchdog)
    const limit = () => (this.gotFrame ? SILENCE_MS : FIRST_FRAME_MS)
    this.watchdog = this.timers.set(() => {
      this.watchdog = null
      if (!this.sock) return
      if (this.now() - this.lastFrame >= limit()) { this.lost(); return }
      this.arm()
    }, Math.max(1, this.lastFrame + limit() - this.now()))
  }

  private lost(): void {
    this.teardown()
    this.publish(null)
    this.scheduleRetry()
  }

  private scheduleRetry(): void {
    if (!this.active || this.retry) return
    const wait = Math.min(RETRY_MAX_MS, RETRY_BASE_MS * 2 ** this.failures)
    this.failures = Math.min(this.failures + 1, 10)
    this.retry = this.timers.set(() => {
      this.retry = null
      if (this.active && !this.sock) this.open()
    }, wait)
  }
}

/** 浏览器的 setTimeout / clearTimeout 不能脱离 window 调（`timers.set(...)` 会以 timers 为 this，Safari/Chrome 报 Illegal invocation），包一层箭头。 */
function browserTimers(): { set: typeof setTimeout; clear: typeof clearTimeout } {
  return {
    set: ((fn: () => void, ms?: number) => setTimeout(fn, ms)) as typeof setTimeout,
    clear: ((id?: ReturnType<typeof setTimeout>) => clearTimeout(id)) as typeof clearTimeout,
  }
}
