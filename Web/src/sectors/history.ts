/* Hkline Web · 板块 5 日收盘（照手机端 SectorHistoryFeed）
 *
 * 同源 GET /v1/market/sector-history → {"data":{"asof":"YYYY-MM-DD","symbols":{"BTCUSDT":{"c5":…,"c20":…}}}}
 * c5 是 asof − 5 那天的日线收盘（UTC 零点切日），「5 日」= 现价 / c5 − 1。
 *
 * - 进板块页取一次，之后每小时一次；失败按 5、15、45 秒…封顶 10 分钟重试。
 * - 网络与本机缓存共用同一道闸：不新鲜的（超过 7 天）、比手上旧的、同一天却更少的，一律不认。
 * - 服务端出错 / 没数据：什么都不提示，页面只是没有「5 日」那一档。
 * - 原样响应体存本机（约 30 KB），下次进来先用它顶上。
 */
import { EMPTY_HISTORY, accepts, decodeHistory, historyRetryDelay } from './aggregate'
import type { SectorHistory } from './aggregate'
import { SECTOR_HISTORY_KEY } from '../util/storage'

const KEY = SECTOR_HISTORY_KEY
const URL = `${import.meta.env.BASE_URL.replace(/\/web\/$/, '/')}v1/market/sector-history`
const HOUR_MS = 3_600_000

export const history = { held: EMPTY_HISTORY as SectorHistory }

let loadedDisk = false
function loadDisk(): boolean {
  if (loadedDisk) return false
  loadedDisk = true
  try {
    const raw = localStorage.getItem(KEY); if (!raw) return false
    const h = decodeHistory(JSON.parse(raw))
    if (h && accepts(history.held, h)) { history.held = h; return true }
  } catch { /* 坏缓存当没有 */ }
  return false
}

let lastOk = 0
let failures = 0
let timer: ReturnType<typeof setTimeout> | undefined
let running = false
let inflight = false

async function pull(): Promise<boolean> {
  const ctl = new AbortController()
  const t = setTimeout(() => ctl.abort(), 10_000)
  try {
    // 服务端给了 max-age=3600，这里让浏览器缓存照常生效
    const r = await fetch(URL, { signal: ctl.signal })
    if (!r.ok) throw new Error(String(r.status))
    const text = await r.text()
    const h = decodeHistory(JSON.parse(text))
    if (!h) throw new Error('shape')
    lastOk = Date.now()
    failures = 0
    if (!accepts(history.held, h)) return false
    history.held = h
    try { localStorage.setItem(KEY, text) } catch { /* 存不下就不存 */ }
    return true
  } catch {
    failures++
    return false
  } finally { clearTimeout(t) }
}

/** 页面开着时维持 5 日收盘；拿到新的一份才回调 */
export function startHistory(onChange: () => void): void {
  if (running) return
  running = true
  if (loadDisk()) onChange()
  const schedule = (ms: number): void => { clearTimeout(timer); timer = setTimeout(tick, ms) }
  const tick = (): void => {
    if (!running || inflight) return
    const due = failures > 0 || !lastOk || Date.now() - lastOk >= HOUR_MS
    if (!due) { schedule(lastOk + HOUR_MS - Date.now()); return }
    inflight = true
    void pull().then(changed => {
      inflight = false
      if (!running) return
      if (changed) onChange()
      schedule(failures ? historyRetryDelay(failures) * 1000 : HOUR_MS)
    })
  }
  tick()
}
export function stopHistory(): void { running = false; clearTimeout(timer) }
