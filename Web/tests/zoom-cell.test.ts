/* P3-2：多图里放大一格（同 TradingView「最大化」）——切换规则、双击标题区判定、网格收成一格且别的格子只藏不删 */
import { describe, expect, it } from 'vitest'
import { applyGrid, inZoomStrip, nextZoom, ZOOM_STRIP_H } from '../src/pages/chartLayout'

/** 只带 applyGrid 放大分支用到的字段的假元素 */
function el() {
  const cls = new Set<string>()
  return {
    style: {} as Record<string, string>,
    classList: { toggle: (k: string, on: boolean) => { if (on) cls.add(k); else cls.delete(k) }, contains: (k: string) => cls.has(k) },
  }
}

describe('放大这一格', () => {
  it('切换：放大 → 再点同一格还原；放大着点别的格 = 换成那一格；null（Esc）还原；只有一格不放大', () => {
    expect(nextZoom(null, 'a', 16)).toBe('a')
    expect(nextZoom('a', 'a', 16)).toBeNull()
    expect(nextZoom('a', 'b', 16)).toBe('b')
    expect(nextZoom('a', null, 16)).toBeNull()
    expect(nextZoom(null, 'a', 1)).toBeNull()
  })
  it('双击标题区：画布顶部一条、价格轴以左才算；往下、在价格轴上都不算', () => {
    expect(inZoomStrip(100, 10, 400)).toBe(true)
    expect(inZoomStrip(100, ZOOM_STRIP_H, 400)).toBe(true)
    expect(inZoomStrip(100, ZOOM_STRIP_H + 1, 400)).toBe(false)
    expect(inZoomStrip(420, 10, 400)).toBe(false)
  })
  it('网格收成一格：放大的那格带 zoomed、其余只是藏起来（元素都还在），布局存档不碰', () => {
    const area = el(), cells = Array.from({ length: 16 }, el)
    applyGrid(area as unknown as HTMLElement, '16', cells as unknown as HTMLElement[], cells[5] as unknown as HTMLElement)
    expect(area.classList.contains('zoomed')).toBe(true)
    expect(area.style.gridTemplateColumns).toBe('minmax(0, 1fr)')
    expect(area.style.gridTemplateRows).toBe('minmax(0, 1fr)')
    expect(cells.filter(c => c.classList.contains('zoomed'))).toEqual([cells[5]])
    expect(cells).toHaveLength(16)
  })
})
