// 深度审查 Web F 线（性能与压测，2026-10-05）的回归用例；压测脚本见 scripts/f-perf.mjs
import { describe, it, expect } from 'vitest'
import { Limiter, type LimitSnap } from '../src/market/limit'
import { visibleRange, flashClass, FLASH_CLASSES } from '../src/watch/logic'
import widgetSource from '../src/watch/widget.ts?raw'

const F = 'https://fapi.binance.com'

describe('F1 宽侧栏持仓额只取看得见的行', () => {
  it('300 行、视口 900、行高 32：只取视口上下各一屏的行，滚到中间取中间那一段', () => {
    const [a, b] = visibleRange(300, 0, 900, 30, 32)
    expect(a).toBe(0)
    expect(b).toBe(Math.ceil((0 - 30 + 1800) / 32))
    expect(b - a).toBeLessThan(60)
    const [c, d] = visibleRange(300, 4000, 900, 30, 32)
    expect(c).toBe(Math.floor((4000 - 30 - 900) / 32))
    expect(d).toBe(Math.ceil((4000 - 30 + 1800) / 32))
    const [e, f] = visibleRange(300, 99999, 900, 30, 32)
    expect(f).toBe(300)
    expect(e).toBeLessThanOrEqual(f)
  })
  it('量不出行高或视口（收起、还没排版）时一行都不取；空表不取', () => {
    expect(visibleRange(300, 0, 0, 30, 32)).toEqual([0, 0])
    expect(visibleRange(300, 0, 900, 30, 0)).toEqual([0, 0])
    expect(visibleRange(0, 0, 900, 30, 32)).toEqual([0, 0])
  })
})

describe('F2 限流账本按秒并笔，大小不随请求数长', () => {
  it('一分钟 600 次请求：落盘账本每道最多 60 笔，记的总权重不变，预算照样卡得住', () => {
    let disk: string | null = null, writes = 0, bytes = 0
    const store = { load: () => (disk ? JSON.parse(disk) : null), save: (x: LimitSnap) => { disk = JSON.stringify(x); writes++; bytes += disk.length }, raw: () => disk }
    const g = new Limiter({ fapi: 1200, dapi: 1200, spot: 3000 }, store)
    const oi = (i: number) => `${F}/fapi/v1/openInterest?symbol=S${i}USDT`
    for (let i = 0; i < 600; i++) expect(g.take(oi(i), 1000 + i * 100)).toBe(0)
    const snap = JSON.parse(disk!) as LimitSnap
    expect(snap.used.fapi.length).toBeLessThanOrEqual(60)
    expect(snap.used.fapi.reduce((s, x) => s + x[1], 0)).toBe(600)
    expect(g.usedOf('fapi', 1000 + 599 * 100)).toBe(600)
    expect(writes).toBe(600)
    // 原来一笔一行：最后几次写的是 600 行（约 9 KB）；并笔后最长 60 行
    expect(disk!.length).toBeLessThan(1500)
    expect(bytes / writes).toBeLessThan(1500)
    // 预算：再塞到上限就要排队
    const big = `${F}/fapi/v1/klines?symbol=BTCUSDT&interval=1m&limit=1500`
    let t = 61_000
    while (g.take(big, t) === 0) t += 1
    expect(g.usedOf('fapi', t)).toBeLessThanOrEqual(1200)
  })
  it('跨秒不并：第二秒的一笔单独成行，最早那一秒滚出窗口时只放掉那一秒的权重', () => {
    const g = new Limiter({ fapi: 100, dapi: 100, spot: 100 })
    const K = `${F}/fapi/v1/klines?symbol=BTCUSDT&interval=1m&limit=1500` // 10
    for (let i = 0; i < 5; i++) g.take(K, 1000 + i)
    for (let i = 0; i < 5; i++) g.take(K, 2500 + i)
    expect(g.usedOf('fapi', 3000)).toBe(100)
    expect(g.take(K, 3000)).toBe(1000 + 60_000 - 3000)
    expect(g.usedOf('fapi', 61_000)).toBe(50)
  })
})

describe('F4 自选跳价闪色不强制重算样式', () => {
  it('两套关键帧轮换：上次第一套这次挂第二套，第二套之后回到第一套，涨跌各自换名', () => {
    expect(flashClass('num', 1)).toBe('wv-flash-up')
    expect(flashClass('num wv-flash-up', 1)).toBe('wv-flash-up2')
    expect(flashClass('num wv-flash-up2', 1)).toBe('wv-flash-up')
    expect(flashClass('num wv-flash-up', -1)).toBe('wv-flash-down2')
    expect(flashClass('num wv-flash-down2', -1)).toBe('wv-flash-down')
    expect(FLASH_CLASSES).toContain(flashClass('x', -1))
  })
  it('widget 里不再用读 offsetWidth 的办法重播动画', () => {
    expect(widgetSource).not.toMatch(/void\s+\w+\.offset(Width|Height)/)
  })
})
