import { describe, expect, it } from 'vitest'
import { wallOf } from '../src/orderflow/bands'
import { orderId } from '../src/orderflow/types'
import { DISPLAY_ALL, shows } from '../src/orderflow/settings'
import { defaultOrderFlowDisplay, displayShows, orderFlowDisplayEqual } from '../src/orderflow/group'
import { defaultPrefs, normalizePrefs, syncedSlice } from '../src/m/app/prefs'
import { hydrate } from '../src/app/store'
import { encodeSettings, applySettings, factorySettings, resetSettings, SETTINGS_ID, type SettingsState } from '../src/sync/codec'
import type { BigOrder, Status } from '../src/orderflow/types'
import { corePrint } from '../src/sync/bridge'
import type { SyncObject } from '../src/sync/types'

const order = (status: Status): BigOrder => ({
  venueID: 'binance:spot:BTCUSDT', exchange: 'binance', product: 'spot', side: 'bid',
  bucket: 100, price: 100, firstSeenMs: 0, status, initialNotional: 2e6, notional: 1e6,
  filledNotional: 1e6, threshold: 1e6, endMs: status === 'live' ? null : 60_000, vanishedNotional: null,
})

describe('历史大单', () => {
  it('PC 与手机：关闭只看 live，部分成交仍显示；打开恢复全部结束类型', () => {
    for (const status of ['live', 'filled', 'cancelled', 'lost'] as const) {
      const o = order(status)
      expect(shows({ ...DISPLAY_ALL, history: false }, o)).toBe(status === 'live')
      expect(displayShows({ ...defaultOrderFlowDisplay(), history: false }, o)).toBe(status === 'live')
      expect(shows({ ...DISPLAY_ALL, history: true }, o)).toBe(true)
      expect(displayShows({ ...defaultOrderFlowDisplay(), history: true }, o)).toBe(true)
    }
    expect(orderFlowDisplayEqual({ ...defaultOrderFlowDisplay(), history: false }, defaultOrderFlowDisplay())).toBe(false)
  })
  it('抽屉高亮不能把隐藏的历史单重新画回图上', () => {
    const ended = order('cancelled')
    const keep = (o: BigOrder) => shows({ ...DISPLAY_ALL, history: false }, o)
    expect(wallOf([], orderId(ended), [ended], 1, keep)).toBeNull()
    const live = order('live')
    expect(wallOf([], orderId(live), [live], 1, keep)).not.toBeNull()
  })
  it('旧档案缺字段与坏值默认关；用户打开可保存并同步', () => {
    expect(defaultPrefs().orderFlowHistory).toBe(false)
    expect(normalizePrefs({}).orderFlowHistory).toBe(false)
    expect(normalizePrefs({ orderFlowHistory: 'true' }).orderFlowHistory).toBe(false)
    expect(normalizePrefs({ orderFlowHistory: true }).orderFlowHistory).toBe(true)
    expect(syncedSlice(normalizePrefs({ orderFlowHistory: true })).orderFlowHistory).toBe(true)
    expect(hydrate({}).orderFlowHistory).toBe(false)
  })
  it('电脑偏好与云端双向同步；换账号回到关闭', () => {
    const s: SettingsState = { ...factorySettings(), orderFlowHistory: true }
    const before = corePrint({ ...hydrate({}), orderFlowHistory: false })
    expect(corePrint({ ...hydrate({}), orderFlowHistory: true })).not.toBe(before)
    const pushed = encodeSettings(s, undefined, {})!
    expect(pushed.body.orderFlowHistory).toBe(true)
    const cloud = { ...pushed, body: { orderFlowHistory: false }, id: SETTINGS_ID } as SyncObject
    expect(applySettings(s, cloud, {})).toContain('orderFlowHistory')
    expect(s.orderFlowHistory).toBe(false)
    s.orderFlowHistory = true
    resetSettings(s)
    expect(s.orderFlowHistory).toBe(false)
  })
})
