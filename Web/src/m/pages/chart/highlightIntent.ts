/* Hkline 手机网页 · 首页「异动」点一行带去行情页的意图
 *
 * 首页在 openSymbol 之前放一份（哪只、要展开哪张卡），行情页换好品种后认领（读后即删）：
 * 240 ms 后升半页、展开那张卡并亮 1.2 秒。放太久（换页卡住、人又点了别处）就作废。
 */
import { normKey } from '../../chart/symbolKey'
import type { Focus } from './highlightsSheet'

export type IntentFocus = Focus | { kind: 'none' }
const TTL_MS = 5_000
let pending: { symbol: string; focus: IntentFocus; at: number } | null = null

export function setHighlightIntent(symbol: string, focus: IntentFocus, now = Date.now()): void {
  pending = { symbol: normKey(symbol), focus, at: now }
}

/** 认领：只认同一只、没过期的 */
export function takeHighlightIntent(symbol: string, now = Date.now()): IntentFocus | null {
  const p = pending
  if (!p) return null
  if (now - p.at > TTL_MS) { pending = null; return null }
  if (p.symbol !== normKey(symbol)) return null
  pending = null
  return p.focus
}
