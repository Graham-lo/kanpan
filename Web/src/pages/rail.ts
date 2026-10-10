/* Hkline Web · 右侧栏（图标竖条）点了之后怎么变（纯函数，tests/rail-side.test.ts）
 *
 * 2026-10-10 用户定版（docs/prototypes/web-layout-2026-10-10.html §3，审查 A2 / C3）：
 *   · 「自选」那一颗开 / 关自选栏（自选列表 + 详情卡），这一栏是侧栏唯一的常驻内容；
 *   · 主力订单流 / 提醒 / 笔记 / 成交 四颗点出弹层（摆在竖条左边，盖在图上），不再把自选栏顶掉、也不挤 K 线；
 *     同一颗再点一下收起，点另一颗换成另一块，点外面 / Esc 收起（ui/overlay.ts popover）。 */
import type { PanelId } from '../app/store'

export type PopId = Exclude<PanelId, 'watch'>
export const RAIL: readonly (readonly [PanelId, string, string])[] = [['watch', 'list', '自选'], ['alerts', 'bell', '提醒'], ['flow', 'flow', '主力订单流'], ['notes', 'note', '笔记'], ['trades', 'trades', '成交']]
/** 弹层宽跟视口走（2026-10-10 用户：不同屏幕 / 分辨率不写死）：视口宽 × 比例，夹在 [min, max]。
 *  开关类（订单流）2560 上 320、列表类 2560 上 358；1440 上分别落到 300 / 320 */
export const POP_W: Record<PopId, { k: number; min: number; max: number }> = {
  flow: { k: 0.125, min: 300, max: 380 },
  alerts: { k: 0.14, min: 320, max: 440 }, notes: { k: 0.14, min: 320, max: 440 }, trades: { k: 0.14, min: 320, max: 440 },
}
/** 这块弹层在宽 vw 的视口里多宽（再窄也不超过视口减两边各 8） */
export function popW(id: PopId, vw: number): number {
  const s = POP_W[id]
  return Math.max(0, Math.min(Math.round(Math.min(s.max, Math.max(s.min, vw * s.k))), vw - 16))
}

export interface RailState { side: boolean; pop: PopId | null }

/** 点了一颗之后：自选那颗只管栏的开关（弹层不动）；其余四颗开 / 换 / 收弹层（栏不动） */
export function railNext(s: RailState, clicked: PanelId): RailState {
  if (clicked === 'watch') return { side: !s.side, pop: s.pop }
  return { side: s.side, pop: s.pop === clicked ? null : clicked }
}

/** 存档里的 panel 可能还是老版本（或别的电脑上的老页面）记的 flow / alerts……：一律当「栏开着」 */
export const sidePanelOf = (p: PanelId | null): 'watch' | null => p ? 'watch' : null
