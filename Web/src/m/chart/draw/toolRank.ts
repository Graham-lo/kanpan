/* 画线条上露哪几把工具（照 iOS Drawing/DrawingToolRank.swift，2026-10-05）
 *
 * 从前横屏画线台把面板上那十二把（DrawKind.palette）全摆出来，一排挤满还要横着滚，把撤销、更多、完成都挤到边上
 * （用户：「只展示少量常用的，根据用户的使用频率智能展示即可」）。现在条上只露几把，其余一把不少，都在「工具」面板里。
 *
 * 次数记在 Prefs.drawToolUsage（随账号同步，iOS 与手机网页同一张表）：每挑一次 +1（counted）。
 * 总数一过 DECAY_CEILING 就整体减半、减成 0 的删掉——量的是「最近常用」。不给「固定哪几把」的设置。
 */
import { DrawKind, type DrawingKind } from './drawing'

/** 竖屏画线条露几把（手机网页竖屏没有画线条，只为与 iOS 对齐留着） */
export const PORTRAIT_COUNT = 4
/** 横屏画线台那条露几把 */
export const DOCK_COUNT = 5
/** 所有工具次数加起来超过它就整体减半 */
export const DECAY_CEILING = 256

/** 一次都没用过的工具按这个顺序补位：趋势线、水平线、斐波那契、平行通道、测量…… */
export const DEFAULT_ORDER: readonly DrawingKind[] = [
  'trend', 'hline', 'fibonacci', 'channel', 'measure', 'note', 'vline', 'fibExtension',
  'anchoredVWAP', 'fixedVolumeProfile', 'anchoredVolumeProfile', 'position',
]

/** 面板上代表它的那一格：变体归到族首（射线 → 趋势线），本身就在面板上的不变 */
export function toolHead(k: DrawingKind): DrawingKind {
  return DrawKind.paletteHead(k) ?? k
}

/**
 * 条上露哪几把（从左到右）。
 * - 用过的按次数从多到少；次数一样按面板顺序。
 * - 没用过的按 DEFAULT_ORDER 补齐。
 * - held：这一回刚从面板挑的、不在前几把里的那把，顶掉最后一格——手上拿着的工具条上一定看得见。
 */
export function shownTools(usage: Readonly<Record<string, number>>, count: number, held?: DrawingKind | null): DrawingKind[] {
  const palette = DrawKind.palette
  const used = palette
    .map((k, at) => ({ k, n: usage[k] ?? 0, at }))
    .filter(e => Number.isFinite(e.n) && e.n > 0)
    .sort((a, b) => b.n - a.n || a.at - b.at)
    .map(e => e.k)
  const order = [...used]
  for (const k of DEFAULT_ORDER) if (!order.includes(k)) order.push(k)
  for (const k of palette) if (!order.includes(k)) order.push(k)
  const picked = order.slice(0, Math.max(0, count))
  const h = held ? toolHead(held) : null
  if (h && palette.includes(h) && !picked.includes(h) && picked.length) picked[picked.length - 1] = h
  return picked
}

/** 挑了一次 k 之后的次数表（新对象）。变体记在族首名下；不在面板上的不记——表里最多十二个键 */
export function countedTool(usage: Readonly<Record<string, number>>, k: DrawingKind): Record<string, number> {
  const head = toolHead(k)
  if (!DrawKind.palette.includes(head)) return { ...usage }
  let next: Record<string, number> = {}
  for (const [key, n] of Object.entries(usage)) if (n > 0) next[key] = n
  next[head] = (next[head] ?? 0) + 1
  if (Object.values(next).reduce((a, b) => a + b, 0) > DECAY_CEILING) {
    const halved: Record<string, number> = {}
    for (const [key, n] of Object.entries(next)) { const m = Math.floor(n / 2); if (m > 0) halved[key] = m }
    next = halved
  }
  return next
}
