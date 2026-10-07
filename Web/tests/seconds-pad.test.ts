// 秒线实时段补平（2026-10-07）：没成交的秒补平线、5 秒并出来一样、断流不编、回前台一次补齐、和服务端历史拼接不重复
import { beforeEach, describe, expect, it } from 'vitest'
import * as iv from '../src/chart/intervals'
import { spliceSeconds } from '../src/chart/secondsHistory'

const T0 = 1_700_000_010_000 // 整 15 秒
const tr = (price: number, t: number, sell = false) => ({ symbol: 'BTCUSDT', price, qty: 1, t, sell })
let host: { syms: string[]; core: string[]; resumed: string[] }
beforeEach(() => {
  iv.resetSeconds()
  host = { syms: ['BTCUSDT'], core: ['BTCUSDT'], resumed: [] }
  iv.setSecondsPadHost({ symbols: () => host.syms, keepsWhenHidden: k => host.core.includes(k), resumed: k => { host.resumed.push(k) } })
})
const ts = (iv1 = '1s') => iv.secondBars('BTCUSDT', iv1).map(b => b.t - T0)

describe('秒线补平', () => {
  it('这一秒过完（再等 0.5 秒）没成交：补一根开高低收等于上一根收盘、量 0 的平线', () => {
    iv.reconcileSeconds(T0, true, false)
    iv.feedTrade(tr(100, T0 + 100)); iv.feedTrade(tr(101, T0 + 900))
    expect(iv.padSeconds('BTCUSDT', T0 + 1_400)).toBe(0)      // 第 1 秒还没过完 0.5 秒
    expect(iv.padSeconds('BTCUSDT', T0 + 3_600)).toBe(2)      // 第 1、2 秒都没成交
    const b = iv.secondBars('BTCUSDT', '1s')
    expect(ts()).toEqual([0, 1000, 2000])
    expect(b[1]).toMatchObject({ o: 101, h: 101, l: 101, c: 101, v: 0 })
    expect(iv.padSeconds('BTCUSDT', T0 + 3_600)).toBe(0)      // 不重复补
  })
  it('一笔成交隔了几秒才来：中间的秒先补平再接上；补平的那一秒晚到的成交按真开盘算', () => {
    iv.reconcileSeconds(T0, true, false)
    iv.feedTrade(tr(100, T0 + 10)); iv.feedTrade(tr(105, T0 + 4_200))
    expect(ts()).toEqual([0, 1000, 2000, 3000, 4000])
    iv.padSeconds('BTCUSDT', T0 + 5_600)
    iv.feedTrade(tr(106, T0 + 5_700))                          // 第 5 秒先被补平，成交晚到
    expect(iv.secondBars('BTCUSDT', '1s').at(-1)).toMatchObject({ t: T0 + 5000, o: 106, h: 106, l: 106, c: 106 })
  })
  it('5 秒 / 15 秒由补平后的 1 秒并出来，也没有缺口', () => {
    iv.reconcileSeconds(T0, true, false)
    iv.feedTrade(tr(100, T0 + 10))
    iv.padSeconds('BTCUSDT', T0 + 31_000)
    expect(ts('5s')).toEqual([0, 5000, 10000, 15000, 20000, 25000])
    expect(ts('15s')).toEqual([0, 15000])
    expect(iv.secondBarsSince('BTCUSDT', '5s', T0 + 20_000).map(b => b.t - T0)).toEqual([20000, 25000])
  })
  it('页面在后台睡着（定时器被节流），当前格的逐笔一直在收：回前台一次把睡掉的秒补齐', () => {
    iv.reconcileSeconds(T0, true, false)
    iv.feedTrade(tr(100, T0 + 10))
    iv.reconcileSeconds(T0 + 2_000, true, true)                // 藏到后台：当前格的逐笔是核心流，照收
    iv.reconcileSeconds(T0 + 600_000, true, false)             // 10 分钟后回来
    expect(iv.padSeconds('BTCUSDT', T0 + 600_600)).toBe(599)
    expect(ts().length).toBe(600)
    expect(host.resumed).toEqual([])
  })
  it('非当前格藏到后台逐笔被退订、WS 断开：断掉那段不编平线，恢复后等下一笔真成交再接着补，并让页面重取历史', () => {
    host.syms = ['BTCUSDT', 'ETHUSDT']; host.core = ['ETHUSDT']
    iv.reconcileSeconds(T0, true, false)
    iv.feedTrade(tr(100, T0 + 10))
    iv.reconcileSeconds(T0 + 2_000, true, true)                // 后台：BTC 不是核心流，停补
    expect(iv.padSeconds('BTCUSDT', T0 + 60_000)).toBe(0)
    expect(iv.reconcileSeconds(T0 + 60_000, true, false)).toEqual(['BTCUSDT'])
    expect(iv.padSeconds('BTCUSDT', T0 + 62_000)).toBe(0)      // 最后一根在断流前：不接着编
    iv.feedTrade(tr(110, T0 + 62_100))
    expect(ts()).toEqual([0, 62000])
    expect(iv.padSeconds('BTCUSDT', T0 + 64_600)).toBe(2 - 1)
    iv.reconcileSeconds(T0 + 70_000, false, false)             // WS 断
    expect(iv.padSeconds('BTCUSDT', T0 + 80_000)).toBe(0)
    expect(iv.reconcileSeconds(T0 + 80_000, true, false)).toEqual(['BTCUSDT', 'ETHUSDT'])
  })
  it('刚开始看、还没连上就不算断流：不叫页面重取', () => {
    iv.reconcileSeconds(T0, false, false)
    expect(iv.reconcileSeconds(T0 + 1_000, true, false)).toEqual([])
  })
  it('没在秒级格子里的品种不补', () => {
    host.syms = []
    iv.reconcileSeconds(T0, true, false)
    iv.feedTrade(tr(100, T0 + 10)); iv.feedTrade(tr(100, T0 + 5_010))
    expect(ts()).toEqual([0, 5000])
  })
  it('拼服务端历史：服务端那一秒有真成交、逐笔这边是补出来的平线 → 用服务端的；都有成交以逐笔为准；不重复', () => {
    const hist = [{ t: 0, o: 1, h: 2, l: 1, c: 2, v: 5 }, { t: 1000, o: 2, h: 3, l: 2, c: 3, v: 7 }]
    const live = [{ t: 1000, o: 2, h: 2, l: 2, c: 2, v: 0, bv: 0, tb: 0 }, { t: 2000, o: 3, h: 3, l: 3, c: 3, v: 1 }]
    expect(spliceSeconds(hist, live).map(b => [b.t, b.v])).toEqual([[0, 5], [1000, 7], [2000, 1]])
    const live2 = [{ t: 1000, o: 2, h: 4, l: 2, c: 4, v: 9 }]
    expect(spliceSeconds(hist, live2).map(b => [b.t, b.v])).toEqual([[0, 5], [1000, 9]])
  })
  it('历史拼好后接到逐笔内存里：补平从历史最后一根接着走', () => {
    iv.seedSeconds('BTCUSDT', { t: T0, o: 1, h: 1, l: 1, c: 1, v: 3 })
    expect(iv.padSeconds('BTCUSDT', T0 + 2_600)).toBe(1)
    expect(ts()).toEqual([0, 1000])
  })
})
