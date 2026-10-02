/* 手机网页版 · 系统通知与提醒铃声（价格提醒、自选波动、上新下架三处共用）
 *
 * 照 iOS 本地通知的样子：标题、正文、点开就去那只品种的行情页；铃声跟设置里「铃声」那一档。
 * - 页面开着时：价格提醒、自选波动只出页里的提示条 + 响铃，不再压一张系统横幅（iOS willPresent 同样压掉）；
 *   上新下架照常弹系统通知。页面在后台时一律弹系统通知。
 * - 「默认」= 系统通知自带的声音（网页拿不到系统铃声文件），所以前台只出提示条时没有声音——浏览器做不到。
 * - 清脆 / 电子 / 玻璃：页面开着时由这里用 Web Audio 播 iOS 同一份声音（Web/public/m/alert-*.m4a，
 *   由 Kanpan/Kanpan/Resources/alert-*.caf 转码），同时弹的通知静音免得响两遍；页面在后台时网页放不了声音，
 *   通知用系统默认声。浏览器要求先有一次用户手势才能出声，第一次点屏幕时解锁。
 * - 点通知：页面里 new Notification 的直接 onclick；加到主屏幕走 service worker 的，由 sw.js 的
 *   notificationclick 把品种发回来（type: 'notify-open'），页面没开着就新开一页带 ?notify=。
 */
import { st } from '../app/store'
import { openSymbol } from '../app/shell'
import type { AlertSound } from '../app/prefs'

const ICON = import.meta.env.BASE_URL + 'm/icon-192.png'
const SOUND_URL = (s: Exclude<AlertSound, 'default'>): string => import.meta.env.BASE_URL + `m/alert-${s}.m4a`

/** 通知权限：'granted' | 'denied' | 'default'；浏览器没有通知能力时是 'unsupported' */
export function notifyPermission(): NotificationPermission | 'unsupported' {
  try { return typeof Notification === 'undefined' ? 'unsupported' : Notification.permission } catch { return 'unsupported' }
}

/** 要一次权限（只在还没问过时弹系统框）；返回问完之后的状态 */
export async function askNotifyPermission(): Promise<NotificationPermission | 'unsupported'> {
  const p = notifyPermission()
  if (p !== 'default') return p
  try { return await Notification.requestPermission() } catch { return notifyPermission() }
}

export interface NotifyOptions {
  title: string
  body: string
  /** 同一个 tag 的通知只留最新一条 */
  tag: string
  /** 点开去哪只（图表页认的代号）；没有就只把页面叫到前面 */
  symbol?: string | null
  /** 页面开着时弹不弹系统横幅。照 iOS AlertNotifications.willPresent：价格提醒与自选波动前台有自己的浮条，
   *  系统横幅压掉（只响铃）；上新下架前台没有浮条替它说，照常弹 */
  foreground: 'sound' | 'banner'
}

const visible = (): boolean => document.visibilityState === 'visible'

/** 发一条系统通知并按设置响铃。返回这条有没有真的弹成系统通知（没权限、前台只响铃时是 false） */
export function notify(o: NotifyOptions): boolean {
  const sound = st.alertSound
  if (visible() && sound !== 'default') playSound(sound)
  if (o.foreground === 'sound' && visible()) return false
  if (notifyPermission() !== 'granted') return false
  const opts: NotificationOptions = { body: o.body, tag: o.tag, icon: ICON, silent: sound !== 'default' && visible(), data: { symbol: o.symbol ?? '' } }
  try {
    // 加到主屏幕的 PWA 里 new Notification 不可用，要经 service worker
    if (navigator.serviceWorker?.controller) {
      void navigator.serviceWorker.ready.then(r => r.showNotification(o.title, opts)).catch(() => {})
      return true
    }
    const n = new Notification(o.title, opts)
    n.onclick = () => {
      n.close()
      try { window.focus() } catch { /* 忽略 */ }
      if (o.symbol) openSymbol(o.symbol)
    }
    return true
  } catch { return false }
}

// ───────── 铃声 ─────────

let ctx: AudioContext | null = null
const buffers = new Map<string, Promise<AudioBuffer | null>>()

function audio(): AudioContext | null {
  if (ctx) return ctx
  const C = (globalThis as { AudioContext?: typeof AudioContext; webkitAudioContext?: typeof AudioContext }).AudioContext
    ?? (globalThis as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext
  if (!C) return null
  try { ctx = new C() } catch { ctx = null }
  return ctx
}

function load(s: Exclude<AlertSound, 'default'>): Promise<AudioBuffer | null> {
  let p = buffers.get(s)
  if (!p) {
    p = fetch(SOUND_URL(s)).then(r => (r.ok ? r.arrayBuffer() : Promise.reject(new Error(String(r.status)))))
      .then(b => new Promise<AudioBuffer | null>(res => { const a = audio(); if (!a) { res(null); return } a.decodeAudioData(b, res, () => res(null)) }))
      .catch(() => { buffers.delete(s); return null })
    buffers.set(s, p)
  }
  return p
}

/** 播一遍；页面在后台、没解锁过、解不出来都静默跳过 */
export function playSound(s: AlertSound): void {
  if (s === 'default' || document.visibilityState !== 'visible') return
  const a = audio()
  if (!a) return
  void load(s).then(buf => {
    if (!buf) return
    if (a.state === 'suspended') void a.resume().catch(() => {})
    const src = a.createBufferSource()
    src.buffer = buf
    src.connect(a.destination)
    src.start()
  })
}

/** 设置里点一档时的试听（照 iOS AlertSoundPage：选了就响一遍）。「默认」只能借一条通知响，没权限就不响 */
export function previewSound(s: AlertSound): void {
  if (s !== 'default') { playSound(s); return }
  if (notifyPermission() !== 'granted') return
  const opts: NotificationOptions = { body: '提醒到了会这样响', tag: 'sound-preview', icon: ICON, data: { symbol: '' } }
  try {
    if (navigator.serviceWorker?.controller) void navigator.serviceWorker.ready.then(r => r.showNotification('默认铃声', opts)).catch(() => {})
    else new Notification('默认铃声', opts)
  } catch { /* 忽略 */ }
}

let wired = false
/** 启动时调一次（幂等）：第一次点屏幕解锁声音；接住 service worker 转来的「点了通知」与 ?notify= 深链 */
export function wireNotify(): void {
  if (wired) return
  wired = true
  const unlock = (): void => {
    const a = audio()
    if (a && a.state === 'suspended') void a.resume().catch(() => {})
    if (st.alertSound !== 'default') void load(st.alertSound)
  }
  // 一直挂着：iOS Safari 切后台回来会把上下文重新挂起，下一次点屏幕再恢复
  document.addEventListener('pointerdown', unlock, { capture: true, passive: true })
  navigator.serviceWorker?.addEventListener('message', e => {
    const d = e.data as { type?: unknown; symbol?: unknown } | null
    if (d && d.type === 'notify-open' && typeof d.symbol === 'string' && d.symbol) openSymbol(d.symbol)
  })
  try {
    const q = new URLSearchParams(location.search)
    const sym = q.get('notify')
    if (sym) {
      q.delete('notify')
      const qs = q.toString()
      history.replaceState(history.state, '', location.pathname + (qs ? '?' + qs : '') + location.hash)
      if (/^[A-Za-z0-9_]{2,30}$/.test(sym)) openSymbol(sym)
    }
  } catch { /* 忽略 */ }
}
