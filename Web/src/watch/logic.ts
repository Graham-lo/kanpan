/* Hkline Web · 自选小部件里不碰 DOM 的那几步（拖动排序落点、清空撤销、持仓额格） */

/** 拖动松手：在「画出来的那份」（含空格取消后淡着留下的那一行）上按落点挪，再丢掉已不在自选里的。
 *  落点那一行可能是淡行（不在自选里），也可能拖动途中同步把别的行删了、加了：
 *  按画出来的相对位置算，不会因为落点不在自选里就把它甩到最后。
 *  返回新的自选顺序；挪不了（被拖的那只已不在自选里、落点已不在画面上）返回 null。 */
export function reorderWatch(list: readonly string[], rendered: readonly string[], moved: string, target: string, below: boolean): string[] | null {
  if (moved === target || !list.includes(moved)) return null
  const r = rendered.filter(k => k !== moved)
  let i = r.indexOf(target)
  if (i < 0) return null
  if (below) i++
  r.splice(i, 0, moved)
  const keep = new Set(list)
  const out = r.filter(k => keep.has(k))
  // 画完之后才同步进来的（画面上没有）：按它在自选里的位置插回
  list.forEach((k, at) => { if (!out.includes(k)) out.splice(Math.min(at, out.length), 0, k) })
  return out
}

/** 清空后 ⌘Z：清空前那份原样回来，清空之后新加的（别处同步进来、或搜索刚加的）接在后面，不被覆盖掉 */
export function undoClear(before: readonly string[], now: readonly string[]): string[] {
  const out = [...before]
  for (const k of now) if (!out.includes(k)) out.push(k)
  return out
}

/** 持仓量缓存一格：oi 是合约张数（币安 openInterest）；
 *  undefined = 还没取到（取失败、限流），null = 币安回了 0（没有这只永续的持仓）。
 *  持仓额在画的时候用当时的最新价乘：取数那一刻没有价格时不会被当成「没有永续」。 */
export interface OiEntry { oi: number | null | undefined; t: number }

export function oiShown(e: OiEntry | undefined, price: number | null | undefined): { value: number | null; noPerp: boolean } {
  if (!e || e.oi === undefined) return { value: null, noPerp: false }
  if (e.oi === null) return { value: null, noPerp: true }
  return price && price > 0 && Number.isFinite(price) ? { value: e.oi * price, noPerp: false } : { value: null, noPerp: false }
}

/** 币安回的 openInterest 字段 → 缓存里的张数 */
export function oiFromResponse(raw: string | number | undefined): number | null | undefined {
  const n = Number(raw)
  if (raw === undefined || raw === '' || !Number.isFinite(n)) return undefined
  return n > 0 ? n : null
}
