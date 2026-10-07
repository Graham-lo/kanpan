/* 手机网页版 · 板块页的两条展示规则（照 iOS SectorPage.snapshot 与 SectorDrillDecision）
 *
 * 1. 页头规模「N 个板块 · M 个品种」里的 M：目录板块与兜底桶的成员去重后，这段窗口上
 *    真算得出收益的那些——不是「挂在板块下、手里有报价」的那些（5 日档缺收盘价的不算）。
 * 2. 已经钻进某个板块、这一帧统计里却找不到它时：只有目录不认、兜底桶里也没有、而且
 *    这一帧确实算出了别的板块，才算「板块没了」退回列表；其余只是行情还没到，留在原地等。
 */
import {
  catalog, windowReturn,
  type Quotes, type SectorBucket, type SectorHistory, type SectorMarket, type SectorStat, type SectorWindow,
} from '../../sectors/aggregate'

export function coveredCount(market: SectorMarket, quotes: Quotes, buckets: SectorBucket[], w: SectorWindow, history: SectorHistory): number {
  const seen = new Set<string>()
  const cover = (members: string[]): void => {
    for (const base of members) {
      const q = quotes.get(base)
      if (!q || windowReturn(q, w, history.closes.get(base)) == null) continue
      seen.add(base)
    }
  }
  for (const d of catalog.sectors(market)) cover(d.members)
  for (const b of buckets) cover(b.members)
  return seen.size
}

export type DrillDecision = 'show' | 'wait' | 'pop'
export function drillDecision(id: string, stats: Pick<SectorStat, 'id'>[], buckets: Pick<SectorBucket, 'id'>[]): DrillDecision {
  if (stats.some(s => s.id === id)) return 'show'
  if (catalog.sector(id) || buckets.some(b => b.id === id)) return 'wait'
  if (!stats.length) return 'wait'
  return 'pop'
}

// ---------------------------------------------------------------- 等行情时的骨架

/** 板块 / 品种行情还在路上时摆几行骨架（一屏大约七行），不是一句「加载中」 */
export const SKELETON_ROWS = 7
/** 骨架里名字那一截的宽度：一行一个样，看着像真的一列名字 */
const SKEL_W = [92, 68, 112, 80, 60, 104, 74, 96]

/**
 * 骨架行。board：板块列表（图标 32 · 名字 + 副行 · 涨跌）；symbol：板块里的品种（徽章 33 · 名字 + 成交额 · 价格 + 药丸）。
 * 只是占位：没有 data-sec / data-sym、不可点、读屏跳过。
 */
export function skeletonRowsHTML(kind: 'board' | 'symbol', n = SKELETON_ROWS): string {
  let html = ''
  for (let i = 0; i < n; i++) {
    const w = SKEL_W[i % SKEL_W.length]
    html += `<div class="sec-skel ${kind}${i === 0 ? ' first' : ''}" aria-hidden="true"><span class="sk-icon"></span>`
      + `<span class="sk-name"><span class="sk-bar" style="width:${w}px"></span><span class="sk-bar sub" style="width:${Math.round(w * 0.6)}px"></span></span>`
      + (kind === 'symbol' ? '<span class="sk-bar price"></span><span class="sk-pill"></span>' : '<span class="sk-bar pct"></span>')
      + `</div>`
  }
  return html
}

/** 板块列表该不该摆骨架：还一个板块都没算出来、也没判定取不到 */
export const boardsWaiting = (boards: number, failed: boolean): boolean => boards === 0 && !failed
/** 钻进去的板块该不该摆骨架：行情一只都还没到 */
export const drillWaiting = (rows: number, quotes: number): boolean => rows === 0 && quotes === 0
