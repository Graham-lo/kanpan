/* 手机网页版 · 搜索页的「对比模式」判定（照 iOS Symbols/CompareSearchMode.swift，2026-10-05）
 *
 * 对比原来是「分析」面板里的一节：「添加对比」开一张挑品种的小表、挑完就关；要加三只得开三趟。
 * 现在入口是行情页顶栏那颗加号，开的就是搜索页本身，只是换了一副行尾：
 *   - 页顶一条「正在对比」，把集合里的（最多三只）摆成小块，每块一个 × 直接拿掉；
 *   - 每一行行尾一颗 ＋，点了加进集合、页面不关；已经在集合里的那一行是选中态，再点一下拿掉；
 *     满三只时别的行的 ＋ 退成禁用色，点了说一句「最多对比 3 个品种」；
 *   - 主图那只自己那一行整行禁用；
 *   - 排序与普通搜索一模一样，但不记搜索历史、不换主图。
 * 这里只是纯判定（可测）：集合本身仍是 st.compareSymbols（规范键 venue/market/SYMBOL），由宿主经 cleanCompare + save 落盘同步。
 */
import { syncKeyOf } from '../../market/macro'
import { compareSymbolOf } from '../chart/compare.source'
import { MAX_COMPARE } from '../app/prefs'

export type CompareRowState = 'add' | 'added' | 'full' | 'main'
export type CompareAction = { kind: 'add'; key: string } | { kind: 'remove'; key: string } | { kind: 'rejectFull' } | { kind: 'none' }

/** 满了时那一句（顶栏加号、行尾 ＋ 共用） */
export const COMPARE_FULL_NOTICE = `最多对比 ${MAX_COMPARE} 个品种`

/** 裸代号或规范键 → 规范键（DXY ↔ macro/index/DXY，其余 binance/usd_m/<代号>）；认不出的回 null */
export function compareKeyOf(symbolOrKey: string): string | null {
  const sym = compareSymbolOf(symbolOrKey)
  return sym ? syncKeyOf(sym) : null
}

export class CompareSearchMode {
  /** 持久集合里认得出的几只（规范键，按加入顺序） */
  readonly keys: string[]
  /** 主图那只（规范键） */
  readonly current: string
  constructor(keys: readonly string[], current: string) {
    this.keys = keys.map(k => compareKeyOf(k)).filter((k): k is string => !!k)
    this.current = compareKeyOf(current) ?? current
  }
  /** 满三只了没有（按持久集合数） */
  get isFull(): boolean { return this.keys.length >= MAX_COMPARE }

  state(symbol: string): CompareRowState {
    const key = compareKeyOf(symbol)
    if (!key) return 'main' // 认不出的代号当不可点（不会出现在搜索结果里）
    if (key === this.current) return 'main'
    if (this.keys.includes(key)) return 'added'
    return this.isFull ? 'full' : 'add'
  }

  action(symbol: string): CompareAction {
    const key = compareKeyOf(symbol)
    switch (this.state(symbol)) {
      case 'add': return { kind: 'add', key: key! }
      case 'added': return { kind: 'remove', key: key! }
      case 'full': return { kind: 'rejectFull' }
      default: return { kind: 'none' }
    }
  }

  /** 照 action 改出来的新集合（不改的原样返回） */
  apply(a: CompareAction): string[] {
    if (a.kind === 'add') return [...this.keys, a.key].slice(0, MAX_COMPARE)
    if (a.kind === 'remove') return this.keys.filter(k => k !== a.key)
    return [...this.keys]
  }
}
