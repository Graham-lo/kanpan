/* 手机网页版壳层：画线提醒对账的「见过的线」基线在启动时就建（m/app/lineAlerts），不等行情页挂上。
 * 行情页是空闲时才挂的；原来基线建在它挂上那一刻，首次同步先到、整桶换了线，那次删线比不出来，
 * 被删线上的提醒留着照响。 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import mainSrc from '../src/m/main.ts?raw'
import chartSrc from '../src/m/pages/chart.ts?raw'

const T = 1_700_000_000_000
class MemStorage {
  m = new Map<string, string>()
  getItem(k: string) { return this.m.has(k) ? this.m.get(k)! : null }
  setItem(k: string, v: string) { this.m.set(k, String(v)) }
  removeItem(k: string) { this.m.delete(k) }
  clear() { this.m.clear() }
  key(i: number) { return [...this.m.keys()][i] ?? null }
  get length() { return this.m.size }
}

const lineAlert = (sym: string, id: string, p: number) => ({
  id: 'al-' + id, kind: 'drawing' as const, market: 'binance/usd_m' as const, symbol: sym,
  lines: [{ points: [{ t: T, p }], extendLeft: true, extendRight: true }], condition: 'touch' as const, status: 'active' as const, once: true,
  armedAt: 1, firedAt: null, firedPrice: null, title: 't', note: null, webhook: null, webhookText: null,
  drawingID: `binance/usd_m/${sym}/${id}`, reviewID: null, dueAt: null, rule: null, created: 1,
})

/** 本机存档里先放好线，再按启动顺序加载模块（drawings.ts 读档 → 壳装对账） */
async function boot(local: Record<string, [string, number][]>) {
  const { DrawArchive, encodeArchive } = await import('../src/m/chart/draw/archive')
  const { decodeDrawing } = await import('../src/m/chart/draw/drawing')
  const hline = (id: string, p: number) => decodeDrawing({ id, kind: 'hline', points: [{ t: T, p }] })!
  const a = new DrawArchive()
  for (const [sym, lines] of Object.entries(local)) a.set('binance/usd_m/' + sym, lines.map(([id, p]) => hline(id, p)))
  const ls = new MemStorage()
  ls.setItem('hkline-m-drawings-v1', JSON.stringify(encodeArchive(a)))
  vi.stubGlobal('localStorage', ls)
  const S = await import('../src/m/app/store')
  const D = await import('../src/m/app/drawings')
  const L = await import('../src/m/app/lineAlerts')
  const cloud = (bySym: Record<string, [string, number][]>) => {
    const next = D.drawingBook.archive.clone()
    for (const [sym, lines] of Object.entries(bySym)) next.set('binance/usd_m/' + sym, lines.map(([id, p]) => hline(id, p)))
    return next
  }
  return { S, D, L, cloud, ids: () => S.st.alerts.map(x => x.id).sort() }
}

beforeEach(() => { vi.resetModules() })
afterEach(() => { vi.unstubAllGlobals() })

describe('启动 → 同步先到 → 行情页后挂载：被删线上的提醒已撤', () => {
  it('首次同步整桶删了 BTC 的 a、ETH 的 e：行情页还没挂，提醒已经撤掉，b 上的留着', async () => {
    const { S, D, L, cloud, ids } = await boot({ BTCUSDT: [['a', 60_000], ['b', 61_000]], ETHUSDT: [['e', 3_000]] })
    S.st.alerts = [lineAlert('BTCUSDT', 'a', 60_000), lineAlert('BTCUSDT', 'b', 61_000), lineAlert('ETHUSDT', 'e', 3_000)]
    L.startLineAlerts() // main.ts：同步开始之前
    D.replaceDrawings(cloud({ BTCUSDT: [['b', 61_000]], ETHUSDT: [] })) // 首次同步整桶换进来（行情页还在等空闲）
    expect(ids(), '同步在行情页挂上之前删的线，提醒留着照响').toEqual(['al-b'])
    // 行情页后挂上：它不再自己建基线 / 订 replaced（否则会重复对账，或拿换过之后的线当「删之前」）
    const chartB = await import('../src/m/pages/chart/drawingBench')
    chartB.reconcileLineAlerts('BTCUSDT', D.drawingBook.items('binance/usd_m/BTCUSDT')) // 挂上后本机 onChanged 那条路
    expect(ids()).toEqual(['al-b'])
    // 挂上之后再来的同步照样对账（壳层订阅一直在）
    D.replaceDrawings(cloud({ BTCUSDT: [] }))
    expect(ids()).toEqual([])
  })

  it('同步把线挪了：行情页没挂也跟着改价位、重新上膛', async () => {
    const { S, D, L, cloud } = await boot({ BTCUSDT: [['b', 61_000]] })
    S.st.alerts = [lineAlert('BTCUSDT', 'b', 61_000)]
    L.startLineAlerts()
    D.replaceDrawings(cloud({ BTCUSDT: [['b', 65_000]] }))
    expect(S.st.alerts[0].lines[0].points[0].p).toBe(65_000)
    expect(S.st.alerts[0].armedAt).toBeGreaterThan(1)
  })

  it('本机没有这条线的来历（提醒先到、线还没拉到）：不当删', async () => {
    const { S, D, L, cloud, ids } = await boot({ BTCUSDT: [['old', 59_000]] })
    S.st.alerts = [lineAlert('BTCUSDT', 'late', 62_000)]
    L.startLineAlerts()
    D.replaceDrawings(cloud({ BTCUSDT: [['old', 59_000], ['other', 58_000]] }))
    expect(ids()).toEqual(['al-late'])
    D.replaceDrawings(cloud({ BTCUSDT: [['old', 59_000], ['late', 62_000]] }))
    D.replaceDrawings(cloud({ BTCUSDT: [['old', 59_000]] }))
    expect(ids(), '见过的线被删了，提醒要撤').toEqual([])
  })

  it('装多次只装一次：一次换线只对账一遍', async () => {
    const { S, D, L, cloud } = await boot({ BTCUSDT: [['b', 61_000]] })
    S.st.alerts = [lineAlert('BTCUSDT', 'b', 61_000)]
    L.startLineAlerts(); L.startLineAlerts()
    let n = 0
    const M = await import('../src/m/model/alerts')
    const off = M.onAlertsChange(() => { n++ })
    D.replaceDrawings(cloud({ BTCUSDT: [['b', 65_000]] }))
    off()
    expect(n).toBe(1)
  })

  it('接线：main.ts 在同步开始之前装对账；行情页不再自己订 replaced、不再挂载时建基线', () => {
    const start = mainSrc.indexOf('startLineAlerts()')
    expect(start).toBeGreaterThan(0)
    expect(start).toBeLessThan(mainSrc.indexOf('initMobileSync()'))
    expect(chartSrc).not.toMatch(/reconcileLineAlertsIn/)
    expect(chartSrc).not.toMatch(/onDrawingsChanged/)
  })
})
