/* Hkline Web · 图标字形（2026-10-10 起照 OpenMarket 的画线栏语言重画：单一粗细细线）
 *
 * 规格：24 格（viewBox 0 0 24 24），字形占 3–21（留 3 内边）；一笔到底的细线，描边 1.5、圆头圆角、不填充；
 *   全部单色（--q1，落回 currentColor）；没有面、没有分层透明度、没有强调墨；涨跌方向不上色。
 *   线段的锚点 = 小实心圆点（r 1.6，同色）：趋势线两端各一点、射线起点一点……其余字形不加点。
 *   唯一的实心字形：u_star（已加自选）。
 * 描边粗细走 --qsw（默认 1.5）：字形按 24 px 摆时就是 1.5 px；CSS 把字形缩到别的尺寸时可改 --qsw 保持物理粗细。
 * 像素对齐：横竖线一律落在 .5 格上，整组再平移 .25——1.5 宽的线边缘正好落在 DPR 2 的物理像素格上，不糊。
 * 各 key 的含义与旧「质感」一套一一对应（画线种类名直接取；u_ 开头是界面记号；layoutN 是多图布局记号）。 */

type Op =
  | { t: 'p'; d: string }                                              // 描边路径
  | { t: 'c'; cx: number; cy: number; r: number }                     // 描边圆
  | { t: 'r'; x: number; y: number; w: number; h: number; rx: number } // 描边圆角矩形
  | { t: 'd'; x: number; y: number; r?: number }                       // 实心点（锚点 / i 上的点 / 列表圆点）
  | { t: 'f'; d: string }                                              // 实心面（只给 u_star）
  | { t: 'g'; tr: string; ops: Op[] }                                  // 变换组

const p = (d: string): Op => ({ t: 'p', d })
const c = (cx: number, cy: number, r: number): Op => ({ t: 'c', cx, cy, r })
const R = (x: number, y: number, w: number, h: number, rx = 2): Op => ({ t: 'r', x, y, w, h, rx })
const a = (x: number, y: number, r?: number): Op => ({ t: 'd', x, y, r })
const grp = (tr: string, ops: Op[]): Op => ({ t: 'g', tr, ops })
const n2 = (v: number): string => (+v.toFixed(2)).toString()

/** 五角星（圆角由 linejoin 给） */
const star = (cx: number, cy: number, ro: number, ri: number): string => {
  let d = ''
  for (let i = 0; i < 10; i++) {
    const r = i % 2 ? ri : ro, q = -Math.PI / 2 + i * Math.PI / 5
    d += (i ? 'L' : 'M') + n2(cx + r * Math.cos(q)) + ' ' + n2(cy + r * Math.sin(q))
  }
  return d + 'Z'
}
/** 齿轮外廓：8 齿，齿顶 / 齿根两圈 */
const gear = (): string => {
  const n = 8, ro = 8.6, ri = 6.6, st = 2 * Math.PI / n
  const P = (r: number, q: number): string => `${n2(12 + r * Math.cos(q))} ${n2(12 + r * Math.sin(q))}`
  let d = ''
  for (let i = 0; i < n; i++) {
    const q = i * st - Math.PI / 2
    d += (i ? 'L' : 'M') + P(ri, q - .3) + 'L' + P(ro, q - .17) + 'L' + P(ro, q + .17) + 'L' + P(ri, q + .3) + `A${ri} ${ri} 0 0 1 ` + P(ri, q + st - .3)
  }
  return d + 'Z'
}
/** 太阳的 8 道光：r0 → r1 */
const rays = (r0: number, r1: number): string => {
  let d = ''
  for (let i = 0; i < 8; i++) { const q = i * Math.PI / 4; d += `M${n2(12 + r0 * Math.cos(q))} ${n2(12 + r0 * Math.sin(q))}L${n2(12 + r1 * Math.cos(q))} ${n2(12 + r1 * Math.sin(q))}` }
  return d
}

const EYE = 'M3 12C5.4 7.6 8.4 5.5 12 5.5S18.6 7.6 21 12C18.6 16.4 15.6 18.5 12 18.5S5.4 16.4 3 12Z'
const ST = star(12, 12.6, 8.6, 4.1)
const TRAY = 'M4.5 13.5V18A2 2 0 0 0 6.5 20H17.5A2 2 0 0 0 19.5 18V13.5'
const UNDO = [p('M9 4.5L5 8.5L9 12.5'), p('M5 8.5H14.5A4.75 4.75 0 0 1 14.5 18H9.5')]
const BELL = 'M5 17.5H19L17.5 15.5V11A5.5 5.5 0 0 0 6.5 11V15.5Z'

export const G: Record<string, Op[]> = {
  // —— 画线工具 ——
  cursor: [c(12, 12, 7), p('M12 3V8M12 16V21M3 12H8M16 12H21')],
  trend: [p('M5 19L19 5'), a(5, 19), a(19, 5)],
  ray: [p('M5 19L20.5 3.5'), a(5, 19), a(11.5, 12.5)],
  extended: [p('M3.5 20.5L20.5 3.5'), a(9.5, 14.5), a(14.5, 9.5)],
  hline: [p('M3 12H21'), a(12, 12)],
  hray: [p('M5 12H21'), a(5, 12)],
  vline: [p('M12 3V21'), a(12, 12)],
  crossLine: [p('M3 12H21M12 3V21'), a(12, 12)],
  arrowLine: [p('M5 19L19 5M12 5H19V12'), a(5, 19)],
  channel: [p('M4 13L20 5M4 19L20 11'), a(4, 13), a(20, 5), a(12, 15)],
  regression: [p('M4 10.5L20 3.5M4 19.5L20 12.5'), p('M4 15L20 8'), a(4, 15), a(20, 8)],
  pitchfork: [p('M4 20L17 7M9 9L15 15M9 9L14 4M15 15L20 10'), a(4, 20), a(9, 9), a(15, 15)],
  gannBox: [R(4, 4, 16, 16, 1.5), p('M12 4V20M4 12H20M4 20L20 4')],
  gannFan: [p('M4 20L20 4M4 20L20 12M4 20L12 4M4 20L20 17M4 20L7 4'), a(4, 20)],
  fib: [p('M3 4H21M3 9H21M3 14H21M3 20H21'), p('M7 20L17 4'), a(7, 20), a(17, 4)],
  fibExtension: [p('M4.5 20L8.5 6L12.5 14.5'), p('M15.5 5H21M15.5 10H21M15.5 15H21'), a(4.5, 20), a(8.5, 6), a(12.5, 14.5)],
  fibChannel: [p('M4 12L12 4M8 16L16 8M12 20L20 12'), a(4, 12), a(12, 4), a(12, 12)],
  fibTimeZone: [p('M3.5 4V20M6.5 4V20M10 4V20M14.5 4V20M20.5 4V20')],
  fibFan: [p('M20 4V20M4 20L20 4M4 20L20 10M4 20L20 15'), a(4, 20)],
  xabcd: [p('M4 18L8 5L12 13L16 7L20 19'), p('M4 18L12 13L20 19'), a(4, 18), a(20, 19)],
  abcd: [p('M4 19L9 6L14.5 14L20 5'), a(4, 19), a(20, 5)],
  headShoulders: [p('M3 19.5L6.5 9L9 14.5L12 4L15 14.5L17.5 9L21 19.5'), p('M3.5 14.5H20.5')],
  elliottImpulse: [p('M4 20L7.5 12.5L10.5 15.5L15 6L17.5 9.5L20 4.5'), a(4, 20), a(20, 4.5)],
  elliottCorrection: [p('M4 4.5L9.5 16L13.5 10L20 19.5'), a(4, 4.5), a(20, 19.5)],
  // 多空仓位：开仓价那根线从左边伸进止盈 / 止损框
  position: [R(8, 4, 12, 16, 2), p('M4.5 13H20'), a(4.5, 13)],
  ptMeasure: [grp('rotate(-45 12 12)', [R(3, 8.5, 18, 7, 1.5), p('M7 8.5V11.5M10 8.5V10.5M13 8.5V11.5M16 8.5V10.5')])],
  priceRange: [p('M4 4H20M4 20H20'), p('M12 7.5V16.5M9 10L12 7L15 10M9 14L12 17L15 14')],
  dateRange: [p('M4 4V20M20 4V20'), p('M7.5 12H16.5M10 9L7 12L10 15M14 9L17 12L14 15')],
  datePriceRange: [R(4, 4, 16, 16, 1.5), p('M8.5 15.5L15.5 8.5M10.5 8.5H15.5V13.5')],
  rect: [R(4, 6, 16, 12, 1), a(4, 6), a(20, 18)],
  ellipse: [p('M4 12A8 5.5 0 1 0 20 12A8 5.5 0 1 0 4 12Z'), a(4, 12), a(20, 12)],
  triangle: [p('M12 4.5L20 19H4Z'), a(12, 4.5), a(20, 19), a(4, 19)],
  curve: [p('M4 19Q11 0 20 16'), a(4, 19), a(20, 16)],
  note: [p('M5 6.5V4.5H19V6.5M12 4.5V19.5M9.5 19.5H14.5')],
  callout: [p('M6 4.5H18A2 2 0 0 1 20 6.5V14.5A2 2 0 0 1 18 16.5H11.5L7.5 20V16.5H6A2 2 0 0 1 4 14.5V6.5A2 2 0 0 1 6 4.5Z'), p('M8 9H16M8 12.5H13')],
  priceLabel: [p('M3.5 12L8 6.5H18.5A2 2 0 0 1 20.5 8.5V15.5A2 2 0 0 1 18.5 17.5H8Z'), p('M11 12H17')],
  flag: [p('M6 20.5V4H18.5L16 8.5L18.5 13H6')],
  markerUp: [p('M12 20V4.5M6 10.5L12 4.5L18 10.5')],
  markerDown: [p('M12 4V19.5M6 13.5L12 19.5L18 13.5')],
  // 锚定 VWAP：锚点竖线（锚点上方断开，点才看得见）+ 从锚点出发的均价曲线
  avwap: [p('M4.5 4V14'), p('M4.5 18C11 18 12 7 20 6.5'), a(4.5, 18)],
  fvp: [p('M4 4V20M20 4V20'), p('M7 6H11M7 10H14M7 14H17M7 18H12')],
  anchoredVolumeProfile: [p('M4.5 4V18'), p('M8 6H12M8 10H15M8 14H19M8 18H13'), a(4.5, 19.5)],
  // 临时测量（⇧ 拖）——三角尺，和「预测与测量」组里的直尺（ptMeasure）分开
  measure: [p('M4.5 4.5V19.5H19.5Z'), p('M8 11.5V16H12.5Z')],
  magnet: [p('M5 4H9V12A3 3 0 0 0 15 12V4H19V12A7 7 0 0 1 5 12Z'), p('M5 7.5H9M15 7.5H19')],
  lock: [R(5, 11, 14, 9.5, 2), p('M8 11V8A4 4 0 0 1 16 8V11'), p('M12 14.5V17')],
  eye: [p(EYE), c(12, 12, 3)],
  trash: [p('M4 6.5H20M9.5 6.5V4.5H14.5V6.5M6.5 6.5L7.5 20H16.5L17.5 6.5M10.5 10.5V16M13.5 10.5V16')],

  // —— 界面 ——
  u_search: [c(10.5, 10.5, 6.5), p('M15.5 15.5L20 20')],
  u_bell: [p(BELL), p('M12 3.5V5.5M10 20A2 2 0 0 0 14 20')],
  // 建提醒：铃往左下让出右上角放加号
  u_bellPlus: [p('M3.5 18.5H15.5L14.5 16.5V12.5A4.5 4.5 0 0 0 5.5 12.5V16.5Z'), p('M10 6V8M8.5 21A1.5 1.5 0 0 0 11.5 21'), p('M18 3V9M15 6H21')],
  u_ind: [R(4, 4, 16, 16, 3), p('M7.5 15L10.5 11L13.5 13.5L16.5 8.5')],
  u_cmp: [p('M4 11.5L8.5 7L12.5 10L20 4.5'), p('M4 17L8.5 19L13 14L20 16.5')],
  // 笔记 / 记一笔：一页纸 + 斜放的铅笔
  u_note: [p('M16 10.5V6A2 2 0 0 0 14 4H6.5A2 2 0 0 0 4.5 6V18A2 2 0 0 0 6.5 20H10.5'), p('M8 8.5H12.5M8 12H11'), p('M18.5 11.5L20.5 13.5L14.5 19.5L12 20L12.5 17.5Z')],
  // 热力图：火苗（照 OpenMarket 的「热」）
  u_heat: [p('M12 20.5C8.5 20.5 6 18 6 14.5C6 11 9 9.5 9.5 4.5C12 6.5 13 8.5 13 10.5C14 9.5 14.5 8.5 14.5 7.5C16.5 9 18 11.5 18 14.5C18 18 15.5 20.5 12 20.5Z'), p('M12 20.5C10.6 20.5 9.5 19.4 9.5 18C9.5 16.4 10.8 15.6 11.5 13.5C13 14.6 14.5 16 14.5 18C14.5 19.4 13.4 20.5 12 20.5Z')],
  // 主力订单流：一根 K 线 + 右边三道挂单带
  u_flow: [R(5, 7.5, 4, 8, 1), p('M7 4V7.5M7 15.5V19.5'), p('M12.5 9H21M12.5 13.5H18M12.5 18H20')],
  u_layout: [R(3, 4, 18, 16, 2), p('M12 4V20M12 12H21')],
  u_camera: [p('M4 8.5A2 2 0 0 1 6 6.5H8L9.5 4.5H14.5L16 6.5H18A2 2 0 0 1 20 8.5V17.5A2 2 0 0 1 18 19.5H6A2 2 0 0 1 4 17.5Z'), c(12, 13, 3.5)],
  u_full: [p('M4 9V4H9M15 4H20V9M20 15V20H15M9 20H4V15')],
  u_undo: UNDO,
  u_redo: [grp('matrix(-1 0 0 1 24 0)', UNDO)],
  u_set: [p(gear()), c(12, 12, 2.75)],
  u_eyeOff: [p(EYE), c(12, 12, 3), p('M4.5 4L19.5 20')],
  u_star: [{ t: 'f', d: ST }, p(ST)],
  u_starOff: [p(ST)],
  u_starLine: [p(ST)],
  u_list: [p('M10.5 6.5H20M10.5 12H20M10.5 17.5H17'), a(6, 6.5, 1.25), a(6, 12, 1.25), a(6, 17.5, 1.25)],
  // 成交 / 大单：大小三颗气泡
  u_trades: [c(8.5, 14, 5), c(16, 7.5, 3.5), c(17.5, 17.5, 2)],
  u_info: [c(12, 12, 8.5), p('M12 11V16.5'), a(12, 7.75, 1.1)],
  u_sun: [c(12, 12, 3.5), p(rays(6.5, 8.5))],
  u_moon: [p('M19.5 14.5A8 8 0 1 1 9.5 4.5A6.5 6.5 0 0 0 19.5 14.5Z')],
  u_share: [p(TRAY), p('M12 15V4M8 8L12 4L16 8')],
  u_export: [p(TRAY), p('M12 4V15M8 11L12 15L16 11')],
  u_pencil: [p('M15.5 4.5L19.5 8.5L9 19L4.5 19.5L5 15Z'), p('M13 7L17 11')],
  // K 线回放：起点竖线 + 播放三角
  u_replay: [p('M5 5V19'), p('M9.5 5.5V18.5L19.5 12Z')],
}

/* 多图布局记号：一个 18×16 圆角框按 cols × rows 分格（分隔线都落在 .5 格上；三行时中间那格窄 .5，看不出） */
const qGrid = (cols: number, rows: number): Op[] => {
  const xs = cols === 3 ? [9, 15] : Array.from({ length: cols - 1 }, (_, i) => 3 + 18 * (i + 1) / cols)
  const ys = rows === 3 ? [9.5, 14.5] : Array.from({ length: rows - 1 }, (_, i) => 4 + 16 * (i + 1) / rows)
  const d = xs.map(x => `M${x} 4V20`).join('') + ys.map(y => `M3 ${y}H21`).join('')
  return d ? [R(3, 4, 18, 16, 2), p(d)] : [R(3, 4, 18, 16, 2)]
}
Object.assign(G, {
  layout1: qGrid(1, 1), layout2: qGrid(2, 1), layout2v: qGrid(1, 2), layout3: G.u_layout, layout4: qGrid(2, 2),
  layout6: qGrid(3, 2), layout8: qGrid(4, 2), layout9: qGrid(3, 3), layout12: qGrid(4, 3), layout16: qGrid(4, 4),
})

const INK = 'var(--q1,currentColor)'

/** 字形 → svg 内容（描边属性挂在外层组上，见 qsvg） */
export function rQ(ops: Op[]): string {
  return ops.map(o => {
    switch (o.t) {
      case 'p': return `<path d="${o.d}"/>`
      case 'c': return `<circle cx="${o.cx}" cy="${o.cy}" r="${o.r}"/>`
      case 'r': return `<rect x="${o.x}" y="${o.y}" width="${o.w}" height="${o.h}" rx="${o.rx}"/>`
      case 'd': return `<circle cx="${o.x}" cy="${o.y}" r="${o.r ?? 1.6}" style="fill:${INK};stroke:none"/>`
      case 'f': return `<path d="${o.d}" style="fill:${INK}"/>`
      case 'g': return `<g transform="${o.tr}">${rQ(o.ops)}</g>`
    }
    return ''
  }).join('')
}

/** 界面名 → 字形（画线种类直接按种类名取，见 toolGlyph；「note」在界面上是笔记 / 记一笔，画线里是文字注释，所以分两条路） */
export const UI_Q: Record<string, string> = {
  search: 'u_search', bell: 'u_bell', bellPlus: 'u_bellPlus', indicators: 'u_ind', compare: 'u_cmp', note: 'u_note',
  heat: 'u_heat', flow: 'u_flow', layout: 'u_layout', camera: 'u_camera', fullscreen: 'u_full', undo: 'u_undo', redo: 'u_redo',
  gear: 'u_set', eye: 'eye', eyeOff: 'u_eyeOff', star: 'u_star', starOff: 'u_starOff', starLine: 'u_starLine', list: 'u_list',
  trades: 'u_trades', info: 'u_info', sun: 'u_sun', moon: 'u_moon', share: 'u_share', pencil: 'u_pencil',
  cursor: 'cursor', magnet: 'magnet', lock: 'lock', trash: 'trash', measure: 'measure',
}

const WRAP = `<g transform="translate(.25 .25)" style="fill:none;stroke:${INK};stroke-width:var(--qsw,1.5);stroke-linecap:round;stroke-linejoin:round">`

/** 字形的 svg（24 格）；cls 照旧决定尺寸 */
export const qsvg = (key: string, cls: string): string =>
  `<svg class="${cls} q${key === 'trash' ? ' q-del' : ''}" viewBox="0 0 24 24" aria-hidden="true">${WRAP}${rQ(G[key] ?? [])}</g></svg>`
