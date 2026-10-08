/* 成交量分布画法（照 TradingView 源码的 HHist 渲染）：柱子从哪条边长、最长一行多宽、价值区内外明暗、行缝、三种看法、数值与合计行、三条横线、底板 */
import { describe, expect, it } from 'vitest'
import { drawProfile, fmtVolume, isDarkBg, profileDefaults, profileLayout, profileRows, shiftColor, splitAlpha, type ProfileInput, type ProfileLook } from '../src/chart/volumeProfile'
import { developingProfile, vpvr, type Vpvr } from '../src/chart/overlays'
import type { Bar } from '../src/chart/calc'

// 价格 100–110 分 10 行，每行 1 块钱；y = 1000 − 价格 × 10（每行 10 px，价格越高 y 越小）
const Y = (p: number) => 1000 - p * 10
const V = (rows: [number, number][], poc: number, vaLo: number, vaHi: number): Vpvr => ({
  lo: 100, hi: 100 + rows.length, step: 1, rows: rows.map(([buy, sell]) => ({ buy, sell })), poc, vaLo, vaHi, total: rows.reduce((s, [b, q]) => s + b + q, 0),
})
const v10 = V([[1, 1], [2, 1], [3, 2], [4, 4], [6, 4], [5, 3], [3, 2], [2, 1], [1, 1], [0, 0]], 4, 2, 6)
const DARK = profileDefaults(true)
// 测试用一套不透明好认的颜色，透明度另给
const LOOK: ProfileLook = { ...DARK, up: '#089981', down: '#F23645', vaUp: '#00BCD4D9', vaDown: '#E91E63D9', bg: { on: false, color: '#00BCD414' } }
const base = (o: Partial<ProfileInput> = {}, look: Partial<ProfileLook> = {}): ProfileInput => ({
  x0: 100, x1: 600, v: v10, mode: 'split', look: { ...LOOK, ...look }, priceToY: Y, ...o,
})

describe('主图可见区间分布的行数按像素', () => {
  it('每 4 px 一行，1–240', () => {
    expect(profileRows(400)).toBe(100); expect(profileRows(-80)).toBe(20)
    expect(profileRows(2)).toBe(1); expect(profileRows(5000)).toBe(240)
  })
})

describe('出厂配色（TV 源码值，与 K 线涨跌色脱钩，深浅同一套）', () => {
  it('区外 #26C6DA / #EC407A α 0.5、区内 α 0.75、底色 #26C6DA α 0.05、发展中价值区 #00BCD4；价值区上下沿浅粉开、控制点紫关', () => {
    for (const dark of [true, false]) {
      const d = profileDefaults(dark)
      expect(splitAlpha(d.up)).toEqual(['#26C6DA', 0.5]); expect(splitAlpha(d.down)).toEqual(['#EC407A', 0.5])
      expect(splitAlpha(d.vaUp)).toEqual(['#26C6DA', 0.75]); expect(splitAlpha(d.vaDown)).toEqual(['#EC407A', 0.75])
      expect(splitAlpha(d.bg.color)).toEqual(['#26C6DA', 0.05]); expect(d.bg.on).toBe(true)
      expect(d.devVa.color).toBe('#00BCD4')
      expect([d.vah.on, d.val.on, d.poc.on, d.devPoc.on, d.devVa.on]).toEqual([true, true, false, false, false])
      expect([d.vah.extend, d.val.extend, d.poc.extend]).toEqual([false, false, false])
      expect(d.widthPct).toBe(30); expect(d.placement).toBe('left'); expect(d.values).toBe(false)
    }
    expect(DARK.valuesColor).toBe('#DBDBDB'); expect(profileDefaults(false).valuesColor).toBe('#0F0F0F')
    expect(DARK.devPoc.color).toBe('#DBDBDB')
    expect(DARK.vah.color).toBe('#F8BBD0'); expect(DARK.poc.color).toBe('#B388FF')
  })
  it('深浅判断读底色亮度', () => {
    expect(isDarkBg('#131722')).toBe(true); expect(isDarkBg('#F4F1EA')).toBe(false)
    expect(isDarkBg('rgb(250, 248, 244)')).toBe(false); expect(isDarkBg('')).toBe(true)
  })
  it('TV 成交量格式：三位有效数字，单位前空一格', () => {
    expect(fmtVolume(12)).toBe('12'); expect(fmtVolume(1234)).toBe('1.23 K'); expect(fmtVolume(45_600_000)).toBe('45.6 M')
    expect(fmtVolume(999_999)).toBe('1 M'); expect(fmtVolume(2.5e9)).toBe('2.5 B')
    expect(shiftColor('#DBDBDB', 1.5)).toBe('#ffffff'); expect(shiftColor('#0F0F0F', 1.5)).toBe('#171717')
  })
})

describe('柱子', () => {
  it('最长一行 = 区间宽 × 30% − 段数；从左沿往右长，涨段贴基线、跌段接在后面', () => {
    const L = profileLayout(base())
    expect(L.maxW).toBe(148)
    const poc = L.rects.filter(q => q.row === 4)
    expect(poc.map(q => q.color)).toEqual(['#00BCD4', '#E91E63'])
    expect(poc[0].x).toBe(100); expect(poc[1].x).toBe(poc[0].x + poc[0].w)
    expect(poc[0].w + poc[1].w).toBe(148)
    expect(poc[0].w).toBe(89)
    for (let k = 0; k < 10; k++) expect(L.rects.filter(q => q.row === k).reduce((s, q) => s + q.w, 0)).toBeLessThanOrEqual(148)
  })
  it('宽度 %：60% 时 298；合计看法只减 1、净差减 3；区间太窄时长度归零', () => {
    expect(profileLayout(base({}, { widthPct: 60 })).maxW).toBe(298)
    expect(profileLayout(base({ mode: 'total' })).maxW).toBe(149)
    expect(profileLayout(base({ mode: 'delta' })).maxW).toBe(147)
    expect(profileLayout(base({ x0: 0, x1: 5 })).maxW).toBe(0)
  })
  it('放右：从右沿往左长，涨段贴右沿', () => {
    const L = profileLayout(base({}, { placement: 'right' }))
    for (let k = 0; k < 9; k++) {
      const segs = L.rects.filter(q => q.row === k)
      const edge = segs.find(q => q.x + q.w === 600)!
      expect(edge.color).toBe(k >= 2 && k <= 6 ? '#00BCD4' : '#089981')
      expect(Math.min(...segs.map(q => q.x))).toBeGreaterThanOrEqual(600 - 148)
    }
  })
  it('四色按价值区分；零量行不画', () => {
    const L = profileLayout(base())
    for (const q of L.rects) {
      const inVa = q.row >= 2 && q.row <= 6
      expect(q.alpha).toBe(inVa ? 0.85 : 1)
      if (inVa) expect(['#00BCD4', '#E91E63']).toContain(q.color); else expect(['#089981', '#F23645']).toContain(q.color)
    }
    expect(L.rects.some(q => q.row === 9)).toBe(false)
  })
  it('关掉「成交量分布」只剩线', () => {
    const L = profileLayout(base({}, { vp: false }))
    expect(L.rects).toHaveLength(0); expect(L.lines.length).toBeGreaterThan(0)
  })
  it('行缝：平均行高 ≥ 1 CSS px 留 1 个物理像素，否则不留；坐标对齐物理像素', () => {
    const L = profileLayout(base())
    const r4 = L.rects.find(q => q.row === 4)!, r5 = L.rects.find(q => q.row === 5)!
    expect(r4.h).toBe(9); expect(r5.y + r5.h + 1).toBe(r4.y)
    const tight = profileLayout(base({ priceToY: p => 1000 - p * 2 }))
    expect(tight.rects.find(q => q.row === 4)!.h).toBe(1)
    const retina = profileLayout(base({ pr: 2 }))
    const a = retina.rects.find(q => q.row === 4)!
    expect(a.h).toBe(9)   // 缝 = floor(像素比) 个物理像素
    for (const q of retina.rects) for (const n of [q.x, q.y, q.w, q.h]) expect(Number.isInteger(n * 2)).toBe(true)
    const sub = profileLayout(base({ pr: 2, priceToY: p => 1000 - p * 0.4 }))
    const s4 = sub.rects.find(q => q.row === 4)!, s5 = sub.rects.find(q => q.row === 5)!
    expect(s5.y + s5.h).toBeGreaterThanOrEqual(s4.y)
  })
  it('净差：占优一方的颜色三段（原样 / 一半 / 四分之一透明度），一行总长按买 + 卖', () => {
    const v = V([[5, 1], [1, 3], [2, 2]], 0, 0, 0)
    const L = profileLayout(base({ v, mode: 'delta' }))
    const r0 = L.rects.filter(q => q.row === 0), r1 = L.rects.filter(q => q.row === 1), r2 = L.rects.filter(q => q.row === 2)
    expect(r0.map(q => [q.color, q.alpha])).toEqual([['#00BCD4', 0.85], ['#00BCD4', 0.425], ['#00BCD4', 0.213]])
    expect(r0.reduce((s, q) => s + q.w, 0)).toBe(147)
    expect(r1.map(q => [q.color, q.alpha])).toEqual([['#F23645', 1], ['#F23645', 0.5], ['#F23645', 0.25]])
    expect(r1[0].w).toBe(49)
    expect(r2.map(q => q.alpha)).toEqual([0.5, 0.25])   // 买卖相等：净差那段为 0 不画
  })
  it('合计：单色一根（涨色），明暗同样区分价值区', () => {
    const L = profileLayout(base({ mode: 'total' }))
    expect(L.rects.find(q => q.row === 4)!).toMatchObject({ w: 149, color: '#00BCD4', alpha: 0.85 })
    expect(L.rects.find(q => q.row === 0)!).toMatchObject({ color: '#089981', alpha: 1 })
  })
  it('纵向裁切：窗格外的行不进版式', () => {
    const L = profileLayout(base({ clipY: [-200, -50] }))  // 只看得见 105 以上
    expect(L.rects.length).toBeGreaterThan(0)
    expect(L.rects.every(q => q.row >= 4)).toBe(true)
  })
})

describe('数值', () => {
  const Y2 = (p: number) => 1000 - p * 20   // 每行 20 px
  it('出厂不写；打开后每行「涨量 × 跌量」写在基线内侧 3 px、行顶下 0.7 行高，最底下多一行合计（提亮 1.5 倍），字号统一', () => {
    expect(profileLayout(base({ priceToY: Y2 })).values).toHaveLength(0)
    const L = profileLayout(base({ priceToY: Y2 }, { values: true }))
    expect(L.font).toBe(12)
    const r4 = L.values.find(q => q.row === 4)!
    expect(r4).toMatchObject({ x: 103, y: Y2(105) + 14, align: 'left', text: '6 × 4', color: '#DBDBDB' })
    const tot = L.values.find(q => q.row === -1)!
    expect(tot).toMatchObject({ x: 103, y: Y2(100) + 14, text: '27 × 19', color: '#ffffff' })
    expect(L.values).toHaveLength(11)
  })
  it('放右：数字倒过来、右对齐贴右沿内 3 px', () => {
    const L = profileLayout(base({ priceToY: Y2 }, { values: true, placement: 'right' }))
    expect(L.values.find(q => q.row === 4)!).toMatchObject({ x: 597, align: 'right', text: '4 × 6' })
    expect(L.values.find(q => q.row === -1)!.text).toBe('19 × 27')
  })
  it('合计看法一个数；字号算出来小于 7.5 px 一行都不写', () => {
    const L = profileLayout(base({ priceToY: Y2, mode: 'total' }, { values: true }))
    expect(L.values.find(q => q.row === 4)!.text).toBe('10')
    expect(profileLayout(base({}, { values: true })).values).toHaveLength(0)   // 行高 10 → 6 px
  })
})

describe('横线、发展中折线与底色', () => {
  it('出厂：只有价值区上下沿两条（浅粉 1 px，左沿到右沿、对齐物理像素），没有控制点线', () => {
    const L = profileLayout(base())
    expect(L.lines.map(l => l.kind)).toEqual(['vah', 'val'])
    const by = Object.fromEntries(L.lines.map(l => [l.kind, l]))
    expect(by.vah).toMatchObject({ y: Y(107) + 0.5, x0: 100, x1: 600, color: '#F8BBD0', width: 1, dash: 'solid' })
    expect(by.val).toMatchObject({ y: Y(102) + 0.5, x0: 100, x1: 600, color: '#F8BBD0', width: 1 })
  })
  it('各条线的开关、颜色、线型、粗细都认；只有打开「向右延伸」的那条延到绘图区右沿', () => {
    const L = profileLayout(base({ extendTo: 900 }, { vah: { ...LOOK.vah, on: false }, poc: { on: true, color: '#B388FF80', width: 2, dash: 'dashed', extend: true } }))
    expect(L.lines.map(l => l.kind)).toEqual(['val', 'poc'])
    expect(L.lines.find(l => l.kind === 'poc')!).toMatchObject({ y: Y(104.5), x0: 100, x1: 900, color: '#B388FF', alpha: 0.5, width: 2, dash: 'dashed' })
    expect(L.lines.find(l => l.kind === 'val')!.x1).toBe(600)
  })
  it('发展中控制点 / 价值区：出厂关；打开后逐根阶梯折线，NaN 处断开', () => {
    const dev = { poc: [NaN, 104.5, 105.5], vah: [NaN, 106, 107], val: [NaN, 103, 102], xs: [110, 120, 130] }
    expect(profileLayout(base({ dev })).paths).toHaveLength(0)
    const L = profileLayout(base({ dev }, { devPoc: { ...LOOK.devPoc, on: true }, devVa: { ...LOOK.devVa, on: true } }))
    expect(L.paths.map(q => q.kind)).toEqual(['devPoc', 'devVah', 'devVal'])
    expect(L.paths[0].pts).toEqual([null, { x: 120, y: Y(104.5) }, { x: 130, y: Y(104.5) }, { x: 130, y: Y(105.5) }])
    expect(L.paths[1].color).toBe('#00BCD4')
    // 打开「延伸」：最后一级台阶平着接到绘图区右沿；没给右沿不接
    const E = profileLayout(base({ dev, extendTo: 900 }, { devPoc: { ...LOOK.devPoc, on: true, extend: true }, devVa: { ...LOOK.devVa, on: true } }))
    expect(E.paths[0].pts.at(-1)).toEqual({ x: 900, y: Y(105.5) })
    expect(E.paths[1].pts.at(-1)).toEqual({ x: 130, y: Y(107) })
    expect(profileLayout(base({ dev }, { devPoc: { ...LOOK.devPoc, on: true, extend: true } })).paths[0].pts.at(-1)).toEqual({ x: 130, y: Y(105.5) })
  })
  it('底色：开着时铺整个区间（时间上左右沿、价格上最高到最低），颜色透明度取自色值；关了不铺', () => {
    expect(profileLayout(base()).base).toBeNull()
    const b = profileLayout(base({ x0: 600, x1: 100 }, { bg: { on: true, color: '#00BCD414' } })).base!
    expect(b).toMatchObject({ x: 100, w: 500, y: Y(110), h: 100, color: '#00BCD4', alpha: 0.08 })
  })
})

describe('发展中控制点的算法', () => {
  it('逐根累加：每根收完时的控制点就是到这根为止量最大的一行', () => {
    const bars = [
      { t: 0, o: 100.5, h: 100.9, l: 100.1, c: 100.5, v: 10 },
      { t: 1, o: 104.5, h: 104.9, l: 104.1, c: 104.5, v: 30 },
      { t: 2, o: 102.5, h: 102.9, l: 102.1, c: 102.5, v: 5 },
    ] as unknown as Bar[]
    const v = vpvr(bars, 0, 2, 10)!
    const d = developingProfile(bars, 0, 2, v, 0.7)
    const row = (p: number) => Math.floor((p - v.lo) / v.step)
    expect(row(d.poc[0])).toBe(row(100.5)); expect(row(d.poc[1])).toBe(row(104.5)); expect(row(d.poc[2])).toBe(row(104.5))
    expect(d.poc).toHaveLength(3); expect(d.vah[2]).toBeGreaterThan(d.val[2])
    // 最后一根的发展中控制点 = 整段的控制点
    expect(row(d.poc[2])).toBe(v.poc)
  })
})

describe('往画布上画', () => {
  it('按版式涂：每块柱子一次 fillRect、每条线一次 stroke、透明度走 globalAlpha', () => {
    const calls: [string, unknown[]][] = []
    let ga = 1
    const ctx = new Proxy({} as Record<string, unknown>, {
      get: (t, k: string) => k in t ? t[k] : (...a: unknown[]) => { calls.push([k, a]); if (k === 'fillRect') calls.push(['alpha', [ga]]) },
      set: (t, k: string, val) => { if (k === 'globalAlpha') ga = val as number; else t[k] = val; return true },
    }) as unknown as CanvasRenderingContext2D
    const L = drawProfile(ctx, base({}, { bg: { on: true, color: '#00BCD414' } }))
    expect(calls.filter(([k]) => k === 'fillRect')).toHaveLength(L.rects.length + 1)
    expect(calls.filter(([k]) => k === 'stroke')).toHaveLength(2)
    expect(calls.some(([k]) => k === 'strokeRect')).toBe(false)
    const alphas = calls.filter(([k]) => k === 'alpha').map(([, a]) => a[0])
    expect(alphas[0]).toBe(0.08); expect(alphas).toContain(0.85); expect(alphas).toContain(1)
  })
})
