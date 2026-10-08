/* Hkline Web · 提醒模块（数据与判定）
 *
 * 一条提醒的形状和手机端 / 服务端同步的 `alerts` 对象一字不差（19 个字段，见
 * Backend/kanpan-api/src/sync_validation.rs 与 KanpanCore Alerts/Alert.swift）：
 *   kind、market、symbol、lines、condition、status、once、armedAt、firedAt、firedPrice、
 *   title、note、webhook、webhookText、drawingID、reviewID、dueAt、rule、created
 * 本地 id 是 "a" + UUID（和手机一样），同步 id 是 `${market}/${symbol}/${id}`。
 *
 * 几何照服务端的约定由客户端摊平：价格提醒是一条两侧无限延伸的水平线；画线提醒按工具摊成
 * 折线（水平线两侧延伸、射线只往右、趋势线不延伸）。判定也照服务端 `touched`：
 * 线在「此刻」的价落在上一笔与这一笔成交价之间就算碰到；上一笔正好在线上不算（那一下归上一笔），
 * 提醒创建之前的行情一概不算。响一次就结束（从表里删掉），没有重复提醒。
 *
 * 这个文件只有形状、构造、迁移和判定的纯函数（不碰 store，store 读盘迁移时也要用它）；
 * 表的增删与触发在 model.ts。
 */
import type { Drawing } from '../chart/chart'
import { MACRO_CN, isMacro } from '../market/macro'
import { alertMarketOf, syncKeyOf, wireSymbol } from '../market/identity'
import { indicatorPhrase, isIndicatorRule, type IndicatorRule } from './indicator'

export type AlertKind = 'drawing' | 'price' | 'reviewDue' | 'condition'
/** 提醒正文的 market（venue/market），和服务端 alerts / sync_validation 的白名单同一份；2026-10-08 加 OKX / Bybit / Hyperliquid 永续 */
export type AlertMarket = 'binance/usd_m' | 'coinbase/spot' | 'macro/index' | 'okx/usd_m' | 'bybit/usd_m' | 'hyperliquid/usd_m'
export interface AlertPoint { t: number; p: number }
export interface AlertGeom { points: AlertPoint[]; extendLeft: boolean; extendRight: boolean }
export type AlertRule =
  | { type: 'funding'; side: 'above' | 'below'; rate: string }
  | { type: 'openInterestChange'; threshold: string }
  | { type: 'maCross'; interval: string; length: number; side: 'above' | 'below' }
  | { type: 'orderflowWall'; threshold: string }
  /** 技术指标条件（均线交叉 / RSI / 突破）：线上是 `{kind:…}`，没有 type，见 indicator.ts */
  | IndicatorRule
  | { type: string; [k: string]: unknown }

export interface Alert {
  id: string
  kind: AlertKind
  market: AlertMarket
  symbol: string
  lines: AlertGeom[]
  condition: 'touch' | 'close'
  status: 'active' | 'fired' | 'paused'
  once: boolean
  armedAt: number
  firedAt: number | null
  firedPrice: number | null
  title: string
  note: string | null
  webhook: string | null
  webhookText: string | null
  drawingID: string | null
  reviewID: string | null
  dueAt: number | null
  rule: AlertRule | null
  created: number
}

export const MARKET: AlertMarket = 'binance/usd_m'
/** 这只品种的提醒 market：币安 U 本位、美元指数 macro/index、别家按它的身份键（okx/usd_m……） */
export const marketOf = (symbol: string): AlertMarket => alertMarketOf(symbol) as AlertMarket
const QUOTES = ['USDT', 'USDC', 'FDUSD', 'BUSD', 'USD1', 'TUSD', 'USD']

export function newAlertId(): string {
  const u = typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : `${Date.now().toString(16)}-${Math.random().toString(16).slice(2)}`
  return 'a' + u.toUpperCase()
}
/** 同步 id：`${market}/${那一家的代号}/${id}`（本机的 symbol 是网页键，别家是完整键，取代号那一段） */
export const syncIdOf = (a: Pick<Alert, 'market' | 'symbol' | 'id'>): string => `${a.market}/${wireSymbol(a.symbol)}/${a.id}`
/** 标题里的品种短名：BTCUSDT → BTC，BTC-USD → BTC */
export function baseOf(symbol: string): string {
  if (isMacro(symbol)) return MACRO_CN   // 推送标题照服务端写「美元指数」
  symbol = wireSymbol(symbol)
  if (symbol.includes('-')) return symbol.split('-')[0]
  for (const q of QUOTES) if (symbol.length > q.length && symbol.endsWith(q)) return symbol.slice(0, -q.length)
  return symbol
}

/** 价位文字：保留用户看到的位数，去掉尾巴上的 0 */
export function priceLabel(p: number, dec?: number): string {
  const d = dec ?? (p >= 1000 ? 2 : p >= 1 ? 4 : 8)
  const s = p.toFixed(Math.max(0, Math.min(10, d)))
  return s.includes('.') ? s.replace(/\.?0+$/, '') : s
}

// ------------------------------------------------------------ 标题
export function priceTitle(symbol: string, target: number, current: number | null | undefined, dec?: number): string {
  const verb = current == null ? '到了' : target >= current ? '涨到' : '跌到'
  return `${baseOf(symbol)} ${verb} ${priceLabel(target, dec)}`
}
const LINE_NAME: Record<string, string> = { hline: '水平线', trend: '趋势线', ray: '向右延伸', rect: '矩形', fib: '斐波那契回撤' }
export const drawingTitle = (symbol: string, type: string): string => `${baseOf(symbol)} 触到你画的${LINE_NAME[type] || '线'}`
function pct(ratio: string, dp: number): string {
  const n = +ratio * 100
  return String(+n.toFixed(dp))
}
/** 条件那一段（和服务端 Rule::phrase 一字对一字） */
export function rulePhrase(r: AlertRule | null): string {
  if (!r) return '条件提醒'
  if (isIndicatorRule(r)) return indicatorPhrase(r)
  if (r.type === 'funding') { const f = r as { side: string; rate: string }; return `资金费率${f.side === 'above' ? '高于' : '低于'} ${pct(f.rate, 6)}%` }
  if (r.type === 'openInterestChange') return `1 小时持仓量变化超过 ${pct((r as { threshold: string }).threshold, 4)}%`
  if (r.type === 'maCross') { const m = r as { interval: string; length: number; side: string }; return `${m.interval} 收盘${m.side === 'above' ? '站上' : '跌破'} MA${m.length}` }
  if (r.type === 'orderflowWall') return '出现大单墙'
  return '条件提醒'
}
export const conditionTitle = (symbol: string, r: AlertRule): string => `${baseOf(symbol)} ${rulePhrase(r)}`
/** 条件名：页里只写「价格达到」 */
export const conditionLabel = (c: Alert['condition']): string => c === 'close' ? '收盘穿过' : '价格达到'

// ------------------------------------------------------------ 构造
function base(symbol: string, kind: AlertKind, now: number): Alert {
  return {
    id: newAlertId(), kind, market: marketOf(symbol), symbol, lines: [], condition: 'touch', status: 'active', once: true,
    armedAt: now, firedAt: null, firedPrice: null, title: '', note: null, webhook: null, webhookText: null,
    drawingID: null, reviewID: null, dueAt: null, rule: null, created: now,
  }
}
export function makePriceAlert(symbol: string, target: number, current: number | null | undefined, opts: { now?: number; dec?: number; webhook?: string | null } = {}): Alert {
  const now = opts.now ?? Date.now()
  const a = base(symbol, 'price', now)
  a.lines = [{ points: [{ t: now, p: target }], extendLeft: true, extendRight: true }]
  a.title = priceTitle(symbol, target, current, opts.dec)
  a.webhook = cleanWebhook(opts.webhook)
  return a
}
export const drawingIdOf = (symbol: string, drawingId: string): string => `${syncKeyOf(symbol)}/${drawingId}`
/** 画线摊平成折线（水平线两侧延伸、射线往右、趋势线不延伸）；别的工具不给提醒 */
export function drawingLines(d: Pick<Drawing, 'type' | 'pts'>): AlertGeom[] {
  const pts = d.pts.map(p => ({ t: Math.round(p.t), p: p.p }))
  if (d.type === 'hline' && pts[0]) return [{ points: [pts[0]], extendLeft: true, extendRight: true }]
  if ((d.type === 'trend' || d.type === 'ray') && pts.length >= 2) {
    const [a, b] = pts[0].t <= pts[1].t ? [pts[0], pts[1]] : [pts[1], pts[0]]
    // 射线从第一个点朝第二个点的方向延伸
    const rightward = d.pts[1].t >= d.pts[0].t
    return [{ points: [a, b], extendLeft: d.type === 'ray' && !rightward, extendRight: d.type === 'ray' && rightward }]
  }
  return []
}
export const drawingCanAlert = (type: string): boolean => type === 'hline' || type === 'trend' || type === 'ray'
export function makeDrawingAlert(symbol: string, d: Drawing, now = Date.now()): Alert {
  const a = base(symbol, 'drawing', now)
  a.lines = drawingLines(d)
  a.drawingID = drawingIdOf(symbol, d.id)
  a.title = drawingTitle(symbol, d.type)
  return a
}
export function makeConditionAlert(symbol: string, rule: AlertRule, opts: { now?: number; webhook?: string | null } = {}): Alert {
  const a = base(symbol, 'condition', opts.now ?? Date.now())
  a.rule = rule
  a.title = conditionTitle(symbol, rule)
  a.webhook = cleanWebhook(opts.webhook)
  return a
}
/** Webhook 只填地址：http(s):// 开头、不带空白，不合规就当没填 */
export function cleanWebhook(u: string | null | undefined): string | null {
  const s = (u || '').trim()
  return /^https?:\/\/\S+$/i.test(s) && s.length <= 1024 ? s : null
}
export const validWebhook = (u: string): boolean => !u.trim() || cleanWebhook(u) != null

// ------------------------------------------------------------ 迁移（第一阶段存的三种老形状）
interface OldAlert { id?: string; symbol?: string; kind?: string; created?: number; price?: number; dir?: number; value?: number; op?: 'gt' | 'lt'; webhook?: string | null }
const ratioText = (percent: number): string => String(+(percent / 100).toPrecision(8))
/** 认得就补成完整形状，认不得就丢 */
export function migrateAlert(raw: unknown): Alert | null {
  if (!raw || typeof raw !== 'object') return null
  const o = raw as Partial<Alert> & OldAlert
  if (typeof o.symbol !== 'string' || !o.symbol) return null
  if (Array.isArray(o.lines) && typeof o.market === 'string' && (o.kind === 'price' || o.kind === 'drawing' || o.kind === 'condition' || o.kind === 'reviewDue')) {
    const now = Date.now(), b = base(o.symbol, o.kind, now)
    const a = { ...b, ...o } as Alert
    if (typeof a.id !== 'string' || !a.id) a.id = b.id
    // 老存档里暂停着的画线提醒（从前「线找不到」时暂停的）读进来就恢复生效、从此刻起算：
    // 2026-10-06 起提醒不再依附画线，线没了照它自己的 lines 判（用户：「删除画线也不应该删除警报」）
    if (a.kind === 'drawing' && a.status === 'paused') { a.status = 'active'; a.armedAt = Math.max(a.armedAt || 0, now) }
    return a
  }
  const created = typeof o.created === 'number' ? o.created : Date.now()
  if (o.kind === 'price' && typeof o.price === 'number' && o.price > 0) {
    const a = makePriceAlert(o.symbol, o.price, o.dir == null ? null : o.price - (o.dir || 1), { now: created, webhook: o.webhook })
    return a
  }
  if ((o.kind as string) === 'fr' && typeof o.value === 'number' && isFinite(o.value)) {
    const v = Math.max(-10, Math.min(10, o.value))
    return makeConditionAlert(o.symbol, { type: 'funding', side: o.op === 'lt' ? 'below' : 'above', rate: ratioText(v) }, { now: created, webhook: o.webhook })
  }
  if ((o.kind as string) === 'oi' && typeof o.value === 'number' && o.value > 0) {
    return makeConditionAlert(o.symbol, { type: 'openInterestChange', threshold: ratioText(Math.max(0.1, Math.min(1000, o.value))) }, { now: created, webhook: o.webhook })
  }
  return null
}

// ------------------------------------------------------------ 几何与判定（纯函数，服务端 price_at / touched 的镜像）
/** 折线在 t 时刻的价；越过端点且那一侧不延伸就是 null；只有一个点是水平线 */
export function linePriceAt(line: AlertGeom, t: number): number | null {
  const pts = line.points.slice().sort((a, b) => a.t - b.t)
  if (!pts.length) return null
  const first = pts[0], last = pts[pts.length - 1]
  const ext = (left: boolean): number => {
    if (pts.length < 2) return pts[0].p
    const [a, b] = left ? [pts[0], pts[1]] : [pts[pts.length - 2], pts[pts.length - 1]]
    const edge = left ? a : b
    if (b.t <= a.t) return edge.p
    return edge.p + (b.p - a.p) * (t - edge.t) / (b.t - a.t)
  }
  if (t < first.t) return line.extendLeft ? ext(true) : null
  if (t > last.t) return line.extendRight ? ext(false) : null
  for (let i = 1; i < pts.length; i++) {
    const a = pts[i - 1], b = pts[i]
    if (t >= a.t && t <= b.t) return b.t <= a.t ? a.p : a.p + (b.p - a.p) * (t - a.t) / (b.t - a.t)
  }
  return first.p
}
/** 图上画的那条提醒线的价（价格提醒 = 目标价；画线提醒 = 线在此刻的价） */
export function alertLevel(a: Alert, t = Date.now()): number | null {
  for (const l of a.lines) { const p = linePriceAt(l, t); if (p != null && isFinite(p)) return p }
  return null
}
/** 从上一笔 prev 到这一笔 cur 之间碰到线了吗；上一笔正好在线上不算（那一下已经算过） */
export function touchedBetween(a: Alert, prev: number, cur: number, t: number): number | null {
  if (a.status !== 'active' || a.condition !== 'touch' || (a.kind !== 'price' && a.kind !== 'drawing')) return null
  if (t < a.armedAt || !isFinite(prev) || !isFinite(cur)) return null
  const lo = Math.min(prev, cur), hi = Math.max(prev, cur)
  for (const l of a.lines) {
    const p = linePriceAt(l, t)
    if (p != null && isFinite(p) && p >= lo && p <= hi && prev !== p) return p
  }
  return null
}
/** 资金费率结算前判的那个窗口 */
export const FUNDING_WINDOW_MS = 15 * 60e3
/** 资金费率：结算前 15 分钟那个窗口里、武装之后，够没够线（恰好等于阈值算够，和服务端 judge_funding、
 *  iOS ConditionJudge 同一条规矩）。「每次结算只判一次」由 judgeFunding 记 */
export function fundingHit(rule: AlertRule, fr: number | null | undefined, nextFunding: number | null | undefined, now: number, armedAt = 0): boolean {
  if (rule.type !== 'funding' || fr == null || !isFinite(fr) || !nextFunding) return false
  if (now < nextFunding - FUNDING_WINDOW_MS || now >= nextFunding || now < armedAt) return false
  const rate = +(rule as { rate: string }).rate
  return (rule as { side: string }).side === 'above' ? fr >= rate : fr <= rate
}
/** 照服务端：一条提醒在一次结算的窗口里只判第一眼——第一眼没够线，这一次结算就不再判（后面费率涨上去也不算）。
 *  judged 记「这条提醒判过的是哪一次结算」，跨调用保留 */
export function judgeFunding(a: Pick<Alert, 'id' | 'rule' | 'armedAt'>, fr: number | null | undefined, nextFunding: number | null | undefined, now: number, judged: Map<string, number>): boolean {
  if (!a.rule || a.rule.type !== 'funding' || fr == null || !isFinite(fr) || !nextFunding) return false
  if (now < nextFunding - FUNDING_WINDOW_MS || now >= nextFunding || now < a.armedAt) return false
  if (judged.get(a.id) === nextFunding) return false
  judged.set(a.id, nextFunding)
  return fundingHit(a.rule, fr, nextFunding, now, a.armedAt)
}
export function oiHit(rule: AlertRule, changeRatio: number): boolean {
  return rule.type === 'openInterestChange' && Math.abs(changeRatio) >= +(rule as { threshold: string }).threshold
}
/** 持仓量比较的跨度：最新一个点和恰好 1 小时前的点比（服务端 OI_SPAN_MS） */
export const OI_SPAN_MS = 3600e3
/** openInterestHist 一串点 → 最新一个点与恰好 1 小时前那个点的变化比；只认最新点在武装之后的（照服务端
 *  judge_open_interest：缺 1 小时前那个点不判，任一端是 0 不判）。返回 null = 这一轮不判 */
export function oiChange(rows: readonly { timestamp: number; sumOpenInterest: string | number }[], armedAt: number): number | null {
  const pts = rows.map(r => ({ at: +r.timestamp, v: +r.sumOpenInterest })).filter(p => isFinite(p.at) && isFinite(p.v)).sort((a, b) => a.at - b.at)
  const last = pts[pts.length - 1]
  if (!last || last.at < armedAt) return null
  const before = pts.find(p => p.at === last.at - OI_SPAN_MS)
  if (!before || before.v === 0 || last.v === 0) return null
  return last.v / before.v - 1
}
/** 价格输入框里的数（手机网页、电脑网页同一份，照 iOS AlertForm）：去千分位与空白、全角句点当小数点；不是正数就 null */
export function parseTarget(text: string): number | null {
  const s = text.replace(/[,，\s]/g, '').replace(/[。．]/g, '.')
  if (!/^\d*\.?\d*$/.test(s) || !s || s === '.') return null
  const n = +s
  return n > 0 && isFinite(n) ? n : null
}
/** 百分数输入框（资金费率、持仓量变化）：同上，另认负号（含全角 −／－）与末尾的 %；空的、不是数的给 null（不当 0） */
export function parsePercent(text: string): number | null {
  const s = text.replace(/[,，\s%％]/g, '').replace(/[。．]/g, '.').replace(/^[−－]/, '-')
  if (!/^[-+]?\d*\.?\d*$/.test(s) || !/\d/.test(s)) return null
  const n = +s
  return isFinite(n) ? n : null
}

/** 创建条件提醒时填的百分数在不在服务端收的范围里：持仓量 0.1%–1000%（threshold 0.001–10），资金费率 ±10%（rate ±0.1） */
export function conditionPercentOK(kind: 'funding' | 'oi', v: number): boolean {
  if (!isFinite(v)) return false
  return kind === 'oi' ? v >= 0.1 && v <= 1000 : Math.abs(v) <= 10
}

/** 照手机 AlertWatcher.report：条件提醒本机判到的由本机发（服务端只替它自己判到的那一次发）；
 *  价格 / 画线提醒登录着由服务端发（看到同步上去的 active → fired），没登录才由这里发 */
export function webhookByPage(a: Alert, remote: boolean, signedIn: boolean): boolean {
  if (!a.webhook || remote) return false
  return a.kind === 'condition' || !signedIn
}
