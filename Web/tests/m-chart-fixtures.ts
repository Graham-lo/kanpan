// m-chart-*.test.ts 共用的夹具：移植自 KanpanCore/Tests/KanpanCoreTests/Fixtures.swift 的 Rng / synthSeries，
// 以及 FormatTests.swift 的 SplitMix。文件名不以 .test.ts 结尾，vitest 不会把它当测试跑。
//
// Rng 用两个 32 位半字做 64 位 xorshift（结果与 Swift 的 UInt64 逐位相同），比 BigInt 快一个量级——
// ClampTests 要抽十万次。
// @ts-expect-error Web 的 tsconfig 不带 @types/node，这里只在 vitest（node 环境）里用
import { readFileSync } from 'node:fs'
import { BarSeries } from '../src/m/chart/series'
import type { Interval } from '../src/m/chart/series'

const M64 = (1n << 64n) - 1n

/** Fixtures.swift 的 `Rng`：`s = seed &* 6364136223846793005 &+ 1`，xorshift64（13, 7, 17）。 */
export class Rng {
  private hi: number
  private lo: number
  constructor(seed: number | bigint) {
    const s = (BigInt(seed) * 6364136223846793005n + 1n) & M64
    this.hi = Number(s >> 32n) >>> 0
    this.lo = Number(s & 0xffffffffn) >>> 0
  }
  private shl(n: number): [number, number] {
    return [((this.hi << n) | (this.lo >>> (32 - n))) >>> 0, (this.lo << n) >>> 0]
  }
  private step(): void {
    let [h, l] = this.shl(13)
    this.hi = (this.hi ^ h) >>> 0; this.lo = (this.lo ^ l) >>> 0
    // s ^= s >> 7
    l = ((this.lo >>> 7) | (this.hi << 25)) >>> 0; h = this.hi >>> 7
    this.hi = (this.hi ^ h) >>> 0; this.lo = (this.lo ^ l) >>> 0
    ;[h, l] = this.shl(17)
    this.hi = (this.hi ^ h) >>> 0; this.lo = (this.lo ^ l) >>> 0
  }
  /** 调试用：当前 64 位状态。 */
  nextBig(): bigint { this.step(); return (BigInt(this.hi) << 32n) | BigInt(this.lo) }
  /** [0, 1)：`Double(next() >> 11) / 2^53`。 */
  d(a = 0, b = 1): number {
    this.step()
    const x = (this.hi * 2097152 + (this.lo >>> 11)) / 9007199254740992
    return a + x * (b - a)
  }
  /** `a + Int(next() % UInt64(b - a + 1))`（区间宽度 < 2^21 时精确）。 */
  i(a: number, b: number): number {
    this.step()
    const m = b - a + 1
    return a + (((this.hi % m) * 4294967296 + this.lo) % m)
  }
}

/** Fixtures.swift 的 `synthSeries(count:interval:t0:seed:)`。 */
export function synthSeries(count: number, o: { interval?: Interval; t0?: number; seed?: number } = {}): BarSeries {
  const r = new Rng(o.seed ?? 7)
  const op: number[] = [], h: number[] = [], l: number[] = [], c: number[] = [], v: number[] = [], tb: number[] = []
  let px = 100
  for (let k = 0; k < count; k++) {
    const open = px
    px = Math.max(1, px * (1 + r.d(-0.02, 0.02)))
    op.push(open); c.push(px)
    h.push(Math.max(open, px) * (1 + r.d(0, 0.01)))
    l.push(Math.min(open, px) * (1 - r.d(0, 0.01)))
    const vol = r.d(10, 5000)
    v.push(vol)
    tb.push(tb.length % 17 === 5 ? NaN : vol * r.d(0.2, 0.8))
  }
  return new BarSeries({
    symbol: 'SYN', interval: o.interval ?? '1h', t0: o.t0 ?? 1_700_000_000_000,
    open: op, high: h, low: l, close: c, volume: v, takerBuy: tb,
  })
}

/** FormatTests.swift 的 SplitMix64（全程按 UInt64 回绕）。 */
export class SplitMix {
  private state: bigint
  constructor(seed: number | bigint) { this.state = BigInt(seed) & M64 }
  next(): bigint {
    this.state = (this.state + 0x9E3779B97F4A7C15n) & M64
    let z = this.state
    z = ((z ^ (z >> 30n)) * 0xBF58476D1CE4E5B9n) & M64
    z = ((z ^ (z >> 27n)) * 0x94D049BB133111EBn) & M64
    return z ^ (z >> 31n)
  }
}

/** 读 iOS 那边 KanpanCore 的 JSON 夹具（不复制一份）。 */
export function coreFixture<T = Record<string, unknown>>(name: string): T {
  const url = new URL(`../../KanpanCore/Tests/KanpanCoreTests/Fixtures/${name}.json`, import.meta.url)
  return JSON.parse(readFileSync(url, 'utf8')) as T
}

/** JSON 里 NaN 写成 null，读回来还原成 NaN。 */
export const nums = (a: unknown): number[] => (Array.isArray(a) ? a.map(x => (typeof x === 'number' ? x : NaN)) : [])
export const rows = (a: unknown): number[][] => (Array.isArray(a) ? a.map(nums) : [])
