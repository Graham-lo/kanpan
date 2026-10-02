/* 手机网页版 · 长按预览卡的纯逻辑（照 iOS Symbols/SymbolPreviewCard.swift 与 FavoritesView.historyChange）
 *
 * 卡上那段 K 线：1 小时 × 60 根；自选页另取逐分钟走势算「1 小时 / 4 小时」涨跌。
 * 取到的数按品种记着，最多 24 个（翻一页自选也就几十行，多了白占内存），最近用过的在后面。
 */

export interface PreviewBar { t: number; o: number; h: number; l: number; c: number }

/** 卡上 K 线的周期与根数（SymbolPreviewService.interval / barCount） */
export const PREVIEW_IV = '1h'
export const PREVIEW_BARS = 60
/** 算 4 小时涨跌要的逐分钟根数：4 × 60 再多两根兜住「当前这根还没走完」 */
export const PREVIEW_MINUTE_BARS = 242
export const PREVIEW_CAPACITY = 24

/** 近 N 小时涨跌（百分数）：取开盘时刻 ≤ 目标时刻的最后一根 1 分钟 K 线，且离目标不到一分钟，拿它的开盘价比现价。
 *  逐分钟走势对不上（缺根、还没到）就给 null——拿 1 小时线去凑会差出将近一整根，宁可不写 */
export function historyChange(bars: readonly PreviewBar[] | null | undefined, price: number | null | undefined, hours: number, now = Date.now()): number | null {
  if (!bars?.length || price == null || !Number.isFinite(price)) return null
  const target = now - hours * 3_600_000
  let bar: PreviewBar | undefined
  for (let i = bars.length - 1; i >= 0; i--) if (bars[i].t <= target) { bar = bars[i]; break }
  if (!bar || target - bar.t >= 60_000 || !(bar.o > 0)) return null
  return (price / bar.o - 1) * 100
}

export interface CandleGeom { x: number; wickTop: number; wickBottom: number; bodyTop: number; bodyH: number; bodyW: number; up: boolean }
/** 迷你 K 线几何（MiniCandles）：每根占 w / n 宽，实体宽 = 格宽 × 0.62 夹在 1.2…5，影线 1，实体至少 1 高；收 ≥ 开算涨 */
export function miniCandles(bars: readonly PreviewBar[], w: number, h: number): CandleGeom[] {
  if (bars.length < 2 || !(w > 0) || !(h > 0)) return []
  let lo = Infinity, hi = -Infinity
  for (const b of bars) { if (b.l < lo) lo = b.l; if (b.h > hi) hi = b.h }
  if (!(hi > lo) || !Number.isFinite(lo) || !Number.isFinite(hi)) return []
  const slot = w / bars.length
  const body = Math.max(1.2, Math.min(5, slot * 0.62))
  const y = (v: number): number => h - (v - lo) / (hi - lo) * h
  return bars.map((b, i) => {
    const top = y(Math.max(b.o, b.c)), bottom = y(Math.min(b.o, b.c))
    return { x: (i + 0.5) * slot, wickTop: y(b.h), wickBottom: y(b.l), bodyTop: top, bodyH: Math.max(1, bottom - top), bodyW: body, up: b.c >= b.o }
  })
}

/** 「最近用过」表（PreviewRecentKeys）：touch 一个键挪到最后，超出容量从前面扔，返回被扔掉的键 */
export class RecentKeys {
  readonly keys: string[] = []
  constructor(readonly capacity = PREVIEW_CAPACITY) { this.capacity = Math.max(1, capacity) }
  touch(key: string): string[] {
    const i = this.keys.indexOf(key)
    if (i >= 0) this.keys.splice(i, 1)
    this.keys.push(key)
    const over = this.keys.length - this.capacity
    return over > 0 ? this.keys.splice(0, over) : []
  }
}

/** 卡头第二行：「1时 · 近 60 根」 */
export const PREVIEW_SPAN_TEXT = `1时 · 近 ${PREVIEW_BARS} 根`
