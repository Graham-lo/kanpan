/* Hkline Web · 最近看过的 K 线留在本机
 *
 * 刷新、关了再开时，图先拿上次的那段摆出来，再照断线重连那条路（pages/chart.ts resyncTail）只补这段时间收的几根，
 * 不再对着空画布等 1500 根整段回来。只留最近看过的「品种 | 周期」各最后 300 根：
 *   · IndexedDB（hkline-klines）：最多 40 段，每段约 19 KB（8 个数一根），合计 1 MB 以内；
 *   · 浏览器不给 IndexedDB 时退到 localStorage：只留 8 段（和自选、画线那份存档同一块 5 MB，不多占）。
 * 写不进去就算了——它只是让下次开得快一点。成交额、主动买入额照存，持仓量不存（开图后照常补）。
 */
import type { Bar } from '../chart/calc'

export const DISK_BARS = 300
export const DISK_KEYS = 40
export const DISK_KEYS_LS = 8
export const KLINE_LS_KEY = 'hkline-klines-v1'
const DB = 'hkline-klines', STORE = 'bars'
const F = 8   // t o h l c v tb bv
/** 记下之后多久落盘：攒一下同一拍里几格的写入；不能拖太久——关页那一刻起的 IndexedDB 事务浏览器不保证写完 */
export const FLUSH_MS = 800

export interface DiskRow { k: string; at: number; d: Float64Array | number[] }

/** 只留最后 n 根，压成一串数（读回来是同样的 Bar，缺的字段是 NaN → 读回 undefined） */
export function packBars(bars: readonly Bar[], n = DISK_BARS): Float64Array {
  const src = bars.length > n ? bars.slice(bars.length - n) : bars
  const a = new Float64Array(src.length * F)
  src.forEach((b, i) => {
    const o = i * F
    a[o] = b.t; a[o + 1] = b.o; a[o + 2] = b.h; a[o + 3] = b.l; a[o + 4] = b.c
    a[o + 5] = b.v ?? NaN; a[o + 6] = b.tb ?? NaN; a[o + 7] = b.bv ?? NaN
  })
  return a
}
export function unpackBars(a: ArrayLike<number>): Bar[] {
  const out: Bar[] = []
  for (let o = 0; o + F <= a.length; o += F) {
    const b: Bar = { t: a[o], o: a[o + 1], h: a[o + 2], l: a[o + 3], c: a[o + 4], v: a[o + 5] }
    if (!Number.isFinite(b.t) || !Number.isFinite(b.c)) return []
    if (!Number.isFinite(b.v)) b.v = 0
    if (Number.isFinite(a[o + 6])) b.tb = a[o + 6]
    if (Number.isFinite(a[o + 7])) b.bv = a[o + 7]
    out.push(b)
  }
  return out
}

/** 内存里的「最近看过」表：Map 的插入顺序就是新旧（读、写都挪到最后），超出 max 段扔最旧的 */
export class RecentBars {
  private m = new Map<string, { at: number; d: Float64Array }>()
  constructor(readonly max = DISK_KEYS, readonly n = DISK_BARS) {}
  get size(): number { return this.m.size }
  get(key: string): Bar[] | null {
    const e = this.m.get(key); if (!e) return null
    this.m.delete(key); this.m.set(key, e)
    const bars = unpackBars(e.d)
    return bars.length ? bars : null
  }
  has(key: string): boolean { return this.m.has(key) }
  clear(): void { this.m.clear() }
  /** 写一段；返回被挤掉的键 */
  put(key: string, bars: readonly Bar[], at: number): string[] {
    if (!bars.length) return []
    this.m.delete(key)
    this.m.set(key, { at, d: packBars(bars, this.n) })
    return this.trim()
  }
  /** 从盘上读回来的：按时间从旧到新插在前面，本会话已经写过的键不让旧的盖掉 */
  load(rows: readonly DiskRow[]): string[] {
    const fresh = [...this.m.entries()]
    this.m.clear()
    for (const r of [...rows].sort((a, b) => a.at - b.at)) {
      if (typeof r?.k !== 'string' || !r.d || typeof r.at !== 'number') continue
      this.m.set(r.k, { at: r.at, d: r.d instanceof Float64Array ? r.d : Float64Array.from(r.d) })
    }
    for (const [k, e] of fresh) { this.m.delete(k); this.m.set(k, e) }
    return this.trim()
  }
  row(key: string): DiskRow | null { const e = this.m.get(key); return e ? { k: key, at: e.at, d: e.d } : null }
  /** 新的在前 */
  rows(): DiskRow[] { return [...this.m.entries()].reverse().map(([k, e]) => ({ k, at: e.at, d: e.d })) }
  private trim(): string[] {
    const out: string[] = []
    while (this.m.size > this.max) { const k = this.m.keys().next().value as string; this.m.delete(k); out.push(k) }
    return out
  }
}

// ------------------------------------------------------------ 盘
export interface Backend { load(): Promise<DiskRow[]>; write(mem: RecentBars, keys: string[], drop: string[]): Promise<void> }

function lsOf(): Storage | null { try { return typeof localStorage === 'undefined' ? null : localStorage } catch { return null } }

export function lsBackend(store: Storage): Backend {
  return {
    async load() {
      try {
        const v = JSON.parse(store.getItem(KLINE_LS_KEY) ?? 'null') as { rows?: { k: string; at: number; d: number[] }[] } | null
        return Array.isArray(v?.rows) ? v!.rows : []
      } catch { return [] }
    },
    async write(mem) {
      // 整份重写，只留最近的几段
      const rows = mem.rows().slice(0, DISK_KEYS_LS).map(r => ({ k: r.k, at: r.at, d: Array.from(r.d) }))
      try { store.setItem(KLINE_LS_KEY, JSON.stringify({ rows })) } catch { try { store.removeItem(KLINE_LS_KEY) } catch { /* 隐私模式 */ } }
    },
  }
}

function req<T>(r: IDBRequest<T>): Promise<T> { return new Promise((res, rej) => { r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error) }) }
function idbBackend(db: IDBDatabase): Backend {
  return {
    async load() { return await req(db.transaction(STORE, 'readonly').objectStore(STORE).getAll()) as DiskRow[] },
    write(mem, keys, drop) {
      return new Promise(res => {
        try {
          const tx = db.transaction(STORE, 'readwrite'), os = tx.objectStore(STORE)
          for (const k of keys) { const r = mem.row(k); if (r) os.put(r) }
          for (const k of drop) os.delete(k)
          tx.oncomplete = tx.onerror = tx.onabort = () => res()
        } catch { res() }
      })
    },
  }
}
function openIdb(): Promise<IDBDatabase | null> {
  if (typeof indexedDB === 'undefined') return Promise.resolve(null)
  return new Promise(res => {
    try {
      const r = indexedDB.open(DB, 1)
      r.onupgradeneeded = () => { if (!r.result.objectStoreNames.contains(STORE)) r.result.createObjectStore(STORE, { keyPath: 'k' }) }
      r.onsuccess = () => res(r.result)
      r.onerror = r.onblocked = () => res(null)
    } catch { res(null) }
  })
}

// ------------------------------------------------------------ 对外
const mem = new RecentBars(DISK_KEYS)
let backend: Backend | null = null
let readyP: Promise<void> | null = null
let loaded = false
const dirty = new Set<string>(), dropped = new Set<string>()
let flushTimer: ReturnType<typeof setTimeout> | undefined

/** 读一次盘（会话内只读一次）；最多等 timeout 毫秒——盘慢就先不用它，读完了后面的开图照样用得上 */
export function klineDiskReady(timeout = 150): Promise<void> {
  readyP ??= (async () => {
    const db = await openIdb()
    if (db) backend = idbBackend(db)
    else { const ls = lsOf(); if (ls) backend = lsBackend(ls) }
    if (!backend) return
    for (const k of mem.load(await backend.load())) { dropped.add(k); dirty.delete(k) }
    if (dropped.size) scheduleFlush()
  })().catch(() => { /* 读不了就当没有 */ }).finally(() => { loaded = true })
  if (loaded) return readyP
  return Promise.race([readyP, new Promise<void>(r => setTimeout(r, timeout))])
}
export const klineDiskLoaded = (): boolean => loaded

const keyOf = (symbol: string, iv: string): string => `${symbol}|${iv}`
/** 上次留下的这一段（复制一份，改了不影响盘上那份）；没有是 null */
export function diskBars(symbol: string, iv: string): Bar[] | null { return mem.get(keyOf(symbol, iv)) }
/** 记下这一段的最新样子（只留最后 300 根），稍后统一落盘 */
export function keepBars(symbol: string, iv: string, bars: readonly Bar[], now = Date.now()): void {
  if (!bars.length) return
  const k = keyOf(symbol, iv)
  dirty.add(k); dropped.delete(k)
  for (const d of mem.put(k, bars, now)) { dropped.add(d); dirty.delete(d) }
  scheduleFlush()
}
function scheduleFlush(): void {
  if (flushTimer || typeof setTimeout === 'undefined') return
  flushTimer = setTimeout(() => { flushTimer = undefined; void flushBars() }, FLUSH_MS)
}
/** 立刻落盘（关页、切走时调） */
export async function flushBars(): Promise<void> {
  if (flushTimer) { clearTimeout(flushTimer); flushTimer = undefined }
  if (!loaded) { await readyP; if (!loaded) return }
  if (!backend || (!dirty.size && !dropped.size)) return
  const keys = [...dirty], drop = [...dropped]
  dirty.clear(); dropped.clear()
  await backend.write(mem, keys, drop)
}
/** 测试用 */
export function resetKlineDiskForTest(b: Backend | null = null): void {
  mem.clear()
  backend = b; readyP = b ? Promise.resolve() : null; loaded = !!b; dirty.clear(); dropped.clear()
  if (flushTimer) { clearTimeout(flushTimer); flushTimer = undefined }
}
