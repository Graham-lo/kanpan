/* 手机网页版壳层：画线提醒对账在启动时就装（m/app/lineAlerts），不等行情页挂上。
 * 2026-10-06 起提醒不依附画线：线删了（本机或别处）提醒照留、照自己的 lines 判；只有线挪了才跟着改。 */
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

describe('启动 → 同步先到 → 行情页后挂载：线删了提醒照留', () => {
  it('首次同步整桶删了 BTC 的 a、ETH 的 e：提醒全留着、还生效、lines 不变；挂上之后再删也一样', async () => {
    const { S, D, L, cloud, ids } = await boot({ BTCUSDT: [['a', 60_000], ['b', 61_000]], ETHUSDT: [['e', 3_000]] })
    S.st.alerts = [lineAlert('BTCUSDT', 'a', 60_000), lineAlert('BTCUSDT', 'b', 61_000), lineAlert('ETHUSDT', 'e', 3_000)]
    const before = structuredClone(S.st.alerts)
    L.startLineAlerts() // main.ts：同步开始之前
    D.replaceDrawings(cloud({ BTCUSDT: [['b', 61_000]], ETHUSDT: [] })) // 首次同步整桶换进来（行情页还在等空闲）
    expect(ids(), '删线不该删提醒').toEqual(['al-a', 'al-b', 'al-e'])
    expect(S.st.alerts, '提醒还生效、几何与上膛时刻都不动').toEqual(before)
    const chartB = await import('../src/m/pages/chart/drawingBench')
    chartB.reconcileLineAlerts('BTCUSDT', []) // 本机在图上删光（onChanged 那条路）
    D.replaceDrawings(cloud({ BTCUSDT: [] }))
    expect(S.st.alerts).toEqual(before)
    // 图上的提醒线照提醒自己的几何给（画哪几条由图按线在不在定，见 m-chart-drawing「提醒线」）
    const sig = chartB.lineAlertSignals('BTCUSDT')
    expect(sig.map(x => [x.id, x.drawingID])).toEqual([['al-a', 'a'], ['al-b', 'b']])
    expect(sig[0].lines).toEqual(before[0].lines)
  })

  it('线删了又回来（撤销 / 别处恢复）且挪了位置：提醒按回来的样子重算、重新上膛', async () => {
    const { S, D, L, cloud } = await boot({ BTCUSDT: [['a', 60_000]] })
    S.st.alerts = [lineAlert('BTCUSDT', 'a', 60_000)]
    L.startLineAlerts()
    D.replaceDrawings(cloud({ BTCUSDT: [] }))
    expect(S.st.alerts[0].armedAt).toBe(1)
    D.replaceDrawings(cloud({ BTCUSDT: [['a', 64_000]] }))
    expect(S.st.alerts[0].lines[0].points[0].p).toBe(64_000)
    expect(S.st.alerts[0].armedAt).toBeGreaterThan(1)
  })

  it('同步把线挪了：行情页没挂也跟着改价位、重新上膛', async () => {
    const { S, D, L, cloud } = await boot({ BTCUSDT: [['b', 61_000]] })
    S.st.alerts = [lineAlert('BTCUSDT', 'b', 61_000)]
    L.startLineAlerts()
    D.replaceDrawings(cloud({ BTCUSDT: [['b', 65_000]] }))
    expect(S.st.alerts[0].lines[0].points[0].p).toBe(65_000)
    expect(S.st.alerts[0].armedAt).toBeGreaterThan(1)
  })

  it('提醒先到、线还没拉到：不动；线到了几何相同也不重新上膛', async () => {
    const { S, D, L, cloud, ids } = await boot({ BTCUSDT: [['old', 59_000]] })
    S.st.alerts = [lineAlert('BTCUSDT', 'late', 62_000)]
    L.startLineAlerts()
    D.replaceDrawings(cloud({ BTCUSDT: [['old', 59_000], ['other', 58_000]] }))
    expect(ids()).toEqual(['al-late'])
    D.replaceDrawings(cloud({ BTCUSDT: [['old', 59_000], ['late', 62_000]] }))
    expect(S.st.alerts[0].armedAt).toBe(1)
    D.replaceDrawings(cloud({ BTCUSDT: [['old', 59_000]] }))
    expect(ids(), '线又被删了，提醒照留').toEqual(['al-late'])
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
    // 点中提醒线开「提醒」表（照 iOS onAlertSignalTap → openAlertHub）
    expect(chartSrc).toMatch(/c\.onSignalTap = [^\n]*openAlertHub/)
  })
})
