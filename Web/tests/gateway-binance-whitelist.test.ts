/* Web 深度审查 C 线 2026-10-05 · 网页走网关时拼出来的币安路径与查询参数，必须都在服务端透传白名单里
 * （Backend/kanpan-api/src/venues/binance.rs 的 upstream_of / query_ok；不在里面的服务端回 404 / 400，那条数据在网关线路上整条是空的）。
 * 原来手机网页的基差副图（futures/data/basis?pair=…&contractType=PERPETUAL）两样都不在白名单里。 */
import { describe, expect, it } from 'vitest'
import RS from '../../Backend/kanpan-api/src/venues/binance/mod.rs?raw'
import { EXTERNAL_IDS, fetchMetric } from '../src/m/chart/external.source'

const SOURCES = import.meta.glob('../src/**/*.ts', { query: '?raw', import: 'default', eager: true }) as Record<string, string>
const body = (fn: string): string => { const i = RS.indexOf(`fn ${fn}(`); return RS.slice(i, RS.indexOf('\n}\n', i)) }
const PATHS = new Set([...body('upstream_of').matchAll(/"((?:fapi|dapi|futures)\/[^"]+)"/g)].map(m => m[1]))
const KEYS = new Set([...(/matches!\(key,([^)]*)\)/.exec(body('query_ok'))![1]).matchAll(/"([^"]+)"/g)].map(m => m[1]))

describe('网关透传白名单 × 网页拼的币安请求', () => {
  it('白名单解析得到（防止改了 binance.rs 的写法后这条用例空转）', () => {
    expect(PATHS.has('fapi/v1/klines')).toBe(true)
    expect(KEYS.has('symbol')).toBe(true)
  })

  it('源码里写到的每一条币安合约路径都放行', () => {
    const used = new Set<string>()
    expect(Object.keys(SOURCES).length).toBeGreaterThan(50)
    for (const text of Object.values(SOURCES)) for (const m of text.matchAll(/\b((?:fapi|dapi)\/v\d\/[A-Za-z0-9/]+|futures\/data\/[A-Za-z]+)/g)) used.add(m[1])
    expect(used.size).toBeGreaterThan(5)
    expect([...used].filter(p => !PATHS.has(p))).toEqual([])
  })

  it('四条外部副图（持仓量、多空比、主动买卖比、基差）拼出来的路径与参数都放行', async () => {
    const urls: string[] = []
    const now = 1_800_000_000_000
    for (const id of EXTERNAL_IDS) {
      await fetchMetric(id, 'BTCUSDT', '1h', now - 86_400_000, now, now, async <T>(u: string) => { urls.push(u); return [] as unknown as T })
    }
    expect(urls).toHaveLength(4)
    for (const u of urls) {
      const url = new URL(u)
      expect(PATHS.has(url.pathname.slice(1)), url.pathname).toBe(true)
      for (const k of url.searchParams.keys()) expect(KEYS.has(k), `${url.pathname} ${k}`).toBe(true)
    }
  })
})
