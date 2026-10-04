/* 手机网页版 · 记一笔（照 iOS KanpanReview/ReviewCaptureCard.swift、PC 版 notes/dialog.ts）
 *
 * 顶栏「记一笔」：把眼前这段图（视野里收盘了的那几根）取成一段区间，写方向 / 目标 / 失效 / 一句话 / 来源，
 * 「记下」建一条观点记录，并附上和「分享图片」同一张成片。
 * 先落本地队列（hkline-m-notes-v1，截图另存 hkline-m-notes-shots-v1），再上传；
 * 没登录、断网时留在队列里，登录、联网、打开行情页时各补传一次。幂等键就是记录编号，重发不会记成两条。
 * 服务端明确拒收（400 / 409 / 422）的那条不再重试，直接丢掉。
 * 每一笔记着记下时登录的账号（owner），只传给那个账号、只列在那个账号的复盘本里；没登录时记的
 * 由第一个登录上的账号认领。传的途中换了账号就停下，换上来的账号接着再跑一趟（只传它自己的）。
 *
 * 没记完的那一笔（照 iOS ReviewStore.saveDraft）：卡上每动一下就把写的话、方向、手改过的价存进
 * hkline-m-note-draft-v1，收起卡不丢；同品种同周期再打开记一笔就接着写（unfinishedNote）。
 * 复盘本右上「+」与「继续未完成的记录」走 requestNote → resumeNote：有草稿先切回它的品种和周期，
 * 等那张图的 K 线到了再开卡；没有就在眼下这张图上新记。规则见 model/noteDraft.ts。
 */
import type { ChartHandle } from '../../chart'
import { INTERVAL_SHORT } from '../../chart/series'
import type { IntervalId } from '../../app/prefs'
import { openSheet, type Sheet } from '../../ui/sheet'
import { toast } from '../../ui/toast'
import { el, esc } from '../../ui/dom'
import { S } from '../../../market'
import { fmtPrice, grouped } from '../../model/rowText'
import { readStored } from '../../../account/client'
import { onSession, session } from '../../../account/session'
import { reviewApi, reviewToken, ReviewError, errorText, uuid } from '../../../review/api'
import {
  captureRange, buildDraft, checkDraft, sideLevels,
  DIRECTION_LABEL, CONFIRMATION_LABEL, ORIGIN_LABEL,
  type Capture, type Direction, type Confirmation, type Origin, type NoteDraft, type BarLike,
} from '../../../notes/draft'
import { chartCanvas, jpegBase64 } from './snapshot'
import { monthDayTime } from './logic'
import { NOTE_DRAFT_KEY, parseUnfinished, reusableFor, nextStored, type UnfinishedNote } from '../../model/noteDraft'

export const NOTES_KEY = 'hkline-m-notes-v1'
export const NOTE_SHOTS_KEY = 'hkline-m-notes-shots-v1'

// ───────────────────────────── 本地队列

interface Queued {
  draft: NoteDraft; queued: number
  /** 记下时登录的账号编号；没登录时记的没有这一项，谁先登录就传给谁 */
  owner?: string
}

function readJSON<T>(key: string, fallback: T): T {
  try { const raw = localStorage.getItem(key); return raw ? JSON.parse(raw) as T : fallback } catch { return fallback }
}
function writeJSON(key: string, v: unknown): void {
  try { localStorage.setItem(key, JSON.stringify(v)) } catch { /* 存满了：截图先丢，记录本身还在队列里 */ }
}
const queue = (): Queued[] => readJSON<Queued[]>(NOTES_KEY, [])
/** 现在登录的账号编号（调试令牌没有账号编号时为 null） */
const currentUid = (): string | null => readStored()?.userId ?? session.userId ?? null
const mine = (q: Queued, uid: string | null): boolean => q.owner == null || q.owner === uid
/** 队列里归现在这个账号的那几条（别的账号记的、还没传上的不算在这里，复盘本也不列） */
export const pendingNotes = (): Queued[] => { const uid = currentUid(); return queue().filter(q => mine(q, uid)) }
const shots = (): Record<string, string> => readJSON<Record<string, string>>(NOTE_SHOTS_KEY, {})

function enqueue(draft: NoteDraft, shot: string | null): void {
  const owner = currentUid() ?? undefined
  writeJSON(NOTES_KEY, [...queue().filter(q => q.draft.id !== draft.id), { draft, queued: Date.now(), owner }])
  if (shot) {
    const all = shots(); all[draft.id] = shot
    writeJSON(NOTE_SHOTS_KEY, all)
    // 写不进去（配额满）就退一步只存记录
    if (!(draft.id in shots())) { delete all[draft.id]; writeJSON(NOTE_SHOTS_KEY, all) }
  }
}
function dequeue(id: string): void {
  writeJSON(NOTES_KEY, queue().filter(q => q.draft.id !== id))
  const all = shots()
  if (id in all) { delete all[id]; writeJSON(NOTE_SHOTS_KEY, all) }
}

const canUpload = (): boolean => !!readStored() || !!reviewToken()
/** 服务端判定这条本身不合法：重发也没用 */
const rejected = (e: unknown): boolean => e instanceof ReviewError && [400, 409, 422].includes(e.status)

/** 被服务端拒收而丢掉的记录：编号 → 给人看的一句 */
const refused = new Map<string, string>()

let flushing: Promise<number> | null = null
/** 跑着的这一轮期间又被叫了（换了账号）：跑完再来一轮 */
let again = false
/** 把队列里的记录逐条补传；返回传上去几条。并发调用共用一轮 */
export function flushNotes(): Promise<number> {
  if (flushing) { again = true; return flushing }
  flushing = (async () => {
    let sent = 0
    do { again = false; sent += await flushRound() } while (again)
    return sent
  })().finally(() => { flushing = null })
  return flushing
}

async function flushRound(): Promise<number> {
  let sent = 0
  if (!canUpload() || !navigator.onLine) return 0
  const uid = currentUid()
  // 每条之前重读队列：这一轮还在传时新记下的那条（记一笔页 await 的正是这一轮）也跟着传，
  // 不会因为不在开头那份快照里而被报成「稍后自动上传」、一直留到下次登录 / 联网 / 回行情页
  const tried = new Set<string>()
  const next = (): Queued | undefined => queue().find(x => !tried.has(x.draft.id) && mine(x, uid))
  for (let q = next(); q; q = next()) {
    // 途中换了账号：后面的请求会带上新账号的令牌，停下交给下一轮
    if (currentUid() !== uid) break
    tried.add(q.draft.id)
    try {
      await reviewApi.createRecord(q.draft)
    } catch (e) {
      if (rejected(e)) { refused.set(q.draft.id, errorText(e)); dequeue(q.draft.id); continue }
      break // 没登录 / 断网 / 服务器忙：整轮停下，下次再来
    }
    const shot = shots()[q.draft.id]
    if (shot && currentUid() === uid) { try { await reviewApi.putShot(q.draft.id, shot) } catch { /* 图传不上不挡记录 */ } }
    dequeue(q.draft.id)
    sent++
  }
  return sent
}

let wired = false
/** 登录、联网时各补传一次（行情页打开时自己再调一次 flushNotes） */
export function wireNoteUploads(): void {
  if (wired) return
  wired = true
  onSession(() => { void flushNotes() })
  addEventListener('online', () => { void flushNotes() })
}

// ───────────────────────────── 没记完的那一笔

/** 本机存着的那份没记完的（没有 / 坏了就是 null） */
export function unfinishedNote(): UnfinishedNote | null {
  return parseUnfinished(readJSON<unknown>(NOTE_DRAFT_KEY, null))
}
function storeUnfinished(v: UnfinishedNote): void {
  const saved = unfinishedNote()
  switch (nextStored(saved, v)) {
    case 'save': writeJSON(NOTE_DRAFT_KEY, v); break
    case 'clear': try { localStorage.removeItem(NOTE_DRAFT_KEY) } catch { /* 无 */ } break
    case 'keep': break
  }
}
function clearUnfinished(symbol: string, interval: string): void {
  if (reusableFor(unfinishedNote(), symbol, interval)) try { localStorage.removeItem(NOTE_DRAFT_KEY) } catch { /* 无 */ }
}

export interface ResumeContext extends NoteContext {
  /** 把行情页切到这只品种、这个周期（草稿不是眼下这张图上的时候） */
  switchTo(symbol: string, interval: IntervalId): void
}

/** 图上已经是这只、这个周期，且 K 线到了 */
const loadedFor = (chart: ChartHandle, symbol: string, interval: string): boolean => {
  const s = chart.state?.input.series
  return chart.symbol === symbol && chart.interval === interval && !!s && !s.isEmpty && s.symbol === symbol && s.interval === interval
}

let waiting: (() => void) | null = null
/** K 线到了再做（切品种、切周期之后要等一页数据）；最多等 12 秒 */
function whenLoaded(chart: ChartHandle, symbol: string, interval: string, run: () => void): void {
  waiting?.()
  if (loadedFor(chart, symbol, interval)) { waiting = null; run(); return }
  let done = false
  const finish = (ok: boolean): void => {
    if (done) return
    done = true; off(); clearTimeout(timer); waiting = null
    if (ok) run(); else toast('这段行情还没取到，稍后再记')
  }
  const off = chart.on('status', e => {
    if (e.loading) return
    // status 先于状态落到 chart.state：下一帧再量
    requestAnimationFrame(() => { if (loadedFor(chart, symbol, interval)) finish(true) })
  })
  const timer = window.setTimeout(() => finish(loadedFor(chart, symbol, interval)), 12_000)
  waiting = () => { done = true; off(); clearTimeout(timer) }
}

/** 接着写没记完的那一笔；没有就在眼下这张图上新记（复盘本右上「+」） */
export function resumeNote(ctx: ResumeContext): void {
  const d = unfinishedNote()
  let sym = ctx.symbol(), iv: string = ctx.interval()
  if (d && !reusableFor(d, sym, iv)) {
    ctx.switchTo(d.symbol, d.interval as IntervalId)
    sym = d.symbol; iv = d.interval
  }
  whenLoaded(ctx.chart, sym, iv, () => { openNote(ctx) })
}

let noteHandler: (() => void) | null = null
let noteWanted = false
/** 行情页挂上「要记一笔」的处理（resumeNote）；挂上之前就有人要了，立刻补做 */
export function wireNoteRequests(fn: () => void): void {
  noteHandler = fn
  if (noteWanted) { noteWanted = false; fn() }
}
/** 别的页要记一笔（复盘本「+」）：先 go('chart') 再调这个 */
export function requestNote(): void {
  if (noteHandler) noteHandler(); else noteWanted = true
}

// ───────────────────────────── 取景

export interface NoteContext {
  chart: ChartHandle
  symbol(): string
  interval(): IntervalId
}

/** 视野里的那段（按时刻换成下标）取成一段区间 */
export function captureVisible(chart: ChartHandle, now = Date.now()): Capture | null {
  const s = chart.state
  if (!s || s.input.series.isEmpty) return null
  const b = s.input.series
  const bars: BarLike[] = new Array(b.count)
  for (let i = 0; i < b.count; i++) bars[i] = { t: b.time(i), h: b.high[i], l: b.low[i], c: b.close[i] }
  const v = s.viewport.view
  const from = b.firstIndexAtOrAfter(v.from)
  const to = Math.min(b.count - 1, b.index(v.to))
  return captureRange(b.symbol, b.interval, bars, from, to, now)
}

/** 价格输入：只收数字与一个小数点 */
function cleanPrice(raw: string): string {
  const s = raw.replace(/[^\d.]/g, '')
  const i = s.indexOf('.')
  return i < 0 ? s : s.slice(0, i + 1) + s.slice(i + 1).replace(/\./g, '')
}

const seg = <T extends string>(labels: Record<T, string>, value: T, act: string): string =>
  `<div class="cp-seg" role="radiogroup">${(Object.keys(labels) as T[]).map(k =>
    `<button type="button" class="cp-seg-opt${k === value ? ' on' : ''}" role="radio" aria-checked="${k === value}" data-act="${act}" data-v="${k}">${esc(labels[k])}</button>`).join('')}</div>`

// ───────────────────────────── 取景卡

export function openNote(ctx: NoteContext): Sheet | null {
  const now = Date.now()
  const cap = captureVisible(ctx.chart, now)
  if (!cap) {
    toast(ctx.chart.state?.input.series.isEmpty === false ? '这个周期记不了，换个周期再记' : '图还没画出来')
    return null
  }
  // 成片在打开那一刻就取：记下的是「当时看到的样子」
  const canvas = chartCanvas(ctx.chart)
  const shot = canvas ? jpegBase64(canvas, 900, 400 * 1024) : null
  const sym = ctx.symbol(), iv = ctx.interval()
  const dec = S.symbols.get(sym)?.dec ?? 2
  const px = (v: number): string => grouped(fmtPrice(v, dec))
  const plain = (v: number): string => fmtPrice(v, dec)

  // 同品种同周期有没记完的：写的话、方向、手改过的价都接着用，区间换成眼下这一屏（iOS beginCapture）
  const saved = unfinishedNote()
  const resume = reusableFor(saved, sym, iv) ? saved! : null
  let direction: Direction = resume?.direction ?? 'observe'
  let confirmation: Confirmation = resume?.confirmation ?? 'bar_close'
  let origin: Origin = resume?.origin ?? 'chart_first'
  let text = resume?.text ?? ''
  let targetEdited = !!resume?.targetEdited && !!resume.target
  let invalidationEdited = !!resume?.invalidationEdited && !!resume.invalidation
  let target = targetEdited ? resume!.target : ''
  let invalidation = invalidationEdited ? resume!.invalidation : ''
  let busy = false
  let saved_ = false
  const place = (): void => {
    const lv = sideLevels(direction, cap.reference, cap.high, cap.low)
    if (!targetEdited) target = plain(lv.target)
    if (!invalidationEdited) invalidation = plain(lv.invalidation)
  }
  /** 卡上每动一下存一次（收起卡不丢）；记下之后清掉 */
  const persist = (): void => {
    if (saved_) return
    storeUnfinished({
      symbol: sym.toUpperCase(), interval: iv, direction, confirmation, origin, text,
      target: targetEdited ? target : '', invalidation: invalidationEdited ? invalidation : '',
      targetEdited, invalidationEdited, updated: Date.now(),
    })
  }

  const sheet = openSheet((body, sh) => {
    const host = el('div', 'cp-panel cp-note')
    body.append(host)
    const range = `${cap.range.bars} 根 · ${monthDayTime(cap.range.start)} – ${monthDayTime(cap.range.end)}`
    const render = (): void => {
      const observe = direction === 'observe'
      host.innerHTML = `
        <div class="cp-nrow"><span class="cp-nlab">区间</span><span class="cp-nval num">${esc(range)}</span></div>
        ${seg(DIRECTION_LABEL, direction, 'dir')}
        ${observe ? '' : `
          <div class="cp-nprices">
            <label class="cp-nfield"><span>目标</span><input class="cp-nin num" inputmode="decimal" autocomplete="off" data-f="target" value="${esc(target)}"></label>
            <label class="cp-nfield"><span>失效</span><input class="cp-nin num" inputmode="decimal" autocomplete="off" data-f="invalidation" value="${esc(invalidation)}"></label>
          </div>
          <div class="cp-nrow cp-nref"><span class="num">参考价 ${esc(px(cap.reference))}</span><button type="button" class="cp-textbtn" data-act="reset">按方向重置</button></div>
          ${seg(CONFIRMATION_LABEL, confirmation, 'conf')}`}
        <textarea class="cp-ntext" rows="2" maxlength="2000" placeholder="一句话（可选）" data-f="text">${esc(text)}</textarea>
        <div class="cp-nrow"><span class="cp-nlab">来源</span>${seg(ORIGIN_LABEL, origin, 'origin')}</div>
        <p class="cp-nerr" hidden></p>
        <div class="cp-nfoot"><button type="button" class="cp-primary" data-act="save">记下</button></div>`
    }
    place()
    render()
    const error = (msg: string | null): void => {
      const p = host.querySelector<HTMLElement>('.cp-nerr')!
      p.hidden = !msg; p.textContent = msg ?? ''
    }
    host.addEventListener('input', e => {
      const t = e.target as HTMLInputElement | HTMLTextAreaElement
      const f = t.dataset.f
      if (f === 'text') { text = t.value; persist(); return }
      if (f === 'target' || f === 'invalidation') {
        const v = cleanPrice(t.value)
        if (v !== t.value) t.value = v
        if (f === 'target') { target = v; targetEdited = true } else { invalidation = v; invalidationEdited = true }
        error(null)
        persist()
      }
    })
    host.addEventListener('click', e => {
      const b = (e.target as Element).closest<HTMLElement>('[data-act]')
      if (!b) return
      switch (b.dataset.act) {
        case 'dir': direction = b.dataset.v as Direction; place(); render(); break
        case 'conf': confirmation = b.dataset.v as Confirmation; render(); break
        case 'origin': origin = b.dataset.v as Origin; render(); break
        case 'reset': targetEdited = invalidationEdited = false; place(); render(); break
        case 'save': void submit(); return
        default: return
      }
      persist()
    })
    const submit = async (): Promise<void> => {
      if (busy) return
      const draft = buildDraft({
        id: uuid(), capture: cap, direction, confirmation,
        target: +target, invalidation: +invalidation, targetEdited, invalidationEdited,
        text, origin, created: Date.now(),
      })
      const bad = checkDraft(draft)
      if (bad) { error(bad); return }
      busy = true
      enqueue(draft, shot)
      saved_ = true
      clearUnfinished(sym, iv)
      sh.close()
      if (!canUpload()) { toast('已记下 · 登录后自动上传'); return }
      if (!navigator.onLine) { toast('已记下 · 联网后自动上传'); return }
      await flushNotes()
      const why = refused.get(draft.id)
      if (why) { refused.delete(draft.id); toast(`没记上 · ${why}`); return }
      toast(pendingNotes().some(q => q.draft.id === draft.id) ? '已记下 · 稍后自动上传' : '已记下')
    }
  }, {
    title: `记一笔 · ${INTERVAL_SHORT[iv] ?? iv}`, detent: 'auto', id: 'note', className: 'cp-sheet', noBack: true,
    action: { title: '收起', run: () => sheet.close() },
  })
  return sheet
}
