/* 手机网页 × 契约值规则（2026-10-10「同步字段解耦」）
 *
 * 契约 `rules` 里的正反样例是 iOS 按规则造的，服务端 settings_rules 的测试逐条照办；这里让网页也逐条对：
 *   1. sync/settingsRules 的 `accepts` 和契约样例一致（网页对规则的读法和服务端一样）；
 *   2. 任何样例经 normalizePrefs 洗过之后，都是服务端收的值（客户端只能比服务端严，不能宽）；
 *   3. 出厂值满足规则；契约里每个 synced 字段手机网页都有通用规则或手写清洗。
 */
import { describe, expect, it } from 'vitest'
import { RULES, accepts, cleanByRule, ruleOf, type FieldRule } from '../src/sync/settingsRules'
import { SYNCED_FIELDS, defaultPrefs, normalizePrefs, syncedSlice, type Prefs } from '../src/m/app/prefs'

const generic = Object.entries(RULES).filter(([, r]) => r.type !== 'custom') as [string, FieldRule & { accept?: unknown[]; reject?: unknown[] }][]

describe('契约值规则 · 网页读法', () => {
  it('契约里每个 synced 字段都有规则，字段名与 SYNCED_FIELDS 相同', () => {
    expect(Object.keys(RULES).sort()).toEqual([...SYNCED_FIELDS].sort())
  })

  it('accepts 与契约样例逐条一致', () => {
    let n = 0
    for (const [k, r] of generic) {
      for (const v of r.accept ?? []) { expect(accepts(r, v), `${k} 应收 ${JSON.stringify(v)}`).toBe(true); n++ }
      for (const v of r.reject ?? []) { expect(accepts(r, v), `${k} 应拒 ${JSON.stringify(v)}`).toBe(false); n++ }
    }
    expect(n).toBeGreaterThan(100)
  })

  it('cleanByRule 洗出来的都是服务端收的（含退回的出厂值）', () => {
    const d = defaultPrefs()
    for (const [k, r] of generic) {
      const fallback = d[k as keyof Prefs]
      for (const v of [...(r.accept ?? []), ...(r.reject ?? []), undefined]) {
        const out = cleanByRule(r, v, fallback)
        expect(accepts(r, out), `${k}: ${JSON.stringify(v)} 洗成 ${JSON.stringify(out)}，服务端不收`).toBe(true)
      }
    }
  })

  it('收得下的样例洗完原样保留（bool / enum / number / int）', () => {
    const d = defaultPrefs()
    for (const [k, r] of generic) {
      if (!['bool', 'enum', 'number', 'int'].includes(r.type)) continue
      for (const v of r.accept ?? []) expect(cleanByRule(r, v, d[k as keyof Prefs]), k).toEqual(v)
    }
  })
})

describe('契约值规则 · normalizePrefs', () => {
  it('出厂值满足规则', () => {
    const d = syncedSlice(defaultPrefs())
    for (const [k, r] of generic) expect(accepts(r, d[k]), `${k} 出厂值 ${JSON.stringify(d[k])}`).toBe(true)
  })

  it('任何样例洗进 Prefs 再取出来，服务端都收', () => {
    const cases = Math.max(...generic.map(([, r]) => (r.accept?.length ?? 0) + (r.reject?.length ?? 0)))
    for (let i = 0; i < cases; i++) {
      const raw: Record<string, unknown> = {}
      for (const [k, r] of generic) { const all = [...(r.accept ?? []), ...(r.reject ?? [])]; if (all.length) raw[k] = all[i % all.length] }
      const out = syncedSlice(normalizePrefs(raw))
      for (const [k, r] of generic) expect(accepts(r, out[k]), `第 ${i} 组：${k} = ${JSON.stringify(raw[k])} 洗成 ${JSON.stringify(out[k])}`).toBe(true)
    }
  })

  it('favoritesGroup 按 UTF-8 字节数（服务端口径）：128 字节收，多一个字节退回出厂值', () => {
    expect(normalizePrefs({ favoritesGroup: 'a'.repeat(128) }).favoritesGroup).toBe('a'.repeat(128))
    expect(normalizePrefs({ favoritesGroup: '汉'.repeat(42) }).favoritesGroup).toBe('汉'.repeat(42))
    expect(normalizePrefs({ favoritesGroup: '汉'.repeat(43) }).favoritesGroup).toBe(defaultPrefs().favoritesGroup)
  })

  it('custom 字段不走通用清洗（ruleOf 给的是手写函数名）', () => {
    for (const k of ['compareSymbols', 'orderFlowOverrides', 'learnedDefaults', 'params', 'indicatorColors', 'subHeightOverrides']) {
      expect(ruleOf(k)?.type, k).toBe('custom')
    }
  })
})
