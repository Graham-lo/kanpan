/* 手机网页版 · 「我的 › 账号」那几层（照 iOS Account/AccountView.swift、AccountExport.swift）
 *
 * 账号页：（会话被服务端拒了 / 被同类设备顶下去时）红字一句 +「已退出登录，本机数据都在」+「重新登录」；
 *   用户名；同步 › / 登录设备 › / 修改密码 › / 导出我的数据（导出中转圈）；出错一行红字；
 *   退出登录（红字，不弹确认：本机数据都留着、随时能登回来）；注销账号（红字）→ 推注销页。
 * 同步页：上次同步（尚未同步）、出错那句、待同步 N 项；「立即同步」（同步中转圈）。
 * 登录设备：每一行都有「退出」，本机那一行点了就是退出登录（每类设备只许一台在线，这张表要看得见）。
 * 表单（登录 / 注册 / 修改密码 / 注销）：用户名框回车跳到密码框、密码框回车提交；提交中按钮里转圈；
 *   注销页只有密码 +「注销后云端数据将删除」+ 红色「注销账号」，不再追问一遍（iOS 同样没有确认框）。
 * 导出：GET /v1/auth/me/export → 键排序、两格缩进的 JSON →「Hkline-我的数据-YYYYMMDD.json」；
 *   iOS 交给系统分享面板，网页还在用户手势里时同样走系统分享（navigator.share），否则直接下载。
 *   导出途中换了号 / 退了登，回来的那份作废（不下载上一个人的数据）。
 */
import { session, loggedIn, onSession } from '../../account/session'
import { authed, login, logout, devices, kick, changePassword, deleteAccount, errorText, type DeviceRow } from '../../account/client'
import { syncNow, syncStatus, onSyncStatus } from '../app/sync'
import { icon } from '../ui/icons'
import { toast } from '../ui/toast'
import { esc } from '../ui/dom'
import { onSyncChange, syncSource } from '../model/syncStatus'
import { KIND_CN, PASSWORD_RULE, USERNAME_RULE, deviceMeta, exportFileName, sortedJSON, syncAgo, validPassword, validUsername } from '../model/formText'
import type { MeHost, MeLayer } from './meHost'

const CHEV = icon('chevronRight', 12)
export const SPIN = '<span class="me-spin" aria-hidden="true"></span>'

const navRow = (act: string, title: string, trailing = `<span class="me-chev">${CHEV}</span>`, disabled = false): string =>
  `<button type="button" class="me-row plain" data-a="${act}"${disabled ? ' disabled' : ''}><span class="me-row-title">${title}</span>${trailing}</button>`

/** 会话被拒之后那一块（照 AccountView.expired）；正常登录着时是空串 */
function expiredBlock(): string {
  if (loggedIn() || !session.notice) return ''
  return `<div class="me-card me-notice"><div class="danger">${esc(session.notice)}</div>
    <div class="me-note-in">已退出登录，本机数据都在</div>
    <button type="button" class="me-relogin" data-a="relogin">重新登录</button></div>`
}

// ───────── 账号 ─────────

export function buildAccount(body: HTMLElement, layer: MeLayer, host: MeHost): void {
  body.classList.add('me-account')
  let exporting = false
  let error: string | null = null
  /** 换号 / 退登时加一：在途的导出回来就作废 */
  let gen = 0

  const paint = (): void => {
    if (!loggedIn()) { body.innerHTML = expiredBlock(); return }
    body.innerHTML = `
      <div class="me-card"><div class="me-kv"><span>用户名</span><b>${esc(session.user)}</b></div></div>
      <div class="me-card">
        ${navRow('sync', '同步')}${navRow('devices', '登录设备')}${navRow('password', '修改密码')}
        ${navRow('export', '导出我的数据', exporting ? SPIN : `<span class="me-chev">${CHEV}</span>`, exporting)}
      </div>
      ${error ? `<div class="me-card"><div class="me-kv danger" data-error>${esc(error)}</div></div>` : ''}
      <div class="me-card">${navRow('logout', '退出登录', '').replace('me-row plain', 'me-row plain danger')}</div>
      <div class="me-card">${navRow('close', '注销账号', '').replace('me-row plain', 'me-row plain danger')}</div>`
  }

  async function exportData(): Promise<void> {
    if (exporting) return
    exporting = true; error = null
    paint()
    const started = gen
    try {
      const data = await authed<unknown>('GET', '/v1/auth/me/export')
      if (started !== gen) return
      if (!data || typeof data !== 'object') throw new Error('invalid')
      const name = exportFileName(Date.now())
      const file = new File([sortedJSON(data)], name, { type: 'application/json' })
      await deliver(file)
    } catch (e) {
      if (started === gen && !(e instanceof DOMException && e.name === 'AbortError')) error = errorText(e)
    } finally {
      if (started === gen) { exporting = false; paint() }
    }
  }

  body.addEventListener('click', e => {
    const b = (e.target as HTMLElement).closest<HTMLButtonElement>('[data-a]')
    if (!b || b.disabled) return
    switch (b.dataset.a) {
      case 'sync': host.push('同步', (bd, l) => buildSync(bd, l, host)); break
      case 'devices': host.push('登录设备', (bd, l) => buildDevices(bd, l, host)); break
      case 'password': host.push('修改密码', (bd, l) => buildAuth(bd, l, host, 'password')); break
      case 'export': void exportData(); break
      case 'logout': logout(); host.popToRoot(); toast('已退出登录'); break
      case 'close': host.push('注销账号', (bd, l) => buildAuth(bd, l, host, 'close')); break
      case 'relogin': host.openLogin(); break
    }
  })
  layer.off.push(onSession(() => {
    gen++; exporting = false; error = null
    // 在别的标签页退了登（没有原因可说）：这一页没东西可看了，回根；被拒 / 被顶下去：留在这儿说清楚
    if (!loggedIn() && !session.notice) { if (host.isTop(layer)) host.popToRoot(); return }
    paint()
  }))
  layer.off.push(() => { gen++ })
  paint()
}

/** 交出导出文件：还在用户手势里、能分享文件就走系统分享面板（照 iOS），否则下载 */
async function deliver(file: File): Promise<void> {
  const nav = navigator as Navigator & { userActivation?: { isActive: boolean } }
  if (nav.userActivation?.isActive && nav.canShare?.({ files: [file] })) {
    try { await nav.share({ files: [file] }); return } catch (e) {
      if (e instanceof DOMException && e.name === 'AbortError') return
    }
  }
  const url = URL.createObjectURL(file)
  const a = document.createElement('a')
  a.href = url; a.download = file.name; a.rel = 'noopener'
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 60_000)
}

// ───────── 同步 ─────────

function buildSync(body: HTMLElement, layer: MeLayer, host: MeHost): void {
  body.classList.add('me-account')
  const paint = (): void => {
    if (!loggedIn()) { body.innerHTML = expiredBlock(); return }
    const s = syncSource().state()
    const busy = syncStatus().syncing
    body.innerHTML = `
      <div class="me-card">
        <div class="me-kv"><span>上次同步</span><b class="num">${s.lastSync == null ? '尚未同步' : syncAgo(s.lastSync, Date.now())}</b></div>
        ${s.error ? `<div class="me-kv me-kv-note" data-sync-error>${esc(s.error)}</div>` : ''}
        ${s.pending > 0 ? `<div class="me-kv"><span>待同步</span><b class="num">${s.pending} 项</b></div>` : ''}
      </div>
      <div class="me-card"><button type="button" class="me-row plain accent" data-a="now"${busy ? ' disabled' : ''}><span class="me-row-title">立即同步</span>${busy ? SPIN : ''}</button></div>`
  }
  body.addEventListener('click', e => {
    const b = (e.target as HTMLElement).closest<HTMLButtonElement>('[data-a]')
    if (!b || b.disabled) return
    if (b.dataset.a === 'relogin') { host.openLogin(); return }
    void syncNow().finally(paint)
    paint()
  })
  layer.off.push(onSyncChange(paint), onSyncStatus(paint))
  layer.off.push(onSession(() => { if (!loggedIn() && !session.notice) { if (host.isTop(layer)) host.popToRoot() } else paint() }))
  // 「N 分钟前」会过时
  const tick = setInterval(() => { if (!document.hidden) paint() }, 30_000)
  layer.off.push(() => clearInterval(tick))
  paint()
}

// ───────── 登录设备 ─────────

function buildDevices(body: HTMLElement, layer: MeLayer, host: MeHost): void {
  body.classList.add('me-account')
  let list: DeviceRow[] | null = null
  let failed = ''
  const paint = (): void => {
    if (!loggedIn()) { body.innerHTML = expiredBlock(); return }
    const rows = list
      ? list.map(d => `<div class="me-dev">
          <span class="me-row-text"><span class="me-row-title">${esc(d.name || KIND_CN[d.kind] || '设备')}</span><span class="me-row-status num">${esc(deviceMeta(d))}</span></span>
          <button type="button" class="me-kick" data-kick="${esc(d.id)}"${d.current ? ' data-current' : ''}>退出</button></div>`).join('')
      : failed ? '' : `<div class="me-dev me-loading">${SPIN}</div>`
    body.innerHTML = (rows ? `<div class="me-card">${rows}</div>` : '')
      + (failed ? `<div class="me-card"><div class="me-kv danger" data-error>${esc(failed)}</div></div>` : '')
  }
  const load = (): void => {
    devices().then(r => { list = r; failed = ''; paint() }, err => { failed = errorText(err); paint() })
  }
  body.addEventListener('click', e => {
    const t = e.target as HTMLElement
    if (t.closest('[data-a="relogin"]')) { host.openLogin(); return }
    const b = t.closest<HTMLButtonElement>('[data-kick]')
    if (!b || b.disabled) return
    // 本机那一行：就是退出登录
    if (b.hasAttribute('data-current')) { logout(); host.popToRoot(); toast('已退出登录'); return }
    b.disabled = true
    const id = b.dataset.kick!
    kick(id).then(() => { list = list?.filter(d => d.id !== id) ?? null; failed = ''; paint() },
      err => { failed = errorText(err); b.disabled = false; paint() })
  })
  layer.off.push(onSession(() => { if (!loggedIn() && !session.notice) { if (host.isTop(layer)) host.popToRoot() } else paint() }))
  paint(); load()
}

// ───────── 表单 ─────────

export type AuthPage = 'login' | 'register' | 'password' | 'close'

export function buildAuth(body: HTMLElement, layer: MeLayer, host: MeHost, page: AuthPage): void {
  body.classList.add('me-form')
  const title = { login: '登录', register: '注册', password: '保存', close: '注销账号' }[page]
  const fields: [string, string, string, string][] = page === 'login' || page === 'register'
    ? [['user', '用户名', 'text', 'username'], ['pass', '密码', 'password', page === 'register' ? 'new-password' : 'current-password']]
    : page === 'password' ? [['pass', '当前密码', 'password', 'current-password'], ['next', '新密码', 'password', 'new-password']]
      : [['pass', '密码', 'password', 'current-password']]
  // 被拒 / 被顶下去之后来登录：先说清楚为什么、数据没丢
  const notice = (page === 'login' || page === 'register') && session.notice
    ? `<div class="me-card me-notice"><div class="danger">${esc(session.notice)}</div><div class="me-note-in">已退出登录，本机数据都在</div></div>` : ''
  body.innerHTML = `${notice}${fields.map(([k, label, type, ac], i) => `<label class="me-field"><span class="me-flabel">${label}</span>
      <input data-k="${k}" type="${type}" autocomplete="${ac}" autocapitalize="off" autocorrect="off" spellcheck="false" ${k === 'user' ? 'lang="en" inputmode="latin"' : ''}
        enterkeyhint="${i === fields.length - 1 ? 'go' : 'next'}" placeholder="${label}">
      <span class="me-rule" data-rule="${k}" hidden></span></label>`).join('')}
    ${page === 'close' ? '<div class="me-close-note">注销后云端数据将删除</div>' : ''}
    <div class="me-err" hidden></div>
    <button type="button" class="me-primary${page === 'close' ? ' danger' : ''}" disabled aria-label="${title}"><span class="me-primary-t">${title}</span></button>
    ${page === 'login' || page === 'register' ? `<button type="button" class="me-switch">${page === 'login' ? '注册' : '登录'}</button>` : ''}`
  const input = (k: string): HTMLInputElement | null => body.querySelector<HTMLInputElement>(`input[data-k="${k}"]`)
  const btn = body.querySelector<HTMLButtonElement>('.me-primary')!
  const errEl = body.querySelector<HTMLElement>('.me-err')!
  let busy = false
  const values = (): Record<string, string> => ({ user: input('user')?.value.trim() ?? '', pass: input('pass')?.value ?? '', next: input('next')?.value ?? '' })
  const ok = (): boolean => {
    const v = values()
    if (page === 'login') return validUsername(v.user) && v.pass.length > 0
    if (page === 'register') return validUsername(v.user) && validPassword(v.pass)
    if (page === 'password') return v.pass.length > 0 && validPassword(v.next)
    return v.pass.length > 0
  }
  const paint = (): void => {
    const v = values()
    const ru = body.querySelector<HTMLElement>('[data-rule="user"]')
    if (ru) { ru.textContent = USERNAME_RULE; ru.hidden = !v.user || validUsername(v.user) }
    const rp = body.querySelector<HTMLElement>(page === 'register' ? '[data-rule="pass"]' : '[data-rule="next"]')
    const pw = page === 'register' ? v.pass : v.next
    if (rp && (page === 'register' || page === 'password')) { rp.textContent = PASSWORD_RULE; rp.hidden = !pw || validPassword(pw) }
    btn.disabled = busy || !ok()
    btn.classList.toggle('busy', busy)
    btn.innerHTML = busy ? SPIN : `<span class="me-primary-t">${title}</span>`
  }
  body.addEventListener('input', e => {
    const t = e.target as HTMLInputElement
    if (t.dataset.k === 'user') { const low = t.value.toLowerCase(); if (low !== t.value) t.value = low }
    errEl.hidden = true; paint()
  })
  // 回车：前面的框跳到下一个框，最后一个框提交（照 iOS .submitLabel(.next / .go)）
  body.addEventListener('keydown', e => {
    if ((e as KeyboardEvent).key !== 'Enter' || (e as KeyboardEvent).isComposing) return
    const t = e.target as HTMLElement
    if (!(t instanceof HTMLInputElement)) return
    e.preventDefault()
    const i = fields.findIndex(([k]) => k === t.dataset.k)
    if (i >= 0 && i < fields.length - 1) { input(fields[i + 1][0])?.focus(); return }
    if (!btn.disabled) btn.click()
  })
  body.querySelector<HTMLElement>('.me-switch')?.addEventListener('click', () => {
    host.back()
    const next: AuthPage = page === 'login' ? 'register' : 'login'
    host.push(next === 'login' ? '登录' : '注册', (b, l) => buildAuth(b, l, host, next))
  })
  btn.onclick = async () => {
    if (!ok() || busy) return
    const v = values()
    busy = true; paint()
    ;(document.activeElement as HTMLElement | null)?.blur?.()
    try {
      if (page === 'login' || page === 'register') {
        await login(v.user, v.pass, page === 'register')
        if (host.isTop(layer)) host.popToRoot()
        toast(page === 'register' ? '注册成功' : '已登录')
      } else if (page === 'password') {
        await changePassword(v.pass, v.next)
        if (host.isTop(layer)) host.back()
        toast('密码已修改')
      } else {
        await deleteAccount(v.pass)
        if (host.isTop(layer)) host.popToRoot()
        toast('账号已注销')
      }
    } catch (err) {
      busy = false
      const text = errorText(err, page === 'login' ? 'login' : page === 'register' ? 'register' : 'password')
      // 请求在路上时人已经退出这一层：结果用提示条说，不动别人后来推的那层
      if (!host.isTop(layer)) { toast(text); return }
      errEl.textContent = text
      errEl.hidden = false
      paint()
    }
  }
  layer.off.push(() => { busy = false })
  // 别的标签页登进去了（登录 / 注册页）、会话没了（改密码 / 注销页）：这一页没意义了，回根
  layer.off.push(onSession(() => {
    if (busy || !host.isTop(layer)) return
    if ((page === 'login' || page === 'register') ? loggedIn() : !loggedIn()) host.popToRoot()
  }))
  paint()
  requestAnimationFrame(() => input(fields[0][0])?.focus({ preventScroll: true }))
}
