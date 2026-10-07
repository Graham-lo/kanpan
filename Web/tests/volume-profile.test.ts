/* 成交量分布画法（TradingView 样式）：柱子从哪条边长、最长一行多宽、价值区内外明暗、行缝、三种看法、三条横线、底板 */
import { describe, expect, it } from 'vitest'
import { PROFILE, drawProfile, profileLayout, profileRows, type ProfileInput } from '../src/chart/volumeProfile'
import type { Vpvr } from '../src/chart/overlays'

// 价格 100–110 分 10 行，每行 1 块钱；y = 1000 − 价格 × 10（每行 10 px，价格越高 y 越小）
const Y = (p: number) => 1000 - p * 10
const V = (rows: [number, number][], poc: number, vaLo: number, vaHi: number): Vpvr => ({
  lo: 100, hi: 100 + rows.length, step: 1, rows: rows.map(([buy, sell]) => ({ buy, sell })), poc, vaLo, vaHi, total: rows.reduce((s, [b, q]) => s + b + q, 0),
})
const v10 = V([[1, 1], [2, 1], [3, 2], [4, 4], [6, 4], [5, 3], [3, 2], [2, 1], [1, 1], [0, 0]], 4, 2, 6)
const base = (o: Partial<ProfileInput> = {}): ProfileInput => ({
  x0: 100, x1: 600, v: v10, mode: 'split', colors: { up: '#089981', down: '#F23645', line: '#2962FF' }, priceToY: Y, ...o,
})

describe('行数按像素', () => {
  it('每 4 px 一行，1–240', () => {
    expect(profileRows(400)).toBe(100); expect(profileRows(-80)).toBe(20)
    expect(profileRows(2)).toBe(1); expect(profileRows(5000)).toBe(240)
  })
})

describe('柱子', () => {
  it('最长一行 = 区间宽 30%，从左沿往右长；买卖分开时涨色在左、跌色接在右', () => {
    const L = profileLayout(base())
    expect(L.maxW).toBe(150)
    const poc = L.rects.filter(q => q.row === 4)
    expect(poc.map(q => q.color)).toEqual(['#089981', '#F23645'])
    expect(poc[0].x).toBe(100); expect(poc[1].x).toBe(poc[0].x + poc[0].w)
    expect(poc[0].w + poc[1].w).toBe(150)
    expect(poc[0].w).toBe(90)
    // 别的行都不比控制点那行长
    for (let k = 0; k < 10; k++) {
      const w = L.rects.filter(q => q.row === k).reduce((s, q) => s + q.w, 0)
      expect(w).toBeLessThanOrEqual(150)
    }
  })
  it('窄区间柱宽至少 16 px', () => {
    expect(profileLayout(base({ x0: 0, x1: 20 })).maxW).toBe(16)
  })
  it('贴右沿（可见区间）：柱子右端对齐区间右沿往左长', () => {
    const L = profileLayout(base({ alignRight: true }))
    for (let k = 0; k < 9; k++) {
      const segs = L.rects.filter(q => q.row === k)
      const right = Math.max(...segs.map(q => q.x + q.w))
      expect(right).toBe(600)
      expect(segs[0].color).toBe('#089981')
    }
  })
  it('价值区内实（0.9）、区外淡（0.35）；零量行不画', () => {
    const L = profileLayout(base())
    for (const q of L.rects) expect(q.alpha).toBe(q.row >= 2 && q.row <= 6 ? PROFILE.alphaIn : PROFILE.alphaOut)
    expect(PROFILE.alphaIn).toBe(0.9); expect(PROFILE.alphaOut).toBe(0.35)
    expect(L.rects.some(q => q.row === 9)).toBe(false)
  })
  it('行与行之间留 1 px 缝；每行不到 3 px 时不留', () => {
    const L = profileLayout(base())
    const r4 = L.rects.find(q => q.row === 4)!, r5 = L.rects.find(q => q.row === 5)!
    expect(r4.h).toBe(9); expect(r5.y + r5.h + 1).toBe(r4.y)
    const tight = profileLayout(base({ priceToY: p => 1000 - p * 2 }))
    const a = tight.rects.find(q => q.row === 4)!, b = tight.rects.find(q => q.row === 5)!
    expect(a.h).toBe(2); expect(b.y + b.h).toBe(a.y)
  })
  it('净差：每行一根，买多涨色、卖多跌色，长按 |买−卖|', () => {
    const v = V([[5, 1], [1, 3], [2, 2]], 0, 0, 2)
    const L = profileLayout(base({ v, mode: 'delta' }))
    const r0 = L.rects.filter(q => q.row === 0), r1 = L.rects.filter(q => q.row === 1)
    expect(r0).toHaveLength(1); expect(r0[0].color).toBe('#089981'); expect(r0[0].w).toBe(150)
    expect(r1[0].color).toBe('#F23645'); expect(r1[0].w).toBe(75)
    expect(L.rects.some(q => q.row === 2)).toBe(false)
  })
  it('合计：单色一根，明暗同样区分价值区', () => {
    const L = profileLayout(base({ mode: 'total' }))
    expect(new Set(L.rects.map(q => q.color))).toEqual(new Set([PROFILE.total]))
    expect(L.rects.find(q => q.row === 4)!.w).toBe(150)
    expect(L.rects.find(q => q.row === 0)!.alpha).toBe(0.35)
  })
  it('纵向裁切：窗格外的行不进版式', () => {
    const L = profileLayout(base({ clipY: [0, 50] }))  // 只看得见 105 以上
    expect(L.rects.every(q => q.row >= 4)).toBe(true)
  })
})

describe('横线与底板', () => {
  it('价值区上下沿 1 px 工具色、控制点 1.5 px 橙，都从左沿画到右沿', () => {
    const L = profileLayout(base())
    const by = Object.fromEntries(L.lines.map(l => [l.kind, l]))
    expect(by.vah).toMatchObject({ y: Y(107) + 0.5, x0: 100, x1: 600, color: '#2962FF', width: 1 })
    expect(by.val).toMatchObject({ y: Y(102) + 0.5, x0: 100, x1: 600, color: '#2962FF', width: 1 })
    expect(by.poc).toMatchObject({ y: Math.round(Y(104.5)) + 0.5, x0: 100, x1: 600, color: '#FF9800', width: 1.5 })
  })
  it('底板只在要求时铺，范围是整个区间（时间上左右沿、价格上最高到最低）', () => {
    expect(profileLayout(base()).base).toBeNull()
    const b = profileLayout(base({ base: true, x0: 600, x1: 100 })).base!
    expect(b).toMatchObject({ x: 100, w: 500, y: Y(110), h: 100, color: '#2962FF', alpha: 0.06 })
  })
})

describe('往画布上画', () => {
  it('按版式涂：每块柱子一次 fillRect、三条线、透明度走 globalAlpha（CSS 变量里的颜色写法都认）', () => {
    const calls: [string, unknown[]][] = []
    let ga = 1
    const ctx = new Proxy({} as Record<string, unknown>, {
      get: (t, k: string) => k in t ? t[k] : (...a: unknown[]) => { calls.push([k, a]); if (k === 'fillRect') calls.push(['alpha', [ga]]) },
      set: (t, k: string, val) => { if (k === 'globalAlpha') ga = val as number; else t[k] = val; return true },
    }) as unknown as CanvasRenderingContext2D
    const L = drawProfile(ctx, base({ base: true, colors: { up: 'rgb(8,153,129)', down: 'rgb(242,54,69)', line: '#2962FF' } }))
    expect(calls.filter(([k]) => k === 'fillRect')).toHaveLength(L.rects.length + 1)
    expect(calls.filter(([k]) => k === 'stroke')).toHaveLength(3)
    const alphas = calls.filter(([k]) => k === 'alpha').map(([, a]) => a[0])
    expect(alphas[0]).toBe(0.06); expect(alphas).toContain(0.9); expect(alphas).toContain(0.35)
  })
})
