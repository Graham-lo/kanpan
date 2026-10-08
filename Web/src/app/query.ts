/* Hkline Web · 地址栏参数（截图、分享链接用）：?s=ETHUSDT&i=4h&theme=dark&skin=terra&layout=4&panel=alerts
 *
 * 不认的值一律不动、照样从地址栏拿掉；品种代号大小写都认（手打的 btcusdt 和分享出去的 BTCUSDT 一样），
 * 中文底名的合约（币安人生USDT、龙虾USDT）也认——「复制这张图的链接」给的就是它们原样的代号。
 * 品种是否真的存在要等品种表到了才知道：不存在的由图表页启动时换成兜底品种（pages/chart.ts 启动收尾）。 */
import { clampActive, ensureCells, LAYOUTS, LAYOUT_N, type Layout, type PanelId, type State } from './store'
import { INTERVALS } from '../market/symbols'
import { displayKey } from '../market/identity'
import { validSymbol } from './layouts'

export const QUERY_KEYS = ['s', 'i', 'theme', 'skin', 'layout', 'panel', 'ladder', 'drawer'] as const
const PANELS: readonly string[] = ['watch', 'alerts', 'flow', 'notes', 'trades']

/** 把地址栏参数落进 st；返回用过（要从地址栏拿掉）的键 */
export function applyQueryTo(s: State, search: string): string[] {
  const q = new URLSearchParams(search)
  const raw = q.get('s')?.trim() ?? ''
  // 别家的品种是完整键（okx/usd_m/BTCUSDT），venue / market 段小写、代号段原样；币安裸代号照旧转大写
  const parts = raw.split('/')
  const sym = parts.length === 3 ? displayKey(`${parts[0].toLowerCase()}/${parts[1].toLowerCase()}/${parts[2].toUpperCase()}`) : raw.toUpperCase(), i = q.get('i'), th = q.get('theme'), sk = q.get('skin'), lo = q.get('layout'), pn = q.get('panel')
  // 先定布局再落品种 / 周期：存着的当前格可能在新布局之外（八图第 3 格 → 一图），不收回来就落到看不见的格子上
  if (lo && (LAYOUTS as readonly string[]).includes(lo)) { s.layout = lo as Layout; clampActive(s) }
  // 格子配置补齐到布局的格数：存着的是一图、地址栏要十六图时 st.cells 只有一项，直接写第 n 格会留下没有周期的半截配置
  ensureCells(s, LAYOUT_N[s.layout])
  if (sym && (/^[\p{L}\p{N}]{2,40}$/u.test(sym) || validSymbol(sym))) s.cells[s.active] = { ...s.cells[s.active], symbol: sym }
  if (i && INTERVALS.includes(i)) s.cells[s.active] = { ...s.cells[s.active], iv: i }
  if (th === 'light' || th === 'dark') s.theme = th
  if (sk === 'sage' || sk === 'terra' || sk === 'classic') s.skin = sk
  if (pn === 'none') s.panel = null
  else if (pn && PANELS.includes(pn)) s.panel = pn as PanelId
  if (q.has('ladder')) s.slots.ladder = q.get('ladder') === '1'
  if (q.has('drawer')) s.slots.drawer = q.get('drawer') === '1'
  return QUERY_KEYS.filter(k => q.has(k))
}

/** 拿掉用过的键之后的地址（其余参数与 # 原样留着） */
export function strippedUrl(pathname: string, search: string, hash: string, used: readonly string[]): string {
  const q = new URLSearchParams(search)
  used.forEach(k => q.delete(k))
  const rest = q.toString()
  return pathname + (rest ? '?' + rest : '') + hash
}
