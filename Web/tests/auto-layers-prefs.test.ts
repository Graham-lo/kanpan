/* 2026-10-10 公允价值缺口（FVG）第 2 步：跟人走的偏好字段 autoLayers（字符串数组，白名单 AUTO_LAYERS = ['FVG']，出厂空）。
 * iOS Prefs.autoLayers、服务端 sync_validation AUTO_LAYERS、手机网页 Prefs.autoLayers、电脑网页 st.autoLayers 同一个字段。
 * 读的一侧：认不出的名字丢掉、去重，形状不对回出厂；开关界面在后面几步。 */
import { describe, expect, it } from 'vitest'
import { SYNCED_FIELDS, defaultPrefs, normalizePrefs } from '../src/m/app/prefs'
import { applySettings as mApply, encodeSettings as mEncode, settingsBody } from '../src/m/app/syncCodec'
import { hydrate } from '../src/app/store'
import {
  SETTINGS_FIELDS, applySettings, cleanAutoLayers, decodeSetting, encodeSetting, encodeSettings, factorySettings, putSetting, resetSettings, webSetting,
} from '../src/sync/codec'
import { AUTO_LAYERS } from '../src/analysis/fvg'
import contract from '../../Backend/kanpan-api/contract/settings-fields.json'

describe('autoLayers 词表', () => {
  it('网页白名单 = 契约 autoLayerIDs（iOS AutoLayer 生成）', () => {
    expect([...AUTO_LAYERS]).toEqual((contract as unknown as { autoLayerIDs: string[] }).autoLayerIDs)
    expect((contract as unknown as { fieldClasses: Record<string, string> }).fieldClasses.autoLayers).toBe('synced')
  })
})

describe('手机网页偏好 autoLayers', () => {
  it('出厂空、进同步字段', () => {
    expect(defaultPrefs().autoLayers).toEqual([])
    expect(SYNCED_FIELDS).toContain('autoLayers')
  })
  it('认不出的名字丢掉、去重；形状不对回出厂', () => {
    expect(normalizePrefs({ autoLayers: ['X', 'FVG', 'fvg', 'FVG', 3] }).autoLayers).toEqual(['FVG'])
    expect(normalizePrefs({ autoLayers: ['X'] }).autoLayers).toEqual([])
    expect(normalizePrefs({ autoLayers: 'FVG' }).autoLayers).toEqual([])
    expect(normalizePrefs({}).autoLayers).toEqual([])
  })
  it('上云、另一台拉下来原样装回', () => {
    const a = defaultPrefs(); a.autoLayers = ['FVG']
    expect(settingsBody(a).autoLayers).toEqual(['FVG'])
    const b = defaultPrefs()
    mApply(b, mEncode(a, undefined, {})!, {})
    expect(b.autoLayers).toEqual(['FVG'])
  })
})

describe('电脑网页 autoLayers ↔ st.autoLayers', () => {
  const base = () => ({ ...factorySettings() })
  it('本机存档：出厂空、认不出的丢掉', () => {
    expect(hydrate({}).autoLayers).toEqual([])
    expect(hydrate({ autoLayers: ['FVG', 'X', 'FVG'] } as never).autoLayers).toEqual(['FVG'])
    expect(hydrate({ autoLayers: 'FVG' } as never).autoLayers).toEqual([])
    expect(cleanAutoLayers(null)).toEqual([])
  })
  it('进同步字段、出厂空、换人回出厂', () => {
    expect(SETTINGS_FIELDS).toContain('autoLayers')
    expect(factorySettings().autoLayers).toEqual([])
    const s = { ...base(), autoLayers: ['FVG' as const] }
    expect(resetSettings(s)).toContain('autoLayers')
    expect(s.autoLayers).toEqual([])
  })
  it('编解码：只认白名单数组；网页认不出的层推的时候原地留着', () => {
    expect(webSetting({ ...base(), autoLayers: ['FVG'] }, 'autoLayers')).toEqual(['FVG'])
    expect(webSetting({ ...base(), autoLayers: undefined }, 'autoLayers')).toEqual([])
    expect(encodeSetting('autoLayers', ['FVG'], undefined)).toEqual(['FVG'])
    expect(encodeSetting('autoLayers', [], ['FVG'])).toEqual([])
    expect(encodeSetting('autoLayers', ['FVG'], ['NEW'])).toEqual(['NEW', 'FVG'])
    expect(decodeSetting('autoLayers', ['FVG', 'X'], base())).toEqual(['FVG'])
    expect(decodeSetting('autoLayers', 'FVG', base())).toBeUndefined()
    const s = base(); putSetting(s, 'autoLayers', ['FVG']); expect(s.autoLayers).toEqual(['FVG'])
  })
  it('本机开 → 推 autoLayers；另一台拉下来装进 st.autoLayers', () => {
    const seen: Record<string, never> = {}
    const s = base()
    encodeSettings(s, undefined, seen)
    s.autoLayers = ['FVG']
    const o = encodeSettings(s, undefined, seen)!
    expect(o.body.autoLayers).toEqual(['FVG'])
    const t = base(), seen2 = {}
    expect(applySettings(t, o, seen2)).toContain('autoLayers')
    expect(t.autoLayers).toEqual(['FVG'])
  })
})
