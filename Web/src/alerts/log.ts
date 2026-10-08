/* Hkline Web · 提醒日志（响过的提醒一条一条记下来；照 iOS Alerts/AlertLog.swift，协议 docs/提醒日志-协议-2026-10-05.md）
 *
 * 提醒「响一次就删」，本机响过就没了，所以「响过什么」只有服务端那份账（kanpan-api alert_log，留 30 天）：
 *   - GET  /v1/alerts/log?limit=200 → {data:{records:[{id,alertId,kind,symbol,title,condition,firedAt,firedPrice}]}}（裸的 {records} 也认）
 *   - DELETE /v1/alerts/log → 204（清空）
 *   - 404 = 服务端还没这条路：当「暂无记录」，不当故障；401 / 没登录：「登录后可查看」
 * 拉到的按账号存一份在本机（200 条几十 KB），断网 / 服务器宕机时照摆上一次那份（云端只是同步通道）。
 * 手机网页版（m/pages/alertHub.ts）与电脑网页版（alerts/panel.ts 的「日志」分段）共用这一份。
 * 上半截是纯函数（拆包、排序、按上海时间分天、写时刻与第二行），单测直接调。
 */
import { authed, ApiError } from '../account/client'
import { session, onSession } from '../account/session'
import { displayKey } from '../market/identity'
import { priceLabel } from './shape'

export interface AlertLogRecord {
  id: string
  alertId?: string | null
  /** price / drawing（iOS 叫 line）/ condition / reviewDue；认不得的也照摆 */
  kind: string
  /** 完整品种键 venue/market/SYMBOL（binance/usd_m/BTCUSDT、macro/index/DXY） */
  symbol: string
  title: string
  condition?: string | null
  /** 响的那一刻，UTC 毫秒 */
  firedAt: number
  firedPrice?: number | null
}

// ───────── 纯函数 ─────────

const str = (v: unknown): string => typeof v === 'string' ? v : ''
/** 宽进：多给的字段不管、少给的可选字段当空；firedAt 是浮点或数字串也认；缺 id / firedAt 的那条丢掉 */
export function decodeRecord(v: unknown): AlertLogRecord | null {
  if (!v || typeof v !== 'object') return null
  const o = v as Record<string, unknown>
  const id = str(o.id)
  const at = typeof o.firedAt === 'number' ? o.firedAt : typeof o.firedAt === 'string' ? Number(o.firedAt) : NaN
  if (!id || !isFinite(at)) return null
  const px = typeof o.firedPrice === 'number' && isFinite(o.firedPrice) ? o.firedPrice : null
  return {
    id, alertId: str(o.alertId) || null, kind: str(o.kind) || 'price', symbol: str(o.symbol), title: str(o.title),
    condition: str(o.condition) || null, firedAt: Math.trunc(at), firedPrice: px,
  }
}

/** 拆包：{records:[…]} 或 {data:{records:[…]}}；按响的时间倒序 */
export function decodeLog(body: unknown): AlertLogRecord[] {
  if (!body || typeof body !== 'object') return []
  const o = body as { records?: unknown; data?: { records?: unknown } }
  const raw = Array.isArray(o.records) ? o.records : Array.isArray(o.data?.records) ? o.data!.records as unknown[] : []
  return sortedLog(raw.map(decodeRecord).filter((r): r is AlertLogRecord => !!r))
}

/** 新的在前；同一刻按 id 定序（刷新时不跳行） */
export function sortedLog(rs: readonly AlertLogRecord[]): AlertLogRecord[] {
  return [...rs].sort((a, b) => a.firedAt !== b.firedAt ? b.firedAt - a.firedAt : a.id < b.id ? 1 : a.id > b.id ? -1 : 0)
}

const DAY = 86_400_000
/** 上海时间（不给选时区，记忆 kanpan-timezone-shanghai） */
const SH = 8 * 3600_000
/** 上海日历上的那一天（自 1970-01-01 起的天数） */
export const localDay = (ms: number): number => Math.floor((ms + SH) / DAY)

/** 「今天」「昨天」「10月3日」「2025年10月3日」（今年以外的才写年） */
export function dayTitle(day: number, today: number): string {
  if (day === today) return '今天'
  if (day === today - 1) return '昨天'
  const d = new Date(day * DAY), t = new Date(today * DAY)
  const md = `${d.getUTCMonth() + 1}月${d.getUTCDate()}日`
  return d.getUTCFullYear() === t.getUTCFullYear() ? md : `${d.getUTCFullYear()}年${md}`
}

export interface LogDay { day: number; title: string; records: AlertLogRecord[] }
/** 按上海的天分组，组内与组间都是倒序 */
export function logDays(rs: readonly AlertLogRecord[], now = Date.now()): LogDay[] {
  const today = localDay(now)
  const out: LogDay[] = []
  for (const r of sortedLog(rs)) {
    const day = localDay(r.firedAt)
    const last = out[out.length - 1]
    if (last?.day === day) last.records.push(r)
    else out.push({ day, title: dayTitle(day, today), records: [r] })
  }
  return out
}

/** 行尾那个时刻：14:03（上海 24 小时制） */
export function logClock(ms: number): string {
  const m = Math.floor((((ms + SH) % DAY) + DAY) % DAY / 60_000)
  return String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(m % 60).padStart(2, '0')
}

/** 千分位（小数部分不动） */
export function groupedPrice(p: number, dec?: number): string {
  const s = priceLabel(p, dec)
  const [head, tail] = s.split('.')
  const neg = head.startsWith('-')
  const g = (neg ? head.slice(1) : head).replace(/\B(?=(\d{3})+(?!\d))/g, ',')
  return (neg ? '-' : '') + g + (tail != null ? '.' + tail : '')
}

/** 行上第二行：条件（服务端写好的「价格达到 86,000」；没有就用标题）·「触发价 X」。都没有就空 */
export function logDetail(r: AlertLogRecord, dec?: number): string {
  const parts: string[] = []
  const cond = (r.condition ?? '').trim(), title = r.title.trim()
  if (cond) parts.push(cond)
  else if (title) parts.push(title)
  if (r.firedPrice != null && isFinite(r.firedPrice) && r.firedPrice > 0) parts.push('触发价 ' + groupedPrice(r.firedPrice, dec))
  return parts.join(' · ')
}

/** 完整键 → 网页版的裸代号（macro/index/DXY → DXY，binance/usd_m/BTCUSDT → BTCUSDT）；本来就是裸的原样回 */
export function bareSymbol(key: string): string {
  if (!key) return ''
  // 完整键 → 网页键：币安回裸代号、美元指数回 DXY，别家（okx/usd_m/BTCUSDT）原样——不能只取最后一段，那会把 OKX 的提醒开成币安的
  return key.includes('/') ? displayKey(key) : key
}

/** 行上第一行：品种名（pair 由各端给，手机「BTC/USDT」、电脑「BTCUSDT」）；没给品种时用标题，再没有就叫「提醒」 */
export function logName(r: AlertLogRecord, pair: (symbol: string) => string): string {
  const s = bareSymbol(r.symbol)
  if (s) return pair(s)
  return r.title.trim() || '提醒'
}

// ───────── 状态：本机缓存 + 一趟拉取 / 清空 ─────────

export type LogPhase = 'idle' | 'loading' | 'loaded' | 'failed'
export const LOG_PATH = '/v1/alerts/log'
export const LOG_LIMIT = 200
export const logCacheKey = (owner: string): string => 'hkline-alert-log.' + owner.toLowerCase()

interface KV { getItem(k: string): string | null; setItem(k: string, v: string): void; removeItem(k: string): void }
const ls = (): KV | null => { try { return (globalThis as { localStorage?: KV }).localStorage ?? null } catch { return null } }

/** 发请求的那一层（测试换掉它） */
export type LogFetch = (method: 'GET' | 'DELETE', path: string, owner: string) => Promise<unknown>
// 替谁拉的就只用谁的令牌（拉的路上换了号，旧号那一趟作废，不把新号的记录装进旧号的缓存）
const liveFetch: LogFetch = (method, path, owner) => authed<unknown>(method, path, undefined, {}, owner === session.userId ? owner : undefined)
/** 当前账号的身份（老登录态没存 userId 的退到用户名） */
export const logOwner = (): string | null => session.userId || session.user || null

export class AlertLogModel {
  records: AlertLogRecord[] = []
  phase: LogPhase = 'idle'
  /** 当前账号的 userId；null = 没登录 */
  owner: string | null = null
  private subs = new Set<() => void>()
  private run = 0
  constructor(private fetcher: LogFetch = liveFetch, private store: () => KV | null = ls) {}

  onChange(fn: () => void): () => void { this.subs.add(fn); return () => { this.subs.delete(fn) } }
  private emit(): void { this.subs.forEach(f => { try { f() } catch (e) { console.error(e) } }) }

  /** 换到这个人（null = 没登录）：摆上他那份缓存 */
  select(owner: string | null): void {
    if (owner === this.owner) return
    this.run++
    this.owner = owner
    this.phase = 'idle'
    this.records = owner ? this.readCache(owner) : []
    this.emit()
  }

  /** 拉一趟。404 当空；别的失败照摆缓存（phase = failed） */
  async refresh(owner: string | null): Promise<void> {
    this.select(owner)
    if (!owner) return
    const run = ++this.run
    this.phase = 'loading'; this.emit()
    try {
      const body = await this.fetcher('GET', `${LOG_PATH}?limit=${LOG_LIMIT}`, owner)
      if (run !== this.run) return
      this.records = decodeLog(body)
      this.phase = 'loaded'
    } catch (e) {
      if (run !== this.run) return
      if (e instanceof ApiError && e.status === 404) { this.records = []; this.phase = 'loaded' }
      else { this.phase = 'failed' }
    }
    this.writeCache(owner, this.records)
    this.emit()
  }

  /** 清空（服务端那份 + 本机缓存）；成功回 true */
  async clear(): Promise<boolean> {
    const owner = this.owner
    if (!owner) return false
    try { await this.fetcher('DELETE', LOG_PATH, owner) } catch (e) {
      // 404：服务端没这条路，本来就没有记录，照清本机
      if (!(e instanceof ApiError && e.status === 404)) return false
    }
    if (owner !== this.owner) return true
    this.run++ // 清空前发出去、还在路上的那趟拉取作废（回来的是清空前的旧账）
    this.records = []; this.phase = 'loaded'
    this.writeCache(owner, [])
    this.emit()
    return true
  }

  private readCache(owner: string): AlertLogRecord[] {
    try { return decodeLog({ records: JSON.parse(this.store()?.getItem(logCacheKey(owner)) || '[]') }) } catch { return [] }
  }
  private writeCache(owner: string, rs: AlertLogRecord[]): void {
    try { this.store()?.setItem(logCacheKey(owner), JSON.stringify(rs)) } catch { /* 满了就算了：下次照拉 */ }
  }
}

/** 全站一份（手机与电脑网页各自一页一份，同源共用缓存键） */
let shared: AlertLogModel | null = null
export function alertLog(): AlertLogModel {
  if (!shared) {
    shared = new AlertLogModel()
    // 退登 / 换号：换成那个人的缓存（没登录就清空展示）
    onSession(() => shared!.select(logOwner()))
  }
  return shared
}
