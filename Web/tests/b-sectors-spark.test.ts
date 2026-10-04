/* 板块走势格的空状态：取过了还画不出 → 「—」；还在取 → 空着等 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const klinesMock = vi.fn()
vi.mock('../src/market', () => ({ klines: (...a: unknown[]) => klinesMock(...a) }))
const { wantSparks, resetSparks, boardPath, sparkSettled } = await import('../src/sectors/spark')

const flush = async (): Promise<void> => { for (let i = 0; i < 20; i++) await new Promise(r => setTimeout(r, 0)) }
beforeEach(() => {
  resetSparks(); klinesMock.mockReset()
  vi.stubGlobal('sessionStorage', { getItem: () => null, setItem: () => {}, removeItem: () => {} })
})
afterEach(() => { vi.unstubAllGlobals() })

describe('走势格空状态', () => {
  it('服务端说这只没数：取过了，算「真没有」', async () => {
    vi.stubGlobal('fetch', async () => ({ ok: true, status: 200, json: async () => ({ series: {} }) }))
    wantSparks(['NEWUSDT'], () => {})
    expect(sparkSettled(['NEWUSDT'])).toBe(false) // 还在路上：空着等
    await flush()
    expect(boardPath(['NEWUSDT'], 'today', '')).toBeNull()
    expect(sparkSettled(['NEWUSDT'])).toBe(true)
  })
  it('直连那一路网络错（klines 抛错）也算取过了，不会一直当在取', async () => {
    vi.stubGlobal('fetch', async () => ({ ok: true, status: 200, json: async () => ({ series: {} }) }))
    klinesMock.mockRejectedValue(new Error('net'))
    wantSparks(['币安人生USDT'], () => {})
    await flush()
    expect(klinesMock).toHaveBeenCalledTimes(1)
    expect(sparkSettled(['币安人生USDT'])).toBe(true)
  })
})
