/* 手机网页版 · 复盘本（照 iOS KanpanReview/ReviewUI：ReviewBook / ReviewRecordView / ReviewSearchView /
 * ReviewSavedMatchesView / ReviewAttachmentsSection / ReviewStatisticsView / ReviewRevisionsView /
 * TradeBookList / TradeRecordView / TradeStatisticsList，以及 ReviewSyncEngine 的待传队列）
 *
 * 从「我的」推进来，整页是「观点 · 交易」两面；导航栏右上「+」（记一笔）与「…」（已存案例）。
 *   观点：战绩摘要卡（点开分组战绩）+「全部 / 待判定 N / 已判定」+ 搜索；列表按页拉、滑到底接下一页；
 *         记一笔还没传上去的那几条先按本机记录排在最前。
 *         点一条进「记录详情」：没能同步、结果有更新、这次判断、当时（在图上重温 · 找相似）、当时那张图、
 *         对应的交易、补图、市场的答案、写复盘、历史复盘、修订记录、作废（5 秒内可撤销）。
 *   交易：上周周报卡 + 持仓中 / 按平仓那天分组；每行带徽章与小图。点一笔进「交易详情」：
 *         那段行情的图（点图或正中圆片回放这一笔）、成交、结算、持仓期间、离开后、当时怎么想、对应的观点。
 * 顶上那一块（分段、摘要、筛选）在滚动区里吸顶，只有列表在动——和 iOS 那几块固定在 List 上面一样。
 *
 * 写复盘、作废、归并一律先进本机待传队列（照 ReviewSyncEngine）：界面立刻按本机这份显示，
 * 有网就按顺序传；断网、服务器忙就留着，联网、回前台、再打开复盘本时接着传；
 * 服务端明确不收的那次改动隔离下来，在记录详情「没能同步」里由人拍板。
 *
 * 「我的」根上那两行字、底栏「我的」角标也从这里出（reviewRootStatus / onReviewStatus / refreshReviewStatus，
 * 30 秒内不重拉）。
 *
 * 和 iOS 不一样的地方（都不是没做，是浏览器里换了做法或做不到）：
 * - 「在图上重温」「打开相似片段」「回放这笔交易」：复盘本把回放计划（review/replay.ts 的 planNote / planMatch /
 *   planTrade）连同市场写进 sessionStorage[M.INTENT_KEY] 并在 window 上发 M.INTENT_EVENT，只把页面切到行情页；
 *   行情页认领这份意图，在实时图上盖一层回放（pages/chart/replay.ts），实时图的品种、周期、指标都不动。
 *   「我的」这一摞不退，点「退出」回来还在原处。
 * - 继续未完成的记录：那份草稿住在行情页的记一笔里（note.ts 的 unfinishedNote）。有草稿时观点列表顶上多一行
 *   「继续未完成的记录」，它和右上「+」一样走 requestNote：回行情页、切回草稿那只和那个周期、接着写；没有就新记。
 * - 接入交易所：交易所密钥只存在手机本机（iOS 钥匙串），网页不收密钥；交易面空着时写「接入交易所后自动生成」。
 * - 触感：用 navigator.vibrate（安卓 / 鸿蒙浏览器有；iOS Safari 没有这个接口，就安静地不震）。
 */
import '../styles/review.css'
import { esc, pressGate, setHTML } from '../ui/dom'
import { icon } from '../ui/icons'
import { confirmDialog, openMenu, openSheet } from '../ui/sheet'
import { deleteAction, swipeRow, type SwipeHandle } from '../ui/swipeDelete'
import { toast } from '../ui/toast'
import { registerTerms, termHTML } from '../ui/hint'
import { loggedIn, onSession, session } from '../../account/session'
import { go, hooks, setMeBadge } from '../app/shell'
import { st, save as saveState } from '../app/store'
import { S, REST, j } from '../../market'
import { fmtPrice, priceDecimalsFallback } from '../chart/format'
import { makeState } from '../chart/state'
import { BarSeries, bar, INTERVAL_STEP, type Bar, type Interval } from '../chart/series'
import { ViewWindow, priceTransform } from '../chart/geometry'
import { readChartColors } from '../chart/paint'
import { ChartRenderer } from '../chart/renderer'
import { appChartOptions } from '../chart/index'
import { makeDrawing } from '../chart/draw/drawing'
import { assetOf, badgeHTML } from '../model/badge'
import { flushNotes, pendingNotes, requestNote, unfinishedNote } from './chart/note'
import { INTERVAL_SHORT } from '../chart/series'
import { errorText, reviewApi, reviewBookApi, ReviewError, uuid } from '../../review/api'
import { planMatch, planNote, planTrade } from '../../review/replay'
import { groupRateText, resolvedGroups, roundDecimals } from '../../review/model'
import type { Fill, Match, ReviewAttachment, Round, SavedMatch, SearchStatus, StatGroup, TradeRecord, ViewRecordFull } from '../../review/types'
import * as M from '../model/reviewBook'
import type { MeHost, MeLayer } from './meHost'
import { ago, before } from '../../util/clock'

const CHEV = icon('chevronRight', 12)
const PLAY = '<svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true"><path d="M5 3.2v11.6c0 .6.66.97 1.17.66l9.3-5.8a.78.78 0 0 0 0-1.32l-9.3-5.8A.78.78 0 0 0 5 3.2z" fill="currentColor"/></svg>'

// ───────── 术语（照 iOS GlossaryTerms+Review） ─────────
registerTerms([
  { id: 'rvRewardRisk', title: '盈亏比', body: '平均每笔赚的，除以平均每笔亏的。\n大于 1 说明赚的时候比亏的时候多；胜率不高时，靠它撑住。' },
  { id: 'rvExpectancy', title: '每笔期望', body: '平均每做一笔赚（或亏）多少钱。\n为正说明这样做下去长期是赚的。' },
  { id: 'rvFeeShare', title: '费用占毛利', body: '手续费（扣掉收到的、加上付出的资金费）占平仓赚亏的比例。\n比例越高，越多的利润被费用吃掉了；毛利为负时不算。' },
  { id: 'rvFills', title: '成交', body: '这一笔里每一次买卖。\n挂单：你的单先挂在簿上、被别人吃掉，手续费低。\n吃单：直接吃掉别人的挂单，成交快、手续费高。' },
  { id: 'rvRealized', title: '已实现', body: '平仓时交易所结算的赚亏，还没扣手续费、没算资金费。' },
  { id: 'rvTradeRewardRisk', title: '盈亏比 · 这一笔', body: '这一笔的净盈亏，除以持仓期间最大浮亏。\n数越大，说明担的风险换来的回报越多。' },
  { id: 'rvAfterClose', title: '离开后', body: '平仓之后 1、4、24 小时，价格比你的平仓价又走了多少。\n用来看是走早了，还是躲过了一段。' },
])

// ───────── 本机待传队列（照 iOS ReviewSyncEngine） ─────────
const kv: M.KV = {
  getItem: k => { try { return localStorage.getItem(k) } catch { return null } },
  setItem: (k, v) => localStorage.setItem(k, v),
}
const readOps = (): M.PendingOp[] => (session.user ? M.readPending(kv, session.user) : [])
function writeOps(list: M.PendingOp[]): void { if (session.user) M.writePending(kv, session.user, list) }
function patchOp(id: string, fn: (o: M.PendingOp) => void): void {
  const list = readOps()
  const o = list.find(x => x.id === id)
  if (!o) return
  fn(o)
  writeOps(list)
}

/** 某条记录的队列变了（或服务端那份换了）；recordId '*' = 整张列表要重拉（记一笔刚传上去） */
type RecordListener = (recordId: string, server?: ViewRecordFull) => void
const recordSubs = new Set<RecordListener>()
function emitRecord(recordId: string, server?: ViewRecordFull): void {
  recordSubs.forEach(fn => { try { fn(recordId, server) } catch (e) { console.error(e) } })
  setMeBadge(pendingNow())
  emitStatus()
}
function onRecord(fn: RecordListener): () => void { recordSubs.add(fn); return () => { recordSubs.delete(fn) } }

/** 本机刚传上去之后服务端给的版本号：同一条后面排着的改动按它接着发（先写复盘、再作废） */
const ownRevision = new Map<string, number>()
let flushing: Promise<void> | null = null
let flushAgain = false
let holdTimer: ReturnType<typeof setTimeout> | undefined
let holdAt = 0

/** 到点再传一轮（几条各自等着时，按最早到点的那条排；那一轮里还没到点的会再排下一次） */
function scheduleFlush(ms: number): void {
  const at = Date.now() + Math.max(0, ms) + 50
  if (holdTimer && holdAt <= at) return
  clearTimeout(holdTimer)
  holdAt = at
  holdTimer = setTimeout(() => { holdTimer = undefined; holdAt = 0; void flushPending() }, at - Date.now())
}

/** 按顺序把队列传上去：每一步之后重读队列（这一轮还在传时新写进来的也带上） */
function flushPending(): Promise<void> {
  if (flushing) { flushAgain = true; return flushing }
  flushing = (async () => {
    do {
      flushAgain = false
      await flushRound()
    } while (flushAgain)
  })().finally(() => { flushing = null })
  return flushing
}

async function flushRound(): Promise<void> {
  if (!loggedIn() || !navigator.onLine) return
  const who = session.user
  const tried = new Set<string>()
  const blocked = new Set<string>()
  const local = new Set(pendingNotes().map(q => q.draft.id))
  for (;;) {
    if (session.user !== who) return
    const op = readOps().find(o => !tried.has(o.id) && !o.kept && !o.conflict && !blocked.has(o.recordId))
    if (!op) return
    tried.add(op.id)
    // 记一笔那条还没传上去：先等它（服务端还没有这条）
    if (local.has(op.recordId)) { blocked.add(op.recordId); continue }
    const now = Date.now()
    if (op.holdUntil && before(op.holdUntil, M.VOID_HOLD_MS, now) && !op.attempted) {
      // 作废留 5 秒撤销：到点再来；这条后面排着的也等它
      blocked.add(op.recordId)
      scheduleFlush(op.holdUntil - now)
      continue
    }
    if (!op.attempted) {
      const own = ownRevision.get(op.recordId)
      if (own != null && own > op.body.expectedRevision) op.body.expectedRevision = own
      op.attempted = true
      patchOp(op.id, o => { o.attempted = true; o.body.expectedRevision = op.body.expectedRevision })
    }
    try {
      const res = await reviewBookApi.pushOperation(op.recordId, op.kind, op.body, op.id)
      writeOps(readOps().filter(o => o.id !== op.id))
      ownRevision.set(op.recordId, res.record.revision)
      patchView(res.record)
      emitRecord(op.recordId, res.record)
    } catch (e) {
      const f = e instanceof ReviewError ? { code: e.code, status: e.status } : { code: 'network', status: 0 }
      const verdict = M.failureVerdict(f)
      if (verdict === 'transient') {
        // 断网、超时、服务器忙：整轮停下，下次联网 / 回前台 / 再打开时接着传
        patchOp(op.id, o => { o.error = errorText(e) })
        emitRecord(op.recordId)
        return
      }
      const reason = M.failureMessage(f)
      patchOp(op.id, o => { o.conflict = { reason, retryable: verdict === 'conflict' }; o.error = null })
      blocked.add(op.recordId)
      toast(reason)
      emitRecord(op.recordId)
    }
  }
}

function enqueue(rec: ViewRecordFull, kind: M.OpKind, body: M.OpBody, holdMs = 0): M.PendingOp {
  const op: M.PendingOp = { id: uuid(), recordId: rec.draft.id, kind, body, at: Date.now(), ...(holdMs ? { holdUntil: Date.now() + holdMs } : {}) }
  writeOps(M.enqueueOp(readOps(), op))
  emitRecord(op.recordId)
  if (holdMs) scheduleFlush(holdMs); else void flushPending()
  return op
}

/** 「没能同步」里人拍的板：用云端那份 = 丢掉这次改动；用我这份 = 拿最新版本号重发；留在本机 = 不再发 */
async function resolveConflict(recordId: string, keepLocal: boolean): Promise<void> {
  const bad = readOps().filter(o => o.recordId === recordId && o.conflict)
  if (!bad.length) return
  if (!keepLocal) {
    const drop = new Set(bad.map(o => o.id))
    writeOps(readOps().filter(o => !drop.has(o.id)))
    emitRecord(recordId)
    return
  }
  let latest: number | null = null
  if (bad.some(o => o.conflict!.retryable)) {
    try { latest = (await reviewBookApi.recordDetail(recordId)).record.revision } catch (e) { toast(errorText(e)); return }
  }
  const list = readOps().map(o => {
    if (o.recordId !== recordId || !o.conflict) return o
    if (!o.conflict.retryable) return { ...o, kept: true, conflict: null }
    return { ...o, id: uuid(), body: { ...o.body, expectedRevision: latest ?? o.body.expectedRevision }, attempted: false, conflict: null, error: null, holdUntil: undefined }
  })
  writeOps(list)
  ownRevision.delete(recordId)
  emitRecord(recordId)
  void flushPending()
}

/** 记一笔、复盘一起补传（联网、回前台、打开复盘本） */
function syncAll(): void {
  if (!loggedIn()) return
  void flushNotes().then(n => {
    if (n > 0) { emitRecord('*'); refreshReviewStatus(true) }
  }, () => 0).finally(() => { void flushPending() })
}

const haptic = (): void => { try { navigator.vibrate?.(10) } catch { /* iOS Safari 没有震动接口 */ } }

// ───────── 「我的」根上那两行 + 角标（全模块共用的一份数） ─────────
const THROTTLE = 30_000
const status = {
  /** 全部观点记录（算战绩三个数、待判定条数）；null = 还没拉到 */
  views: null as ViewRecordFull[] | null,
  /** 全部交易回合（周报、交易列表、交易战绩）；null = 还没拉到 */
  trades: null as TradeRecord[] | null,
  viewsError: null as string | null,
  tradesError: null as string | null,
  at: 0,
  user: null as string | null,
}
/** 在途那一拉是替谁拉的；again = 拉的途中又有人要求强制重拉（刚改过记录），回来后再拉一遍 */
let inflight: { user: string | null; again: boolean } | null = null
const statusSubs = new Set<() => void>()
let sessionWired = false

function emitStatus(): void { statusSubs.forEach(fn => { try { fn() } catch (e) { console.error(e) } }) }

function wireSession(): void {
  if (sessionWired) return
  sessionWired = true
  status.user = session.user
  // 换了人（登录、退登、被顶掉）：旧数作废，按新身份重拉
  onSession(() => {
    if (session.user === status.user) return
    status.user = session.user
    status.views = null; status.trades = null; status.viewsError = null; status.tradesError = null; status.at = 0
    ownRevision.clear()
    if (loggedIn()) refreshReviewStatus(true)
    else { setMeBadge(0); emitStatus() }
  })
  hooks.onForeground.push(syncAll)
  window.addEventListener('online', syncAll)
}

/** 共用那份叠上本机还没传的改动（角标、摘要、对应的观点都按人眼里那份算） */
const viewsNow = (): ViewRecordFull[] | null => {
  if (!status.views) return null
  const ops = readOps()
  return ops.length ? status.views.map(v => M.applyPending(v, ops)) : status.views
}
const pendingNow = (): number => { const v = viewsNow(); return v ? M.pendingCount(v) : 0 }
const tallyNow = (): M.Tally => { const v = viewsNow(); return v ? M.tally(v) : { live: 0, realized: 0, unrealized: 0 } }

/** 「我的」根上复盘本那一行的两行字；没拉到之前是空串（行上先不写数） */
export function reviewRootStatus(): { line1: string; line2: string } {
  if (!loggedIn()) return { line1: M.rootLine1(false, tallyNow(), 0), line2: '' }
  return {
    line1: status.views ? M.rootLine1(true, tallyNow(), pendingNow()) : '',
    line2: status.trades ? M.rootLine2(true, status.trades, Date.now()) : '',
  }
}

/** 两行字或角标变了就叫一声；返回退订 */
export function onReviewStatus(fn: () => void): () => void {
  wireSession()
  statusSubs.add(fn)
  return () => { statusSubs.delete(fn) }
}

/** 重拉记录与交易（30 秒内重复调用不重拉；force 用在刚改过记录之后） */
export function refreshReviewStatus(force = false): void {
  wireSession()
  if (!loggedIn()) {
    setMeBadge(0)
    if (status.views || status.trades) { status.views = null; status.trades = null; emitStatus() }
    return
  }
  void flushPending()
  // 只有替同一个人拉的那一拉才挡：换了人时上一个人的那拉回来会被丢掉，新人这拉必须照发
  if (inflight && inflight.user === session.user) { if (force) inflight.again = true; return }
  if (!force && status.at && ago(status.at) < THROTTLE) return
  status.at = Date.now()
  const who = session.user
  const run = { user: who, again: false }
  inflight = run
  void Promise.allSettled([reviewApi.views(), reviewApi.trades()]).then(([v, t]) => {
    if (session.user !== who) return
    if (v.status === 'fulfilled') { status.views = v.value as ViewRecordFull[]; status.viewsError = null } else status.viewsError = errorText(v.reason)
    if (t.status === 'fulfilled') { status.trades = t.value; status.tradesError = null } else status.tradesError = errorText(t.reason)
    setMeBadge(pendingNow())
  }).finally(() => {
    if (inflight !== run) return
    inflight = null
    emitStatus()
    if (run.again && session.user === who) refreshReviewStatus(true)
  })
}

/** 改过一条：先把共用那份就地换掉（角标、摘要立刻对），再去服务端对一次 */
function patchView(r: ViewRecordFull): void {
  if (status.views) {
    const i = status.views.findIndex(x => x.draft.id === r.draft.id)
    if (i >= 0) status.views[i] = r
    setMeBadge(pendingNow())
    emitStatus()
  }
  refreshReviewStatus(true)
}
function patchTrade(t: TradeRecord): void {
  if (!status.trades) return
  const i = status.trades.findIndex(x => x.id === t.id)
  if (i >= 0) status.trades[i] = t
  emitStatus()
}

// ───────── 去图上看（复盘本 → 行情页） ─────────
/** 交给行情页回放：计划写进 sessionStorage 并发事件，只把页面切过去——实时图的品种、周期不动
 *  （回放是盖在行情页上的一层，退出回到「我的」这一摞原处，像 iOS 回放盖在复盘本上） */
function sendIntent<P extends { symbol: string; iv: string }>(kind: M.IntentKind, plan: P, where: { venue: string; market: string } | null): void {
  const detail: M.ReviewIntent<P> = { kind, at: Date.now(), plan, market: where ? `${where.venue}/${where.market}` : null }
  try { sessionStorage.setItem(M.INTENT_KEY, JSON.stringify(detail)) } catch { /* 存不下就只靠事件 */ }
  go('chart')
  window.dispatchEvent(new CustomEvent(M.INTENT_EVENT, { detail }))
}

/** 看完回放回到「我的」时，要把「当时怎么想」点亮的那一笔 */
let focusTradeNote: string | null = null

// ───────── 两页共用的「观点 · 交易」 ─────────
type Segment = 'views' | 'trades'
let segment: Segment = 'views'
let bookTab: 'all' | 'todo' | 'decided' = 'todo'
const segSubs = new Set<() => void>()
function setSegment(v: Segment): void {
  if (segment === v) return
  segment = v
  segSubs.forEach(fn => fn())
}
const segHTML = (): string =>
  `<div class="m-seg rv-seg" role="radiogroup">${([['views', '观点'], ['trades', '交易']] as const).map(([v, t]) =>
    `<button type="button" class="m-seg-opt${segment === v ? ' on' : ''}" role="radio" aria-checked="${segment === v}" data-seg="${v}">${t}</button>`).join('')}</div>`

// ───────── 小件 ─────────
const TONE: Record<string, string> = { up: 'rv-up', down: 'rv-down', danger: 'rv-danger', ink2: 'rv-ink2', ink3: 'rv-ink3' }
const tone = (k: string): string => TONE[k] ?? ''

function priceText(v: number, symbol: string, fallbackDec?: number): string {
  if (!isFinite(v)) return '—'
  const dec = S.symbols.get(symbol)?.dec ?? fallbackDec ?? priceDecimalsFallback(v)
  return fmtPrice(v, dec)
}

/** 数量原样（十进制字符串去掉尾零）；指数写法就用原文 */
function qty(s: string): string {
  const n = Number(s)
  if (!isFinite(n)) return s
  const t = String(n)
  return /e/i.test(t) ? s : t
}

const secHead = (title: string, term?: string): string =>
  `<div class="rv-sec-h">${esc(title)}${term ? termHTML(term) : ''}</div>`
const section = (title: string | null, inner: string, opts: { term?: string; cls?: string } = {}): string =>
  `<section class="rv-sec${opts.cls ? ' ' + opts.cls : ''}">${title ? secHead(title, opts.term) : ''}<div class="rv-group">${inner}</div></section>`
const kv2 = (label: string, value: string, opts: { term?: string; cls?: string } = {}): string =>
  `<div class="rv-cell rv-kv"><span class="rv-kv-k">${esc(label)}${opts.term ? termHTML(opts.term) : ''}</span><span class="rv-kv-v num${opts.cls ? ' ' + opts.cls : ''}">${esc(value)}</span></div>`
const listNote = (text: string, cls = 'rv-ink3'): string => `<div class="rv-line ${cls}">${esc(text)}</div>`
const spinner = (): string => '<div class="rv-loading" aria-label="正在加载"><span class="rv-spin"></span></div>'
const loginGate = (): string => `<div class="rv-gate"><div class="rv-line rv-ink3">登录后可用</div><button type="button" class="rv-link" data-login>登录</button></div>`

/** 一条观点记录的三行（列表行与详情顶上那一格同一份） */
function recordInner(r: ViewRecordFull): string {
  const t = M.rowText(r)
  return `<span class="rv-rec-l1"><b>${esc(t.symbol)}</b><small>${esc(t.interval)}</small><i class="${tone(t.tone)}">${esc(t.outcome)}</i></span>
    <span class="rv-rec-text${t.empty ? ' rv-ink3' : ''}">${esc(t.text)}</span>
    <span class="rv-rec-l3"><span>${esc(t.direction)}</span><span>${esc(t.origin)}</span><span class="rv-sp"></span><span class="num">${esc(t.time)}</span></span>
    ${t.foot ? `<span class="rv-rec-foot">${esc(t.foot)}</span>` : ''}`
}
const recordRow = (r: ViewRecordFull): string => `<button type="button" class="rv-rec" data-rec="${esc(r.draft.id)}">${recordInner(r)}</button>`

function tradeBadge(symbol: string, size: number): string {
  const info = S.symbols.get(symbol)
  const base = info?.base ?? M.shortSymbol(symbol)
  return `<span class="rv-badge" style="width:${size}px;height:${size}px">${badgeHTML(base, size, assetOf(info?.kind, base))}</span>`
}

/** 一笔交易的行（徽章 · 品种方向杠杆 · 持仓时长与时刻 · 盈亏或「持仓中」· 那段行情的小图） */
function tradeRow(t: TradeRecord, now: number): string {
  const r = t.round
  const open = r.status === 'open'
  const net = M.dec(r.netPnl)
  const hold = open ? '已持 ' + M.holding(now - r.openedAt) : M.holding(r.holdingMs)
  return `<button type="button" class="rv-trade" data-trade="${esc(t.id)}">
    ${tradeBadge(r.symbol, 28)}
    <span class="rv-trade-main">
      <span class="rv-trade-l1"><b>${esc(M.shortSymbol(r.symbol))}</b><em class="${r.direction === 'long' ? 'rv-up' : 'rv-down'}">${M.tradeDirection(r.direction)}</em>${r.leverage != null ? `<small>${r.leverage}x</small>` : ''}</span>
      <span class="rv-trade-l2 num"><span class="rv-hold">${esc(hold)}</span><span class="rv-trade-time">${esc(M.dayTime(r.closedAt ?? r.openedAt))}</span></span>
    </span>
    ${open ? '<span class="rv-pill">持仓中</span>' : `<span class="rv-trade-net num ${tone(M.pnlTone(net))}">${esc(M.money(net))}</span>`}
    <span class="rv-thumb" data-thumb="${esc(t.id)}" aria-hidden="true"></span>
  </button>`
}

function autoGrow(ta: HTMLTextAreaElement): void {
  ta.style.height = 'auto'
  ta.style.height = ta.scrollHeight + 'px'
}

function scroller(node: HTMLElement): HTMLElement | null { return node.closest<HTMLElement>('.me-scroll') }

// ───────── 交易那段行情的图（照 iOS ExchangeReviewBridge.chartImage：币安 U 本位合约 K 线 + 成交箭头 + 均价虚线） ─────────
const barCache = new Map<string, Promise<Bar[] | null>>()

function fetchBars(symbol: string, iv: Interval, start: number, end: number): Promise<Bar[] | null> {
  const key = `${symbol}|${iv}|${start}|${end}`
  const hit = barCache.get(key)
  if (hit) return hit
  const step = INTERVAL_STEP[iv]
  const job = (async (): Promise<Bar[] | null> => {
    const out: Bar[] = []
    let cursor = start
    while (cursor <= end && out.length < 1500) {
      const rows = await j<unknown[][]>(`${REST}/fapi/v1/klines?symbol=${encodeURIComponent(symbol)}&interval=${iv}&startTime=${cursor}&endTime=${end}&limit=1500`, 10000, true)
      if (!Array.isArray(rows) || !rows.length) break
      for (const r of rows) out.push(bar(Number(r[0]), Number(r[1]), Number(r[2]), Number(r[3]), Number(r[4]), Number(r[5])))
      const next = Number(rows[rows.length - 1][0]) + step
      if (!(next > cursor) || rows.length < 1500) break
      cursor = next
    }
    return out.length >= 2 ? out.slice(0, 1500) : null
  })().catch(() => null)
  barCache.set(key, job)
  // 拉不到的不留缓存（下次再试）；缓存最多 40 段
  void job.then(v => { if (!v) barCache.delete(key) })
  while (barCache.size > 40) barCache.delete(barCache.keys().next().value as string)
  return job
}

interface TradeBars { bars: Bar[]; iv: Interval }

/** 只有币安 U 本位合约的回合拉得到这段行情（别家 / 别的市场就留底色） */
function tradeBars(t: TradeRecord, now: number): Promise<TradeBars | null> {
  const r = t.round
  if ((r.venue && r.venue !== 'binance') || (r.market && r.market !== 'usd_m')) return Promise.resolve(null)
  let spec = M.chartSpecFor(r, t.result, now)
  if (!(spec.interval in INTERVAL_STEP)) spec = M.chartWindow(r, now)
  const iv = spec.interval as Interval
  return fetchBars(r.symbol, iv, spec.start, spec.end).then(bars => (bars ? { bars, iv } : null))
}

function drawTradeChart(canvas: HTMLCanvasElement, W: number, H: number, scale: number, t: TradeRecord, data: TradeBars, thumb: boolean): void {
  const r = t.round
  const { bars, iv } = data
  const step = INTERVAL_STEP[iv]
  const closes = bars.map(b => b.close)
  const info = S.symbols.get(r.symbol)
  const dec = info?.dec ?? M.decimalsOfCloses(closes) ?? priceDecimalsFallback(closes[closes.length - 1])
  const markers = M.tradeMarkers(r).map(m => {
    const d = makeDrawing(m.kind, { t: m.t, p: m.p }, null, null, m.id)
    if (m.dashed) d.dash = 'dashed'
    return d
  })
  const state = makeState({
    series: BarSeries.fromBars(r.symbol, iv, bars),
    symbol: { symbol: r.symbol, base: info?.base ?? M.shortSymbol(r.symbol), priceDecimals: dec },
    view: ViewWindow.fromTo(bars[0].openTime - step, bars[bars.length - 1].openTime + 2 * step),
    colors: readChartColors(),
    price: priceTransform(st.priceMode === 'percent' ? 'linear' : st.priceMode),
    overlays: [], subs: [],
    drawings: markers,
    decimals: dec,
    options: { ...appChartOptions(), drawings: true, countdown: false, sinceChange: false, lastLine: !thumb },
  })
  canvas.width = Math.round(W * scale)
  canvas.height = Math.round(H * scale)
  const ctx = canvas.getContext('2d')
  if (!ctx) return
  ctx.setTransform(scale, 0, 0, scale, 0, 0)
  new ChartRenderer(state).draw(ctx, W, H, scale, false)
}

// 列表小图：画成 216×132 的图再缩进 72×44 的格子；进屏才画，同时最多两张
const thumbCache = new Map<string, string | null>()
const thumbQueue: (() => Promise<void>)[] = []
let thumbActive = 0
const thumbKey = (t: TradeRecord): string => `${t.id}@${t.round.updatedAt}@${t.result?.chart?.end ?? 0}`

function pumpThumbs(): void {
  while (thumbActive < 2 && thumbQueue.length) {
    const job = thumbQueue.shift()!
    thumbActive++
    void job().finally(() => { thumbActive--; pumpThumbs() })
  }
}

function paintThumb(el: HTMLElement, url: string | null | undefined): void {
  if (url) el.innerHTML = `<img alt="" src="${url}">`
}

/** 给容器里每个 [data-thumb] 挂上小图；返回解绑 */
function hydrateThumbs(root: HTMLElement, find: (id: string) => TradeRecord | undefined, ioRoot: Element | null): () => void {
  const els = [...root.querySelectorAll<HTMLElement>('[data-thumb]')]
  const want = (el: HTMLElement): void => {
    const t = find(el.dataset.thumb!)
    if (!t) return
    const key = thumbKey(t)
    if (thumbCache.has(key)) { paintThumb(el, thumbCache.get(key)); return }
    thumbQueue.push(async () => {
      if (!el.isConnected) return
      if (thumbCache.has(key)) { paintThumb(el, thumbCache.get(key)); return }
      const data = await tradeBars(t, Date.now())
      let url: string | null = null
      if (data) {
        const c = document.createElement('canvas')
        drawTradeChart(c, 216, 132, 1, t, data, true)
        try { url = c.toDataURL('image/jpeg', 0.8) } catch { url = null }
      }
      thumbCache.set(key, url)
      if (el.isConnected) paintThumb(el, url)
    })
    pumpThumbs()
  }
  if (!('IntersectionObserver' in window)) { els.forEach(want); return () => {} }
  const io = new IntersectionObserver(es => {
    for (const e of es) if (e.isIntersecting) { io.unobserve(e.target); want(e.target as HTMLElement) }
  }, { root: ioRoot, rootMargin: '120px 0px' })
  for (const el of els) {
    const t = find(el.dataset.thumb!)
    if (t && thumbCache.has(thumbKey(t))) paintThumb(el, thumbCache.get(thumbKey(t)))
    else io.observe(el)
  }
  return () => io.disconnect()
}

/** 回行情页记一笔：有没记完的先切回它那只、那个周期接着写（iOS 复盘本「+」与「继续未完成的记录」同一条路） */
function startNote(host: MeHost): void {
  host.popToRoot()
  go('chart')
  requestNote()
}

// ───────── 复盘本 ─────────
export function buildReviewBook(body: HTMLElement, layer: MeLayer, host: MeHost): void {
  wireSession()
  body.classList.add('rv-book')

  // 导航栏右上：「+」记一笔（有没记完的就接着写，没有就在行情页新记）·「…」已存案例
  const trail = document.createElement('div')
  trail.className = 'rv-trail'
  trail.innerHTML = `<button type="button" class="rv-disc" data-new aria-label="记一笔">${icon('plus', 16)}</button><button type="button" class="rv-disc" data-more aria-label="更多">${icon('more', 18)}</button>`
  layer.trailing.appendChild(trail)
  trail.querySelector('[data-new]')!.addEventListener('click', () => startNote(host))
  const more = trail.querySelector<HTMLElement>('[data-more]')!
  more.addEventListener('click', () => {
    openMenu(more, [{ title: '已存案例', run: () => openSaved(host) }])
  })

  let unmount: (() => void) | null = null
  let was = loggedIn()
  const paint = (): void => {
    unmount?.(); unmount = null
    body.innerHTML = ''
    if (!loggedIn()) {
      setMeBadge(0)
      body.innerHTML = loginGate()
      body.querySelector('[data-login]')!.addEventListener('click', () => host.openLogin())
      return
    }
    unmount = mountBook(body, host)
  }
  paint()
  const offSession = onSession(() => { if (loggedIn() !== was) { was = loggedIn(); paint() } })
  layer.off.push(offSession, () => { unmount?.() })
}

function mountBook(body: HTMLElement, host: MeHost): () => void {
  body.innerHTML = `<div class="rv-top">${segHTML()}
      <div class="rv-top-views">
        <button type="button" class="rv-card rv-summary" data-stats></button>
        <div class="rv-chips" role="radiogroup"></div>
      </div>
      <div class="rv-top-trades"></div>
    </div>
    <label class="rv-search">${icon('search', 16)}<input type="search" placeholder="搜品种或笔记" enterkeyhint="search" autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false" aria-label="搜品种或笔记"><button type="button" class="rv-search-clear" aria-label="清除" hidden>${icon('close', 14)}</button></label>
    <div class="rv-list rv-views"></div>
    <div class="rv-list rv-trades"></div>`
  const top = body.querySelector<HTMLElement>('.rv-top')!
  const topViews = body.querySelector<HTMLElement>('.rv-top-views')!
  const topTrades = body.querySelector<HTMLElement>('.rv-top-trades')!
  const summary = body.querySelector<HTMLElement>('.rv-summary')!
  const chips = body.querySelector<HTMLElement>('.rv-chips')!
  // 搜索框不吸顶：iOS 的 .searchable 在导航栏抽屉里，一滑列表就收起；小屏上吸顶的一块已经占了三分之一屏
  const searchRow = body.querySelector<HTMLElement>('.rv-search')!
  const input = body.querySelector<HTMLInputElement>('.rv-search input')!
  const clear = body.querySelector<HTMLElement>('.rv-search-clear')!
  const viewsList = body.querySelector<HTMLElement>('.rv-views')!
  const tradesList = body.querySelector<HTMLElement>('.rv-trades')!
  const sc = scroller(body)

  // 列表状态（records 是服务端那份；画的时候叠上本机队列、前面插上还没传上去的记一笔）
  let records: ViewRecordFull[] = []
  let next: string | null = null
  let loading = false
  let error: string | null = null
  let seq = 0
  let q = ''
  let typingTimer: ReturnType<typeof setTimeout> | undefined

  const query = (): { todo?: boolean; decided?: boolean; q?: string } =>
    bookTab === 'todo' ? { todo: true, q } : bookTab === 'decided' ? { decided: true, q } : { q }

  async function load(reset: boolean): Promise<void> {
    if (!reset && (loading || !next)) return
    const my = ++seq
    if (reset) { records = []; next = null }
    loading = true; error = null
    paintViews()
    try {
      const page = await reviewBookApi.recordsPage(query(), reset ? null : next)
      if (my !== seq) return
      records = reset ? page.records : M.appendUnique(records, page.records)
      next = page.next
    } catch (e) {
      if (my !== seq) return
      error = errorText(e)
    }
    loading = false
    paintViews()
  }

  /** 记一笔还没传上去的那几条（按本机记录先列出来；已判定那一档里没有它们） */
  function localRows(): ViewRecordFull[] {
    if (bookTab === 'decided') return []
    const have = new Set(records.map(r => r.draft.id))
    const needle = q.toLowerCase()
    return pendingNotes()
      .filter(n => !have.has(n.draft.id))
      .map(n => M.localNoteRecord(n.draft) as ViewRecordFull)
      .filter(r => !needle || r.draft.range.symbol.toLowerCase().includes(needle) || r.draft.text.toLowerCase().includes(needle))
      .sort((a, b) => b.draft.created - a.draft.created)
  }

  function shownRecords(): ViewRecordFull[] {
    const ops = readOps()
    const all = [...localRows(), ...records]
    return ops.length ? all.map(r => M.applyPending(r, ops)) : all
  }

  function paintTop(): void {
    top.querySelectorAll<HTMLElement>('[data-seg]').forEach(b => {
      const on = b.dataset.seg === segment
      b.classList.toggle('on', on); b.setAttribute('aria-checked', String(on))
    })
    topViews.hidden = segment !== 'views'
    topTrades.hidden = segment !== 'trades'
    viewsList.hidden = segment !== 'views'
    tradesList.hidden = segment !== 'trades'
    searchRow.hidden = segment !== 'views'
    const t = tallyNow()
    const stat = (label: string, v: number | string, cls = ''): string => `<span class="rv-stat"><b class="num ${cls}">${esc(v)}</b><small>${label}</small></span>`
    summary.innerHTML = `<span class="rv-card-h"><span class="rv-card-title">战绩</span><span class="rv-sp"></span><span class="me-chev">${CHEV}</span></span>
      <span class="rv-stats">${stat('记录', t.live)}${stat('判对', t.realized)}${stat('判错', t.unrealized)}</span>`
    const pending = pendingNow()
    chips.innerHTML = ([['all', '全部'], ['todo', pending > 0 ? `待判定 ${pending}` : '待判定'], ['decided', '已判定']] as const)
      .map(([v, label]) => `<button type="button" class="rv-chip${bookTab === v ? ' on' : ''}" role="radio" aria-checked="${bookTab === v}" data-tab="${v}"><span class="num">${label}</span></button>`).join('')
    paintWeek()
  }

  function paintWeek(): void {
    const live = (status.trades ?? []).filter(t => !t.voided)
    if (!live.length) { topTrades.innerHTML = ''; return }
    const w = M.lastWeek(live.map(t => t.round), Date.now())
    const s = w.summary
    const stat = (label: string, v: string, cls = ''): string => `<span class="rv-stat"><b class="num ${cls}">${esc(v)}</b><small>${label}</small></span>`
    const extra: string[] = []
    if (s.count > 0) {
      if (s.best) extra.push(`最好 ${M.shortSymbol(s.best.symbol)} ${M.money(M.dec(s.best.netPnl))}`)
      if (s.worst && s.worst.id !== s.best?.id) extra.push(`最差 ${M.shortSymbol(s.worst.symbol)} ${M.money(M.dec(s.worst.netPnl))}`)
      extra.push(`手续费 ${M.money(s.fees, false)}`)
    }
    topTrades.innerHTML = `<button type="button" class="rv-card rv-summary" data-stats>
      <span class="rv-card-h"><span class="rv-card-title">上周</span><span class="rv-card-span num">${esc(M.weekSpan(w))}</span><span class="rv-sp"></span><span class="me-chev">${CHEV}</span></span>
      <span class="rv-stats">${stat('笔数', String(s.count))}${stat('净盈亏', s.count === 0 ? '—' : M.money(s.netPnl), s.count === 0 ? '' : tone(M.pnlTone(s.netPnl)))}${stat('胜率', M.percent(s.winRate))}</span>
      ${extra.length ? `<span class="rv-week-extra num">${extra.map(x => `<span>${esc(x)}</span>`).join('')}</span>` : ''}
    </button>`
  }

  let io: IntersectionObserver | null = null
  function paintViews(): void {
    const s = M.sections(shownRecords())
    const group = (title: string | null, list: ViewRecordFull[]): string =>
      list.length ? `<section class="rv-lsec">${title ? secHead(title) : ''}<div class="rv-rows">${list.map(recordRow).join('')}</div></section>` : ''
    const d = unfinishedNote()
    let html = d ? `<button type="button" class="rv-resume" data-resume><b>继续未完成的记录</b><small class="num">${esc(d.symbol)} · ${esc(INTERVAL_SHORT[d.interval as keyof typeof INTERVAL_SHORT] ?? d.interval)}</small><span class="me-chev">${CHEV}</span></button>` : ''
    html += bookTab === 'todo' ? group('待处理', s.pending) + group('等答案', s.waiting)
      : bookTab === 'decided' ? group(null, s.decided) : group(null, s.all)
    if (loading) html += spinner()
    if (error) html += `<div class="rv-line rv-danger">${esc(error)}</div><button type="button" class="rv-link" data-retry>重试</button>`
    if (!s.all.length && !loading && !error) html += `<div class="rv-empty">${bookTab === 'todo' ? '没有待判定的' : '还没有记录'}</div>`
    if (next && !error) html += '<div class="rv-more" aria-hidden="true"></div>'
    viewsList.innerHTML = html
    io?.disconnect()
    const more = viewsList.querySelector('.rv-more')
    if (more && 'IntersectionObserver' in window) {
      io = new IntersectionObserver(es => { if (es.some(e => e.isIntersecting)) void load(false) }, { root: sc, rootMargin: '0px 0px 240px 0px' })
      io.observe(more)
    }
  }

  let offThumbs: () => void = () => {}
  let thumbsOn = false
  function tradesHTML(now: number): string {
    if (!status.trades) {
      return status.tradesError
        ? `<div class="rv-line rv-danger">${esc(status.tradesError)}</div><button type="button" class="rv-link" data-retry-trades>重试</button>`
        : spinner()
    }
    const live = status.trades.filter(t => !t.voided)
    if (!live.length) return `<div class="rv-empty rv-ink2">接入交易所后自动生成</div>`
    const s = M.tradeSections(live, now)
    const group = (title: string, items: TradeRecord[]): string =>
      `<section class="rv-lsec">${secHead(title)}<div class="rv-rows">${items.map(t => tradeRow(t, now)).join('')}</div></section>`
    return (s.open.length ? group('持仓中', s.open) : '') + s.days.map(d => group(d.title, d.items)).join('')
  }
  /** 每分钟的「已持 N 分」、每次对数（onReviewStatus）都会来重画：内容没变就不动这块；
   *  手指按在交易行上时等松手再换，不然按着的那一行被换成新节点，点开详情落空 */
  function paintTradesNow(): void {
    const changed = setHTML(tradesList, tradesHTML(Date.now()))
    const want = segment === 'trades' && !!status.trades?.some(t => !t.voided)
    if (!changed && thumbsOn === want) return
    offThumbs(); offThumbs = () => {}; thumbsOn = false
    if (want) { offThumbs = hydrateThumbs(tradesList, id => status.trades?.find(x => x.id === id), sc); thumbsOn = true }
  }
  const tradesGate = pressGate(tradesList)
  function paintTrades(): void { tradesGate(paintTradesNow) }

  const paintAll = (): void => { paintTop(); paintTrades() }

  const openRec = (r: ViewRecordFull): void => openRecord(host, r)

  // 交互
  body.addEventListener('click', e => {
    const t = e.target as HTMLElement
    const seg = t.closest<HTMLElement>('[data-seg]')
    if (seg) { setSegment(seg.dataset.seg as Segment); return }
    const chip = t.closest<HTMLElement>('[data-tab]')
    if (chip) {
      const v = chip.dataset.tab as typeof bookTab
      if (v !== bookTab) { bookTab = v; paintTop(); if (sc) sc.scrollTop = 0; void load(true) }
      return
    }
    if (t.closest('[data-stats]')) { openStats(host); return }
    if (t.closest('[data-resume]')) { startNote(host); return }
    if (t.closest('[data-retry]')) { void (next && records.length ? load(false) : load(true)); return }
    if (t.closest('[data-retry-trades]')) { refreshReviewStatus(true); paintTrades(); return }
    const rec = t.closest<HTMLElement>('[data-rec]')
    if (rec) {
      const id = rec.dataset.rec
      const r = records.find(x => x.draft.id === id) ?? localRows().find(x => x.draft.id === id)
      if (r) openRec(r)
      return
    }
    const tr = t.closest<HTMLElement>('[data-trade]')
    if (tr) {
      const item = status.trades?.find(x => x.id === tr.dataset.trade)
      if (item) openTrade(host, item)
    }
  })
  input.addEventListener('input', () => {
    clear.hidden = !input.value
    clearTimeout(typingTimer)
    // 停手 200ms 才落定，免得每敲一个字发一次
    typingTimer = setTimeout(() => {
      const v = input.value.trim()
      if (v === q) return
      q = v
      void load(true)
    }, 200)
  })
  input.addEventListener('keydown', e => { if (e.key === 'Enter') input.blur() })
  clear.addEventListener('click', e => {
    e.preventDefault()
    input.value = ''; clear.hidden = true
    clearTimeout(typingTimer)
    if (q) { q = ''; void load(true) }
  })

  const segFn = (): void => { paintTop(); if (segment === 'trades') paintTrades() }
  segSubs.add(segFn)
  const offStatus = onReviewStatus(paintAll)
  // 队列动了：就地重画（叠的那层变了）；服务端回了新的一版：换掉手上那份；记一笔刚传上去：整张重拉
  const offRecord = onRecord((id, server) => {
    if (id === '*') { void load(true); return }
    if (server) {
      const i = records.findIndex(x => x.draft.id === server.draft.id)
      if (i >= 0) records[i] = server
    }
    paintViews()
  })
  // 隔一分钟「已持 N 分」会过时：在前台、正看交易时重画
  const tick = setInterval(() => { if (!document.hidden && segment === 'trades') paintTrades() }, 60_000)

  paintAll()
  void load(true)
  // 一打开就对一次数（战绩三个数、待判定条数、交易），并把本机没传完的补传
  refreshReviewStatus(true)
  syncAll()

  return () => {
    seq++
    clearTimeout(typingTimer)
    clearInterval(tick)
    io?.disconnect()
    offThumbs()
    segSubs.delete(segFn)
    offStatus()
    offRecord()
  }
}

// ───────── 战绩 ─────────
function openStats(host: MeHost): void {
  host.push('战绩', (body, layer) => {
    body.classList.add('rv-book', 'rv-statspage')
    body.innerHTML = `<div class="rv-top">${segHTML()}</div><div class="rv-list rv-sviews"></div><div class="rv-list rv-strades"></div>`
    const views = body.querySelector<HTMLElement>('.rv-sviews')!
    const trades = body.querySelector<HTMLElement>('.rv-strades')!
    let groups: StatGroup[] | null = null
    let err: string | null = null
    let alive = true

    function paintSeg(): void {
      body.querySelectorAll<HTMLElement>('[data-seg]').forEach(b => {
        const on = b.dataset.seg === segment
        b.classList.toggle('on', on); b.setAttribute('aria-checked', String(on))
      })
      views.hidden = segment !== 'views'
      trades.hidden = segment !== 'trades'
    }
    function paintViews(): void {
      if (!loggedIn()) { views.innerHTML = `<div class="rv-line rv-ink3">登录后可用</div><button type="button" class="rv-link" data-login>登录</button>`; return }
      if (err) { views.innerHTML = `<div class="rv-line rv-danger">${esc(err)}</div>`; return }
      if (!groups) { views.innerHTML = spinner(); return }
      if (!groups.length) { views.innerHTML = `<div class="rv-line rv-ink3">暂无已判定样本</div>`; return }
      views.innerHTML = `<div class="rv-rows">${groups.map(g => {
        const short = g.verdictStatus === 'insufficient'
        return `<div class="rv-srow"><span class="rv-srow-text"><span class="rv-srow-title">${esc(g.title)}</span><small class="num">${g.total} 条有效记录</small></span><span class="${short ? 'rv-rate-short' : 'rv-rate num'}">${esc(groupRateText(g))}</span></div>`
      }).join('')}</div>`
    }
    /** 每次对数都会来：内容没变不动（「？」解释按在手上时不被换掉） */
    function paintTrades(): void { setHTML(trades, statTradesHTML()) }
    function statTradesHTML(): string {
      if (!status.trades) return status.tradesError ? `<div class="rv-line rv-danger">${esc(status.tradesError)}</div>` : spinner()
      const rounds = status.trades.filter(t => !t.voided).map(t => t.round)
      const s = M.summarize(rounds)
      if (s.count === 0) return rounds.length ? `<div class="rv-line rv-ink3">暂无平仓的交易</div>` : `<div class="rv-line rv-ink2">接入交易所后自动生成</div>`
      const metric = (label: string, value: string, opts: { term?: string; cls?: string } = {}): string =>
        `<div class="rv-metric"><span>${esc(label)}${opts.term ? termHTML(opts.term) : ''}</span><b class="num${opts.cls ? ' ' + opts.cls : ''}">${esc(value)}</b></div>`
      const group = (title: string, rows: M.RoundGroup[]): string => rows.length ? `<section class="rv-lsec">${secHead(title)}<div class="rv-rows">${rows.map(g =>
        `<div class="rv-srow"><span class="rv-srow-text"><span class="rv-srow-title">${esc(g.title)}</span><small class="num">${g.summary.count} 笔 · 胜率 ${esc(M.percent(g.summary.winRate))}</small></span><b class="rv-srow-net num ${tone(M.pnlTone(g.summary.netPnl))}">${esc(M.money(g.summary.netPnl))}</b></div>`).join('')}</div></section>` : ''
      return `<div class="rv-rows">
          ${metric('笔数', String(s.count))}
          ${metric('胜率', M.percent(s.winRate))}
          ${metric('盈亏比', M.ratio(s.rewardRisk), { term: 'rvRewardRisk' })}
          ${metric('每笔期望', s.expectancy == null ? '—' : M.money(s.expectancy), { term: 'rvExpectancy' })}
          ${metric('净盈亏', M.money(s.netPnl), { cls: tone(M.pnlTone(s.netPnl)) })}
          ${metric('费用占毛利', M.percent(s.feeShareOfGross), { term: 'rvFeeShare' })}
          ${metric('最长连亏', `${s.longestLosingStreak} 笔`)}
          ${metric('平均持仓', M.holding(s.averageHoldingMs))}
        </div>
        ${group('按品种', M.bySymbol(rounds))}${group('按方向', M.byDirection(rounds))}${group('按持仓时长', M.byHolding(rounds))}${group('按开仓时段', M.bySession(rounds))}${group('按周几', M.byWeekday(rounds))}`
    }

    body.addEventListener('click', e => {
      const t = e.target as HTMLElement
      const seg = t.closest<HTMLElement>('[data-seg]')
      if (seg) setSegment(seg.dataset.seg as Segment)
      else if (t.closest('[data-login]')) host.openLogin()
    })
    const segFn = (): void => paintSeg()
    segSubs.add(segFn)
    const offStatus = onReviewStatus(paintTrades)
    layer.off.push(() => { alive = false; segSubs.delete(segFn); offStatus() })
    paintSeg(); paintViews(); paintTrades()
    if (loggedIn()) {
      reviewApi.statistics().then(s => { groups = resolvedGroups(s) }, e => { err = errorText(e) }).finally(() => { if (alive) paintViews() })
    }
  })
}

// ───────── 记录详情 ─────────
function openRecord(host: MeHost, initial: ViewRecordFull): void {
  host.push('记录详情', (body, layer) => {
    body.classList.add('rv-detail')
    const id = initial.draft.id
    /** 服务端那份（本机记一笔还没传上去的，是按本机草稿拼的那份） */
    let server = initial
    let extra: M.Revisions = {}
    let hasShot = false
    let shot: string | null = null
    let alive = true
    const view = (): ViewRecordFull & { conflict?: M.OpConflict | null } => M.applyPending(server, readOps())
    let baseNote = view().reflection?.note ?? ''
    let baseNext = view().reflection?.nextTime ?? ''
    const symbol = initial.draft.range.symbol
    const price = (v: number): string => priceText(v, symbol)
    const isLocal = (): boolean => server.serverId == null && pendingNotes().some(n => n.draft.id === id)

    body.innerHTML = `<div class="rv-d-top"></div><div class="rv-d-attach"></div><div class="rv-d-answer"></div>
      <section class="rv-sec">${secHead('现在怎么看')}<div class="rv-group"><div class="rv-cell rv-ta"><textarea rows="3" data-max="8" placeholder="当时的判断，哪些成立" aria-label="现在怎么看" data-f="note"></textarea></div></div></section>
      <section class="rv-sec">${secHead('下次怎么做')}<div class="rv-group"><div class="rv-cell rv-ta"><textarea rows="2" data-max="6" placeholder="同样的局面再来，改哪儿" aria-label="下次怎么做" data-f="next"></textarea></div></div></section>
      <section class="rv-sec"><div class="rv-group"><button type="button" class="rv-cell rv-btn rv-ink2" data-act="draft">保存草稿</button><button type="button" class="rv-cell rv-btn rv-strong" data-act="publish">完成复盘</button></div></section>
      <div class="rv-d-bottom"></div>`
    const topBox = body.querySelector<HTMLElement>('.rv-d-top')!
    const attachBox = body.querySelector<HTMLElement>('.rv-d-attach')!
    const answerBox = body.querySelector<HTMLElement>('.rv-d-answer')!
    const bottomBox = body.querySelector<HTMLElement>('.rv-d-bottom')!
    const noteTa = body.querySelector<HTMLTextAreaElement>('[data-f="note"]')!
    const nextTa = body.querySelector<HTMLTextAreaElement>('[data-f="next"]')!
    noteTa.value = baseNote; nextTa.value = baseNext
    for (const ta of [noteTa, nextTa]) {
      const max = Number(ta.dataset.max)
      ta.style.maxHeight = `calc(${max} * 1.35em + 2px)`
      ta.addEventListener('input', () => autoGrow(ta))
    }

    const attach = mountAttachments(attachBox, () => (server.serverId ? id : null))
    layer.off.push(attach.destroy)

    function paint(): void {
      const r = view()
      const dir = r.draft.rule.direction
      const o = M.outcome(r)
      const parts: string[] = []
      parts.push(section(null, `<div class="rv-cell rv-rec rv-rec-static">${recordInner(r)}</div>`))
      // 有一次上传服务端不收：内容一直在本机，人只需要拍一次板
      if (r.conflict) {
        parts.push(section('没能同步', listNote(r.conflict.reason, 'rv-ink2') + (r.conflict.retryable
          ? '<button type="button" class="rv-cell rv-btn" data-act="keepLocal">用我这份</button><button type="button" class="rv-cell rv-btn" data-act="keepRemote">用云端那份</button>'
          : '<button type="button" class="rv-cell rv-btn" data-act="keepLocal">留在本机</button>'), { cls: 'rv-conflict' }))
      }
      if (M.assessmentMoved(extra)) parts.push(section('结果有更新', listNote('这条的结果在你写完复盘之后变过，再看一眼', 'rv-ink2')))
      if (r.groupPending === true && !r.voided) parts.push(section('这次判断', listNote('与最近一笔是同一次判断吗？', 'rv-ink2')
        + '<button type="button" class="rv-cell rv-btn" data-act="same">同一次判断</button><button type="button" class="rv-cell rv-btn" data-act="apart">独立判断</button>'))
      let when = kv2('区间', `${r.draft.range.bars} 根 · ${M.intervalShort(r.draft.range.interval)}`)
      if (dir !== 'observe') {
        when += kv2('目标', price(r.draft.rule.target)) + kv2('失效', price(r.draft.rule.invalidation))
          + kv2('判定', M.CONFIRM_TITLE[r.draft.rule.confirmation] ?? r.draft.rule.confirmation) + kv2('到期', M.fullTime(r.draft.rule.expires))
      }
      when += '<button type="button" class="rv-cell rv-btn" data-act="chart">在图上重温</button><button type="button" class="rv-cell rv-btn" data-act="search">找相似</button>'
      parts.push(section('当时', when))
      if (shot) parts.push(section('当时那张图', `<div class="rv-cell rv-shotcell"><img class="rv-shot" alt="当时那张图" src="${esc(shot)}"></div>`))
      const linked = status.trades ? M.roundsForView(r, status.trades, Date.now()) : []
      if (linked.length) parts.push(section('对应的交易', linked.map(t => `<div class="rv-cell rv-linkrow">${tradeRow(t, Date.now())}</div>`).join(''), { cls: 'rv-links' }))
      topBox.innerHTML = parts.join('')
      offThumbs()
      if (linked.length) offThumbs = hydrateThumbs(topBox, tid => status.trades?.find(x => x.id === tid), scroller(body))

      answerBox.innerHTML = section('市场的答案', `<div class="rv-cell rv-answer"><b>${esc(M.OUTCOME_TITLE[o])}</b>${r.assessment ? `<small>${esc(r.assessment.reason)}</small>` : ''}</div>`)

      const tail: string[] = []
      const hist = r.reflectionHistory ?? []
      if (hist.length) tail.push(section('历史复盘', hist.map(h => listNote(h.note || '未写内容', h.note ? 'rv-ink2' : 'rv-ink3')).join('')))
      if (r.serverId) tail.push(section(null, `<button type="button" class="rv-cell rv-btn rv-nav" data-act="revisions"><span>修订记录</span><span class="me-chev">${CHEV}</span></button>`))
      if (!r.voided) tail.push(section(null, '<button type="button" class="rv-cell rv-btn rv-danger" data-act="void">作废记录</button>'))
      bottomBox.innerHTML = tail.join('')
      attach.refresh()
    }
    let offThumbs: () => void = () => {}

    /** 人正在写的不去冲掉：只有没动过才跟（服务端 + 本机队列）那份对齐 */
    function syncFields(): void {
      const r = view()
      const sn = r.reflection?.note ?? '', sx = r.reflection?.nextTime ?? ''
      if (noteTa.value === baseNote) noteTa.value = sn
      if (nextTa.value === baseNext) nextTa.value = sx
      baseNote = sn; baseNext = sx
      autoGrow(noteTa); autoGrow(nextTa)
    }

    function apply(r: ViewRecordFull): void {
      server = r
      syncFields()
      if (alive) paint()
    }

    async function loadDetail(): Promise<void> {
      if (isLocal()) return
      try {
        const d = await reviewBookApi.recordDetail(id)
        if (!alive) return
        extra = { assessmentRevision: d.assessmentRevision, reflectionAssessmentRevision: d.reflectionAssessmentRevision }
        apply({ ...d.record, groupPending: d.groupPending })
        if (d.hasShot && !hasShot) {
          hasShot = true
          reviewBookApi.recordShot(id).then(s => {
            if (!alive || !s?.image) return
            shot = `data:${s.mime || 'image/png'};base64,${s.image}`
            paint()
          }, () => { /* 图拉不到就不出这一格 */ })
        }
      } catch { /* 详情拉不到：留着手上那一份 */ }
    }

    function save(publish: boolean): void {
      if (publish && M.publishBlocked(noteTa.value)) { toast('先写一句复盘'); return }
      noteTa.blur(); nextTa.blur()
      if (publish) haptic()
      const note = noteTa.value, nextTime = nextTa.value
      enqueue(server, 'reflection', { expectedRevision: server.revision, reflection: { note, nextTime, publishedAt: null, revision: 0 }, publish })
      baseNote = note; baseNext = nextTime
    }

    const offRecord = onRecord((rid, srv) => {
      if (!alive) return
      if (rid === '*') { if (server.serverId == null && !isLocal()) void loadDetail(); return }
      if (rid !== id) { paint(); return }
      if (srv) { server = { ...srv, groupPending: srv.groupPending ?? server.groupPending }; void loadDetail() }
      syncFields()
      paint()
    })
    const offStatus = onReviewStatus(() => { if (alive) paint() })

    body.addEventListener('click', async e => {
      const b = (e.target as HTMLElement).closest<HTMLElement>('[data-act]')
      if (!b) return
      switch (b.dataset.act) {
        case 'draft': save(false); break
        case 'publish': save(true); break
        case 'chart': sendIntent('revisit', planNote(view(), Date.now()), view().draft.range); break
        case 'search': openSearch(host, view()); break
        case 'same': case 'apart':
          haptic()
          enqueue(server, 'group', { expectedRevision: server.revision, sameEpisode: b.dataset.act === 'same' })
          break
        case 'keepLocal': await resolveConflict(id, true); if (alive) void loadDetail(); break
        case 'keepRemote': await resolveConflict(id, false); if (alive) { syncFields(); void loadDetail() } break
        case 'revisions': openRevisions(host, view()); break
        case 'void': {
          const yes = await confirmDialog({ title: '作废后保留内容，退出战绩统计', confirm: '作废记录', destructive: true })
          if (!yes || !alive) return
          const op = enqueue(server, 'void', { expectedRevision: server.revision }, M.VOID_HOLD_MS)
          toast('已作废', {
            title: '撤销',
            run: () => {
              const list = readOps()
              const o = list.find(x => x.id === op.id)
              if (!o || o.attempted) return
              writeOps(list.filter(x => x.id !== op.id))
              emitRecord(id)
            },
          })
          break
        }
      }
    })

    // 退出这一页时，写了没存的当草稿存一份（照 iOS onDisappear）
    layer.off.push(() => {
      alive = false
      offRecord(); offStatus(); offThumbs()
      if (view().voided) return
      const note = noteTa.value, nextTime = nextTa.value
      if (note === baseNote && nextTime === baseNext) return
      enqueue(server, 'reflection', { expectedRevision: server.revision, reflection: { note, nextTime, publishedAt: null, revision: 0 }, publish: false })
    })

    paint()
    requestAnimationFrame(() => { autoGrow(noteTa); autoGrow(nextTa) })
    void loadDetail()
  })
}

// ───────── 补图（照 iOS ReviewAttachmentsSection：最多三张，横翻，单张 ≤ 5 MB） ─────────
function mountAttachments(box: HTMLElement, recordId: () => string | null): { refresh(): void; destroy(): void } {
  let list: ReviewAttachment[] | null = null
  let loadedFor: string | null = null
  const images = new Map<string, string>()
  let busy = false
  let error: string | null = null
  let alive = true
  let index = 0
  const file = document.createElement('input')
  file.type = 'file'; file.accept = 'image/*'; file.hidden = true
  box.after(file)

  async function load(rid: string, toLast = false): Promise<void> {
    try {
      const items = await reviewBookApi.attachments(rid)
      if (!alive) return
      list = items
      loadedFor = rid
      if (toLast) index = Math.max(0, items.length - 1)
      paint()
      for (const a of items) {
        if (images.has(a.id)) continue
        reviewBookApi.attachment(a.id).then(x => {
          if (!alive || !x?.image) return
          images.set(a.id, `data:${x.mime || a.mime || 'image/jpeg'};base64,${x.image}`)
          const page = box.querySelector<HTMLElement>(`[data-att="${CSS.escape(a.id)}"] .rv-att-img`)
          if (page) page.innerHTML = `<img alt="补图" src="${images.get(a.id)}">`
        }, () => { /* 这张拉不到：留着转圈那一格的底色 */ })
      }
    } catch (e) {
      if (!alive) return
      list = list ?? []
      loadedFor = rid
      error = errorText(e)
      paint()
    }
  }

  function paint(): void {
    const rid = recordId()
    if (!loggedIn() || !rid) { box.innerHTML = ''; return }
    const items = list ?? []
    const count = items.length
    const pager = count ? `<div class="rv-cell rv-att-cell">
        <div class="rv-att-pager">${items.map(a => `<div class="rv-att-page" data-att="${esc(a.id)}">
          <div class="rv-att-img">${images.has(a.id) ? `<img alt="补图" src="${images.get(a.id)}">` : '<span class="rv-spin"></span>'}</div>
          <button type="button" class="rv-att-del" data-del="${esc(a.id)}" aria-label="删除这张图"><span>${icon('trash', 16)}</span></button>
        </div>`).join('')}</div>
        ${count > 1 ? `<div class="rv-att-dots" aria-hidden="true">${items.map((_, i) => `<i${i === index ? ' class="on"' : ''}></i>`).join('')}</div>` : ''}
      </div>` : ''
    const full = count >= M.ATTACH_LIMIT
    box.innerHTML = section('补图', `${pager}
      <button type="button" class="rv-cell rv-btn rv-nav rv-att-add" data-add${busy || full || list == null ? ' disabled' : ''}><span>补一张图</span>${busy ? '<span class="rv-spin"></span>' : `<span class="num rv-ink3">${list == null ? '' : `${count}/${M.ATTACH_LIMIT}`}</span>`}</button>
      ${error ? listNote(error, 'rv-danger') : ''}`)
    const pg = box.querySelector<HTMLElement>('.rv-att-pager')
    if (pg) {
      requestAnimationFrame(() => { pg.scrollLeft = index * pg.clientWidth })
      pg.addEventListener('scroll', () => {
        const i = Math.round(pg.scrollLeft / Math.max(1, pg.clientWidth))
        if (i === index) return
        index = i
        box.querySelectorAll('.rv-att-dots i').forEach((d, k) => d.classList.toggle('on', k === i))
      }, { passive: true })
    }
  }

  async function encode(f: File): Promise<string | null> {
    const url = URL.createObjectURL(f)
    try {
      const img = await new Promise<HTMLImageElement>((res, rej) => {
        const i = new Image()
        i.onload = () => res(i); i.onerror = () => rej(new Error('decode'))
        i.src = url
      })
      const w = img.naturalWidth, h = img.naturalHeight
      if (!w || !h) return null
      for (const s of M.jpegSteps()) {
        const k = M.fitScale(w, h, s.side)
        const c = document.createElement('canvas')
        c.width = Math.max(1, Math.round(w * k)); c.height = Math.max(1, Math.round(h * k))
        const ctx = c.getContext('2d')
        if (!ctx) return null
        ctx.drawImage(img, 0, 0, c.width, c.height)
        const b64 = c.toDataURL('image/jpeg', s.quality).split(',')[1] ?? ''
        if (b64 && M.base64Bytes(b64) <= M.ATTACH_MAX_BYTES) return b64
      }
      return null
    } catch { return null } finally { URL.revokeObjectURL(url) }
  }

  file.addEventListener('change', async () => {
    const f = file.files?.[0]
    file.value = ''
    const rid = recordId()
    if (!f || !rid || busy) return
    busy = true; error = null; paint()
    const b64 = await encode(f)
    if (!alive) return
    if (!b64) { busy = false; error = '这张图读不出来'; paint(); return }
    try {
      await reviewBookApi.putAttachment(uuid(), rid, b64)
      if (!alive) return
      busy = false
      await load(rid, true)
    } catch (e) {
      if (!alive) return
      busy = false; error = errorText(e); paint()
    }
  })

  box.addEventListener('click', async e => {
    const t = e.target as HTMLElement
    const rid = recordId()
    if (!rid) return
    if (t.closest('[data-add]')) { if (!busy) file.click(); return }
    const del = t.closest<HTMLElement>('[data-del]')
    if (del) {
      const yes = await confirmDialog({ title: '删除这张图？', confirm: '删除', destructive: true })
      if (!yes || !alive) return
      busy = true; error = null; paint()
      try {
        await reviewBookApi.deleteAttachment(del.dataset.del!)
        images.delete(del.dataset.del!)
      } catch (err) { error = errorText(err) }
      if (!alive) return
      busy = false
      index = Math.min(index, Math.max(0, (list?.length ?? 1) - 2))
      await load(rid)
    }
  })

  return {
    refresh(): void {
      const rid = recordId()
      if (!loggedIn() || !rid) { box.innerHTML = ''; return }
      if (loadedFor !== rid) { if (list == null) paint(); void load(rid) } else if (!box.firstChild) paint()
    },
    destroy(): void { alive = false; file.remove() },
  }
}

// ───────── 找相似（照 iOS ReviewSearchView / ReviewSearchModel） ─────────
function openSearch(host: MeHost, rec: ViewRecordFull): void {
  const range = rec.draft.range
  const cutoff = rec.draft.created
  let run = 0
  let sid: string | null = null
  let timer: ReturnType<typeof setTimeout> | undefined
  let wake: (() => void) | null = null
  let searching = false
  let progress: SearchStatus | null = null
  let error: string | null = null
  let items: Match[] = []
  let next: string | null = null
  let partial = false
  let loadingMore = false
  let done = false
  const savedIds = new Set<string>()
  let swipes: SwipeHandle[] = []
  let root: HTMLElement | null = null

  const sleep = (ms: number): Promise<void> => new Promise(res => { wake = res; timer = setTimeout(res, ms) })

  function cancel(): void {
    run++
    clearTimeout(timer)
    wake?.(); wake = null
    if (sid) { const id = sid; sid = null; void reviewBookApi.cancelSearch(id).catch(() => {}) }
    searching = false
  }

  async function start(): Promise<void> {
    cancel()
    const my = run
    error = null; items = []; next = null; progress = null; partial = false; done = false
    savedIds.clear()
    if (!loggedIn()) { paint(); return }
    if (range.bars < M.MIN_SEARCH_BARS) { error = M.MIN_SEARCH_TEXT; paint(); return }
    const id = uuid()
    sid = id
    searching = true
    paint()
    const t0 = Date.now()
    const sched = new M.PollSchedule()
    try {
      let s = await reviewBookApi.startSearch(id, range, cutoff, st.reviewSearchScope)
      while (my === run && (s.status === 'queued' || s.status === 'running')) {
        progress = s; paint()
        const wait = sched.next(s.checked, Date.now() - t0)
        if (wait == null) {
          void reviewBookApi.cancelSearch(id).catch(() => {})
          sid = null
          throw { code: 'search_timeout' }
        }
        await sleep(wait)
        if (my !== run) return
        try { s = await reviewBookApi.searchStatus(id) } catch (e) {
          if (e instanceof ReviewError && M.keepsPolling(e.status)) continue
          throw e
        }
      }
      if (my !== run) return
      if (s.status !== 'completed') throw s.status === 'cancelled' ? { code: 'search_cancelled' } : { code: 'search_incomplete', status: 503 }
      const page = await reviewBookApi.searchResultsPage(id)
      if (my !== run) return
      items = page.items
      next = page.next
      partial = page.partial ?? true
      done = true
    } catch (e) {
      if (my !== run) return
      error = e instanceof ReviewError ? errorText(e) : M.failureMessage(e as M.FailureLike)
    }
    searching = false
    progress = null
    paint()
  }

  async function loadMore(): Promise<void> {
    if (!sid || !next || loadingMore) return
    const my = run
    loadingMore = true; paint()
    try {
      const page = await reviewBookApi.searchResultsPage(sid, next)
      if (my !== run) return
      items = M.appendMatches(items, page.items)
      next = page.next
      partial = partial || (page.partial ?? false)
    } catch (e) { if (my === run) toast(errorText(e)) }
    loadingMore = false
    paint()
  }

  function paint(): void {
    if (!root) return
    swipes.forEach(s => s.destroy()); swipes = []
    const scope = st.reviewSearchScope
    const seg = `<div class="m-seg rv-seg rv-scope" role="radiogroup">${([['history', '市场历史'], ['private', '我的记录']] as const).map(([v, t]) =>
      `<button type="button" class="m-seg-opt${scope === v ? ' on' : ''}" role="radio" aria-checked="${scope === v}" data-scope="${v}">${t}</button>`).join('')}</div>`
    let inner = ''
    if (!loggedIn()) {
      inner = `<div class="rv-sstate"><div class="rv-ink3">登录后可用</div><button type="button" class="rv-link" data-login>登录</button></div>`
    } else if (searching && !items.length) {
      inner = `<div class="rv-sstate"><span class="rv-spin"></span><div class="rv-ink2 num">${esc(M.searchProgressText(progress))}</div><button type="button" class="rv-link" data-cancel>取消</button></div>`
    } else if (error) {
      inner = `<div class="rv-sstate"><div class="rv-danger">${esc(error)}</div>${range.bars < M.MIN_SEARCH_BARS ? '' : '<button type="button" class="rv-link" data-retry>重试</button>'}</div>`
    } else if (done && !items.length) {
      inner = `<div class="rv-sstate"><div class="rv-ink3">没有很像的区间</div></div>`
    } else if (items.length) {
      inner = `${partial ? `<div class="rv-scaption">部分行情暂缺，已列出完成比对的结果</div>` : ''}
        <div class="rv-group rv-matches">${items.map(m => {
          const t = M.matchRowText(m)
          return `<div class="rv-mrow-wrap"><button type="button" class="rv-cell rv-mrow" data-match="${esc(m.id)}">
            <span class="rv-mrow-l"><b>${esc(t.title)}</b><small class="num">${esc(t.time)} · ${esc(t.bars)}</small></span>
            <span class="rv-mrow-score num">${esc(t.score)}</span><span class="me-chev">${CHEV}</span>
          </button></div>`
        }).join('')}</div>
        ${next ? `<button type="button" class="rv-link rv-smore" data-more${loadingMore || searching ? ' disabled' : ''}>${loadingMore ? '<span class="rv-spin"></span>' : '更多结果'}</button>` : ''}`
    }
    root.innerHTML = seg + inner
    root.querySelectorAll<HTMLElement>('.rv-mrow-wrap').forEach(wrap => {
      const mid = wrap.querySelector<HTMLElement>('[data-match]')!.dataset.match!
      const saved = savedIds.has(mid)
      swipes.push(swipeRow(wrap, {
        trailing: [{
          id: 'save', title: saved ? '已保存' : '保存', fill: 'var(--accent)',
          run: () => {
            if (savedIds.has(mid) || !sid) return
            const searchId = sid
            reviewBookApi.saveMatch(searchId, mid).then(() => { savedIds.add(mid); paint() }, e => toast(errorText(e)))
          },
        }],
        fullSwipe: false,
      }))
    })
  }

  const sheet = openSheet(body => {
    body.classList.add('rv-sheet')
    root = document.createElement('div')
    root.className = 'rv-search-body'
    body.appendChild(root)
    root.addEventListener('click', e => {
      const t = e.target as HTMLElement
      const sc = t.closest<HTMLElement>('[data-scope]')
      if (sc) {
        const v = sc.dataset.scope as typeof st.reviewSearchScope
        if (v !== st.reviewSearchScope) { st.reviewSearchScope = v; saveState(); void start() }
        return
      }
      if (t.closest('[data-cancel]')) { cancel(); sheet.close(); return }
      if (t.closest('[data-retry]')) { void start(); return }
      if (t.closest('[data-login]')) { sheet.close(); host.openLogin(); return }
      if (t.closest('[data-more]')) { void loadMore(); return }
      const row = t.closest<HTMLElement>('[data-match]')
      if (row) {
        const m = items.find(x => x.id === row.dataset.match)
        if (!m) return
        sheet.close()
        sendIntent('match', planMatch(m, cutoff), m.range)
      }
    })
    paint()
  }, { title: '找相似', detent: 'large', className: 'rv-search-sheet', onClose: () => { cancel(); swipes.forEach(s => s.destroy()); swipes = [] } })
  void start()
}

// ───────── 已存案例（照 iOS ReviewSavedMatchesView） ─────────
function openSaved(host: MeHost): void {
  host.push('已存案例', (body, layer) => {
    body.classList.add('rv-detail')
    let items: SavedMatch[] = []
    let next: string | null = null
    let loading = false
    let error: string | null = null
    let alive = true
    let seq = 0
    let swipes: SwipeHandle[] = []
    let io: IntersectionObserver | null = null

    async function load(reset: boolean): Promise<void> {
      if (!loggedIn()) { paint(); return }
      if (!reset && (loading || !next)) return
      const my = ++seq
      loading = true; error = null
      if (reset) { items = []; next = null }
      paint()
      try {
        const page = await reviewBookApi.savedPage(reset ? null : next)
        if (!alive || my !== seq) return
        const seen = new Set(items.map(x => x.item.id))
        items = [...items, ...page.items.filter(x => !seen.has(x.item.id))]
        next = page.next
      } catch (e) {
        if (!alive || my !== seq) return
        error = errorText(e)
      }
      loading = false
      paint()
    }

    function paint(): void {
      swipes.forEach(s => s.destroy()); swipes = []
      io?.disconnect()
      if (!loggedIn()) { body.innerHTML = loginGate(); return }
      let html = ''
      if (items.length) {
        html += `<div class="rv-group rv-matches">${items.map(s => {
          const t = M.matchRowText(s.item)
          return `<div class="rv-mrow-wrap"><button type="button" class="rv-cell rv-mrow" data-saved="${esc(s.item.id)}">
            <span class="rv-mrow-l"><b>${esc(t.title)}</b><small class="num">${esc(t.time)} · ${esc(t.bars)}</small></span>
            <span class="rv-mrow-score num">${esc(t.score)}</span><span class="me-chev">${CHEV}</span>
          </button></div>`
        }).join('')}</div>`
      }
      if (loading) html += spinner()
      if (error) html += `<div class="rv-line rv-danger">${esc(error)}</div><button type="button" class="rv-link" data-retry>重试</button>`
      if (!items.length && !loading && !error) html += `<div class="rv-empty">还没有存下的案例</div>`
      if (next && !error) html += '<div class="rv-more" aria-hidden="true"></div>'
      body.innerHTML = html
      body.querySelectorAll<HTMLElement>('.rv-mrow-wrap').forEach(wrap => {
        const sid = wrap.querySelector<HTMLElement>('[data-saved]')!.dataset.saved!
        swipes.push(swipeRow(wrap, {
          trailing: [deleteAction(() => {
            const s = items.find(x => x.item.id === sid)
            if (!s) return
            items = items.filter(x => x !== s)
            paint()
            reviewBookApi.unsaveMatch(s.item.id, s.revision).catch(e => {
              if (!alive) return
              toast(errorText(e))
              void load(true)
            })
          })],
        }))
      })
      const more = body.querySelector('.rv-more')
      if (more && 'IntersectionObserver' in window) {
        io = new IntersectionObserver(es => { if (es.some(e => e.isIntersecting)) void load(false) }, { root: scroller(body), rootMargin: '0px 0px 240px 0px' })
        io.observe(more)
      }
    }

    body.addEventListener('click', e => {
      const t = e.target as HTMLElement
      if (t.closest('[data-login]')) { host.openLogin(); return }
      if (t.closest('[data-retry]')) { void load(items.length > 0 && !!next ? false : true); return }
      const row = t.closest<HTMLElement>('[data-saved]')
      if (row) {
        const s = items.find(x => x.item.id === row.dataset.saved)
        if (s) sendIntent('match', planMatch(s.item, Date.now()), s.item.range)
      }
    })
    const offSession = onSession(() => { if (alive) void load(true) })
    layer.off.push(() => { alive = false; seq++; io?.disconnect(); swipes.forEach(s => s.destroy()); offSession() })
    void load(true)
  })
}

// ───────── 修订记录 ─────────
function openRevisions(host: MeHost, rec: ViewRecordFull): void {
  host.push('修订记录', (body, layer) => {
    body.classList.add('rv-detail')
    let alive = true
    layer.off.push(() => { alive = false })
    body.innerHTML = spinner()
    const price = (v: number): string => priceText(v, rec.draft.range.symbol)
    reviewBookApi.revisions(rec.draft.id).then(list => {
      if (!alive) return
      const shown = M.visibleRevisions(list)
      if (!shown.length) { body.innerHTML = `<div class="rv-line rv-ink3">还没有上传过，暂无修订</div>`; return }
      body.innerHTML = section(null, shown.map(r => `<div class="rv-cell rv-rev">
        <span class="rv-rev-h"><b>${esc(M.revisionTitle(r))}</b><small class="num">${esc(M.fullTime(r.at))}</small></span>
        ${M.revisionLines(r, price).map(l => `<span class="rv-rev-l">${esc(l)}</span>`).join('')}</div>`).join(''))
    }, e => { if (alive) body.innerHTML = `<div class="rv-line rv-danger">${esc(errorText(e))}</div>` })
  })
}

// ───────── 交易详情 ─────────
function openTrade(host: MeHost, initial: TradeRecord): void {
  host.push('交易详情', (body, layer) => {
    body.classList.add('rv-detail')
    let item = initial
    let alive = true
    let loaded = item.note?.text ?? ''
    let chartKey = ''
    body.innerHTML = `<div class="rv-d-top"></div>
      <section class="rv-sec rv-note-sec">${secHead('当时怎么想')}<div class="rv-group"><div class="rv-cell rv-ta"><textarea rows="3" data-max="8" placeholder="开这一笔时在想什么" aria-label="当时怎么想"></textarea></div><button type="button" class="rv-cell rv-btn rv-strong" data-act="save" disabled>保存</button></div></section>
      <div class="rv-d-bottom"></div>`
    const topBox = body.querySelector<HTMLElement>('.rv-d-top')!
    const bottomBox = body.querySelector<HTMLElement>('.rv-d-bottom')!
    const ta = body.querySelector<HTMLTextAreaElement>('textarea')!
    const saveBtn = body.querySelector<HTMLButtonElement>('[data-act="save"]')!
    ta.value = loaded
    ta.style.maxHeight = 'calc(8 * 1.35em + 2px)'
    const syncSave = (): void => { saveBtn.disabled = ta.value === loaded }
    ta.addEventListener('input', () => { autoGrow(ta); syncSave() })

    function paint(): void {
      const r = item.round
      const open = r.status === 'open'
      const net = M.dec(r.netPnl)
      const dec = S.symbols.get(r.symbol)?.dec ?? roundDecimals(r)
      const p = (s: string | null): string => s == null ? '—' : priceText(M.dec(s), r.symbol, dec)
      const now = Date.now()
      const parts: string[] = []
      parts.push(section(null, `<div class="rv-cell rv-th">
        <span class="rv-th-l1">${tradeBadge(r.symbol, 28)}<b>${esc(M.shortSymbol(r.symbol))}</b><em class="${r.direction === 'long' ? 'rv-up' : 'rv-down'}">${M.tradeDirection(r.direction)}</em>${r.leverage != null ? `<small>${r.leverage}x</small>` : ''}<span class="rv-sp"></span>${open ? '<i class="rv-accent">持仓中</i>' : `<strong class="num ${tone(M.pnlTone(net))}">${esc(M.money(net))}</strong>`}</span>
        <span class="rv-th-l2 num"><span>${esc(M.fullTime(r.openedAt))}</span>${r.closedAt != null ? `<span>→</span><span>${esc(M.fullTime(r.closedAt))}</span>` : ''}</span></div>`))
      parts.push(section(null, `<div class="rv-cell rv-tchart-cell"><div class="rv-tchart${open ? '' : ' rv-tchart-tap'}" data-chart${open ? '' : ' role="button" aria-label="回放这笔交易"'}><canvas></canvas>${open ? '' : `<button type="button" class="rv-play" data-act="replay" aria-label="回放这笔交易">${PLAY}</button>`}</div></div>`))
      parts.push(section('成交', r.fills.map(f => fillRow(f, r, p)).join('') || listNote('—'), { term: 'rvFills' }))
      let settle = kv2('开仓均价', p(r.openAvgPrice))
      if (r.closeAvgPrice != null) settle += kv2('平仓均价', p(r.closeAvgPrice))
      settle += kv2('最大仓位', `${qty(r.maxQty)} · ${M.money(M.dec(r.peakNotional), false)}`)
      settle += kv2('已实现', M.money(M.dec(r.realizedPnl)), { term: 'rvRealized' })
      settle += kv2('手续费', M.money(-M.dec(r.commission)))
      if (M.dec(r.funding) !== 0) settle += kv2('资金费', M.money(M.dec(r.funding)))
      settle += kv2('持仓', open ? '已持 ' + M.holding(now - r.openedAt) : M.holding(r.holdingMs))
      parts.push(section('结算', settle))
      if (!open) {
        const x = item.result?.excursion
        parts.push(section('持仓期间', x
          ? kv2('最大浮盈', `${M.money(M.dec(x.maxFavorable))} · ${M.percent(x.maxFavorablePct, true)}`)
            + kv2('最大浮亏', `${M.money(M.dec(x.maxAdverse))} · ${M.percent(x.maxAdversePct, true)}`)
            + kv2('盈亏比', M.ratio(x.rewardRisk), { term: 'rvTradeRewardRisk' })
          : kv2('最大浮盈', '—') + kv2('最大浮亏', '—') + kv2('盈亏比', '—', { term: 'rvTradeRewardRisk' })))
        const after = item.result?.after
        parts.push(section('离开后', ([['h1', '1 小时'], ['h4', '4 小时'], ['h24', '24 小时']] as const).map(([k, label]) => {
          const pt = after?.[k]
          return pt ? kv2(label, M.percent(pt.changePct, true), { cls: tone(M.pnlTone(M.dec(pt.changePct))) }) : kv2(label, '—', { cls: 'rv-ink3' })
        }).join(''), { term: 'rvAfterClose' }))
      }
      topBox.innerHTML = parts.join('')
      chartKey = ''
      void paintChart()
      paintViews()
    }

    /** 对应的观点：同品种、时间段有交叠（叠上本机还没传的改动） */
    function paintViews(): void {
      const views = viewsNow()
      const list = views ? M.viewsForRound(item.round, views, Date.now()) : []
      bottomBox.innerHTML = list.length ? section('对应的观点', list.map(v => `<div class="rv-cell rv-linkrow">${recordRow(v)}</div>`).join(''), { cls: 'rv-links' }) : ''
    }

    async function paintChart(): Promise<void> {
      const box = topBox.querySelector<HTMLElement>('[data-chart]')
      const canvas = box?.querySelector('canvas')
      if (!box || !canvas) return
      const key = thumbKey(item)
      chartKey = key
      const data = await tradeBars(item, Date.now())
      if (!alive || chartKey !== key || !canvas.isConnected) return
      if (!data) { box.classList.add('rv-tchart-empty'); return }
      const W = Math.max(200, Math.round(box.clientWidth)), H = 220
      drawTradeChart(canvas, W, H, window.devicePixelRatio || 1, item, data, false)
      canvas.style.width = W + 'px'; canvas.style.height = H + 'px'
    }

    function replay(): void {
      if (item.round.status === 'open') return
      ta.blur()
      focusTradeNote = item.id
      sendIntent('trade', planTrade(item.round, item.result, Date.now(), item.note?.text || null, st.interval), item.round)
    }

    function apply(t: TradeRecord): void {
      item = t
      const server = t.note?.text ?? ''
      if (ta.value === loaded) ta.value = server
      loaded = server
      autoGrow(ta); syncSave()
      patchTrade(t)
      if (alive) paint()
    }

    async function refetch(): Promise<void> {
      try { const t = await reviewBookApi.tradeDetail(item.id); if (alive) apply(t) } catch { /* 留着手上这份 */ }
    }

    async function save(): Promise<boolean> {
      const text = ta.value
      try {
        const t = await reviewBookApi.saveTradeNote(item.id, item.revision, text)
        loaded = text
        if (alive) apply(t); else patchTrade(t)
        return true
      } catch (e) {
        if (e instanceof ReviewError && (e.status === 409 || e.code === 'record_revision_changed')) {
          toast('这条在别的设备上改过了，已换成最新的')
          await refetch()
        } else toast(errorText(e))
        return false
      }
    }

    body.addEventListener('click', e => {
      const t = e.target as HTMLElement
      if (t.closest('[data-act="replay"]') || t.closest('.rv-tchart-tap')) { replay(); return }
      const rec = t.closest<HTMLElement>('[data-rec]')
      if (rec) {
        const v = viewsNow()?.find(x => x.draft.id === rec.dataset.rec)
        const raw = status.views?.find(x => x.draft.id === rec.dataset.rec)
        if (raw ?? v) openRecord(host, (raw ?? v)!)
      }
    })
    saveBtn.addEventListener('click', () => { ta.blur(); saveBtn.disabled = true; void save().then(() => syncSave()) })

    // 看完回放回到「我的」：这笔还没写过「当时怎么想」，就滚到那一节、把输入框点亮（照 iOS focusTradeNote）
    const onPage = (page: string): void => {
      if (page !== 'me' || focusTradeNote !== item.id || !alive) return
      focusTradeNote = null
      if (!host.isTop(layer) || (item.note?.text ?? '') !== '' || ta.value !== '') return
      setTimeout(() => {
        if (!alive) return
        ta.scrollIntoView({ block: 'center', behavior: 'smooth' })
        ta.focus({ preventScroll: true })
      }, 350)
    }
    hooks.onPage.push(onPage)
    const offStatus = onReviewStatus(() => { if (alive) paintViews() })
    const offRecord = onRecord(() => { if (alive) paintViews() })
    const onResize = (): void => { chartKey = ''; void paintChart() }
    window.addEventListener('resize', onResize)

    layer.off.push(() => {
      alive = false
      const i = hooks.onPage.indexOf(onPage)
      if (i >= 0) hooks.onPage.splice(i, 1)
      offStatus(); offRecord()
      window.removeEventListener('resize', onResize)
      if (ta.value !== loaded) void save()
    })
    paint()
    requestAnimationFrame(() => { autoGrow(ta); chartKey = ''; void paintChart() })
    void refetch()
  })
}

function fillRow(f: Fill, r: Round, p: (s: string) => string): string {
  void r
  const realized = M.dec(f.realizedPnl)
  return `<div class="rv-cell rv-fill">
    <span class="rv-fill-l1"><b class="${f.side === 'BUY' ? 'rv-up' : 'rv-down'}">${esc(M.FILL_ROLE[f.role] ?? f.role)}</b><span class="num">${esc(p(f.price))}</span><span class="num rv-ink2">× ${esc(qty(f.qty))}</span><span class="rv-sp"></span>${realized !== 0 ? `<span class="num ${tone(M.pnlTone(realized))}">${esc(M.money(realized))}</span>` : ''}</span>
    <span class="rv-fill-l2 num"><span>${esc(M.dayTime(f.time))}</span><span>${f.maker ? '挂单' : '吃单'}</span><span>手续费 ${esc(qty(f.commission))} ${esc(f.commissionAsset)}</span></span>
  </div>`
}
