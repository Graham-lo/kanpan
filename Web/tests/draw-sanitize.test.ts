/* 画线读档清洗：存档会被老版本、别的标签页、手改写坏——不认识的种类 / 锚点数不对的丢掉，
 * 颜色 / 粗细 / 线型坏了就地换默认（颜色只认 #RGB / #RRGGBB / #RRGGBBAA），好档原样保留、几何不动 */
import { describe, expect, it } from 'vitest'
import type { Drawing } from '../src/chart/chart'
import { ANCHOR_COUNT, DEFAULT_DRAW_COLOR, DEFAULT_DRAW_WIDTH, DRAWING_TYPES, cleanDrawColor, cleanDrawWidth, cleanDrawing } from '../src/chart/drawTools'
import { sanitizeDrawings } from '../src/app/store'

const P = (t: number, p: number) => ({ t, p })
const two = [P(1e12, 100), P(1e12 + 36e5, 110)]
const GOOD: Drawing[] = [
  { id: 'tr', type: 'trend', pts: two, color: '#F23645', width: 2 },
  { id: 'ry', type: 'ray', pts: two, color: '#2962ff', width: 1, dash: 'dashed' },
  { id: 'hl', type: 'hline', pts: [P(1e12, 105)], color: '#089981CC', width: 3, dash: 'dotted', locked: true, alert: true },
  { id: 'vl', type: 'vline', pts: [P(1e12, 105)] },
  { id: 'rc', type: 'rect', pts: two, color: '#FFEB3B', width: 1.5 },
  { id: 'fb', type: 'fib', pts: two, color: '#9C27B0', width: 2 },
  { id: 'ms', type: 'measure', pts: two, color: '#2962FF', width: 1 },
  { id: 'av', type: 'avwap', pts: [P(1e12, 100)], color: '#00BCD4', width: 2 },
  { id: 'fv', type: 'fvp', pts: two, color: '#787B86', width: 2 },
  { id: 'ps', type: 'position', pts: [P(1e12, 100), P(1e12 + 36e5, 110), P(1e12 + 36e5, 95)], width: 2 },
]
const one = (raw: unknown) => sanitizeDrawings({ BTCUSDT: [raw] })

describe('画线读档清洗', () => {
  it('好档原样保留：每种工具、几何与样式一个字不改，不报坏', () => {
    const r = sanitizeDrawings({ BTCUSDT: structuredClone(GOOD) })
    expect(r.damaged).toBe(false)
    expect(r.drawings.BTCUSDT).toEqual(GOOD)
    // 白名单与类型定义一一对应（新加一把工具忘了登记锚点数，这里会少一种）
    expect([...DRAWING_TYPES].sort()).toEqual(GOOD.map(d => d.type).sort())
    for (const d of GOOD) expect(d.pts.length).toBe(ANCHOR_COUNT[d.type])
  })

  it('不认识的画线类型：丢掉并报坏（走 markDrawingsSuspect）', () => {
    const r = sanitizeDrawings({ BTCUSDT: [GOOD[0], { id: 'x', type: 'nosuchtool', pts: two, color: '#2962FF' }] })
    expect(r.damaged).toBe(true)
    expect(r.drawings.BTCUSDT).toEqual([GOOD[0]])
    expect(one({ id: 'y', type: 7, pts: two }).drawings.BTCUSDT).toEqual([])
    expect(one({ id: 'z', type: 'toString', pts: two }).drawings.BTCUSDT).toEqual([])
  })

  it('锚点个数不对：丢掉', () => {
    expect(one({ id: 'a', type: 'hline', pts: two }).drawings.BTCUSDT).toEqual([])
    expect(one({ id: 'b', type: 'trend', pts: [P(1, 1)] }).drawings.BTCUSDT).toEqual([])
    expect(one({ id: 'c', type: 'position', pts: two }).drawings.BTCUSDT).toEqual([])
    expect(one({ id: 'd', type: 'trend', pts: [] }).drawings.BTCUSDT).toEqual([])
    expect(one({ id: 'e', type: 'trend', pts: [P(1, 1), { t: 2, p: null }] }).drawings.BTCUSDT).toEqual([])
    expect(one({ id: 'f', type: 'trend', pts: [P(1, 1), { t: '2', p: 3 }] }).drawings.BTCUSDT).toEqual([])
    expect(one({ id: '', type: 'hline', pts: [P(1, 1)] }).drawings.BTCUSDT).toEqual([])
    expect(one({ type: 'hline', pts: [P(1, 1)] }).damaged).toBe(true)
  })

  it('color 是数字：换成默认色（字符串），几何不动', () => {
    const r = one({ id: 'n', type: 'trend', pts: two, color: 123 })
    expect(r.drawings.BTCUSDT).toEqual([{ id: 'n', type: 'trend', pts: two, color: DEFAULT_DRAW_COLOR }])
  })

  it('color 里带 HTML：换成默认色，不留一个字符', () => {
    const bad = '#fff" onmouseover="window.__xss=1"><img src=x onerror="window.__xss=2">'
    const d = one({ id: 'i', type: 'trend', pts: two, color: bad }).drawings.BTCUSDT[0]
    expect(d.color).toBe(DEFAULT_DRAW_COLOR)
    expect(JSON.stringify(d)).not.toMatch(/onerror|onmouseover|<img/)
  })

  it('color 形状：#RGB 展开成六位，#RRGGBB / #RRGGBBAA 大小写不限原样留，其余换默认', () => {
    expect(cleanDrawColor('#fA0')).toBe('#ffAA00')
    expect(cleanDrawColor('#a1b2c3')).toBe('#a1b2c3')
    expect(cleanDrawColor('#A1B2C3d4')).toBe('#A1B2C3d4')
    for (const c of ['notacolor', 'red', '#12345', '#1234567', 'rgb(1,2,3)', '#GGGGGG', '', ' #FFFFFF', '#FFFFFF;', null, {}, ['#FFF']]) expect(cleanDrawColor(c)).toBe(DEFAULT_DRAW_COLOR)
    expect(one({ id: 's', type: 'hline', pts: [P(1, 1)], color: 'notacolor' }).drawings.BTCUSDT[0].color).toBe(DEFAULT_DRAW_COLOR)
    // 没写颜色 / null：不补一个上去（画法按默认色）
    expect('color' in one({ id: 'u', type: 'hline', pts: [P(1, 1)], color: null }).drawings.BTCUSDT[0]).toBe(false)
  })

  it('width 不合规换默认 2，dash 不认识的去掉（实线），locked / alert 不是布尔的去掉', () => {
    const d = one({ id: 'w', type: 'trend', pts: two, color: '#D500F9', width: 'x', dash: 7, locked: 'yes', alert: 1 }).drawings.BTCUSDT[0]
    expect(d).toEqual({ id: 'w', type: 'trend', pts: two, color: '#D500F9', width: DEFAULT_DRAW_WIDTH })
    for (const w of [0, -1, 7, NaN, Infinity, '2', null, {}]) expect(cleanDrawWidth(w)).toBe(DEFAULT_DRAW_WIDTH)
    for (const w of [0.5, 1, 1.5, 2, 3, 6]) expect(cleanDrawWidth(w)).toBe(w)
    expect(one({ id: 'w2', type: 'trend', pts: two, width: 99 }).drawings.BTCUSDT[0].width).toBe(DEFAULT_DRAW_WIDTH)
    expect('dash' in one({ id: 'w3', type: 'trend', pts: two, dash: 'solid' }).drawings.BTCUSDT[0]).toBe(false)
    expect(one({ id: 'w4', type: 'trend', pts: two, dash: 'dotted' }).drawings.BTCUSDT[0].dash).toBe('dotted')
  })

  it('样式坏了只修不丢：不报坏（没有画线被丢掉，同步不必进只补不删）', () => {
    const r = sanitizeDrawings({ BTCUSDT: [{ id: 'n', type: 'trend', pts: two, color: 123, width: 'x' }] })
    expect(r.damaged).toBe(false)
    expect(r.drawings.BTCUSDT).toHaveLength(1)
  })

  it('非对象条目（null、数字、字符串）丢掉并报坏；cleanDrawing 不改入参', () => {
    const r = sanitizeDrawings({ BTCUSDT: [null, 5, 'str', GOOD[2]] })
    expect(r.damaged).toBe(true)
    expect(r.drawings.BTCUSDT).toEqual([GOOD[2]])
    const raw = { id: 'm', type: 'trend', pts: two, color: 123, width: 'x', dash: 7 }
    const before = JSON.stringify(raw)
    cleanDrawing(raw)
    expect(JSON.stringify(raw)).toBe(before)
  })
})
