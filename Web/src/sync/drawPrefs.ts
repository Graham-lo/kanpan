/* Hkline Web · 画线工具偏好 ↔ 云端 drawingPreferences（id "tools"，和 iOS / 手机网页同一个对象；纯函数，不碰 DOM）
 *
 * 电脑网页只替其中三样说话（OWNED 按路径第一段认领，收藏 favorites、连续画 continuous 原样带回，不碰）：
 * - magnet：磁吸开关（st.magnet），两边同一个意思
 * - styles/<kind>：手机按「每把工具」记样式，网页按「同族」记（st.drawStyles，族 = TOOL_GROUPS 的组）。
 *   推：网页一族的样式写进这一族里每个契约 kind；网页没有的 filled / levels 沿用云端那份，云端没有就取出厂
 *   （填色开、各工具自己的刻度）；线宽 1…8 夹进服务端的 0.5…6（同画线编码）。
 *   装：一族里云端变了的几个 kind，取最后写的那个（字段时间戳最新）装成这一族的样式
 * - variants/<面板头>：手机「这一族上次选的画法」（trend → extended、hline → hray、vline → crossLine）。
 *   网页「线」那一组工具栏上记的那把（st.toolLast.lines）就是它：推成它所在那一族的 variants，装回来换掉 toolLast.lines
 *
 * 记账照设置的规矩：账本 seen 里按「dp:<路径>」记上一次对上时网页这一侧的样子（投影），
 * 网页值 ≠ seen 才推；云端值 ≠ seen 才装，装完 seen 记成装完后的投影（手机只改了一个 kind，网页整族跟着换，不回推别的 kind）。
 * 「dp:ready」：这台电脑已经和云端那份对上过；对上之前不推（升级前的老账本没拉过这张表，见 bridge.drawPrefsPending）。
 */
import type { State } from '../app/store'
import type { DrawingType } from '../chart/chart'
import { CONTRACT_KIND, TOOL_GROUPS, WEB_TYPE, levelsOk } from '../chart/drawTools'
import { DrawKind, type DrawingKind } from '../m/chart/draw/drawing'
import type { SyncStore } from './store'
import { type Body, type Json, type SyncObject, same } from './types'

export const DP_COLLECTION = 'drawingPreferences'
export const DP_ID = 'tools'

const rootOf = (path: string): string => { const i = path.indexOf('/'); return i < 0 ? path : path.slice(0, i) }
/** 按路径第一段认领（`styles/<kind>` 这种拍平路径） */
class RootSet extends Set<string> {
  constructor(private readonly roots: readonly string[]) { super() }
  override has(k: string): boolean { return this.roots.includes(rootOf(k)) }
}
/** 网页替它说话的路径：磁吸、样式、画法；收藏与连续画不归网页 */
export const DP_OWNED: Set<string> = new RootSet(['magnet', 'styles', 'variants'])

export type DpState = Partial<Pick<State, 'magnet' | 'drawStyles' | 'toolLast'>>
type FamilyStyle = State['drawStyles'][string]

const SEEN = 'dp:'
export const DP_READY = SEEN + 'ready'
/** 升级前的老账本：记下「从这一刻起等一次全量」的时刻（bridge.drawPrefsPending） */
export const DP_SINCE = SEEN + 'since'

const HEX = /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/
const isObj = (v: unknown): v is Record<string, Json> => !!v && typeof v === 'object' && !Array.isArray(v)
const num = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v)
/** 网页的线宽（1…8）→ 服务端收的 0.5…6；网页这一族没设线宽时取网页新画线的默认 2 */
const lineWidthOf = (w: number | undefined): number => Math.min(6, Math.max(0.5, w ?? 2))

/** 网页一族 → 这一族里的契约 kind */
const FAMILY_KINDS: Record<string, DrawingKind[]> = Object.fromEntries(TOOL_GROUPS.map(g =>
  [g.id, g.tools.map(([t]) => CONTRACT_KIND[t]).filter((k): k is DrawingKind => !!k)]))
/** 契约 kind → 网页一族 */
const KIND_FAMILY: Record<string, string> = Object.fromEntries(Object.entries(FAMILY_KINDS).flatMap(([f, ks]) => ks.map(k => [k, f])))

/** 「线」那一组工具栏上那把 → 手机的 variants 一项（只有同族换画法的那三族有） */
function variantOf(tool: string | undefined): [string, DrawingKind] | null {
  const k = tool ? CONTRACT_KIND[tool as DrawingType] : undefined
  const head = k ? DrawKind.paletteHead(k) : null
  return k && head ? ['variants/' + head, k] : null
}

/** 网页这一侧投影成云端的那几个路径。prev：云端（账本）那份 body，网页说不清的 filled / levels / 颜色沿用它 */
export function projectDrawPrefs(s: DpState, prev: Body): Body {
  const out: Body = {}
  if (typeof s.magnet === 'boolean') out.magnet = s.magnet
  for (const [fam, st] of Object.entries(s.drawStyles ?? {})) {
    if (!st || (!st.color && !st.width && !st.dash)) continue
    for (const k of FAMILY_KINDS[fam] ?? []) {
      const p = isObj(prev['styles/' + k]) ? prev['styles/' + k] as Record<string, Json> : {}
      const o: Body = {}
      // 网页这一族没设颜色：手机那把自己的颜色留着
      if (st.color && HEX.test(st.color)) o.color = { value: st.color }
      else if (isObj(p.color)) o.color = p.color
      o.lineWidth = st.width ? lineWidthOf(st.width) : num(p.lineWidth) && p.lineWidth >= 0.5 && p.lineWidth <= 6 ? p.lineWidth : lineWidthOf(undefined)
      o.dash = st.dash ?? 'solid'
      o.filled = typeof p.filled === 'boolean' ? p.filled : true
      o.levels = levelsOk(p.levels) ? [...p.levels] : DrawKind.defaultLevels(k)
      out['styles/' + k] = o
    }
  }
  const v = variantOf(s.toolLast?.lines)
  if (v) out[v[0]] = v[1]
  return out
}

/** 云端一把工具的样式 → 网页一族的样式（只认颜色、线宽、线型） */
function familyStyleOf(v: Record<string, Json>): FamilyStyle | null {
  if (!num(v.lineWidth)) return null
  const out: FamilyStyle = {}
  const c = isObj(v.color) ? v.color.value : null
  if (typeof c === 'string' && HEX.test(c)) out.color = c
  out.width = Math.min(8, Math.max(1, Math.round(v.lineWidth)))
  if (v.dash === 'dashed' || v.dash === 'dotted') out.dash = v.dash
  return out
}

/** 字段最后一次被写的时刻（服务端字段戳；本机刚写、还没确认的算最新） */
function fieldTime(o: SyncObject | undefined, path: string): number {
  const f = o?.fields?.[path]
  return isObj(f) && num(f.timestamp) ? f.timestamp : Number.MAX_SAFE_INTEGER
}

/** 记账：网页这一侧变了的路径编码进 body（其余原样沿用云端那份）。没对上过、没变 → null */
export function encodeDrawPrefs(s: DpState, store: SyncStore): SyncObject | null {
  const seen = store.a.seen
  if (!(DP_READY in seen)) return null
  const o = store.get(DP_COLLECTION, DP_ID)
  const prev = o && !o.deleted ? o.body : {}
  const body: Body = { ...prev }
  let touched = false
  for (const [k, v] of Object.entries(projectDrawPrefs(s, prev))) {
    if (same(v, seen[SEEN + k])) continue
    seen[SEEN + k] = v
    if (same(v, prev[k])) continue
    body[k] = v; touched = true
  }
  return touched ? { collection: DP_COLLECTION, id: DP_ID, body, fields: {}, revision: 0, deleted: false, generation: 0 } : null
}

/**
 * 装：云端变了的（≠ seen）装进页面状态（原地改），返回改没改。
 * 第一次对上（seen 里还没有 ready）：seen 是空的，云端有的一律装（手机设过的磁吸、样式、画法），
 * 云端没有的（网页独有的几族样式、云端从没写过的磁吸）seen 不记，下一次记账推上去。
 */
export function applyDrawPrefs(s: DpState, store: SyncStore): boolean {
  const seen = store.a.seen
  const o = store.get(DP_COLLECTION, DP_ID)
  const body = o && !o.deleted ? o.body : {}
  let changed = false
  if (typeof body.magnet === 'boolean' && !same(body.magnet, seen[SEEN + 'magnet']) && s.magnet !== body.magnet) { s.magnet = body.magnet; changed = true }
  // 样式：一族里变了的几个 kind 取最后写的那个
  const pick: Record<string, { style: FamilyStyle; t: number }> = {}
  let variant: { tool: string; t: number } | null = null
  for (const [path, v] of Object.entries(body)) {
    if (same(v, seen[SEEN + path])) continue
    const root = rootOf(path), k = path.slice(root.length + 1), t = fieldTime(o, path)
    if (root === 'styles' && isObj(v)) {
      const fam = KIND_FAMILY[k], st = familyStyleOf(v)
      if (fam && st && (!pick[fam] || t > pick[fam].t)) pick[fam] = { style: st, t }
    } else if (root === 'variants' && typeof v === 'string') {
      // 只认网页「线」那一组里有的、确实属于这一族的画法
      const tool = WEB_TYPE[v]
      if (tool && KIND_FAMILY[v] === 'lines' && DrawKind.paletteHead(v as DrawingKind) === k && (!variant || t > variant.t)) variant = { tool, t }
    }
  }
  for (const [fam, { style }] of Object.entries(pick)) {
    if (same(style, s.drawStyles?.[fam])) continue
    s.drawStyles = { ...(s.drawStyles ?? {}), [fam]: style }
    changed = true
  }
  if (variant && s.toolLast?.lines !== variant.tool) { s.toolLast = { ...(s.toolLast ?? {}), lines: variant.tool }; changed = true }
  // seen 记装完后的投影（云端有的那些路径）：手机只改了一把，网页整族换了，别的 kind 不回推；
  // 网页投影不到的（网页没设样式的那几族、不是当前那把的另两族画法）记云端值，表示装过了、不再反复装
  const proj = projectDrawPrefs(s, body)
  for (const k of Object.keys(body)) if (DP_OWNED.has(k)) seen[SEEN + k] = k in proj ? proj[k] : body[k]
  seen[DP_READY] = true
  delete seen[DP_SINCE]
  return changed
}
