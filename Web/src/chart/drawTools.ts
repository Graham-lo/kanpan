/* Hkline Web · 画线工具：几何、命中、画法（chart.ts 只做接入）
 *
 * 三把「算出来的」工具（形状由锚点圈住的 K 线算，不由锚点本身定）：
 *   · 锚定 VWAP（avwap，一点）：从锚点那根起累计 典型价 × 成交量，只画一条线（与 iOS、手机网页版一致，不画 σ 带）；
 *     算法与主图 VWAP 一致（indicators.vwap：典型价 (高+低+收)/3，按成交量（币）加权）。
 *   · 固定区间成交量分布（fvp，两点）：两点圈一段时间，复用 overlays.vpvr 与主图 VPVR 的三种看法，画法照 TradingView
 *     （volumeProfile.ts，与主图共用）；行数按这段价格区间的像素高自动定（每行 ≥ 4 px），控制点与七成价值区上下沿都是实线。
 *   · 多空持仓（position，三点：入场、目标、止损）：目标在入场上方就是多、下方就是空（照手机 DrawGeometry）；
 *     只标止盈 / 止损相对入场的百分比与盈亏比 R，不算仓位。
 * 复盘回放时 lastIndex() 是放到的那根，这里一律只算到它为止——不会拿「未来」的 K 线画。
 *
 * 另有画线交互的几样小工具：45° 吸附、每只品种的数量 / 体积上限、工具分组与同族样式。
 */
import { fmt, hexA } from '../util/format'
import type { Bar } from './calc'
import { vpvr, type Vpvr } from './overlays'
import { drawProfile, profileRows } from './volumeProfile'
import { vwapWeight } from './indicators'
import type { DrawPoint, Drawing, DrawingType, Pane, PriceRange, TVChart } from './chart'

export interface XY { x: number; y: number }
type Ctx = CanvasRenderingContext2D

/** 这三把是算出来的，画法与命中在这里 */
export const COMPUTED: ReadonlySet<DrawingType> = new Set<DrawingType>(['avwap', 'fvp', 'position'])

/** 每种画线的锚点数（全部种类的白名单就是它的键；读档清洗按它认：不认识的种类、锚点数不对的丢掉） */
export const ANCHOR_COUNT: Readonly<Record<DrawingType, number>> = { trend: 2, ray: 2, hline: 1, vline: 1, rect: 2, fib: 2, measure: 2, avwap: 1, fvp: 2, position: 3 }
export const DRAWING_TYPES: ReadonlySet<DrawingType> = new Set(Object.keys(ANCHOR_COUNT) as DrawingType[])
export const isDrawingType = (t: unknown): t is DrawingType => typeof t === 'string' && DRAWING_TYPES.has(t as DrawingType)

// ------------------------------------------------------------ 样式取值（存档会被老版本、手改写坏：颜色只认 #RGB / #RRGGBB / #RRGGBBAA，
// 粗细只认 0.5–6 的有限数（和服务端 sync_validation 的 lineWidth 同一口径；手机有 1.5 档），线型只认虚线 / 点线，不合规的换默认）
export const DEFAULT_DRAW_COLOR = '#2962FF'
export const DEFAULT_DRAW_WIDTH = 2
const DRAW_COLOR = /^#(?:[0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i
export const drawColorOk = (c: unknown): c is string => typeof c === 'string' && DRAW_COLOR.test(c)
/** 合规颜色（三位简写展开成六位，同步层只认六 / 八位）；不合规给默认色 */
export function cleanDrawColor(c: unknown): string {
  if (!drawColorOk(c)) return DEFAULT_DRAW_COLOR
  return c.length === 4 ? '#' + c.slice(1).split('').map(x => x + x).join('') : c
}
export const drawWidthOk = (w: unknown): w is number => typeof w === 'number' && Number.isFinite(w) && w >= 0.5 && w <= 6
export const cleanDrawWidth = (w: unknown): number => drawWidthOk(w) ? w : DEFAULT_DRAW_WIDTH

/** 读档清洗一条画线：形状认不出（没 id、不认识的种类、锚点数不对、锚点不是有限数）返回 null；
 *  样式字段坏了就地换默认（颜色 / 粗细）或去掉（线型、锁定、提醒），能留的原样留着、几何不动 */
export function cleanDrawing(raw: unknown): Drawing | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null
  const x = raw as Record<string, unknown>
  if (typeof x.id !== 'string' || !x.id || !isDrawingType(x.type)) return null
  const pts = x.pts
  if (!Array.isArray(pts) || pts.length !== ANCHOR_COUNT[x.type]) return null
  const fin = (v: unknown): boolean => typeof v === 'number' && Number.isFinite(v)
  if (!pts.every(p => !!p && typeof p === 'object' && fin((p as DrawPoint).t) && fin((p as DrawPoint).p))) return null
  const d = { ...x } as unknown as Drawing
  if (x.color == null) delete d.color
  else { const c = cleanDrawColor(x.color); if (c !== x.color) d.color = c }
  if (x.width == null) delete d.width
  else if (!drawWidthOk(x.width)) d.width = DEFAULT_DRAW_WIDTH
  if ('dash' in x && x.dash !== 'dashed' && x.dash !== 'dotted') delete d.dash
  if ('locked' in x && typeof x.locked !== 'boolean') delete d.locked
  if ('alert' in x && typeof x.alert !== 'boolean') delete d.alert
  return d
}

/** 放一条线要点几下（两点的也可以按下拖到位松手） */
export function placeCount(t: DrawingType): 1 | 2 { return t === 'hline' || t === 'vline' || t === 'avwap' ? 1 : 2 }

/** 草稿第二点跟着鼠标走；持仓的第三点（止损）先按 1R 对称放，画完再拖手柄改 */
export function setDraftEnd(d: Drawing, tp: DrawPoint): void {
  if (d.type === 'position') { const a = d.pts[0]; d.pts = [a, tp, { t: tp.t, p: a.p - (tp.p - a.p) }]; return }
  d.pts[d.pts.length - 1] = tp
}

/** 线型：实线 / 虚线 / 点线（和手机 Drawing.dash 同名） */
export type Dash = 'solid' | 'dashed' | 'dotted'
export function dashPattern(d: Pick<Drawing, 'dash' | 'width'>): number[] {
  const w = d.width || 2
  return d.dash === 'dashed' ? [w * 3, w * 2.5] : d.dash === 'dotted' ? [w * 0.5, w * 2] : []
}

// ------------------------------------------------------------ 45° 吸附
/** 按住 ⇧ 拖端点：从 a 到 b 的方向吸到 0° / 45° / 90°（像素空间）。
 *  横坐标先落到整根 K 线上（锚点的时间永远是某根的开盘），斜线再按这个 x 反推 y，保证正好 45° */
export function snap45(a: XY, b: XY, snapX: (x: number) => number): XY {
  const dx = b.x - a.x, dy = b.y - a.y
  if (!dx && !dy) return b
  const k = Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) & 7 // 0..7：→ ↘ ↓ ↙ ← ↖ ↑ ↗
  if (k === 2 || k === 6) return { x: a.x, y: b.y }
  const x = snapX(b.x)
  if (k === 0 || k === 4) return { x, y: a.y }
  const sy = k === 1 || k === 3 ? 1 : -1
  return { x, y: a.y + sy * Math.abs(x - a.x) }
}

// ------------------------------------------------------------ 上限
/** 每只品种最多 500 条、合计 2 MB（超了拒绝新增并提示；线上存档与同步的队列都不该被一只品种撑爆） */
export const QUOTA = { count: 500, bytes: 2 * 1024 * 1024 } as const
export function drawingBytes(list: readonly Drawing[]): number {
  let n = 2
  for (const d of list) if (d.type !== 'measure') n += JSON.stringify(d).length + 1
  return n
}
/** 再加 add 条还在上限以内吗 */
export function quotaOK(list: readonly Drawing[], add: readonly Drawing[] = []): boolean {
  const kept = list.filter(d => d.type !== 'measure')
  const extra = add.filter(d => d.type !== 'measure')
  if (kept.length + extra.length > QUOTA.count) return false
  return drawingBytes(kept) + drawingBytes(extra) <= QUOTA.bytes
}

// ------------------------------------------------------------ 分组与同族
export type GroupId = 'lines' | 'shapes' | 'fib' | 'forecast' | 'volume'
export interface ToolGroup { id: GroupId; name: string; tools: [DrawingType, string, string][] }
/** 左侧工具栏的分组（照 TradingView：一组一个按钮，右下角小箭头展开同组的工具） */
export const TOOL_GROUPS: ToolGroup[] = [
  { id: 'lines', name: '线', tools: [['trend', '趋势线', 'Alt T'], ['ray', '射线', 'Alt J'], ['hline', '水平线', 'Alt H'], ['vline', '垂直线', 'Alt V']] },
  { id: 'shapes', name: '形状', tools: [['rect', '矩形', 'Alt ⇧ R']] },
  { id: 'fib', name: '斐波那契', tools: [['fib', '斐波那契回撤', 'Alt F']] },
  { id: 'forecast', name: '预测与测量', tools: [['position', '多空持仓', ''], ['measure', '测量（也可以按住 ⇧ 拖）', '']] },
  { id: 'volume', name: '成交量', tools: [['avwap', '锚定 VWAP', ''], ['fvp', '固定区间成交量分布', '']] },
]
export function groupOf(t: DrawingType): ToolGroup | undefined { return TOOL_GROUPS.find(g => g.tools.some(x => x[0] === t)) }
export function toolName(t: DrawingType): string { return groupOf(t)?.tools.find(x => x[0] === t)?.[1] ?? t }
/** 同族工具共用「上次改过的样式」（颜色、粗细、线型） */
export function familyOf(t: DrawingType): GroupId { return groupOf(t)?.id ?? 'lines' }

// ------------------------------------------------------------ 锚定 VWAP
export interface Avwap { mid: number[] }
/** 从 from 那根起累计到 to（含）；返回的数组下标 k 对应第 from + k 根 */
export function anchoredVwap(bars: readonly Bar[], from: number, to: number): Avwap {
  const out: Avwap = { mid: [] }
  let sw = 0, swp = 0
  for (let i = Math.max(0, from); i <= Math.min(to, bars.length - 1); i++) {
    const b = bars[i], tp = (b.h + b.l + b.c) / 3, w = vwapWeight(b)
    if (w > 0) { sw += w; swp += w * tp }
    out.mid.push(sw > 0 ? swp / sw : tp)
  }
  return out
}

/** 锚定 VWAP 从哪根起算：含锚点时刻的那一根。向下取整——换到更粗的周期，10:37 的锚落在 10:00 那根里，
 *  四舍五入会跳到 11:00、把锚点所在那根整根漏掉。锚点早于已加载的第一根：这一段的累计缺了开头，
 *  返回 null 不画（往左翻到那里再画），不拿第一根冒充锚点画一条数值不对的线 */
export function avwapStart(ch: TVChart, d: Drawing): number | null {
  if (!d.pts.length || !ch.bars.length) return null
  const f = ch.indexAt(d.pts[0].t)
  return f < -1e-9 ? null : Math.floor(f + 1e-9)
}

/** 按画线缓存锚定 VWAP：悬停时每条线都要做一次命中、每帧又要画一次，每次都从锚点重新累计的话，
 *  图上堆满锚定 VWAP 时主线程一半时间耗在这里（2026-09-29 A 路压测：499 条锚定 VWAP 悬停扫图，主线程占用 52%）。
 *  键带上根数、首根时间与末根收盘 / 成交量，末根实时跳动或翻页补历史都会重算，和固定区间成交量分布一个做法。 */
const vwapCache = new WeakMap<Drawing, { key: string; b: Avwap }>()
export function vwapOf(ch: TVChart, d: Drawing, i0: number, end: number): Avwap {
  const lb = ch.bars[end]
  const key = `${i0}:${end}:${ch.bars.length}:${ch.bars[0]?.t}:${lb?.c}:${lb?.v}`
  let hit = vwapCache.get(d)
  if (!hit || hit.key !== key) { hit = { key, b: anchoredVwap(ch.bars, i0, end) }; vwapCache.set(d, hit) }
  return hit.b
}

// ------------------------------------------------------------ 固定区间成交量分布
/** 行数：这段价格区间在屏上的像素高 ÷ 4（每行至少 4 px），1–240 行 */
export function fvpRows(pxH: number): number { return profileRows(pxH) }
export interface FvpShape { v: Vpvr; i0: number; i1: number; x0: number; x1: number }
const fvpCache = new WeakMap<Drawing, { key: string; v: Vpvr | null }>()
export function fvpShape(ch: TVChart, d: Drawing, p: Pane, r: PriceRange): FvpShape | null {
  if (d.pts.length < 2) return null
  const last = ch.lastIndex()
  const a = Math.round(ch.indexAt(d.pts[0].t)), b = Math.round(ch.indexAt(d.pts[1].t))
  const i0 = Math.max(0, Math.min(a, b)), i1 = Math.min(last, Math.max(a, b))
  if (i1 < i0) return null
  let lo = Infinity, hi = -Infinity
  for (let i = i0; i <= i1; i++) { const k = ch.bars[i]; if (!k) continue; if (k.l < lo) lo = k.l; if (k.h > hi) hi = k.h }
  if (!isFinite(lo)) return null
  const rows = fvpRows(ch.priceToY(lo, p, r) - ch.priceToY(hi, p, r))
  const lb = ch.bars[i1]
  const key = `${i0}:${i1}:${rows}:${ch.bars.length}:${ch.bars[0]?.t}:${lb?.c}:${lb?.v}`
  let hit = fvpCache.get(d)
  if (!hit || hit.key !== key) { hit = { key, v: vpvr(ch.bars as Bar[], i0, i1, rows) }; fvpCache.set(d, hit) }
  if (!hit.v) return null
  const half = ch.spacing / 2
  return { v: hit.v, i0, i1, x0: ch.indexToX(i0) - half, x1: ch.indexToX(i1) + half }
}

// ------------------------------------------------------------ 多空持仓
export interface PositionStats { long: boolean; targetPct: number | null; stopPct: number | null; r: number | null }
export function positionStats(entry: number, target: number, stop: number): PositionStats {
  const pct = (to: number) => entry !== 0 && isFinite(entry) && isFinite(to) ? (to - entry) / Math.abs(entry) * 100 : null
  const gain = Math.abs(target - entry), risk = Math.abs(entry - stop)
  return { long: target >= entry, targetPct: pct(target), stopPct: pct(stop), r: risk > 0 ? gain / risk : null }
}
const pctLabel = (v: number | null) => v == null ? '—' : `${v >= 0 ? '+' : '−'}${Math.abs(v).toFixed(2)}%`
/** 画完时目标和入场落在同一根上：框给十根宽，不然是一条缝 */
export function widenPosition(ch: TVChart, d: Drawing): void {
  if (d.type !== 'position' || d.pts.length < 3) return
  const ia = ch.indexAt(d.pts[0].t), ib = ch.indexAt(d.pts[1].t)
  if (Math.abs(ib - ia) >= 2) return
  const t = ch.timeAt(Math.round(ia) + 10)
  d.pts[1] = { t, p: d.pts[1].p }; d.pts[2] = { t, p: d.pts[2].p }
}

// ------------------------------------------------------------ 手柄
/** 每个锚点在屏上的手柄位置（算出来的工具不一定就在锚点的价位上） */
export function handlePixels(ch: TVChart, d: Drawing, p: Pane, r: PriceRange): XY[] {
  const px = (q: DrawPoint): XY => ({ x: ch.indexToX(ch.indexAt(q.t)), y: ch.priceToY(q.p, p, r) })
  if (d.type === 'avwap' && d.pts.length) {
    const s = avwapStart(ch, d), b = s != null ? ch.bars[s] : undefined
    const x = s != null ? ch.indexToX(s) : px(d.pts[0]).x
    return [{ x, y: b ? ch.priceToY((b.h + b.l + b.c) / 3, p, r) : px(d.pts[0]).y }]
  }
  if (d.type === 'fvp' && d.pts.length >= 2) {
    const s = fvpShape(ch, d, p, r)
    if (s) {
      const y = ch.priceToY((s.v.lo + s.v.hi) / 2, p, r)
      const a = ch.indexAt(d.pts[0].t) <= ch.indexAt(d.pts[1].t)
      return a ? [{ x: s.x0, y }, { x: s.x1, y }] : [{ x: s.x1, y }, { x: s.x0, y }]
    }
    return d.pts.map(px)
  }
  if (d.type === 'position' && d.pts.length >= 3) {
    const a = px(d.pts[0]), b = px(d.pts[1]), c = px(d.pts[2])
    const x1 = Math.max(a.x, b.x)
    return [a, { x: x1, y: b.y }, { x: x1, y: c.y }]
  }
  return d.pts.map(px)
}
/** 拖第 k 个手柄到 now（持仓：止损手柄只改价位，目标手柄改框宽与目标价） */
export function moveHandle(d: Drawing, k: number, now: DrawPoint): void {
  if (d.type === 'position' && k === 2) { d.pts[2] = { t: d.pts[1].t, p: now.p }; return }
  if (d.type === 'position' && k === 1) { d.pts[1] = now; d.pts[2] = { t: now.t, p: d.pts[2].p }; return }
  d.pts[k] = now
}

// ------------------------------------------------------------ 包围框（选中时的快捷条放在它上方）
export function bbox(ch: TVChart, d: Drawing, p: Pane, r: PriceRange): { x0: number; y0: number; x1: number; y1: number } | null {
  if (!d.pts.length) return null
  const PW = ch.plotW()
  let pts = handlePixels(ch, d, p, r)
  if (d.type === 'hline') pts = [{ x: 0, y: pts[0].y }, { x: PW, y: pts[0].y }]
  if (d.type === 'vline') pts = [{ x: pts[0].x, y: p.y }, { x: pts[0].x, y: p.y + p.h }]
  if (d.type === 'fvp') { const s = fvpShape(ch, d, p, r); if (s) pts = [{ x: s.x0, y: ch.priceToY(s.v.hi, p, r) }, { x: s.x1, y: ch.priceToY(s.v.lo, p, r) }] }
  if (d.type === 'avwap') { const b = avwapPixels(ch, d, p, r); if (b.length) pts = pts.concat(b.filter((_, i) => i % 8 === 0 || i === b.length - 1)) }
  if (d.type === 'position') pts = pts.concat(d.pts.map(q => ({ x: ch.indexToX(ch.indexAt(d.pts[0].t)), y: ch.priceToY(q.p, p, r) })))
  const xs = pts.map(q => q.x), ys = pts.map(q => q.y)
  return { x0: Math.max(0, Math.min(...xs)), x1: Math.min(PW, Math.max(...xs)), y0: Math.max(p.y, Math.min(...ys)), y1: Math.min(p.y + p.h, Math.max(...ys)) }
}

/** 锚定 VWAP 中线在可见范围里的像素点 */
function avwapPixels(ch: TVChart, d: Drawing, p: Pane, r: PriceRange): XY[] {
  const i0 = avwapStart(ch, d), last = ch.lastIndex()
  if (i0 == null) return []
  const { to } = ch.visible()
  const end = Math.min(last, to + 1)
  if (end < i0) return []
  const bands = vwapOf(ch, d, i0, end)
  const from = Math.max(i0, Math.floor(ch.xToIndex(0)) - 1)
  const out: XY[] = []
  for (let i = from; i <= end; i++) { const v = bands.mid[i - i0]; if (v != null) out.push({ x: ch.indexToX(i), y: ch.priceToY(v, p, r) }) }
  return out
}

// ------------------------------------------------------------ 画
/** 画三把算出来的工具之一；别的工具返回 false 交回 chart.ts 画 */
export function drawComputed(ch: TVChart, d: Drawing, p: Pane, r: PriceRange, sel: boolean): boolean {
  if (!COMPUTED.has(d.type)) return false
  const c: Ctx = ch.ctx, col = d.color || '#2962FF'
  c.save()
  c.lineCap = 'round'; c.lineJoin = 'round'
  if (d.type === 'avwap') drawAvwap(ch, c, d, p, r, col)
  else if (d.type === 'fvp') drawFvp(ch, c, d, p, r, col, sel)
  else drawPosition(ch, c, d, p, r, col)
  c.restore()
  if (sel) {
    for (const q of handlePixels(ch, d, p, r)) { c.fillStyle = ch.colors.bg; c.strokeStyle = col; c.lineWidth = 2; c.beginPath(); c.arc(q.x, q.y, 4.5, 0, Math.PI * 2); c.fill(); c.stroke() }
  }
  return true
}

function drawAvwap(ch: TVChart, c: Ctx, d: Drawing, p: Pane, r: PriceRange, col: string): void {
  if (!d.pts.length) return
  const i0 = avwapStart(ch, d), last = ch.lastIndex()
  const { to } = ch.visible()
  const end = Math.min(last, to + 1)
  const ax = ch.indexToX(i0 ?? ch.indexAt(d.pts[0].t))
  // 锚点：图底一枚小三角，标出从哪根起算
  c.fillStyle = col; c.beginPath(); c.moveTo(ax, p.y + p.h - 2); c.lineTo(ax - 5, p.y + p.h - 10); c.lineTo(ax + 5, p.y + p.h - 10); c.closePath(); c.fill()
  if (i0 == null || end < i0) return
  const b = vwapOf(ch, d, i0, end)
  const from = Math.max(i0, Math.floor(ch.xToIndex(0)) - 1)
  const X = (i: number) => ch.indexToX(i), Y = (v: number) => ch.priceToY(v, p, r)
  const line = (s: number[], stroke: string, w: number, dash: number[] = []) => {
    c.strokeStyle = stroke; c.lineWidth = w; c.setLineDash(dash); c.beginPath()
    for (let i = from; i <= end; i++) { const x = X(i), y = Y(s[i - i0]); if (i === from) c.moveTo(x, y); else c.lineTo(x, y) }
    c.stroke(); c.setLineDash([])
  }
  line(b.mid, col, d.width || 1.5, dashPattern(d))
  if (end - from >= 0) {
    // 线尾标读数
    const v = b.mid[end - i0], x = X(end), y = Y(v)
    c.font = `11px ${ch.font.split('px ')[1] || 'sans-serif'}`; c.textBaseline = 'middle'; c.textAlign = 'left'
    const t = `VWAP ${fmt(v, ch.meta.dec)}`, w = c.measureText(t).width + 8
    if (x + 6 + w < ch.plotW()) { c.fillStyle = hexA(col, 0.14); roundRect(c, x + 6, y - 9, w, 18, 4); c.fill(); c.fillStyle = col; c.fillText(t, x + 10, y) }
  }
}

function drawFvp(ch: TVChart, c: Ctx, d: Drawing, p: Pane, r: PriceRange, col: string, sel: boolean): void {
  const s = fvpShape(ch, d, p, r)
  if (!s || !s.v.total) {
    // 圈的范围里还没有 K 线：只画两条边界
    const xs = d.pts.map(q => ch.indexToX(ch.indexAt(q.t)))
    c.strokeStyle = hexA(col, 0.5); c.lineWidth = 1; c.setLineDash([4, 4]); c.beginPath()
    for (const x of xs) { c.moveTo(Math.round(x) + .5, p.y); c.lineTo(Math.round(x) + .5, p.y + p.h) }
    c.stroke(); c.setLineDash([]); return
  }
  // 照 TradingView 固定区间成交量分布：底板、从左沿往右长的实色柱、价值区上下沿实线、控制点橙线（画法见 volumeProfile.ts）
  const C = ch.colors
  drawProfile(c, {
    x0: s.x0, x1: s.x1, v: s.v, mode: ch.vpvrMode, base: true,
    colors: { up: C.up || '#089981', down: C.down || '#F23645', line: col },
    priceToY: price => ch.priceToY(price, p, r), clipY: [p.y, p.y + p.h],
  })
  if (sel) {
    const yHi = ch.priceToY(s.v.hi, p, r), yLo = ch.priceToY(s.v.lo, p, r)
    c.strokeStyle = hexA(col, 0.6); c.lineWidth = 1
    c.strokeRect(Math.round(s.x0) + .5, Math.round(yHi) + .5, Math.round(s.x1 - s.x0), Math.round(yLo - yHi))
  }
}

function drawPosition(ch: TVChart, c: Ctx, d: Drawing, p: Pane, r: PriceRange, col: string): void {
  if (d.pts.length < 3) return
  const [ea, ta, sa] = d.pts
  const ax = ch.indexToX(ch.indexAt(ea.t)), bx = ch.indexToX(ch.indexAt(ta.t))
  const x0 = Math.min(ax, bx), x1 = Math.max(ax, bx), W = Math.max(1, x1 - x0)
  const ay = ch.priceToY(ea.p, p, r), by = ch.priceToY(ta.p, p, r), cy = ch.priceToY(sa.p, p, r)
  const up = ch.colors.up || '#089981', down = ch.colors.down || '#F23645'
  const box = (y0: number, y1: number, tint: string) => {
    const top = Math.min(y0, y1), h = Math.abs(y1 - y0)
    c.fillStyle = hexA(tint, 0.14); c.fillRect(x0, top, W, h)
    c.strokeStyle = hexA(tint, 0.7); c.lineWidth = 1; c.strokeRect(Math.round(x0) + .5, Math.round(top) + .5, Math.round(W), Math.round(h))
  }
  box(ay, by, up)   // 入场 → 目标：赚的那一半
  box(ay, cy, down) // 入场 → 止损：亏的那一半
  c.strokeStyle = col; c.lineWidth = d.width || 2; c.setLineDash(dashPattern(d))
  c.beginPath(); c.moveTo(x0, Math.round(ay) + .5); c.lineTo(x1, Math.round(ay) + .5); c.stroke(); c.setLineDash([])
  const s = positionStats(ea.p, ta.p, sa.p)
  const fam = ch.font.split('px ')[1] || 'sans-serif'
  c.font = `600 11px ${fam}`; c.textBaseline = 'middle'
  const chip = (text: string, x: number, y: number, bg: string, align: 'right' | 'center') => {
    const w = c.measureText(text).width + 12, h = 18
    const left = align === 'right' ? x - w : x - w / 2
    c.fillStyle = bg; roundRect(c, left, y - h / 2, w, h, 4); c.fill()
    c.fillStyle = '#fff'; c.textAlign = 'center'; c.fillText(text, left + w / 2, y)
  }
  // 三个读数各贴各的线：目标、止损甩到框外那一侧，盈亏比压在入场线中间（照手机，三条线两两不同高不会撞）
  chip(`目标 ${pctLabel(s.targetPct)}`, x1 - 3, by + (s.long ? -12 : 12), up, 'right')
  chip(`止损 ${pctLabel(s.stopPct)}`, x1 - 3, cy + (s.long ? 12 : -12), down, 'right')
  chip(`盈亏比 ${s.r == null ? '—' : s.r.toFixed(2)}`, (x0 + x1) / 2, ay, col, 'center')
}

// ------------------------------------------------------------ 命中
/** 点到三把算出来的工具身上的距离（px）；别的工具返回 null 交回 chart.ts 算 */
export function hitComputed(ch: TVChart, d: Drawing, x: number, y: number, p: Pane, r: PriceRange): number | null {
  if (!COMPUTED.has(d.type)) return null
  if (d.type === 'avwap') {
    const pts = avwapPixels(ch, d, p, r)
    let best = Infinity
    for (let i = 1; i < pts.length; i++) best = Math.min(best, segDist(x, y, pts[i - 1], pts[i]))
    if (pts.length === 1) best = Math.hypot(x - pts[0].x, y - pts[0].y)
    return best
  }
  if (d.type === 'fvp') {
    const s = fvpShape(ch, d, p, r); if (!s) return Infinity
    const yHi = ch.priceToY(s.v.hi, p, r), yLo = ch.priceToY(s.v.lo, p, r)
    return x >= s.x0 - 3 && x <= s.x1 + 3 && y >= yHi - 3 && y <= yLo + 3 ? 0 : Infinity
  }
  const [ea, ta, sa] = d.pts
  if (!sa) return Infinity
  const ax = ch.indexToX(ch.indexAt(ea.t)), bx = ch.indexToX(ch.indexAt(ta.t))
  const ys = [ea.p, ta.p, sa.p].map(v => ch.priceToY(v, p, r))
  const x0 = Math.min(ax, bx), x1 = Math.max(ax, bx), y0 = Math.min(...ys), y1 = Math.max(...ys)
  return x >= x0 - 3 && x <= x1 + 3 && y >= y0 - 3 && y <= y1 + 3 ? 0 : Infinity
}

// ------------------------------------------------------------ 小工具
export function segDist(x: number, y: number, a: XY, b: XY): number {
  const dx = b.x - a.x, dy = b.y - a.y, L = dx * dx + dy * dy
  const t = L ? Math.max(0, Math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / L)) : 0
  return Math.hypot(x - (a.x + t * dx), y - (a.y + t * dy))
}
function roundRect(c: Ctx, x: number, y: number, w: number, h: number, r: number): void { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath() }
