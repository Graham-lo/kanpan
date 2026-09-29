/* Hkline 手机网页版 · 入口（/web/m/）
 *
 * 顺序：账号键名（boot）→ 样式 → 壳（四页 + 底栏 + 主题 + 路由）→ 恢复会话 → 行情线路 → 同步
 * → 懒加载各页 → 常驻盯价（没进过「我的」的人提醒也照样响）。
 * 页面模块在 ./pages/<id>.ts，导出 init<Id>(root) → { show, hide, reselect? }（合同见 app/README.md）；
 * 模块还不存在时挂一行「即将到来」，不挡别的页。
 */
import './boot'
import './styles/tokens.css'
import './styles/base.css'
import './styles/shell.css'
import './styles/ui.css'
import { st, PAGES, type PageId } from './app/store'
import { installShell, registerPage, pageRoot, hooks, type PageHandle } from './app/shell'
import { startUniverseRefresh } from './app/universeRefresh'
import { glyph, type GlyphName } from './ui/icons'
import { resume } from '../account/client'
import { setRoute } from '../market'
import { initMobileSync } from './app/sync'
import { startLinkGrace } from './app/linkGrace'

type PageModule = Record<string, unknown>
const modules = import.meta.glob<PageModule>('./pages/*.ts')

const TITLE: Record<PageId, string> = { chart: '图表', favorites: '自选', sectors: '板块分类', me: '我的' }
const GLYPH: Record<PageId, GlyphName> = { chart: 'chart', favorites: 'favorites', sectors: 'sectors', me: 'me' }

function placeholder(id: PageId): PageHandle {
  const root = pageRoot(id)
  root.innerHTML = `<div class="page-soon">${glyph(GLYPH[id], 36)}<span>${TITLE[id]} · 即将到来</span></div>`
  return { show() {}, hide() {} }
}

async function mount(id: PageId): Promise<void> {
  const load = modules[`./pages/${id}.ts`]
  if (!load) { registerPage(id, placeholder(id)); return }
  try {
    const mod = await load()
    const name = 'init' + id[0].toUpperCase() + id.slice(1)
    const init = (mod[name] ?? mod.default) as ((root: HTMLElement) => PageHandle) | undefined
    if (typeof init !== 'function') { registerPage(id, placeholder(id)); return }
    registerPage(id, init(pageRoot(id)))
  } catch (e) {
    console.error(`[m] 页面 ${id} 加载失败`, e)
    registerPage(id, placeholder(id))
  }
}

installShell(document.getElementById('m-mount') ?? document.body)
resume()
setRoute(st.routePolicy)
startLinkGrace()
initMobileSync()
// 品种表：回前台超过 30 分钟、在前台每 6 小时重拉（新上线的搜得到、下架的翻成下架）
startUniverseRefresh({ onForeground: fn => hooks.onForeground.push(fn) })

// 先挂当前页，其余页空闲时再挂（切过去时已经就绪）
const first = st.page
void mount(first).then(() => {
  const rest = PAGES.filter(p => p !== first)
  const idle = (cb: () => void): void => { if ('requestIdleCallback' in window) requestIdleCallback(cb, { timeout: 1200 }); else setTimeout(cb, 300) }
  idle(() => rest.forEach(p => void mount(p)))
  // 提醒的常驻监听挂在壳上：不依赖进没进过「我的」/ 提醒页
  void import('./pages/alerts').then(m => m.startAlertWatcher()).catch(e => console.error('[m] 提醒监听启动失败', e))
})

// PWA：只缓存壳，行情永远走网络（见 public/m/sw.js）；开发时不注册，免得缓存住热更新
if ('serviceWorker' in navigator && import.meta.env.PROD) {
  // 版本号 = 本次构建的入口脚本名（带哈希），构建一次变一次，SW 据此换缓存
  const v = new URL(import.meta.url).pathname.split('/').pop() || 'dev'
  addEventListener('load', () => {
    navigator.serviceWorker.register(`${import.meta.env.BASE_URL}m/sw.js?v=${encodeURIComponent(v)}`, { scope: import.meta.env.BASE_URL + 'm/' })
      .catch(e => console.warn('[m] Service Worker 注册失败', e))
    // SW 就绪后把这一次实际加载过的构建产物报过去补存（第一次打开时它们是 SW 装好之前取的），下次断网打开也有完整的壳；
    // 各页是空闲时懒加载的，稍等一会儿再报
    void navigator.serviceWorker.ready.then(reg => setTimeout(() => {
      const urls = performance.getEntriesByType('resource').map(e => e.name).filter(u => u.includes('/assets/'))
      reg.active?.postMessage({ type: 'keep', urls })
    }, 4000))
  })
}
