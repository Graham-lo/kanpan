import { afterEach, describe, expect, it } from 'vitest'
import { st, tabGuard } from '../src/app/store'
import { checkPrice, fire, forgetPrices, makePriceAlert, onAlertFired } from '../src/alerts/model'
import { conditionPercentOK, fundingHit, judgeFunding, makeConditionAlert, oiChange, FUNDING_WINDOW_MS } from '../src/alerts/shape'

afterEach(() => { tabGuard.reset(); st.alerts = []; forgetPrices() })

describe('条件提醒和服务端 / iOS 同一套判法（深度审查 B 线）', () => {
  it('创建时持仓量能填 0.1%–1000%，资金费率 ±10%（服务端 threshold 0.001–10、rate ±0.1）', () => {
    expect(conditionPercentOK('oi', 25)).toBe(true) // 修前：> 10 一律被拒，提示却说「0.1 到 1000」
    expect(conditionPercentOK('oi', 1000)).toBe(true)
    expect(conditionPercentOK('oi', 0.1)).toBe(true)
    expect(conditionPercentOK('oi', 0.05)).toBe(false)
    expect(conditionPercentOK('oi', 1000.1)).toBe(false)
    expect(conditionPercentOK('oi', NaN)).toBe(false)
    expect(conditionPercentOK('funding', -10)).toBe(true)
    expect(conditionPercentOK('funding', 10.01)).toBe(false)
  })

  const H = 3600e3
  const rows = (pts: [number, number][]): { timestamp: number; sumOpenInterest: string }[] => pts.map(([t, v]) => ({ timestamp: t, sumOpenInterest: String(v) }))
  it('持仓量：最新点与恰好 1 小时前的点比；最新点早于武装时刻不判（建好那一刻不会因为过去一小时的变化当场响）', () => {
    const r = rows(Array.from({ length: 13 }, (_, i) => [10 * H + i * 300e3, 100 + i] as [number, number]))
    const last = 10 * H + 12 * 300e3
    expect(oiChange(r, last - 1)).toBeCloseTo(112 / 100 - 1, 12)
    expect(oiChange(r, last + 1)).toBeNull() // 修前：不看 armedAt，变化够线就当场响
    // 缺 1 小时前那个点（服务端也不判）
    expect(oiChange(r.slice(1), 0)).toBeNull()
    // 乱序也按时间排
    expect(oiChange([...r].reverse(), 0)).toBeCloseTo(0.12, 12)
    // 0 不判
    expect(oiChange(rows([[0, 0], [H, 5]]), 0)).toBeNull()
  })

  it('资金费率：恰好等于阈值算够线；结算那一刻起不算；武装之前不算', () => {
    const r = { type: 'funding', side: 'above', rate: '0.0005' } as const
    const settle = 100 * H
    expect(fundingHit(r, 0.0005, settle, settle - 60e3)).toBe(true) // 修前用 >，恰好等于不响
    expect(fundingHit(r, 0.001, settle, settle)).toBe(false)
    expect(fundingHit(r, 0.001, settle, settle - 60e3, settle - 30e3)).toBe(false)
    expect(fundingHit({ ...r, side: 'below', rate: '-0.0001' }, -0.0001, settle, settle - 60e3)).toBe(true)
  })

  it('资金费率：一次结算只判窗口里第一眼，第一眼没够线后面涨上去也不算；下一次结算重新判', () => {
    const a = makeConditionAlert('BTCUSDT', { type: 'funding', side: 'above', rate: '0.0005' }, { now: 0 })
    const judged = new Map<string, number>()
    const settle = 100 * H
    expect(judgeFunding(a, 0.001, settle, settle - FUNDING_WINDOW_MS - 1, judged)).toBe(false)
    expect(judged.size).toBe(0)
    expect(judgeFunding(a, 0.0004, settle, settle - FUNDING_WINDOW_MS, judged)).toBe(false)
    expect(judgeFunding(a, 0.001, settle, settle - FUNDING_WINDOW_MS + 60e3, judged)).toBe(false) // 修前：窗口里每一口标记价都判，这里就响了
    const next = settle + 8 * H
    expect(judgeFunding(a, 0.000612, next, next - 14 * 60e3, judged)).toBe(true)
  })
})

describe('同一浏览器两页：被比下去的那页不再判提醒', () => {
  it('旧页里那边已经删掉的提醒不会照响、不会再弹一遍通知 / 发一遍 Webhook', () => {
    const a = makePriceAlert('BTCUSDT', 101000, 100000, { now: 1 })
    st.alerts = [a]
    const got: string[] = []
    const off = onAlertFired(f => got.push(f.alert.id))
    tabGuard.touch(1000)
    tabGuard.onForeignWrite(2000) // 另一页更近被人动过并写了盘
    checkPrice('BTCUSDT', 100500, 10)
    checkPrice('BTCUSDT', 101500, 20)
    fire(a, 101500, 101000)
    off()
    expect(got).toEqual([]) // 修前：两页各报一遍
    expect(a.status).toBe('active')
  })
  it('人正在用的那页照常判', () => {
    const a = makePriceAlert('BTCUSDT', 101000, 100000, { now: 1 })
    st.alerts = [a]
    const got: string[] = []
    const off = onAlertFired(f => got.push(f.alert.id))
    checkPrice('BTCUSDT', 100500, 10)
    checkPrice('BTCUSDT', 101500, 20)
    off()
    expect(got).toEqual([a.id])
  })
})
