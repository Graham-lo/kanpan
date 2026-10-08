import { describe, expect, it } from 'vitest'
import type { Drawing } from '../src/chart/chart'
import { TEMPLATES_MAX_BYTES, TEMPLATE_MAX, applyPreset, cleanDefaults, cleanTemplates, decodePrefs, encodePrefs, factoryPreset, presetOf, type DrawPreset, type DrawTemplate } from '../src/chart/drawPreset'
import { LEVEL_TABLE, MAIN_DEF, factoryLevels } from '../src/chart/drawSpec'

const trend = (over: Partial<Drawing> = {}): Drawing => ({ id: 'd', type: 'trend', pts: [{ t: 1, p: 1 }, { t: 2, p: 2 }], ...over })

describe('同步编解码：encodePrefs / decodePrefs', () => {
  it('默认往返一致', () => {
    const defaults: Record<string, DrawPreset> = { trend: { color: '#F23645', width: 3, dash: 'dashed', style: { extR: true } }, rect: { filled: false } }
    expect(decodePrefs(encodePrefs(defaults, {}, {})).defaults).toEqual(defaults)
  })

  it('模板往返一致（带文字、刻度）', () => {
    const templates: Record<string, DrawTemplate[]> = { fib: [{ name: '黄金', color: '#808080', width: 1, levels: [0, 0.5, 1] }], note: [{ name: '注', text: '支撑' }] }
    expect(decodePrefs(encodePrefs({}, templates, {})).templates).toEqual(templates)
  })

  it('键名是 webStyles / templates 加契约种类名', () => {
    const body = encodePrefs({ rect: { width: 1 } }, { rect: [{ name: 'A' }] }, {})
    expect(Object.keys(body).sort()).toEqual(['templates/rectangle', 'webStyles/rectangle'])
  })

  it('模板的键照画线本身：color 是 { value }、粗细叫 lineWidth、线型总写', () => {
    const body = encodePrefs({}, { trend: [{ name: 'A', color: '#F23645', width: 2 }] }, {})
    expect(body['templates/trend']).toEqual([{ name: 'A', color: { value: '#F23645' }, lineWidth: 2, dash: 'solid' }])
  })

  it('别的键（手机的工具偏好）原样留着', () => {
    const prev = { favorites: ['trend'], magnet: true, 'styles/trend': { lineWidth: 2 }, 'variants/trend': 'extended' }
    expect(encodePrefs({ trend: { width: 1 } }, {}, prev)).toMatchObject(prev)
  })

  it('本机没有了的默认不写（交给账本发 null）', () => {
    expect('webStyles/trend' in encodePrefs({}, {}, { 'webStyles/trend': { width: 1 } })).toBe(false)
  })

  it('模板删光了写 []', () => {
    expect(encodePrefs({}, {}, { 'templates/trend': [{ name: 'A' }] })['templates/trend']).toEqual([])
  })

  it('网页没有的工具不编码', () => {
    expect(encodePrefs({ measure: { width: 1 } } as Record<string, DrawPreset>, {}, {})).toEqual({})
  })

  it('解码只认网页有的工具', () => {
    const r = decodePrefs({ 'webStyles/text': { width: 1 }, 'webStyles/nope': { width: 1 }, 'styles/trend': { lineWidth: 2 } })
    expect(r).toEqual({ defaults: {}, templates: {} })
  })

  it('模板最多 16 个，多的丢', () => {
    const list = Array.from({ length: 20 }, (_, i) => ({ name: 'T' + i, lineWidth: 1 }))
    expect(decodePrefs({ 'templates/trend': list }).templates.trend).toHaveLength(TEMPLATE_MAX)
  })

  it('模板名字去重：同名的只留第一个', () => {
    const r = decodePrefs({ 'templates/trend': [{ name: 'A', lineWidth: 1 }, { name: 'A', lineWidth: 2 }, { name: ' A ', lineWidth: 3 }] })
    expect(r.templates.trend).toEqual([{ name: 'A', width: 1 }])
  })

  it('没名字、名字太长的模板丢', () => {
    const r = decodePrefs({ 'templates/trend': [{ lineWidth: 1 }, { name: '  ' }, { name: 'x'.repeat(65) }, { name: 'ok' }] })
    expect(r.templates.trend).toEqual([{ name: 'ok' }])
  })

  it('坏值丢：颜色、粗细、线型、刻度不合规的项不进来', () => {
    const r = decodePrefs({ 'webStyles/fib': { color: 'red', width: 9, dash: 'wavy', levels: [0, 99], filled: 'no', style: { extR: 'yes' } } })
    expect(r.defaults).toEqual({})
  })

  it('坏值丢：一份里好的项留下', () => {
    const r = decodePrefs({ 'webStyles/trend': { color: '#2962FF', width: 9 } })
    expect(r.defaults.trend).toEqual({ color: '#2962FF' })
  })

  it('扩展样式按这把工具的白名单清洗', () => {
    const r = decodePrefs({ 'webStyles/trend': { style: { extR: true, fill: '#FF0000' } } })
    expect(r.defaults.trend).toEqual({ style: { extR: true } })
  })

  it('不是对象的 body、不是数组的模板当没有', () => {
    expect(decodePrefs(undefined)).toEqual({ defaults: {}, templates: {} })
    expect(decodePrefs({ 'templates/trend': { name: 'A' }, 'webStyles/trend': 'x' })).toEqual({ defaults: {}, templates: {} })
  })
})

/** 一个带整张斐波那契刻度表与可见范围的模板（约 1.2 KB） */
const fatFib = (i: number): DrawTemplate => ({
  name: '斐波那契模板' + i, color: '#808080', width: 1, levels: [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1],
  style: { levels: LEVEL_TABLE.fib!.levels.map(x => ({ ...x, c: x.c || '#787B86' })), vis: { sec: { on: true, lo: 1, hi: 59 }, min: { on: true, lo: 1, hi: 59 }, hour: { on: true, lo: 1, hi: 24 }, day: { on: true, lo: 1, hi: 366 } } },
})
const utf8 = (v: unknown): number => new TextEncoder().encode(JSON.stringify(v)).length

describe('体量上限（服务端超了整条 400）', () => {
  it('模板整份超过 16 KB：从后往前少带几个上云', () => {
    const list = Array.from({ length: TEMPLATE_MAX }, (_, i) => fatFib(i))
    const out = encodePrefs({}, { fib: list }, {})['templates/fibonacci'] as unknown[]
    expect(utf8(list.map(t => ({ ...t })))).toBeGreaterThan(TEMPLATES_MAX_BYTES)
    expect(utf8(out)).toBeLessThanOrEqual(TEMPLATES_MAX_BYTES)
    expect(out.length).toBeLessThan(TEMPLATE_MAX)
  })

  it('少带的是后面那几个，前面的照原样', () => {
    const list = Array.from({ length: TEMPLATE_MAX }, (_, i) => fatFib(i))
    const back = decodePrefs(encodePrefs({}, { fib: list }, {})).templates.fib
    expect(back).toEqual(list.slice(0, back.length))
  })
})

describe('读档清洗：cleanDefaults / cleanTemplates', () => {
  it('不认识的工具、坏值丢', () => {
    expect(cleanDefaults({ trend: { width: 2 }, nope: { width: 2 }, hline: 'x' })).toEqual({ trend: { width: 2 } })
  })

  it('模板清洗同一套规矩（上限、去重）', () => {
    const list = [{ name: 'A' }, { name: 'A' }, ...Array.from({ length: 20 }, (_, i) => ({ name: 'T' + i }))]
    expect(cleanTemplates({ trend: list }).trend).toHaveLength(TEMPLATE_MAX)
  })
})

describe('applyPreset 与出厂值', () => {
  it('出厂：TradingView 的主样式', () => {
    expect(factoryPreset('trend')).toEqual({ color: MAIN_DEF.trend!.color, width: MAIN_DEF.trend!.width })
  })

  it('出厂：带刻度的工具带上出厂刻度', () => {
    expect(factoryPreset('fib').levels).toEqual(factoryLevels('fib').levels)
  })

  it('套预设：主字段与 style 整份换掉', () => {
    const d = trend({ color: '#000000', width: 1, dash: 'dotted', style: { extL: true } })
    applyPreset(d, { color: '#F23645', width: 3, style: { extR: true } })
    expect(d).toMatchObject({ color: '#F23645', width: 3, style: { extR: true } })
    expect('dash' in d).toBe(false)
  })

  it('套预设：预设里没有的回到出厂', () => {
    const d = trend({ color: '#000000', width: 5, style: { extL: true } })
    applyPreset(d, {})
    expect(d.color).toBe(MAIN_DEF.trend!.color)
    expect(d.width).toBe(MAIN_DEF.trend!.width)
    expect('style' in d).toBe(false)
  })

  it('套预设：刻度工具没给刻度时用出厂刻度', () => {
    const d: Drawing = { id: 'f', type: 'fib', pts: [{ t: 1, p: 1 }, { t: 2, p: 2 }], levels: [0, 1] }
    applyPreset(d, {})
    expect(d.levels).toEqual(factoryLevels('fib').levels)
  })

  it('套预设：不带文字的预设不动画线的文字', () => {
    const d = trend({ text: '支撑' })
    applyPreset(d, { width: 2 })
    expect(d.text).toBe('支撑')
  })

  it('套预设：预设的 style 是拷贝，改画线不改预设', () => {
    const p: DrawPreset = { style: { extR: true } }
    const d = trend()
    applyPreset(d, p)
    d.style!.extR = false
    expect(p.style).toEqual({ extR: true })
  })

  it('presetOf 取回一条线现在的样子（存为默认不带文字）', () => {
    const d = trend({ color: '#F23645', width: 3, text: '支撑', style: { extR: true } })
    expect(presetOf(d, false)).toEqual({ color: '#F23645', width: 3, style: { extR: true } })
    expect(presetOf(d, true).text).toBe('支撑')
  })
})

describe('新画一条用默认（pages/drawing 的 styleFor / newDrawing）', () => {
  const pts = [{ t: 1, p: 1 }, { t: 2, p: 2 }]

  it('存过默认：照默认画，优先于同族记忆', async () => {
    const { st } = await import('../src/app/store')
    const { newDrawing } = await import('../src/pages/drawing')
    const { familyOf } = await import('../src/chart/drawTools')
    st.drawStyles = { [familyOf('trend')]: { color: '#000000', width: 5 } }
    st.drawDefaults = { trend: { color: '#F23645', dash: 'dashed', style: { extR: true } } }
    expect(newDrawing('trend', pts)).toMatchObject({ color: '#F23645', width: MAIN_DEF.trend!.width, dash: 'dashed', style: { extR: true } })
  })

  it('没存默认：照旧用同族记忆', async () => {
    const { st } = await import('../src/app/store')
    const { newDrawing } = await import('../src/pages/drawing')
    st.drawDefaults = {}
    const { familyOf } = await import('../src/chart/drawTools')
    st.drawStyles = { [familyOf('hline')]: { color: '#089981', width: 3 } }
    const d = newDrawing('hline', [pts[0]])
    expect(d).toMatchObject({ color: '#089981', width: 3 })
    expect('style' in d).toBe(false)
  })

  it('图表新画（chart 的 drawStyle 回调）拿到的是同一份默认，含刻度与扩展样式', async () => {
    const { st } = await import('../src/app/store')
    const { styleFor } = await import('../src/pages/drawing')
    st.drawDefaults = { fib: { levels: [0, 0.5, 1], style: { reverse: true } } }
    expect(styleFor('fib')).toMatchObject({ levels: [0, 0.5, 1], style: { reverse: true } })
  })

  it('两次新画拿到的 style 不是同一个对象', async () => {
    const { st } = await import('../src/app/store')
    const { newDrawing } = await import('../src/pages/drawing')
    st.drawDefaults = { trend: { style: { extR: true } } }
    const a = newDrawing('trend', pts), b = newDrawing('trend', pts)
    expect(a.style).not.toBe(b.style)
  })
})
