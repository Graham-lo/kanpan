/* Hkline Web · K 线回放（自由回放，对标 TradingView「Bar Replay」）
 *
 * 一次只有一格在回放（当前格），其余格子照常实时。流程：
 *   ⌥ R / 格子底栏「回放」→ 选起点（竖线跟着鼠标，点一下定；或在回放条上打时间）
 *   → 这一格的数据源由回放接管：图上只留起点及左边的 K 线（至少再往左 300 根，指标按当时的样子算），
 *     实时推送对这一格停住；「未来」的 K 线从 REST 预取（起点之后 600 根，快播完再补），从不拿推送
 *   → 播放 / 暂停、1–16 倍速、拖进度线、跳到起点；切周期在新周期上按同一时刻重新定位，换品种退出
 *   → 退出：整份重取实时数据、跳回最新。回放状态不落盘、不同步，刷新页面即退出。
 *
 * 图表引擎不认识回放：它看到的就是一份「历史 + 已播」的 K 线，播一根 = updateBar 推一根，
 * 指标沿用引擎的懒重算（一帧最多算一次），所以指标与副图只按可见数据算，画线、十字线照常。
 * 页面（pages/chart.ts）只挂几行：按钮、⌥ R、loadCell 开头一句 replayLoad、推送 / 补尾巴跳过 replaying 的格子、头部报价。
 */
import type { Bar } from '../chart/calc'
import type { TVChart, ChartLayer, ChartMetaInput } from '../chart/chart'
import { klines, klinesFrom, attachOI } from '../market'
import { isCustomIv, customBase, customKlines, aggregate } from '../chart/intervals'
import { IV_MS, fmt } from '../util/format'
import { toast, dialogs } from '../ui/overlay'
import { cls, pctText, sym } from '../ui/common'
import * as M from './model'
import { ReplayBar, PickOverlay, type BarState } from './bar'

/** 页面上一格的样子（pages/chart.ts 的 Cell 结构上满足它） */
export interface ReplayCell { idx: number; el: HTMLElement; host: HTMLElement; chart: TVChart; loadToken: number; hold: string | null }
export interface ReplayEnv {
  cfg(cell: ReplayCell): { symbol: string; iv: string }
  meta(cell: ReplayCell): ChartMetaInput
  /** 整份重取实时数据（loadCell），取到后调 then */
  reload(cell: ReplayCell, then: () => void): void
  active(): ReplayCell | undefined
  /** 头部报价与标签页标题按实时重画（退出回放时） */
  quote(): void
}

/** 图右边空出的根数（和引擎的 RIGHT_MARGIN_BARS 一致） */
const MARGIN = 6

interface Session {
  cell: ReplayCell
  symbol: string
  iv: string
  /** 起点的回放钟（起点那一根的收线时刻） */
  start: number
  /** 当前回放钟 */
  clock: number
  /** 还没播的 K 线（升序） */
  future: Bar[]
  /** 未来已经取到最新了，没有下一页 */
  ended: boolean
  playing: boolean
  speed: number
  timer: ReturnType<typeof setTimeout> | null
  /** 取数代号：切周期 / 改起点 / 退出时作废在路上的取数 */
  token: number
  busy: boolean
  /** 整份重摆（定起点、切周期）在取数 */
  loading: boolean
  /** 拖进度线拖到了还没取到的地方：取到后再落过去 */
  want: number | null
  /** 整份重摆还在取数时又拖到了别处：取到后再落到这里 */
  again: number | null
  /** 回放期间收起来的外挂绘制层（订单流是实时的，不能画到过去） */
  layers: ChartLayer[]
  ui: ReplayBar
}

interface Pick { cell: ReplayCell; ui: ReplayBar; overlay: PickOverlay }

let env: ReplayEnv | null = null
let sess: Session | null = null
let pick: Pick | null = null

export function installReplay(e: ReplayEnv): void {
  env = e
  window.addEventListener('keydown', onKey)
}

/** 这一格的数据源是不是被回放接管了（推送、补尾巴都跳过它） */
export function replaying(cell: ReplayCell): boolean { return sess?.cell === cell }

/** ⌥ R / 底栏按钮：没在回放就进选起点，选起点或回放中就退出 */
export function toggleReplay(cell: ReplayCell): void {
  if (!env) return
  if (sess?.cell === cell) { exit(sess); return }
  if (pick?.cell === cell) { cancelPick(); return }
  const { iv } = env.cfg(cell)
  if (!M.canReplay(iv)) { toast('秒级周期不能回放', '换到 1 分钟或更大的周期再试', 'info'); return }
  if (sess) exit(sess)
  cancelPick()
  startPick(cell)
}

/** loadCell 开头调：true = 这一格由回放接管，loadCell 就此返回 */
export function replayLoad(cell: ReplayCell): boolean {
  if (!env) return false
  const c = env.cfg(cell)
  paintButton(cell, c.iv)
  if (pick?.cell === cell && !M.canReplay(c.iv)) cancelPick()
  const s = sess
  if (!s || s.cell !== cell) return false
  if (c.symbol !== s.symbol) { exit(s, false); return false }
  if (!M.canReplay(c.iv)) { exit(s, false); toast('秒级周期不能回放', '已回到实时', 'info'); return false }
  if (c.iv !== s.iv) { s.iv = c.iv; void place(s, s.clock, null) }
  return true
}

/** 头部最新价 / 涨跌与标签页标题：当前格在回放就按当前那根 K 线写（patchDetail / renderDetail / syncTitle 末尾调） */
export function paintReplayQuote(): void {
  const s = sess
  if (!s || !env || s.cell !== env.active()) return
  const ch = s.cell.chart, q = M.quoteAt(ch.bars, ch.bars.length, s.iv); if (!q) return
  const sy = sym(s.symbol), dec = sy?.dec ?? ch.meta.dec
  const price = fmt(q.price, dec)
  const big = document.querySelector<HTMLElement>('#detail [data-f="big"]')
  if (big) { big.textContent = price; big.className = `big num price-live ${cls(q.pct)}` }
  const chg = document.querySelector<HTMLElement>('#detail [data-f="chg"]')
  if (chg) { chg.textContent = `${q.chg >= 0 ? '+' : ''}${fmt(q.chg, dec)}  ${pctText(q.pct)}`; chg.className = `chg num ${cls(q.pct)}` }
  document.title = `${sy?.code ?? s.symbol} ${price} ${pctText(q.pct)} · 回放 · Hkline`
}

/** 底栏「回放」按钮：秒级周期置灰并说明，回放中 / 选起点时亮着。
 *  2026-10-10 起整页只有一条全局底栏（#chartFoot，作用于当前格）：只画当前格的状态，切当前格时页面调 paintReplayButton */
function paintButton(cell: ReplayCell, iv = env?.cfg(cell).iv ?? ''): void {
  if (!env || cell !== env.active()) return
  const b = document.querySelector<HTMLElement>('#chartFoot [data-act="replay"]'); if (!b) return
  const ok = M.canReplay(iv), on = sess?.cell === cell || pick?.cell === cell
  b.setAttribute('aria-disabled', String(!ok))
  b.setAttribute('aria-pressed', String(on))
  b.dataset.tip = !ok ? 'K 线回放：秒级周期不能回放' : on ? '退出回放' : 'K 线回放：选一个起点，一根一根往后播'
}

/** 当前格换了（或底栏刚建好）：底栏「回放」按钮按当前格重画 */
export function paintReplayButton(): void { const c = env?.active(); if (c) paintButton(c) }

// ------------------------------------------------------------ 选起点
function startPick(cell: ReplayCell): void {
  const ui = new ReplayBar(cell.host, {
    toggle: () => {}, speed: () => {}, seek: () => {}, toStart: () => {},
    exit: cancelPick, cancel: cancelPick,
    startAt: text => { const t = M.parseShTime(text); if (t == null) { badTime(); return } void begin(cell, t) },
  })
  ui.pick()
  const overlay = new PickOverlay(cell.chart, () => env?.cfg(cell).iv ?? '1m', t => { void begin(cell, t) })
  pick = { cell, ui, overlay }
  paintButton(cell)
}
function cancelPick(): void {
  const p = pick; if (!p) return
  p.overlay.destroy(); p.ui.destroy(); pick = null
  paintButton(p.cell)
}
function badTime(): void { toast('时间没看懂', '照 2026-10-04 21:30 这样写（上海时间）', 'info') }

/** 在时刻 t 定起点（选起点时点的、回放条上打的） */
async function begin(cell: ReplayCell, t: number): Promise<void> {
  if (!env || cell.chart.dead) return
  const { symbol, iv } = env.cfg(cell)
  const now = Date.now(), start = M.clockAtStart(t, iv), stop = M.liveEnd(now, iv)
  if (start >= stop) { toast('起点要早于最新一根 K 线', '', 'info'); return }
  let s = sess?.cell === cell ? sess : null
  if (!s) {
    if (cell.hold) { toast('K 线还在加载，稍等再定起点', '', 'info'); return }
    if (sess) exit(sess)
    cancelPick()
    // 作废这一格在路上的取数（往左翻页、补尾巴）：它们按实时那份数据算的
    cell.loadToken++
    const ch = cell.chart
    s = {
      cell, symbol, iv, start, clock: start, future: [], ended: false, playing: false, speed: 1, timer: null,
      token: 0, busy: false, loading: false, want: null, again: null, layers: ch.layers, ui: null as unknown as ReplayBar,
    }
    const ss = s
    s.ui = new ReplayBar(cell.host, {
      toggle: () => toggle(ss),
      speed: v => { ss.speed = v; if (ss.playing) schedule(ss); sync(ss) },
      seek: (pos, phase) => drag(ss, pos, phase),
      toStart: () => { seek(ss, ss.start); sync(ss) },
      exit: () => exit(ss),
      cancel: () => exit(ss),
      startAt: text => { const tt = M.parseShTime(text); if (tt == null) { badTime(); return } void begin(cell, tt) },
    })
    ch.layers = []
    sess = s
    paintButton(cell)
  } else {
    stopTimer(s); s.playing = false
    s.start = start; s.clock = start
  }
  const local = s.cell.chart.bars.concat(s.future)
  await place(s, start, local)
}

// ------------------------------------------------------------ 摆数据
/** 把这一格摆成「回放钟 = clock」的样子：local 里够用就直接切，不够（或切了周期）从 REST 取 */
async function place(s: Session, clock: number, local: Bar[] | null): Promise<void> {
  const tok = ++s.token, wasPlaying = s.playing
  stopTimer(s)
  // 在路上的补页按旧的那份算的，作废（它回来看到代号变了就不动）
  s.want = null; s.again = null; s.busy = false
  const now = Date.now()
  let cut = local ? M.splitAt(local, clock, s.iv, now) : null
  if (!cut) {
    s.loading = true; sync(s)
    cut = await fetchAround(s, clock)
    if (sess !== s || tok !== s.token) return
    s.loading = false
    if (!cut || !cut.hist.length) { toast('取不到这一段的 K 线', '已回到实时', 'wifiOff'); exit(s); return }
  }
  const ch = s.cell.chart
  if (ch.dead) { teardown(s); return }
  s.future = cut.future
  s.ended = false
  s.clock = clock
  ch.setData(cut.hist, env!.meta(s.cell))
  ch.rightBar = cut.hist.length - 1 + MARGIN
  ch.setAuto(true)
  ch.dirty = true
  if (cut.hist.length < M.HISTORY_BARS) void moreHistory(s)
  after(s)
  if (wasPlaying) play(s)
  // 取数那会儿进度线又被拖到了别处：落过去（还在这份里就直接切，不在就再取一份）
  if (s.again != null) { const w = s.again; s.again = null; if (w !== clock) { seek(s, w); sync(s) } }
}

/** 往左补历史：起点左边不到 300 根时（切周期后从当前时刻往回取的那页不够）补一页 */
async function moreHistory(s: Session): Promise<void> {
  const ch = s.cell.chart, first = ch.bars[0]; if (!first) return
  const tok = s.token
  const r = await fetchBack(s.symbol, s.iv, first.t, () => sess === s && tok === s.token)
  if (sess !== s || tok !== s.token || !r.length) return
  ch.prependData(r)
}

/** 取 clock 前后的两页：左边一整页历史，右边 FUTURE_BARS 根未来 */
async function fetchAround(s: Session, clock: number): Promise<{ hist: Bar[]; future: Bar[] } | null> {
  const plan = M.fetchPlan(clock, s.iv, Date.now()), tok = s.token
  const alive = () => sess === s && tok === s.token
  const [hist, future] = await Promise.all([
    fetchBack(s.symbol, s.iv, plan.histEnd, alive),
    fetchFwd(s.symbol, s.iv, plan.futureFrom, plan.futureLimit, alive),
  ])
  if (!hist.length) return null
  return { hist, future: future ?? [] }
}

/** 开盘严格早于 endTime 的一页（自定义分钟周期由原生周期并出来） */
async function fetchBack(symbol: string, iv: string, endTime: number, alive: () => boolean): Promise<Bar[]> {
  const r = isCustomIv(iv) ? await customKlines(symbol, iv, endTime, alive) : await klines(symbol, iv, endTime, M.PAGE, false, false, alive)
  if (!r.ok) return []
  if (!isCustomIv(iv)) void attachOI(symbol, iv, r.bars)
  return r.bars
}


/** 开盘不早于 from 的 limit 根「未来」，只留走完的整根；取不到返回 null */
async function fetchFwd(symbol: string, iv: string, from: number, limit: number, alive: () => boolean): Promise<Bar[] | null> {
  const custom = isCustomIv(iv), base = custom ? customBase(iv) : iv
  const per = custom ? Math.round(IV_MS[iv] / IV_MS[base]) : 1
  const n = Math.min(M.PAGE, Math.max(1, limit * per))
  try {
    // 按品种所属的交易所取（币安走 fapi，别家走它自己的模块；见 market/rest.ts klinesFrom）
    let bars = await klinesFrom(symbol, base, from, n, alive)
    if (custom) {
      const lastBase = bars[bars.length - 1]
      bars = aggregate(bars, IV_MS[iv])
      // 最后一格要是没并满（这页到头了）就丢掉，下一页从它的开盘重取
      const tail = bars[bars.length - 1]
      if (tail && lastBase && M.barClose(lastBase.t, base) < M.barClose(tail.t, iv)) bars.pop()
    }
    bars = M.completed(bars, iv, Date.now())
    if (!custom) void attachOI(symbol, iv, bars)
    return bars
  } catch { return null }
}

/** 没播的不多了：补下一页（拖进度线越过已取的部分时 force） */
async function refill(s: Session, force = false): Promise<void> {
  if (s.busy || s.ended) return
  const ch = s.cell.chart
  const lastOpen = s.future.length ? s.future[s.future.length - 1].t : ch.bars.length ? ch.bars[ch.bars.length - 1].t : null
  if (lastOpen == null) return
  const now = Date.now()
  if (!force && !M.needRefill(s.future.length, lastOpen, s.iv, now)) return
  if (M.refillFrom(lastOpen, s.iv) > M.liveEnd(now, s.iv) - 1) { s.ended = true; return }
  const tok = s.token
  s.busy = true
  const more = await fetchFwd(s.symbol, s.iv, M.refillFrom(lastOpen, s.iv), force ? M.PAGE : M.FUTURE_BARS, () => sess === s && tok === s.token)
  if (sess !== s || tok !== s.token) return
  s.busy = false
  if (more == null) { if (s.want != null) { s.want = null; sync(s) } return }   // 网络抖了：下一根播完再试
  const fresh = more.filter(b => b.t > lastOpen)
  if (!fresh.length) s.ended = true
  for (const b of fresh) s.future.push(b)
  if (s.want != null) { const w = s.want; s.want = null; seek(s, w) }
  sync(s)
}

// ------------------------------------------------------------ 播放
function play(s: Session): void {
  if (!s.future.length && s.ended) return
  s.playing = true
  schedule(s)
  sync(s)
}
function pause(s: Session): void { stopTimer(s); s.playing = false; sync(s) }
function toggle(s: Session): void {
  if (s.playing) { pause(s); return }
  // 播到最新了：从起点重播
  if (atEnd(s)) seek(s, s.start)
  play(s)
}
function atEnd(s: Session): boolean { return !s.future.length && s.ended && !s.busy }
function stopTimer(s: Session): void { if (s.timer) { clearTimeout(s.timer); s.timer = null } }
function schedule(s: Session): void {
  stopTimer(s)
  s.timer = setTimeout(() => tick(s), M.speedDelay(s.speed))
}
function tick(s: Session): void {
  s.timer = null
  if (sess !== s || !s.playing) return
  if (s.cell.chart.dead) { teardown(s); return }
  const b = s.future.shift()
  if (b) {
    s.cell.chart.updateBar(b)
    s.clock = M.barClose(b.t, s.iv)
    after(s)
    schedule(s)
    return
  }
  // 没有现成的：在补就等一下，补不出来就是到最新了
  if (s.busy) { s.timer = setTimeout(() => tick(s), 250); return }
  if (!s.ended) { void refill(s, true); s.timer = setTimeout(() => tick(s), 250); return }
  pause(s)
  toast('已经播到最新', '退出回放回到实时，或从起点重播', 'info')
}
/** 每动一次：回放条、头部报价、要不要补下一页 */
function after(s: Session): void {
  sync(s)
  paintReplayQuote()
  void refill(s)
}

/** 回放钟落到 clock：往回就把多出来的那几根收回「未来」，往前就从「未来」里搬，不重取 */
function seek(s: Session, clock: number): void {
  const ch = s.cell.chart, bars = ch.bars
  // 往回落到了手里最早那根之前（切过周期、拖到过最右之后，图上这份是围着别的时刻取的）：
  // 这份里一根都不该露出来，整份围着 clock 重取，不能把 K 线全收回「未来」留一张空图
  const first = bars[0] ?? s.future[0]
  if (s.loading || !first || first.t >= M.relocate(clock, s.iv)) { reposition(s, clock); return }
  const off = ch.rightBar - (bars.length - 1)
  const n = M.visibleCount(bars, clock, s.iv)
  s.want = null
  if (n < bars.length) {
    s.future = bars.splice(n).concat(s.future)
  } else {
    const k = M.visibleCount(s.future, clock, s.iv)
    for (const b of s.future.splice(0, k)) bars.push(b)
    // 拖过了已取的部分（未来搬空了还没到 clock）：记下要去的地方，取到再落过去
    const last = bars[bars.length - 1]
    if (!s.future.length && !s.ended && last && M.relocate(clock, s.iv) > M.barClose(last.t, s.iv)) { s.want = clock; void refill(s, true) }
  }
  ch.rightBar = bars.length - 1 + off
  ch.recalc(); ch.legendDirty = true
  const last = bars[bars.length - 1]
  s.clock = s.want != null && last ? M.barClose(last.t, s.iv) : clock
  if (bars.length < M.HISTORY_BARS) void moreHistory(s)
  paintReplayQuote()
}

/** 整份围着 clock 重摆：先清掉图上那份（都在 clock 之后，露出来就是「未来」），已经在取就只记下最后要去的地方 */
function reposition(s: Session, clock: number): void {
  s.clock = clock
  s.want = null
  if (s.loading) { s.again = clock; return }
  const ch = s.cell.chart
  ch.bars.splice(0)
  s.future = []
  s.ended = false
  ch.recalc(); ch.legendDirty = true
  paintReplayQuote()
  void place(s, clock, null)
}

/** 拖进度线：拖的时候暂停，松手按之前的状态继续 */
let dragWasPlaying = false
function drag(s: Session, pos: number, phase: 'start' | 'move' | 'end'): void {
  if (phase === 'start') { dragWasPlaying = s.playing; stopTimer(s); s.playing = false }
  if (phase !== 'end') { seek(s, M.clockAtPos(pos, s.start, M.liveEnd(Date.now(), s.iv), s.iv)); sync(s) }
  else { if (dragWasPlaying && !atEnd(s)) play(s); else sync(s); void refill(s) }
}

function sync(s: Session): void {
  if (sess !== s) return
  const stop = M.liveEnd(Date.now(), s.iv)
  const last = s.cell.chart.bars[s.cell.chart.bars.length - 1]
  const st: BarState = {
    playing: s.playing, speed: s.speed, pos: M.trackPos(s.clock, s.start, stop),
    time: last ? last.t : null, start: s.start, iv: s.iv, loading: s.loading || s.want != null,
    end: atEnd(s),
  }
  s.ui.play(st)
}

// ------------------------------------------------------------ 退出
function exit(s: Session, reload = true): void {
  if (sess !== s) return
  teardown(s)
  const cell = s.cell
  if (reload && env && !cell.chart.dead) env.reload(cell, () => {
    const ch = cell.chart
    ch.rightBar = ch.bars.length - 1 + MARGIN
    ch.setAuto(true)
    ch.dirty = true
  })
  env?.quote()
}
function teardown(s: Session): void {
  stopTimer(s)
  s.token++
  s.playing = false
  if (sess === s) sess = null
  if (!s.cell.chart.dead) s.cell.chart.layers = s.layers.concat(s.cell.chart.layers)
  s.ui.destroy()
  paintButton(s.cell)
}

// ------------------------------------------------------------ 键盘
function onKey(e: KeyboardEvent): void {
  const t = e.target as HTMLElement | null
  const typing = !!t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)
  if (typing || dialogs.length || e.metaKey || e.ctrlKey || e.altKey) return
  if (e.key === 'Escape' && pick) { cancelPick(); return }
  const s = sess
  if (!s || !env || s.cell !== env.active()) return
  if (e.key === ' ' || e.code === 'Space') { e.preventDefault(); toggle(s); return }
  if (e.key === 'Home') { e.preventDefault(); seek(s, s.start); sync(s) }
}

/** 单测与验收脚本用：当前回放的状态 */
export function replayState(): { idx: number; symbol: string; iv: string; start: number; clock: number; visible: number; future: number; playing: boolean; speed: number } | null {
  const s = sess
  return s ? { idx: s.cell.idx, symbol: s.symbol, iv: s.iv, start: s.start, clock: s.clock, visible: s.cell.chart.bars.length, future: s.future.length, playing: s.playing, speed: s.speed } : null
}
;(globalThis as unknown as { __replay?: typeof replayState }).__replay = replayState
