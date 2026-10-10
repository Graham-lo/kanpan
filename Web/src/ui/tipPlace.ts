/* Hkline Web · 悬停提示摆在哪（纯函数，tests/tip-place.test.ts）
 *
 * 规则（2026-10-10 审查 C4：提示压住同一行的开关、跑出面板压住下一行、挡住顶栏旁边的铃铛）：
 *   · 提示不盖住目标本身——一律出在目标的外侧，间隔 8；
 *   · 方向由 data-tip-side 定：right / left 贴着目标竖直居中（画线栏、右侧面板的行），bottom / top 水平居中（默认 bottom）；
 *   · 首选那一边放不下（超出视口）就翻到对边；两边都放不下：左右两侧的改到下方 / 上方，上下两侧的取空间大的那边；
 *   · 最后夹进视口（四边各留 8）；选到的那一边放得下时，夹只会沿目标的边挪，不会把提示夹回到目标身上。 */
export type TipSide = 'right' | 'left' | 'bottom' | 'top'
export interface TipRect { left: number; top: number; right: number; bottom: number; width: number; height: number }
export interface TipPos { x: number; y: number; side: TipSide }

const GAP = 8, EDGE = 8
const OPP: Record<TipSide, TipSide> = { right: 'left', left: 'right', bottom: 'top', top: 'bottom' }

/** 这一边能不能完整放下（不越出视口） */
function fits(r: TipRect, tw: number, th: number, side: TipSide, vw: number, vh: number): boolean {
  switch (side) {
    case 'right': return r.right + GAP + tw <= vw - EDGE
    case 'left': return r.left - GAP - tw >= EDGE
    case 'bottom': return r.bottom + GAP + th <= vh - EDGE
    case 'top': return r.top - GAP - th >= EDGE
  }
}

/** 选边：首选 → 对边 → （左右放不下时）下 / 上 → 空间大的那边 */
export function pickSide(r: TipRect, tw: number, th: number, want: TipSide, vw: number, vh: number): TipSide {
  const order: TipSide[] = want === 'left' || want === 'right' ? [want, OPP[want], 'bottom', 'top'] : [want, OPP[want]]
  for (const s of order) if (fits(r, tw, th, s, vw, vh)) return s
  if (want === 'left' || want === 'right') return r.left >= vw - r.right ? 'left' : 'right'
  return r.top >= vh - r.bottom ? 'top' : 'bottom'
}

const clamp = (v: number, lo: number, hi: number): number => Math.max(lo, Math.min(Math.max(lo, hi), v))

/** 提示左上角坐标（视口坐标）与实际用的那一边 */
export function placeTip(r: TipRect, tw: number, th: number, want: TipSide | undefined, vw: number, vh: number): TipPos {
  const side = pickSide(r, tw, th, want ?? 'bottom', vw, vh)
  let x: number, y: number
  if (side === 'right' || side === 'left') {
    x = clamp(side === 'right' ? r.right + GAP : r.left - GAP - tw, EDGE, vw - tw - EDGE)
    y = clamp(r.top + r.height / 2 - th / 2, EDGE, vh - th - EDGE)
  } else {
    y = clamp(side === 'bottom' ? r.bottom + GAP : r.top - GAP - th, EDGE, vh - th - EDGE)
    x = clamp(r.left + r.width / 2 - tw / 2, EDGE, vw - tw - EDGE)
  }
  return { x: Math.round(x), y: Math.round(y), side }
}

export function isTipSide(v: string | undefined): v is TipSide { return v === 'right' || v === 'left' || v === 'bottom' || v === 'top' }
