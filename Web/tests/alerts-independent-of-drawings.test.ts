/* 2026-10-06 用户：「画线和警报是不冲突的，我删除画线也不应该删除警报才对」「即使画线删除也应该保留预警信号啊」。
 * 电脑网页这一侧：线删了提醒照留、照自己的 lines 判；线挪了提醒跟上、从此刻起算；老版本留下的暂停态复活；
 * 图上由「提醒线」（虚线 + 铃铛，按提醒自己的几何）指出位置——线在、画出来了就不画。 */
import { describe, expect, it, vi } from 'vitest'

vi.mock('../src/market/rest', () => ({ klines: vi.fn(async () => ({ ok: false, bars: [] })) }))

const { st } = await import('../src/app/store')
const { reconcileDrawingAlerts, makeDrawingAlert, drawingIdOf } = await import('../src/alerts/model')
const { migrateAlert } = await import('../src/alerts/shape')
const { TVChart } = await import('../src/chart/chart')
type Drawing = import('../src/chart/chart').Drawing
type AlertSignal = import('../src/chart/chart').AlertSignal
type Any = Record<string, unknown>

const T = 1_700_006_400_000, H = 36e5
const hline = (id: string, p: number): Drawing => ({ id, type: 'hline', pts: [{ t: T, p }] })

describe('画线删了提醒照留（电脑网页 reconcileDrawingAlerts）', () => {
  it('线删了：提醒还是 active、lines 原样不动、不删', () => {
    const a = makeDrawingAlert('BTCUSDT', hline('L1', 100), 5)
    st.alerts = [a]
    const before = JSON.stringify(a.lines)
    reconcileDrawingAlerts('BTCUSDT', [])
    expect(st.alerts).toHaveLength(1)
    expect(st.alerts[0].status).toBe('active')
    expect(JSON.stringify(st.alerts[0].lines)).toBe(before)
    expect(st.alerts[0].armedAt).toBe(5)
  })

  it('线挪了：提醒的几何跟上、从此刻起算', () => {
    const a = makeDrawingAlert('BTCUSDT', hline('L1', 100), 5)
    st.alerts = [a]
    reconcileDrawingAlerts('BTCUSDT', [hline('L1', 120)])
    expect(st.alerts[0].lines[0].points[0].p).toBe(120)
    expect(st.alerts[0].armedAt).toBeGreaterThan(5)
  })

  it('老版本「缺线暂停」留下的画线提醒：对账时复活成 active，线不在也不删', () => {
    const a = { ...makeDrawingAlert('BTCUSDT', hline('L1', 100), 5), status: 'paused' as const }
    st.alerts = [a]
    reconcileDrawingAlerts('BTCUSDT', [])
    expect(st.alerts).toHaveLength(1)
    expect(st.alerts[0].status).toBe('active')
    expect(st.alerts[0].armedAt).toBeGreaterThan(5)
  })

  it('载入时（migrateAlert）暂停态画线提醒复活；价格提醒的状态不动', () => {
    const a = { ...makeDrawingAlert('BTCUSDT', hline('L1', 100), 5), status: 'paused' as const }
    const m = migrateAlert(JSON.parse(JSON.stringify(a)))!
    expect(m.status).toBe('active')
    expect(m.armedAt).toBeGreaterThan(5)
    expect(m.lines).toEqual(a.lines)
    expect(m.drawingID).toBe(drawingIdOf('BTCUSDT', 'L1'))
  })
})

describe('电脑网页图上的提醒线', () => {
  const bars = Array.from({ length: 10 }, (_, k) => ({ t: T + k * H, o: 100, h: 110, l: 90, c: 100, v: 1 }))
  const sig: AlertSignal = { id: 'al-1', drawingID: 'L1', lines: [{ points: [{ t: T, p: 100 }], extendLeft: true, extendRight: true }] }
  const fake = (fields: Any) => Object.assign(Object.create(TVChart.prototype), {
    w: 660, aw: 60, rightBar: 9, spacing: 20, bars, iv: H, log: false, compare: [], drawings: [hline('L1', 100)],
    drawingsHidden: false, alertSignals: [sig], ...fields,
  }) as InstanceType<typeof TVChart>

  it('线在、画出来了：不画；线删了：渲染数据里多出一条提醒线', () => {
    expect(fake({}).signalsShown()).toEqual([])
    expect(fake({ drawings: [] }).signalsShown().map(s => s.id)).toEqual(['al-1'])
  })

  it('「隐藏画线」开着：线在也画提醒线；对比态（百分比轴）不画', () => {
    expect(fake({ drawingsHidden: true }).signalsShown().map(s => s.id)).toEqual(['al-1'])
    expect(fake({ drawingsHidden: true, compare: [{ symbol: 'ETHUSDT' }] }).signalsShown()).toEqual([])
  })

  it('两端无限延的水平提醒线铺满图区、高度就是那个价；真的描了一笔虚线和一枚铃铛', () => {
    const calls: string[] = []
    const ctx = new Proxy({} as Any, {
      get(o, k: string) { return k in o ? o[k] : (..._a: unknown[]) => { calls.push(k) } },
      set(o, k: string, v) { o[k] = v; return true },
    })
    const ch = fake({ drawings: [], ctx, colors: { alert: '#f90' } })
    const pane = { id: 'main', y: 0, h: 400 } as never, r = { min: 90, max: 110 } as never
    const path = ch.signalPath(sig.lines[0], pane, r)
    expect(path[0].x).toBe(0)
    expect(path[path.length - 1].x).toBe(600)
    for (const q of path) expect(q.y).toBeCloseTo(ch.priceToY(100, pane, r), 6)
    ch.drawAlertSignals(pane, r)
    expect(calls.filter(k => k === 'stroke').length).toBeGreaterThanOrEqual(1)
    expect(calls.filter(k => k === 'fill').length).toBeGreaterThanOrEqual(2) // 铃铛的钟罩与锤子
  })
})
