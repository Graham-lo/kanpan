/* Hkline Web · 画线的「默认样式」与「模板」（设置对话框底部的模板菜单）
 *
 * 一份预设 = 主字段（颜色、粗细、线型、填色、刻度，模板还可带文字）+ 扩展样式 style。
 *   · 存为默认：这把工具以后新画的都照它（st.drawDefaults[工具]），优先于同族记忆与出厂值
 *   · 模板：每把工具最多 16 个、有名字（st.drawTemplates[工具]）
 * 两样都随账号同步：drawingPreferences「tools」对象里的 `webStyles/<KIND>` 与 `templates/<KIND>`（KIND 是契约种类名，
 * 服务端 sync_validation.rs 的 web_style / templates 校验）；手机端不读，原样带着走。
 */
import type { Drawing, DrawingType } from './chart'
import { CONTRACT_KIND, WEB_TYPE, isDrawingType, levelsOk, textOk, usesLevels } from './drawTools'
import { MAIN_DEF, cleanStyle, factoryLevels } from './drawSpec'
import type { DrawStyle } from './drawStyle'

export interface DrawPreset { color?: string; width?: number; dash?: 'dashed' | 'dotted'; filled?: boolean; levels?: number[]; text?: string; style?: DrawStyle }
export interface DrawTemplate extends DrawPreset { name: string }
export const TEMPLATE_MAX = 16
export const TEMPLATE_NAME_MAX = 64

const HEX = /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/
const isObj = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v)
const widthOk = (w: unknown): w is number => typeof w === 'number' && Number.isFinite(w) && w >= 0.5 && w <= 6

/** 一条画线现在的样子（存为默认不带文字，模板带） */
export function presetOf(d: Drawing, withText: boolean): DrawPreset {
  const p: DrawPreset = {}
  if (d.color && HEX.test(d.color)) p.color = d.color
  if (widthOk(d.width)) p.width = d.width
  if (d.dash) p.dash = d.dash
  if (d.filled === false) p.filled = false
  if (d.levels && levelsOk(d.levels)) p.levels = [...d.levels]
  if (withText && d.text) p.text = d.text
  const s = d.style ? cleanStyle(d.type, d.style) : null
  if (s) p.style = structuredClone(s)
  return p
}

/** 出厂：TradingView 的主样式 + 出厂刻度 */
export function factoryPreset(t: DrawingType): DrawPreset {
  const m = MAIN_DEF[t], f = factoryLevels(t)
  const p: DrawPreset = { color: m?.color ?? '#2962FF', width: m?.width ?? 2 }
  if (m?.dash) p.dash = m.dash
  if (m?.filled === false) p.filled = false
  if (f.levels) p.levels = f.levels
  if (f.style) p.style = f.style
  return p
}

/** 把预设套到一条画线上（主字段与 style 整份换掉；预设里没有的回到「没设」） */
export function applyPreset(d: Drawing, p: DrawPreset): void {
  const f = factoryPreset(d.type)
  d.color = p.color ?? f.color
  d.width = p.width ?? f.width
  if (p.dash) d.dash = p.dash; else delete d.dash
  if (p.filled === false) d.filled = false; else delete d.filled
  if (p.levels) d.levels = [...p.levels]
  else if (usesLevels(d.type)) { if (f.levels) d.levels = [...f.levels]; else delete d.levels }
  else delete d.levels
  if (p.text !== undefined) { if (p.text) d.text = p.text; else delete d.text }
  const s = p.style ? cleanStyle(d.type, p.style) : null
  if (s) d.style = structuredClone(s); else delete d.style
}

/** 清洗一份预设（读档、同步来的）；一个可用的键都没有返回 null */
export function cleanPreset(t: DrawingType, raw: unknown, withText = false): DrawPreset | null {
  if (!isObj(raw)) return null
  const p: DrawPreset = {}
  if (typeof raw.color === 'string' && HEX.test(raw.color)) p.color = raw.color
  if (widthOk(raw.width)) p.width = raw.width
  if (raw.dash === 'dashed' || raw.dash === 'dotted') p.dash = raw.dash
  if (raw.filled === false) p.filled = false
  if (levelsOk(raw.levels)) p.levels = [...raw.levels]
  if (withText && typeof raw.text === 'string' && raw.text && textOk(raw.text)) p.text = raw.text
  const s = cleanStyle(t, raw.style)
  if (s) p.style = s
  return Object.keys(p).length ? p : null
}
function cleanName(v: unknown): string | null {
  if (typeof v !== 'string') return null
  const n = v.trim()
  return n && [...n].length <= TEMPLATE_NAME_MAX ? n : null
}
export function cleanTemplateList(t: DrawingType, raw: unknown): DrawTemplate[] {
  if (!Array.isArray(raw)) return []
  const out: DrawTemplate[] = []
  for (const x of raw) {
    if (!isObj(x)) continue
    const name = cleanName(x.name); if (!name || out.some(o => o.name === name)) continue
    out.push({ name, ...(cleanPreset(t, x, true) ?? {}) })
    if (out.length >= TEMPLATE_MAX) break
  }
  return out
}
/** 读档：工具 → 默认 */
export function cleanDefaults(raw: unknown): Record<string, DrawPreset> {
  const out: Record<string, DrawPreset> = {}
  if (!isObj(raw)) return out
  for (const [t, v] of Object.entries(raw)) { if (!isDrawingType(t) || !CONTRACT_KIND[t]) continue; const p = cleanPreset(t, v); if (p) out[t] = p }
  return out
}
/** 读档：工具 → 模板 */
export function cleanTemplates(raw: unknown): Record<string, DrawTemplate[]> {
  const out: Record<string, DrawTemplate[]> = {}
  if (!isObj(raw)) return out
  for (const [t, v] of Object.entries(raw)) { if (!isDrawingType(t) || !CONTRACT_KIND[t]) continue; const l = cleanTemplateList(t, v); if (l.length) out[t] = l }
  return out
}

// ------------------------------------------------------------ 同步（drawingPreferences「tools」里的拍平键）
type J = Record<string, unknown>
/** 默认 → `webStyles/<KIND>` 的值（服务端只卡形状：对象、≤ 8 KB、≤ 4 层） */
function encodeDefault(p: DrawPreset): J {
  const o: J = {}
  if (p.color) o.color = p.color
  if (p.width != null) o.width = p.width
  if (p.dash) o.dash = p.dash
  if (p.filled === false) o.filled = false
  if (p.levels) o.levels = [...p.levels]
  if (p.style) o.style = structuredClone(p.style)
  return o
}
/** 模板 → `templates/<KIND>` 里的一项（键与值照画线本身：color 是 { value }、粗细叫 lineWidth；不写 null） */
function encodeTemplate(p: DrawTemplate): J {
  const o: J = { name: p.name }
  if (p.color) o.color = { value: p.color }
  if (p.width != null) o.lineWidth = p.width
  o.dash = p.dash ?? 'solid'
  if (p.filled === false) o.filled = false
  if (p.levels) o.levels = [...p.levels]
  if (p.text) o.text = p.text
  if (p.style) o.style = structuredClone(p.style)
  return o
}
function decodeTemplate(t: DrawingType, x: unknown): unknown {
  if (!isObj(x)) return null
  return { ...x, color: isObj(x.color) ? x.color.value : undefined, width: x.lineWidth }
}

export const PREF_ROOTS = ['webStyles', 'templates'] as const
const isMine = (k: string): boolean => PREF_ROOTS.some(r => k.startsWith(r + '/'))

/** 写回云端对象的 body：别的键（手机的工具偏好）原样留着，这两类按本机重写。
 *  模板清空了写 []（服务端也收 null，但空数组更明白「这把工具没有模板」） */
export function encodePrefs(defaults: Record<string, DrawPreset>, templates: Record<string, DrawTemplate[]>, prev: Record<string, unknown>): Record<string, unknown> {
  const body: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(prev)) if (!isMine(k)) body[k] = v
  for (const [t, p] of Object.entries(defaults)) { const kind = CONTRACT_KIND[t as DrawingType]; if (kind) body['webStyles/' + kind] = encodeDefault(p) }
  for (const k of Object.keys(prev)) if (k.startsWith('templates/') && Array.isArray(prev[k]) && (prev[k] as unknown[]).length) body[k] = []
  for (const [t, l] of Object.entries(templates)) { const kind = CONTRACT_KIND[t as DrawingType]; if (kind && l.length) body['templates/' + kind] = l.map(encodeTemplate) }
  return body
}
export function decodePrefs(body: Record<string, unknown> | undefined): { defaults: Record<string, DrawPreset>; templates: Record<string, DrawTemplate[]> } {
  const defaults: Record<string, DrawPreset> = {}, templates: Record<string, DrawTemplate[]> = {}
  for (const [k, v] of Object.entries(body ?? {})) {
    const i = k.indexOf('/'); if (i < 0) continue
    const root = k.slice(0, i), t = WEB_TYPE[k.slice(i + 1)]
    if (!t) continue
    if (root === 'webStyles') { const p = cleanPreset(t, v); if (p) defaults[t] = p }
    if (root === 'templates' && Array.isArray(v)) { const l = cleanTemplateList(t, v.map(x => decodeTemplate(t, x))); if (l.length) templates[t] = l }
  }
  return { defaults, templates }
}
