import { describe, expect, it } from 'vitest'
import { flattenFills, sideText, venueRows, NO_KEY_TEXT } from '../src/trades/panel'
import type { Fill, TradeRecord } from '../src/review/types'

const fill = (id: string, time: number, side: 'BUY' | 'SELL', role: string, price = '84070', qty = '0.01'): Fill => ({
  id, orderId: 'o' + id, time, side, positionSide: 'BOTH', price, qty, quoteQty: String(+price * +qty),
  commission: '0', commissionAsset: 'USDT', realizedPnl: '0', maker: false, role,
} as Fill)

const rec = (id: string, fills: Fill[], o: { submitted?: number; voided?: boolean; venue?: string; market?: string; tag?: string; dir?: 'long' | 'short' } = {}): TradeRecord => ({
  kind: 'trade', id, revision: 1, submitted: o.submitted ?? 0, updated: 0, voided: !!o.voided, result: null, note: null,
  round: {
    id: 'r' + id, version: 1, venue: o.venue ?? 'binance', market: o.market ?? 'usd_m', symbol: 'BTCUSDT', accountTag: o.tag ?? '',
    positionSide: 'BOTH', direction: o.dir ?? 'long', status: 'closed', quoteAsset: 'USDT', openedAt: 0, closedAt: 0, holdingMs: 0,
    fills,
  } as unknown as TradeRecord['round'],
})

describe('侧栏成交', () => {
  it('没绑密钥的文案一字不差', () => {
    expect(NO_KEY_TEXT).toBe('在手机上绑定交易所只读密钥后，成交会自动同步到这里')
  })

  it('回合摊成逐笔，按时间倒序；同一毫秒按成交 id 倒序；作废的回合不列', () => {
    const rows = flattenFills([
      rec('a', [fill('1', 100, 'BUY', 'open'), fill('3', 300, 'SELL', 'close')]),
      rec('b', [fill('2', 300, 'BUY', 'open'), fill('4', 400, 'SELL', 'close')], { dir: 'short' }),
      rec('c', [fill('9', 999, 'BUY', 'open')], { voided: true }),
    ])
    expect(rows.map(r => r.fill.id)).toEqual(['4', '3', '2', '1'])
    expect(rows.map(r => r.rec)).toEqual(['b', 'a', 'b', 'a'])
    expect(rows[0].direction).toBe('short')
  })

  it('方向写成买开 / 卖平 / 买加 / 卖减，角色不认识只写买卖', () => {
    expect(sideText(fill('1', 0, 'BUY', 'open'))).toBe('买开')
    expect(sideText(fill('1', 0, 'SELL', 'close'))).toBe('卖平')
    expect(sideText(fill('1', 0, 'BUY', 'add'))).toBe('买加')
    expect(sideText(fill('1', 0, 'SELL', 'reduce'))).toBe('卖减')
    expect(sideText(fill('1', 0, 'SELL', '???'))).toBe('卖')
  })
})

describe('交易所账号页', () => {
  it('按交易所 + 产品 + 账户归拢：回合数、最近一次上传、最新成交；最近上传的排前', () => {
    const v = venueRows([
      rec('a', [fill('1', 100, 'BUY', 'open'), fill('2', 500, 'SELL', 'close')], { submitted: 1000 }),
      rec('b', [fill('3', 700, 'BUY', 'open')], { submitted: 2000 }),
      rec('c', [fill('4', 50, 'BUY', 'open')], { submitted: 3000, venue: 'okx', market: 'spot' }),
    ])
    expect(v).toHaveLength(2)
    expect(v[0]).toMatchObject({ venue: 'okx', title: 'OKX · 现货', rounds: 1, lastUpload: 3000, lastFill: 50 })
    expect(v[1]).toMatchObject({ venue: 'binance', title: '币安 · U 本位合约', rounds: 2, lastUpload: 2000, lastFill: 700 })
  })

  it('同一家两个账户分两行', () => {
    const v = venueRows([rec('a', [], { tag: 'main' }), rec('b', [], { tag: 'sub' })])
    expect(v.map(x => x.accountTag).sort()).toEqual(['main', 'sub'])
  })

  it('没有回合就是空（页面据此显示没绑密钥）', () => {
    expect(venueRows([])).toEqual([])
  })
})
