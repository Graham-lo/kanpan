/* Hkline Web · 图表页的尺寸与分隔条
 *
 * 图表页的网格（layoutSlots 排的那张）里三处能拖：
 *   深度梯子列与图表区之间 —— 竖线，改梯子宽（160–480，默认 240）
 *   右侧面板左沿           —— 竖线，改面板宽（320–640，默认 320）
 *   底部抽屉上沿           —— 横线，改抽屉高（160 到页面高的 60%，默认 280）
 * 多图网格里每两列之间一条竖线、每两行之间一条横线，按布局各记一组比例。
 * 左侧工具列与顶部工具栏不动。尺寸只存本机（app/sizes.ts），窗口变小时按比例收、变回来复原。
 */
import { GRID, type Layout } from '../app/store'
import { sizes, saveSizes, fitWidths, fitDrawer, clampSize, trackFracs, fitTracks, dragTracks, REGIONS, CHART_MIN_W, TRACK_MIN_W, TRACK_MIN_H } from '../app/sizes'
import { splitter, type Splitter } from '../ui/splitter'

const px = (el: Element, name: string, def: number): number => {
  const v = parseFloat(getComputedStyle(el).getPropertyValue(name))
  return isFinite(v) ? v : def
}

// ------------------------------------------------------------ 页面三处
export interface SlotsOn { ladder: boolean; panel: boolean; drawer: boolean }

/** 把本机尺寸按当前窗口夹一遍，写成图表页上的 CSS 变量（--ladder-w / --panel-w / --drawer-h） */
export function applyPageSizes(page: HTMLElement, on: SlotsOn): void {
  const gut = px(page, '--gutter', 4), draw = px(page, '--drawbar-w', 48), rail = px(page, '--rail-w', 48)
  const ncol = 3 + (on.ladder ? 1 : 0) + (on.panel ? 1 : 0)
  const room = page.clientWidth - 2 * gut - draw - rail - (ncol - 1) * gut
  const w = fitWidths(on.ladder ? sizes.ladder ?? REGIONS.ladder.def : null, on.panel ? sizes.panel ?? REGIONS.panel.def : null, room)
  const s = page.style
  if (w.ladder != null) s.setProperty('--ladder-w', `${w.ladder}px`)
  if (w.panel != null) s.setProperty('--panel-w', `${w.panel}px`)
  if (on.drawer) s.setProperty('--drawer-h', `${fitDrawer(sizes.drawer, pageBodyH(page))}px`)
}
/** 顶栏以下、图表区 + 抽屉那一段的高 */
function pageBodyH(page: HTMLElement): number {
  const gut = px(page, '--gutter', 4), tb = px(page, '--toolbar-h', 40)
  return page.clientHeight - 2 * gut - tb - gut
}

let pageSplits: { ladder: Splitter; panel: Splitter; drawer: Splitter } | null = null

/**
 * 摆好页面上的三条分隔线（没开的槽位藏起来）。relayout = 重新排图表页（layoutSlots）。
 * 位置按各槽位的实际矩形算：线的中心落在两块之间的那道间隙正中。
 */
export function placePageSplits(page: HTMLElement, on: SlotsOn, relayout: () => void): void {
  const $ = (id: string): HTMLElement | null => page.querySelector<HTMLElement>(`#${id}`)
  if (!pageSplits || pageSplits.ladder.el.parentElement !== page) pageSplits = makePageSplits(page, relayout)
  const pr = page.getBoundingClientRect(), gut = px(page, '--gutter', 4)
  const place = (sp: Splitter, el: HTMLElement | null, show: boolean, dir: 'x' | 'y'): void => {
    if (!show || !el || el.hidden) { sp.show(false); return }
    const r = el.getBoundingClientRect()
    if (!r.width || !r.height) { sp.show(false); return }
    sp.show(true)
    if (dir === 'x') sp.place(r.left - pr.left - gut / 2, r.top - pr.top, r.bottom - pr.top)
    else sp.place(r.top - pr.top - gut / 2, r.left - pr.left, r.right - pr.left)
  }
  place(pageSplits.ladder, $('ladderSlot'), on.ladder, 'x')
  place(pageSplits.panel, $('sidePanel'), on.panel, 'x')
  place(pageSplits.drawer, $('drawerSlot'), on.drawer, 'y')
}

function makePageSplits(page: HTMLElement, relayout: () => void): { ladder: Splitter; panel: Splitter; drawer: Splitter } {
  const rect = (id: string): DOMRect => (page.querySelector(`#${id}`) as HTMLElement).getBoundingClientRect()
  let w0 = 0, room = 0
  const tip = '拖动调整，双击恢复默认'
  const start = (id: string) => () => { w0 = rect(id).width; room = rect('chartArea').width - CHART_MIN_W }
  return {
    ladder: splitter({
      dir: 'x', parent: page, name: 'ladder', tip,
      onStart: start('ladderSlot'),
      onMove: d => { sizes.ladder = clampSize(w0 - d, REGIONS.ladder, Math.min(REGIONS.ladder.max, w0 + Math.max(0, room))); relayout() },
      onEnd: saveSizes,
      onReset: () => { delete sizes.ladder; saveSizes(); relayout() },
    }),
    panel: splitter({
      dir: 'x', parent: page, name: 'panel', tip,
      onStart: start('sidePanel'),
      onMove: d => { sizes.panel = clampSize(w0 - d, REGIONS.panel, Math.min(REGIONS.panel.max, w0 + Math.max(0, room))); relayout() },
      onEnd: saveSizes,
      onReset: () => { delete sizes.panel; saveSizes(); relayout() },
    }),
    drawer: splitter({
      dir: 'y', parent: page, name: 'drawer', tip,
      onStart: () => { w0 = rect('drawerSlot').height },
      onMove: d => { sizes.drawer = fitDrawer(w0 - d, pageBodyH(page)); relayout() },
      onEnd: saveSizes,
      onReset: () => { delete sizes.drawer; saveSizes(); relayout() },
    }),
  }
}

// ------------------------------------------------------------ 多图网格
/** 按布局与本机比例排多图网格；cells = 各格子的元素（按格子顺序） */
/** 这种布局现在生效的列宽 / 行高比例：存的比例按当前像素夹到每条不小于下限 */
function liveFracs(area: HTMLElement, layout: Layout, axis: 'cols' | 'rows'): number[] {
  const n = GRID[layout][axis], gut = px(area, '--gutter', 4)
  const total = (axis === 'cols' ? area.clientWidth : area.clientHeight) - (n - 1) * gut
  return fitTracks(trackFracs(sizes.grid?.[layout]?.[axis], n), total, axis === 'cols' ? TRACK_MIN_W : TRACK_MIN_H)
}
export function applyGrid(area: HTMLElement, layout: Layout, cells: readonly HTMLElement[]): void {
  const g = GRID[layout]
  const cols = liveFracs(area, layout, 'cols'), rows = liveFracs(area, layout, 'rows')
  const fr = (f: number[]): string => f.map(x => `minmax(0, ${(x * 1000).toFixed(3)}fr)`).join(' ')
  area.style.gridTemplateColumns = fr(cols)
  area.style.gridTemplateRows = fr(rows)
  area.style.gridTemplateAreas = g.areas ? g.areas.map(r => `"${r.join(' ')}"`).join(' ') : ''
  const letters = g.areas ? [...new Set(g.areas.flat())] : null
  cells.forEach((el, i) => { el.style.gridArea = letters ? letters[i] || '' : '' })
}

let gridSplits: Splitter[] = []
let gridDrag: { fr: number[]; total: number } | null = null

/** 摆多图网格的分隔线（挂在图表区里）；relayout = 重排网格并重摆分隔线 */
export function placeGridSplits(area: HTMLElement, layout: Layout, relayout: () => void): void {
  const g = GRID[layout]
  const want = (g.cols - 1) + (g.rows - 1)
  gridSplits = gridSplits.filter(s => s.el.parentElement === area)
  if (gridSplits.length !== want || gridSplits.some(s => s.el.dataset.layout !== layout)) {
    gridSplits.forEach(s => s.destroy()); gridSplits = []
    for (let i = 0; i < g.cols - 1; i++) gridSplits.push(gridSplitter(area, layout, 'cols', i, relayout))
    for (let i = 0; i < g.rows - 1; i++) gridSplits.push(gridSplitter(area, layout, 'rows', i, relayout))
  }
  const gut = px(area, '--gutter', 4)
  const W = area.clientWidth, H = area.clientHeight
  const cols = liveFracs(area, layout, 'cols'), rows = liveFracs(area, layout, 'rows')
  const tw = W - (g.cols - 1) * gut, th = H - (g.rows - 1) * gut
  let k = 0, x = 0, y = 0
  for (let i = 0; i < g.cols - 1; i++) { x += cols[i] * tw; gridSplits[k++].place(x + i * gut + gut / 2, 0, H) }
  // 「左一右二」：行分隔线只横在右边那列
  const from = g.areas ? cols[0] * tw + gut : 0
  for (let i = 0; i < g.rows - 1; i++) { y += rows[i] * th; gridSplits[k++].place(y + i * gut + gut / 2, from, W) }
}

function gridSplitter(area: HTMLElement, layout: Layout, axis: 'cols' | 'rows', i: number, relayout: () => void): Splitter {
  const g = GRID[layout]
  const sp = splitter({
    dir: axis === 'cols' ? 'x' : 'y', parent: area, name: `grid-${axis}-${i}`, tip: '拖动调整，双击恢复平均',
    onStart: () => {
      const n = axis === 'cols' ? g.cols : g.rows, gut = px(area, '--gutter', 4)
      const total = (axis === 'cols' ? area.clientWidth : area.clientHeight) - (n - 1) * gut
      gridDrag = { fr: liveFracs(area, layout, axis), total }
    },
    onMove: d => {
      if (!gridDrag) return
      const grid = (sizes.grid ||= {}), mine = (grid[layout] ||= {})
      mine[axis] = dragTracks(gridDrag.fr, i, d, gridDrag.total, axis === 'cols' ? TRACK_MIN_W : TRACK_MIN_H).map(x => +x.toFixed(5))
      relayout()
    },
    onEnd: () => { gridDrag = null; saveSizes() },
    onReset: () => {
      const mine = sizes.grid?.[layout]
      if (mine) { delete mine[axis]; if (!mine.cols && !mine.rows) delete sizes.grid![layout] }
      saveSizes(); relayout()
    },
  })
  sp.el.dataset.layout = layout
  return sp
}

