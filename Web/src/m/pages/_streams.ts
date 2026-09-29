/* 手机网页版 · 各页共用的取数小工具（market 的 setStreams 是整表替换，这里按页合并）
 *
 * - wantStreams(owner, list, core?)：market/stream.ts 的 setStreams 是「整表替换」，
 *   几页各自调会互相覆盖；这里按 owner 记各自要的流，合并后一次交给 setStreams。
 *   图表页也应改用它（owner = 'chart'），否则它调 setStreams 会把自选 / 板块 / 提醒的订阅冲掉。
 * - ensureUniverse()：全市场表（exchangeInfo + 24hr + premiumIndex）只拉一次，各页共享同一个 promise。
 */
import { S, loadUniverse, setStreams } from '../../market'

const wants = new Map<string, { all: string[]; core: string[] }>()
/** owner 要订的流；list 为空就是撤掉。core：切后台时仍要保住的（提醒监听要保住） */
export function wantStreams(owner: string, list: string[], core: string[] = []): void {
  if (list.length || core.length) wants.set(owner, { all: list, core })
  else wants.delete(owner)
  const all: string[] = [], keep: string[] = []
  for (const w of wants.values()) { all.push(...w.all, ...w.core); keep.push(...w.core) }
  setStreams([...new Set(all)], [...new Set(keep)])
}
export const streamsOf = (owner: string): string[] => wants.get(owner)?.all ?? []

let universeP: Promise<unknown> | null = null
/** 表还没拉就拉一次（失败 30 秒后才允许再拉） */
export function ensureUniverse(): Promise<unknown> {
  if (S.symbols.size && S.live) return Promise.resolve(S.symbols)
  if (universeP) return universeP
  universeP = loadUniverse().finally(() => {
    if (S.live === false) setTimeout(() => { universeP = null }, 30_000)
  })
  return universeP
}
/** 前台回来、表是空的：重拉 */
export function retryUniverse(): Promise<unknown> { universeP = null; return ensureUniverse() }

/** 验收截图用的深链：?open=xxx 命中本页认得的值才读，读完从地址里去掉（模拟器 Safari 里没法点，只能靠地址进到子层） */
export function takeOpenParam(accept: readonly string[]): string | null {
  try {
    const q = new URLSearchParams(location.search)
    const v = q.get('open')
    if (!v || !accept.includes(v)) return null
    q.delete('open')
    const qs = q.toString()
    history.replaceState(history.state, '', location.pathname + (qs ? '?' + qs : '') + location.hash)
    return v
  } catch { return null }
}
