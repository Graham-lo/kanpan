/* Hkline Web · 侧栏「自选」视图的高度分配（纯逻辑）
 *
 * 2560×1440 下整条侧栏（顶栏以下的全部高度）一屏放下、不出滚动条：
 *   自选 ≥ 8 行（行高 32）、详情约 230、盘口「交易所 × 产品」表 + 8 档、成交 10 行、大单 6 行、提醒余下；
 *   24 小时流动性 / 成交两块定高 120。
 * 每块都能收起（收起只剩标题行），收起省下来的高度：先保证展开的各块到最小，再平均分给能长的块。
 * 实在放不下就按优先级从低到高往 floor 压（提醒 → 大单 → 盘口档数 → 两块统计的图 → 成交 → 自选），详情不压。
 * 八块全开（2560×1440 侧栏 1384）时放得下：自选 7 行、盘口 4 档、成交 8 行、大单 3 行、提醒 1 行，统计图 72 高；
 * 侧栏窄（< DETAIL_2COL_BELOW）时详情十二格改两列、高 +48，自选再让到 5 行，仍然一屏放下。
 * 以前成交排在盘口前面先压、floor 只有 5 行，八块全开时成交流被挤成 5 行而盘口还留着整 8 档（2026-09-29 压测）。
 * 再小的屏连 floor 都放不下时侧栏整条可以滚（orderflow.css），不再把下面几块直接裁掉看不见。
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
export const DETAIL_H = 252
export const DETAIL_HEAD = 52
/** 侧栏比这窄时详情十二格改成两列（三列每格只剩 85–100 px，「下次结算 07:59:59」「标记价 83,103.6」都会被截成省略号） */
export const DETAIL_2COL_BELOW = 400
/** 两列时详情的高：多两行 × (22 + 2) */
export const DETAIL_H_2COL = DETAIL_H + 48
/** 24 小时流动性 / 成交两块的高（含标题行） */
export const STAT_H = 120

/** 各块的尺寸（和 orderflow.css / app.css 里的行高一一对应） */
export const PARTS: Record<WidgetId, PartSpec> = {
  watch: { head: WATCH_HEAD + SEP, min: SEP + WATCH_HEAD + WATCH_THEAD + 8 * WATCH_ROW, floor: SEP + WATCH_HEAD + WATCH_THEAD + 5 * WATCH_ROW, shrink: 5 },
  detail: { head: DETAIL_HEAD + SEP, min: DETAIL_H + SEP, floor: DETAIL_H + SEP, fixed: true, shrink: 9 },
  // 盘口：标题 32 + 压力 44 + 交易所表 94 + 分档表头 20 + 8 档 × 17 + 底 4
  book: { head: WIDGET_HEAD + SEP, min: SEP + WIDGET_HEAD + 44 + 94 + 20 + 8 * BOOK_ROW + 4, floor: SEP + WIDGET_HEAD + 44 + 94 + 20 + 4 * BOOK_ROW + 4, shrink: 2 },
  tape: { head: WIDGET_HEAD + SEP, min: SEP + WIDGET_HEAD + 10 * TAPE_ROW + 4, floor: SEP + WIDGET_HEAD + 8 * TAPE_ROW + 4, shrink: 4 },
  walls: { head: WIDGET_HEAD + SEP, min: SEP + WIDGET_HEAD + 6 * WALL_ROW + 4, floor: SEP + WIDGET_HEAD + 3 * WALL_ROW + 4, shrink: 1 },
  // 24 小时流动性 / 成交：定高 120（标题 32 + 图 88），不参与分多出来的高度
  // 挤不下时图可以从 88 压到 72（画布跟着宿主高重画）
  liq: { head: WIDGET_HEAD + SEP, min: SEP + STAT_H, floor: SEP + STAT_H - 16, fixed: true, shrink: 3 },
  vol: { head: WIDGET_HEAD + SEP, min: SEP + STAT_H, floor: SEP + STAT_H - 16, fixed: true, shrink: 3 },
  alerts: { head: WIDGET_HEAD + SEP, min: SEP + WIDGET_HEAD + 2 * ALERT_ROW + 4, floor: SEP + WIDGET_HEAD + ALERT_ROW + 4, shrink: 0 },
}

/** 按侧栏宽取尺寸表：窄侧栏的详情是两列、更高 */
export function partsFor(width: number): Record<WidgetId, PartSpec> {
  if (!(width > 0) || width >= DETAIL_2COL_BELOW) return PARTS
  return { ...PARTS, detail: { ...PARTS.detail, min: DETAIL_H_2COL + SEP, floor: DETAIL_H_2COL + SEP } }
}

/**
 * 按顺序给每块定高度。avail = 侧栏内容区高；collapsed = 收起的块。
 * 返回与 ids 同序的整数高度；展开的块能长时总和恰好等于 avail（放不下时可能超出，由外层裁掉）。
 */
export function planSidebar(avail: number, ids: readonly WidgetId[], collapsed: ReadonlySet<string>, parts: Record<string, PartSpec> = PARTS, user?: Readonly<Record<string, number>> | null): number[] {
  const spec = ids.map(id => parts[id])
  const open = ids.map((id, i) => !!spec[i] && !collapsed.has(id))
  if (user && ids.some((id, i) => open[i] && !spec[i].fixed && typeof user[id] === 'number')) return planUser(avail, ids, spec, open, user)
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

/**
 * 用户拖过分隔线之后的分配：展开的非定高块先取用户拖出来的高（没拖过的取 min），
 * 再把多出 / 缺的高度按各块现有高度的比例摊给它们（缺的时候不低于 floor）——
 * 所以收起一块、窗口变高变矮，总高都正好铺满，块与块之间的比例保持用户拖的样子。
 */
function planUser(avail: number, ids: readonly WidgetId[], spec: PartSpec[], open: boolean[], user: Readonly<Record<string, number>>): number[] {
  const h = ids.map((id, i) => {
    if (!spec[i]) return 0
    if (!open[i]) return spec[i].head
    if (spec[i].fixed) return spec[i].min
    const u = user[id]
    return typeof u === 'number' && isFinite(u) ? Math.max(spec[i].floor, u) : spec[i].min
  })
  const grow = ids.map((_, i) => i).filter(i => open[i] && !spec[i].fixed)
  if (!grow.length) return h.map(Math.round)
  // 按比例伸缩，碰到 floor 的钉住再把剩下的差额摊给其余几块（最多几轮）
  let free = grow.slice()
  for (let round = 0; round < 4 && free.length; round++) {
    const left = avail - h.reduce((a, b) => a + b, 0)
    if (Math.abs(left) < 0.5) break
    const base = free.reduce((a, i) => a + h[i], 0)
    if (base <= 0) break
    const k = (base + left) / base
    const pinned: number[] = []
    for (const i of free) { const v = h[i] * k; if (v < spec[i].floor) { h[i] = spec[i].floor; pinned.push(i) } else h[i] = v }
    if (!pinned.length) break
    free = free.filter(i => !pinned.includes(i))
  }
  // 取整：差额补给最后一块能长的
  const out = h.map(Math.round)
  const diff = avail - out.reduce((a, b) => a + b, 0)
  const last = grow[grow.length - 1]
  if (diff && out[last] + diff >= spec[last].floor) out[last] += diff
  return out
}

/**
 * 拖第 k 块与第 k+1 块之间的线 dy：只在线上下最近的两块「展开、非定高」的块之间挪高度，
 * 夹在中间的定高块（详情）跟着走、自己高度不变。返回新高度；两边找不到能挪的块就原样返回。
 */
export function dragSidebar(hs: readonly number[], ids: readonly WidgetId[], collapsed: ReadonlySet<string>, k: number, dy: number, parts: Record<string, PartSpec> = PARTS): number[] {
  const out = hs.slice()
  const ok = (i: number): boolean => !!parts[ids[i]] && !collapsed.has(ids[i]) && !parts[ids[i]].fixed
  let a = k; while (a >= 0 && !ok(a)) a--
  let b = k + 1; while (b < ids.length && !ok(b)) b++
  if (a < 0 || b >= ids.length) return out
  const fa = parts[ids[a]].floor, fb = parts[ids[b]].floor, sum = hs[a] + hs[b]
  const na = Math.round(Math.min(Math.max(hs[a] + dy, fa), sum - fb))
  if (na < fa || sum - na < fb) return out
  out[a] = na; out[b] = sum - na
  return out
}
/** 第 k 条线能不能拖（上下都有能挪的块） */
export function sideCanDrag(ids: readonly WidgetId[], collapsed: ReadonlySet<string>, k: number, parts: Record<string, PartSpec> = PARTS): boolean {
  const ok = (i: number): boolean => !!parts[ids[i]] && !collapsed.has(ids[i]) && !parts[ids[i]].fixed
  let a = k; while (a >= 0 && !ok(a)) a--
  let b = k + 1; while (b < ids.length && !ok(b)) b++
  return a >= 0 && b < ids.length
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
