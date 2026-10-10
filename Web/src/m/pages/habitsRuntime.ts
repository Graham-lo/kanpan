/* 手机网页版 · 「自动适应」（个性化学习）的运行时（照 iOS Habits/Habits.swift）
 *
 * 规则与推断全在 m/model/habits.ts；这里只做接线：看屏幕上在看什么、计停留、记事件、把推出来的结论写回设置。
 * 读结论的一侧已经在各页里：图表页换品种时用学到的周期、价格轴用学到的那档（chart.ts learnedInterval /
 * effectivePriceMode）。这里补上：
 * - 停留：图在人眼前（行情页、前台）时按「品种 × 周期 × 价格轴」分段计秒数，一段结束记一条 interval（+ axisDwell）。
 * - 亲手切价格轴：图表设置里点线性 / 对数时调 notePriceAxisPicked（照 iOS ChartPanel → Habits.notePriceAxisPicked），
 *   记一条 axisPick 进日志、当场重推结论——亲手选的立刻压过之前的停留。
 * - 板块页今日 / 5 日：本机亲手切的记一条；一次启动里每个市场按学到的那档摆一次，之后人怎么点就怎么是。
 * - 自选波动提醒：响了记 moveFired；15 分钟内打开那只记 moveOpened；灵敏度倍数由 watchMoveFactor 给监听用。
 * - 开关关掉（本机或别的设备）、结论被清空（清除已学到的、恢复默认、别的设备清的）：日志跟着删。
 * 日志只留在本机、一个账号一份（localStorage）；随账号同步的只有结论（Prefs.learnedDefaults）。
 * 「本机亲手改」与「云端装进来」的区分：云端那一下在 settle 里先 save() 再同步调 hooks.onSync，
 * 所以订阅回调里先记下变化、放到微任务里再判，onSync 报过的键就不算本机改的。
 */
import { st, save, subscribe } from '../app/store'
import { hooks } from '../app/shell'
import { homeSeg, onHomeSeg, refreshSectors } from '../app/homeSeg'
import { sameValue, emptyLearned, type PriceMode } from '../app/prefs'
import { session, onSession } from '../../account/session'
import { S, on } from '../../market'
import { canonicalInstrument } from '../chart/draw/instrument'
import { habitCategory, priceModeFor } from './chart/logic'
import { pairOf } from '../model/symKey'
import { H, AXIS_VALUES, SECTOR_VALUES, appendLog, learn, learnedEmpty, mergedLearned, pruneLog, readLog, type HabitEvent } from '../model/habits'

const LOG_KEY = (owner: string): string => 'kanpan.habits.log.v1.' + (owner || 'guest')
const nowSec = (): number => Date.now() / 1000

interface Focus { symbol: string; interval: string; category: string; priceMode: PriceMode; visible: boolean }
const sameFocus = (a: Focus | null, b: Focus): boolean =>
  !!a && a.symbol === b.symbol && a.interval === b.interval && a.category === b.category && a.priceMode === b.priceMode && a.visible === b.visible

let log: HabitEvent[] = []
let loadedOwner: string | null = null
let focus: Focus | null = null
let segment: { focus: Focus; mode: string; start: number } | null = null
const sectorApplied = new Set<string>()
/** 自己在改设置（摆学到的板块档、清结论）时不把它当成人的选择 */
let selfEditing = false

const owner = (): string => session.userId ?? ''
const enabled = (): boolean => st.habitLearning

function withLog<T>(fn: (l: HabitEvent[]) => T, write = false): T {
  const o = owner()
  if (o !== loadedOwner) {
    loadedOwner = o
    try { log = readLog(JSON.parse(localStorage.getItem(LOG_KEY(o)) || '[]')) } catch { log = [] }
    pruneLog(log, nowSec())
  }
  const out = fn(log)
  if (write) {
    try {
      if (log.length) localStorage.setItem(LOG_KEY(o), JSON.stringify(log))
      else localStorage.removeItem(LOG_KEY(o))
    } catch { /* 存不下就只留在内存里 */ }
  }
  return out
}

/** 记下、落盘、重推结论；结论变了才写回设置（写回随账号同步） */
function record(events: HabitEvent[]): void {
  if (!enabled() || !events.length) return
  const t = nowSec()
  const l = withLog(l => { for (const e of events) appendLog(l, e, t); return l.slice() }, true)
  const next = mergedLearned(st.learnedDefaults, learn(l, t), t)
  if (!sameValue(next, st.learnedDefaults)) {
    selfEditing = true
    try { st.learnedDefaults = next; save() } finally { selfEditing = false }
  }
}

const categoryOf = (sym: string): string => habitCategory(S.symbols.get(sym)?.kind, pairOf(sym, S.symbols.get(sym)).base)
const effectiveMode = (sym: string, mode = st.priceMode): string =>
  priceModeFor(mode, st.habitLearning, st.learnedDefaults.priceAxis[categoryOf(sym)]?.v)

function currentFocus(): Focus {
  return {
    symbol: st.symbol, interval: st.interval, category: categoryOf(st.symbol), priceMode: st.priceMode,
    visible: st.page === 'chart' && document.visibilityState === 'visible',
  }
}

function closeSegment(): void {
  const seg = segment
  segment = null
  if (!seg || !enabled()) return
  const seconds = Math.min(H.maxDwell, nowSec() - seg.start)
  if (seconds < H.minDwell) return
  const key = canonicalInstrument(seg.focus.symbol)
  if (!key) return
  const t = nowSec()
  const batch: HabitEvent[] = [{ t, kind: 'interval', key, value: seg.focus.interval, w: seconds }]
  if (AXIS_VALUES.includes(seg.mode)) batch.push({ t, kind: 'axisDwell', key: seg.focus.category, value: seg.mode, w: seconds })
  record(batch)
}

function setFocus(next: Focus): void {
  if (sameFocus(focus, next)) return
  closeSegment()
  focus = next
  if (next.visible && enabled()) segment = { focus: next, mode: effectiveMode(next.symbol, next.priceMode), start: nowSec() }
}

/** 刚响过波动提醒（15 分钟内、还没点开过）的那只被打开了 */
function noteOpened(symbol: string): void {
  if (!enabled()) return
  const key = canonicalInstrument(symbol)
  if (!key) return
  const t = nowSec()
  const hit = withLog(l => {
    let fired: HabitEvent | undefined
    for (let i = l.length - 1; i >= 0; i--) if (l[i].kind === 'moveFired' && l[i].key === key) { fired = l[i]; break }
    if (!fired || t - fired.t > H.moveOpenWindow) return false
    const f = fired
    return !l.some(e => e.kind === 'moveOpened' && e.key === key && e.t >= f.t)
  })
  if (hit) record([{ t, kind: 'moveOpened', key }])
}

/** 板块（首页第四段）此刻站着、看得见 */
const sectorsVisible = (): boolean => st.page === 'home' && homeSeg() === 'sectors'

/** 板块页这个市场这次启动还没摆过：按学到的那档摆一次 */
function applySectorWindow(): void {
  const market = st.sectorMarket
  if (!enabled() || sectorApplied.has(market)) return
  sectorApplied.add(market)
  const w = st.learnedDefaults.sectorWindow[market]?.v
  if (!w || !SECTOR_VALUES.includes(w) || w === st.sectorWindow) return
  selfEditing = true
  try { st.sectorWindow = w as typeof st.sectorWindow; save() } finally { selfEditing = false }
  refreshSectors()
}

function clearLog(): void {
  segment = null
  withLog(l => { l.length = 0 }, true)
}

// ───────── 对外 ─────────

/** 自选波动提醒幅度要乘的倍数（规范键） */
export function watchMoveFactor(key: string): number {
  if (!enabled()) return 1
  const f = st.learnedDefaults.watchMove[key]?.v
  return typeof f === 'number' && Number.isFinite(f) ? f : 1
}

/** 图表设置里亲手切了线性 / 对数（照 iOS Habits.notePriceAxisPicked）：切之前那段按旧的那档记完，
 *  记一笔 axisPick 并重推结论（按习惯时它立刻生效），再从新那档起一段。调用方随后照旧把 priceMode 写进设置。
 *  百分比不参与；学习关着不记。category 传图上那只的类别（chart.ts axisCategory）。 */
export function notePriceAxisPicked(mode: string, category: string = categoryOf(st.symbol)): void {
  if (!enabled() || !AXIS_VALUES.includes(mode) || !category) return
  closeSegment()
  record([{ t: nowSec(), kind: 'axisPick', key: category, value: mode }])
  if (focus?.visible) segment = { focus, mode, start: nowSec() }
}

/** 自选波动提醒响了 */
export function noteWatchMoveFired(key: string): void {
  if (!enabled() || !key) return
  record([{ t: nowSec(), kind: 'moveFired', key }])
}

/** 设置里那颗开关。关掉：结论立刻清空、日志删掉、不再记 */
export function setHabitLearning(onOff: boolean): void {
  if (onOff) { st.habitLearning = true; save(); setFocus(currentFocus()); return }
  segment = null
  clearLog()
  selfEditing = true
  try { st.habitLearning = false; st.learnedDefaults = emptyLearned(); save() } finally { selfEditing = false }
}

/** 「清除已学到的」：结论与日志都清掉，开关不动 */
export function clearLearned(): void {
  clearLog()
  selfEditing = true
  try { st.learnedDefaults = emptyLearned(); save() } finally { selfEditing = false }
  focus = null
  setFocus(currentFocus())
}

let started = false
/** 启动（幂等） */
export function startHabits(): void {
  if (started) return
  started = true
  let seen = { symbol: st.symbol, priceMode: st.priceMode, interval: st.interval, sectorWindow: st.sectorWindow, sectorMarket: st.sectorMarket }
  let lastSwitch = { enabled: st.habitLearning, empty: learnedEmpty(st.learnedDefaults), owner: owner() }
  let pending: { prev: typeof seen; selfMade: boolean } | null = null
  let remote = new Set<string>()

  const settle = (): void => {
    const p = pending
    pending = null
    const cur = seen
    const fromCloud = remote
    remote = new Set()
    if (!p) return
    // 别处（另一台设备、恢复默认、这里自己）关掉了 / 清空了：本机日志跟着删
    const sw = { enabled: st.habitLearning, empty: learnedEmpty(st.learnedDefaults), owner: owner() }
    if (sw.owner === lastSwitch.owner && ((lastSwitch.enabled && !sw.enabled) || (!lastSwitch.empty && sw.empty))) clearLog()
    lastSwitch = sw
    if (!enabled()) { segment = null; focus = null; return }
    if (p.selfMade) return
    // 板块页亲手切了今日 / 5 日
    if (cur.sectorWindow !== p.prev.sectorWindow && !fromCloud.has('sectorWindow') && cur.sectorMarket === p.prev.sectorMarket
      && SECTOR_VALUES.includes(cur.sectorWindow)) {
      sectorApplied.add(cur.sectorMarket)
      record([{ t: nowSec(), kind: 'sectorWindow', key: cur.sectorMarket, value: cur.sectorWindow }])
    }
    if (cur.sectorMarket !== p.prev.sectorMarket && sectorsVisible()) applySectorWindow()
  }

  subscribe(() => {
    const prev = seen
    seen = { symbol: st.symbol, priceMode: st.priceMode, interval: st.interval, sectorWindow: st.sectorWindow, sectorMarket: st.sectorMarket }
    if (seen.symbol !== prev.symbol) noteOpened(seen.symbol)
    // 价格轴切换前那一段按旧的那档记完：setFocus 先 closeSegment 再开新段
    setFocus(currentFocus())
    if (!pending) { pending = { prev, selfMade: selfEditing }; queueMicrotask(settle) }
    else if (selfEditing) pending.selfMade = true
  })
  hooks.onSync.push(ch => { for (const k of ch.settings) remote.add(k) })
  hooks.onPage.push(() => { setFocus(currentFocus()); if (sectorsVisible()) applySectorWindow() })
  onHomeSeg(() => { if (sectorsVisible()) applySectorWindow() })
  hooks.onBackground.push(() => setFocus(currentFocus()))
  hooks.onForeground.push(() => setFocus(currentFocus()))
  document.addEventListener('visibilitychange', () => setFocus(currentFocus()))
  // 品种表到了：类别从「不知道」变成真的类别，换一段
  on(e => { if (e.type === 'universe') setFocus(currentFocus()) })
  // 换账号：上一段归上一个人；日志换一份
  onSession(() => { closeSegment(); focus = null; lastSwitch = { enabled: st.habitLearning, empty: learnedEmpty(st.learnedDefaults), owner: owner() }; setFocus(currentFocus()) })
  // 关页面前把这一段记完
  addEventListener('pagehide', () => closeSegment())
  setFocus(currentFocus())
  // 这次启动：当前那个市场先按学到的摆好（板块页还没打开也行，打开就是它）
  applySectorWindow()
}
