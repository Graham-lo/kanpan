/* 手机网页版 · 推送连接「断了多久」（照 iOS Main/LinkGrace.swift）
 *
 * 顶栏价格与自选表用同一条规矩：从「该连着却不在 open」那一刻起算，满 5 秒算断——st.stale = true，
 * 价格变灰；闪断（退避第一拍 1 秒、重连几百毫秒）在宽限之内接上，看不见灰一下；一接上立刻复原。
 * 后台不算，回前台从回来那一刻重新起算。「时间流过去」不是事件，所以起算那一刻挂一拍、到点来扫。
 * 计时器本体在 app/linkGrace.ts，电脑网页 pages/chart.ts 也用它；这里只接手机壳的 st.stale。
 */
import { S, on as onMarket } from '../../market'
import { st, save } from './store'
import { LINK_GRACE_MS, LinkGrace, linkWaiting } from '../../app/linkGrace'

export { LINK_GRACE_MS, LinkGrace, linkWaiting }

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
