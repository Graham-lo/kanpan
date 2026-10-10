// 手机网页 · 「盘口要点」：接口解析（宽进严出）、拼字（数额 / 价位 / 时刻 / 事件句 / 入口条那一句）、半页片段 HTML、
// 首页意图（读后即删、过期作废）与带子落在哪一根。样本取自线上 /v1/market/orderflow/highlights?base=BTC（2026-10-10）。
import { describe, expect, it } from 'vitest'
import { parseHighlights, parseBoard, parseMarketBoard, boardUrl, highlightsUrl, marketBoardUrl } from '../src/highlights/api'
import {
  usd, signedUsd, signedPct, levelPx, bandPx, distText, hhmm, spanText, heldText, agoText, wallStateWord,
  levelSentence, nearestLevel, straddles, levelMeta2, rangeEdgesText, eventSentence, eventTime, stripSentence, boardFact, positionCells, fundingText, flowLabel, pctileText,
} from '../src/highlights/format'
import { bodyHTML, quietState, flowBlockHTML, levelsBlockHTML, positionBlockHTML, eventsBlockHTML } from '../src/m/pages/chart/highlightsSheet'
import { setHighlightIntent, takeHighlightIntent } from '../src/m/pages/chart/highlightIntent'
import { barAt } from '../src/m/chart/highlightBand'
import { HL } from '../src/terms'

const GEN = 1791622872002
const SAMPLE = {
  base: 'BTC', generatedAtMs: GEN, tracked: true, staleMs: null,
  events: [
    { atMs: 1791619541329, distPct: -0.042, id: 'E:wallEaten:2', price: 82780.0, side: 'sell', t: 'wallEaten', usd: 11286439 },
    { atMs: 1791622344873, distPct: -0.041, id: 'E:wallEaten:1', price: 82780.6, side: 'sell', t: 'wallEaten', usd: 16271179 },
    { fromMs: 1791620100000, toMs: 1791621000000, id: 'E:liqWave:1', side: 'long', t: 'liqWave', usd: 18e6, pxPct: -1.1 },
    { id: 'E:bad', t: 'wallEaten' },
  ],
  flow: { rows: [
    { diverge: false, netUsd: 14347223, oiPct: 0.08, pxPct: 0.1, w: '15m' },
    { diverge: false, netUsd: 5663335, oiPct: 0.09, pxPct: 0.07, w: '1h' },
    { diverge: true, netUsd: -161603195, oiPct: 0.92, pxPct: 0.2, w: '4h' },
    { diverge: false, netUsd: 712603138, oiPct: 1.2, pxPct: 1.65, sinceMs: 1791486000000, w: 'range' },
  ] },
  levels: [
    { distPct: -0.45, fillBuyUsd: 7551201394, fillSellUsd: 7838066733, high: 82608.8, id: 'L:14153', liqUsd: 22425674, low: 82279.2, refs: ['dayLow', 'vwap'], side: 'bid', tests: 30, touchMs: [1791428400000, 1791617400000], wallHeldMs: 38081629, wallState: 'live', wallUsd: 98140063 },
    { distPct: 0.27, fillBuyUsd: 3781296389, fillSellUsd: 3602530421, high: 83139.0, id: 'L:14163', liqUsd: 8837321, low: 82939.8, refs: ['dayHigh', 'nope'], side: 'ask', tests: 13, touchMs: [1791378000000, 1791562500000], wallHeldMs: 59993844, wallState: 'reducing', wallUsd: 128272194 },
    { distPct: -0.05, fillBuyUsd: 7089434965, fillSellUsd: 7077506656, high: 82939.8, id: 'L:14158', liqUsd: 0, low: 82608.8, refs: [], side: 'bid', tests: 27, touchMs: [null, 1791622800000], wallHeldMs: 2_880_000, wallState: 'live', wallUsd: 35e6 },
    { id: 'L:bad', low: -1, high: 2, side: 'bid' },
  ],
  position: { funding: { pctile: 5, rate: -1.455e-05 }, oi: { combo: 'oiUpPxUp', pct1h: 3.1, pctile: 88 }, show: true, spotPremium: { pct: 0.05, pctile: 61 } },
  range: { high: 83499.9, highFillUsd: 10705069972, highTests: 9, low: 81386.2, lowFillUsd: 6948333596, lowTests: 4, sinceMs: 1791486000000 },
}

describe('盘口要点 · 接口解析', () => {
  const d = parseHighlights(SAMPLE, 'BTC')!
  it('坏条目整条丢掉、价位按价从高到低、事件按末刻倒序', () => {
    expect(d.levels.map(l => l.id)).toEqual(['L:14163', 'L:14158', 'L:14153'])
    expect(d.events.map(e => e.id)).toEqual(['E:wallEaten:1', 'E:liqWave:1', 'E:wallEaten:2'])
    expect(d.levels[0].refs).toEqual(['dayHigh'])
    expect(d.levels[1].touchMs).toEqual([null, 1791622800000])
    expect(d.flow?.length).toBe(4)
    expect(d.range?.lowTests).toBe(4)
  })
  it('品种对不上 / 缺 tracked 不认；没跟踪的答复照收', () => {
    expect(parseHighlights(SAMPLE, 'ETH')).toBeNull()
    expect(parseHighlights({ ...SAMPLE, tracked: undefined }, 'BTC')).toBeNull()
    const u = parseHighlights({ base: 'AXS', generatedAtMs: 5, tracked: false, staleMs: null, flow: null, range: null, levels: [], position: null, events: [] }, 'AXS')!
    expect(u.tracked).toBe(false)
    expect(u.flow).toBeNull()
  })
  it('首页排行：一只一行、类别与代表那条按种类解析', () => {
    const b = parseBoard({ generatedAtMs: 9, rows: [
      { atMs: 1, base: 'BTC', cat: 'book', changePct: 0.26, count: 9, favorite: true, price: 82747.8, tier: 3, top: { kind: 'level', ...SAMPLE.levels[0] } },
      { atMs: 2, base: 'BTC', cat: 'book', changePct: 0.26, count: 9, favorite: true, price: 82747.8, tier: 3, top: { kind: 'level', ...SAMPLE.levels[0] } },
      { atMs: 3, base: 'ARPA', cat: 'funding', changePct: 6.05, count: 5, favorite: false, price: 0.011915, tier: 7, top: { kind: 'position', funding: { pctile: 0, rate: -0.00050144 }, oi: { combo: 'oiDownPxDown', pct1h: -1.08, pctile: 13 }, show: true, spotPremium: { pct: null, pctile: null } } },
      { atMs: 4, base: 'CAP', cat: 'oi', changePct: 24.74, count: 4, favorite: false, price: 0.09111, tier: 1, top: { atMs: 4, id: 'E:oiJump:4', kind: 'event', pct: -4.98, t: 'oiJump' } },
      { atMs: 5, base: 'X', cat: 'weird', top: { kind: 'event' } },
    ] })!
    expect(b.rows.map(r => r.base)).toEqual(['BTC', 'ARPA', 'CAP'])
    expect(b.rows[1].tier).toBe(3)
    expect(boardFact(b.rows[0])).toBe('下方 <b>82,279</b> 买区 <b>98.1M</b>')
    expect(boardFact(b.rows[1])).toBe('费率 <b>−0.0501%</b> · ↓1')
    expect(boardFact(b.rows[2])).toBe('持仓 5 分钟 <b>−5.0%</b>')
  })
  it('全市场榜单与地址', () => {
    const m = parseMarketBoard({ generatedAtMs: 1, rows: [{ base: 'A', changePct: 3.2, oiUsd: 5e6, price: 1 }, { base: 'B' }] })!
    expect(m.rows.map(r => r.base)).toEqual(['A'])
    expect(boardUrl([])).toBe('/v1/market/orderflow/highlights/board')
    expect(boardUrl(['BTC', 'ETH'])).toBe('/v1/market/orderflow/highlights/board?bases=BTC,ETH')
    expect(highlightsUrl('BTC')).toBe('/v1/market/orderflow/highlights?base=BTC')
    expect(marketBoardUrl('oi', '4h')).toBe('/v1/market/board?kind=oi&window=4h')
  })
})

describe('盘口要点 · 拼字', () => {
  it('数额、带号数额、百分比', () => {
    expect([usd(35e6), usd(12.44e6), usd(120.4e6), usd(1.23e9), usd(950), usd(4.05e3)]).toEqual(['35M', '12.4M', '120M', '1.2B', '950', '4.1K'])
    expect([signedUsd(46e6), signedUsd(-8e6), signedUsd(0)]).toEqual(['+46M', '−8M', '+0'])
    expect([signedPct(1.44), signedPct(-0.5), signedPct(-0.01), signedPct(null)]).toEqual(['+1.4%', '−0.5%', '+0.0%', '—'])
    expect([distText(-0.45), distText(1.25), distText(0.4)]).toEqual(['0.45%', '1.3%', '0.4%'])
    expect([fundingText(0.00045), fundingText(-1.455e-5), fundingText(null)]).toEqual(['0.0450%', '−0.0015%', '—'])
  })
  it('价位约五位有效数字、千分位', () => {
    expect([levelPx(82279.2), levelPx(2.446), levelPx(0.011915), levelPx(612.34)]).toEqual(['82,279', '2.446', '0.011915', '612.34'])
    expect(bandPx(86120, 86180)).toBe('86,120–86,180')
    expect(bandPx(87450, 87450.2)).toBe('87,450')
  })
  it('时刻按北京时间、时段同一小时只写分钟、撑了多久、多久前', () => {
    const t = Date.UTC(2026, 9, 10, 2, 20) // 北京 10:20
    expect(hhmm(t)).toBe('10:20')
    expect(spanText(t, t + 15 * 60_000)).toBe('10:20–35')
    expect(spanText(t, t + 45 * 60_000)).toBe('10:20–11:05')
    expect([heldText(48 * 60_000), heldText(10.4 * 3_600_000), heldText(3.2 * 86_400_000)]).toEqual(['48 分', '10 时', '3 天'])
    expect([agoText(t, t + 30_000), agoText(t, t + 12 * 60_000), agoText(t, t + 3 * 3_600_000)]).toEqual([HL.justNow, '12 分前', '3 小时前'])
  })
  it('墙状态词只有三个；撤单百分比服务端给了才写', () => {
    expect(wallStateWord('live', null)).toBe('挂单中')
    expect(wallStateWord('reducing', null)).toBe('撤单中')
    expect(wallStateWord('reducing', 0.42)).toBe('撤单 42%')
    expect(wallStateWord('broken', null)).toBe('已破')
    expect(wallStateWord(null, null)).toBe('')
  })
  it('价位一句话、最近那条、入口条', () => {
    const d = parseHighlights(SAMPLE, 'BTC')!
    const near = nearestLevel(d.levels)!
    expect(near.id).toBe('L:14158')
    expect(levelSentence(near)).toBe('下方 <b>82,609</b> 买区 <b>35M</b> · 挂 48 分 · 测 27 次')
    expect(stripSentence(d.levels, d.events, d.flow)).toBe(levelSentence(near))
    // 没有价位、有事件：写 1 时净主动；连事件都没有：抓手
    expect(stripSentence([], d.events, d.flow)).toBe('1 时净主动 <b>+5.7M</b>')
    expect(stripSentence([], [], d.flow)).toBeNull()
    const noWall = { ...near, wallUsd: 0, fillBuyUsd: 30e6, fillSellUsd: 18e6, distPct: 1.1, side: 'ask' as const }
    expect(levelSentence(noWall)).toBe('上方 <b>82,609</b> 卖区 吃单 <b>48M</b> · 测 27 次')
  })
  it('价区包住现价：不说上方 / 下方，写「现价内」和整段价区', () => {
    const d = parseHighlights(SAMPLE, 'BTC')!
    const near = nearestLevel(d.levels)!
    const at = { ...near, id: 'L:at', low: 63.405, high: 63.659, distPct: 0.08, side: 'ask' as const, wallUsd: 12e6, wallHeldMs: 9 * 60_000, tests: 0 }
    expect(straddles(at, 63.5)).toBe(true)
    expect(straddles(at, 63.7)).toBe(false)
    expect(straddles({ ...at, distPct: 0 }, null)).toBe(true)
    expect(levelSentence(at, { price: 63.5 })).toBe('现价内 <b>63.405–63.659</b> 卖区 <b>12M</b> · 挂 9 分')
    expect(levelSentence({ ...at, distPct: 0 })).toBe('现价内 <b>63.405–63.659</b> 卖区 <b>12M</b> · 挂 9 分')
    // 入口条：包住现价的那条优先，哪怕别的距离更近
    const far = { ...at, id: 'L:far', low: 63.1, high: 63.2, distPct: -0.01, side: 'bid' as const }
    expect(nearestLevel([far, at], 63.5)!.id).toBe('L:at')
    expect(stripSentence([far, at], [], null, 63.5)).toMatch(/^现价内 /)
    // 首页行（服务端带 price）
    expect(boardFact({ key: 'LTC', atMs: 1, base: 'LTC', cat: 'book', changePct: -1, count: 1, favorite: false, price: 63.5, tier: 3, top: { kind: 'level', ...at } })).toMatch(/^现价内 <b>63.405–63.659<\/b> 卖区/)
  })
  it('关键价位：包住现价的那条紧贴现价线下面，距那格写「现价内」', () => {
    const d = parseHighlights(SAMPLE, 'BTC')!
    const lv = d.levels.map(l => (l.id === 'L:14163' ? { ...l, low: 82650, high: 82750, distPct: 0.02 } : l))
    const h = levelsBlockHTML({ ...d, levels: lv }, 82700, null, GEN)
    const iNow = h.indexOf('class="now"'), iAt = h.indexOf('data-lv="L:14163"')
    expect(iAt).toBeGreaterThan(iNow)
    const row = h.slice(iAt, h.indexOf('</button>', iAt))
    expect(row).toContain('<small>现价内')
    expect(row).not.toContain('距 ')
  })
  it('测 0 次、爆仓 0、挂 0 不写，分隔符不悬空', () => {
    const d = parseHighlights(SAMPLE, 'BTC')!
    const near = nearestLevel(d.levels)!
    const bare = { ...near, tests: 0, liqUsd: 0, wallHeldMs: 0 }
    expect(levelMeta2(bare)).toBe('')
    expect(levelMeta2({ ...bare, liqUsd: 120e3 })).toBe('爆仓 120K')
    expect(levelMeta2({ ...bare, tests: 6 })).toBe('测 6 次')
    expect(levelMeta2({ ...bare, liqUsd: 127e3, tests: 6 })).toBe('爆仓 127K · 测 6 次')
    expect(levelSentence(bare)).toBe('下方 <b>82,609</b> 买区 <b>35M</b>')
    expect(rangeEdgesText({ ...d.range!, lowTests: 0, highTests: 0, lowFillUsd: 47.2e6, highFillUsd: 94.3e6 })).toBe('下沿累计吃单 47.2M ｜ 上沿 94.3M')
    expect(rangeEdgesText({ ...d.range!, lowTests: 2, highTests: 0, lowFillUsd: 47.2e6, highFillUsd: 94.3e6 })).toBe('下沿累计吃单 47.2M · 测 2 次 ｜ 上沿 94.3M')
    const h = levelsBlockHTML({ ...d, levels: d.levels.map(l => ({ ...l, tests: 0, liqUsd: 0, wallHeldMs: 0 })), range: { ...d.range!, lowTests: 0, highTests: 0 } }, 82700, null, GEN)
    expect(h).not.toContain('测 0 次')
    const metas = h.split('class="meta">').slice(1).map(x => x.split('</span>')[0])
    expect(metas.length).toBe(3)
    expect(metas.some(m => m.includes('爆仓'))).toBe(false)
    expect(h).not.toContain('挂 ')
    expect(h).not.toMatch(/· <br>|<br><\/span>|· <\/span>|<span class="meta">[^<]*<br>\s*<\/span>/)
  })
  it('事件句与时刻列', () => {
    const d = parseHighlights(SAMPLE, 'BTC')!
    expect(eventSentence(d.events[0])).toBe('卖墙被吃 <b>16.3M</b> @ 82,781')
    expect(eventSentence(d.events[1])).toBe('多单爆仓 <b>18M</b> · 价格 −1.1%')
    expect(eventTime(d.events[1])).toBe(spanText(1791620100000, 1791621000000))
    expect(eventSentence({ id: 'c', t: 'wallCancel', atMs: 1, price: 86880, usd: 19.6e6, side: 'sell', distPct: 0.05 })).toBe('卖墙撤单 <b>19.6M</b> @ 86,880 · 距价 0.05%')
    expect(eventSentence({ id: 'f', t: 'flowBurst', fromMs: 1, toMs: 2, netUsd: 46e6, pxPct: 1.4 })).toBe('主动买入 <b>+46M</b> · 价格 +1.4%')
    expect(eventSentence({ id: 'b', t: 'levelBroken', atMs: 1, low: 85400, high: 85460, side: 'bid', distPct: -1 })).toBe('买区 85,400–85,460 已破')
  })
  it('流向第一列与三格', () => {
    const d = parseHighlights(SAMPLE, 'BTC')!
    expect(d.flow!.map(r => flowLabel(r, GEN))).toEqual(['15 分', '1 时', '4 时', '区间 38 时'])
    const c = positionCells(d.position!)
    expect(c.map(x => x.value)).toEqual(['+3.1%', '−0.0015%', '+0.05%'])
    expect(c.map(x => x.note)).toEqual(['增仓上涨', '↓5', '↑61'])
  })
  it('30 天百分位写成箭头 + 数字：≥ 50 ↑N、< 50 ↓N，取整夹在 1–100，没有就空', () => {
    expect([pctileText(50), pctileText(49.6), pctileText(49.4), pctileText(99), pctileText(100), pctileText(0), pctileText(1)]).toEqual(['↑50', '↑50', '↓49', '↑99', '↑100', '↓1', '↓1'])
    expect(pctileText(null)).toBe('')
    expect(pctileText(NaN)).toBe('')
    expect([HL.pctileUp, HL.pctileDown]).toEqual(['↑{n}', '↓{n}'])
  })
})

describe('盘口要点 · 半页片段', () => {
  const d = parseHighlights(SAMPLE, 'BTC')!
  it('流向：四行、背离标、第四行加粗、分叉条按方向', () => {
    const h = flowBlockHTML(d, GEN)
    expect(h.match(/class="w/g)?.length).toBe(4)
    expect(h).toContain(`<em class="tag">${HL.diverge}</em>`)
    expect(h).toContain('class="w lg">区间 38 时')
    expect(h).toContain('<i class="d" style="right:50%')
    expect(h).toContain('<b class="down">−162M</b>')
  })
  it('关键价位：上方在现价线之上、下方在之下；展开那条带证据与回图', () => {
    const h = levelsBlockHTML(d, 82700, 'L:14158', GEN)
    const iAsk = h.indexOf('data-lv="L:14163"'), iNow = h.indexOf('class="now"'), iBid = h.indexOf('data-lv="L:14158"')
    expect(iAsk).toBeGreaterThan(0)
    expect(iNow).toBeGreaterThan(iAsk)
    expect(iBid).toBeGreaterThan(iNow)
    expect(h).toContain('现价 82,700')
    expect(h).toContain('区间 <b>81,386–83,500</b> · 已走 38 时')
    expect(h).toContain('下沿累计吃单 6.9B · 测 4 次 ｜ 上沿 10.7B · 测 9 次')
    expect(h.match(/class="lev"/g)?.length).toBe(1)
    expect(h).toContain('data-back="L:14158"')
    expect(h).toContain('<s>墙</s><span><b>35M</b> · 挂 48 分 · 挂单中</span>')
    expect(h).toContain('= 今日高点')
    expect(levelsBlockHTML(d, 82700, null, GEN)).not.toContain('class="lev"')
  })
  it('三格只在 show 时出；事件至多 4 条', () => {
    expect(positionBlockHTML(d)).toContain('↓5')
    expect(positionBlockHTML({ ...d, position: { ...d.position!, show: false } })).toBe('')
    const many = { ...d, events: [...d.events, ...d.events, ...d.events] }
    expect(eventsBlockHTML(many).match(/class="it"/g)?.length).toBe(4)
  })
  it('各状态：骨架 / 取不到 / 未跟踪 / 平静', () => {
    expect(bodyHTML({ kind: 'loading' }, null)).toContain('hl-skel')
    expect(bodyHTML({ kind: 'failed' }, null)).toContain(HL.retry)
    const u = parseHighlights({ base: 'AXS', generatedAtMs: 5, tracked: false, staleMs: null, flow: null, range: null, levels: [], position: null, events: [] }, 'AXS')!
    expect(bodyHTML({ kind: 'data', data: u, price: null, now: 5 }, null)).toContain(HL.untracked)
    const calm = { ...d, levels: [], range: null, events: [] }
    const h = bodyHTML({ kind: 'data', data: calm, price: 1, now: GEN }, null)
    expect(h).toContain(HL.quiet)
    expect(h).toContain('data-blk="flow"')
  })
  it('刚开盯的品种（tracked + observingSinceMs）：价位为空且不到 15 分钟写「观察中 · 约 N 分钟」紧跟流向，不写平静；满 15 分钟才写平静；有价位都不写', () => {
    const MIN = 60_000
    const raw = { ...SAMPLE, levels: [], range: null, events: [], observingSinceMs: GEN - 3 * MIN, partial: true }
    const o = parseHighlights(raw, 'BTC')!
    expect(o.observingSinceMs).toBe(GEN - 3 * MIN)
    expect(o.partial).toBe(true)
    expect(quietState(o, GEN)).toEqual({ kind: 'observing', minutes: 12 })
    const h = bodyHTML({ kind: 'data', data: o, price: 1, now: GEN }, null)
    expect(h).toContain('关键价位与事件观察中 · 约 12 分钟')
    expect(h).not.toContain(HL.quiet)
    expect(h).not.toContain(HL.untracked)
    expect(h.indexOf('hl-quiet obs')).toBeGreaterThan(h.indexOf('data-blk="flow"'))       // 在流向下面
    expect(h.indexOf('hl-quiet obs')).toBeLessThan(h.indexOf('data-blk="position"'))      // 在持仓 · 费率上面
    // 快满 15 分钟：至少写 1 分钟
    expect(quietState(o, GEN - 3 * MIN + 15 * MIN - 1000)).toEqual({ kind: 'observing', minutes: 1 })
    // 满 15 分钟还是什么都没有：平静
    expect(quietState(o, GEN + 12 * MIN)).toEqual({ kind: 'calm' })
    expect(bodyHTML({ kind: 'data', data: o, price: 1, now: GEN + 12 * MIN }, null)).toContain(HL.quiet)
    // 观察中但已经有事件：价位为空仍写观察中；不到 15 分钟有价位 → 都不写
    expect(quietState({ ...o, events: d.events }, GEN)).toEqual({ kind: 'observing', minutes: 12 })
    expect(quietState({ ...o, levels: d.levels }, GEN)).toEqual({ kind: 'none' })
    // 满 15 分钟、没价位但有事件：不写平静
    expect(quietState({ ...o, events: d.events }, GEN + 12 * MIN)).toEqual({ kind: 'none' })
    // 服务端没给开盯时刻（旧服务端）：照旧
    const old = parseHighlights({ ...SAMPLE, levels: [], range: null, events: [] }, 'BTC')!
    expect(old.observingSinceMs).toBeNull()
    expect(quietState(old, GEN)).toEqual({ kind: 'calm' })
    expect(parseHighlights({ ...raw, observingSinceMs: 'x', partial: 1 }, 'BTC')).toMatchObject({ observingSinceMs: null, partial: false })
    // tracked:false 仍走老的「打开后开始观察」
    const u = parseHighlights({ ...raw, tracked: false }, 'BTC')!
    expect(bodyHTML({ kind: 'data', data: u, price: null, now: GEN }, null)).toContain(HL.untracked)
  })
})

describe('首页意图与带子', () => {
  it('同一只、没过期才认领，读后即删', () => {
    setHighlightIntent('BTCUSDT', { kind: 'level', id: 'L:1' }, 1000)
    expect(takeHighlightIntent('ETHUSDT', 1100)).toBeNull()
    expect(takeHighlightIntent('BTCUSDT', 1200)).toEqual({ kind: 'level', id: 'L:1' })
    expect(takeHighlightIntent('BTCUSDT', 1300)).toBeNull()
    setHighlightIntent('BTCUSDT', { kind: 'position' }, 1000)
    expect(takeHighlightIntent('BTCUSDT', 7000)).toBeNull()
  })
  it('带子落在含那一刻的那根', () => {
    const s = { count: 10, step: 900, time: (i: number) => i * 900, index: (t: number) => Math.max(0, Math.min(9, Math.round(t / 900))) }
    expect(barAt(s, 1700)).toBe(1)
    expect(barAt(s, 1800)).toBe(2)
    expect(barAt(s, 99999)).toBe(9)
    expect(barAt({ ...s, count: 0 }, 5)).toBe(-1)
  })
})
