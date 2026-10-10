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

/** 只有电脑网页版读写、不进 iOS 契约的设置字段（sync.rs WEB_ONLY_SETTINGS_FIELDS，如多套图表布局 chartLayouts） */
function webOnlyFields(): Set<string> {
  const m = /pub const WEB_ONLY_SETTINGS_FIELDS:&\[&str\]=&\[([^\]]*)\];/.exec(syncRs)
  return new Set(m ? [...m[1].matchAll(/"([^"]+)"/g)].map(x => x[1]) : [])
}

const sorted = (a: Iterable<string>) => [...a].sort()

describe('手机网页版 · 同步字段白名单三方对账', () => {
  const mobile = sorted(SYNCED_FIELDS)
  const ios = sorted(Object.entries(contract.fieldClasses).filter(([, c]) => c === 'synced').map(([k]) => k))
  const webOnly = webOnlyFields()
  const server = serverSettingsFields().filter(k => !webOnly.has(k))
  const wireOnly = new Set(Object.keys(contract.wireOnlyKeys))

  it('手机 = iOS 契约里 synced 的字段', () => { expect(mobile).toEqual(ios) })
  it('网页独有字段在服务端白名单里、不在契约与手机里', () => {
    expect([...webOnly]).toContain('chartLayouts')
    for (const k of webOnly) { expect(serverSettingsFields()).toContain(k); expect(contract.wireKeys).not.toContain(k); expect(mobile).not.toContain(k) }
  })
  it('手机 = 服务端 SETTINGS_FIELDS − wireOnlyKeys', () => { expect(mobile).toEqual(sorted(server.filter(k => !wireOnly.has(k)))) })
  it('2026-10-10 起 wireOnlyKeys 是空表：退役的键三方都不认（服务端进 RETIRED_SETTINGS_FIELDS）', () => {
    expect(wireOnly.size).toBe(0)
    const retired = /pub const RETIRED_SETTINGS_FIELDS:&\[&str\]=&\[([\s\S]*?)\];/.exec(syncRs)
    expect(retired).toBeTruthy()
    for (const k of ['portraitHeight', 'indicatorLayouts', 'styleID', 'drawToolGroup', 'compactValues', 'routePolicy']) {
      expect(retired![1]).toContain(`"${k}"`)
      expect(server).not.toContain(k)
      expect(mobile).not.toContain(k)
    }
  })
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

describe('手机网页版 · 复盘本停在哪一面、哪一档（2026-10-10，跟人走）', () => {
  it('出厂停在「观点」「待判定」，两个都进同步', () => {
    const d = defaultPrefs()
    expect(d.reviewSegment).toBe('views')
    expect(d.reviewBookFilter).toBe('todo')
    expect(SYNCED_FIELDS).toContain('reviewSegment')
    expect(SYNCED_FIELDS).toContain('reviewBookFilter')
    expect(syncedSlice({ ...d, reviewSegment: 'trades', reviewBookFilter: 'decided' })).toMatchObject({ reviewSegment: 'trades', reviewBookFilter: 'decided' })
  })
  it('认得的照读，认不出的（大小写不对、空、类型错、更高版本的新档位）退回出厂、只丢那一项', () => {
    for (const seg of ['views', 'trades'] as const) for (const f of ['all', 'todo', 'decided'] as const) {
      const p = normalizePrefs({ reviewSegment: seg, reviewBookFilter: f })
      expect([p.reviewSegment, p.reviewBookFilter]).toEqual([seg, f])
    }
    for (const bad of [{ reviewSegment: 'Trades', reviewBookFilter: 'ALL' }, { reviewSegment: '', reviewBookFilter: '' },
      { reviewSegment: 7, reviewBookFilter: ['all'] }, { reviewSegment: 'notes', reviewBookFilter: 'done' }]) {
      const p = normalizePrefs(bad)
      expect([p.reviewSegment, p.reviewBookFilter]).toEqual(['views', 'todo'])
    }
    const half = normalizePrefs({ reviewSegment: 'trades', reviewBookFilter: 'nope', skin: 'terra' })
    expect([half.reviewSegment, half.reviewBookFilter, half.skin]).toEqual(['trades', 'todo', 'terra'])
  })
})

describe('手机网页版 · 上次用的画线工具按画线词表清洗', () => {
  it('认得的留着，认不出的（更高版本的新工具、手改的档、类型错）退回空', () => {
    expect(normalizePrefs({ lastDrawTool: 'trend' }).lastDrawTool).toBe('trend')
    expect(normalizePrefs({ lastDrawTool: 'fibonacci' }).lastDrawTool).toBe('fibonacci')
    for (const bad of ['laser', 'Trend', 'trend ', 3, null, ['trend']]) expect(normalizePrefs({ lastDrawTool: bad }).lastDrawTool).toBe('')
    expect(defaultPrefs().lastDrawTool).toBe('')
  })
})

describe('手机网页版 · 2026-10-10 退役的键', () => {
  it('老档里带着 portraitHeight / indicatorLayouts 照常读，其余字段一个不丢，也不再写回', () => {
    const p = normalizePrefs({
      skin: 'terra', interval: '4h', subs: ['VOL', 'MACD'], portraitHeight: 0.62,
      indicatorLayouts: { others: { hour: { subs: ['RSI'] } }, shared: { overlays: ['EMA'] } },
    })
    expect([p.skin, p.interval]).toEqual(['terra', '4h'])
    expect(p.subs).toEqual(['VOL', 'MACD'])
    expect(p.overlays).toEqual(defaultPrefs().overlays)
    expect('portraitHeight' in p).toBe(false)
    expect('indicatorLayouts' in p).toBe(false)
    expect(Object.keys(syncedSlice(p))).not.toContain('portraitHeight')
    expect(Object.keys(syncedSlice(p))).not.toContain('indicatorLayouts')
  })
})
