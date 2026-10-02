/* Hkline 手机网页版 · 「像 app」的那几件全局小事（壳装上时调一次 installNativeFeel）
 *
 * - 按下态：iOS Safari 不给 :active，除非文档上挂着一个 touchstart 监听（空的就行）。
 * - 不让页面被捏放大 / 双击放大：视口 user-scalable=no 在 iOS 上被无视，CSS 的 touch-action 之外
 *   再把 Safari 私有的 gesturestart / gesturechange 拦掉（图表自己的双指缩放走 pointer / touch，不受影响）。
 * - 长按不出系统菜单：iOS 靠 -webkit-touch-callout: none（base.css），Chromium（安卓 / 鸿蒙 ArkWeb）不认它，
 *   长按链接（底栏四格是 <a>）、图片照样弹「在新标签页打开 / 下载」——在 contextmenu 上拦掉；输入框里照常。
 * - 看图时不锁屏：照 iOS Main/KeepAwakeGate.swift——图表页在屏幕上就撑着屏幕（Screen Wake Lock），
 *   退后台 / 离开图表页放手；没在充电且电量 ≤ 20% 时也放手（网页读不到低电量模式，用「没在充电」顶它）。
 */

/** 输入框、可编辑区里长按要能出「粘贴 / 选择」菜单 */
export function allowsSystemMenu(t: EventTarget | null): boolean {
  const e = t as Element | null
  if (!e || typeof e.closest !== 'function') return false
  return !!e.closest('input, textarea, select, [contenteditable=""], [contenteditable="true"], [data-system-menu]')
}

/** 电量未知记作 -1，不算低电 */
export const LOW_BATTERY = 0.2

/** 要不要撑着屏幕（KeepAwakeGate.wantsIdleTimerDisabled 的网页版） */
export function wantsWakeLock(o: { onChart: boolean; visible: boolean; charging: boolean; battery: number }): boolean {
  if (!o.onChart || !o.visible) return false
  if (!o.charging && o.battery >= 0 && o.battery <= LOW_BATTERY) return false
  return true
}

interface WakeSentinel { released: boolean; release(): Promise<void>; addEventListener(t: 'release', fn: () => void): void }
interface BatteryLike { level: number; charging: boolean; addEventListener(t: string, fn: () => void): void }

let installed = false

/** 装一次。onChart：图表页现在是不是在屏幕上（壳换页后调返回的 refresh） */
export function installNativeFeel(onChart: () => boolean): { refresh(): void } {
  if (installed || typeof document === 'undefined') return { refresh() {} }
  installed = true

  document.addEventListener('touchstart', () => {}, { passive: true })
  const stop = (e: Event): void => e.preventDefault()
  document.addEventListener('gesturestart', stop, { passive: false } as AddEventListenerOptions)
  document.addEventListener('gesturechange', stop, { passive: false } as AddEventListenerOptions)
  document.addEventListener('contextmenu', e => { if (!allowsSystemMenu(e.target)) e.preventDefault() })

  // —— 不锁屏 ——
  const wl = (navigator as Navigator & { wakeLock?: { request(t: 'screen'): Promise<WakeSentinel> } }).wakeLock
  let lock: WakeSentinel | null = null
  let asking = false
  let battery = -1, charging = true
  const refresh = (): void => {
    if (!wl) return
    const want = wantsWakeLock({ onChart: onChart(), visible: document.visibilityState === 'visible', charging, battery })
    if (want && !lock && !asking) {
      asking = true
      wl.request('screen').then(s => {
        asking = false
        lock = s
        s.addEventListener('release', () => { if (lock === s) lock = null })
        refresh() // 请求路上换了页 / 退了后台
      }, () => { asking = false })
    } else if (!want && lock) {
      const s = lock; lock = null
      s.release().catch(() => {})
    }
  }
  // 系统在退后台时会自己收走锁；回到前台要重新要
  document.addEventListener('visibilitychange', refresh)
  const nb = navigator as Navigator & { getBattery?: () => Promise<BatteryLike> }
  nb.getBattery?.().then(b => {
    const read = (): void => { battery = b.level; charging = b.charging; refresh() }
    b.addEventListener('levelchange', read)
    b.addEventListener('chargingchange', read)
    read()
  }, () => {})
  refresh()
  return { refresh }
}
