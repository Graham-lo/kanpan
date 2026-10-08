/* 品种身份的三端交叉契约（网页这一端）：读 Backend/kanpan-api/contract/venue-identity-cases.json，
 * accept 每条：parseKey 拆得开、注册表那一家的代号规则（symbolOk）收、displayKey → syncKeyOf 往返一字不差、
 *   同步层（sync/codec webSymbol / instrumentIdentity / compareKey）也收；
 * reject 每条：symbolOk 拒、同步层拒（美元指数 macro/index/DXY 按 identity 的特判，只认这一只）。
 * Rust：sync_validation venue_identity_contract_cases；Swift：KanpanCore InstrumentSyncIdentityTests。 */
import { describe, expect, it } from 'vitest'
import { displayKey, keyOf, parseKey, syncKeyOf } from '../src/market/identity'
import { isMacro } from '../src/market/macro'
import { symbolOk } from '../src/venues'
import { compareKey, instrumentIdentity, webSymbol } from '../src/sync/codec'
import { normKey } from '../src/m/chart/symbolKey'
import raw from '../../Backend/kanpan-api/contract/venue-identity-cases.json'

const cases = raw as unknown as { accept: string[]; reject: string[] }

/** 网页这一端对一条完整键的判定：拆成三段 → 美元指数按 identity 特判，其余按注册表那一家的代号规则 */
function webAccepts(full: string): boolean {
  const k = parseKey(full)
  // 完整键必须真是三段（裸代号兜底成币安的那条路不算「收了这条完整键」）
  if (`${k.venue}/${k.market}/${k.symbol}` !== full) return false
  if (k.venue === 'macro') return k.market === 'index' && isMacro(keyOf(k.venue, k.market, k.symbol))
  return symbolOk(full)
}

describe('三端交叉契约：venue-identity-cases.json', () => {
  it('夹具读得到，两组都不空、互不重叠', () => {
    expect(cases.accept.length).toBeGreaterThan(10)
    expect(cases.reject.length).toBeGreaterThan(10)
    expect(cases.accept.filter(k => cases.reject.includes(k))).toEqual([])
  })

  for (const full of cases.accept) {
    it(`收：${full}`, () => {
      const k = parseKey(full)
      expect(`${k.venue}/${k.market}/${k.symbol}`).toBe(full)
      expect(webAccepts(full)).toBe(true)
      // 网页存的规范键 → 完整三段键：往返一字不差
      const web = displayKey(full)
      expect(syncKeyOf(web)).toBe(full)
      expect(displayKey(web)).toBe(web)
      // 手机网页的归一（大小写容错）也落到同一个键
      expect(normKey(full)).toBe(web)
      // 同步层（自选 / 提醒 / 画线桶 / 对比键）同一条判断
      expect(webSymbol(web)).toBe(true)
      expect(instrumentIdentity(k.venue, k.market, k.symbol)).toBe(true)
      expect(compareKey(full)).toBe(true)
      // 币安 / 美元指数回裸代号，别家留完整键
      if (k.venue === 'binance' || k.venue === 'macro') expect(web.includes('/')).toBe(false)
      else expect(web).toBe(full)
    })
  }

  for (const full of cases.reject) {
    it(`拒：${JSON.stringify(full)}`, () => {
      expect(webAccepts(full)).toBe(false)
      expect(symbolOk(full)).toBe(false)
      const p = full.split('/')
      if (p.length === 3) expect(instrumentIdentity(p[0], p[1], p[2])).toBe(false)
      expect(compareKey(full)).toBe(false)
      // 网页存的键也不许上云：拆不开的写法兜底成币安裸代号，那条也必须被币安规则拒
      expect(webSymbol(displayKey(full))).toBe(false)
    })
  }
})
