/* Hkline Web · 电脑版首页的纯逻辑（测试直接测）
 *
 * 四栏折行、榜单默认几行与展开、板块精简榜（强弱条 · 跑赢 / 落后大盘）、涨跌药丸的方向。
 * 异动列表的合并 / 计数 / 筛选 / 点行意图与手机共用 highlights/home.ts，这里不重写。
 */
import { MINUS, signedPct } from '../highlights/format'
import type { SectorStat } from '../sectors/aggregate'

// ───────── 四栏折行 ─────────

/** 2560 宽四栏并排；窄于 1800 板块栏并到持仓栏下方（三栏）；窄于 1300 两栏两行 */
export type HomeCols = 4 | 3 | 2
export const WIDE_MIN = 1800
export const MID_MIN = 1300
export function homeCols(width: number): HomeCols {
  if (!(width > 0)) return 4
  return width >= WIDE_MIN ? 4 : width >= MID_MIN ? 3 : 2
}

// ───────── 涨跌 / 持仓榜 ─────────

/** 每张榜默认至少几行（「全部」展开、「收起」收回） */
export const RANK_ROWS = 8
/** 榜单行高、榜头（标题行 14 + 6 内边距 + 26 高的窗口分段）高，和 styles/home.css 的 .rk-row / .rk-sh 一致 */
export const RANK_ROW_H = 40
export const RANK_HEAD_H = 46

/** 按栏里可用的高度算每张榜默认摆几行：两张榜各占一半，减去榜头，整行向下取整，最少 RANK_ROWS 行
 *  （量不到高度——页面藏着是 0——也按最少行数） */
export function rankRowsFor(bodyHeight: number, boards = 2, min = RANK_ROWS): number {
  if (!(bodyHeight > 0) || boards < 1) return min
  const n = Math.floor((bodyHeight / boards - RANK_HEAD_H) / RANK_ROW_H)
  return Math.max(min, n)
}

/** 这张榜现在摆哪几行，标题行尾的链接写什么（行数不超过默认的不给链接） */
export function rankView<T>(rows: readonly T[], open: boolean, n = RANK_ROWS): { rows: T[]; more: 'all' | 'collapse' | null } {
  if (rows.length <= n) return { rows: [...rows], more: null }
  return open ? { rows: [...rows], more: 'collapse' } : { rows: rows.slice(0, n), more: 'all' }
}

/** 涨跌药丸：写一位小数，颜色跟写出来的号走（舍成 +0.0% 的算涨，不出现「绿底 −0.0%」）；没有数是灰的 */
export function pillOf(pct: number | null | undefined): { text: string; cls: 'up' | 'down' | 'none' } {
  if (pct == null || !Number.isFinite(pct)) return { text: '—', cls: 'none' }
  const text = signedPct(pct)
  return { text, cls: text.startsWith(MINUS) ? 'down' : 'up' }
}

// ───────── 板块精简榜 ─────────

export interface SectorLine {
  id: string; name: string; pct: number
  /** 板块涨跌 − 大盘（百分点）；没有大盘时 null */
  beat: number | null
  /** 强弱条：从中线往左 / 右画，left / width 都是百分比（0–100） */
  bar: { left: number; width: number; up: boolean }
}

/** 精简榜：沿用板块页的顺序（boardOrder）；大盘用板块页同一条基准（sectors/aggregate.ts marketReturn），不到三家有行情的不上（它们不算跑赢大盘）；强弱条按这一屏最大的幅度归一 */
export function sectorLines(ordered: readonly SectorStat[], market: number | null, isThin: (s: SectorStat) => boolean): SectorLine[] {
  const list = ordered.filter(s => !isThin(s) && Number.isFinite(s.pct))
  const max = list.reduce((m, s) => Math.max(m, Math.abs(s.pct)), 0)
  return list.map(s => {
    const w = max > 0 ? (Math.abs(s.pct) / max) * 50 : 0
    return {
      id: s.id, name: s.name, pct: s.pct,
      beat: market == null ? null : s.pct - market,
      bar: { left: s.pct >= 0 ? 50 : 50 - w, width: w, up: s.pct >= 0 },
    }
  })
}

/** 「跑赢 3.9%」/「落后 1.1%」的数（不带号，方向由前面的词说）；舍完是 0 算跑赢 */
export function beatParts(beat: number): { ahead: boolean; v: string } {
  const v = Math.abs(beat).toFixed(1) + '%'
  return { ahead: beat >= 0 || v === '0.0%', v }
}
