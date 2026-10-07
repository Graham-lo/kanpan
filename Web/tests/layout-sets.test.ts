import { describe, expect, it } from 'vitest'
import {
  cleanBook, cleanName, bookFrom, deleteLayout, liveBook, mergeBooks, migrateLegacyFootprint, renameLayout, saveAsLayout,
  switchLayout, uniqueName, MAX_LAYOUTS, NAME_MAX, type CellCfg, type LayoutBook, type LiveLayout,
} from '../src/app/layouts'
import { hydrate } from '../src/app/store'
import { decodeSetting, encodeSetting, encodeSettings, factorySettings, putSetting, seenWhenUndecodable, webSetting, SETTINGS_FIELDS, type SettingsState } from '../src/sync/codec'
import { OWNED, adoptBook, applyInto, captureInto, corePrint, layoutsPrint, mergeFirst, type Prints, type WebState } from '../src/sync/bridge'
import { footprintOn, setFootprint, setFootprintSource } from '../src/chart/footprint'
import { Engine } from '../src/sync/engine'
import { SyncStore } from '../src/sync/store'
import { emptyArchive, type Json } from '../src/sync/types'
import { FakeServer, ctx } from './sync-fake'

const cells16 = (): CellCfg[] => ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XAUUSDT', 'BNBUSDT', 'XRPUSDT', 'DOGEUSDT', 'NVDAUSDT', 'ADAUSDT', 'LINKUSDT', 'AVAXUSDT', 'SUIUSDT', 'XAGUSDT', 'TSLAUSDT', 'LTCUSDT', 'TRXUSDT'].map(symbol => ({ symbol, iv: '15m' }))
/** 两套：默认（一图 BTC 1 小时）+ 「盯盘」（十六图 15 分，当前）——照用户的做法：另存一套，再在新那套里改成十六图 */
function two(): LiveLayout {
  const s: LiveLayout = { layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '1h' }], active: 0, layouts: bookFrom('1', [{ symbol: 'BTCUSDT', iv: '1h' }]) }
  saveAsLayout(s, '盯盘', 'watch16')
  s.layout = '16'; s.cells = cells16(); s.active = 5
  return s
}
const asWeb = (live: LiveLayout): WebState => ({ ...hydrate({}), ...live } as unknown as WebState)

describe('布局集：编码规范形', () => {
  it('坏输入返回 null；id 重复的后一个丢掉；空名给「未命名」；当前那套不存在回第一套', () => {
    expect(cleanBook(null)).toBeNull()
    expect(cleanBook({ active: 'x', sets: [] })).toBeNull()
    expect(cleanBook({ active: 'x', sets: [{ id: 'bad id!', name: 'a', layout: '1', cells: [] }] })).toBeNull()
    const b = cleanBook({
      active: 'nope',
      sets: [
        { id: 'a', name: '  日内\n盯盘  ', layout: 4, cells: [{ symbol: 'ETHUSDT', iv: '5m' }] },
        { id: 'a', name: '重复', layout: '1', cells: [] },
        { id: 'b', name: '   ', layout: '99', cells: [{ symbol: 'SOLUSDT', iv: 'nope', footprint: true, hue: 'x', 'bad key': 1 }] },
      ],
    })!
    expect(b.active).toBe('a')
    expect(b.sets.map(x => x.id)).toEqual(['a', 'b'])
    expect(b.sets[0].name).toBe('日内 盯盘')
    expect(b.sets[0].layout).toBe('4')
    expect(b.sets[0].cells).toEqual([{ symbol: 'ETHUSDT', iv: '5m' }])
    expect(b.sets[1]).toMatchObject({ name: '未命名', layout: '1' })
    // 认不出的周期回 1 小时；足迹与以后的短键原样留着，不合规的键丢掉
    expect(b.sets[1].cells[0]).toEqual({ symbol: 'SOLUSDT', iv: '1h', footprint: true, hue: 'x' })
  })

  it(`最多 ${MAX_LAYOUTS} 套、名字最多 ${NAME_MAX} 个字、格子最多 16 格，洞补上`, () => {
    const many = Array.from({ length: 30 }, (_, i) => ({ id: 's' + i, name: '套'.repeat(40), layout: '16', cells: [{ symbol: 'BTCUSDT', iv: '1h' }, null, ...cells16()] }))
    const b = cleanBook({ active: 's25', sets: many })!
    expect(b.sets).toHaveLength(MAX_LAYOUTS)
    expect(b.active).toBe('s0')
    expect([...b.sets[0].name]).toHaveLength(NAME_MAX)
    expect(b.sets[0].cells).toHaveLength(16)
    expect(b.sets[0].cells[1].symbol).toMatch(/USDT$/)
    expect(cleanName('a b\u0000c')).toBe('a b c')
  })

  it('同步字段：编码、解码都是规范形；坏的解不出来', () => {
    const raw = { active: 'a', sets: [{ id: 'a', name: '默认', layout: '2', cells: [{ symbol: 'BTCUSDT', iv: '4h', footprint: true }, { symbol: 'ETHUSDT', iv: '4h' }] }] }
    expect(encodeSetting('chartLayouts', raw as unknown as Json, undefined)).toEqual(raw)
    const s = hydrate({}) as unknown as SettingsState
    expect(decodeSetting('chartLayouts', raw as unknown as Json, s)).toEqual(raw)
    expect(decodeSetting('chartLayouts', { sets: 'nope' } as unknown as Json, s)).toBeUndefined()
    expect(SETTINGS_FIELDS).toContain('chartLayouts')
  })
})

describe('布局集：旧数据迁移', () => {
  it('老存档只有 layout + cells：原样迁成一套「默认」（id default），格子一格不丢', () => {
    const cells = [{ symbol: 'ETHUSDT', iv: '15m' }, { symbol: 'SOLUSDT', iv: '15m' }, { symbol: 'XAUUSDT', iv: '15m' }, { symbol: 'NVDAUSDT', iv: '15m' }]
    const s = hydrate({ layout: '4', cells, active: 2 })
    expect(s.layouts.active).toBe('default')
    expect(s.layouts.sets).toEqual([{ id: 'default', name: '默认', layout: '4', cells }])
    expect(s.layout).toBe('4')
    expect(s.cells).toEqual(cells)
    expect(s.active).toBe(2)
  })

  it('有布局集也有活数据：活数据（最后一次 save 写下的）为准抄回当前那套', () => {
    const book: LayoutBook = { active: 'b', sets: [{ id: 'a', name: '默认', layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '1h' }] }, { id: 'b', name: '四图', layout: '4', cells: cells16().slice(0, 4) }] }
    const live = cells16().slice(0, 4).map(c => ({ ...c, iv: '1d' }))
    const s = hydrate({ layouts: book, layout: '4', cells: live })
    expect(s.layouts.sets[1].cells).toEqual(live)
    expect(s.layouts.sets[0].cells).toEqual([{ symbol: 'BTCUSDT', iv: '1h' }])
  })

  it('只有布局集没有活数据：从当前那套装活数据', () => {
    const book: LayoutBook = { active: 'b', sets: [{ id: 'a', name: '默认', layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '1h' }] }, { id: 'b', name: '四图', layout: '4', cells: cells16().slice(0, 4) }] }
    const s = hydrate({ layouts: book })
    expect(s.layout).toBe('4')
    expect(s.cells).toEqual(cells16().slice(0, 4))
  })

  it('出厂：一套「默认」一图 BTC 1 小时，和同步的出厂设置一致', () => {
    const s = hydrate({})
    expect(s.layouts).toEqual(bookFrom('1', [{ symbol: 'BTCUSDT', iv: '1h' }]))
    expect(s.layouts).toEqual(factorySettings().layouts)
  })
})

describe('布局集：切换、另存、改名、删除', () => {
  it('另存为：当前活数据存成新的一套、排在当前那套后面并切过去；切来切去各自的格子都在', () => {
    const s = two()
    // 活数据要到 save()（commitLive）才抄回那一套：liveBook 是同步看到的样子
    expect(liveBook(s).sets.map(x => [x.id, x.name, x.layout])).toEqual([['default', '默认', '1'], ['watch16', '盯盘', '16']])
    expect(s.layouts.active).toBe('watch16')
    expect(switchLayout(s, 'default')).toBe(true)
    expect(s.layout).toBe('1')
    expect(s.cells).toEqual([{ symbol: 'BTCUSDT', iv: '1h' }])
    expect(s.active).toBe(0)
    // 在默认里改周期 → 切走再切回来还在
    s.cells[0].iv = '4h'
    switchLayout(s, 'watch16')
    expect(s.cells).toHaveLength(16)
    expect(s.cells[3]).toEqual({ symbol: 'XAUUSDT', iv: '15m' })
    switchLayout(s, 'default')
    expect(s.cells[0].iv).toBe('4h')
    expect(switchLayout(s, 'default')).toBe(false)
    expect(switchLayout(s, 'nope')).toBe(false)
  })

  it('另存为撞名自动加序号；满 20 套返回 null', () => {
    const s = two()
    expect(saveAsLayout(s, '盯盘')!.name).toBe('盯盘 2')
    expect(uniqueName(s.layouts, '盯盘')).toBe('盯盘 3')
    while (s.layouts.sets.length < MAX_LAYOUTS) saveAsLayout(s, 'x')
    expect(saveAsLayout(s, '再来一套')).toBeNull()
    expect(new Set(s.layouts.sets.map(x => x.id)).size).toBe(MAX_LAYOUTS)
    expect(new Set(s.layouts.sets.map(x => x.name)).size).toBe(MAX_LAYOUTS)
  })

  it('改名：空名不改；和别的套撞名加序号；和自己同名不算改', () => {
    const s = two()
    expect(renameLayout(s.layouts, 'watch16', '  ')).toBeNull()
    expect(renameLayout(s.layouts, 'watch16', '盯盘')).toBeNull()
    expect(renameLayout(s.layouts, 'watch16', '默认')).toBe('默认 2')
    expect(renameLayout(s.layouts, 'watch16', '十六图 美股')).toBe('十六图 美股')
    expect(s.layouts.sets[1].name).toBe('十六图 美股')
  })

  it('删除：最后一套不删；删当前那套切到它后面那套（没有就前面那套）；删别的那套不动当前活数据', () => {
    const s = two()
    s.cells[0].iv = '1d'
    expect(deleteLayout(s, 'default')).toBe(true)
    expect(s.layouts.sets.map(x => x.id)).toEqual(['watch16'])
    expect(s.cells[0].iv).toBe('1d')
    expect(deleteLayout(s, 'watch16')).toBe(false)
    const t = two()
    expect(deleteLayout(t, 'watch16')).toBe(true)
    expect(t.layouts.active).toBe('default')
    expect(t.layout).toBe('1')
    expect(t.cells).toEqual([{ symbol: 'BTCUSDT', iv: '1h' }])
  })

  it('同步拿到的是「活数据抄回之后」的整个布局集（不改状态）', () => {
    const s = two()
    s.cells[0] = { symbol: 'PAXGUSDT', iv: '15m' }
    const b = liveBook(s)
    expect(b.sets[1].cells[0].symbol).toBe('PAXGUSDT')
    expect(s.layouts.sets[1].cells[0].symbol).toBe('BTCUSDT')
  })
})

describe('布局集：和云端对上', () => {
  it('合并：以一边为准，另一边多出来的几套接在后面，撞名带「（本机）」；一样的、出厂那套不接', () => {
    const cloud: LayoutBook = { active: 'c1', sets: [{ id: 'c1', name: '盯盘', layout: '4', cells: cells16().slice(0, 4) }] }
    const local: LayoutBook = { active: 'default', sets: [
      { id: 'default', name: '默认', layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '1h' }] },
      { id: 'c1', name: '盯盘', layout: '2', cells: cells16().slice(0, 2) },
      { id: 'same', name: '另一个名', layout: '4', cells: cells16().slice(0, 4) },
    ] }
    const m = mergeBooks(cloud, local)
    expect(m.active).toBe('c1')
    expect(m.sets.map(x => x.name)).toEqual(['盯盘', '盯盘（本机）'])
    expect(m.sets[1].id).not.toBe('c1')
    expect(m.sets[1].layout).toBe('2')
  })

  it('adoptBook：云端没有 → seen 记 null（本机这份要推）；replace 整份用云端的；cloud 以云端为准并接上本机的', () => {
    const s = asWeb(two())
    const seen: Record<string, Json> = {}
    expect(adoptBook(s, undefined, seen, 'cloud')).toEqual([])
    expect(seen.chartLayouts).toBeNull()
    expect(seenWhenUndecodable(s as unknown as SettingsState, 'chartLayouts', undefined)).toBeNull()
    const cloud = { active: 'c', sets: [{ id: 'c', name: '云上', layout: '2', cells: cells16().slice(0, 2) }] } as unknown as Json
    const r = asWeb(two())
    expect(adoptBook(r, cloud, {}, 'replace')).toEqual(['chartLayouts'])
    expect(r.layouts!.sets.map(x => x.name)).toEqual(['云上'])
    expect(r.layout).toBe('2')
    const c = asWeb(two())
    adoptBook(c, cloud, {}, 'cloud')
    expect(c.layouts!.sets.map(x => x.name)).toEqual(['云上', '盯盘'])
    expect(c.layouts!.active).toBe('c')
    expect(c.cells).toHaveLength(2)
  })

  it('指纹分两份：改布局只动 layoutsPrint，改指标只动 corePrint', () => {
    const s = asWeb(two())
    const core = corePrint(s), lays = layoutsPrint(s)
    s.cells![0].iv = '1w'
    expect(corePrint(s)).toBe(core)
    expect(layoutsPrint(s)).not.toBe(lays)
    s.ind.ema = !s.ind.ema
    expect(corePrint(s)).not.toBe(core)
  })

  it('putSetting 装云端的布局集：活数据跟着换成当前那套', () => {
    const s = hydrate({}) as unknown as SettingsState
    putSetting(s, 'chartLayouts', { active: 'b', sets: [{ id: 'a', name: '默认', layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '1h' }] }, { id: 'b', name: '四', layout: '4', cells: cells16().slice(0, 4) }] } as unknown as Json)
    expect(s.layout).toBe('4')
    expect(s.cells).toHaveLength(4)
    expect((webSetting(s, 'chartLayouts') as unknown as LayoutBook).active).toBe('b')
  })

  it('两台电脑：A 存的两套布局（含足迹开关）同步到 B，B 切换后改的格子再回到 A', async () => {
    const server = new FakeServer()
    const a = browser(server, two())
    a.s.cells![2].footprint = true
    await a.first({ settings: 0, favorites: 0, layouts: Date.now() })
    const pushed = server.objects.get('settings:chart')?.body.chartLayouts as unknown as LayoutBook
    expect(pushed.sets.map(x => x.name)).toEqual(['默认', '盯盘'])
    expect(pushed.sets[1].cells[2].footprint).toBe(true)
    const b = browser(server)
    await b.first()
    expect(b.s.layouts!.sets.map(x => x.name)).toEqual(['默认', '盯盘'])
    expect(b.s.layout).toBe('16')
    expect(b.s.cells![2]).toEqual({ symbol: 'SOLUSDT', iv: '15m', footprint: true })
    // B 切回「默认」改成 4 小时
    switchLayout(b.s as unknown as LiveLayout, 'default')
    b.s.cells![0].iv = '4h'
    await b.sync()
    await a.sync()
    expect(a.s.layouts!.active).toBe('default')
    expect(a.s.cells).toEqual([{ symbol: 'BTCUSDT', iv: '4h' }])
    expect(a.s.layouts!.sets[1].cells[2].footprint).toBe(true)
  })
})

describe('足迹开关跟人走', () => {
  it('老存法（localStorage 一串格子序号）并进格子配置：越界、坏数据不并', () => {
    const s = { cells: [{ symbol: 'BTCUSDT', iv: '1h' }, { symbol: 'ETHUSDT', iv: '1h' }, { symbol: 'SOLUSDT', iv: '1h', footprint: true }] as CellCfg[] }
    expect(migrateLegacyFootprint(s, '[0,2,7,-1,"x",1.5]')).toBe(1)
    expect(s.cells.map(c => c.footprint === true)).toEqual([true, false, true])
    expect(migrateLegacyFootprint(s, 'not json')).toBe(0)
    expect(migrateLegacyFootprint(s, '{"0":true}')).toBe(0)
    expect(migrateLegacyFootprint(s, null)).toBe(0)
  })

  it('开关写进格子配置（图表页接上的来源），切布局时跟着那一套走', () => {
    const s = two()
    let saved = 0
    setFootprintSource({ on: i => s.cells[i]?.footprint === true, set: (i, on) => { const c = s.cells[i]; if (!c) return; if (on) c.footprint = true; else delete c.footprint; saved++ } })
    try {
      setFootprint(3, true)
      expect(footprintOn(3)).toBe(true)
      expect(s.cells[3]).toEqual({ symbol: 'XAUUSDT', iv: '15m', footprint: true })
      expect(saved).toBe(1)
      switchLayout(s, 'default')
      expect(footprintOn(3)).toBe(false)
      switchLayout(s, 'watch16')
      expect(footprintOn(3)).toBe(true)
      setFootprint(3, false)
      expect('footprint' in s.cells[3]).toBe(false)
    } finally { setFootprintSource(null) }
  })

  it('格子配置里的足迹进同步；关着的不带键', () => {
    const s = hydrate({ layout: '2', cells: [{ symbol: 'BTCUSDT', iv: '1h', footprint: true }, { symbol: 'ETHUSDT', iv: '1h', footprint: false }] })
    expect(s.cells).toEqual([{ symbol: 'BTCUSDT', iv: '1h', footprint: true }, { symbol: 'ETHUSDT', iv: '1h' }])
    const o = encodeSettings(s as unknown as SettingsState, undefined, {})!
    expect((o.body.chartLayouts as unknown as LayoutBook).sets[0].cells[0].footprint).toBe(true)
  })
})

/** 一台「网页」：页面状态 + 账本 + 引擎，接同一个假服务端（照 sync-bridge.test.ts） */
function browser(server: FakeServer, live?: LiveLayout) {
  const s = { ...hydrate({}), watch: { crypto: ['BTCUSDT'], us: [], idx: [], com: [] }, drawings: {}, alerts: [], ...(live ?? {}) } as unknown as WebState
  const store = new SyncStore(emptyArchive(), 'dev-' + Math.random(), () => server.now)
  const fp: Prints = {}
  let initial = true
  const engine = new Engine(store, server.transport(), OWNED, {
    capture: () => { if (!initial) captureInto(s, store, ctx, fp) },
    apply: () => { if (!initial) applyInto(s, store, ctx) },
  })
  return {
    s,
    async first(edited: { settings: number; favorites: number; layouts?: number } = { settings: 0, favorites: 0 }) {
      await engine.full()
      mergeFirst(s, store, ctx, edited, false)
      initial = false
      captureInto(s, store, ctx, fp)
      await engine.push()
    },
    async sync() { await engine.push(); await engine.pull(); await engine.push() },
  }
}
