/* 手机网页版 · 行情页看朋友发来的线（照 iOS MainScreen.openShare / endSharePreview / keepShare / replyShare / sendReply、
 * Share/ShareCard.swift 的 ShareCard / ShareReplyBar、Alerts/AlertPrompt.swift 的 offerBatch / AlertPromptBar、
 * Drawing/DrawingController.preview）
 *
 * 头部价格行上那一格（36 高、淡强调色底、细描边，盖在价格与六格的位置上，行高不变、图一个点不动），同一时刻只摆一样：
 *   「顺便建提醒」那一句 > 正在看的那封信 > 最新一封没看过的信 > 「回给他」那一条（先后见 model/sharePreview.headerCard）。
 * - 没看过的信：缩略图 · 谁（回信写「谁 回了你」）· 「BTC · 3 条线  +2」· 「查看」；横划算看过。
 * - 查看 = 预览：切到那只品种、信上的周期（临时的，不写偏好；人自己在周期条上换了就算他的），图铺到信上那段视野；
 *   朋友的线画在我自己的图上（我的皮肤、指标、参数一概不动），我自己的线淡下去；点开即算已读。
 *   卡上：「正在看 谁 的线」· 保存到图上（留下过写「已保存」置灰）· 回给 谁 · 退出（退出时周期改回去）。
 * - 保存到图上：线复制一份进这只品种的画线（新 id，重试不重复），然后问一句「顺便建提醒」：
 *   发信人设了提醒的那几条优先问「也给你设上？」，没有就问整组「要在这 N 条线上提醒你吗？」；
 *   「只留线」/ 六秒没动 = 不加，「加入提醒」= 那几条一次挂上画线提醒（只响一次，上限 200 条）。
 * - 回给他：先把他的线留到我图上（同一条路，不重复复制），卡换成「回给 谁 · 发送 · 取消」，我接着画，
 *   点发送把这只品种上看得见的线连同视野原路发回去（带 replyTo，不过朋友名单），再补传缩略图。
 * 横屏画线台没有头部，这一格不摆（预览中的线照样画着）；手机网页版没有震动。
 */
import type { IntervalId } from '../../app/prefs'
import { INTERVALS } from '../../app/prefs'
import type { ChartHandle } from '../../chart'
import { tryDecodeDrawing, type Drawing } from '../../chart/draw/drawing'
import { authed } from '../../../account/client'
import { session, onSession } from '../../../account/session'
import { alertLinesOf } from '../../app/lineAlerts'
import { openableSymbol, shortSymbol, unseen, type ShareItem } from '../../model/inbox'
import { headerCard, cardTitle, cardSubtitle, offerBatch, isDismissSwipe, ALERT_LIMIT, type HeaderCard } from '../../model/sharePreview'
import { inboxItems, inboxItem, keepItem, markOpened, onInboxChange, pullInbox, thumbOf } from '../inboxStore'
import { buildOutbound, shareableLines, shareErrorText, thumbnail, uploadShot } from './share'
import { addLineAlerts } from './drawingBench'
import { toast } from '../../ui/toast'
import { el, esc } from '../../ui/dom'
import { icon } from '../../ui/icons'

export interface PreviewContext {
  chart: ChartHandle
  /** 头部（价格 + 六格那一行）：卡盖在它上面 */
  head: HTMLElement
  symbol(): string
  /** 图上眼下的周期（含预览的临时周期） */
  interval(): IntervalId
  /** 切到这只品种（记来路、切到行情页） */
  openSymbol(symbol: string): void
  /** 把页面状态对到图上（临时周期变了之后） */
  sync(): void
  /** 收掉盖在图上的面板、退出画线 / 回放 */
  clearStage(): void
}

export interface SharePreview {
  /** 临时周期（预览那封信的周期）；没有就 null，用偏好里的 */
  interval(): IntervalId | null
  /** 人自己在周期条上换了周期：临时的那个作废，退出时不再改回去 */
  userPickedInterval(): void
  /** 品种换了（syncChart 里调）：朋友的线只在那只品种上画 */
  symbolChanged(): void
  /** 头部那一格摆着：价格区的横滑不扫图 */
  cardVisible(): boolean
  previewing(): boolean
  open(item: ShareItem): void
  end(): void
  render(): void
}

const REPLY = '<svg width="15" height="15" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M10 4.6a1 1 0 0 1 1.7.7V9c5.6.3 9.3 3.6 10 9.8a.7.7 0 0 1-1.3.4C18.7 16.4 15.7 15 11.7 15v3.7a1 1 0 0 1-1.7.7L2.6 12.7a1 1 0 0 1 0-1.4L10 4.6z"/></svg>'
const CHART = '<svg width="15" height="15" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 4v16h16"/><path d="m7 15 4-5 3 3 5-6"/></svg>'
const PATIENCE = 6000

const validInterval = (v: string): IntervalId | null => ((INTERVALS as readonly string[]).includes(v) ? (v as IntervalId) : null)

export function createSharePreview(ctx: PreviewContext): SharePreview {
  const card = el('div', 'cp-card')
  card.hidden = true
  ctx.head.append(card)

  let previewing: ShareItem | null = null
  let previewSym = ''
  let guest: Drawing[] = []
  /** 临时周期：只活在这只品种上，人自己换了周期或换了品种就作废 */
  let temp: { symbol: string; interval: IntervalId } | null = null
  let replying: ShareItem | null = null
  let sending = false
  let offer: { symbol: string; sentence: string; batch: Drawing[] } | null = null
  let offerTimer = 0
  let waitOff: (() => void) | null = null
  let shown: HeaderCard = null
  let paintedKey = ''

  // ---- 朋友的线画在图上
  let applied: Drawing[] | null = null
  function applyGuest(): void {
    const on = !!previewing && ctx.symbol() === previewSym
    const want = on ? guest : []
    if (applied === want || (!applied?.length && !want.length && applied)) return // syncChart 每次都调，没变不重画
    applied = want
    ctx.chart.view.guestDrawings = want
    ctx.chart.view.ownDimmed = on
  }

  /** K 线到了（这只、这个周期）再把视野铺到信上那一段 */
  function showWindowWhenLoaded(symbol: string, interval: string, from: number, to: number): void {
    waitOff?.()
    const ready = (): boolean => {
      const s = ctx.chart.state?.input.series
      return ctx.chart.symbol === symbol && ctx.chart.interval === interval && !!s && !s.isEmpty && s.symbol === symbol && s.interval === interval
    }
    if (ready()) { ctx.chart.showWindow(from, to); waitOff = null; return }
    const off = ctx.chart.on('status', e => {
      if (e.loading) return
      requestAnimationFrame(() => { if (ready()) { stop(); ctx.chart.showWindow(from, to) } })
    })
    const timer = window.setTimeout(() => stop(), 12_000)
    const stop = (): void => { off(); clearTimeout(timer); if (waitOff === stop) waitOff = null }
    waitOff = stop
  }

  // ---- 预览
  function open(item: ShareItem): void {
    const sym = openableSymbol(item)
    if (!sym) { markOpened(item); toast('这只品种网页版还打不开，在 App 里看'); return }
    endPreview(false)
    dismissOffer()
    ctx.clearStage()
    previewing = item
    previewSym = sym
    guest = item.drawings.map(raw => tryDecodeDrawing(raw)).filter((d): d is Drawing => !!d)
    // 临时周期先记上再换品种：换品种那一下就直接取信上的周期，不先按偏好取一趟
    const iv = validInterval(item.interval)
    temp = iv ? { symbol: sym, interval: iv } : null
    ctx.openSymbol(sym) // 从「我的」点信进来时也要切到行情页
    ctx.sync()
    applyGuest()
    if (item.view.to > item.view.from) showWindowWhenLoaded(sym, ctx.interval(), item.view.from, item.view.to)
    markOpened(item)
    render()
  }

  /** 退出预览；restore：临时周期改回去（「退出」），留下 / 回信时就停在信上的周期 */
  function endPreview(restore: boolean): void {
    if (!previewing) return
    previewing = null; previewSym = ''; guest = []
    waitOff?.()
    applyGuest()
    if (restore && temp) { temp = null; ctx.sync() }
    render()
  }

  // ---- 保存到图上 → 顺便建提醒
  function keep(item: ShareItem): void {
    const r = keepItem(item)
    if (!r.ok) { toast(r.reason); render(); return }
    const sym = openableSymbol(item) ?? previewSym
    endPreview(false)
    const o = offerBatch(r.lines, d => alertLinesOf(d) != null, r.preferred, item.from)
    if (o && sym) {
      offer = { symbol: sym, sentence: o.sentence, batch: o.batch }
      clearTimeout(offerTimer)
      offerTimer = window.setTimeout(dismissOffer, PATIENCE)
    }
    render()
  }
  function dismissOffer(): void {
    clearTimeout(offerTimer); offerTimer = 0
    if (!offer) return
    offer = null
    render()
  }
  function acceptOffer(): void {
    const o = offer
    dismissOffer()
    if (!o) return
    const r = addLineAlerts(o.symbol, o.batch)
    if (r.full) toast(`提醒最多 ${ALERT_LIMIT} 条`)
  }

  // ---- 回给他
  function reply(item: ShareItem): void {
    const kept = !!(inboxItem(item.id) ?? item).keptAt
    if (!kept) {
      const r = keepItem(item)
      if (!r.ok) { toast(r.reason); return }
    }
    endPreview(false)
    replying = inboxItem(item.id) ?? item
    render()
  }
  async function sendReply(): Promise<void> {
    const item = replying
    if (!item || sending) return
    const sc = { chart: ctx.chart, symbol: ctx.symbol, interval: ctx.interval }
    if (!shareableLines(ctx.chart, ctx.symbol()).length) { toast('先在图上画点什么'); return }
    const draft = buildOutbound(sc)
    if (!draft) { toast('图还没画出来'); return }
    const shot = thumbnail(ctx.chart)
    const owner = session.userId
    sending = true; render()
    try {
      const r = await authed<{ id: string }>('POST', '/v1/shares', { to: item.from, ...draft, replyTo: item.id })
      if (session.userId !== owner) return
      if (replying?.id === item.id) replying = null
      toast(`已回给 ${item.from}`)
      pullInbox()
      if (shot && r?.id) void uploadShot(r.id, shot).catch(() => { /* 缩略图传不上不挡 */ })
    } catch (e) {
      toast(shareErrorText(e))
    } finally {
      sending = false
      render()
    }
  }

  // ---- 那一格
  function current(): { mode: HeaderCard; item: ShareItem | null; extra: number } {
    const list = unseen(inboxItems())
    const mode = headerCard({ prompt: !!offer, previewing: !!previewing, replying: !!replying, unseen: list.length })
    const item = mode === 'preview' ? previewing : mode === 'unseen' ? list[0] : mode === 'reply' ? replying : null
    return { mode, item, extra: Math.max(0, list.length - 1) }
  }
  function render(): void {
    const { mode, item, extra } = current()
    shown = mode
    ctx.head.classList.toggle('carding', mode != null)
    card.hidden = mode == null
    card.dataset.mode = mode ?? ''
    const fresh = item ? inboxItem(item.id) ?? item : null
    const key = JSON.stringify([mode, fresh?.id, fresh?.keptAt ? 1 : 0, extra, sending, offer?.sentence])
    if (key === paintedKey) return
    paintedKey = key
    if (mode === 'prompt' && offer) {
      card.innerHTML = `<span class="cp-card-ic">${icon('bell', 15)}</span>
        <span class="cp-card-say">${esc(offer.sentence)}</span>
        <button type="button" class="cp-card-btn quiet" data-act="only">只留线</button>
        <button type="button" class="cp-card-pill" data-act="accept">加入提醒</button>`
      return
    }
    if (mode === 'reply' && fresh) {
      card.innerHTML = `<span class="cp-card-ic">${REPLY}</span>
        <span class="cp-card-text"><b>${esc('回给 ' + fresh.from)}</b></span>
        ${sending ? '<span class="cp-card-spin" aria-label="正在发送"></span>' : '<button type="button" class="cp-card-btn" data-act="send">发送</button>'}
        <button type="button" class="cp-card-btn quiet" data-act="cancel"${sending ? ' disabled' : ''}>取消</button>`
      return
    }
    if ((mode === 'preview' || mode === 'unseen') && fresh) {
      const prev = mode === 'preview'
      const kept = !!fresh.keptAt
      card.innerHTML = `<span class="cp-card-thumb" data-thumb="${esc(fresh.id)}">${CHART}</span>
        <span class="cp-card-text"><b>${esc(cardTitle(fresh.from, prev, !!fresh.replyTo))}</b>${prev ? '' : `<small class="num">${esc(cardSubtitle(shortSymbol(fresh), fresh.drawings.length, extra))}</small>`}</span>
        ${prev
          ? `<button type="button" class="cp-card-btn" data-act="keep"${kept ? ' disabled' : ''}>${kept ? '已保存' : '保存到图上'}</button>
             <button type="button" class="cp-card-btn" data-act="reply">${esc('回给 ' + fresh.from)}</button>
             <button type="button" class="cp-card-btn quiet" data-act="exit">退出</button>`
          : '<button type="button" class="cp-card-btn" data-act="open">查看</button>'}`
      const id = fresh.id
      void thumbOf(id).then(url => {
        const box = card.querySelector<HTMLElement>(`[data-thumb="${CSS.escape(id)}"]`)
        if (url && box) box.innerHTML = `<img src="${esc(url)}" alt="">`
      })
      return
    }
    card.innerHTML = ''
  }

  card.addEventListener('click', e => {
    const b = (e.target as Element).closest<HTMLButtonElement>('[data-act]')
    if (!b || b.disabled) return
    const { item } = current()
    switch (b.dataset.act) {
      case 'only': dismissOffer(); break
      case 'accept': acceptOffer(); break
      case 'open': if (item) open(item); break
      case 'keep': if (previewing) keep(previewing); break
      case 'reply': if (previewing) reply(previewing); break
      case 'exit': endPreview(true); break
      case 'send': void sendReply(); break
      case 'cancel': replying = null; render(); break
    }
  })
  // 没看过的那封横划一下算看过（触摸走 touch，鼠标走 pointer）
  const swiped = (dx: number, dy: number): void => {
    if (shown !== 'unseen' || !isDismissSwipe(dx, dy)) return
    const { item } = current()
    if (item) markOpened(item)
  }
  let tx = 0, ty = 0, px = 0, py = 0, tracking = false
  card.addEventListener('touchstart', e => { const t = e.touches[0]; tx = t.clientX; ty = t.clientY }, { passive: true })
  card.addEventListener('touchend', e => { const t = e.changedTouches[0]; swiped(t.clientX - tx, t.clientY - ty) }, { passive: true })
  card.addEventListener('pointerdown', e => { if (e.pointerType !== 'mouse') return; px = e.clientX; py = e.clientY; tracking = true })
  card.addEventListener('pointerup', e => { if (!tracking) return; tracking = false; swiped(e.clientX - px, e.clientY - py) })

  onInboxChange(() => render())
  onSession(() => {
    if (!session.userId) { replying = null; endPreview(true); dismissOffer() }
    render()
  })
  render()

  return {
    interval: () => (temp && temp.symbol === ctx.symbol() ? temp.interval : null),
    userPickedInterval(): void { temp = null },
    symbolChanged(): void {
      if (temp && temp.symbol !== ctx.symbol()) temp = null
      applyGuest()
    },
    cardVisible: () => shown != null,
    previewing: () => !!previewing,
    open,
    end: () => endPreview(true),
    render,
  }
}

// ───────── 别处（「我的 › 朋友」点一封信）要在行情页上看：行情页挂上之后登记进来
let target: SharePreview | null = null
export function wireSharePreview(p: SharePreview): void { target = p }
/** 在行情页上预览这封信；行情页还没挂上返回 false */
export function previewShare(item: ShareItem): boolean {
  if (!target) return false
  target.open(item)
  return true
}
