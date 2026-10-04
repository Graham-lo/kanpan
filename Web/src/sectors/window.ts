/* 板块页「今日 / 5 日」的选择：want 是存在本机的偏好，once 是这一次临时改看的窗口
 * （从图表点进来的板块不在 5 日榜上时先看今日）。once 只活到用户自己点窗口、换市场或离开板块页，
 * 不写进偏好，也不挡住用户再点回偏好的那一档。 */
import type { SectorWindow } from './aggregate'

export interface WindowChoice { want: SectorWindow; once: SectorWindow | null }

export const shownWindow = (c: WindowChoice): SectorWindow => c.once ?? c.want

/** 用户点了某一档：返回新的选择与要不要存偏好；和正在看的一样返回 null */
export function pickWindow(c: WindowChoice, w: SectorWindow): { next: WindowChoice; save: boolean } | null {
  if (w === shownWindow(c)) return null
  return { next: { want: w, once: null }, save: w !== c.want }
}
