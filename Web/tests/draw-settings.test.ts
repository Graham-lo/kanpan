/* 画线设置对话框的行（chart/drawSettingsModel）：每把工具有哪几页、每页哪些行，改一项后 d 长什么样，
 * 刻度表 ↔ d.levels 往返，可见范围、坐标、文字、锁定；对话框只是把这些行画出来，这里不用 DOM */
import { describe, expect, it } from 'vitest'
import type { Drawing, DrawingType } from '../src/chart/chart'
import { ALLOWED, DEF, KEYS, LEVEL_TABLE, TEXT_ON, contractLevels, factoryLevels, levelRows, visibleAt } from '../src/chart/drawSpec'
import { ANCHOR_COUNT, usesLevels } from '../src/chart/drawTools'
import { profileLookOf } from '../src/chart/drawStyle'
import { applyPreset, factoryPreset, presetOf } from '../src/chart/drawPreset'
import { applyEdit, knobs, labelOf, rowsOf, shInput, shParse, tabsOf, type Row, type TabId } from '../src/chart/drawSettingsModel'

const TYPES = (Object.keys(ANCHOR_COUNT) as DrawingType[]).filter(t => t !== 'measure')
const mk = (type: DrawingType, extra: Partial<Drawing> = {}): Drawing => ({
  id: type, type, pts: Array.from({ length: ANCHOR_COUNT[type] }, (_, i) => ({ t: 1.7e12 + i * 36e5, p: 100 + i })), color: '#2962FF', width: 2, ...extra,
})
const fib = (): Drawing => { const d = mk('fib'); const f = factoryLevels('fib'); if (f.levels) d.levels = f.levels; return d }
/** 一行管的那些 style 键（控件 path 里 style.<键>、刻度表的键） */
function keysOf(r: Row): string[] {
  if (r.kind === 'group') return []
  if (r.kind === 'levels') return [r.key]
  return [...(r.check ? [r.check] : []), ...r.ctls].map(c => c.path.split('.')).filter(s => s[0] === 'style').map(s => s[1])
}
const keyList = (d: Drawing, tab: TabId) => rowsOf(d, tab).filter(r => r.kind !== 'group').map(r => (r as { key: string }).key)

describe('每把工具的页', () => {
  it('输入页只给有输入项的工具（照 TV：成交量分布两把、回归趋势）；文本页只给能写字的；坐标与可见范围每把都有', () => {
    const inputs = TYPES.filter(t => tabsOf(t).includes('inputs')).sort()
    expect(inputs).toEqual(['anchoredVolumeProfile', 'fvp', 'regression'].sort())
    for (const t of TYPES) {
      const tabs = tabsOf(t)
      // 列了输入页就有行，没列的输入页一行都没有
      expect(rowsOf(mk(t), 'inputs').length > 0, t).toBe(tabs.includes('inputs'))
      expect(tabs.includes('text'), t).toBe(TEXT_ON.has(t))
      expect(tabs.includes('style'), t).toBe(true)
      expect(tabs.slice(-2), t).toEqual(['coords', 'vis'])
    }
    expect(tabsOf('measure')).toEqual([])
  })
  it('这把工具认的每个扩展键（可见范围除外）恰好落在某一页的一行上', () => {
    for (const t of TYPES) {
      const d = mk(t), seen: string[] = []
      for (const tab of tabsOf(t)) if (tab !== 'vis' && tab !== 'coords') for (const r of rowsOf(d, tab)) seen.push(...keysOf(r))
      const want = [...ALLOWED[t]!].filter(k => k !== 'vis').sort()
      expect([...new Set(seen)].sort(), t).toEqual(want)
      // 同一个键不在两行里出现（合成行里一行管几个键可以）
      const perRow = tabsOf(t).flatMap(tab => rowsOf(d, tab).map(r => [...new Set(keysOf(r))])).flat()
      expect(perRow.length, t).toBe(new Set(perRow).size)
    }
  })
  it('行序照 TradingView：趋势线先主线、端点、延伸，统计成一节；斐波那契先趋势线再刻度表', () => {
    expect(keyList(mk('trend'), 'style')).toEqual(['main', 'startEnd', 'endEnd', 'extL', 'extR', 'midPt', 'priceLbl',
      'statPrice', 'statPct', 'statBars', 'statTime', 'statAngle', 'statsPos', 'statsAlways'])
    expect(rowsOf(mk('trend'), 'style').some(r => r.kind === 'group')).toBe(true)
    expect(keyList(fib(), 'style')).toEqual(['trend', 'main', 'levels', 'extL', 'extR', 'fill', 'reverse', 'prices', 'coeffs', 'pct', 'lblPos', 'lblSize'])
    expect(keyList(mk('gannBox'), 'style')).toEqual(['main', 'angles', 'levels', 'tlevels', 'reverse', 'lblL', 'lblR', 'lblT', 'lblB', 'fill'])
    expect(keyList(mk('trend'), 'text')).toEqual(['text', 'font', 'hAlign', 'vAlign'])
    expect(keyList(mk('note'), 'text')).toEqual(['text', 'font', 'txtBg', 'txtBorder'])
    expect(keyList(mk('fvp'), 'inputs')).toEqual(['rowsLayout', 'rowSize', 'volume', 'vaPct', 'extendRight'])
  })
  it('照 TV 摆页：回归的上 / 下偏差在输入页、皮尔逊在样式页；叉子样式、艾略特浪级、斐波那契 / 江恩箱的反转都在样式页', () => {
    expect(keyList(mk('regression'), 'inputs')).toEqual(['devUp', 'devDn'])
    expect(keyList(mk('regression'), 'style')).toEqual(['base', 'upLine', 'dnLine', 'main', 'extR', 'pearson', 'fill'])
    expect(keyList(mk('pitchfork'), 'style')).toEqual(['fork', 'main', 'midLine', 'levels', 'extR', 'fill'])
    for (const t of ['elliottImpulse', 'elliottCorrection'] as DrawingType[]) expect(keyList(mk(t), 'style'), t).toEqual(['main', 'degree', 'font'])
    for (const t of ['fib', 'fibExtension', 'gannBox'] as DrawingType[]) {
      expect(keyList(mk(t), 'style'), t).toContain('reverse')
      expect(tabsOf(t), t).toEqual(['style', 'coords', 'vis'])
    }
    expect(tabsOf('regression')).toEqual(['inputs', 'style', 'coords', 'vis'])
  })
  it('成交量分布五条线行尾各一颗「延伸」（照 TV 每条线的 Extend），出厂关', () => {
    for (const t of ['fvp', 'anchoredVolumeProfile'] as DrawingType[]) {
      const rows = rowsOf(mk(t), 'style').filter((r): r is Extract<Row, { kind: 'row' }> => r.kind === 'row' && ['vah', 'val', 'poc', 'devPoc', 'devVa'].includes(r.key))
      expect(rows.map(r => r.key), t).toEqual(['vah', 'val', 'poc', 'devPoc', 'devVa'])
      for (const r of rows) {
        expect(r.ctls.map(c => c.kind), `${t}/${r.key}`).toEqual(['color', 'width', 'dash', 'check'])
        expect(r.ctls[3], `${t}/${r.key}`).toMatchObject({ path: `style.${r.key}.extend`, value: false, def: false, label: '延伸' })
      }
    }
    // 别的工具的副线没有延伸
    const mid = rowsOf(mk('channel'), 'style').find(r => r.kind === 'row' && r.key === 'midLine')
    expect(mid && mid.kind === 'row' && mid.ctls.map(c => c.kind)).toEqual(['color', 'width', 'dash'])
  })
  it('主线一行照 knobs 给：持仓没有，成交量分布只有颜色，刻度一族没有线型', () => {
    const main = (t: DrawingType) => { const r = rowsOf(mk(t), 'style').find(x => x.kind === 'row' && x.key === 'main'); return r && r.kind === 'row' ? r.ctls.map(c => c.kind) : null }
    expect(main('position')).toBeNull()
    expect(main('fvp')).toEqual(['color'])
    expect(main('fib')).toEqual(['color', 'width'])
    expect(main('trend')).toEqual(['color', 'width', 'dash'])
    expect(knobs('note')).toMatchObject({ width: false, dash: false })
  })
  it('标签都有中文词（不露键名），出厂值跟着行走', () => {
    for (const t of TYPES) for (const tab of tabsOf(t)) for (const r of rowsOf(mk(t), tab)) {
      expect(r.label, `${t}/${tab}`).toBeTruthy()
      if (r.kind === 'row') expect(r.label, `${t}/${tab}/${r.key}`).not.toBe(r.key)
    }
    const ext = rowsOf(mk('ray'), 'style').find(r => r.kind === 'row' && r.key === 'extR')
    expect(ext && ext.kind === 'row' && ext.check).toMatchObject({ value: true, def: true })
    expect(labelOf('extL')).toBe('向左延伸')
  })
  it('没设的开关读出厂（渲染端 !== false 的几项与设置框读法一致）', () => {
    for (const t of TYPES) {
      if (t === 'fvp' || t === 'anchoredVolumeProfile') continue
      for (const k of ALLOWED[t]!) if (KEYS[k] === 'bool') expect(typeof DEF[t]?.[k], `${t}.${k}`).toBe('boolean')
    }
  })
})

describe('改一项后 d 长什么样', () => {
  it('开关：改了存、改回出厂就删，style 空了整份去掉', () => {
    const d = mk('trend')
    expect(applyEdit(d, 'style.extL', true)).toBe(true)
    expect(d.style).toEqual({ extL: true })
    applyEdit(d, 'style.statPct', true)
    expect(d.style).toEqual({ extL: true, statPct: true })
    applyEdit(d, 'style.extL', false); applyEdit(d, 'style.statPct', false)
    expect(d.style).toBeUndefined()
  })
  it('副线一个字段一个字段地存；颜色给空 = 跟画线色', () => {
    const d = mk('channel')
    applyEdit(d, 'style.midLine.on', false)
    expect(d.style).toEqual({ midLine: { on: false } })
    applyEdit(d, 'style.midLine.color', '#F23645')
    expect(d.style).toEqual({ midLine: { on: false, color: '#F23645' } })
    applyEdit(d, 'style.midLine.on', true); applyEdit(d, 'style.midLine.color', '#2962FF')
    expect(d.style).toBeUndefined() // 和出厂（#2962FF 1 像素虚线、开）一样
    applyEdit(d, 'style.midLine.width', 3)
    expect(d.style).toEqual({ midLine: { width: 3 } })
  })
  it('色块：给值存、给空回出厂；数字越界收到上下限；字号下拉给的字符串也认', () => {
    const d = mk('rect')
    applyEdit(d, 'style.fill', '#9C27B033')
    expect(d.style).toEqual({ fill: '#9C27B033' })
    applyEdit(d, 'style.fill', '')
    expect(d.style).toBeUndefined()
    const f = fib()
    applyEdit(f, 'style.bgAlpha', 150)
    expect(f.style?.bgAlpha).toBe(100)
    applyEdit(f, 'style.lblSize', '16')
    expect(f.style?.lblSize).toBe(16)
    expect(applyEdit(mk('trend'), 'style.vah', true)).toBe(false) // 这把工具不认的键
  })
  it('主字段：线型实线 = 删键，填色开 = 删键', () => {
    const d = mk('rect', { dash: 'dashed', filled: false })
    applyEdit(d, 'main.dash', 'solid'); applyEdit(d, 'main.filled', true)
    expect(d.dash).toBeUndefined(); expect(d.filled).toBeUndefined()
    applyEdit(d, 'main.color', '#f23645cc'); applyEdit(d, 'main.width', 3)
    expect(d).toMatchObject({ color: '#F23645CC', width: 3 })
    expect(applyEdit(d, 'main.color', 'red')).toBe(false)
  })
  it('文字：超 60 个字素截断，清空删键', () => {
    const d = mk('trend')
    applyEdit(d, 'text', '突'.repeat(80))
    expect([...d.text!].length).toBe(60)
    applyEdit(d, 'text', '')
    expect(d.text).toBeUndefined()
  })
  it('锁定的线一项都改不了', () => {
    const d = mk('trend', { locked: true })
    expect(applyEdit(d, 'style.extL', true)).toBe(false)
    expect(applyEdit(d, 'main.color', '#000000')).toBe(false)
    expect(d.style).toBeUndefined()
  })
  it('成交量分布：输入项回到出厂就删；外观色照存', () => {
    const d = mk('fvp')
    applyEdit(d, 'style.rowSize', 30)
    expect(d.style).toEqual({ rowSize: 30 })
    applyEdit(d, 'style.rowSize', 24)
    expect(d.style).toBeUndefined()
    applyEdit(d, 'style.poc.on', true)
    expect(d.style).toEqual({ poc: { on: true } })
    const poc = rowsOf(d, 'style').find(r => r.kind === 'row' && r.key === 'poc')
    expect(poc && poc.kind === 'row' && poc.check?.value).toBe(true)
    // 延伸：打开存进这条线、图上照它延到右沿（profileLookOf）；关回去就不存
    applyEdit(d, 'style.poc.extend', true)
    expect(d.style).toEqual({ poc: { on: true, extend: true } })
    expect(profileLookOf(d.style, true).poc.extend).toBe(true)
    const ext = rowsOf(d, 'style').find(r => r.kind === 'row' && r.key === 'poc')
    expect(ext && ext.kind === 'row' && ext.ctls.at(-1)).toMatchObject({ kind: 'check', value: true })
    applyEdit(d, 'style.poc.extend', false)
    expect(d.style).toEqual({ poc: { on: true } })
    applyEdit(d, 'style.devVa.extend', true)
    expect(profileLookOf(d.style, false).devVa).toMatchObject({ on: false, extend: true })
    // 数值色的出厂灰随底色变
    const vc = (dark: boolean) => { const r = rowsOf(mk('fvp'), 'style', { dark }).find(x => x.kind === 'row' && x.key === 'values'); return r && r.kind === 'row' && r.ctls[0].kind === 'color' ? r.ctls[0].shown : '' }
    expect(vc(true)).not.toBe(vc(false))
  })
})

describe('刻度表 ↔ d.levels', () => {
  it('斐波那契关掉一条：d.levels 去掉它，整张表进 style；再打开回到出厂（style 去掉）', () => {
    const d = fib(), base = [...d.levels!]
    const i = levelRows(d).findIndex(x => x.v === 0.236)
    applyEdit(d, `lv.levels.${i}.on`, false)
    expect(d.levels).toEqual(base.filter(v => v !== 0.236))
    expect((d.style?.levels as { v: number; on: boolean }[])[i]).toMatchObject({ v: 0.236, on: false })
    expect(levelRows(d)[i].on).toBe(false)
    applyEdit(d, `lv.levels.${i}.on`, true)
    expect(d.levels).toEqual(base)
    expect(d.style).toBeUndefined()
  })
  it('改值、改色：三端口径跟着值走，颜色只在 style 里', () => {
    const d = fib()
    const i = levelRows(d).findIndex(x => x.v === 0.5)
    applyEdit(d, `lv.levels.${i}.v`, '0.55')
    applyEdit(d, `lv.levels.${i}.c`, '#FFEB3B')
    expect(d.levels).toContain(0.55); expect(d.levels).not.toContain(0.5)
    expect(levelRows(d)[i]).toEqual({ v: 0.55, c: '#FFEB3B', on: true })
    expect(contractLevels('fib', levelRows(d))).toEqual(d.levels)
    applyEdit(d, `lv.levels.${i}.c`, '')
    expect(levelRows(d)[i].c).toBe('')
  })
  it('出厂关着的刻度（4.618）打开：表里记着，|v| ≤ 10 也进三端的 d.levels', () => {
    const d = fib()
    const i = levelRows(d).findIndex(x => x.v === 4.618)
    applyEdit(d, `lv.levels.${i}.on`, true)
    expect(levelRows(d)[i].on).toBe(true)
    expect(d.levels).toContain(4.618)
  })
  it('江恩箱的 0 / 1 是箱框：只在 style 里开关，不进 d.levels', () => {
    const d = mk('gannBox'); d.levels = factoryLevels('gannBox').levels
    const i0 = levelRows(d).findIndex(x => x.v === 0)
    applyEdit(d, `lv.levels.${i0}.on`, false)
    expect(levelRows(d)[i0].on).toBe(false)
    expect(d.levels).not.toContain(0)
    expect(d.levels).toEqual(factoryLevels('gannBox').levels)
    const t = levelRows(d, 'tlevels').findIndex(x => x.v === 0.5)
    applyEdit(d, `lv.tlevels.${t}.on`, false)
    expect(levelRows(d, 'tlevels')[t].on).toBe(false)
  })
  it('叉子不走三端刻度：只写 style', () => {
    const d = mk('pitchfork')
    expect(usesLevels('pitchfork')).toBe(false)
    const i = levelRows(d).findIndex(x => x.v === 0.618)
    applyEdit(d, `lv.levels.${i}.on`, true)
    expect(d.levels).toBeUndefined()
    expect(levelRows(d)[i].on).toBe(true)
    expect(LEVEL_TABLE.pitchfork!.levels[i].on).toBe(false) // 出厂表没被改到
  })
})

describe('坐标与可见范围', () => {
  it('改锚点；持仓改目标时间时止损跟着走', () => {
    const d = mk('trend')
    applyEdit(d, 'pt.1.p', '123.5'); applyEdit(d, 'pt.0.t', 1.7e12 - 6e4)
    expect(d.pts).toEqual([{ t: 1.7e12 - 6e4, p: 100 }, { t: 1.7e12 + 36e5, p: 123.5 }])
    const p = mk('position')
    applyEdit(p, 'pt.1.t', 1.8e12)
    expect(p.pts[2].t).toBe(1.8e12)
    // 水平线只有价格、竖线只有时间、持仓止损只有价格
    const kinds = (d: Drawing) => rowsOf(d, 'coords').map(r => r.kind === 'row' ? r.ctls.map(c => c.kind).join('+') : '')
    expect(kinds(mk('hline'))).toEqual(['num'])
    expect(kinds(mk('vline'))).toEqual(['time'])
    expect(kinds(mk('position'))).toEqual(['num+time', 'num+time', 'num'])
  })
  it('上海时间往返', () => {
    expect(shInput(Date.UTC(2026, 0, 1, 0, 0))).toBe('2026-01-01T08:00')
    expect(shParse('2026-01-01T08:00')).toBe(Date.UTC(2026, 0, 1, 0, 0))
    expect(shParse('坏的')).toBeNull()
  })
  it('六类每类一行；改了写 style.vis、和图上显隐一致，改回整类去掉', () => {
    const d = mk('trend')
    expect(rowsOf(d, 'vis').map(r => r.kind === 'row' ? r.key : '')).toEqual(['vis.sec', 'vis.min', 'vis.hour', 'vis.day', 'vis.week', 'vis.month'])
    applyEdit(d, 'vis.min.lo', 5)
    expect(d.style).toEqual({ vis: { min: { on: true, lo: 5, hi: 59 } } })
    expect(visibleAt(d, 6e4)).toBe(false); expect(visibleAt(d, 5 * 6e4)).toBe(true)
    applyEdit(d, 'vis.min.hi', 3) // 上限比下限小：下限跟着收
    expect(d.style?.vis).toEqual({ min: { on: true, lo: 3, hi: 3 } })
    applyEdit(d, 'vis.hour.on', false)
    expect(visibleAt(d, 36e5)).toBe(false)
    applyEdit(d, 'vis.min.lo', 1); applyEdit(d, 'vis.min.hi', 59); applyEdit(d, 'vis.hour.on', true)
    expect(d.style).toBeUndefined()
  })
})

describe('模板与恢复出厂', () => {
  it('设置框改过的线存成模板、套到另一条上一模一样；恢复出厂清掉 style', () => {
    const a = fib()
    applyEdit(a, 'style.extR', true); applyEdit(a, 'main.color', '#F23645')
    applyEdit(a, `lv.levels.${levelRows(a).findIndex(x => x.v === 0.382)}.on`, false)
    const b = fib()
    applyPreset(b, { ...presetOf(a, true) })
    expect(b.style).toEqual(a.style); expect(b.levels).toEqual(a.levels); expect(b.color).toBe('#F23645')
    applyPreset(b, factoryPreset('fib'))
    expect(b.style).toBeUndefined(); expect(b.levels).toEqual(factoryLevels('fib').levels)
  })
})
