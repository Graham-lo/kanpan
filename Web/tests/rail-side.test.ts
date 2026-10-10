// 右竖条（2026-10-10 定版原型 §3，审查 A2 / C3）：自选那颗只开关自选栏；订单流 / 提醒 / 笔记 / 成交点出弹层，不顶掉自选、不挤 K 线
import { describe, expect, it } from 'vitest'
import { RAIL, POP_W, popW, railNext, sidePanelOf, type RailState } from '../src/pages/rail'
import { popPlace } from '../src/ui/overlay'

describe('竖条点了之后', () => {
  const open: RailState = { side: true, pop: null }
  it('自选：只开关栏，弹层不动', () => {
    expect(railNext(open, 'watch')).toEqual({ side: false, pop: null })
    expect(railNext({ side: false, pop: 'flow' }, 'watch')).toEqual({ side: true, pop: 'flow' })
  })
  it('其余四颗：开弹层 → 同一颗再点收起 → 点另一颗换过去；自选栏始终不变', () => {
    const a = railNext(open, 'flow'); expect(a).toEqual({ side: true, pop: 'flow' })
    const b = railNext(a, 'alerts'); expect(b).toEqual({ side: true, pop: 'alerts' })
    expect(railNext(b, 'alerts')).toEqual({ side: true, pop: null })
    for (const p of ['alerts', 'flow', 'notes', 'trades'] as const) expect(railNext(open, p).side).toBe(true)
  })
  it('老存档里的 flow / alerts / notes / trades 一律当「栏开着」，null 还是收起', () => {
    for (const p of ['watch', 'alerts', 'flow', 'notes', 'trades'] as const) expect(sidePanelOf(p)).toBe('watch')
    expect(sidePanelOf(null)).toBeNull()
  })
  it('五颗都在、每颗弹层都有宽', () => {
    expect(RAIL.map(r => r[0])).toEqual(['watch', 'alerts', 'flow', 'notes', 'trades'])
    expect(Object.keys(POP_W).sort()).toEqual(['alerts', 'flow', 'notes', 'trades'])
  })
  it('弹层宽跟视口走、夹在上下限之间；窄到放不下就不超过视口', () => {
    expect([1440, 1920, 2560, 3840].map(v => popW('flow', v))).toEqual([300, 300, 320, 380])
    expect([1440, 1920, 2560, 3840].map(v => popW('alerts', v))).toEqual([320, 320, 358, 440])
    expect(popW('alerts', 300)).toBe(284)
  })
})

describe('弹层摆位：贴在竖条按钮左边、顶对齐，出不了屏', () => {
  it('常规：按钮左边留 8、顶和按钮齐、高到底边为止', () => {
    expect(popPlace({ left: 2500, top: 120, right: 2548 }, 320, 500, 2560, 1440)).toEqual({ x: 2172, y: 120, maxH: 1312 })
  })
  it('内容比剩下的高还高：往上挪，最多贴到上边 8', () => {
    const p = popPlace({ left: 2500, top: 1200, right: 2548 }, 360, 900, 2560, 1440)
    expect(p.y).toBe(1440 - 8 - 900); expect(p.y + p.maxH).toBe(1432)
    const tall = popPlace({ left: 2500, top: 1200, right: 2548 }, 360, 5000, 2560, 1440)
    expect(tall).toEqual({ x: 2132, y: 8, maxH: 1424 })
  })
  it('窄窗：左边不出屏', () => {
    expect(popPlace({ left: 200, top: 50, right: 248 }, 360, 100, 400, 800).x).toBe(8)
  })
})

describe('详情卡：板块标签折行全显，定高跟着自然高放大', async () => {
  const { PARTS, SEP, withDetailHeight } = await import('../src/orderflow/sidebar')
  it('比出厂定高高就照自然高；量不到 / 更矮照旧（原对象）', () => {
    const big = withDetailHeight(PARTS, 330.2)
    expect(big.detail.min).toBe(331 + SEP); expect(big.detail.floor).toBe(331 + SEP); expect(big.detail.fixed).toBe(true)
    expect(big.watch).toBe(PARTS.watch)
    expect(withDetailHeight(PARTS, 0)).toBe(PARTS)
    expect(withDetailHeight(PARTS, 100)).toBe(PARTS)
  })
  it('八块全开、详情按量到的自然高（BTC 400 宽 300、320 宽 348）：2560×1440 侧栏 1384 仍一屏放下，盘口 4 档、成交 8 行、大单 3 行，400 宽自选 ≥ 6 行', async () => {
    const { planSidebar, partsFor, rowsThatFit, WIDGET_HEAD, TAPE_ROW, WALL_ROW, BOOK_ROW, WATCH_HEAD, WATCH_THEAD, WATCH_ROW } = await import('../src/orderflow/sidebar')
    const EIGHT = ['watch', 'detail', 'book', 'tape', 'walls', 'liq', 'vol', 'alerts'] as const
    for (const [w, nat] of [[400, 299], [320, 347]] as const) {
      const parts = withDetailHeight(partsFor(w), nat)
      const h = planSidebar(1384, EIGHT, new Set(), parts)
      expect(h.reduce((a, b) => a + b, 0)).toBe(1384)
      const [watch, detail, book, tape, walls] = h
      expect(detail).toBe(nat + SEP)
      expect(Math.floor((book - SEP - WIDGET_HEAD - 44 - 94 - 20 - 4) / BOOK_ROW)).toBeGreaterThanOrEqual(4)
      expect(rowsThatFit(tape, WIDGET_HEAD, TAPE_ROW)).toBeGreaterThanOrEqual(8)
      expect(rowsThatFit(walls, WIDGET_HEAD, WALL_ROW)).toBeGreaterThanOrEqual(3)
      EIGHT.forEach((id, i) => expect(h[i]).toBeGreaterThanOrEqual(parts[id].floor))
      if (w === 400) expect(Math.floor((watch - SEP - WATCH_HEAD - WATCH_THEAD) / WATCH_ROW)).toBeGreaterThanOrEqual(6)
    }
  })
})

describe('右侧栏出厂宽跟视口走', async () => {
  const { panelDefault, REGIONS, clampSize } = await import('../src/app/sizes')
  it('1440 → 280、1920 → 288、2560 → 320、封顶 400；用户拖过的宽照旧优先', () => {
    expect([1280, 1440, 1920, 2560, 3840, 5120].map(panelDefault)).toEqual([280, 280, 288, 320, 384, 400])
    expect(REGIONS.panel.min).toBe(280)
    expect(clampSize(450, REGIONS.panel)).toBe(450)
  })
})
