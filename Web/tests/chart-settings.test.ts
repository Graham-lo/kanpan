/* 2026-10-07 用户：「图表可以设置高度和右边距离吗，你把图表设置也复刻进来」。
 * 照 TradingView「图表设置」：商品 / 状态栏 / 比例尺与线 / 画布；画布边距（上 % / 下 % / 右侧留白 根）。
 * 十六格同一份、跟人走（store + 同步字段 webChart，只存和默认不同的几项、≤ 8 KB）。 */
import { describe, expect, it, vi } from 'vitest'

vi.mock('../src/market/rest', () => ({ klines: vi.fn(async () => ({ ok: false, bars: [] })) }))

const { TVChart } = await import('../src/chart/chart')
const { DEFAULTS, LIMITS, MAX_BYTES, clean, crossText, dashOf, dateText, diff, marginRange, withUpDownReset, dayStartSh } = await import('../src/chart/chartSettings')
const { crossTimeLabel } = await import('../src/util/format')
const { SETTINGS_FIELDS, decodeSetting, encodeSetting, encodeSettings, factorySettings, putSetting, webSetting } = await import('../src/sync/codec')
type Any = any // eslint-disable-line @typescript-eslint/no-explicit-any
const fake = (f: Any): Any => Object.assign(Object.create(TVChart.prototype), f)
const bars = (n: number) => Array.from({ length: n }, (_, k) => ({ t: 1_700_006_400_000 + k * 36e5, o: 100, h: 110, l: 90, c: 100, v: 1 }))

describe('chartSettings · 默认值与清洗', () => {
  it('默认照 TradingView：上 10% / 下 8% / 右 10 根、最新价线点线、十字线虚线 1 像素、状态栏背景 50%', () => {
    expect([DEFAULTS.marginTop, DEFAULTS.marginBottom, DEFAULTS.rightBars]).toEqual([10, 8, 10])
    expect(DEFAULTS.lastLineStyle).toBe('dotted')
    expect([DEFAULTS.crossStyle, DEFAULTS.crossWidth]).toEqual(['dashed', 1])
    expect([DEFAULTS.legendBg, DEFAULTS.legendBgOpacity]).toEqual([true, 50])
    // 蜡烛颜色默认不覆盖：跟涨跌色（绿涨红跌）走
    expect([DEFAULTS.bodyUp, DEFAULTS.bodyDown, DEFAULTS.wickUp, DEFAULTS.borderDown]).toEqual([null, null, null, null])
    expect(Object.isFrozen(DEFAULTS)).toBe(true)
  })
  it('坏值回默认、越界按上下限收、未知键丢掉、颜色统一大写', () => {
    const s = clean({ marginTop: 99, marginBottom: -5, rightBars: 1e6, grid: 'xx', bodyUp: '#26a69a', bodyDown: 'red', junk: 1, precision: 3.4, crossWidth: 9 })
    expect(s.marginTop).toBe(LIMITS.margin[1]); expect(s.marginBottom).toBe(0)
    expect(s.rightBars).toBe(LIMITS.rightBars[1])
    expect(s.grid).toBe('both'); expect(s.bodyUp).toBe('#26A69A'); expect(s.bodyDown).toBeNull()
    expect('junk' in s).toBe(false); expect(s.precision).toBe(3); expect(s.crossWidth).toBe(4)
    expect(clean(null)).toEqual({ ...DEFAULTS }); expect(clean([1, 2])).toEqual({ ...DEFAULTS })
  })
  it('上下边距加起来超过 80% 回默认（价格窗不能被挤没）', () => {
    const s = clean({ marginTop: 40, marginBottom: 40 }); expect([s.marginTop, s.marginBottom]).toEqual([40, 40])
    const t = clean({ marginTop: 40, marginBottom: 41 }); expect([t.marginTop, t.marginBottom]).toEqual([40, 40])
  })
  it('diff 只留和默认不同的项；换涨跌配色把蜡烛颜色覆盖清掉', () => {
    expect(diff({ ...DEFAULTS })).toEqual({})
    expect(diff(clean({ marginTop: 20, rightBars: 3 }))).toEqual({ marginTop: 20, rightBars: 3 })
    const r = withUpDownReset(clean({ bodyUp: '#123456', wickDown: '#654321', bg: '#000000' }))
    expect([r.bodyUp, r.wickDown, r.bg]).toEqual([null, null, '#000000'])
  })
})

describe('chartSettings · 边距 → 价格范围', () => {
  it('最高价离上沿 top%、最低价离下沿 bottom%', () => {
    const { min, max } = marginRange(100, 200, 10, 8, false)
    const H = max - min
    expect((max - 200) / H).toBeCloseTo(0.10, 6)
    expect((100 - min) / H).toBeCloseTo(0.08, 6)
    const z = marginRange(100, 200, 0, 0, false); expect([z.min, z.max]).toEqual([100, 200])
  })
  it('对数轴按对数空间留白；一字线不塌成一条', () => {
    const { min, max } = marginRange(10, 1000, 20, 20, true)
    const H = Math.log(max) - Math.log(min)
    expect((Math.log(max) - Math.log(1000)) / H).toBeCloseTo(0.2, 6)
    const f = marginRange(50, 50, 10, 8, false); expect(f.max).toBeGreaterThan(f.min)
  })
  it('引擎自动模式走设置里的边距；手动拖过价格轴不受影响', () => {
    const c = fake({ bars: bars(20), calcStale: false, _series: {}, hidden: new Set(), log: false, settings: clean({ marginTop: 30, marginBottom: 0 }), manual: null })
    const r = c.rangeMain(0, 19)
    expect(r.min).toBeCloseTo(90, 6); expect((r.max - 110) / (r.max - r.min)).toBeCloseTo(0.3, 6)
    c.manual = { min: 1, max: 2 }; expect(c.rangeMain(0, 19)).toEqual({ min: 1, max: 2 })
  })
})

describe('chartSettings · 右侧留白', () => {
  it('rightMarginBars 读设置；没装设置（老测试的假图）按默认 10', () => {
    expect(fake({}).rightMarginBars()).toBe(10)
    expect(fake({ settings: clean({ rightBars: 37 }) }).rightMarginBars()).toBe(37)
  })
  it('回到最新（resetView）按设置留白', () => {
    const c = fake({ bars: bars(100), replay: null, settings: clean({ rightBars: 25 }), o: {}, zAnim: null, dirty: false })
    c.resetView()
    expect(c.rightBar).toBe(99 + 25)
  })
  it('改留白时贴着最新的格子跟着挪，看历史的不动', () => {
    const base = { bars: bars(100), replay: null, o: {}, colors: {}, dirty: false, paneLegendKeys: [null], renderLegend: () => {} }
    const live = fake({ ...base, rightBar: 109 }); live.setSettings(clean({ rightBars: 40 }))
    expect(live.rightBar).toBe(139)
    const hist = fake({ ...base, rightBar: 60 }); hist.setSettings(clean({ rightBars: 40 }))
    expect(hist.rightBar).toBe(60)
  })
})

describe('chartSettings · 时间与线型', () => {
  it('默认的十字线时间标签和以前一字不差', () => {
    for (const iv of [60e3, 36e5, 864e5, 1e3]) expect(crossText(1_759_120_200_000, iv, DEFAULTS)).toBe(crossTimeLabel(1_759_120_200_000, iv))
  })
  it('日期格式 / 星期 / 12 小时制', () => {
    const t = Date.UTC(2026, 8, 29, 6, 30) // 上海 14:30
    expect(dateText(t, 'yyyy-MM-dd')).toBe('2026-09-29')
    expect(dateText(t, 'dd MMM \'yy')).toBe('29 Sep \'26')
    expect(crossText(t, 36e5, { dateFmt: 'MM/dd/yyyy', weekday: false, hour12: true })).toBe('09/29/2026  02:30 PM')
    expect(dayStartSh(t)).toBe(Date.UTC(2026, 8, 28, 16))
  })
  it('线型 → 虚线数组', () => {
    expect(dashOf('solid')).toEqual([]); expect(dashOf('dashed', 2)).toEqual([8, 8]); expect(dashOf('dotted')).toEqual([1, 2])
  })
})

describe('chartSettings · 同步（webChart）', () => {
  it('进同步字段；云端只存和默认不同的几项', () => {
    expect(SETTINGS_FIELDS).toContain('webChart')
    const s = factorySettings(); s.chartSettings = clean({ marginTop: 20, rightBars: 3 })
    expect(webSetting(s, 'webChart')).toEqual({ marginTop: 20, rightBars: 3 })
    expect(webSetting(factorySettings(), 'webChart')).toEqual({})
  })
  it('超过 8 KB 不推（本机照常生效）；坏的云端值清洗后再装', () => {
    expect(encodeSetting('webChart', { marginTop: 20 }, undefined)).toEqual({ marginTop: 20 })
    expect(encodeSetting('webChart', { x: 'y'.repeat(MAX_BYTES) }, undefined)).toBeUndefined()
    expect(decodeSetting('webChart', { marginTop: 999, bogus: 1 }, factorySettings())).toEqual({ marginTop: LIMITS.margin[1] })
    expect(decodeSetting('webChart', 'nope', factorySettings())).toBeUndefined()
    const s = factorySettings(); putSetting(s, 'webChart', { rightBars: 50, grid: 'none' })
    expect(s.chartSettings.rightBars).toBe(50); expect(s.chartSettings.grid).toBe('none'); expect(s.chartSettings.marginTop).toBe(10)
  })
  it('改了会推一次 settings 对象，再改回默认推空对象', () => {
    const seen = {}
    const s = factorySettings(); s.chartSettings = clean({ marginBottom: 0 })
    const o = encodeSettings(s, undefined, seen)!
    expect(o.body.webChart).toEqual({ marginBottom: 0 })
    s.chartSettings = clean({})
    expect(encodeSettings(s, o, seen)!.body.webChart).toEqual({})
  })
})
