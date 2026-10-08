/* Hkline Web · 图标「质感」一套（2026-10-08 用户定版，照 docs/prototypes/web-visual-2026-10-08.html 原样搬过来）
 *
 * 字形 = SF Symbols 分层：主体 1，次要 .55，面与辅助 .22–.28；关键点（锚点 / 斐波那契亮档 / 当前部位的尖）一处强调墨，每个图标最多一处。
 * 几何语言：18 格；线 = 2.2 圆头条，锚点 = 实心圆点带底色内沿，面 = 淡填充，斐波那契 = 透明度递减的几根条。
 * 颜色只走三个变量（随底块状态由 CSS 改，见 styles/icons.css）：
 *   --q1 主体（静止 = 主文字色混 20% 次文字色，悬停 = 主文字色，选中 = 白）
 *   --qa 强调墨（皮肤强调字色；选中 = 白）
 *   --qw 底色内沿（锚点外圈、字形里的「挖空」：等于底块中间色，看起来就是镂空）
 * 不在底块里用（面板、菜单里的小图标）时三个变量都没设：主体 / 强调跟 currentColor，内沿取卡片底色。
 * 涨跌方向不上色（跌那一半退到 .55）。
 * 原型里没有、真 app 里要用的几只（测量、分享、带加号的铃、铅笔、空心星）照同一套几何语言补齐，标了「补」。 */

interface Op {
  t: 'l' | 'a' | 'f' | 's' | 'r' | 'o' | 'g' | 'cut'
  d?: string; r?: string | number; o?: number; w?: number; c?: string | null
  x?: number; y?: number; s?: number; h?: number; rx?: number; cx?: number; cy?: number
  tr?: string; ops?: Op[]
}

export const G: Record<string, Op[]> = (() => {
  const l = (d: string, r = 'm', o?: number, w?: number, c?: string): Op => ({ t: 'l', d, r, o, w, c })
  const a = (x: number, y: number, s = 1): Op => ({ t: 'a', x, y, s })
  const f = (d: string, o?: number, c?: string): Op => ({ t: 'f', d, o, c })
  const s = (d: string, o?: number, c?: string | null, h?: number): Op => ({ t: 's', d, o, c, h })
  const R = (x: number, y: number, w: number, h: number, rx: number, o?: number, c?: string | null, _h?: number): Op => ({ t: 'r', x, y, w, h, rx, o, c })
  const O = (cx: number, cy: number, r: number, o?: number, c?: string): Op => ({ t: 'o', cx, cy, r, o, c })
  const grp = (tr: string, ops: Op[]): Op => ({ t: 'g', tr, ops })
  const cut = (d: string, w: number, ops: Op[]): Op => ({ t: 'cut', d, w, ops })
  const cp = (cx: number, cy: number, r: number): string => `M${cx - r} ${cy}a${r} ${r} 0 1 0 ${2 * r} 0a${r} ${r} 0 1 0 ${-2 * r} 0Z`
  const star = (cx: number, cy: number, ro: number, ri: number): string => {
    let p = ''
    for (let i = 0; i < 10; i++) { const r = i % 2 ? ri : ro, q = -Math.PI / 2 + i * Math.PI / 5; p += (i ? 'L' : 'M') + (cx + r * Math.cos(q)).toFixed(2) + ' ' + (cy + r * Math.sin(q)).toFixed(2) }
    return p + 'Z'
  }
  const gear = (): string => {
    const n = 8, ro = 7.7, ri = 5.7, st = 2 * Math.PI / n; let p = ''
    const P = (r: number, q: number): string => `${(9 + r * Math.cos(q)).toFixed(2)} ${(9 + r * Math.sin(q)).toFixed(2)}`
    for (let i = 0; i < n; i++) { const q = i * st - Math.PI / 2; p += (i ? 'L' : 'M') + P(ri, q - .3) + 'L' + P(ro, q - .18) + 'L' + P(ro, q + .18) + 'L' + P(ri, q + .3) + `A${ri} ${ri} 0 0 1 ` + P(ri, q + st - .3) }
    return p + 'Z' + cp(9, 9, 2.7).replace(/a(\S+) (\S+) 0 1 0/g, 'a$1 $2 0 1 1')
  }
  const EY = 'M1.4 9C3.4 5.2 5.9 3.6 9 3.6S14.6 5.2 16.6 9C14.6 12.8 12.1 14.4 9 14.4S3.4 12.8 1.4 9Z'
  const eye = [f(EY, .26), l(EY, 'm', 1, 1.8), O(9, 9, 3.1, 1), O(10.15, 7.85, 1, 1, 'w')]
  const E = 'M1.6 9A7.4 5.2 0 1 0 16.4 9A7.4 5.2 0 1 0 1.6 9Z'
  const BUB = 'M4.4 2.4H13.6A2.6 2.6 0 0 1 16.2 5V10.2A2.6 2.6 0 0 1 13.6 12.8H8.6L5 15.8V12.8H4.4A2.6 2.6 0 0 1 1.8 10.2V5A2.6 2.6 0 0 1 4.4 2.4Z'
  const undo = [l('M6.6 6.4H11A4.6 4.6 0 0 1 11 15.6H6.4', 'm', .62), s('M1.8 6.4L6.8 2.3V10.5Z', 1)]
  const heat: Op[] = []
  for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++)
    heat.push(R(1 + c * 4.2, 1 + r * 4.2, 3.4, 3.4, .8, +(.25 + ((c * 3 + r * 5) % 7) / 9).toFixed(2), (c + r) % 3 ? null : 'k2'))
  const hist = (x: number): Op[] => [R(x, 2.4, 6, 2.6, 1.3, .45), R(x, 5.9, 9, 2.6, 1.3, .65), R(x, 9.4, 16 - x - .6 + 0, 2.6, 1.3, 1), R(x, 12.9, 7, 2.6, 1.3, .65)]
  const bell = [s('M9 1.6c.55 0 1 .45 1 1v.55a4.9 4.9 0 0 1 3.9 4.8v2.7l1.35 2.05a.9.9 0 0 1-.75 1.4H3.5a.9.9 0 0 1-.75-1.4L4.1 10.65V7.95A4.9 4.9 0 0 1 8 3.15V2.6c0-.55.45-1 1-1Z', .9, null, 1), s('M6.9 15.2h4.2a2.1 2.1 0 0 1-4.2 0Z', 1), R(5.9, 6.6, 1.5, 3.6, .75, .55, 'w')]
  const ST = star(9, 9.7, 7.9, 3.8)
  const g: Record<string, Op[]> = {
    cursor: [l('M9 1.8V6M9 12V16.2M1.8 9H6M12 9H16.2'), O(9, 9, 1.7, 1)],
    trend: [l('M3 15L15 3'), a(3, 15), a(15, 3)],
    ray: [l('M10 8L16.6 1.4', 'x'), l('M3 15L10 8'), a(3, 15), a(10, 8)],
    extended: [l('M1.4 16.6L5.5 12.5M12.5 5.5L16.6 1.4', 'x'), l('M5.5 12.5L12.5 5.5'), a(5.5, 12.5), a(12.5, 5.5)],
    hline: [R(3.4, 10.9, 2.6, 5.2, 1.3, .3), R(12, 2.1, 2.6, 5, 1.3, .3), l('M1.6 9H16.4'), a(9, 9)],
    hray: [R(8.4, 10.9, 2.6, 5.2, 1.3, .3), R(12.8, 2.1, 2.6, 5, 1.3, .3), l('M3.6 9H16.4'), a(3.6, 9)],
    vline: [R(2.6, 3.4, 2.6, 6.2, 1.3, .3), R(12.8, 8.4, 2.6, 6.2, 1.3, .3), l('M9 1.6V16.4'), a(9, 9)],
    crossLine: [l('M1.6 9H16.4M9 1.6V16.4'), a(9, 9)],
    arrowLine: [l('M3 15L11.4 6.6'), s('M15.9 2.1L14.6 8.4L9.6 3.4Z', 1), a(3, 15)],
    channel: [f('M2 10.5L16 3V8L2 15.5Z'), l('M2 10.5L16 3M2 15.5L16 8'), a(2, 10.5), a(16, 3), a(9, 11.75, 0)],
    regression: [f('M2 8.6L16 2.6V9.4L2 15.4Z', .16), l('M2 8.6L16 2.6M2 15.4L16 9.4', 's'), l('M2 12L16 6', 'k'), a(2, 12), a(16, 6)],
    pitchfork: [f('M8 5L16.5 1.3V12.1L11 14.5Z'), l('M8 5L11 14.5', 'g'), l('M8 5L16.5 1.3M11 14.5L16.5 12.1', 's'), l('M2 13L16.5 6.7', 'k'), a(2, 13), a(8, 5, 0), a(11, 14.5, 0)],
    gannBox: [f('M2 2H16V16H2Z', .12), l('M6.67 2V16M11.33 2V16M2 6.67H16M2 11.33H16', 'g', .32, 1.3), l('M2 2H16V16H2Z', 's'), l('M2 16L16 2', 'k'), a(2, 16), a(16, 2)],
    gannFan: [f('M2 16L16 7.5V2H7.5Z', .16), l('M2 16L16 12M2 16L6 2', 'g'), l('M2 16L16 7.5M2 16L7.5 2', 'k', .6), l('M2 16L16 2', 'k'), a(2, 16)],
    fib: [f('M2 6.8H16V11.2H2Z', .14), l('M2 2.6H16', 'k', 1), l('M2 6.8H16', 'k', .74), l('M2 11.2H16', 'k', .5), l('M2 15.4H16', 'k', .3), l('M4.2 15.4L13.8 2.6', 'x', .38, 1.6), a(4.2, 15.4), a(13.8, 2.6)],
    fibExtension: [l('M12 2.6H16.6', 'k', 1), l('M12 6.8H16.6', 'k', .62), l('M12 11H16.6', 'k', .36), l('M2 15.4L6.6 4L10.4 11'), a(2, 15.4), a(6.6, 4, 0), a(10.4, 11, 0)],
    fibChannel: [f('M1.6 9.6L9.6 1.6L12.6 4.6L4.6 12.6Z', .16), l('M1.6 9.6L9.6 1.6', 'k', 1), l('M4.6 12.6L12.6 4.6', 'k', .62), l('M7.6 15.6L15.6 7.6', 'k', .36), a(1.6, 9.6), a(9.6, 1.6), a(11.6, 11.6, 0)],
    fibTimeZone: [l('M2 2V16', 'k', 1), l('M4.8 2V16', 'k', .8), l('M7.8 2V16', 'k', .6), l('M11.6 2V16', 'k', .42), l('M16.2 2V16', 'k', .28), a(2, 15.6)],
    fibFan: [f('M2 16L16 2V7Z', .16), l('M16 2V16', 'g'), l('M2 16L16 11.4', 'k', .36), l('M2 16L16 7', 'k', .62), l('M2 16L16 2', 'k', 1), a(2, 16), a(16, 2)],
    xabcd: [f('M1.8 14.6L5.6 3L9 10Z', .2), f('M9 10L12.6 4.2L16.2 15.2Z', .2), l('M1.8 14.6L9 10L16.2 15.2', 'g'), l('M1.8 14.6L5.6 3L9 10L12.6 4.2L16.2 15.2'), a(1.8, 14.6), a(5.6, 3, 0), a(9, 10, 0), a(12.6, 4.2, 0), a(16.2, 15.2)],
    abcd: [l('M2 15.2L11 10.2M6.8 3L16 2', 'g'), l('M2 15.2L6.8 3L11 10.2L16 2'), a(2, 15.2), a(6.8, 3, 0), a(11, 10.2, 0), a(16, 2)],
    headShoulders: [f('M6.8 11.6L9 2.6L11.2 11.6Z', .24), l('M1.4 11.6H16.6', 'k', .55, 1.6), l('M1.4 15.6L4.4 8L6.8 11.6L9 2.6L11.2 11.6L13.6 8L16.6 15.6'), a(1.4, 15.6), a(9, 2.6, 0), a(16.6, 15.6)],
    elliottImpulse: [l('M1.6 16L4.8 9.6L7.2 12.6L11.6 2.6L13.6 6.6L16.4 1.8'), a(1.6, 16), a(4.8, 9.6, 0), a(7.2, 12.6, 0), a(11.6, 2.6, 0), a(13.6, 6.6, 0), a(16.4, 1.8)],
    elliottCorrection: [l('M1.6 2.4L7.2 13L10.8 7.6L16.4 15.8'), a(1.6, 2.4), a(7.2, 13, 0), a(10.8, 7.6, 0), a(16.4, 15.8)],
    position: [R(2, 2, 14, 6.6, 2, .55, 'up'), R(2, 10.6, 14, 5.4, 2, .55, 'dn'), R(4.2, 4.5, 5, 1.6, .8, 1, 'w'), l('M2 9.6H16', 'm', 1, 1.5)],
    ptMeasure: [grp('rotate(-45 9 9)', [R(-.6, 6, 19.2, 6, 1.8, .88, null, 1), R(2, 6.6, 1.2, 2.6, .6, 1, 'w'), R(5.5, 6.6, 1.2, 3.6, .6, 1, 'w'), R(9, 6.6, 1.2, 2.6, .6, 1, 'w'), R(12.5, 6.6, 1.2, 3.6, .6, 1, 'w'), R(16, 6.6, 1.2, 2.6, .6, 1, 'w')])],
    priceRange: [f('M2 2.6H16V15.4H2Z', .16), l('M2 2.6H16M2 15.4H16'), l('M9 7V11', 'm', 1, 1.8), s('M9 4.8L11.6 7.8H6.4Z', 1), s('M9 13.2L11.6 10.2H6.4Z', 1)],
    dateRange: [f('M2.6 2H15.4V16H2.6Z', .16), l('M2.6 2V16M15.4 2V16'), l('M7 9H11', 'm', 1, 1.8), s('M4.8 9L7.8 6.4V11.6Z', 1), s('M13.2 9L10.2 6.4V11.6Z', 1)],
    datePriceRange: [f('M2 2H16V16H2Z', .16), l('M2 2H16V16H2Z', 's'), l('M5 13L11 7'), s('M14 4L12.6 9.1L8.9 5.4Z', 1), a(5, 13, 0)],
    rect: [f('M2.4 4H15.6V14H2.4Z', .22), l('M2.4 4H15.6V14H2.4Z'), a(2.4, 4), a(15.6, 14)],
    ellipse: [f(E, .22), l(E), a(1.6, 9), a(16.4, 9)],
    triangle: [f('M9 2.6L16 15H2Z', .22), l('M9 2.6L16 15H2Z'), a(9, 2.6), a(16, 15), a(2, 15)],
    curve: [l('M2 15L9 2.4L16 12.6', 'g', .3, 1.4), l('M2 15Q9 2.4 16 12.6'), a(2, 15), a(16, 12.6), a(9, 2.4, 0)],
    note: [R(2.4, 2.4, 13.2, 13.2, 3, .14), l('M4.6 4.8H13.4'), l('M9 4.8V13.4'), l('M6.8 13.4H11.2', 's', .55, 1.8)],
    callout: [s(BUB, .9, null, 1), R(5, 5.4, 8, 1.7, .85, 1, 'w'), R(5, 8.4, 5, 1.7, .85, .7, 'w')],
    priceLabel: [s('M1.4 9L5.4 4.4H14.4A2.2 2.2 0 0 1 16.6 6.6V11.4A2.2 2.2 0 0 1 14.4 13.6H5.4Z', .9, null, 1), R(7.4, 8.15, 6.8, 1.7, .85, 1, 'w'), O(4.8, 9, 1.15, 1, 'w')],
    flag: [l('M3.6 2V16.4', 'm', 1, 2), s('M4.8 2.6H15.4L12.8 6.4L15.4 10.2H4.8Z', .9, null, 1)],
    markerUp: [s('M9 1.8L15.6 8.8H11.6V16.2H6.4V8.8H2.4Z', 1, 'up', 1)],
    markerDown: [s('M9 16.2L15.6 9.2H11.6V1.8H6.4V9.2H2.4Z', 1, 'dn', 1)],
    avwap: [R(5.2, 8.8, 2.4, 6, 1.2, .3), R(9.2, 4.6, 2.4, 6.4, 1.2, .3), R(13.2, 2.4, 2.4, 5.2, 1.2, .3), l('M2.4 2V16', 'g'), l('M2.4 13.4C7.6 13.4 8.8 6.6 16 5.6', 'k'), a(2.4, 13.4)],
    fvp: [l('M1.6 1.6V16.4M16.4 1.6V16.4', 'g', .32, 1.6), ...hist(3.6)],
    anchoredVolumeProfile: [l('M2.4 1.8V13.6', 's'), ...hist(4.4).map(o => (o.w ?? 0) > 10 ? Object.assign({}, o, { w: 12 }) : o), a(2.4, 15.6)],
    // 补：临时测量（⇧ 拖）——三角尺，和「预测与测量」组里的直尺分开
    measure: [s('M2.4 1.8L16.2 15.6H2.4ZM5 8.4V12.8H9.4Z', .9, null, 1)],
    magnet: [s('M2.6 2.6H7.4V10A1.6 1.6 0 0 0 10.6 10V2.6H15.4V10A6.4 6.4 0 0 1 2.6 10Z', .55, null, 1), R(2.6, 2.6, 4.8, 3.4, 1, 1), R(10.6, 2.6, 4.8, 3.4, 1, 1)],
    lock: [l('M5.8 8.2V5.6A3.2 3.2 0 0 1 12.2 5.6V8.2', 'm', .6), R(3, 7.8, 12, 8.8, 2.4, 1), R(8.15, 10.6, 1.7, 3.6, .85, 1, 'w')],
    eye,
    trash: [s('M4.2 6.2H13.8L12.9 16.2H5.1Z', .9, null, 1), l('M2.4 4.2H15.6', 'm', 1, 2), l('M6.8 4V2.6H11.2V4', 'm', 1, 1.6), R(6.9, 8.4, 1.5, 5.4, .75, .85, 'w'), R(9.6, 8.4, 1.5, 5.4, .75, .85, 'w')],
    // 界面
    u_search: [f(cp(7.8, 7.8, 5.4), .22), l(cp(7.8, 7.8, 5.4)), l('M12 12L16 16', 'm', 1, 3)],
    u_bell: bell,
    u_ind: [R(1.6, 1.8, 14.8, 14.4, 3, .28), l('M4.4 12.2L7.4 8.6L10 10.8L13.6 6'), a(13.6, 6, 0)],
    u_cmp: [l('M2 11L6 13.2L10 8.8L16 10.8', 'm', .42), l('M2 14.6L6 9.6L10 12L15.4 5'), a(15.4, 5, 1)],
    u_note: [R(1.6, 1.4, 11.4, 15.2, 2.6, .3), R(4.2, 4.8, 6.2, 1.8, .9, .85), R(4.2, 8.4, 4.2, 1.8, .9, .6), l('M16 7.4L10.8 12.6', 'm', 1, 3.2), s('M9.3 14.1L8.4 16L10.3 15.1Z', 1)],
    u_heat: heat,
    u_layout: [R(1.6, 2.4, 6.8, 13.2, 2, .9), R(9.6, 2.4, 6.8, 6.2, 2, .5), R(9.6, 9.8, 6.8, 5.8, 2, .3)],
    u_camera: [s('M6.6 3.4h4.8a1 1 0 0 1 .85.47L13 5.4h1.6a2 2 0 0 1 2 2v6.6a2 2 0 0 1-2 2H3.4a2 2 0 0 1-2-2V7.4a2 2 0 0 1 2-2H5l.75-1.53a1 1 0 0 1 .85-.47Z', .9, null, 1), O(9, 10.4, 3.5, 1, 'w'), O(9, 10.4, 1.9, 1)],
    u_full: [R(5.6, 5.6, 6.8, 6.8, 1.6, .3), l('M2 6.4V3.6A1.6 1.6 0 0 1 3.6 2H6.4M11.6 2H14.4A1.6 1.6 0 0 1 16 3.6V6.4M16 11.6V14.4A1.6 1.6 0 0 1 14.4 16H11.6M6.4 16H3.6A1.6 1.6 0 0 1 2 14.4V11.6')],
    u_undo: undo,
    u_redo: [grp('matrix(-1 0 0 1 18 0)', undo)],
    u_set: [s(gear(), .9, null, 1), O(9, 9, 1.3, 1)],
    u_eyeOff: [cut('M2.6 2L16.2 15.8', 4.6, eye.map(o => Object.assign({}, o, { o: (o.o ?? 1) * .5 }))), l('M2.8 2.2L15.8 15.6')],
    u_star: [s(ST, 1, null, 1), s(star(9, 9.7, 3.6, 1.7), .35, 'w')],
    u_list: [R(1.6, 1.8, 14.8, 14.4, 3, .28), s(star(5.4, 6.2, 2.6, 1.2), 1), R(8.4, 5.3, 5.8, 1.8, .9, .9), O(5.4, 9.6, 1.1, .7), R(8.4, 8.7, 5.8, 1.8, .9, .65), O(5.4, 13, 1.1, .5), R(8.4, 12.1, 4.2, 1.8, .9, .45)],
    u_trades: [O(6.6, 11, 4.8, .9, 'up'), O(13.2, 5.6, 3.4, .9, 'dn'), O(14.4, 13.8, 1.9, .45), R(4.6, 10.2, 4, 1.6, .8, 1, 'w')],
    u_info: [O(9, 9, 7.4, .26), R(8.05, 7.8, 1.9, 6, .95, 1), O(9, 5.2, 1.25, 1)],
    u_sun: [O(9, 9, 3.7, 1), l('M9 1.6V3.2M9 14.8V16.4M1.6 9H3.2M14.8 9H16.4M3.8 3.8L4.9 4.9M13.1 13.1L14.2 14.2M3.8 14.2L4.9 13.1M13.1 4.9L14.2 3.8', 'm', .6, 1.8)],
    u_moon: [s('M10.2 2.2A6.9 6.9 0 1 0 15.8 11.9A5.4 5.4 0 0 1 10.2 2.2Z', .9, null, 1), O(11.6, 6.2, .9, .5)],
    // 补：分享（托盘次要 + 上箭头主体）、建提醒（铃挖掉右上一角放加号）、改文字（铅笔）、未加自选 / 未钉住（空心星）
    u_share: [l('M3.4 9.8V13.8A2.2 2.2 0 0 0 5.6 16H12.4A2.2 2.2 0 0 0 14.6 13.8V9.8', 'm', .55), l('M9 11.4V5'), s('M9 1.6L12.8 5.8H5.2Z', 1)],
    u_bellPlus: [cut('M14.2 4.2h.01', 7.6, bell), l('M14.2 1.8V6.6M11.8 4.2H16.6', 'm', 1, 2)],
    u_pencil: [s('M12.4 2.4a1.7 1.7 0 0 1 2.4 0l.8.8a1.7 1.7 0 0 1 0 2.4L6.4 14.8L2.2 15.8L3.2 11.6Z', .9, null, 1), l('M10.6 4.2L13.8 7.4', 'm', 1, 1.3, 'w')],
    u_starOff: [f(ST, .22), l(ST, 's', .55, 1.4)],
    u_starLine: [l(ST, 'm', 1, 1.6)],
  }
  return g
})()

/* 单色相下的取舍：涨跌方向不再上色（跌那一半退到 .55），关键点改用强调墨，每个图标最多一处 */
G.cursor[1].c = 'a'          // 光标中心点
G.position[3].c = 'a'        // 开仓价那根线
G.fvp[3].c = 'a'             // 成交量分布的最大量那一档（POC）
G.markerUp[0].c = G.markerDown[0].c = null // 上下箭头标记：整只主体色
// 主力订单流：两根横带在竖条两侧留缝，叠在一起也分得清层次
G.u_flow = [{ t: 'cut', d: 'M6 .5V17.5M12 3.5V16.5', w: 4.2, ops: [{ t: 'r', x: 1, y: 4, w: 16, h: 3, rx: 1.5, o: .3 }, { t: 'r', x: 1, y: 11, w: 16, h: 3, rx: 1.5, o: .55 }] },
  { t: 'r', x: 5, y: 2, w: 2, h: 14, rx: 1, o: 1 }, { t: 'r', x: 11, y: 5, w: 2, h: 10, rx: 1, o: .55 }]

/* 多图布局记号：cols × rows 个圆角格，第一格主体 .9、其余 .4（和 u_layout 同一画法；三图就是 u_layout） */
const qGrid = (cols: number, rows: number): Op[] => {
  const g = cols > 3 || rows > 3 ? .9 : 1.2, x0 = 1.6, y0 = 2.4, W = 14.8, H = 13.2
  const w = (W - g * (cols - 1)) / cols, h = (H - g * (rows - 1)) / rows, rx = +Math.min(2, w / 3, h / 3).toFixed(2)
  const out: Op[] = []
  for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++)
    out.push({ t: 'r', x: +(x0 + i * (w + g)).toFixed(2), y: +(y0 + j * (h + g)).toFixed(2), w: +w.toFixed(2), h: +h.toFixed(2), rx, o: i || j ? .4 : .9 })
  return out
}
Object.assign(G, {
  layout1: [{ t: 'f', d: 'M4.9 3.2H13.1A2.5 2.5 0 0 1 15.6 5.7V12.3A2.5 2.5 0 0 1 13.1 14.8H4.9A2.5 2.5 0 0 1 2.4 12.3V5.7A2.5 2.5 0 0 1 4.9 3.2Z', o: .22 }, { t: 'l', d: 'M4.9 3.2H13.1A2.5 2.5 0 0 1 15.6 5.7V12.3A2.5 2.5 0 0 1 13.1 14.8H4.9A2.5 2.5 0 0 1 2.4 12.3V5.7A2.5 2.5 0 0 1 4.9 3.2Z', r: 'm', w: 1.8 }], layout2: qGrid(2, 1), layout2v: qGrid(1, 2), layout3: G.u_layout, layout4: qGrid(2, 2),
  layout6: qGrid(3, 2), layout8: qGrid(4, 2), layout9: qGrid(3, 3), layout12: qGrid(4, 3), layout16: qGrid(4, 4),
})

/* 补（2026-10-09 质感收尾）：原先 ui/icons.ts 里 24 格实心双调（衬底 30%）的杂项小记号整套改画成 18 格分层字形，
 * 同一套几何语言——主体 1、次要 .55、面 .22–.3，挖空走 --qw；电脑网页除品牌记号外不再有双调老图标。 */
{
  const O = (cx: number, cy: number, r: number, o = 1, c?: string): Op => ({ t: 'o', cx, cy, r, o, c })
  const R = (x: number, y: number, w: number, h: number, rx: number, o = 1, c?: string): Op => ({ t: 'r', x, y, w, h, rx, o, c })
  const l = (d: string, r = 'm', o?: number, w?: number): Op => ({ t: 'l', d, r, o, w })
  const s = (d: string, o = 1, c?: string): Op => ({ t: 's', d, o, c })
  const f = (d: string, o = .22): Op => ({ t: 'f', d, o })
  const back = (x: number): string => `M${x + 7} 4.2v9.6a.8.8 0 0 1-1.3.62L${x + .5} 9.62a.8.8 0 0 1 0-1.24l5.2-4.8A.8.8 0 0 1 ${x + 7} 4.2Z`
  Object.assign(G, {
    u_chevD: [l('M5 7.2L9 11.2L13 7.2')],
    u_plus: [l('M9 3.4V14.6M3.4 9H14.6')],
    u_close: [l('M4.6 4.6L13.4 13.4M13.4 4.6L4.6 13.4')],
    u_check: [l('M3.4 9.6L7.2 13.2L14.6 4.8')],
    u_more: [O(3.6, 9, 1.65), O(9, 9, 1.65), O(14.4, 9, 1.65)],
    u_drag: [O(6.6, 4, 1.35), O(11.4, 4, 1.35), O(6.6, 9, 1.35), O(11.4, 9, 1.35), O(6.6, 14, 1.35), O(11.4, 14, 1.35)],
    u_play: [s('M5.2 3.3v11.4a.9.9 0 0 0 1.38.76l8.7-5.7a.9.9 0 0 0 0-1.52l-8.7-5.7A.9.9 0 0 0 5.2 3.3Z', .9)],
    u_pause: [R(4, 3, 3.8, 12, 1.5, .9), R(10.2, 3, 3.8, 12, 1.5, .9)],
    u_toStart: [R(2.6, 3.4, 2.6, 11.2, 1.3), s(back(7.4), .9)],
    u_replay: [s(back(.8), .9), s(back(8.6), .55)],
    u_refresh: [f('M9 3.6a5.4 5.4 0 1 0 0 10.8a5.4 5.4 0 1 0 0-10.8Z', .14), l('M15.2 9.8A6.2 6.2 0 1 1 13.2 4.4'), s('M15.9 2.2L15.7 7.1L10.9 6.3Z', 1)],
    u_download: [l('M3 11.2V13.6A2.2 2.2 0 0 0 5.2 15.8H12.8A2.2 2.2 0 0 0 15 13.6V11.2', 'm', .55), l('M9 2.2V9'), s('M9 12.6L12.8 8.4H5.2Z')],
    u_user: [O(9, 5.6, 3.4, .9), s('M2.4 15.2C2.4 12 5.4 10.4 9 10.4S15.6 12 15.6 15.2a1 1 0 0 1-1 1H3.4a1 1 0 0 1-1-1Z', .45)],
    u_key: [s('M9 7.9H15.4a1.1 1.1 0 0 1 1.1 1.1V12.4a1.1 1.1 0 0 1-2.2 0V10.1H9Z', .55), O(5.6, 9, 4.2, .9), O(5.6, 9, 1.5, 1, 'w')],
    u_device: [R(1.4, 3, 11.8, 8.8, 2, .3), R(4.2, 13.2, 6.2, 1.8, .9, .3), R(10.6, 5, 6.8, 11.8, 2.2, 1, 'w'), R(11.3, 5.7, 5.4, 10.4, 1.6, .9), R(13.1, 13.6, 1.8, 1, .5, 1, 'w')],
    u_palette: [s('M9 2.2a6.8 6.8 0 0 0 0 13.6c.9 0 1.35-.7 1.05-1.45-.4-.9.2-1.95 1.2-1.95H12.8a3 3 0 0 0 3-3C15.8 5.4 12.8 2.2 9 2.2Z', .3), O(5.4, 8.6, 1.35), O(7.6, 5.2, 1.35), O(11.4, 5.4, 1.35, 1, 'a')],
    u_link: [l('M7.8 10.2a2.7 2.7 0 0 0 3.8 0l2.5-2.5a2.7 2.7 0 0 0-3.8-3.8l-.8.8'), l('M10.2 7.8a2.7 2.7 0 0 0-3.8 0L3.9 10.3a2.7 2.7 0 0 0 3.8 3.8l.8-.8', 's')],
    u_logout: [R(1.8, 2.4, 8, 13.2, 2.2, .3), l('M6.6 9H13.4'), s('M16.4 9L12.6 5.4V12.6Z')],
    u_spec: [R(1.8, 1.8, 6.2, 6.2, 1.9, .9), O(13, 4.9, 3.1, .55), s('M4.9 10.2L8 15.8H1.8Z', .55), R(10, 10, 6.2, 6.2, 3.1, .9)],
    u_wifiOff: [{ t: 'cut', d: 'M3 3L15 15', w: 4.4, ops: [l('M1.8 7.4a10.2 10.2 0 0 1 14.4 0M4.6 10.4a6.2 6.2 0 0 1 8.8 0', 's'), O(9, 14.2, 1.6)] }, l('M3 3L15 15')],
    u_candles: [R(4.4, 1.8, 1.3, 13.6, .65), R(2.9, 4.6, 4.3, 7.6, 1.3), s('M11.75 4.2h1.3v2.4h.65a1.3 1.3 0 0 1 1.3 1.3v4.2a1.3 1.3 0 0 1-1.3 1.3h-.65v2.4h-1.3v-2.4h-.65a1.3 1.3 0 0 1-1.3-1.3V7.9a1.3 1.3 0 0 1 1.3-1.3h.65Z', .55)],
    // 大单列表抽屉的「拉高 / 收回」：两道折线，靠近要去的方向那道是主体
    u_grow: [l('M4.6 8.2L9 3.8L13.4 8.2'), l('M4.6 14L9 9.6L13.4 14', 's')],
    u_shrink: [l('M4.6 4L9 8.4L13.4 4', 's'), l('M4.6 9.8L9 14.2L13.4 9.8')],
    u_layers: [s('M9 2.3l6.3 3.3a.6.6 0 0 1 0 1.06L9 9.9 2.7 6.66a.6.6 0 0 1 0-1.06Z', .9), s('M3.6 9.2L9 12l5.4-2.8.9.46a.6.6 0 0 1 0 1.06L9 13.95 2.7 10.72a.6.6 0 0 1 0-1.06Z', .55)],
  })
}

const QO: Record<string, number> = { m: 1, k: 1, s: .55, g: .28, x: .3 }
const hasKey = (ops: Op[]): boolean => ops.some(o => (o.t === 'a' && o.s) || (o.ops && hasKey(o.ops)))
let MID = 0
const C1 = 'var(--q1,currentColor)', CA = 'var(--qa,currentColor)', CW = 'var(--qw,var(--surface))'

export function rQ(ops: Op[], big?: boolean): string {
  if (big == null) big = hasKey(ops)
  const col = (c?: string | null): string => c === 'w' ? CW : c === 'a' ? CA : C1
  const op = (o: Op, def: number): number => +((o.o ?? def) * (o.c === 'dn' ? .55 : 1)).toFixed(3)
  return ops.map(o => {
    switch (o.t) {
      case 'l': return `<path d="${o.d}" fill="none" stroke="${col(o.c)}" stroke-width="${o.w ?? 2.2}" stroke-linecap="round" stroke-linejoin="round" opacity="${op(o, QO[o.r as string])}"/>`
      // 锚点：端点（大）用强调墨；中间点（小）用主体色——没有端点的图标，它的小点就是那一处强调
      case 'a': return `<circle cx="${o.x}" cy="${o.y}" r="${o.s ? 2.3 : 1.8}" fill="${o.s || !big ? CA : C1}" stroke="${CW}" stroke-width="1"/>`
      case 'f': return `<path d="${o.d}" fill="${col(o.c)}" opacity="${op(o, .22)}"/>`
      case 's': return `<path d="${o.d}" fill="${col(o.c)}" fill-rule="evenodd" stroke="${col(o.c)}" stroke-width=".9" stroke-linejoin="round" opacity="${op(o, 1)}"/>`
      case 'r': return `<rect x="${o.x}" y="${o.y}" width="${o.w}" height="${o.h}" rx="${o.rx}" fill="${col(o.c)}" opacity="${op(o, 1)}"/>`
      case 'o': return `<circle cx="${o.cx}" cy="${o.cy}" r="${o.r}" fill="${col(o.c)}" opacity="${op(o, 1)}"/>`
      case 'g': return `<g transform="${o.tr}">${rQ(o.ops!, big)}</g>`
      case 'cut': { const id = 'qm' + (++MID); return `<mask id="${id}" maskUnits="userSpaceOnUse" x="-2" y="-2" width="22" height="22"><rect x="-2" y="-2" width="22" height="22" fill="#fff"/><path d="${o.d}" stroke="#000" stroke-width="${o.w}" stroke-linecap="round"/></mask><g mask="url(#${id})">${rQ(o.ops!, big)}</g>` }
    }
    return ''
  }).join('')
}

/** 界面名 → 质感字形（画线种类直接按种类名取，见 toolGlyph；「note」在界面上是笔记 / 记一笔，画线里是文字注释，所以分两条路） */
export const UI_Q: Record<string, string> = {
  search: 'u_search', bell: 'u_bell', bellPlus: 'u_bellPlus', indicators: 'u_ind', compare: 'u_cmp', note: 'u_note',
  heat: 'u_heat', flow: 'u_flow', layout: 'u_layout', camera: 'u_camera', fullscreen: 'u_full', undo: 'u_undo', redo: 'u_redo',
  gear: 'u_set', eye: 'eye', eyeOff: 'u_eyeOff', star: 'u_star', starOff: 'u_starOff', starLine: 'u_starLine', list: 'u_list',
  trades: 'u_trades', info: 'u_info', sun: 'u_sun', moon: 'u_moon', share: 'u_share', pencil: 'u_pencil',
  cursor: 'cursor', magnet: 'magnet', lock: 'lock', trash: 'trash', measure: 'measure',
  chevronDown: 'u_chevD', plus: 'u_plus', close: 'u_close', check: 'u_check', more: 'u_more', drag: 'u_drag', play: 'u_play',
  pause: 'u_pause', toStart: 'u_toStart', replay: 'u_replay', refresh: 'u_refresh', download: 'u_download', user: 'u_user',
  key: 'u_key', device: 'u_device', palette: 'u_palette', link: 'u_link', logout: 'u_logout', spec: 'u_spec', wifiOff: 'u_wifiOff',
  candles: 'u_candles', layers: 'u_layers', grow: 'u_grow', shrink: 'u_shrink',
}

/** 质感字形的 svg（18 格）；cls 照旧决定尺寸 */
export const qsvg = (key: string, cls: string): string =>
  `<svg class="${cls} q${key === 'trash' ? ' q-del' : ''}" viewBox="0 0 18 18" aria-hidden="true">${rQ(G[key])}</svg>`
