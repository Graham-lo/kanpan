/* Hkline 手机网页版 · 共享的画线本（全 app 一本）
 *
 * 画线的真值是 m/chart/draw/book.ts 的 DrawingBook（所有品种的线、撤销栈、每品种 50 条上限都在里面）。
 * 行情页用 `attachDrawing(view)` 拿到控制器后 `c.bindDrawings(drawingBook)` 绑上这一本；
 * 这里负责：
 * - 启动时从本机存档读（localStorage `hkline-m-drawings-v1`，encodeArchive / decodeArchive 的形状）；
 *   读不全（解不开、有线这一版解不了、新版本写的）时原文另存到 `hkline-m-drawings-v1.unreadable-<时间>`，
 *   免得第一次落盘把没登录的人仅有的那份线盖掉；
 * - book 一有变动（画、改、删、撤销、同步替换）立刻落盘；
 * - 叫一声订阅者（m/app/sync.ts 据此记账推云端，并记下这只品种「本机最后一次改」）。
 *
 * 工具偏好（收藏的工具、磁吸、连续画、各工具的样式与变体）改了 book 不发通知：
 * 改完 `drawingBook.preferences` 之后调一次 `saveDrawingPreferences()`。
 *
 * 云端来的线由 sync.ts 用 `drawingBook.replace(next)` 整本换进来（只有真变了的桶清撤销栈、发 replaced），
 * 换账号时 `replace(next, true)` 连撤销栈一起清。
 */
import { DrawingBook, type DrawingBookChange } from '../chart/draw/book'
import { DrawArchive, decodeArchive, encodeArchive } from '../chart/draw/archive'
import { tabGuard } from './tabGuard'
import { backupUnreadable } from './unreadable'

export const DRAWINGS_KEY = 'hkline-m-drawings-v1'

/** 本机存档读坏过（有东西但解不开）：同步那边先别按「本机删光了」推删除 */
let suspect = false

/** 存档原文里有、解出来却没有的线（这一版解不开、会被丢掉的）有几条 */
function lostCount(json: unknown, a: DrawArchive): number {
  const d = (json as { d?: unknown } | null)?.d
  if (!d || typeof d !== 'object') return 0
  const kept = new Set(Object.values(a.bySymbol).flatMap(b => b.map(x => x.id)))
  return Object.values(d).flatMap(b => Array.isArray(b) ? b : []).filter(x => {
    const id = (x as { id?: unknown } | null)?.id
    return typeof id !== 'string' || !kept.has(id)
  }).length
}

function load(): DrawArchive {
  let raw: string | null = null
  try { raw = localStorage.getItem(DRAWINGS_KEY) } catch { /* 读不到当空 */ }
  if (!raw) return new DrawArchive()
  let a: DrawArchive
  let json: unknown
  try { json = JSON.parse(raw); a = decodeArchive(json) } catch { suspect = true; backupUnreadable(DRAWINGS_KEY, raw); return new DrawArchive() }
  // 新版本写的、或有线解不开（会被这一版丢掉）：照样用解得开的那些，但原文另存，并按可疑处理（同步只补不删）
  if (a.version > DrawArchive.currentVersion || lostCount(json, a)) { suspect = true; backupUnreadable(DRAWINGS_KEY, raw) }
  return a
}

/** 全 app 共享的那一本 */
export const drawingBook = new DrawingBook(load())

/** 变动的种类：'edited' 本机编辑了这只品种；'replaced' 同步整批换进来；'preferences' 工具偏好改了 */
export type DrawingsChange = DrawingBookChange | { kind: 'preferences' }
const listeners = new Set<(c: DrawingsChange) => void>()
let rev = 0

/** 旧了：把别的标签页写的那一本换进内存（发 replaced，同步据此记账推上去），不写盘；解不开就不换 */
function adopt(): void {
  let next: DrawArchive
  try {
    const raw = localStorage.getItem(DRAWINGS_KEY)
    if (!raw) return
    next = decodeArchive(JSON.parse(raw))
  } catch { return }
  replaceDrawings(next)
}
tabGuard.register(DRAWINGS_KEY, () => JSON.stringify(encodeArchive(drawingBook.archive)), adopt)
/** 落盘；被别的标签页比下去了（tabGuard）就不写，切回来会重载 */
function persist(): void { tabGuard.write(DRAWINGS_KEY) }

function emit(c: DrawingsChange): void {
  rev++
  for (const fn of [...listeners]) { try { fn(c) } catch (e) { console.error(e) } }
}

const owner = {}
drawingBook.observe(owner, c => { persist(); emit(c) })

/** 改完 drawingBook.preferences 之后调：落盘并记账 */
export function saveDrawingPreferences(): void { persist(); emit({ kind: 'preferences' }) }

/** 同步整本换进来（sync.ts 用）：真变了的桶清撤销栈、发 replaced；工具偏好换了也落盘并叫一声。
 *  resetAll：换账号，撤销栈全清 */
export function replaceDrawings(next: DrawArchive, resetAll = false): void {
  const prefsChanged = !drawingBook.preferences.equals(next.preferences)
  drawingBook.replace(next, resetAll)
  if (prefsChanged) { persist(); emit({ kind: 'preferences' }) }
}

/** 订阅变动；返回退订 */
export function onDrawingsChanged(fn: (c: DrawingsChange) => void): () => void {
  listeners.add(fn)
  return () => { listeners.delete(fn) }
}

/** 每变一次加一（指纹用） */
export const drawingsRev = (): number => rev
export const drawingsSuspect = (): boolean => suspect
/** 云端那份已并回来、落过盘：不再可疑 */
export function clearDrawingsSuspect(): void { if (suspect) { suspect = false; persist() } }
