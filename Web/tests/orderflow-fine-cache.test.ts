/* 主力订单流 · 细桶只扫一次：evaluate 扫 1000 bps 时顺带分好 500 bps 的细桶，buildFine 簿没动就复用 */
import { describe, expect, it, vi } from 'vitest'
import { buildFine, type FineBook } from '../src/orderflow/aggregate'
import { OrderFlowModel } from '../src/orderflow/model'
import { bucketKey, type BucketValue } from '../src/orderflow/localBook'
import { usdOf, type BookLevel, type Thresholds, type Venue } from '../src/orderflow/types'
import { D } from '../src/orderflow/settings'

const OKX_PERP: Venue = {
  exchange: 'okx', label: 'OKX', product: 'usdtPerp', instrument: 'BTC-USDT-SWAP',
  notional: { kind: 'linear', multiplier: 1 }, sequenceModel: 'previousFinalExact', snapshotInBand: true,
}
const CB_SPOT: Venue = {
  exchange: 'coinbase', label: 'Coinbase', product: 'spot', instrument: 'BTC-USD',
  notional: { kind: 'linear', multiplier: 1 }, sequenceModel: 'strictIncrementing', snapshotInBand: true,
}

let seq = 1
function snap(m: OrderFlowModel, id: string, bids: [number, number][], asks: [number, number][]): void {
  const lv = (a: [number, number][]): BookLevel[] => a.map(([price, quantity]) => ({ price, quantity }))
  m.ingest(id, { type: 'snapshot', snapshot: { lastUpdateID: seq++, requestedLevels: 5000, bids: lv(bids), asks: lv(asks), connection: 0, slidingWindow: false } }, 0)
}

/** 确定性的一本簿：最优买 / 卖在 bb / ba，两边各铺到 ±15%，价位不整、数量带小数（跨 500 / 1000 bps 边界的桶都有） */
function levels(bb: number, ba: number, salt: number): { bids: [number, number][]; asks: [number, number][] } {
  let x = 12345 + salt
  const rnd = (): number => { x = (x * 1103515245 + 12345) % 2147483648; return x / 2147483648 }
  const bids: [number, number][] = [], asks: [number, number][] = []
  for (let p = bb; p > bb * 0.85; p -= 0.37) bids.push([+p.toFixed(2), +(rnd() * 40 + 0.013).toFixed(3)])
  for (let p = ba; p < ba * 1.15; p += 0.41) asks.push([+p.toFixed(2), +(rnd() * 40 + 0.017).toFixed(3)])
  return { bids, asks }
}

const TH: Thresholds = { usdtPerp: 1_000_000, step: 10 } // 现货没门槛：evaluate 不扫 Coinbase 那本

function setup(): { m: OrderFlowModel; a: string; b: string } {
  seq = 1
  const m = new OrderFlowModel('BTCUSDT', TH)
  const a = m.addVenue(OKX_PERP), b = m.addVenue(CB_SPOT)
  m.connectionOpened(a); m.connectionOpened(b)
  const la = levels(999.3, 1000.4, 1), lb = levels(998.9, 1000.8, 2)
  snap(m, a, la.bids, la.asks)
  snap(m, b, lb.bids, lb.asks)
  return { m, a, b }
}

/** 无缓存版（改动前 VenueBook.buckets 的原样逻辑），直接扫 LocalBook */
function reference(m: OrderFlowModel, id: string, bps: number): Map<string, BucketValue> | null {
  const vb = m.books.get(id)!
  const scheme = m.scheme!
  const out = new Map<string, BucketValue>()
  const mid = vb.book.forEachLevel(bps, (side, p, q) => {
    const usd = usdOf(vb.venue.notional, p, q)
    if (usd <= 0) return
    const k = bucketKey(side, scheme.index(p))
    let v = out.get(k)
    if (!v) { v = { notional: 0, topLevel: 0, price: 0 }; out.set(k, v) }
    v.notional += usd
    if (usd > v.topLevel) { v.topLevel = usd; v.price = p }
  })
  return mid == null ? null : out
}

/** 逐位比较（含 Map 的插入顺序） */
function dump(f: FineBook): unknown {
  const side = (s: FineBook['bid']): unknown => [...s].map(([k, c]) => [k, c.total, [...c.byVenue]])
  return { ...f, bid: side(f.bid), ask: side(f.ask) }
}

describe('主力订单流 · 细桶缓存', () => {
  it('evaluate 之后 buildFine 不再扫已扫过的簿；没门槛的簿只扫一次', () => {
    const { m, a, b } = setup()
    const sa = vi.spyOn(m.books.get(a)!.book, 'forEachLevel')
    const sb = vi.spyOn(m.books.get(b)!.book, 'forEachLevel')
    m.evaluate(0)
    expect(sa).toHaveBeenCalledTimes(1)
    expect(sb).toHaveBeenCalledTimes(0)
    buildFine(m, D.fineRadiusBps, 0)
    expect(sa).toHaveBeenCalledTimes(1) // 复用 evaluate 顺带分好的
    expect(sb).toHaveBeenCalledTimes(1) // evaluate 没扫它，这里补扫一次
    buildFine(m, D.fineRadiusBps, 1)
    expect(sa).toHaveBeenCalledTimes(1)
    expect(sb).toHaveBeenCalledTimes(1) // 输入没变：第二次不重算
  })

  it('输入变了就重算：新深度帧、换半径、换步长', () => {
    const { m, a, b } = setup()
    const sa = vi.spyOn(m.books.get(a)!.book, 'forEachLevel')
    const sb = vi.spyOn(m.books.get(b)!.book, 'forEachLevel')
    buildFine(m, 500, 0)
    expect([sa.mock.calls.length, sb.mock.calls.length]).toEqual([1, 1])
    // 新深度帧（中间价也变了）：只重算这一本
    const la = levels(1001.1, 1002.2, 3)
    snap(m, a, la.bids, la.asks)
    const f1 = buildFine(m, 500, 0)!
    expect([sa.mock.calls.length, sb.mock.calls.length]).toEqual([2, 1])
    expect(f1.mid).toBe((1001.1 + 1002.2) / 2)
    // 换半径
    buildFine(m, 300, 0)
    expect([sa.mock.calls.length, sb.mock.calls.length]).toEqual([3, 2])
    // 换步长
    m.setThresholds({ ...TH, step: 5 })
    const f2 = buildFine(m, 300, 0)!
    expect([sa.mock.calls.length, sb.mock.calls.length]).toEqual([4, 3])
    expect(f2.step).toBe(5)
    // 断线重连：簿清空、不可用
    m.connectionOpened(a)
    const f3 = buildFine(m, 300, 0)!
    expect(f3.ready).toBe(1)
  })

  it('结果与无缓存版逐位一致（evaluate 顺带分的、单独扫的、参考实现三者相同）', () => {
    const viaEval = setup()
    viaEval.m.evaluate(0)
    const cached = buildFine(viaEval.m, D.fineRadiusBps, 7)!
    const again = buildFine(viaEval.m, D.fineRadiusBps, 7)!

    const cold = setup()
    const fresh = buildFine(cold.m, D.fineRadiusBps, 7)!

    expect(dump(cached)).toEqual(dump(fresh))
    expect(dump(again)).toEqual(dump(fresh))
    expect(cached.bid.size).toBeGreaterThanOrEqual(5)
    expect(cached.ask.size).toBeGreaterThanOrEqual(5)

    // 每本簿的细桶与参考实现逐项相同（含插入顺序）
    const ref = setup()
    ref.m.evaluate(0)
    for (const id of [ref.a, ref.b]) {
      const want = reference(setup().m, id, D.fineRadiusBps)
      const got = ref.m.books.get(id)!.fineBuckets(ref.m.scheme!, D.fineRadiusBps)
      expect(got && [...got]).toEqual(want && [...want])
    }
  })

  it('evaluate 的大圈结果不受顺带分细桶影响', () => {
    const x = setup(), y = setup()
    const big = x.m.books.get(x.a)!.buckets(x.m.scheme!, D.scanRadiusBps, D.fineRadiusBps)!
    const plain = y.m.books.get(y.a)!.buckets(y.m.scheme!, D.scanRadiusBps)!
    expect([...big]).toEqual([...plain])
    expect([...big]).toEqual([...reference(setup().m, setup().a, D.scanRadiusBps)!])
  })
})
