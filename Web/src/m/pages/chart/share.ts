/* 手机网页版 · 行情页「分享」（照 iOS Panels/ShareChooser.swift、Share/FriendPickerSheet.swift、Share/ShareClient.swift）
 *
 * 顶栏「分享」开一张二选一：
 *   图片 —— 成片（身份条 + 图 + 落款，和「记一笔」附的是同一张）交给系统分享；浏览器不支持分享文件就直接下载。
 *   画线 —— 「发给朋友」：朋友名单点一行就发，「新朋友」填用户名发；线落在朋友自己的图上（他的皮肤、指标不动）。
 *          没登录、这只上没线时那一格置灰并写明原因。发出去之后再补传一张 600 宽的缩略图（传不上不挡）。
 */
import { drawingBook } from '../../app/drawings'
import { go } from '../../app/shell'
import type { ChartHandle } from '../../chart'
import type { IntervalId } from '../../app/prefs'
import { encodeDrawing } from '../../chart/draw/drawing'
import { INTERVAL_SHORT } from '../../chart/series'
import { ApiError, authed, fresh, readStored } from '../../../account/client'
import { openSheet, type Sheet } from '../../ui/sheet'
import { toast } from '../../ui/toast'
import { el, esc } from '../../ui/dom'
import { USERNAME_RULE, normalUsername } from '../../model/formText'
import { icon } from '../../ui/icons'
import { shotCanvas, chartCanvas } from './snapshot'
import { alertedLineIds } from './drawingBench'
import { splitPair } from './header'

export interface ShareContext {
  chart: ChartHandle
  symbol(): string
  interval(): IntervalId
  /** 正在看朋友的线：没有「发线」那一格，顶栏「分享」直接走图片（照 MainScreen.headerShareAction） */
  previewing?(): boolean
}

/** 朋友的用户名：和登录 / 加朋友同一份规则（model/formText），交出去的是小写 */
export const friendName = normalUsername

/** 发信出错 → 给人看的一句（照 ShareClient.message） */
export function shareErrorText(e: unknown): string {
  if (e instanceof ApiError) {
    if (e.status === 404 && e.code === 'no_such_user') return '没有这个用户名'
    if (e.code === 'cannot_send_self') return '不能发给自己'
    if (e.code === 'invalid_username') return '请填写朋友的用户名'
    if (e.status === 429) return '发得有点快，稍后再试'
    if (e.status === 401) return '登录已过期，重新登录后再发'
  }
  return '暂时连不上'
}

/** 这只品种上能发的线：图上开着「显示画线」、线本身没藏 */
export function shareableLines(chart: ChartHandle, sym: string) {
  if (chart.state && chart.state.input.options.drawings === false) return []
  return drawingBook.items(sym).filter(d => !d.hidden)
}

const loggedIn = (): boolean => !!readStored()

/** 那一格为什么发不了；null 就是能发 */
function linesBlocked(ctx: ShareContext): string | null {
  if (!loggedIn()) return '登录后可发'
  return shareableLines(ctx.chart, ctx.symbol()).length ? null : '先画几条线'
}

// ───────────────────────────── 二选一

export function openShare(ctx: ShareContext): Sheet | null {
  if (ctx.previewing?.()) { shareImage(ctx); return null }
  const blocked = linesBlocked(ctx)
  const sheet = openSheet(body => {
    const host = el('div', 'cp-panel cp-share')
    host.innerHTML = `
      <button type="button" class="cp-stile" data-act="image">
        <span class="cp-stile-ic">${icon('share', 22)}</span>
        <span class="cp-stile-tx"><b>图片</b><small>发到微信等任何地方</small></span>
      </button>
      <button type="button" class="cp-stile" data-act="lines"${blocked ? ' aria-disabled="true"' : ''}>
        <span class="cp-stile-ic">${icon('draw', 22)}</span>
        <span class="cp-stile-tx"><b>画线</b><small>${esc(blocked ?? '朋友在自己的图上看到你的线')}</small></span>
      </button>`
    body.append(host)
    host.addEventListener('click', e => {
      const b = (e.target as Element).closest<HTMLElement>('[data-act]')
      if (!b) return
      if (b.dataset.act === 'image') { sheet.close(); shareImage(ctx); return }
      if (blocked === '登录后可发') { sheet.close(); toast('登录后才能发给朋友', { title: '去登录', run: () => go('me') }); return }
      if (blocked) { toast('先在图上画点什么'); return }
      sheet.close()
      openFriendPicker(ctx)
    })
  }, { title: '分享', detent: 'fit', dim: 'large', id: 'share', className: 'cp-sheet' })
  return sheet
}

// ───────────────────────────── 图片

function dataUrlBlob(url: string): Blob {
  const [head, b64] = url.split(',')
  const type = /data:([^;]+)/.exec(head)?.[1] ?? 'image/png'
  const bin = atob(b64)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return new Blob([out], { type })
}

/** 同步把成片做成文件（iOS Safari 的分享面板要在这次点击里调起，不能先等异步编码） */
export function shareImage(ctx: ShareContext): void {
  const sym = ctx.symbol(), iv = ctx.interval()
  const c = shotCanvas(ctx.chart, sym, iv)
  if (!c) { toast('图还没画出来'); return }
  const { base } = splitPair(sym)
  const name = `${base}-${INTERVAL_SHORT[iv] ?? iv}.png`
  const file = new File([dataUrlBlob(c.toDataURL('image/png'))], name, { type: 'image/png' })
  const nav = navigator as Navigator & { canShare?(d: ShareData): boolean }
  if (nav.share && nav.canShare?.({ files: [file] })) {
    nav.share({ files: [file] }).catch(() => { /* 用户取消 */ })
    return
  }
  const a = document.createElement('a')
  a.href = URL.createObjectURL(file); a.download = name
  document.body.append(a); a.click(); a.remove()
  setTimeout(() => URL.revokeObjectURL(a.href), 4000)
  toast('图片已保存')
}

// ───────────────────────────── 画线：发给朋友

export interface Outbound {
  symbol: string; interval: string; view: { from: number; to: number }
  drawings: ReturnType<typeof encodeDrawing>[]; alerted: string[]
}

/** 缩略图：600 宽 JPEG，≤ 300 KB（服务端上限） */
export function thumbnail(chart: ChartHandle): Blob | null {
  const c = chartCanvas(chart, 1)
  if (!c) return null
  const out = document.createElement('canvas')
  out.width = 600; out.height = Math.round(600 * c.height / c.width)
  out.getContext('2d')!.drawImage(c, 0, 0, out.width, out.height)
  for (const q of [0.8, 0.6, 0.45]) {
    const b = dataUrlBlob(out.toDataURL('image/jpeg', q))
    if (b.size <= 300 * 1024) return b
  }
  return null
}

/** 发出去之后补传缩略图（传不上不挡） */
export async function uploadShot(id: string, shot: Blob): Promise<void> {
  const v = await fresh()
  await fetch(`/v1/shares/${encodeURIComponent(id)}/shot`, {
    method: 'PUT', body: shot, cache: 'no-store',
    headers: { 'Content-Type': 'image/jpeg', Authorization: 'Bearer ' + v.accessToken },
  })
}

/** 发信那一份（回信时外面再补 replyTo） */
export function buildOutbound(ctx: ShareContext): Outbound | null {
  const sym = ctx.symbol()
  const lines = shareableLines(ctx.chart, sym).slice(0, 200)
  const view = ctx.chart.state?.viewport.view
  if (!lines.length || !view) return null
  const alerted = alertedLineIds(sym)
  return {
    symbol: sym, interval: ctx.interval(),
    view: { from: Math.max(0, Math.round(view.from)), to: Math.round(view.to) },
    drawings: lines.map(encodeDrawing),
    alerted: lines.filter(d => alerted.has(d.id)).map(d => d.id),
  }
}

export function openFriendPicker(ctx: ShareContext): Sheet | null {
  const draft = buildOutbound(ctx)
  if (!draft) { toast('先在图上画点什么'); return null }
  const shot = thumbnail(ctx.chart)
  let friends: string[] | null = null
  let adding = false, sending = false
  let error: string | null = null
  let name = ''
  const sheet = openSheet((body, sh) => {
    const host = el('div', 'cp-panel cp-friends')
    body.append(host)
    const render = (): void => {
      const list = friends ?? []
      const showList = !adding && list.length > 0
      const ok = friendName(name) != null
      host.innerHTML = `
        ${showList ? `<div class="cp-group">${list.map(f =>
          `<button type="button" class="cp-row cp-tap" data-send="${esc(f)}"><span class="cp-rn">${esc(f)}</span><span class="cp-plane">${PLANE}</span></button>`).join('')}
          <button type="button" class="cp-row cp-tap" data-act="new"><span class="cp-rn">新朋友</span></button></div>`
        : friends == null && !adding ? '<div class="cp-empty">正在取朋友名单…</div>' : `
          <div class="cp-fname">
            <input class="cp-nin" type="text" inputmode="email" autocapitalize="none" autocorrect="off" spellcheck="false" autocomplete="off"
              placeholder="朋友的用户名" enterkeyhint="send" value="${esc(name)}">
            <button type="button" class="cp-textbtn" data-act="send-new"${ok ? '' : ' disabled'}>发送</button>
          </div>
          ${name && !ok ? `<p class="cp-meta">${USERNAME_RULE}</p>` : ''}`}
        ${error ? `<p class="cp-nerr">${esc(error)}</p>` : ''}
        ${sending ? '<div class="cp-empty">正在发送…</div>' : ''}`
      host.classList.toggle('busy', sending)
    }
    render()
    authed<{ username: string }[]>('GET', '/v1/friends')
      .then(r => { friends = (r ?? []).map(f => f.username) })
      .catch(() => { friends = [] })
      .finally(() => { if (!sh.closed) render() })
    const send = async (to: string): Promise<void> => {
      if (sending || !to) return
      sending = true; error = null; render()
      try {
        const r = await authed<{ id: string }>('POST', '/v1/shares', { to, ...draft })
        if (sh.closed) return
        sh.close()
        toast(`已发给 ${to}`)
        if (shot && r?.id) void uploadShot(r.id, shot).catch(() => { /* 缩略图传不上不挡 */ })
      } catch (e) {
        error = shareErrorText(e)
      } finally {
        sending = false
        if (!sh.closed) render()
      }
    }
    host.addEventListener('input', e => {
      const t = e.target as HTMLInputElement
      if (!t.classList.contains('cp-nin')) return
      name = t.value
      const ok = friendName(name) != null
      const btn = host.querySelector<HTMLButtonElement>('[data-act=send-new]')
      if (btn) btn.disabled = !ok
      const rule = host.querySelector('.cp-fname + .cp-meta')
      if (name && !ok && !rule) host.querySelector('.cp-fname')!.insertAdjacentHTML('afterend', `<p class="cp-meta">${USERNAME_RULE}</p>`)
      else if ((!name || ok) && rule) rule.remove()
    })
    host.addEventListener('keydown', e => {
      if (e.key === 'Enter' && (e.target as Element).classList.contains('cp-nin')) {
        const n = friendName(name); if (n) void send(n)
      }
    })
    host.addEventListener('click', e => {
      const b = (e.target as Element).closest<HTMLElement>('[data-send],[data-act]')
      if (!b || sending) return
      if (b.dataset.send) { void send(b.dataset.send); return }
      if (b.dataset.act === 'new') { adding = true; error = null; render(); host.querySelector<HTMLInputElement>('.cp-nin')?.focus(); return }
      if (b.dataset.act === 'send-new') { const n = friendName(name); if (n) void send(n) }
    })
  }, { title: '发给朋友', detent: 'medium', id: 'share-friends', className: 'cp-sheet cp-list' })
  return sheet
}

/** SF paperplane.fill 的描法 */
const PLANE = `<svg width="17" height="17" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M2.6 10.7 20.4 3.2c.9-.4 1.8.5 1.4 1.4l-7.5 17.8c-.4 1-1.8.9-2.1-.1l-1.9-6.4a1 1 0 0 0-.6-.6L3.3 13.4c-1-.3-1.1-1.7-.1-2.1Z"/></svg>`
