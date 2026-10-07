/* 2026-10-07 P0-1 · 自选很多时网关拒掉第 3 条连接，整页判断线、16 格全不跟推送（market/stream.ts）
 *   根因：① 一条连接被拒就把全局 failed 置真，连接点变红、图变灰，kline 推送被 stale 闸挡掉；
 *        ② 分配不分轻重，1→16 时新格子的 K 线流被分到新开的第 3 条（自选报价把前两条占满）；
 *        ③ 总上限写死 160，而网关的 160 是同一 IP 的所有标签页 / 手机合着算的，被拒了还按 160 去开那条注定被拒的连接。 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import { MIN_CAP, PROBE_MS, PROBE_STEP, assignStreams, capAfterProbe, capAfterReject, closeKind, wsStateOf } from '../src/market/stream'

class FakeWS {
  static OPEN = 1; static CONNECTING = 0; static CLOSED = 3
  static all: FakeWS[] = []
  readyState = 0
  sent: any[] = []
  onopen: (() => void) | null = null
  onmessage: ((e: { data: string }) => void) | null = null
  onclose: ((e?: { code: number; reason: string }) => void) | null = null
  onerror: (() => void) | null = null
  constructor(public url: string) { FakeWS.all.push(this) }
  send(s: string) { this.sent.push(JSON.parse(s)) }
  close() { this.readyState = 3 }
  open() { this.readyState = 1; this.onopen?.() }
  frame() { this.onmessage?.({ data: JSON.stringify({ stream: 'x@ticker', data: {} }) }) }
  reply(id: number) { this.onmessage?.({ data: JSON.stringify({ result: null, id }) }) }
  streams(): string[] { return decodeURIComponent(this.url.split('?streams=')[1] || '').split('/').filter(Boolean) }
  kill(code: number, reason = '') { this.readyState = 3; this.onclose?.({ code, reason }) }
}

afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); vi.resetModules(); FakeWS.all = [] })

async function load() {
  vi.useFakeTimers()
  vi.stubGlobal('WebSocket', FakeWS)
  vi.stubGlobal('location', { protocol: 'https:', host: 'k.example' })
  vi.resetModules()
  const m = await import('../src/market')
  const stream = await import('../src/market/stream')
  stream.setRoute('gateway')
  return { ...m, ...stream }
}

const cellsOf = (n: number) => Array.from({ length: n }, (_, i) => `c${i}usdt@kline_1h`)
const watchOf = (n: number, from = 0) => Array.from({ length: n }, (_, i) => `w${i + from}usdt@ticker`)

describe('assignStreams：关键流永远坐最早的连接，挤出去的是自选报价', () => {
  it('从零分：16 路 K 线全在第 1 条，自选报价排在后面', () => {
    const vit = cellsOf(16), want = [...vit, ...watchOf(144)]
    const { keep, open } = assignStreams([], want, 64, 16)
    expect(keep).toEqual([])
    expect(open.map(o => o.length)).toEqual([64, 64, 32])
    expect(vit.every(x => open[0].includes(x))).toBe(true)
    expect(open.slice(1).flat().some(x => vit.includes(x))).toBe(false)
  })

  it('1→16 复现：前两条已被自选报价占满，新格子的 K 线挤进第 1 条，被挤出的自选报价去新开的那条', () => {
    // 修前：新格子的 15 路 K 线全分到新开的第 3 条，那条被网关按同一 IP 160 路拒掉
    const conn0 = ['c0usdt@kline_1h', ...watchOf(63)], conn1 = watchOf(64, 63)
    const vit = cellsOf(16), want = [...vit, ...watchOf(144)]
    const { keep, open } = assignStreams([conn0, conn1], want, 64, 16)
    expect(vit.every(x => keep[0]!.includes(x))).toBe(true)
    expect(keep[0]).toHaveLength(64)
    expect(open.flat().some(x => vit.includes(x))).toBe(false)
    // 每路恰好分一次
    const flat = [...keep.flat() as string[], ...open.flat()]
    expect(new Set(flat).size).toBe(flat.length)
    expect(new Set(flat)).toEqual(new Set(want))
  })

  it('已经分着、却坐在后面连接上的关键流：和前面连接上排得最靠后的自选报价对调', () => {
    const vit = cellsOf(4), w = watchOf(64)
    const { keep, open } = assignStreams([w, vit], [...vit, ...w], 64, 4)
    expect(open).toEqual([])
    expect(vit.every(x => keep[0]!.includes(x))).toBe(true)
    // 换出去的是排在最后的那 4 路
    expect(keep[1]!.sort()).toEqual(w.slice(60).sort())
  })

  it('要收一条连接时先收关键流最少的', () => {
    const vit = cellsOf(2)
    const { keep } = assignStreams([watchOf(10), [...vit, ...watchOf(3, 10)]], [...vit, ...watchOf(13)], 64, 2)
    expect(keep[0]).toBeNull()
    expect(keep[1]).toEqual(expect.arrayContaining(vit))
  })

  it('vital = 0 时行为不变：已经在连接上的流不挪，收连接收最空的', () => {
    expect(assignStreams([['a@ticker'], ['b@ticker']], ['a@ticker', 'b@ticker', 'c@ticker'], 64))
      .toEqual({ keep: [['a@ticker', 'b@ticker', 'c@ticker'], null], open: [] })
    expect(assignStreams([['a@ticker', 'b@ticker'], ['c@ticker']], ['c@ticker', 'a@ticker', 'b@ticker'], 2))
      .toEqual({ keep: [['a@ticker', 'b@ticker'], ['c@ticker']], open: [] })
  })
})

describe('同一来源总上限：被拒的分类、收紧与放宽', () => {
  it('closeKind：1008 subscription limit exceeded / 握手没成而别的连接好好的 = 额度满；其余按断线', () => {
    expect(closeKind(1008, 'subscription limit exceeded', true, true)).toBe('capacity')
    expect(closeKind(1008, 'control rate exceeded', true, true)).toBe('down')
    expect(closeKind(1008, 'invalid subscription', true, false)).toBe('down')
    expect(closeKind(1006, '', false, true)).toBe('capacity')
    expect(closeKind(1006, '', false, false)).toBe('down')
    expect(closeKind(1006, '', true, true)).toBe('down')
  })
  it('capAfterReject：收到对面已经收下的路数（至少让一档），一路没收下就折半，不低于 MIN_CAP', () => {
    expect(capAfterReject(128, 160)).toBe(128)
    expect(capAfterReject(150, 160)).toBe(160 - PROBE_STEP)
    expect(capAfterReject(0, 160)).toBe(80)
    expect(capAfterReject(5, 160)).toBe(MIN_CAP)
    expect(capAfterReject(5, MIN_CAP)).toBe(MIN_CAP) // 收不动了 → 调用方按普通断线处理
  })
  it('capAfterProbe：每次放宽一档，到 TOTAL 回到不设限', () => {
    expect(capAfterProbe(128, 160)).toBe(144)
    expect(capAfterProbe(144, 160)).toBeNull()
  })
  it('wsStateOf：只看承载关键流的连接', () => {
    expect(wsStateOf(0, false, true, [])).toBe('idle')
    expect(wsStateOf(10, false, true, [{ open: true }])).toBe('open')
    expect(wsStateOf(10, false, false, [{ open: true }])).toBe('connecting')
    expect(wsStateOf(10, true, true, [{ open: true }])).toBe('closed')
  })
})

describe('连接池（网关线路，FakeWS）', () => {
  /** 16 格 + 自选 300：16 路关键 K 线 + 144 路自选报价 = 160 → 三条 64/64/32 */
  async function heavy() {
    const m = await load()
    const vit = cellsOf(16), list = [...vit, ...watchOf(300)]
    m.setStreams(list, vit, { now: true, vital: vit })
    return { m, vit, list }
  }

  it('第 3 条（只有自选报价）握手被拒：整页不判断线、总上限收到 128、退避期间不重开那条', async () => {
    const { m, vit } = await heavy()
    expect(FakeWS.all.map(w => w.streams().length)).toEqual([64, 64, 32])
    expect(vit.every(x => FakeWS.all[0].streams().includes(x))).toBe(true)
    const [a, b, c] = FakeWS.all
    a.open(); a.frame(); b.open(); b.frame()
    c.kill(1006)                               // 浏览器看到的 429 握手被拒
    expect(m.S.wsState).not.toBe('closed')     // 修前：'closed'，16 格变灰、推送被挡
    await vi.advanceTimersByTimeAsync(5000)
    expect(m.S.wsState).toBe('open')
    expect(m.streamDebug().cap).toBe(128)
    expect(FakeWS.all).toHaveLength(3)         // 注定被拒的那条不再重开
    expect(m.streamDebug().subscribed).toHaveLength(128)
    expect(vit.every(x => m.streamDebug().subscribed.includes(x))).toBe(true)
  })

  it('订阅越线被 1008 掐掉（subscription limit exceeded）：至少让一档（160 → 144），不退避、300 ms 后按新额度重开', async () => {
    const { m } = await heavy()
    const [a, b, c] = FakeWS.all
    a.open(); a.frame(); b.open(); b.frame(); c.open(); c.frame()
    c.kill(1008, 'subscription limit exceeded')
    expect(m.S.wsState).not.toBe('closed')
    expect(m.streamDebug().cap).toBe(144)
    await vi.advanceTimersByTimeAsync(400)
    expect(FakeWS.all).toHaveLength(4)
    expect(FakeWS.all[3].streams()).toHaveLength(16)
  })

  it('承载关键流的连接因别的原因断了（1008 control rate exceeded）：照旧判断线、退避重连', async () => {
    const { m } = await heavy()
    const [a, b] = FakeWS.all
    a.open(); a.frame(); b.open(); b.frame()
    a.kill(1008, 'control rate exceeded')
    expect(m.S.wsState).toBe('closed')
    expect(m.streamDebug().cap).toBe(160)
  })

  it('1→16：额度已收到 128 时，新格子的 K 线进第 1 条（不新开连接），全程不判断线', async () => {
    const m = await load()
    const vit1 = cellsOf(1), w = watchOf(300)
    m.setStreams([...vit1, ...w], vit1, { now: true, vital: vit1 })
    const [a, b, c] = FakeWS.all
    a.open(); a.frame(); b.open(); b.frame(); c.kill(1006)
    await vi.advanceTimersByTimeAsync(400)
    expect(m.streamDebug().cap).toBe(128)
    const vit = cellsOf(16)
    m.setStreams([...vit, ...w], vit, { now: true, vital: vit })
    expect(FakeWS.all).toHaveLength(3)
    // 第 2 条要退掉挤出去的自选报价：退订回执到了，第 1 条的新订阅才发（先退后订）
    for (const x of [a, b]) for (const s of x.sent.filter(s => s.method === 'UNSUBSCRIBE')) x.reply(s.id)
    const subA = a.sent.filter(s => s.method === 'SUBSCRIBE').flatMap(s => s.params)
    expect(vit.slice(1).every(x => subA.includes(x))).toBe(true)
    expect(m.S.wsState).not.toBe('closed')
  })

  it('先退后订：别的连接上的退订没回执之前，净新增的订阅先压着，回执到了再发', async () => {
    const m = await load()
    const A = watchOf(64), B = watchOf(10, 64)
    m.setStreams([...A, ...B], [], { now: true, vital: [] })
    const [a, b] = FakeWS.all
    a.open(); a.frame(); b.open(); b.frame()
    // a 退 1 路、b 退 5 路，新增 2 路：一路落 a 的空位，一路落 b
    m.setStreams([...A.slice(1), ...B.slice(5), 'n1usdt@ticker', 'n2usdt@ticker'], [], { now: true, vital: [] })
    const subs = () => [...a.sent, ...b.sent].filter(s => s.method === 'SUBSCRIBE')
    const unsubs = [...a.sent, ...b.sent].filter(s => s.method === 'UNSUBSCRIBE')
    expect(unsubs).toHaveLength(2)
    expect(subs()).toHaveLength(0)
    const ua = a.sent.find(s => s.method === 'UNSUBSCRIBE'), ub = b.sent.find(s => s.method === 'UNSUBSCRIBE')
    a.reply(ua.id)
    expect(subs()).toHaveLength(0)           // b 上的退订还没落地
    b.reply(ub.id)
    expect(subs().flatMap(s => s.params).sort()).toEqual(['n1usdt@ticker', 'n2usdt@ticker'])
  })

  it('被拒后每 PROBE_MS 放宽一档：放到 144 再开一条 16 路的', async () => {
    const { m } = await heavy()
    const [a, b, c] = FakeWS.all
    a.open(); a.frame(); b.open(); b.frame(); c.kill(1006)
    await vi.advanceTimersByTimeAsync(400)
    expect(m.streamDebug().cap).toBe(128)
    // 一直有帧来（不然 30 秒静默看门狗会把 a、b 判断线）
    for (let t = 0; t < PROBE_MS; t += 5000) { await vi.advanceTimersByTimeAsync(5000); a.frame(); b.frame() }
    await vi.advanceTimersByTimeAsync(10)
    expect(m.streamDebug().cap).toBe(144)
    expect(FakeWS.all).toHaveLength(4)
    expect(FakeWS.all[3].streams()).toHaveLength(16)
    expect(FakeWS.all[3].streams().every(x => x.endsWith('@ticker') && x.startsWith('w'))).toBe(true)
  })

  it('换线路清掉摸出来的上限', async () => {
    const { m } = await heavy()
    const [a, b, c] = FakeWS.all
    a.open(); a.frame(); b.open(); b.frame(); c.kill(1006)
    expect(m.streamDebug().cap).toBe(128)
    m.setRoute('direct'); m.setRoute('gateway')
    expect(m.streamDebug().cap).toBe(160)
  })
})
