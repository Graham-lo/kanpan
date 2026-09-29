/* Hkline Web · 侧栏「自选」视图的高度分配（纯逻辑）
 *
 * 2560×1440 下整条侧栏（顶栏以下的全部高度）一屏放下、不出滚动条：
 *   自选 ≥ 8 行（行高 32）、详情约 230、盘口「交易所 × 产品」表 + 8 档、成交 10 行、大单 6 行、提醒余下。
 * 每块都能收起（收起只剩标题行），收起省下来的高度：先保证展开的各块到最小，再平均分给能长的块。
 * 实在放不下（小屏）就按优先级从低到高往 floor 压（提醒 → 大单 → 成交 → 自选 → 盘口），详情是定高不压。
 */
import type { WidgetId } from '../app/store'

export interface PartSpec {
  /** 收起时的高度（标题行） */
  head: number
  /** 展开时至少要的高度 */
  min: number
  /** 挤不下时最多压到这么高（≤ min） */
  floor: number
  /** 定高：不参与分多出来的高度 */
  fixed?: boolean
  /** 挤不下时先压谁：数字小的先压 */
  shrink: number
}

/** 每块之间一道 1 px 分隔线，算在块自己的高度里（border-top） */
export const SEP = 1
/** 行高 */
export const WATCH_ROW = 32
export const WATCH_HEAD = 36
export const WATCH_THEAD = 24
export const WIDGET_HEAD = 32
export const TAPE_ROW = 20
export const WALL_ROW = 24
export const BOOK_ROW = 17
export const ALERT_ROW = 26
export const DETAIL_H = 232
export const DETAIL_HEAD = 52

/** 各块的尺寸（和 orderflow.css / app.css 里的行高一一对应） */
export const PARTS: Record<WidgetId, PartSpec> = {
  watch: { head: WATCH_HEAD + SEP, min: SEP + WATCH_HEAD + WATCH_THEAD + 8 * WATCH_ROW, floor: SEP + WATCH_HEAD + WATCH_THEAD + 4 * WATCH_ROW, shrink: 3 },
  detail: { head: DETAIL_HEAD + SEP, min: DETAIL_H + SEP, floor: DETAIL_H + SEP, fixed: true, shrink: 9 },
  // 盘口：标题 32 + 压力 44 + 交易所表 94 + 分档表头 20 + 8 档 × 17 + 底 4
  book: { head: WIDGET_HEAD + SEP, min: SEP + WIDGET_HEAD + 44 + 94 + 20 + 8 * BOOK_ROW + 4, floor: SEP + WIDGET_HEAD + 44 + 94 + 20 + 4 * BOOK_ROW + 4, shrink: 4 },
  tape: { head: WIDGET_HEAD + SEP, min: SEP + WIDGET_HEAD + 10 * TAPE_ROW + 4, floor: SEP + WIDGET_HEAD + 5 * TAPE_ROW + 4, shrink: 2 },
  walls: { head: WIDGET_HEAD + SEP, min: SEP + WIDGET_HEAD + 6 * WALL_ROW + 4, floor: SEP + WIDGET_HEAD + 3 * WALL_ROW + 4, shrink: 1 },
  alerts: { head: WIDGET_HEAD + SEP, min: SEP + WIDGET_HEAD + 2 * ALERT_ROW + 4, floor: SEP + WIDGET_HEAD + ALERT_ROW + 4, shrink: 0 },
}

/**
 * 按顺序给每块定高度。avail = 侧栏内容区高；collapsed = 收起的块。
 * 返回与 ids 同序的整数高度；展开的块能长时总和恰好等于 avail（放不下时可能超出，由外层裁掉）。
 */
export function planSidebar(avail: number, ids: readonly WidgetId[], collapsed: ReadonlySet<string>, parts: Record<string, PartSpec> = PARTS): number[] {
  const spec = ids.map(id => parts[id])
  const open = ids.map((id, i) => !!spec[i] && !collapsed.has(id))
  const h = ids.map((_, i) => (spec[i] ? (open[i] ? spec[i].min : spec[i].head) : 0))
  let left = avail - h.reduce((a, b) => a + b, 0)
  if (left < 0) {
    // 挤不下：按 shrink 从小到大往 floor 压
    const order = ids.map((_, i) => i).filter(i => open[i]).sort((a, b) => spec[a].shrink - spec[b].shrink)
    for (const i of order) {
      if (left >= 0) break
      const give = Math.min(h[i] - spec[i].floor, -left)
      h[i] -= give; left += give
    }
    return h
  }
  const grow = ids.map((_, i) => i).filter(i => open[i] && !spec[i].fixed)
  if (!grow.length || left === 0) return h
  const each = Math.floor(left / grow.length)
  let rest = left - each * grow.length
  for (const i of grow) { h[i] += each; if (rest > 0) { h[i] += 1; rest-- } }
  return h
}

/** 一块的正文能放几行（扣掉标题行、分隔线和底边） */
export function rowsThatFit(height: number, head: number, row: number, pad = 4): number {
  return Math.max(0, Math.floor((height - head - SEP - pad) / row))
}

/** 收起 / 展开（本机偏好，存 OF.prefs.collapsed） */
export function toggleCollapsed(list: string[], w: string): string[] {
  const i = list.indexOf(w)
  if (i >= 0) list.splice(i, 1); else list.push(w)
  return list
}
