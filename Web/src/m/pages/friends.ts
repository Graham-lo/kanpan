/* 手机网页版 · 「我的 › 朋友与收件箱」（照 iOS Share/FriendsPage.swift、FriendNameField.swift、ShareCard.ShareThumbnail）
 *
 * 一页平铺在 --app 上（不套卡）：
 *   没登录：人形记号 +「登录后可收发画线」+ 强调色胶囊「登录」（朋友、收件箱都挂在账号上，空着的
 *     「还没有朋友」「还没有收到画线」只会让人以为是真的没有）。
 *   登录了：朋友一行一个（左划删除）；一个都没有又没在加时「还没有朋友」；
 *     「加朋友」行（行尾强调色 +）→ 展开成输入框 +「加」（规则同注册用户名，不合格时「加」置灰、框下一行规则字）；
 *     分组「收到的线」：缩略图 +「谁 · 哪只 · 几条线」+ 时间 / 已保存；空时「还没有收到画线」；
 *     拉不下来时底下一行「{原因} · 重试」。
 * 点一封信：照 iOS openShare，退回「我的」根、切到行情页把朋友的线临时画在自己的图上预览
 *   （chart/sharePreview：头部那一格「保存到图上 / 回给他 / 退出」）。
 *   网页版还打不开的品种（别家交易所等）才推一层「信」：大图（发信人截的那张）+ 谁 · 哪只 · 几条线
 *   + 周期与时间 +「保存到图上」（留下后在 App 里看）。点开即算已读（照 iOS openShare → inbox.opened）。
 */
import { esc } from '../ui/dom'
import { icon } from '../ui/icons'
import { toast } from '../ui/toast'
import { swipeRow, deleteAction, type SwipeHandle } from '../ui/swipeDelete'
import { loggedIn, onSession } from '../../account/session'
import { INTERVAL_DISPLAY, type Interval } from '../chart/series'
import { USERNAME_RULE, validUsername } from '../model/formText'
import { letterTime, letterTitle, openableSymbol, shortSymbol, type ShareItem } from '../model/inbox'
import {
  addFriend, friendErrorText, inboxFriends, inboxItems, inboxNotice, keepItem, markOpened, onInboxChange, pullInbox, removeFriend, thumbOf,
} from './inboxStore'
import type { MeHost, MeLayer } from './meHost'
import { previewShare } from './chart/sharePreview'

const PEOPLE = '<svg width="36" height="36" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M9 11.5a3.75 3.75 0 1 0 0-7.5 3.75 3.75 0 0 0 0 7.5zm7.5 0a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM9 13c-3.3 0-6.5 1.7-6.5 4.4V19a1 1 0 0 0 1 1h11a1 1 0 0 0 1-1v-1.6C15.5 14.7 12.3 13 9 13zm7.5.2c-.6 0-1.2.1-1.7.2 1.3 1 2.2 2.4 2.2 4V19c0 .4-.1.7-.2 1h3.7a1 1 0 0 0 1-1v-1.4c0-2.5-2.4-4.4-5-4.4z"/></svg>'
const TRAY = '<svg width="36" height="36" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M6.3 4h11.4a2 2 0 0 1 1.8 1.1l2.3 4.7c.1.3.2.6.2.9V18a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2v-7.3c0-.3.1-.6.2-.9l2.3-4.7A2 2 0 0 1 6.3 4zm-.1 2-2 4.2H8a1 1 0 0 1 1 .9 3 3 0 0 0 6 0 1 1 0 0 1 1-.9h3.8l-2-4.2H6.2z"/></svg>'
const CHART = '<svg width="17" height="17" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 4v16h16"/><path d="m7 15 4-5 3 3 5-6"/></svg>'

const empty = (svg: string, text: string, id = ''): string =>
  `<div class="fr-empty"${id ? ` data-id="${id}"` : ''}>${svg}<span>${esc(text)}</span></div>`

/** 缩略图：先摆占位，拉到了换成图（同一封信内存里有就直接用，不闪占位） */
function fillThumbs(root: HTMLElement): void {
  root.querySelectorAll<HTMLElement>('[data-thumb]').forEach(box => {
    const id = box.dataset.thumb!
    void thumbOf(id).then(url => {
      if (!url || !box.isConnected || box.dataset.thumb !== id) return
      box.innerHTML = `<img src="${url}" alt="">`
    })
  })
}

export function buildFriends(body: HTMLElement, layer: MeLayer, host: MeHost): void {
  body.classList.add('fr-page')
  let adding = false
  let name = ''
  let saving = false
  let error: string | null = null
  const swipes: SwipeHandle[] = []

  const paint = (): void => {
    swipes.splice(0).forEach(s => s.destroy())
    if (!loggedIn()) {
      body.innerHTML = `<div class="fr-signed-out">${empty(PEOPLE, '登录后可收发画线', 'signedOut')}
        <button type="button" class="fr-login" data-act="login">登录</button></div>`
      return
    }
    const friends = inboxFriends()
    const items = inboxItems()
    const notice = inboxNotice()
    body.innerHTML = `
      <div class="fr-friends">${friends.map(f => `<div class="fr-row" data-friend="${esc(f)}"><span class="fr-name">${esc(f)}</span></div>`).join('')}</div>
      ${!friends.length && !adding ? empty(PEOPLE, '还没有朋友') : ''}
      ${adding ? addFieldHTML() : `<button type="button" class="fr-row fr-add" data-act="add"><span class="fr-name">加朋友</span><span class="fr-plus">${icon('plus', 17)}</span></button>`}
      <div class="me-group fr-group">收到的线</div>
      ${items.map(it => `<button type="button" class="fr-item" data-item="${esc(it.id)}">
          <span class="fr-thumb" data-thumb="${esc(it.id)}">${CHART}</span>
          <span class="fr-item-text"><span class="fr-item-title">${esc(letterTitle(it))}</span>
          <span class="fr-item-meta num">${esc(letterTime(it.createdAt))}${it.keptAt ? '<span>已保存</span>' : ''}</span></span>
        </button>`).join('')}
      ${items.length ? '' : empty(TRAY, '还没有收到画线')}
      ${notice ? `<button type="button" class="fr-notice" data-act="retry">${esc(notice)} · 重试</button>` : ''}`
    body.querySelectorAll<HTMLElement>('[data-friend]').forEach(row => {
      const who = row.dataset.friend!
      swipes.push(swipeRow(row, { trailing: [deleteAction(() => { void removeFriend(who) })], brick: 'flush' }))
    })
    fillThumbs(body)
    if (adding) wireField()
  }

  const addFieldHTML = (): string => {
    const ok = validUsername(name)
    return `<div class="fr-field">
      <div class="fr-field-row"><input data-k="friend" type="text" value="${esc(name)}" placeholder="朋友的用户名" lang="en" inputmode="latin" enterkeyhint="done"
        autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false"${saving ? ' disabled' : ''}>
        <button type="button" class="fr-add-go" data-act="commit"${ok && !saving ? '' : ' disabled'}>加</button></div>
      ${name && !ok ? `<div class="fr-rule">${esc(USERNAME_RULE)}</div>` : ''}
      ${error ? `<div class="fr-err">${esc(error)}</div>` : ''}</div>`
  }

  /** 只重画输入那一块（整页重画会把键盘收掉） */
  const repaintField = (): void => {
    const box = body.querySelector<HTMLElement>('.fr-field')
    if (!box) return
    const ok = validUsername(name)
    const go = box.querySelector<HTMLButtonElement>('.fr-add-go')!
    go.disabled = !ok || saving
    const input = box.querySelector<HTMLInputElement>('input')!
    input.disabled = saving
    let rule = box.querySelector<HTMLElement>('.fr-rule')
    if (name && !ok) {
      if (!rule) { rule = document.createElement('div'); rule.className = 'fr-rule'; rule.textContent = USERNAME_RULE; box.querySelector('.fr-field-row')!.after(rule) }
    } else rule?.remove()
    let err = box.querySelector<HTMLElement>('.fr-err')
    if (error) {
      if (!err) { err = document.createElement('div'); err.className = 'fr-err'; box.appendChild(err) }
      err.textContent = error
    } else err?.remove()
  }

  const wireField = (): void => {
    const input = body.querySelector<HTMLInputElement>('.fr-field input')
    if (!input) return
    input.addEventListener('input', () => {
      // 交出去的是服务端会存的样子：去首尾空白、小写（照 AccountCredentialRules.username）
      const low = input.value.toLowerCase()
      if (low !== input.value) input.value = low
      name = input.value.trim()
      error = null
      repaintField()
    })
    input.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); commit() } })
  }

  const commit = (): void => {
    if (saving || !validUsername(name)) return
    saving = true; error = null
    repaintField()
    addFriend(name).then(() => {
      saving = false; name = ''; adding = false
      paint()
    }, e => {
      saving = false
      if (e instanceof Error && e.message === 'cancelled') { paint(); return }
      error = friendErrorText(e)
      repaintField()
      body.querySelector<HTMLInputElement>('.fr-field input')?.focus({ preventScroll: true })
    })
  }

  body.addEventListener('click', e => {
    const t = e.target as HTMLElement
    const act = t.closest<HTMLElement>('[data-act]')?.dataset.act
    if (act === 'login') { host.openLogin(); return }
    if (act === 'add') {
      error = null; adding = true
      paint()
      body.querySelector<HTMLInputElement>('.fr-field input')?.focus({ preventScroll: true })
      return
    }
    if (act === 'commit') { commit(); return }
    if (act === 'retry') { pullInbox(); return }
    const itemEl = t.closest<HTMLElement>('[data-item]')
    if (itemEl) {
      const item = inboxItems().find(i => i.id === itemEl.dataset.item)
      if (item) openLetter(item, host)
    }
  })

  // 收件箱变了（拉完、已读、留下、加删朋友）就重画；正在输入时只在不是自己这一趟引起的变化时整页重画，
  // 输入框里的字与焦点用 name / 聚焦恢复
  layer.off.push(onInboxChange(() => {
    const focused = document.activeElement === body.querySelector('.fr-field input')
    paint()
    if (focused) {
      const input = body.querySelector<HTMLInputElement>('.fr-field input')
      if (input) { input.focus({ preventScroll: true }); input.setSelectionRange(input.value.length, input.value.length) }
    }
  }))
  layer.off.push(onSession(() => { adding = false; name = ''; error = null; paint() }))
  layer.off.push(() => swipes.splice(0).forEach(s => s.destroy()))
  paint()
  pullInbox()
}

/** 推「信」那一层：大图 + 说明 +「保存到图上」 */
function openLetter(item: ShareItem, host: MeHost): void {
  if (openableSymbol(item)) {
    host.popToRoot()
    if (previewShare(item)) return
    // 行情页还没建起来（极少：冷启动直接进「我的」且没去过行情页）：退一步，直接去那只的图上
    markOpened(item)
    host.openSymbol(openableSymbol(item)!, item.interval)
    return
  }
  markOpened(item)
  host.push(shortSymbol(item), (body, layer) => {
    body.classList.add('fr-letter')
    const symbol = openableSymbol(item)
    const iv = INTERVAL_DISPLAY[item.interval as Interval] ?? item.interval
    let busy = false
    const current = (): ShareItem => inboxItems().find(i => i.id === item.id) ?? item
    const paint = (): void => {
      const it = current()
      const kept = !!it.keptAt
      const label = kept ? (symbol ? '去图上看' : '已保存') : '保存到图上'
      body.innerHTML = `
        <div class="fr-shot" data-thumb="${esc(it.id)}">${CHART}</div>
        <div class="fr-letter-text">
          <div class="fr-item-title">${esc(letterTitle(it))}</div>
          <div class="fr-item-meta num">${esc([iv, letterTime(it.createdAt)].filter(Boolean).join(' · '))}${kept ? '<span>已保存</span>' : ''}</div>
          ${symbol ? '' : '<div class="fr-item-meta">这只品种网页版还打不开，保存后在 App 里看</div>'}
        </div>
        <button type="button" class="me-primary" data-act="keep"${(kept && !symbol) || busy ? ' disabled' : ''}>${label}</button>`
      fillThumbs(body)
      const shot = body.querySelector<HTMLElement>('.fr-shot')
      // 大图沿用缩略图同一张（收件箱只给一张截图）
      shot?.classList.add('big')
    }
    body.addEventListener('click', e => {
      if (!(e.target as HTMLElement).closest('[data-act="keep"]') || busy) return
      const it = current()
      if (it.keptAt) { if (symbol) host.openSymbol(symbol, it.interval); return }
      busy = true
      const r = keepItem(it)
      busy = false
      if (!r.ok) { toast(r.reason); paint(); return }
      if (symbol) host.openSymbol(symbol, it.interval)
      else { toast('已保存'); paint() }
    })
    layer.off.push(onInboxChange(paint))
    paint()
  })
}
