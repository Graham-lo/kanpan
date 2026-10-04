/* Hkline Web · 入口 */
import './styles/app.css'
import './styles/workbench.css'
import { st, save, onStorageFull } from './app/store'
import { applyQueryTo, strippedUrl } from './app/query'
import { installShell, applyTheme, renderHeader, go } from './app/shell'
import { hydrateIcons } from './ui/dom'
import { installTooltips, toast } from './ui/overlay'
import { setRoute } from './market'
import { initChart } from './pages/chart'
import { initSectors } from './pages/sectors'
import { initReview } from './pages/review'
import { initMe } from './pages/me'
import { resume } from './account/client'
import { initSync } from './sync/glue'

// 地址栏参数（截图、分享链接用）见 app/query.ts
function applyQuery(): void {
  const used = applyQueryTo(st, location.search)
  save()
  // 用过就从地址栏拿掉：不然打开分享链接后自己换了品种，一刷新又被链接里的品种盖回去
  if (used.length) history.replaceState(history.state, '', strippedUrl(location.pathname, location.search, location.hash, used))
}

applyQuery()
applyTheme()
hydrateIcons()
resume()
renderHeader()
installShell()
installTooltips()
// 本机存储满到清掉缓存也写不下：改动只在这一页内存里，关掉就没了，得让人知道（一页只提示一次）
let fullWarned = false
onStorageFull(() => { if (!fullWarned) { fullWarned = true; toast('本机存储已满', '这次的改动没能存进这台电脑', 'info', 8000) } })
setRoute(st.route)
initSectors()
initReview()
initMe()
initSync()
go(location.hash.slice(1) || 'chart')
void initChart()
