/* 手机网页版 · 「我的 › 设置」（照 iOS Panels/SettingsPanel.swift、DisplaySettingsSection、Alerts/AlertSettingsSection、
 * Alerts/AlertSoundPage、Habits/HabitSettingsView）
 *
 * 一页平铺在 --app 上，分组只有组名、没有说明文字：
 *   配色（三张皮肤卡）· 深浅（外观）· 行情（涨跌色、线路 ?）·
 *   通知（通知被拒 / 浏览器收不了通知时最上面一条琥珀提示行；铃声 › 推一页四档；波动提醒 ? 开关；上新下架开关）·
 *   通用（自动适应 ? 开关；开着时「已学到的 N 项 ›」推一页；关于：版本 + 隐私政策 / 服务条款；恢复默认：不弹确认，提示条里「撤销」）。
 * 价格轴（线性 / 对数）不在这里：iOS 收设置项时把它留在图表设置里，网页版同样只在行情页的图表设置里切。
 * 改一下立刻生效、立刻落盘；进下一页的行尾一律是箭头，就地动作（恢复、清除）是强调色 / 红色的字。
 */
import { st, save, subscribe, layoutSettled, resolvedTheme } from '../app/store'
import { applyTheme, hooks } from '../app/shell'
import type { AlertSound } from '../app/prefs'
import { setRoute } from '../../market'
import { ISSUER } from '../../account/client'
import { baseOf } from '../../alerts/shape'
import { icon } from '../ui/icons'
import { registerTerms, termHTML } from '../ui/hint'
import { confirmDialog } from '../ui/sheet'
import { toast } from '../ui/toast'
import { esc } from '../ui/dom'
import { learnedCount, learnedGroups } from '../model/habits'
import { resetPrefs, restorePrefs } from '../model/prefsReset'
import { SOUNDS, permissionHint, soundTitle, webVersion } from '../model/formText'
import { askNotifyPermission, notifyPermission, previewSound } from './notify'
import { clearLearned, setHabitLearning } from './habitsRuntime'
import { retryUniverse } from './_streams'
import type { MeHost, MeLayer } from './meHost'

// 照 iOS GlossaryTerms+Settings；线路那条按网页版出厂是网关改了说法（浏览器在国内直连不上币安）
registerTerms([
  { id: 'route', title: '线路 · 行情从哪来', body: '网关：经我们的服务器转一道，出厂就是它——国内不开代理时浏览器连不上交易所。\n直连：手机自己直接连交易所，在海外或开着代理时少转一道。\n选了哪条就一直走哪条，不会自己切换。' },
  { id: 'watchMove', title: '波动提醒', body: '自选里的品种短时间内涨跌得特别快时，发一条通知。\n多快才算快按每只自己平时的波动自动定，不用自己填。' },
  { id: 'habits', title: '自动适应', body: '按你平时怎么用来调默认：每只品种常看的周期、各类品种用对数还是线性刻度、板块页看今日还是 5 日、波动提醒的灵敏度。\n学到的都列在「已学到的」里；关掉立刻回到出厂设置。' },
])

/** 配色卡的取色（照 tokens.css 各皮肤的 app / ink / ink3 / accent；卡要画别的皮肤，不能读当前变量） */
const SKINS = {
  sage: { name: '青苔', note: '冷 · 墨绿', light: ['#F3F7F4', '#14211B', '#606F67', '#2E7D6B'], dark: ['#0B120F', '#E9F2EC', '#7B8D85', '#4FB69C'] },
  terra: { name: '陶土', note: '暖 · 赤陶', light: ['#FBF6F0', '#241A13', '#756659', '#B25735'], dark: ['#16100C', '#F7EFE6', '#958576', '#E2874F'] },
  classic: { name: '经典', note: '白 · 墨绿', light: ['#FFFFFF', '#14211B', '#606F67', '#2E7D6B'], dark: ['#0D111C', '#E9F2EC', '#7B8D85', '#4FB69C'] },
} as const
type SkinId = keyof typeof SKINS

const seg = (id: string, opts: [string, string][], on: string): string =>
  `<div class="m-seg" role="radiogroup" data-seg="${id}">${opts.map(([v, t]) => `<button type="button" class="m-seg-opt${v === on ? ' on' : ''}" role="radio" aria-checked="${v === on}" data-v="${v}">${t}</button>`).join('')}</div>`
const sw = (id: string, on: boolean, label: string): string =>
  `<button type="button" class="me-switch-t${on ? ' on' : ''}" role="switch" aria-checked="${on}" aria-label="${label}" data-sw="${id}"><i></i></button>`
const CHEV = icon('chevronRight', 12)

/** 设置页的一行：名字（可带 ?）、名字下的灰字、行尾控件；tap 给了就整行可点 */
function prow(name: string, trailing: string, o: { term?: string; meta?: string; tap?: string; last?: boolean } = {}): string {
  const head = `<span class="me-pname-wrap"><span class="me-pname">${esc(name)}${o.term ? termHTML(o.term) : ''}</span>${o.meta ? `<span class="me-pmeta num">${esc(o.meta)}</span>` : ''}</span>`
  const cls = 'me-prow' + (o.last ? ' last' : '')
  return o.tap
    ? `<button type="button" class="${cls} tap" data-tap="${o.tap}">${head}<span class="me-ptrail">${trailing}</span></button>`
    : `<div class="${cls}">${head}<span class="me-ptrail">${trailing}</span></div>`
}

const isStandalone = (): boolean =>
  matchMedia?.('(display-mode: standalone)').matches || (navigator as { standalone?: boolean }).standalone === true

const legalBase = (): string => (import.meta.env.DEV ? 'https://' + ISSUER : location.origin)

export function buildSettings(body: HTMLElement, layer: MeLayer, host: MeHost): void {
  body.classList.add('me-settings')
  const version = webVersion(document.querySelector<HTMLScriptElement>('script[src*="/assets/m-"]')?.getAttribute('src') ?? null, import.meta.env.DEV)

  const swatch = (id: SkinId, dark: boolean): string => {
    const s = SKINS[id]
    const [app, ink, ink3, accent] = dark ? s.dark : s.light
    const bars = Array.from({ length: 6 }, (_, i) => `<i style="height:${10 + (i * 7) % 27}px;background:var(${i % 3 === 0 ? '--k-down' : '--k-up'})"></i>`).join('')
    return `<button type="button" class="me-swatch${st.skin === id ? ' on' : ''}" data-skin="${id}" role="radio" aria-checked="${st.skin === id}" style="background:${app}">
      <span class="me-sw-art"><span class="me-sw-bars">${bars}</span><span class="me-sw-dot" style="background:${accent}"></span></span>
      <span class="me-sw-name"><b style="color:${ink}">${s.name}</b><small style="color:${ink3}">${s.note}</small></span></button>`
  }

  const paint = (): void => {
    const dark = resolvedTheme() === 'dark'
    const hint = permissionHint(notifyPermission(), navigator.userAgent, isStandalone())
    const count = st.habitLearning ? learnedCount(st.learnedDefaults, baseOf) : 0
    body.innerHTML = `
      <div class="me-group">配色</div>
      <div class="me-swatches" role="radiogroup">${(Object.keys(SKINS) as SkinId[]).map(id => swatch(id, dark)).join('')}</div>
      <div class="me-group">深浅</div>
      ${prow('外观', seg('theme', [['auto', '跟随系统'], ['light', '浅色'], ['dark', '深色']], st.theme), { last: true })}
      <div class="me-group">行情</div>
      ${prow('涨跌色', seg('updown', [['green', '绿涨红跌'], ['red', '红涨绿跌']], st.redUp ? 'red' : 'green'))}
      ${prow('线路', seg('route', [['direct', '直连'], ['gateway', '网关']], st.routePolicy), { term: 'route', last: true })}
      <div class="me-group">通知</div>
      ${hint ? `<button type="button" class="me-perm" data-tap="perm"><span>通知关着，提醒到了不会响</span><b>去打开${CHEV}</b></button>` : ''}
      ${prow('铃声', `<span class="me-pval">${soundTitle(st.alertSound)}</span><span class="me-chev">${CHEV}</span>`, { tap: 'sound' })}
      ${prow('波动提醒', sw('watchMove', st.watchMoveAlert, '波动提醒'), { term: 'watchMove' })}
      ${prow('上新下架', sw('listing', st.notifyListingChanges, '上新下架'), { last: true })}
      <div class="me-group">通用</div>
      ${prow('自动适应', sw('habits', st.habitLearning, '自动适应'), { term: 'habits' })}
      ${st.habitLearning ? prow('已学到的', `${count > 0 ? `<span class="me-pval num">${count} 项</span>` : ''}<span class="me-chev">${CHEV}</span>`, { tap: 'learned' }) : ''}
      ${prow('关于', `<a class="me-link" href="${legalBase()}/privacy" target="_blank" rel="noopener">隐私政策</a><a class="me-link" href="${legalBase()}/terms" target="_blank" rel="noopener">服务条款</a>`, { meta: version })}
      ${prow('恢复默认', '<span class="me-act">恢复</span>', { tap: 'reset', last: true })}`
  }

  const askIfNeeded = (): void => {
    if (notifyPermission() === 'default') void askNotifyPermission().then(paint)
  }

  body.addEventListener('click', e => {
    const t = e.target as HTMLElement
    if (t.closest('a.me-link')) return
    const sk = t.closest<HTMLElement>('.me-swatch')
    if (sk) { st.skin = sk.dataset.skin as SkinId; save(); applyTheme(); paint(); return }
    const s = t.closest<HTMLElement>('[data-sw]')
    if (s) {
      switch (s.dataset.sw) {
        case 'watchMove': st.watchMoveAlert = !st.watchMoveAlert; save(); if (st.watchMoveAlert) askIfNeeded(); break
        case 'listing': st.notifyListingChanges = !st.notifyListingChanges; save(); if (st.notifyListingChanges) askIfNeeded(); break
        case 'habits': setHabitLearning(!st.habitLearning); break
      }
      paint()
      return
    }
    const opt = t.closest<HTMLElement>('.m-seg-opt')
    if (opt) {
      const v = opt.dataset.v!
      switch (opt.parentElement!.dataset.seg) {
        case 'theme': st.theme = v as typeof st.theme; save(); applyTheme(); break
        case 'updown': st.redUp = v === 'red'; save(); applyTheme(); break
        case 'route':
          if (v === st.routePolicy) return
          st.routePolicy = v as typeof st.routePolicy; st.routePicked = true; save(); setRoute(st.routePolicy); void retryUniverse()
          break
      }
      paint()
      return
    }
    const tap = t.closest<HTMLElement>('[data-tap]')?.dataset.tap
    if (tap === 'perm') { const h = permissionHint(notifyPermission(), navigator.userAgent, isStandalone()); if (h) toast(h); else paint() }
    else if (tap === 'sound') host.push('铃声', (b, l) => buildSound(b, l))
    else if (tap === 'learned') host.push('已学到的', (b, l) => buildLearned(b, l, host))
    else if (tap === 'reset') resetAll()
  })

  function resetAll(): void {
    const { changed, before } = resetPrefs(st)
    layoutSettled()
    save()
    applyTheme()
    paint()
    if (!changed.length) { toast('已恢复默认'); return }
    toast('已恢复默认', {
      title: '撤销',
      run: () => {
        if (!restorePrefs(st, changed, before).length) return
        layoutSettled()
        save()
        applyTheme()
      },
    })
  }

  const onTheme = (): void => paint()
  // 回前台再查一遍权限：人可能刚去浏览器设置里把通知打开，这一行要自己消失
  const onFg = (): void => paint()
  hooks.onTheme.push(onTheme)
  hooks.onForeground.push(onFg)
  layer.off.push(
    () => { const i = hooks.onTheme.indexOf(onTheme); if (i >= 0) hooks.onTheme.splice(i, 1) },
    () => { const i = hooks.onForeground.indexOf(onFg); if (i >= 0) hooks.onForeground.splice(i, 1) },
    // 别的设备改的、撤销回来的设置落地时跟着变
    subscribe(() => paint()),
  )
  paint()
}

/** 铃声：四档，选中那一行名字与勾都用强调色；点一档就换并试听一遍 */
function buildSound(body: HTMLElement, layer: MeLayer): void {
  body.classList.add('me-settings', 'me-sound')
  layer.el.classList.add('me-raised')
  const paint = (): void => {
    body.innerHTML = SOUNDS.map(([v, title], i) => {
      const on = st.alertSound === v
      return `<button type="button" class="me-prow tap${on ? ' on' : ''}${i === SOUNDS.length - 1 ? ' last' : ''}" data-sound="${v}" role="radio" aria-checked="${on}">
        <span class="me-pname">${title}</span><span class="me-check">${icon('check', 16)}</span></button>`
    }).join('')
  }
  body.addEventListener('click', e => {
    const b = (e.target as HTMLElement).closest<HTMLElement>('[data-sound]')
    if (!b) return
    const v = b.dataset.sound as AlertSound
    if (st.alertSound !== v) { st.alertSound = v; save() }
    previewSound(v)
    paint()
  })
  layer.off.push(subscribe(() => paint()))
  paint()
}

/** 已学到的：四组只读列表，每行「学到了什么 · 依据几次」；最下面红字「清除已学到的」，确认一次 */
function buildLearned(body: HTMLElement, layer: MeLayer, host: MeHost): void {
  body.classList.add('me-settings', 'me-learned')
  const paint = (): void => {
    const groups = learnedGroups(st.learnedDefaults, baseOf)
    body.innerHTML = (groups.length
      ? groups.map(g => `<div class="me-group">${esc(g.title)}</div>${g.rows.map((r, i) =>
        prow(r.name, `<span class="me-pval ink2">${esc(r.value)}</span>`, { meta: `依据 ${r.count} 次`, last: i === g.rows.length - 1 })).join('')}`).join('')
      : '<div class="me-learned-empty">暂无</div>')
      + `<button type="button" class="me-clear" data-clear${groups.length ? '' : ' disabled'}>清除已学到的</button>`
  }
  body.addEventListener('click', e => {
    const b = (e.target as HTMLElement).closest<HTMLButtonElement>('[data-clear]')
    if (!b || b.disabled) return
    void confirmDialog({ title: '清除已学到的？', confirm: '清除', cancel: '取消', destructive: true }).then(ok => { if (ok) clearLearned() })
  })
  // 别的设备把开关关了：这一页就没有意义了，退回设置
  layer.off.push(subscribe(() => { if (!st.habitLearning && host.isTop(layer)) host.back(); else paint() }))
  paint()
}
