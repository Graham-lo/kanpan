/* Hkline Web · 画线的扩展样式（Drawing.style）
 *
 * 主字段（color / width / dash / filled / levels / text）照旧是三端共用的主样式；TradingView 那套设置里多出来的项
 * （成交量分布的四色与各条线、延伸、箭头、标签、背景、可见周期……）都放进这一个可选对象 style，按种类白名单收键。
 * 这里管：取值（style 叠在出厂值上）与清洗（cleanStyle：不认识的键、坏值一律丢，体积与嵌套有上限）。
 */
import type { VpvrMode } from './overlays'
import { PROFILE, profileDefaults, type LineDash, type ProfileLine, type ProfileLook } from './volumeProfile'

export type StyleValue = boolean | number | string | StyleObject
export interface StyleObject { [k: string]: StyleValue }
export type DrawStyle = StyleObject

const COLOR = /^#(?:[0-9a-f]{6}|[0-9a-f]{8})$/i
export const styleColorOk = (c: unknown): c is string => typeof c === 'string' && COLOR.test(c)
const num = (v: unknown, lo: number, hi: number): v is number => typeof v === 'number' && Number.isFinite(v) && v >= lo && v <= hi
const isObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v)
export const DASHES: readonly LineDash[] = ['solid', 'dashed', 'dotted']

/** style 里一条线：{ on, color, width, dash }（每项都可缺，缺的取出厂） */
export function lineOf(v: unknown, def: ProfileLine): ProfileLine {
  if (!isObj(v)) return def
  return {
    on: typeof v.on === 'boolean' ? v.on : def.on,
    color: styleColorOk(v.color) ? v.color : def.color,
    width: num(v.width, 0.5, 6) ? v.width : def.width,
    dash: DASHES.includes(v.dash as LineDash) ? v.dash as LineDash : def.dash,
    extend: typeof v.extend === 'boolean' ? v.extend : def.extend,
  }
}

// ------------------------------------------------------------ 成交量分布（fvp / anchoredVolumeProfile）
/** 输入页（TV 出厂：行数 24、买卖分开、价值区 70%、不向右延伸） */
export interface ProfileInputs { rowsLayout: 'rows' | 'ticks'; rowSize: number; volume: VpvrMode; vaPct: number; extendRight: boolean }
export const PROFILE_INPUT_DEFAULTS: ProfileInputs = { rowsLayout: 'rows', rowSize: PROFILE.rows, volume: 'split', vaPct: 70, extendRight: false }
export function profileInputs(s: DrawStyle | undefined): ProfileInputs {
  const x = s ?? {}
  return {
    rowsLayout: x.rowsLayout === 'ticks' ? 'ticks' : 'rows',
    rowSize: num(x.rowSize, 1, 1000) ? Math.round(x.rowSize) : PROFILE.rows,
    volume: x.volume === 'total' || x.volume === 'delta' ? x.volume : 'split',
    vaPct: num(x.vaPct, 1, 100) ? x.vaPct : 70,
    extendRight: x.extendRight === true,
  }
}
export function profileLookOf(s: DrawStyle | undefined, dark: boolean): ProfileLook {
  const d = profileDefaults(dark), x = s ?? {}
  const col = (k: string, def: string) => styleColorOk(x[k]) ? x[k] as string : def
  const bg = isObj(x.bg) ? x.bg : {}
  return {
    vp: typeof x.vp === 'boolean' ? x.vp : d.vp,
    widthPct: num(x.widthPct, 1, 100) ? x.widthPct : d.widthPct,
    placement: x.placement === 'right' ? 'right' : x.placement === 'left' ? 'left' : d.placement,
    up: col('up', d.up), down: col('down', d.down), vaUp: col('vaUp', d.vaUp), vaDown: col('vaDown', d.vaDown),
    values: typeof x.values === 'boolean' ? x.values : d.values,
    valuesColor: col('valuesColor', d.valuesColor),
    vah: lineOf(x.vah, d.vah), val: lineOf(x.val, d.val), poc: lineOf(x.poc, d.poc),
    devPoc: lineOf(x.devPoc, d.devPoc), devVa: lineOf(x.devVa, d.devVa),
    bg: { on: typeof bg.on === 'boolean' ? bg.on : d.bg.on, color: styleColorOk(bg.color) ? bg.color : d.bg.color },
  }
}

// ------------------------------------------------------------ 清洗（读档、同步进出都走它）
/** 和服务端 sync_validation `drawing_style` 同一组上限：序列化 ≤ 4 KB；键 1…32 个 ASCII 字母数字、字母打头；
 *  值是布尔、有限数、≤ 64 字节的串，或同样规则的对象，最多套三层；不收数组与 null。 */
export const STYLE_MAX_BYTES = 4096
const STYLE_KEY = /^[A-Za-z][A-Za-z0-9]{0,31}$/
const enc = new TextEncoder()
function cleanLevel(v: Record<string, unknown>, depth: number): StyleObject {
  const out: StyleObject = {}
  for (const [k, x] of Object.entries(v)) {
    if (!STYLE_KEY.test(k)) continue
    if (typeof x === 'boolean' || (typeof x === 'number' && Number.isFinite(x) && Math.abs(x) <= 1e15)) out[k] = x
    else if (typeof x === 'string' && enc.encode(x).length <= 64) out[k] = x
    else if (isObj(x) && depth < 3) out[k] = cleanLevel(x, depth + 1)
  }
  return out
}
/** 扩展样式的规范形：坏键、坏值丢掉；整份超过上限或清完是空的返回 undefined（就是「没有扩展样式」） */
export function cleanStyle(v: unknown): DrawStyle | undefined {
  if (!isObj(v)) return undefined
  const out = cleanLevel(v, 1)
  if (!Object.keys(out).length || enc.encode(JSON.stringify(out)).length > STYLE_MAX_BYTES) return undefined
  return out
}
