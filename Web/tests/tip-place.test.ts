// 悬停提示摆位（2026-10-10 审查 C4）：不盖目标、首选边放不下就翻面、夹进视口
import { describe, expect, it } from 'vitest'
import { pickSide, placeTip, type TipRect } from '../src/ui/tipPlace'

const rect = (left: number, top: number, width: number, height: number): TipRect => ({ left, top, width, height, right: left + width, bottom: top + height })
const VW = 2560, VH = 1440
const overlaps = (r: TipRect, x: number, y: number, w: number, h: number): boolean => x < r.right && x + w > r.left && y < r.bottom && y + h > r.top

describe('placeTip', () => {
  it('主力订单流面板的一行（贴屏幕右缘）：提示出在行左侧、竖直居中，不盖本行开关、不压上下两行', () => {
    const row = rect(2200, 300, 300, 36), next = rect(2200, 336, 300, 36), prev = rect(2200, 264, 300, 36)
    const p = placeTip(row, 260, 24, 'left', VW, VH)
    expect(p.side).toBe('left')
    expect(p.x + 260).toBeLessThanOrEqual(row.left - 8)
    expect(p.y).toBe(306)
    for (const r of [row, next, prev]) expect(overlaps(r, p.x, p.y, 260, 24)).toBe(false)
  })

  it('左边放不下就翻到右边；左右都放不下改到下方', () => {
    expect(placeTip(rect(20, 300, 40, 38), 200, 24, 'left', VW, VH).side).toBe('right')
    expect(pickSide(rect(100, 300, 2360, 38), 200, 24, 'left', VW, VH)).toBe('bottom')
  })

  it('顶栏右侧按钮：出在按钮下方水平居中，不横着挡相邻按钮；靠右缘时夹进视口仍在下方', () => {
    const theme = rect(2468, 8, 32, 32), bell = rect(2432, 8, 32, 32), avatar = rect(2508, 8, 32, 32)
    const p = placeTip(theme, 80, 24, 'bottom', VW, VH)
    expect(p.side).toBe('bottom')
    expect(p.y).toBe(48)
    expect(p.x + 40).toBe(2484)
    for (const r of [theme, bell, avatar]) expect(overlaps(r, p.x, p.y, 80, 24)).toBe(false)
    const q = placeTip(avatar, 120, 24, 'bottom', VW, VH)
    expect(q.x + 120).toBeLessThanOrEqual(VW - 8)
    expect(q.y).toBe(48)
  })

  it('不给方向时默认下方；下方放不下翻到上方', () => {
    expect(placeTip(rect(500, 500, 40, 30), 100, 24, undefined, VW, VH).side).toBe('bottom')
    const p = placeTip(rect(500, 1400, 40, 30), 100, 24, undefined, VW, VH)
    expect(p.side).toBe('top')
    expect(p.y).toBe(1400 - 8 - 24)
  })

  it('左右两侧的提示竖直方向夹进视口', () => {
    const p = placeTip(rect(0, 2, 52, 38), 200, 60, 'right', VW, VH)
    expect(p.side).toBe('right')
    expect(p.y).toBe(8)
  })
})
