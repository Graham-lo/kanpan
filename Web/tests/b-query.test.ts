import { describe, it, expect } from 'vitest'
import { applyQueryTo, strippedUrl } from '../src/app/query'
import type { State } from '../src/app/store'

const base = (): State => ({ layout: '1', active: 0, cells: [{ symbol: 'BTCUSDT', iv: '1h' }], theme: 'light', skin: 'sage', panel: 'watch', slots: { ladder: false, drawer: false } } as unknown as State)

describe('地址栏参数（B9）', () => {
  it('小写代号也认', () => {
    const s = base(); applyQueryTo(s, '?s=ethusdt')
    expect(s.cells[0].symbol).toBe('ETHUSDT')
  })
  it('中文底名的合约（复制链接给出的原样代号，浏览器会百分号编码）也认', () => {
    const s = base(); applyQueryTo(s, '?s=' + encodeURIComponent('币安人生USDT') + '&i=4h')
    expect(s.cells[0].symbol).toBe('币安人生USDT')
    expect(s.cells[0].iv).toBe('4h')
  })
  it('不认的值不动，但照样算用过、从地址栏拿掉', () => {
    const s = base()
    const used = applyQueryTo(s, '?s=<script>&i=7x&theme=pink&skin=x&layout=5&panel=foo&keep=1')
    expect(s.cells[0]).toEqual({ symbol: 'BTCUSDT', iv: '1h' })
    expect([s.theme, s.skin, s.layout, s.panel]).toEqual(['light', 'sage', '1', 'watch'])
    expect(used).toEqual(['s', 'i', 'theme', 'skin', 'layout', 'panel'])
    expect(strippedUrl('/', '?s=x&keep=1&i=1h', '#chart', used)).toBe('/?keep=1#chart')
  })
  it('换到更多格的布局：格子补齐，落在当前格', () => {
    const s = base(); applyQueryTo(s, '?layout=4&s=SOLUSDT')
    expect(s.cells.length).toBe(4)
    expect(s.cells[0].symbol).toBe('SOLUSDT')
  })
})

describe('不认的 #页名（B9）', async () => {
  const { vi } = await import('vitest')
  vi.doMock('../src/ui/dom', () => ({ $: () => null, $$: () => [], I: () => '', esc: (s: string) => s }))
  vi.doMock('../src/ui/overlay', () => ({ hideTip: () => {} }))
  vi.doMock('../src/app/store', () => ({ st: { page: 'chart' }, save: () => {} }))
  const loc = { hash: '#foo' }
  const replaced: string[] = []
  vi.stubGlobal('location', loc)
  vi.stubGlobal('history', { replaceState: (_s: unknown, _t: string, u: string) => { replaced.push(u); loc.hash = u } })
  const { go } = await import('../src/app/shell')
  it('hashchange 进来的 #foo 显示图表页，地址栏也换成 #chart', () => {
    go('foo', false)
    expect(replaced).toEqual(['#chart'])
  })
  it('认得的页名经 hashchange 进来时不再改地址栏', () => {
    replaced.length = 0; loc.hash = '#me'
    go('me', false)
    expect(replaced).toEqual([])
  })
})
