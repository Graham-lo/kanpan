// 手机网页版审查（指标）：与 iOS 逐位交叉验证。
//
// 2026-09-30 审查时写了一个 Swift 小程序，直接链接 KanpanCore/Sources/KanpanCore/Indicator/*.swift
// 与 Model/*（swiftc -O），用下面同一个 LCG 造 9 种场景，跑 IndicatorEngine.ensure 全量算出
// 14 把 K 线指标的每条线、MACD 柱、方向列，再把每把指标的输出按 float64 位模式做 FNV-1a 摘要。
// 这里用同一个生成器在 TS 里重造输入（先比输入摘要，保证喂的是同一份数），跑 TS 引擎，
// 摘要必须一字不差——容差 0，NaN 位置、±0、±Infinity 都算在内。
//
// 这补上了 m-indicator.test.ts 里没有黄金值的几把（VWAP、超级趋势、抛物线转向、DMI、CVD）
// 与脏场景（1e-8 价 / 1e12 量、全同价零成交、真实日历月 + 0 / 负数参数、周线缺口、
// 单根 / 两根、收盘与最高价夹 NaN、主动买量夹 NaN）。
//
// 改了任一指标的算法，iOS 那边若同步改了，需要重跑 Swift 程序更新下面的摘要；
// 若只改了 TS，这条红就是移植偏差。
import { describe, expect, it } from 'vitest'
import { BarSeries } from '../src/m/chart/series'
import type { Interval } from '../src/m/chart/series'
import { IndicatorEngine } from '../src/m/indicator/engine'
import type { IndicatorID, IndicatorResult } from '../src/m/indicator/ids'

// ------------------------------------------------------------------ Swift 那边的生成器

const M64 = (1n << 64n) - 1n
let seed = 20260930n
/** seed = seed &* 6364136223846793005 &+ 1442695040888963407；Double(seed >> 11) / 2^53 */
function rnd(): number {
  seed = (seed * 6364136223846793005n + 1442695040888963407n) & M64
  return Number(seed >> 11n) / 2 ** 53
}

interface Cols { o: number[]; h: number[]; l: number[]; c: number[]; v: number[]; tb: number[] }
function makeCols(n: number, scale: number, vol: number, nanTaker: boolean): Cols {
  const r: Cols = { o: [], h: [], l: [], c: [], v: [], tb: [] }
  let px = 100 * scale
  for (let k = 0; k < n; k++) {
    const op = px
    px = Math.max(scale * 0.01, px * (1 + (rnd() - 0.5) * 0.04))
    r.o.push(op); r.c.push(px)
    r.h.push(Math.max(op, px) * (1 + rnd() * 0.01)); r.l.push(Math.min(op, px) * (1 - rnd() * 0.01))
    const vv = vol * (0.1 + rnd())
    r.v.push(vv); r.tb.push(nanTaker && k % 11 === 4 ? NaN : vv * rnd())
  }
  return r
}
function mk(c: Cols, interval: Interval, t0: number, openTime?: number[]): BarSeries {
  return new BarSeries({ symbol: 'XC', interval, t0, open: c.o, high: c.h, low: c.l, close: c.c, volume: c.v, takerBuy: c.tb, openTime })
}

type Case = { name: string; s: BarSeries; params: Partial<Record<IndicatorID, number[]>> }
function cases(): Case[] {
  seed = 20260930n
  const out: Case[] = []
  out.push({ name: 'h1', s: mk(makeCols(300, 1, 1000, true), '1h', 1_700_000_000_000 - 1_700_000_000_000 % 3_600_000 + 3_600_000 * 5), params: {} })
  out.push({ name: 'd1', s: mk(makeCols(200, 1, 1000, false), '1d', 1_704_067_200_000), params: { ST: [7, 2], DMI: [5] } })
  out.push({ name: 'tiny', s: mk(makeCols(150, 1e-8, 1e12, true), '15m', 1_700_000_100_000 - 1_700_000_100_000 % 900_000), params: { MA: [1, 2, 7], RSI: [1, 2], KDJ: [1, 1, 1] } })
  makeCols(60, 1, 5, false) // Swift 那边先造了一份再整列换成常数，随机数照样要消耗掉
  const k3 = (x: number) => Array.from({ length: 60 }, () => x)
  out.push({ name: 'flat', s: mk({ o: k3(3), h: k3(3), l: k3(3), c: k3(3), v: k3(0), tb: k3(0) }, '4h', 1_700_006_400_000), params: {} })
  {
    const c = makeCols(40, 1, 100, true)
    const times = Array.from({ length: 40 }, (_, i) => Date.UTC(2021 + Math.floor(i / 12), i % 12, 1))
    out.push({ name: 'mo1', s: mk(c, '1M', times[0], times), params: { MA: [0, -3, 1, 2], MACD: [30, 10, 9], BOLL: [1, 0], KDJ: [1, 1, 1], SRSI: [1, 1, 1, 1], ST: [1, 0], DMI: [1], RSI: [0, 1, 40] } })
  }
  {
    const c = makeCols(50, 1, 100, false)
    const times: number[] = []
    let t = 1_704_672_000_000
    for (let k = 0; k < 50; k++) { times.push(t); t += 604_800_000 * (k === 20 ? 3 : 1) }
    out.push({ name: 'w1gap', s: mk(c, '1w', times[0], times), params: {} })
  }
  out.push({ name: 'one', s: mk(makeCols(1, 1, 1, false), '1m', 1_700_000_040_000), params: { MA: [1], RSI: [1], ATR: [1], ST: [1, 3], DMI: [1] } })
  out.push({ name: 'two', s: mk(makeCols(2, 1, 1, false), '1m', 1_700_000_040_000), params: { MA: [1, 2], RSI: [1], ATR: [1], ST: [1, 3], DMI: [1] } })
  {
    const c = makeCols(80, 1, 100, true)
    c.c[30] = NaN
    c.h[50] = NaN
    out.push({ name: 'nan', s: mk(c, '1h', 1_700_002_800_000), params: {} })
  }
  return out
}

// ------------------------------------------------------------------ 摘要：FNV-1a 64 over float64 LE，NaN 归一

function digest(cols: readonly (readonly number[])[]): string {
  let h = 0xcbf29ce484222325n
  const buf = new DataView(new ArrayBuffer(8))
  const feed = (n: number) => {
    for (let i = 0; i < n; i++) h = ((h ^ BigInt(buf.getUint8(i))) * 0x100000001b3n) & M64
  }
  for (const col of cols) {
    buf.setUint32(0, col.length, true); feed(4)
    for (const x of col) {
      if (Number.isNaN(x)) buf.setBigUint64(0, 0x7ff8000000000000n, true)
      else buf.setFloat64(0, x, true)
      feed(8)
    }
  }
  return h.toString(16).padStart(16, '0')
}
const outDigest = (r: IndicatorResult) => digest([...r.lines, r.histogram ?? [], r.dir ?? []])

// ------------------------------------------------------------------ Swift 算出来的摘要

const INPUT: Record<string, string> = { h1: 'fa2de35131f7afbf', d1: '98d29b634ed55d44', tiny: 'c4ef071cc0708e03', flat: '12f4f2a2ac45c835', mo1: 'e88e60c47187212b', w1gap: 'e2921b1e8d3482a4', one: 'ce09ed9abd7b5aea', two: '09a28fc8fa85bf83', nan: 'd45ac2c625b6857b' }
const OUTPUT: Record<string, Record<string, string>> = {
  h1: { MA: '74a6effa78ee4aba', EMA: 'eedbe4514a6a362d', BOLL: 'ecca21208727e7c9', VWAP: 'eadba3c65f0a083a', ST: '61c7e868c746d9b7', SAR: '80dd52428e10ad92', VOL: 'b39d74c548a4f64d', MACD: 'ff40a59ce665dbf1', RSI: 'ea4bf0a77cfa65a2', KDJ: '6ff419262e43bce7', SRSI: '367b66a341542d05', ATR: '44620c09ae21d7fd', DMI: 'bc3228de96ab5c66', CVD: 'd04eb09c7539daa4' },
  d1: { MA: '5aa55cb3069d50c3', EMA: 'd9f35552f993e2a3', BOLL: '921850282c93efe9', VWAP: '65e80e4ffffe8b03', ST: '6dba196ac3accd1e', SAR: '1838dc7576e7485c', VOL: 'c1c692a94bd1731a', MACD: '13a34ead870a77e4', RSI: '58bef04f2463d9ad', KDJ: '4980edd448519ceb', SRSI: '3109ea455813276e', ATR: '4b85cd23895bc015', DMI: 'a0f4edb1c0b1fe3f', CVD: 'cb8184123b38da4e' },
  tiny: { MA: '8ece4d9e6f59134e', EMA: 'a9bec474dba76646', BOLL: '385a9e4478bfa95a', VWAP: '663d0b07fc056293', ST: '4992a9ded5e27860', SAR: '023d6572b96d13ad', VOL: '8afd326ae2add781', MACD: '6c1d32347caa1c5a', RSI: '41ca4e1bb5ed7485', KDJ: '5204688117abd904', SRSI: 'd51ffd2de82cb3b7', ATR: 'ef8ebc366367e119', DMI: 'eb4f17881163f081', CVD: '7a6124df6c9d2b3a' },
  flat: { MA: '18a6a74b281ad875', EMA: '106ea16318c36c28', BOLL: 'e1b9bb3849c0d064', VWAP: '6d39b767489f2dc9', ST: '00850a537666d270', SAR: 'bc6f185fdb987b15', VOL: 'f6cf101cd79502ec', MACD: '72d36b8ad64625ac', RSI: '24d39b8b90d8b78d', KDJ: '4c3e1c8537652c89', SRSI: '91f6ee14ea290af5', ATR: 'c46d13f942216d2c', DMI: 'fb65abeee0267f29', CVD: '5b1146924351dfc9' },
  mo1: { MA: '2929e69bb6ccfc58', EMA: 'cb3b7f1a2fba962c', BOLL: 'fbdea6707b328f0f', VWAP: '155f206a86d13d11', ST: 'aaad50f79d41bbf4', SAR: '77f486d7f630afc0', VOL: '3cf4645e8ae49d19', MACD: 'b3ff16ae7e1a3baa', RSI: '2e0bbd2b7db2dd19', KDJ: '8cb67be7c04f0493', SRSI: '0349c7c63788e8e5', ATR: '9adec31be378781b', DMI: 'd1a61b7b013cbcf1', CVD: '2f21542b8113f46c' },
  w1gap: { MA: 'cd5c8913e7a5e5f5', EMA: '2c014701d20a8e0b', BOLL: '275df1fd8903cfbc', VWAP: 'a6edd45047065cea', ST: 'c7dccfb28064b0d0', SAR: 'a001669e54d3c6c7', VOL: 'a76ee1d0d5d9d08d', MACD: 'ddf8b3aea67fc943', RSI: 'a90bf69a3883f370', KDJ: '8d5105932e7731c7', SRSI: 'cb548d39f2693713', ATR: '1e4c4908d8423dd2', DMI: '0d3936d131304214', CVD: '029dcf60c867fbcd' },
  one: { MA: '265468066aed930d', EMA: 'e99b93259d3bd005', BOLL: '12c4d4a06167b171', VWAP: 'cf2f4f9d9aeaf211', ST: '5aaabed19b02928b', SAR: 'f6a3d69d259b4b55', VOL: 'e0a7fe3409157c11', MACD: '2142700dbcb096e1', RSI: '709be02ce520d285', KDJ: '12c4d4a06167b171', SRSI: '39f4522364c08565', ATR: 'efc3f0ac682b925e', DMI: '367bb3e45e27e594', CVD: '0e630f5f00f60673' },
  two: { MA: '0400e73e8f93bdfe', EMA: '5468ba8b5cf97ae5', BOLL: 'ed4ca6dc33621527', VWAP: 'b3552f6926bd2c47', ST: '47e12e678a7a5945', SAR: '1e9c42c204450845', VOL: 'a18c1bfeafc089b7', MACD: '4d8dd88628fe7237', RSI: 'bf61af80727731f6', KDJ: 'ed4ca6dc33621527', SRSI: '5c331e2b3e062755', ATR: '78c37c461eb669ad', DMI: '359082a6e2d92a8b', CVD: '6d36f8934172bb4a' },
  nan: { MA: 'cb5fdc54edd9c5fb', EMA: '6e76387f002ac46e', BOLL: '7c22a372a99497e0', VWAP: 'd65a2dc9d4dce8b2', ST: 'cce2f9d606494ced', SAR: 'c36ad8ca2581cade', VOL: '4267152d90dfe2c4', MACD: 'eb9da08f1fb74c3c', RSI: '2598ff3579ad7ea2', KDJ: 'bd311451879a514e', SRSI: '9e3df7302d158d39', ATR: 'da153ef939fe9c38', DMI: 'c7ec3db3b0563a76', CVD: 'dc5581cc3110ba2e' },
}

const IDS: IndicatorID[] = ['MA', 'EMA', 'BOLL', 'VWAP', 'ST', 'SAR', 'VOL', 'MACD', 'RSI', 'KDJ', 'SRSI', 'ATR', 'DMI', 'CVD']

describe('与 iOS KanpanCore 逐位交叉验证', () => {
  const all = cases()
  it('场景清单与 Swift 那边一致', () => {
    expect(all.map(c => c.name)).toEqual(Object.keys(OUTPUT))
  })
  it.each(all.map(c => [c.name, c] as const))('%s', (name, c) => {
    const s = c.s
    expect(digest([s.open, s.high, s.low, s.close, s.volume, s.takerBuy, s.openTime]), `${name} 输入`).toBe(INPUT[name])
    const e = new IndicatorEngine()
    e.ensure({ series: s, wanted: IDS, params: c.params, dataKey: 'x' })
    const got = Object.fromEntries(IDS.map(id => [id, outDigest(e.get(id)!)]))
    expect(got).toEqual(OUTPUT[name])
  })
})
