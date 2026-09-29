/* Hkline Web · 入口 */
import './styles/app.css'
import './styles/workbench.css'
import { st, save, clampActive, ensureCells, LAYOUTS, LAYOUT_N, type Layout, type PanelId } from './app/store'
import { installShell, applyTheme, renderHeader, go } from './app/shell'
import { hydrateIcons } from './ui/dom'
import { installTooltips } from './ui/overlay'
import { setRoute, INTERVALS } from './market'
import { initChart } from './pages/chart'
import { initSectors } from './pages/sectors'
import { initReview } from './pages/review'
import { initMe } from './pages/me'
import { resume } from './account/client'
import { initSync } from './sync/glue'

// 地址栏参数（截图、分享链接用）：?s=ETHUSDT&i=4h&theme=dark&skin=terra&layout=4&panel=alerts
function applyQuery(): void {
  const q = new URLSearchParams(location.search)
  const s = q.get('s'), i = q.get('i'), th = q.get('theme'), sk = q.get('skin'), lo = q.get('layout'), pn = q.get('panel')
  // 先定布局再落品种 / 周期：存着的当前格可能在新布局之外（八图第 3 格 → 一图），不收回来就落到看不见的格子上
  if (lo && (LAYOUTS as readonly string[]).includes(lo)) { st.layout = lo as Layout; clampActive(st) }
  // 格子配置补齐到布局的格数：存着的是一图、地址栏要十六图时 st.cells 只有一项，直接写第 n 格会留下没有周期的半截配置
  ensureCells(st, LAYOUT_N[st.layout])
  if (s && /^[A-Z0-9]+$/.test(s)) st.cells[st.active] = { ...st.cells[st.active], symbol: s }
  if (i && INTERVALS.includes(i)) st.cells[st.active] = { ...st.cells[st.active], iv: i }
  if (th === 'light' || th === 'dark') st.theme = th
  if (sk === 'sage' || sk === 'terra' || sk === 'classic') st.skin = sk
  if (pn === 'none') st.panel = null
  else if (pn && ['watch', 'alerts', 'flow', 'notes', 'trades'].includes(pn)) st.panel = pn as PanelId
  if (q.has('ladder')) st.slots.ladder = q.get('ladder') === '1'
  if (q.has('drawer')) st.slots.drawer = q.get('drawer') === '1'
  save()
  // 用过就从地址栏拿掉：不然打开分享链接后自己换了品种，一刷新又被链接里的品种盖回去
  const used = ['s', 'i', 'theme', 'skin', 'layout', 'panel', 'ladder', 'drawer'].filter(k => q.has(k))
  if (used.length) {
    used.forEach(k => q.delete(k))
    const rest = q.toString()
    history.replaceState(history.state, '', location.pathname + (rest ? '?' + rest : '') + location.hash)
  }
}

applyQuery()
applyTheme()
hydrateIcons()
resume()
renderHeader()
installShell()
installTooltips()
setRoute(st.route)
initSectors()
initReview()
initMe()
initSync()
go(location.hash.slice(1) || 'chart')
void initChart()
