/* 手机网页版的同步字段白名单：iOS 契约、服务端 SETTINGS_FIELDS、手机 prefs.ts 三份必须一致。
 * 服务端对含未知字段的操作整条拒绝——多一个键整条队列就堵死，少一个键那项设置就不跟人走。 */
import { describe, expect, it } from 'vitest'
import { DEVICE_ONLY_FIELDS, SYNCED_FIELDS, defaultPrefs, normalizePrefs, syncedSlice } from '../src/m/app/prefs'
import { hydrate } from '../src/m/app/store'
import contractRaw from '../../Backend/kanpan-api/contract/settings-fields.json?raw'
import syncRs from '../../Backend/kanpan-api/src/sync.rs?raw'

const contract = JSON.parse(contractRaw) as {
  fieldClasses: Record<string, string>; wireKeys: string[]; wireOnlyKeys: Record<string, string>
  overlayIndicatorIDs: string[]; subIndicatorIDs: string[]
}

/** 从 sync.rs 抽出 SETTINGS_FIELDS 的字符串字面量（去掉 // 注释） */
function serverSettingsFields(): string[] {
  const m = /pub const SETTINGS_FIELDS:&\[&str\]=&\[([\s\S]*?)\];/.exec(syncRs)
  if (!m) throw new Error('sync.rs 里找不到 SETTINGS_FIELDS')
  const body = m[1].split('\n').map(l => l.replace(/\/\/.*$/, '')).join('\n')
  return [...body.matchAll(/"([^"]+)"/g)].map(x => x[1])
}

const sorted = (a: Iterable<string>) => [...a].sort()

describe('手机网页版 · 同步字段白名单三方对账', () => {
  const mobile = sorted(SYNCED_FIELDS)
  const ios = sorted(Object.entries(contract.fieldClasses).filter(([, c]) => c === 'synced').map(([k]) => k))
  const server = serverSettingsFields()
  const wireOnly = new Set(Object.keys(contract.wireOnlyKeys))

  it('手机 = iOS 契约里 synced 的字段', () => { expect(mobile).toEqual(ios) })
  it('手机 = 服务端 SETTINGS_FIELDS − wireOnlyKeys', () => { expect(mobile).toEqual(sorted(server.filter(k => !wireOnly.has(k)))) })
  it('契约 wireKeys 与服务端 SETTINGS_FIELDS 是同一份', () => { expect(sorted(contract.wireKeys)).toEqual(sorted(server)) })
  it('本机字段与契约 deviceOnly 一致、且不进同步', () => {
    expect(sorted(DEVICE_ONLY_FIELDS)).toEqual(sorted(Object.entries(contract.fieldClasses).filter(([, c]) => c === 'deviceOnly').map(([k]) => k)))
    for (const k of DEVICE_ONLY_FIELDS) expect(mobile).not.toContain(k)
  })
  it('syncedSlice 只带白名单里的键', () => { expect(sorted(Object.keys(syncedSlice(defaultPrefs())))).toEqual(mobile) })
})

describe('手机网页版 · 偏好出厂值与容错', () => {
  it('出厂值照 iOS Prefs', () => {
    const d = defaultPrefs()
    expect(d.interval).toBe('1h')
    expect(d.quickIntervals).toEqual(['5m', '30m', '1h', '4h', '1d', '1w'])
    expect(d.theme).toBe('auto'); expect(d.skin).toBe('sage'); expect(d.redUp).toBe(false)
    expect(d.overlays).toEqual(['MA']); expect(d.subs).toEqual(['VOL', 'OI', 'MACD'])
    expect(Object.keys(d.params).sort()).toEqual(['EMA', 'MA', 'MACD', 'VOL'])
    expect(d.routePolicy).toBe('gateway')
  })
  it('指标 id 与契约词表一致', () => {
    const d = normalizePrefs({ overlays: contract.overlayIndicatorIDs, subs: contract.subIndicatorIDs })
    expect(d.overlays).toEqual(contract.overlayIndicatorIDs)
    // 副图最多三个非 VOL
    expect(d.subs.filter(x => x !== 'VOL').length).toBe(3)
  })
  it('坏值回落出厂值，不丢整份', () => {
    const s = hydrate({ skin: 'neon', theme: 'dark', interval: '7m', quickIntervals: 'x', page: 'nope', symbol: 'ethusdt', symbols: { favorites: ['BTCUSDT', 'BTCUSDT', 3] } })
    expect(s.skin).toBe('sage'); expect(s.theme).toBe('dark'); expect(s.interval).toBe('1h')
    expect(s.quickIntervals.length).toBe(6); expect(s.page).toBe('chart'); expect(s.symbol).toBe('BTCUSDT')
    expect(s.symbols.favorites).toEqual(['BTCUSDT'])
  })

  it('一律绿涨红跌（2026-10-03）：出厂绿涨；迁移之前存的红涨迁一次，迁过之后用户自己选的红涨留住', () => {
    expect(hydrate({}).redUp).toBe(false)
    const once = hydrate({ redUp: true })
    expect(once.redUp).toBe(false)
    expect(once.greenUpMigrated).toBe(true)
    expect(hydrate({ ...once, redUp: true } as unknown as Record<string, unknown>).redUp).toBe(true)
  })
  it('横屏根间距（2026-10-05）：老档案没有就取同一份里的 barSpacing，之后两份各走各的；夹到 1.6…40', () => {
    expect(defaultPrefs().landscapeBarSpacing).toBe(4)
    expect(normalizePrefs({ barSpacing: 9 }).landscapeBarSpacing).toBe(9)
    expect(normalizePrefs({ barSpacing: 9, landscapeBarSpacing: 'x' }).landscapeBarSpacing).toBe(9)
    expect(normalizePrefs({ barSpacing: 9, landscapeBarSpacing: 3 }).landscapeBarSpacing).toBe(3)
    expect(normalizePrefs({ landscapeBarSpacing: 500 }).landscapeBarSpacing).toBe(40)
    expect(normalizePrefs({ barSpacing: 0.1 }).landscapeBarSpacing).toBe(1.6)
  })
})
