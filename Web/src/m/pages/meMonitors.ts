/* 手机网页版 · 「我的 › 设置 › 通知」底下那两样常驻的监听，外加个性化学习与收件箱的启动
 *
 * 1. 自选波动提醒（照 iOS Alerts/WatchMoveMonitor.swift + MainScreen.wireWatchMove）：
 *    开关 watchMoveAlert（随账号同步，服务端读同一份、后台那一半由它判）；盯当前自选，订它们的 ticker，
 *    按 1 分钟桶喂给 m/model/watchMove.ts 的 MoveTracker。响了：提示条「BTC 五分钟涨 3.21% · 查看」+ 铃声，
 *    页面在后台时弹系统通知（正文「现价 X」）；记一笔给个性化学习。切后台扔掉分钟收盘（断过的流不算连续），闸留着。
 *    关掉就全清，再打开从缺口重新开始。
 * 2. 品种上新与停牌下架（照 iOS Alerts/ListingNotices.swift）：开关 notifyListingChanges 开着且登录着时，
 *    回前台、每一轮同步跑完、页面开着时每 10 分钟拉一次 GET /v1/alerts/listing-notices；两次至少隔 20 秒。
 *    每条只出一次（本机按账号记游标）。出法：系统通知（前台也弹）；没给通知权限时页面里出一条提示条。
 */
import { st, subscribe } from '../app/store'
import { hooks, openSymbol } from '../app/shell'
import { S, on, streamName } from '../../market'
import { session, onSession, loggedIn } from '../../account/session'
import { authed } from '../../account/client'
import { onSyncStatus, syncStatus } from '../app/sync'
import { baseOf, priceLabel } from '../../alerts/shape'
import { canonicalInstrument } from '../chart/draw/instrument'
import { toast } from '../ui/toast'
import { MoveTracker, WM, moveNotifyId, moveTitle, type MoveEvent } from '../model/watchMove'
import { LN, cursorKey, noticeSymbol, planNotices, readNotices, type ListingNotice } from '../model/listingNotices'
import { notify, notifyPermission } from './notify'
import { wantStreams } from './_streams'
import { noteWatchMoveFired, startHabits, watchMoveFactor } from './habitsRuntime'
import { startInbox } from './inboxStore'
import { ago } from '../../util/clock'

// ───────── 自选波动提醒 ─────────

/** 最多盯多少只（网关线路一共只给 160 路流，别把行情页的挤掉） */
const MOVE_MAX = 100

let tracker = new MoveTracker()
let moveOn = false
let moveFavs = new Map<string, string>() // 代号 → 规范键

function settleMove(): void {
  const on = st.watchMoveAlert
  if (on !== moveOn) {
    moveOn = on
    if (!on) tracker = new MoveTracker()
  }
  const list = on ? st.symbols.favorites.slice(0, MOVE_MAX) : []
  const next = new Map(list.map(s => [s.toUpperCase(), canonicalInstrument(s)]))
  const same = next.size === moveFavs.size && [...next.keys()].every(k => moveFavs.has(k))
  if (same) return
  moveFavs = next
  tracker.keep(next.values())
  wantStreams('watchMove', [...next.keys()].map(s => streamName.ticker(s)))
}

function observeMove(symbol: string): void {
  if (!moveOn || document.visibilityState !== 'visible') return
  const key = moveFavs.get(symbol)
  if (!key) return
  const price = S.symbols.get(symbol)?.price
  if (price == null || !Number.isFinite(price)) return
  const now = Date.now()
  const event = tracker.observe(key, now - (now % WM.barMs), price, false, watchMoveFactor(key))
  if (event) fireMove(symbol, event)
}

function fireMove(symbol: string, e: MoveEvent): void {
  noteWatchMoveFired(e.symbol)
  const title = moveTitle(baseOf(symbol), e)
  toast(title, { title: '查看', run: () => openSymbol(symbol) })
  notify({ title, body: '现价 ' + priceLabel(e.price, S.symbols.get(symbol)?.dec), tag: moveNotifyId(e), symbol, foreground: 'sound' })
}

// ───────── 上新下架 ─────────

const LISTING_POLL_MS = 10 * 60_000
let inflight = false
const lastPull = new Map<string, number>()

function readCursor(owner: string): number | null {
  try { const v = localStorage.getItem(cursorKey(owner)); return v == null ? null : (Number.isFinite(+v) ? +v : null) } catch { return null }
}

export async function pullListingNotices(): Promise<void> {
  const owner = session.userId
  if (!st.notifyListingChanges || !owner || inflight) return
  if (ago(lastPull.get(owner) ?? 0) < LN.minIntervalMs) return
  inflight = true
  lastPull.set(owner, Date.now())
  try {
    const page = await authed<unknown>('GET', '/v1/alerts/listing-notices')
    if (session.userId !== owner) return
    const plan = planNotices(readNotices(page), readCursor(owner), Date.now())
    if (plan.cursor != null) try { localStorage.setItem(cursorKey(owner), String(plan.cursor)) } catch { /* 忽略 */ }
    presentNotices(plan.show)
  } catch { /* 拉不到下次再拉 */ } finally { inflight = false }
}

function presentNotices(list: readonly ListingNotice[]): void {
  const granted = notifyPermission() === 'granted'
  for (const n of list) {
    const symbol = noticeSymbol(n)
    notify({ title: n.title, body: n.body, tag: 'listing.' + n.id, symbol, foreground: 'banner' })
  }
  // 没给通知权限：页面开着时至少在页里说一声（只说最新那条，免得一串提示条）
  if (!granted && list.length && document.visibilityState === 'visible') {
    const n = list[0]
    const symbol = noticeSymbol(n)
    toast(n.title, symbol && n.event !== 'delisted' ? { title: '查看', run: () => openSymbol(symbol) } : undefined)
  }
}

// ───────── 启动 ─────────

let started = false
/** 启动（幂等）：由提醒监听 startAlertWatcher 顺带调 */
export function startMeMonitors(): void {
  if (started) return
  started = true
  startHabits()
  startInbox()

  settleMove()
  subscribe(settleMove)
  on(e => { if (e.type === 'ticker') observeMove(e.symbol) })
  hooks.onBackground.push(() => tracker.forgetPrices())
  document.addEventListener('visibilitychange', () => { if (document.visibilityState !== 'visible') tracker.forgetPrices() })

  // 上新下架：回前台、同步跑完、定时、开关刚打开、刚登录
  hooks.onForeground.push(() => { void pullListingNotices() })
  let lastSync = syncStatus().lastSync
  onSyncStatus(() => {
    const s = syncStatus()
    if (s.lastSync && s.lastSync !== lastSync) { lastSync = s.lastSync; void pullListingNotices() }
  })
  let listingOn = st.notifyListingChanges
  subscribe(() => {
    if (st.notifyListingChanges !== listingOn) { listingOn = st.notifyListingChanges; if (listingOn) void pullListingNotices() }
  })
  onSession(() => { if (loggedIn()) void pullListingNotices() })
  setInterval(() => { if (document.visibilityState === 'visible') void pullListingNotices() }, LISTING_POLL_MS)
  void pullListingNotices()
}
