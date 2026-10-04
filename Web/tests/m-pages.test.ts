import { describe, expect, it } from 'vitest'
import type { SymbolPrefs } from '../src/m/app/store'
import * as fav from '../src/m/model/favorites'
import { rank, hot, normalize, splitHighlight, remember, readHistory, forget, HISTORY_LIMIT } from '../src/m/model/search'
import { changePercentText, fmtVol, grouped, priceText, textIsUp } from '../src/m/model/rowText'
import { badgeHTML, coinSpec, assetOf, sectorIconHTML } from '../src/m/model/badge'
import { liuliRowHTML, factsOf, pillHTML } from '../src/m/model/rowHTML'
import * as al from '../src/m/model/alerts'
import type { KV } from '../src/m/model/alerts'

const prefs = (over: Partial<SymbolPrefs> = {}): SymbolPrefs =>
  ({ favorites: [], recents: [], groups: [], groupForSymbol: {}, seeded: true, ...over })
const mem = (): KV & { removeItem(k: string): void } => {
  const m = new Map<string, string>()
  return { getItem: (k: string) => m.get(k) ?? null, setItem: (k: string, v: string) => { m.set(k, v) }, removeItem: (k: string) => { m.delete(k) } }
}
const seed = { accent: '#2E7D6B', dark: false }

describe('手机网页版 · 行上的字', () => {
  it('价格千分位、涨跌用 U+2212、数额 K/M/B/T', () => {
    expect(priceText(104233.5, 1)).toBe('104,233.5')
    expect(priceText(null)).toBe('—')
    expect(changePercentText(-1.234)).toBe('−1.23%')
    expect(changePercentText(0.004)).toBe('+0.00%')
    expect(changePercentText(-0.004)).toBe('+0.00%')
    expect(textIsUp('−1.00%')).toBe(false)
    expect(fmtVol(1_234_000_000)).toBe('1.23B')
    expect(fmtVol(5_600)).toBe('5.60K')
    expect(fmtVol(2.1e12)).toBe('2.10T')
    expect(grouped('-1234567.89')).toBe('-1,234,567.89')
  })
  it('药丸按字面判涨跌，缺值是灰的占位', () => {
    expect(pillHTML(1.5)).toContain('m-pill up')
    expect(pillHTML(-1.5)).toContain('m-pill down')
    expect(pillHTML(null)).toContain('m-pill none')
  })
})

describe('手机网页版 · 徽章', () => {
  it('一个品种一个记号，同一品种两次一样，不同品种不一样', () => {
    const a = badgeHTML('BTC', 32, null, seed), b = badgeHTML('ETH', 32, null, seed), c = badgeHTML('ZZZQ', 32, null, seed)
    expect(a).toBe(badgeHTML('BTC', 32, null, seed))
    expect(a).not.toBe(b)
    expect(c).not.toBe(a)
    expect(a).toContain('width:32px')
  })
  it('贵金属 / 实物商品按事实分类取记号，外汇不算商品', () => {
    expect(assetOf('com', 'XAU')).toBe('preciousMetal')
    expect(assetOf('com', 'CL')).toBe('commodity')
    expect(assetOf('com', 'EURUSD')).toBe(null)
    expect(assetOf('crypto', 'BTC')).toBe(null)
    expect(coinSpec('XAG', 'preciousMetal')).toBeTruthy()
  })
  it('琉璃行带光晕外壳，板块图标认识的 id 画得出记号', () => {
    const html = liuliRowHTML(factsOf('BTCUSDT'), { price: 100000, pct: 1, vol: 1e9 }, true)
    expect(html).toContain('class="m-liuli"')
    expect(html).toContain('lr first')
    expect(html).toContain('成交额 1.00B')
    expect(sectorIconHTML('nope-nope', 32, seed)).toContain('m-sector-icon')
  })
})

describe('手机网页版 · 自选', () => {
  it('加自选落进当前分类；没有分类时按资产类型开第一类', () => {
    const p = prefs()
    fav.addFavorite(p, 'btcusdt', null, { kind: 'crypto', base: 'BTC' })
    expect(p.favorites).toEqual(['BTCUSDT'])
    expect(p.groups.map(g => g.name)).toEqual(['加密'])
    const us = fav.createGroup(p, '美股')!
    fav.addFavorite(p, 'NVDAUSDT', us)
    expect(p.groupForSymbol.NVDAUSDT).toBe(us)
    expect(fav.visible(p, us)).toEqual(['NVDAUSDT'])
  })
  it('顺序永远是用户自己的；只在可见行之间挪，其它分类的位置不动', () => {
    const p = prefs({ favorites: ['A', 'X', 'B', 'C'], groups: [{ id: 'g1', name: '一' }, { id: 'g2', name: '二' }], groupForSymbol: { A: 'g1', X: 'g2', B: 'g1', C: 'g1' } })
    fav.moveVisible(p, ['A', 'B', 'C'], 2, 0)
    expect(p.favorites).toEqual(['C', 'X', 'A', 'B'])
    expect(fav.moveList(['a', 'b', 'c'], 0, 2)).toEqual(['b', 'c', 'a'])
  })
  it('拖动途中同步删掉上面一行、列表还没重画：挪的仍是手里那一只（深度审查 D 线 V-4 网页同款）', () => {
    const groups = [{ id: 'g', name: '加密' }]
    const all = { A: 'g', B: 'g', C: 'g', D: 'g' }
    // 画出来的是 A B C D，同步已把 A 删掉；把 C（第 2 行）拖到第 1 行。
    const p = prefs({ favorites: ['B', 'C', 'D'], groups, groupForSymbol: all })
    fav.moveVisible(p, ['A', 'B', 'C', 'D'], 2, 1)
    expect(p.favorites).toEqual(['C', 'B', 'D'])
    // 拖最后一行 D 到最上：旧写法下标越界，什么也不动。
    const q = prefs({ favorites: ['B', 'C', 'D'], groups, groupForSymbol: all })
    fav.moveVisible(q, ['A', 'B', 'C', 'D'], 3, 0)
    expect(q.favorites).toEqual(['D', 'B', 'C'])
  })
  it('取消后撤销按原位置、原分类插回', () => {
    const p = prefs({ favorites: ['A', 'B', 'C'], groups: [{ id: 'g', name: '加密' }], groupForSymbol: { A: 'g', B: 'g', C: 'g' } })
    const snap = fav.snapshot(p, 'B')!
    fav.removeFavorite(p, 'B')
    expect(p.favorites).toEqual(['A', 'C'])
    fav.restore(p, [snap], 'g')
    expect(p.favorites).toEqual(['A', 'B', 'C'])
    expect(p.groupForSymbol.B).toBe('g')
  })
  it('移到分类：候选是已有分类 + 没开的预设；删分类后成员归进选中的分类', () => {
    const p = prefs({ favorites: ['A'], groups: [{ id: 'g', name: '加密' }], groupForSymbol: { A: 'g' } })
    expect(fav.moveTargets(p)).toEqual(['加密', '美股', '贵金属'])
    const id = fav.assignToCategory(p, ['A'], '贵金属')!
    expect(p.groupForSymbol.A).toBe(id)
    fav.deleteGroup(p, id, 'g')
    expect(p.groupForSymbol.A).toBe('g')
  })
  it('最近打开去重、最新在前、最多 10 条', () => {
    const p = prefs()
    for (let i = 0; i < 12; i++) fav.visit(p, 'S' + i)
    fav.visit(p, 'S5')
    expect(p.recents[0]).toBe('S5')
    expect(p.recents.length).toBe(fav.RECENT_LIMIT)
    expect(new Set(p.recents).size).toBe(p.recents.length)
  })
})

describe('手机网页版 · 搜索', () => {
  const list = [
    { symbol: 'BTCDOMUSDT', vol: 5e6, price: 1 },
    { symbol: 'BTCUSDT', vol: 9e9, price: 100000 },
    { symbol: 'WBTCUSDT', vol: 1e7, price: 100000 },
    { symbol: 'BTCSTUSDT', vol: 9e8, price: null },
  ]
  it('先最匹配，同档按成交额降序，停牌沉底', () => {
    expect(rank(list, 'btc').map(r => r.item.symbol)).toEqual(['BTCUSDT', 'BTCDOMUSDT', 'BTCSTUSDT', 'WBTCUSDT'])
    expect(rank(list, 'b t/c').map(r => r.item.symbol)[0]).toBe('BTCUSDT')
    expect(normalize(' btc/usdt ')).toBe('BTCUSDT')
  })
  it('中文名命中（比特币、大饼）', () => {
    expect(rank(list, '大饼').map(r => r.item.symbol)).toEqual(['BTCUSDT'])
  })
  it('高亮切段；热门按成交额取前十且只要有价的', () => {
    expect(splitHighlight('WBTC', [1, 4])).toEqual([{ text: 'W', hit: false }, { text: 'BTC', hit: true }])
    expect(hot(list).map(s => s.symbol)).toEqual(['BTCUSDT', 'WBTCUSDT', 'BTCDOMUSDT'])
  })
  it('历史：去重、新的在前、有上限、可删', () => {
    const s = mem()
    for (let i = 0; i < 15; i++) remember('T' + i, s)
    remember('T3', s)
    const h = readHistory(s)
    expect(h[0]).toBe('T3')
    expect(h.length).toBe(HISTORY_LIMIT)
    expect(forget('T3', s)).not.toContain('T3')
  })
})

describe('手机网页版 · 提醒', () => {
  it('只响一次：碰到就触发、响完就从表里删掉；建之前看到的价不算', () => {
    al.useStore(mem())
    const a = al.addPriceAlert('BTCUSDT', 101000, 100000, 1, null, 1000)!
    const fired: number[] = []
    const off = al.onAlertFired(f => fired.push(f.price))
    al.checkPrice('BTCUSDT', 100500, 2000)
    al.checkPrice('BTCUSDT', 101200, 3000)
    al.checkPrice('BTCUSDT', 100000, 4000)
    al.checkPrice('BTCUSDT', 101500, 5000)
    off()
    expect(fired).toEqual([101200])
    expect(al.activeAlerts()).toEqual([])
    expect(a.status).toBe('fired')
  })
  it('收盘穿过：盘中插针不算，等这一分钟收了、前后两根收盘价分在线两侧才响（照 iOS AlertEvaluator）', () => {
    al.useStore(mem())
    const M = al.BUCKET_MS
    const a = al.addPriceAlert('BTCUSDT', 101000, 100000, 1, null, 10 * M, 'close')!
    expect(a.condition).toBe('close')
    expect(al.recordMeta(a)).toBe('收盘穿过')
    const fired: number[] = []
    const off = al.onAlertFired(f => fired.push(f.price))
    al.checkPrice('BTCUSDT', 100500, 10 * M + 1)
    al.checkPrice('BTCUSDT', 101500, 10 * M + 20_000) // 盘中穿上去
    al.checkPrice('BTCUSDT', 100800, 10 * M + 50_000) // 又收回来
    al.checkPrice('BTCUSDT', 101200, 11 * M + 1)      // 第 10 根收在 100800：没有上一根，不判
    al.checkPrice('BTCUSDT', 100900, 11 * M + 40_000)
    expect(fired).toEqual([])
    al.checkPrice('BTCUSDT', 101100, 12 * M + 1)      // 第 11 根收在 100900，和 100800 同侧
    expect(fired).toEqual([])
    al.checkPrice('BTCUSDT', 100950, 13 * M + 1)      // 第 12 根收在 101100 ⇒ 穿过
    off()
    expect(fired).toEqual([101100])
    expect(a.status).toBe('fired')
  })
  it('收盘穿过：断线超过 5 根不拿旧收盘价比；正好收在线上算穿、从线上走开不算', () => {
    al.useStore(mem())
    const M = al.BUCKET_MS
    al.addPriceAlert('ETHUSDT', 4000, 3900, 2, null, 0, 'close')
    const fired: number[] = []
    const off = al.onAlertFired(f => fired.push(f.price))
    al.checkPrice('ETHUSDT', 3950, 20 * M)
    al.checkPrice('ETHUSDT', 4050, 30 * M)  // 断了 10 根
    al.checkPrice('ETHUSDT', 4060, 31 * M)  // 第 30 根收了，但上一根作废
    expect(fired).toEqual([])
    off()
    expect(al.crosses(3990, 4000, 4000)).toBe(true)
    expect(al.crosses(4000, 4010, 4000)).toBe(false)
    expect(al.crosses(4010, 3990, 4000)).toBe(true)
  })
  it('价格达到的提醒不走收盘那一套；编辑能换条件', () => {
    al.useStore(mem())
    const M = al.BUCKET_MS
    const a = al.addPriceAlert('BTCUSDT', 101000, 100000, 1, null, 0)!
    expect(al.recordMeta(a)).toBe('价格达到')
    al.updatePriceAlert(a.id, 102000, 100000, 1, null, 5, 'close')
    expect(al.activeAlerts()[0].condition).toBe('close')
    const fired: number[] = []
    const off = al.onAlertFired(f => fired.push(f.price))
    al.checkPrice('BTCUSDT', 101000, M)
    al.checkPrice('BTCUSDT', 102500, M + 10)   // 盘中碰到，但已是收盘穿过
    expect(fired).toEqual([])
    al.checkPrice('BTCUSDT', 102500, 2 * M)
    al.checkPrice('BTCUSDT', 102500, 3 * M)    // 第 1 根收 102500，没有上一根；第 2 根收 102500 同侧
    off()
    expect(fired).toEqual([])
  })
  it('落盘后换个实例读回来；全部预警分价格 / 画线两类、按品种分组', () => {
    const s = mem()
    al.useStore(s)
    al.addPriceAlert('BTCUSDT', 90000, 100000, 1, null, 1)
    al.addPriceAlert('ETHUSDT', 5000, 4000, 2, 'https://example.com/hook', 2)
    al.addPriceAlert('BTCUSDT', 110000, 100000, 1, null, 3)
    al.useStore(s)
    const [price, drawing] = al.sections()
    expect(price.count).toBe(3)
    expect(price.groups.map(g => g.symbol)).toEqual(['BTCUSDT', 'ETHUSDT'])
    expect(drawing.count).toBe(0)
    expect(al.records('BTCUSDT').length).toBe(2)
    expect(al.watchedSymbols().sort()).toEqual(['BTCUSDT', 'ETHUSDT'])
    const del = al.deleteAlert(al.records('ETHUSDT')[0].id)!
    expect(al.liveCount()).toBe(2)
    al.restoreAlert(del)
    expect(al.liveCount()).toBe(3)
  })
  it('行上写价位（千分位）；Webhook 那份 JSON 格式由我们定', () => {
    al.useStore(mem())
    const a = al.addPriceAlert('BTCUSDT', 101000, 100000, 1, 'https://x.y/z', 1)!
    expect(al.recordTitle(a)).toContain('101,000')
    expect(al.direction(a, 100000)).toBe('up')
    const body = al.webhookBody(a, 101001, Date.UTC(2026, 8, 30, 0, 0, 0), 101000)
    expect(body.time).toBe('2026-09-30 08:00:00 UTC+8')
    expect(body.once).toBe(true)
    expect(String(body.text)).toContain('101')
  })
})

describe('手机网页版 · 创建提醒与账号表单', () => {
  it('价格输入：去千分位、全角点，非正数不收；提示行照 iOS hintText', async () => {
    const f = await import('../src/m/model/formText')
    expect(f.parseTarget('101,000.5')).toBe(101000.5)
    expect(f.parseTarget('0.0012')).toBe(0.0012)
    expect(f.parseTarget('1。5')).toBe(1.5)
    expect(f.parseTarget('0')).toBeNull()
    expect(f.parseTarget('abc')).toBeNull()
    expect(f.parseTarget('')).toBeNull()
    expect(f.hintText(null, 100)).toBe('输入一个价格')
    expect(f.hintText(100, null)).toBe('现价 —')
    expect(f.hintText(100.001, 100, 2)).toBe('和现价相同')
    expect(f.hintText(95000, 100000, 1)).toBe('现价 100,000.0 · 低于现价 5.00%')
    expect(f.hintText(110000, 100000, 1)).toBe('现价 100,000.0 · 高于现价 10.00%')
  })
  it('用户名 / 密码规则与服务端一致；设备行写类别 + 本机或上海时间', async () => {
    const f = await import('../src/m/model/formText')
    expect(f.validUsername('abc_1')).toBe(true)
    expect(f.validUsername('Ab')).toBe(false)
    expect(f.validUsername('a-b-c')).toBe(false)
    expect(f.validPassword('abcdefg1')).toBe(true)
    expect(f.validPassword('abcdefgh')).toBe(false)
    expect(f.validPassword('1234567a')).toBe(true)
    // 照 iOS AccountCredentialRules：大写也收、交出去小写，首尾空白不算；全角 / 中文不收
    expect(f.validUsername('  Alice_01 ')).toBe(true)
    expect(f.normalUsername('  Alice_01 ')).toBe('alice_01')
    expect(f.normalUsername('ａｂｃ')).toBeNull()
    expect(f.normalUsername('a'.repeat(33))).toBeNull()
    // 密码下限按码点（一个表情算一个），上限 128 字节
    expect(f.validPassword('a1😀😀😀😀😀😀')).toBe(true)
    expect(f.validPassword('a1😀😀😀😀😀')).toBe(false)
    expect(f.validPassword('a1' + 'x'.repeat(126))).toBe(true)
    expect(f.validPassword('a1' + 'x'.repeat(127))).toBe(false)
    expect(f.USERNAME_RULE).toBe('用户名需 3–32 位字母、数字或下划线')
    expect(f.deviceMeta({ kind: 'phone', current: true, lastSeen: 0 })).toBe('手机 · 本机')
    expect(f.deviceMeta({ kind: 'desktop', current: false, lastSeen: Date.UTC(2026, 8, 28, 6, 5) })).toBe('电脑 · 9月28日 14:05')
  })
  it('编辑提醒：id 与建立时间不变，改价后标题跟着换方向，从此刻重新起算', () => {
    al.useStore(mem())
    const a = al.addPriceAlert('BTCUSDT', 90000, 100000, 1, null, 1)!
    expect(a.title).toContain('跌到')
    const b = al.updatePriceAlert(a.id, 120000, 100000, 1, 'https://x.y/h', 50)!
    expect(b.id).toBe(a.id)
    expect(b.created).toBe(1)
    expect(b.armedAt).toBe(50)
    expect(b.title).toContain('涨到')
    expect(b.webhook).toBe('https://x.y/h')
    expect(al.liveCount()).toBe(1)
    expect(al.updatePriceAlert('nope', 1, 1)).toBeNull()
  })
})

describe('手机网页版 · 账号行的同步状态', () => {
  it('照 iOS MePage.syncMeta：出错说错误、有没推的报几项、推完报多久以前', async () => {
    const m = await import('../src/m/model/syncStatus')
    const now = 1_000_000_000
    expect(m.syncMeta({ error: '', pending: 0, lastSync: null }, now)).toBe('尚未同步')
    expect(m.syncMeta({ error: '', pending: 3, lastSync: now }, now)).toBe('待同步 3 项')
    expect(m.syncMeta({ error: '登录过期，请重新登录', pending: 3, lastSync: now }, now)).toBe('登录过期，请重新登录')
    expect(m.syncMeta({ error: '', pending: 0, lastSync: now - 30_000 }, now)).toBe('已同步')
    expect(m.syncMeta({ error: '', pending: 0, lastSync: now - 5 * 60_000 }, now)).toBe('上次 5 分钟前')
    expect(m.syncMeta({ error: '', pending: 0, lastSync: now - 2 * 3_600_000 }, now)).toBe('上次 2 小时前')
    expect(m.syncMeta({ error: '', pending: 0, lastSync: now - 3 * 86_400_000 }, now)).toBe('上次 3 天前')
  })
  it('占位可以换成真的来源；换了会通知重画', async () => {
    const m = await import('../src/m/model/syncStatus')
    expect(m.syncIsPlaceholder()).toBe(true)
    let redraw = 0, pushed = 0
    const off = m.onSyncChange(() => redraw++)
    m.setSyncSource({ state: () => ({ error: '', pending: 1, lastSync: null }), syncNow: () => { pushed++ }, onChange: () => () => {} })
    expect(redraw).toBe(1)
    expect(m.syncMeta(m.syncSource().state())).toBe('待同步 1 项')
    m.syncSource().syncNow()
    expect(pushed).toBe(1)
    m.setSyncSource(null)
    expect(m.syncIsPlaceholder()).toBe(true)
    off()
  })
})
