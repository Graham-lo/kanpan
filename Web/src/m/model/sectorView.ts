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
