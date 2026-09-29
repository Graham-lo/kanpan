/* 手机网页版 · 「我的」账号行的同步状态位（照 iOS MePage.accountRow / MePage.syncMeta）
 *
 * 登录了：第一行用户名，第二行同步状态（报的是「新不新」，不是「成功」），行尾一颗「立即同步」。
 * 同步引擎由 A 接（Web/src/sync/runtime.ts + m/app 那一侧的适配器）；它落地后在建运行时的地方调一次
 *   setSyncSource({ state, syncNow, onChange })
 * 把这里的占位换掉，「我的」页不用再改。
 */

export interface SyncState {
  /** 同步真出错时的那句错误（iOS account.syncStatus 里不在「套话」集合里的那种）；没错就是空串 */
  error: string
  /** 本机还没推上去的操作数 */
  pending: number
  /** 上一次推完 / 拉完的时刻（毫秒）；还没同步过是 null */
  lastSync: number | null
}

export interface SyncSource {
  state(): SyncState
  /** 「立即同步」 */
  syncNow(): void
  /** 状态变了（推完、拉完、出错、队列长了）；返回退订 */
  onChange(fn: () => void): () => void
}

// TODO(A 同步引擎)：同步运行时落地后由 m/app 侧调 setSyncSource 换掉这个占位——
// 占位只报「尚未同步」，「立即同步」只说一句还没接上，不假装同步过。
const placeholder: SyncSource = {
  state: () => ({ error: '', pending: 0, lastSync: null }),
  syncNow: () => { placeholderTap?.() },
  onChange: () => () => {},
}
let placeholderTap: (() => void) | null = null
/** 占位时点「立即同步」的反应（me.ts 给一句提示） */
export function onPlaceholderSync(fn: () => void): void { placeholderTap = fn }

let source: SyncSource = placeholder
const swapListeners = new Set<() => void>()
export function setSyncSource(s: SyncSource | null): void { source = s ?? placeholder; swapListeners.forEach(f => f()) }
export const syncSource = (): SyncSource => source
export const syncIsPlaceholder = (): boolean => source === placeholder
/** 换了来源也要重画：订这个 + 当前来源的 onChange */
export function onSyncChange(fn: () => void): () => void {
  let off = source.onChange(fn)
  const swap = (): void => { off(); off = source.onChange(fn); fn() }
  swapListeners.add(swap)
  return () => { off(); swapListeners.delete(swap) }
}

/** 账号行第二行（照 iOS MePage.syncMeta 逐句）：出错说那句错误；有没推上去的报几项；推完了报多久以前 */
export function syncMeta(s: SyncState, now = Date.now()): string {
  if (s.error) return s.error
  if (s.pending > 0) return `待同步 ${s.pending} 项`
  if (s.lastSync == null) return '尚未同步'
  const age = Math.floor((now - s.lastSync) / 1000)
  if (age < 60) return '已同步'
  if (age < 3600) return `上次 ${Math.floor(age / 60)} 分钟前`
  if (age < 86_400) return `上次 ${Math.floor(age / 3600)} 小时前`
  return `上次 ${Math.floor(age / 86_400)} 天前`
}
