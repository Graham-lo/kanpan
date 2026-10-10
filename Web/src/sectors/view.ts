/* Hkline Web · 板块页展示层的纯函数（不碰 DOM）：强弱条、成分表排序、排序偏好
 *
 * 2026-10-10 板块页按定稿原型（docs/prototypes/web-layout-2026-10-10.html 第 5 节）重排：
 *   · 左表涨跌幅后面跟一根 72×4 的强弱条，中线为 0，涨向右、跌向左，长度按本表最大绝对涨跌幅归一；
 *   · 右表栏头一排「涨跌幅 / 成交额 / 持仓变化」，点哪个按哪列降序，只记本机。
 */

/** 本表强弱条的满格：有限涨跌幅里绝对值最大的那个；一个都没有（或全是 0）给 0 */
export function barScale(pcts: Iterable<number>): number {
  let m = 0
  for (const p of pcts) if (Number.isFinite(p) && Math.abs(p) > m) m = Math.abs(p)
  return m
}

export interface StrengthBar { left: number; width: number; dir: 'up' | 'down' | '' }
/** 一根强弱条：left / width 是占整根轨道的百分比（中线 50）。涨从中线往右、跌从中线往左，
 *  半根轨道 = 本表最大绝对涨跌幅；非数、0、满格为 0 时不画（宽 0） */
export function strengthBar(pct: number, scale: number): StrengthBar {
  if (!Number.isFinite(pct) || pct === 0 || !(scale > 0)) return { left: 50, width: 0, dir: '' }
  const half = Math.round(Math.min(1, Math.abs(pct) / scale) * 500) / 10
  return pct > 0 ? { left: 50, width: half, dir: 'up' } : { left: Math.round((50 - half) * 10) / 10, width: half, dir: 'down' }
}

export type MemberSort = 'pct' | 'vol' | 'oi'
export const MEMBER_SORTS: readonly (readonly [MemberSort, string])[] = [['pct', '涨跌幅'], ['vol', '成交额'], ['oi', '持仓变化']]
/** 排序偏好只记本机（不随账号同步）：读到认不得的值一律回到涨跌幅 */
export const SORT_KEY = 'hkline-web-sector-sort-v1'
export function parseSort(raw: string | null | undefined): MemberSort {
  return raw === 'vol' || raw === 'oi' ? raw : 'pct'
}

export interface SortableRow { base: string; pct: number; quoteVolume: number }
/** 成分表排序：按选中那一列降序；缺数（非数 / 取不到）沉底；并列按代号。不改原数组 */
export function sortMembers<T extends SortableRow>(rows: readonly T[], key: MemberSort, oiOf: (r: T) => number | null | undefined = () => null): T[] {
  const val = (r: T): number => {
    const v = key === 'pct' ? r.pct : key === 'vol' ? r.quoteVolume : oiOf(r)
    return v != null && Number.isFinite(v) ? v : -Infinity
  }
  return rows.slice().sort((a, b) => {
    const x = val(a), y = val(b)
    return x === y ? (a.base < b.base ? -1 : a.base > b.base ? 1 : 0) : y > x ? 1 : -1
  })
}

/** 资金费率（小数）→「0.0100%」；没有写「—」（和图表页详情块同一写法） */
export function fundingText(fr: number | null | undefined): string {
  return fr == null || !Number.isFinite(fr) ? '—' : (fr * 100).toFixed(4) + '%'
}
