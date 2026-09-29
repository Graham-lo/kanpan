/* 手机网页版 · 品种表（universe）的刷新节奏（壳层）
 *
 * 各页的 ensureUniverse 只在表还没有时拉一次；加到主屏的 PWA 一开就是几天，新上线的品种搜不到、
 * 已下架的不会翻成下架。这里定节奏：
 * - 回到前台时，距上次成功拉到超过 30 分钟就重拉；
 * - 页面在前台时每 6 小时重拉一次（后台的定时器浏览器会节流，回前台那一下兜住）。
 * 重拉走 _streams.refreshUniverse → market.loadUniverse，成功后照常发全局 universe 事件（各页都在听）。
 * 手里已经有表时拉失败：loadUniverse 会把 S.live 翻成 false（行情页据此把价格置灰、自选据此不判下架），
 * 这里把在线状态还原、旧表不动、再发一次 universe 让各页按原状态重画——同一轮微任务里完成，界面上看不到。
 */
import { S, emit, on } from '../../market'
import { refreshUniverse } from '../pages/_streams'

export const FOREGROUND_AFTER = 30 * 60_000
export const EVERY = 6 * 3600_000

export interface UniverseRefreshDeps {
  /** 挂「回到前台」回调（壳的 hooks.onForeground） */
  onForeground(fn: () => void): void
  now?: () => number
  visible?: () => boolean
  every?: (fn: () => void, ms: number) => unknown
}

export function startUniverseRefresh(d: UniverseRefreshDeps): { run(): Promise<void>; lastOk(): number } {
  const now = d.now ?? Date.now
  const visible = d.visible ?? (() => document.visibilityState === 'visible')
  const every = d.every ?? ((fn: () => void, ms: number) => setInterval(fn, ms))
  let lastOk = S.live === true && S.symbols.size ? now() : 0
  let restoring = false
  // 各页首拉（ensureUniverse）成功也算一次
  on(e => { if (e.type === 'universe' && !restoring && S.live === true && S.symbols.size) lastOk = now() })

  let running: Promise<void> | null = null
  const run = (): Promise<void> => running ??= (async () => {
    const had = S.live === true && S.symbols.size > 0
    const prev = { live: S.live, limited: S.limited, error: S.error }
    try {
      await refreshUniverse()
    } finally { running = null }
    if (S.live === true) { lastOk = now(); return }
    if (had) {
      Object.assign(S, prev)
      restoring = true
      try { emit({ type: 'universe' }) } finally { restoring = false }
    }
  })()

  d.onForeground(() => { if (lastOk && now() - lastOk > FOREGROUND_AFTER) void run() })
  every(() => { if (visible() && lastOk && now() - lastOk >= EVERY - 60_000) void run() }, EVERY)
  return { run, lastOk: () => lastOk }
}
