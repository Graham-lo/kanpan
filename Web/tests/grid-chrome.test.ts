/* UI 审查 2026-10-10 A3（原型 web-layout-2026-10-10 第 4 节）：多图的底栏与每格 chrome
 * - 整页一条全局底栏，作用于当前格，左头「作用于 · 格 N」（一图不写）
 * - 每格右下角「对数 / 自动」只改这一格
 * - 格子矮（按实际像素，K 线留不够 280）只画主图 + 成交量，格子变高副图原样回来（用户的副图清单不动）
 * - 关键价位的轴标签并进 layoutAxisLabels 一起让位；拖着的提醒价 / 悬停「+」压在最新价上面 */
import { describe, expect, it, vi } from 'vitest'
import { degradeFor, paneHeights, AXIS_H, MAIN_KEEP_PX, FULL } from '../src/chart/panes'
import { footTarget, footTargetLabel, footHTML, cellFootHTML, toggleView, RANGES, GFOOT_H } from '../src/pages/chartFoot'

vi.mock('../src/market/rest', () => ({ klines: vi.fn(async () => ({ ok: false, bars: [] })) }))
// 关键价位：轴标签由测试直接给（真实现读 drawKeyLevels 这一帧摆好的位置）
const keyTags = vi.hoisted(() => ({ list: [] as { y: number; text: string; bg: string }[] }))
vi.mock('../src/chart/keyLevels', async orig => ({ ...(await orig<Record<string, unknown>>()), keyAxisTags: () => keyTags.list }))
const { TVChart } = await import('../src/chart/chart')
type Any = Record<string, unknown>
type Drawn = { text: string; y: number; want: number; pri: number }[]

/** 只带画轴标签 / 副图开关用到的字段的假图：主图 0–400，最新价 100（priceToY / yToPrice 直接等于价） */
function fakeChart(extra: Any = {}): InstanceType<typeof TVChart> & Any {
  const noop = (): void => {}
  const ctx = { fillStyle: '', strokeStyle: '', lineWidth: 1, textAlign: '', font: '', fill: noop, fillText: noop, stroke: noop, beginPath: noop, moveTo: noop, lineTo: noop, arcTo: noop, closePath: noop }
  return Object.assign(Object.create(TVChart.prototype), {
    ctx, aw: 70, w: 600, h: 400, font: '13px sans-serif', meta: { dec: 1, title: 'BTCUSDT' },
    bars: Array.from({ length: 5 }, (_, k) => ({ t: k * 36e5, o: 100, h: 101, l: 99, c: 100, v: 1 })),
    ind: { ma: false, keys: true, subs: ['macd', 'rsi'] }, hidden: new Set<string>(), alerts: [], drag: null, compare: null, axisHoverY: null,
    _series: {}, calcStale: false, axisInd: true, axisTagsDrawn: [], dirty: false, paneLegendKeys: [],
    deg: FULL, recalc() { (this as Any).calcStale = true },
    colors: { text: '#111', text2: '#888', text3: '#aaa', alert: '#f80', up: '#0a0', down: '#a00' },
    settings: undefined, renderLegend: () => {},
    priceToY: (v: number) => v, yToPrice: (y: number) => y, plotW: () => 530, lastColor: () => '#0a0', mainAxisText: (v: number) => v.toFixed(1),
    compareBase: () => null, compareViews: () => [],
    ...extra,
  } as Any) as InstanceType<typeof TVChart> & Any
}
const pane = { id: 'main', y: 0, h: 400 }
const range = { lo: 0, hi: 400 }

describe('格子矮了只画主图 + 成交量（按格子实际像素，不按格数）', () => {
  // 各视口下十六图 / 四图一格的实测尺寸（格子里没有底栏了，画布高 = 格高 − 时间轴 28）
  const G16: [string, number, number][] = [['1440×900', 300, 190], ['1920×1080', 368, 232], ['2560×1440', 528, 322], ['3440×1440', 748, 322]]
  it('十六图在各种屏上都只画主图 + 成交量，K 线占满整格（≥ 2560 时约 300 高）', () => {
    for (const [vp, w, h] of G16) {
      const d = degradeFor(w, h)
      expect(d.subs, vp).toBe(0)
      expect(paneHeights(h - AXIS_H, [], null), vp).toEqual([h - AXIS_H])
    }
  })
  it('同一个四图：2560×1440 留副图，1440×900 只留一个（K 线守住 280）', () => {
    expect(degradeFor(1050, 640).subs).toBeGreaterThanOrEqual(3)
    const small = degradeFor(600, 380)
    expect(small.subs).toBe(1)
    expect(paneHeights(380 - AXIS_H, ['macd'], null)[0]).toBeGreaterThanOrEqual(MAIN_KEEP_PX)
  })
  it('换到十六图（格子变矮）：副图不画、用户的副图清单不动；换回四图（格子变高）原样画回来、要重算', () => {
    const ch = fakeChart()
    ch.setDegrade(degradeFor(528, 322))
    expect(ch.subIds()).toEqual([])
    expect((ch.ind as { subs: string[] }).subs).toEqual(['macd', 'rsi'])
    expect(ch.axisIndicatorLabels).toBe(false)
    ;(ch as Any).calcStale = false
    ch.setDegrade(degradeFor(1050, 640))
    expect(ch.subIds()).toEqual(['macd', 'rsi'])
    expect((ch as Any).calcStale).toBe(true)
    expect(ch.axisIndicatorLabels).toBe(true)
  })
})

describe('全局底栏作用于当前格', () => {
  it('按钮落到当前格；下标越界退到第一格', () => {
    const cells = ['a', 'b', 'c', 'd']
    expect(footTarget(cells, 2)).toBe('c')
    expect(footTarget(cells, 9)).toBe('a')
    expect(footTarget([], 0)).toBeUndefined()
  })
  it('左头：多图写「作用于 · 格 N」（从 1 数），一图不写', () => {
    expect(footTargetLabel(1, 0)).toBe('')
    expect(footTargetLabel(4, 2)).toBe('作用于 · 格 3')
    expect(footTargetLabel(16, 15)).toBe('作用于 · 格 16')
  })
  it('一条底栏装下原来每格那一整条：布局集 · 截图 · 回放 · 导出 · 8 个时间范围 · 钟 · 连接点 · 对数 · 自动；图标是 24 格细线字形', () => {
    const h = footHTML({ label: '作用于 · 格 2', sets: '默认', conn: 'live', connTip: '行情连着', log: true, auto: false, replayTip: '回放' })
    for (const a of ['sets', 'save', 'replay', 'export', 'log', 'auto']) expect(h).toContain(`data-act="${a}"`)
    expect(h.match(/data-range="/g)).toHaveLength(RANGES.length)
    expect(h).toContain('class="clock num"')
    expect(h).toContain('data-conn="live"')
    expect(h).toContain('作用于 · 格 2')
    expect(h).toMatch(/data-act="log"[^>]*aria-pressed="true"/)
    expect(h).toMatch(/data-act="auto"[^>]*aria-pressed="false"/)
    expect(h.match(/<svg class="q-foot q" viewBox="0 0 24 24"/g)).toHaveLength(3)
    expect(h).not.toContain('icon-16')
    // 一图：左头藏起来
    expect(footHTML({ label: '', sets: '', conn: 'live', connTip: '', log: false, auto: true, replayTip: '' })).toMatch(/class="foot-target" hidden/)
    expect(GFOOT_H).toBe(32)
  })
})

describe('每格右下角「对数 / 自动」只改这一格', () => {
  const view = () => {
    const v = { log: false, auto: true, setLog(x: boolean) { v.log = x }, setAuto(x: boolean) { v.auto = x } }
    return v
  }
  it('两颗：对数、自动，按下态跟这一格', () => {
    const h = cellFootHTML({ log: true, auto: false })
    expect(h.match(/<button/g)).toHaveLength(2)
    expect(h).toMatch(/^<div class="cfoot">/)
    expect(h).toMatch(/data-act="log"[^>]*aria-pressed="true"[^>]*>对数</)
    expect(h).toMatch(/data-act="auto"[^>]*aria-pressed="false"[^>]*>自动</)
  })
  it('点第二格的对数 / 自动：第二格变，第一格不动', () => {
    const a = view(), b = view()
    expect(toggleView(b, 'log')).toBe(true)
    expect(toggleView(b, 'auto')).toBe(false)
    expect([a.log, a.auto]).toEqual([false, true])
    expect([b.log, b.auto]).toEqual([true, false])
  })
})

describe('关键价位并进轴标签让位', () => {
  it('关键价位贴着最新价：被推开、不和最新价叠；最新价原位、最后画', () => {
    keyTags.list = [{ y: 104, text: '104.0', bg: '#09c' }]
    const ch = fakeChart()
    ch.drawPriceLabels(pane as never, range as never)
    const d = ch.axisTagsDrawn as Drawn
    const last = d[d.length - 1], key = d.find(t => t.text === '104.0')
    expect(last).toMatchObject({ text: '100.0', y: 100 })
    expect(key).toBeTruthy()
    expect(Math.abs(key!.y - last.y)).toBeGreaterThanOrEqual(21)
    expect(key!.pri).toBeLessThan(last.pri)
  })
  it('离得远的原样放；格子矮 / 窄（不挂指标标签）时和指标标签一起收', () => {
    keyTags.list = [{ y: 300, text: '300.0', bg: '#09c' }]
    const ch = fakeChart()
    ch.drawPriceLabels(pane as never, range as never)
    expect((ch.axisTagsDrawn as Drawn).find(t => t.text === '300.0')?.y).toBe(300)
    const many = fakeChart({ axisInd: false })
    many.drawPriceLabels(pane as never, range as never)
    expect((many.axisTagsDrawn as Drawn).map(t => t.text)).toEqual(['100.0'])
  })
  it('关键价位关着（或被藏起来）不出标签', () => {
    keyTags.list = [{ y: 300, text: '300.0', bg: '#09c' }]
    const off = fakeChart({ ind: { keys: false, subs: [] } })
    off.drawPriceLabels(pane as never, range as never)
    expect((off.axisTagsDrawn as Drawn).map(t => t.text)).toEqual(['100.0'])
  })
})

describe('「+」建提醒与拖着的提醒价压在最新价上面', () => {
  it('价格轴悬停「+」贴着最新价：实底一枚、在鼠标的价位、最后画（不被最新价盖住）', () => {
    keyTags.list = []
    const ch = fakeChart({ axisHoverY: 104 })
    ch.drawPriceLabels(pane as never, range as never)
    const d = ch.axisTagsDrawn as Drawn
    expect(d[d.length - 1]).toMatchObject({ text: '+104.0', y: 104, want: 104 })
    expect(d[d.length - 1].pri).toBeGreaterThan(d.find(t => t.text === '100.0')!.pri)
  })
  it('拖着新建的提醒：不参与让位、不被最新价推开，就画在手上的价位、最后画', () => {
    keyTags.list = []
    const ch = fakeChart({ drag: { kind: 'alert', line: null, price: 103, moved: true } })
    ch.drawPriceLabels(pane as never, range as never)
    const d = ch.axisTagsDrawn as Drawn
    expect(d[d.length - 1]).toMatchObject({ text: '103.0', y: 103 })
    expect(d.filter(t => t.text === '103.0')).toHaveLength(1)
  })
  it('拖着已有的提醒：原位那枚不再画，只画手上那一枚', () => {
    keyTags.list = []
    const line = { price: 250 }
    const ch = fakeChart({ alerts: [line, { price: 320 }], drag: { kind: 'alert', line, price: 101, moved: true } })
    ch.drawPriceLabels(pane as never, range as never)
    const d = ch.axisTagsDrawn as Drawn
    expect(d.find(t => t.text === '250.0')).toBeUndefined()
    expect(d.find(t => t.text === '320.0')?.y).toBe(320)
    expect(d[d.length - 1]).toMatchObject({ text: '101.0', y: 101 })
  })
})

describe('价格轴刻度字在价签排位之后写，和任何一枚价签相交就不写', () => {
  it('最新价、关键价位、悬停「+」、副图指标价签：盖住的刻度全跳过，离得远的照写', () => {
    keyTags.list = [{ y: 240, text: '240.0', bg: '#09c' }]
    const written: number[] = []
    const ch = fakeChart({ axisHoverY: 320, _ranges: { main: range, macd: range } })
    ch.ctx.fillText = (_t: string, _x: number, y: number) => { written.push(y) }
    ch.drawPriceLabels(pane as never, range as never)
    // 副图（macd）上一枚指标价签，y = 50
    ;(ch.axisTagsDrawn as Any[]).push({ pane: 'macd', text: '50', y: 50, want: 50, pri: 1 })
    written.length = 0
    const ticks = [20, 60, 96, 108, 140, 236, 250, 316, 330, 380]
    ch.subFmt = (_id: string, v: number) => String(v)
    ch.drawPriceTicks([{ ...pane, ticks }, { id: 'macd', y: 0, h: 400, ticks: [40, 58, 90] }] as never)
    // 主图：100（最新价）、240（关键价位）、320（「+」）附近的刻度不写
    for (const y of [96, 108, 236, 250, 316, 330]) expect(written.filter(w => w === y)).toHaveLength(0)
    for (const y of [20, 60, 140, 380]) expect(written).toContain(y)
    // 副图：只看本窗格的价签（50 附近的 40 / 58 不写，90 照写），主图的价签不影响副图
    expect(written).not.toContain(40)
    expect(written).not.toContain(58)
    expect(written).toContain(90)
  })
})
