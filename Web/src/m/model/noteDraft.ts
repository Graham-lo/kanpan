/* 手机网页版 · 记一笔没记完的那一笔（照 iOS ReviewStore.saveDraft / ReviewDraft.reusable / ReviewChartBridge.beginCapture）
 *
 * iOS 把取景卡上的草稿整份落盘（关卡不丢），下次在同一品种、同一周期上打开记一笔就接着写：
 * 写的话、方向、确认方式、来源、手改过的目标 / 失效都留着，区间换成眼下这一屏，没手改过的价跟着新区间重算。
 * 复盘本里有草稿时多一行「继续未完成的记录」，右上「+」也是接着写。
 *
 * 和 iOS 不同的一处（假设）：iOS 打开过卡就算有草稿，哪怕一个字没写；这里只有真动过东西
 * （方向 / 确认 / 来源离开默认、写了字、手改了价）才留，免得复盘本里挂一行空的「继续」。
 * 手机网页版只有一份草稿；在别的品种上新起一笔、动了东西，才把旧的那份换掉。
 */
import {
  DIRECTION_LABEL, CONFIRMATION_LABEL, ORIGIN_LABEL,
  type Direction, type Confirmation, type Origin,
} from '../../notes/draft'
import { normKey } from '../chart/symbolKey'

export const NOTE_DRAFT_KEY = 'hkline-m-note-draft-v1'

export interface UnfinishedNote {
  symbol: string
  interval: string
  direction: Direction
  confirmation: Confirmation
  origin: Origin
  text: string
  /** 手改过才有意义；没改过的那个打开时按新区间重算 */
  target: string
  invalidation: string
  targetEdited: boolean
  invalidationEdited: boolean
  updated: number
}

const isKey = <T extends string>(labels: Record<T, string>, v: unknown): v is T =>
  typeof v === 'string' && Object.prototype.hasOwnProperty.call(labels, v)
const priceText = (v: unknown): v is string => typeof v === 'string' && v.length <= 32 && /^[\d.]*$/.test(v)

/** 本机存的那份认不认：形状不对一律当没有 */
export function parseUnfinished(raw: unknown): UnfinishedNote | null {
  if (!raw || typeof raw !== 'object') return null
  const o = raw as Record<string, unknown>
  if (typeof o.symbol !== 'string' || !/^[A-Z0-9]{2,30}$/.test(o.symbol)) return null
  if (typeof o.interval !== 'string' || !o.interval) return null
  if (!isKey(DIRECTION_LABEL, o.direction) || !isKey(CONFIRMATION_LABEL, o.confirmation) || !isKey(ORIGIN_LABEL, o.origin)) return null
  if (typeof o.text !== 'string' || !priceText(o.target) || !priceText(o.invalidation)) return null
  return {
    symbol: o.symbol, interval: o.interval,
    direction: o.direction, confirmation: o.confirmation, origin: o.origin,
    text: o.text.slice(0, 2000), target: o.target, invalidation: o.invalidation,
    targetEdited: o.targetEdited === true, invalidationEdited: o.invalidationEdited === true,
    updated: typeof o.updated === 'number' && Number.isFinite(o.updated) ? o.updated : 0,
  }
}

/** 真动过东西才算没记完 */
export const meaningful = (v: Omit<UnfinishedNote, 'updated' | 'symbol' | 'interval'>): boolean =>
  v.direction !== 'observe' || v.confirmation !== 'bar_close' || v.origin !== 'chart_first'
  || v.text.trim() !== '' || v.targetEdited || v.invalidationEdited

/** 这份草稿能不能接在眼下这张图上（同品种、同周期，ReviewDraft.reusable） */
export const reusableFor = (v: UnfinishedNote | null, symbol: string, interval: string): boolean =>
  !!v && v.symbol === normKey(symbol) && v.interval === interval

/**
 * 卡上动了一下之后，本机那份怎么办：
 * - 动过东西 → 存这一份（同一个槽，换掉旧的）
 * - 全退回默认了，而存着的正是这张图上的那份 → 清掉（人自己把它擦干净了）
 * - 全是默认、存着的是别处的 → 别碰（还没开始写这一笔，不能把那边没写完的冲掉）
 */
export function nextStored(saved: UnfinishedNote | null, current: UnfinishedNote): 'save' | 'clear' | 'keep' {
  if (meaningful(current)) return 'save'
  return saved && reusableFor(saved, current.symbol, current.interval) ? 'clear' : 'keep'
}
