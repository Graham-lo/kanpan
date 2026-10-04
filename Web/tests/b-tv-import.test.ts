import { describe, it, expect, vi, beforeEach } from 'vitest'

const h = vi.hoisted(() => ({
  subs: [] as (() => void)[],
  st: { watch: { crypto: [] as string[], us: [] as string[], com: [] as string[] }, watchTab: 'crypto' },
  textarea: { value: '' },
}))
vi.mock('../src/account/session', () => ({ onSession: (fn: () => void) => { h.subs.push(fn); return () => {} } }))
vi.mock('../src/app/store', () => ({ st: h.st, save: vi.fn() }))
vi.mock('../src/market', () => ({
  S: { symbols: new Map([['BTCUSDT', { kind: 'crypto' }], ['ETHUSDT', { kind: 'crypto' }]]) },
  TABS: [['crypto', '加密'], ['us', '美股'], ['com', '大宗']],
}))
vi.mock('../src/ui/dom', () => ({
  $: (sel: string) => (sel === '#tviText' ? h.textarea : null),
  I: () => '', esc: (s: string) => s, tgt: (e: { target: unknown }) => e.target,
}))
vi.mock('../src/ui/overlay', () => ({ toast: vi.fn() }))
vi.mock('../src/styles/watch.css', () => ({}))

import { tvImportHTML, tvImportClick, tvImportChange } from '../src/watch/importPanel'

const switchAccount = () => h.subs.forEach(f => f())
const goBtn = { closest: (s: string) => (s === '#tviGo' ? {} : null) }

beforeEach(() => { h.st.watch = { crypto: [], us: [], com: [] }; switchAccount() })

describe('我的 →「从 TradingView 导入」换账号', () => {
  it('上一个人粘的代号和导入结果不留给下一个人', () => {
    h.textarea.value = 'BINANCE:ETHUSDT.P'
    tvImportClick({ target: goBtn } as unknown as MouseEvent, () => {})
    expect(h.st.watch.crypto).toEqual(['ETHUSDT'])
    expect(tvImportHTML()).toContain('tviResult')
    expect(tvImportHTML()).toContain('>BINANCE:ETHUSDT.P</textarea>')
    switchAccount()
    const html = tvImportHTML()
    expect(html).not.toContain('tviResult')
    expect(html).toContain('></textarea>')
  })
  it('换账号前选的 .txt 换账号后才读完：不加进下一个人的自选', async () => {
    let resolve!: (s: string) => void
    const file = { text: () => new Promise<string>(r => { resolve = r }) }
    const inp = { id: 'tviFile', files: [file] }
    expect(tvImportChange({ target: inp } as unknown as Event, () => {})).toBe(true)
    switchAccount()
    resolve('BINANCE:ETHUSDT.P')
    await Promise.resolve(); await Promise.resolve()
    expect(h.st.watch.crypto).toEqual([])
  })
  it('没换账号：选的 .txt 读完照常导入', async () => {
    const file = { text: () => Promise.resolve('BINANCE:ETHUSDT.P') }
    tvImportChange({ target: { id: 'tviFile', files: [file] } } as unknown as Event, () => {})
    await Promise.resolve(); await Promise.resolve()
    expect(h.st.watch.crypto).toEqual(['ETHUSDT'])
  })
})

describe('TradingView 分区名带空格', () => {
  it('###US Stocks 整段是分区名，不把 Stocks 当成一只对不上的代号', async () => {
    const { parseTv } = await vi.importActual<typeof import('../src/watch/tvImport')>('../src/watch/tvImport')
    expect(parseTv('###US Stocks,NASDAQ:NVDA,NASDAQ:TSLA\n###My Coins,BINANCE:BTCUSDT.P BINANCE:ETHUSDT.P')).toEqual([
      { raw: 'NASDAQ:NVDA', section: 'US Stocks' }, { raw: 'NASDAQ:TSLA', section: 'US Stocks' },
      { raw: 'BINANCE:BTCUSDT.P', section: 'My Coins' }, { raw: 'BINANCE:ETHUSDT.P', section: 'My Coins' },
    ])
  })
})
