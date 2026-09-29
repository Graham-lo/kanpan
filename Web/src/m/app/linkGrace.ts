/* 手机网页版 · 推送连接「断了多久」（照 iOS Main/LinkGrace.swift）
 *
 * 顶栏价格与自选表用同一条规矩：从「该连着却不在 open」那一刻起算，满 5 秒算断——st.stale = true，
 * 价格变灰；闪断（退避第一拍 1 秒、重连几百毫秒）在宽限之内接上，看不见灰一下；一接上立刻复原。
 * 后台不算，回前台从回来那一刻重新起算。「时间流过去」不是事件，所以起算那一刻挂一拍、到点来扫。
 */
import { S, on as onMarket } from '../../market'
import { st, save } from './store'

export const LINK_GRACE_MS = 5000

/** 只管计时，不管调度（与 iOS LinkGrace 同形） */
export class LinkGrace {
  since: number | null = null
  /** 报一次现状；waiting = 此刻该连着却不在 open。返回 true = 刚开始起算（持有者该在宽限之后来扫） */
  track(waiting: boolean, now: number): boolean {
    if (!waiting) { this.since = null; return false }
    if (this.since != null) return false
    this.since = now
    return true
  }
  isDown(now: number): boolean { return this.since != null && now - this.since >= LINK_GRACE_MS }
}

/** 此刻该连着却没连上：前台、有流要订（idle = 没人要连接）、却不是 open */
export function linkWaiting(ws: typeof S.wsState, foreground: boolean): boolean {
  return foreground && ws !== 'idle' && ws !== 'open'
}

let started = false
/** 壳启动时调一次：连接状态一变就对表，断满宽限把 st.stale 置上并 save()（页面在订阅里重画） */
export function startLinkGrace(): void {
  if (started) return
  started = true
  const link = new LinkGrace()
  let timer: ReturnType<typeof setTimeout> | null = null
  const fg = (): boolean => typeof document === 'undefined' || document.visibilityState !== 'hidden'
  const settle = (): void => {
    const down = link.isDown(Date.now())
    if (down !== st.stale) { st.stale = down; save() }
  }
  const check = (): void => {
    if (link.track(linkWaiting(S.wsState, fg()), Date.now())) {
      if (timer) clearTimeout(timer)
      timer = setTimeout(() => { timer = null; settle() }, LINK_GRACE_MS + 50)
    }
    if (link.since == null && timer) { clearTimeout(timer); timer = null }
    settle()
  }
  onMarket(e => { if (e.type === 'ws') check() })
  document.addEventListener('visibilitychange', check)
  check()
}
