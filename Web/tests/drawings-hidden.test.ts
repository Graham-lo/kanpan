/* 2026-10-06 用户：「画线要给一个主动隐藏的按钮，不然竖屏情况下我既想保留警报又不想看画线体验非常不好」。
 * 同步字段 drawingsHidden（出厂 false，跟账号走）：手机网页在「分析」面板画线节一行开关，电脑网页是画线工具条的眼睛（st.drawHidden）。
 * 藏着时竖屏不画、点不中画线，提醒照判、图上改画提醒线；手机横屏画线台一律显示、看朋友分享的线时自己的线也照画。 */
import { describe, expect, it } from 'vitest'
import { SYNCED_FIELDS, defaultPrefs, normalizePrefs } from '../src/m/app/prefs'
import { applySettings as mApply, encodeSettings as mEncode, settingsBody } from '../src/m/app/syncCodec'
import { st as mst } from '../src/m/app/store'
import { analysisHTML, type PanelContext } from '../src/m/pages/chart/panels'
import {
  SETTINGS_FIELDS, applySettings, decodeSetting, encodeSetting, encodeSettings, factorySettings, putSetting, resetSettings, webSetting,
} from '../src/sync/codec'
import panelSource from '../src/m/pages/chart/panels.ts?raw'
import mChartSource from '../src/m/pages/chart.ts?raw'
import engineSource from '../src/m/chart/index.ts?raw'
import pcChartSource from '../src/pages/chart.ts?raw'
import glueSource from '../src/sync/glue.ts?raw'
import contract from '../../Backend/kanpan-api/contract/settings-fields.json'

describe('手机网页偏好 drawingsHidden', () => {
  it('出厂 false、进同步字段、坏值回出厂', () => {
    expect(defaultPrefs().drawingsHidden).toBe(false)
    expect(SYNCED_FIELDS).toContain('drawingsHidden')
    expect(normalizePrefs({ drawingsHidden: true }).drawingsHidden).toBe(true)
    expect(normalizePrefs({ drawingsHidden: 'yes' }).drawingsHidden).toBe(false)
    expect(normalizePrefs({}).drawingsHidden).toBe(false)
  })
  it('契约里是 synced 字段（与 iOS、服务端同一份）', () => {
    expect(JSON.stringify(contract)).toContain('"drawingsHidden"')
  })
  it('上云、另一台拉下来原样装回', () => {
    const a = defaultPrefs(); a.drawingsHidden = true
    expect(settingsBody(a).drawingsHidden).toBe(true)
    const b = defaultPrefs()
    mApply(b, mEncode(a, undefined, {})!, {})
    expect(b.drawingsHidden).toBe(true)
  })
})

describe('手机网页「分析」面板：隐藏画线一行', () => {
  const ctx: PanelContext = { symbol: () => 'BTCUSDT', port: () => null, onDraw: () => {} }
  it('在「画线」节、紧跟「开始画线」，开关状态照 st.drawingsHidden', () => {
    mst.drawingsHidden = false
    const off = analysisHTML(ctx)
    const draw = off.indexOf('开始画线'), hide = off.indexOf('隐藏画线'), ind = off.indexOf('cp-gt">指标')
    expect(draw).toBeGreaterThan(0)
    expect(hide).toBeGreaterThan(draw)
    if (ind > 0) expect(hide).toBeLessThan(ind)
    expect(off).toMatch(/aria-checked="false" aria-label="隐藏画线" data-act="draw-hide"/)
    mst.drawingsHidden = true
    expect(analysisHTML(ctx)).toMatch(/aria-checked="true" aria-label="隐藏画线" data-act="draw-hide"/)
    mst.drawingsHidden = false
  })
  it('点开关翻转偏好并落盘（save 触发同步）', () => {
    expect(panelSource).toContain("case 'draw-hide': st.drawingsHidden = !st.drawingsHidden; save(); break")
  })
})

describe('手机网页行情页：偏好 → 引擎', () => {
  it('建图与 syncChart 都按 drawingsOn() 设 drawings；看朋友分享的线时照画', () => {
    expect(mChartSource).toContain('const drawingsOn = (): boolean => !st.drawingsHidden || !!preview?.previewing()')
    expect(mChartSource).toMatch(/setCandleStyle\(\{ kind: st\.candleKind, portraitHeight: st\.portraitHeight, drawings: drawingsOn\(\) \}\)/)
    expect(mChartSource).toMatch(/mainInverted: st\.mainInverted, drawings: drawingsOn\(\) \}\)/)
    // 改了偏好要能触发 setCandleStyle：lookKey 里带着它
    expect(mChartSource).toMatch(/const lookKeyOf = [^\n]*\n[^\n]*drawingsOn\(\)\]\)/)
  })
  it('横屏画线台一律画线、对比态一律不画（引擎 compose）', () => {
    expect(engineSource).toMatch(/if \(landscape\) \{ options\.drawings = true/)
    expect(engineSource).toContain('if (comparing) options.drawings = false')
  })
})

describe('电脑网页：drawingsHidden ↔ st.drawHidden', () => {
  const base = () => ({ ...factorySettings() })
  it('进同步字段、出厂 false、换人回出厂', () => {
    expect(SETTINGS_FIELDS).toContain('drawingsHidden')
    expect(factorySettings().drawHidden).toBe(false)
    const s = { ...base(), drawHidden: true }
    expect(resetSettings(s)).toContain('drawingsHidden')
    expect(s.drawHidden).toBe(false)
  })
  it('编解码：只认布尔', () => {
    expect(webSetting({ ...base(), drawHidden: true }, 'drawingsHidden')).toBe(true)
    expect(webSetting({ ...base(), drawHidden: undefined }, 'drawingsHidden')).toBe(false)
    expect(encodeSetting('drawingsHidden', true, undefined)).toBe(true)
    expect(decodeSetting('drawingsHidden', true, base())).toBe(true)
    expect(decodeSetting('drawingsHidden', 'true', base())).toBeUndefined()
    const s = base(); putSetting(s, 'drawingsHidden', true); expect(s.drawHidden).toBe(true)
  })
  it('本机点眼睛 → 推 drawingsHidden；手机推下来 → 装进 st.drawHidden', () => {
    const seen: Record<string, never> = {}
    const s = base()
    encodeSettings(s, undefined, seen)
    s.drawHidden = true
    const o = encodeSettings(s, undefined, seen)!
    expect(o.body.drawingsHidden).toBe(true)
    const t = base(), seen2 = {}
    expect(applySettings(t, o, seen2)).toContain('drawingsHidden')
    expect(t.drawHidden).toBe(true)
  })
  it('眼睛与同步过来的值走同一个 applyDrawingsHidden（各格收起画线、刷新工具条）', () => {
    expect(pcChartSource).toMatch(/function toggleHideDrawings\(\): void \{\n  st\.drawHidden = !st\.drawHidden\n  applyDrawingsHidden\(\)/)
    expect(pcChartSource).toContain('export function applyDrawingsHidden(): void')
    expect(glueSource).toContain("if (r.settings.includes('drawingsHidden')) applyDrawingsHidden()")
  })
})
