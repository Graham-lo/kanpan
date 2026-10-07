/* Hkline Web · 滚轮 / 触控板缩放与平移的算法（照 TradingView）
 *
 * 出处：TradingView 自家开源的 lightweight-charts（v5.2，和 TV 网页版同一套手感）
 *   · ChartWidget._onMousewheel：deltaX / deltaY 先乘 deltaMode 折算（行 32、页 120、像素 1；Windows 上的 Chromium 再除 DPR），
 *     再除以 100；纵向量夹成 sign·min(1, |d|) 交给 zoomTime（滚轮一格 ±100 = 满档 ±1），横向量 scrollChart(-80·dx)（一格 = 80 px）
 *   · TimeScale.zoom(zoomPoint, scale)：barSpacing += scale · barSpacing / 10（一格放大 ×1.1、缩小 ×0.9），
 *     再把右偏移挪回去，让 zoomPoint 底下那根（浮点下标）留在原地
 *   · 间距夹在 [minBarSpacing 0.5, maxBarSpacing]，默认 barSpacing 6；correctOffset：两头至少各留 2 根看得见
 *   · 时间轴拖动（TimeScale.scaleTo）：间距 = 起拖间距 × 起拖点到右沿的距离 / 现在到右沿的距离（右沿不动，往左拖放大）
 * 我们在 TV 之上加的：
 *   · 缩放不是一步到位，ZOOM_MS 内按 ease-out 插到目标间距；连续滚动把目标累加（目标 × 新的一格），中途锚点不动
 *   · Ctrl / ⌘ + 滚轮（触控板捏合在浏览器里就是带 ctrlKey 的滚轮）：按 e^(-deltaY/100) 跟手（捏到两倍就是两倍），
 *     单个事件仍夹在 TV 的一格（×0.9 – ×1.1）以内，鼠标 Ctrl + 一格与普通一格同档
 *   · Shift + 滚轮在没有 deltaX 的环境里（部分系统 / 驱动不替你换轴）按横滑处理
 */

/** 间距上下限（px / 根）：TV 的 minBarSpacing 0.5；上限 50（TV 默认是半个图宽，图很宽时一根能放到几百 px，没有用） */
export const MIN_SPACING = 0.5
export const MAX_SPACING = 50
/** 默认间距（TV barSpacing 默认 6）。右侧留白根数在图表设置里（chartSettings DEFAULTS.rightBars，默认 10 根，同 TV 网页版「右边距」） */
export const DEFAULT_SPACING = 6
/** 滚轮缩放的插值时长：停手后这么久之内到位 */
export const ZOOM_MS = 120
/** 横向一格（deltaX 100）平移的像素：TV scrollChart(-deltaX · 80) */
export const PAN_PX_PER_NOTCH = 80
/** 两头至少各留几根看得见（TV Constants.MinVisibleBarsCount） */
export const MIN_VISIBLE_BARS = 2

export const clampSpacing = (s: number): number => Math.min(MAX_SPACING, Math.max(MIN_SPACING, s))

/** deltaMode 折算系数（TV _determineWheelSpeedAdjustment）：页 120、行 32、像素 1；Windows 上的 Chromium 像素再除 DPR */
export function wheelSpeed(mode: number, winChromium = false, dpr = 1): number {
  if (mode === 2) return 120
  if (mode === 1) return 32
  return winChromium ? 1 / (dpr || 1) : 1
}

/** Windows 上的 Chromium（Chrome / Edge）：TV 用 userAgentData 判（isChromiumBased() && isWindows()），这里按 UA 近似 */
export const isWinChromium = (ua: string): boolean => /Windows|Win32|Win64/.test(ua) && /Chrome\//.test(ua)

export interface WheelLike { deltaX: number; deltaY: number; deltaMode: number; shiftKey?: boolean }
/** 一个滚轮事件折成 TV 的单位（÷100）：dx > 0 往新的那头走，dy > 0 放大（TV 里 deltaY 取反） */
export function wheelDelta(e: WheelLike, speed: number): { dx: number; dy: number } {
  let dx = e.deltaX * speed / 100, dy = -e.deltaY * speed / 100
  if (e.shiftKey && dx === 0) { dx = -dy; dy = 0 } // Shift + 竖滚 = 横滑（往下滚看更新的）
  return { dx, dy }
}

/** TV：纵向量夹成 ±1 的缩放档（一格滚轮正好满档） */
export const zoomScale = (dy: number): number => Math.sign(dy) * Math.min(1, Math.abs(dy))
/** TV TimeScale.zoom：一档 = 当前间距的 1/10 */
export const zoomFactor = (scale: number): number => 1 + scale / 10
/** Ctrl / 捏合：e^dy 跟手，单个事件夹在一格以内 */
export const pinchFactor = (dy: number): number => Math.min(zoomFactor(1), Math.max(zoomFactor(-1), Math.exp(dy)))
/** 横向量 → 平移的像素（正 = 往新的那头） */
export const panPx = (dx: number): number => dx * PAN_PX_PER_NOTCH

/** 让连续下标 idx 落在 x 上的右沿下标（右沿 = 绘图区宽 plotW 处） */
export const anchoredRightBar = (idx: number, x: number, plotW: number, spacing: number): number => idx + (plotW - x) / spacing
/** TV correctOffset：最新一根往左最多挪到只剩 2 根看得见，最老一根往右也一样（first = 0） */
export function clampRightBar(rb: number, last: number, plotW: number, spacing: number): number {
  if (last < 0 || !(plotW > 0) || !(spacing > 0)) return rb
  const keep = Math.min(MIN_VISIBLE_BARS, last + 1)
  const lo = keep - 1, hi = last + plotW / spacing - keep
  return hi < lo ? rb : Math.min(hi, Math.max(lo, rb))
}

/** ease-out（三次）：前段快、收尾慢，停手那一刻就开始收 */
export const easeOut = (t: number): number => 1 - (1 - Math.min(1, Math.max(0, t))) ** 3
/** 间距在对数空间里插值（放大缩小同一手感） */
export function easeSpacing(from: number, to: number, t: number): number {
  const k = easeOut(t)
  if (k <= 0 || from === to) return k <= 0 ? from : to // 两端原样给回，不让 exp(log(x)) 的末位误差冒成一次「回弹」
  if (k >= 1) return to
  return Math.exp(Math.log(from) + (Math.log(to) - Math.log(from)) * k)
}

/** 时间轴拖动（TV TimeScale.scaleTo）：右沿不动，按下处那根跟着鼠标走——间距 = 起拖间距 × 现在到右沿 / 起拖点到右沿
 *  （往左拖放大、往右拖缩小）；两段距离有一段为 0（拖进了价格轴那一角）返回 null = 这一下不动 */
export function timeAxisDragSpacing(sp0: number, x0: number, x: number, plotW: number): number | null {
  const now = Math.min(plotW, Math.max(0, plotW - x)), start = Math.min(plotW, Math.max(0, plotW - x0))
  if (!now || !start) return null
  return clampSpacing(sp0 * now / start)
}

/** 一段进行中的滚轮缩放：from → to 间距，t0 起算，锚点（连续下标 idx 保持在 x 上）；sp / rb 是上一次写进图里的值（别人改了就认出来） */
export interface ZoomAnim { from: number; to: number; t0: number; idx: number; x: number; sp: number; rb: number }

/** 接一格：目标在「还没到的目标」上累加，起点是现在实际的间距；锚点换成这一格鼠标下那根 */
export function zoomStart(prev: ZoomAnim | null, spacing: number, rightBar: number, factor: number, idx: number, x: number, now: number): ZoomAnim | null {
  const to = clampSpacing((prev ? prev.to : spacing) * factor)
  if (to === spacing) return null // 已经在上 / 下限：不起动画
  return { from: spacing, to, t0: now, idx, x, sp: spacing, rb: rightBar }
}

/** 推进一帧：返回这一帧的间距 / 右沿与是否到位 */
export function zoomStep(a: ZoomAnim, now: number, plotW: number, last: number): { spacing: number; rightBar: number; done: boolean } {
  const t = (now - a.t0) / ZOOM_MS, done = t >= 1
  const spacing = done ? a.to : easeSpacing(a.from, a.to, t)
  return { spacing, rightBar: clampRightBar(anchoredRightBar(a.idx, a.x, plotW, spacing), last, plotW, spacing), done }
}
