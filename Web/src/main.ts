/* Hkline Web · 入口 */
import './styles/app.css'
import './styles/workbench.css'
import { st, save, LAYOUTS, type Layout, type PanelId } from './app/store'
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
  if (s && /^[A-Z0-9]+$/.test(s)) st.cells[st.active] = { ...st.cells[st.active], symbol: s }
  if (i && INTERVALS.includes(i)) st.cells[st.active] = { ...st.cells[st.active], iv: i }
  if (th === 'light' || th === 'dark') st.theme = th
  if (sk === 'sage' || sk === 'terra' || sk === 'classic') st.skin = sk
  if (lo && (LAYOUTS as readonly string[]).includes(lo)) st.layout = lo as Layout
  if (pn === 'none') st.panel = null
  else if (pn && ['watch', 'alerts', 'flow', 'notes', 'trades'].includes(pn)) st.panel = pn as PanelId
  if (q.has('ladder')) st.slots.ladder = q.get('ladder') === '1'
  if (q.has('drawer')) st.slots.drawer = q.get('drawer') === '1'
  save()
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
