/* Hkline Web · 推送连接「断了多久」（照 iOS Main/LinkGrace.swift；电脑网页与手机网页共用这一份）
 *
 * 断线变灰只看推送连接，从「该连着却不在 open」那一刻起算，满 5 秒算断；闪断（退避第一拍 1 秒、重连几百毫秒）
 * 在宽限之内接上，看不见灰一下；一接上立刻复原。后台不算，回前台从回来那一刻重新起算。
 * 全市场表（REST）取没取到不在这条规矩里：它有自己的重试，推送连着、K 线帧照来的时候不能把图冻住。
 * 「时间流过去」不是事件，所以起算那一刻挂一拍、到点来扫。
 */
import type { S } from '../market'
import { ago } from '../util/clock'

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
  isDown(now: number): boolean { return this.since != null && ago(this.since, now) >= LINK_GRACE_MS }
}

/** 此刻该连着却没连上：前台、有流要订（idle = 没人要连接）、却不是 open */
export function linkWaiting(ws: typeof S.wsState, foreground: boolean): boolean {
  return foreground && ws !== 'idle' && ws !== 'open'
}
