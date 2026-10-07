/* Hkline Web · 图标
 *
 * 画法：24 格，实心圆润双调——主体用 currentColor 实填，衬底同色 30% 透明；
 * 凡是描边一律 2.2（24 格里的分量，缩到 16 格约 1.5 px），只有品牌记号 2.4。
 * 不用单色细线线框（那是后台风）。只有画线工具例外：那些工具画出来的东西本来就是线，
 * 所以记号里的「线」保留线形，但端点、锚点用实心圆点，和其余图标同一个分量。
 */

const D = 'opacity=".3"'
/** 多图布局记号：cols × rows 个圆角格，第一格实填、其余衬底（和四图、八图同一画法） */
function gridIcon(cols: number, rows: number): string {
  const g = cols > 3 || rows > 3 ? 0.9 : 1, x0 = 2, y0 = 3, W = 20, H = 18
  const w = (W - g * (cols - 1)) / cols, h = (H - g * (rows - 1)) / rows, r = Math.min(1.5, w / 3, h / 3)
  let out = ''
  for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++) {
    const x = +(x0 + i * (w + g)).toFixed(2), y = +(y0 + j * (h + g)).toFixed(2)
    out += `<rect x="${x}" y="${y}" width="${+w.toFixed(2)}" height="${+h.toFixed(2)}" rx="${+r.toFixed(2)}" fill="currentColor"${i || j ? ' ' + D : ''}/>`
  }
  return out
}
const P: Record<string, string> = {
  logo: `<rect x="2" y="2" width="20" height="20" rx="6" fill="var(--accent)"/><path d="M7 16.5V9.2M12 15V6.5M17 13.5v-5" stroke="#fff" stroke-width="2.4" stroke-linecap="round"/><path d="M7 7.2v1M12 16.9v.8M17 15.6v.8M17 6.4v.8" stroke="#fff" stroke-width="2.4" stroke-linecap="round" opacity=".55"/>`,
  search: `<circle cx="10.5" cy="10.5" r="6.5" fill="currentColor" ${D}/><path d="M10.5 3a7.5 7.5 0 1 0 4.55 13.46l4.24 4.25a1.25 1.25 0 0 0 1.77-1.77l-4.25-4.24A7.5 7.5 0 0 0 10.5 3Zm0 2.5a5 5 0 1 1 0 10 5 5 0 0 1 0-10Z" fill="currentColor"/>`,
  bell: `<path d="M12 3a6 6 0 0 0-6 6v3.6L4.3 15.4A1 1 0 0 0 5.2 17h13.6a1 1 0 0 0 .9-1.6L18 12.6V9a6 6 0 0 0-6-6Z" fill="currentColor"/><path d="M9.5 18.5a2.5 2.5 0 0 0 5 0" fill="currentColor" ${D}/>`,
  bellPlus: `<path d="M11 3.1A6 6 0 0 0 6 9v3.6L4.3 15.4A1 1 0 0 0 5.2 17h13.6a1 1 0 0 0 .9-1.6L18 12.6v-.9A5 5 0 0 1 11 3.1Z" fill="currentColor"/><path d="M9.5 18.5a2.5 2.5 0 0 0 5 0" fill="currentColor" ${D}/><path d="M17 2.5a1 1 0 0 1 1 1V5h1.5a1 1 0 1 1 0 2H18v1.5a1 1 0 1 1-2 0V7h-1.5a1 1 0 1 1 0-2H16V3.5a1 1 0 0 1 1-1Z" fill="currentColor"/>`,
  sun: `<circle cx="12" cy="12" r="7.5" fill="currentColor" ${D}/><circle cx="12" cy="12" r="4.5" fill="currentColor"/>`,
  moon: `<circle cx="12" cy="12" r="8.5" fill="currentColor" ${D}/><path d="M13.5 4.2a7.5 7.5 0 1 0 6.3 10.9A6 6 0 0 1 13.5 4.2Z" fill="currentColor"/>`,
  chevronDown: `<path d="M7.3 9.3a1 1 0 0 1 1.4 0L12 12.6l3.3-3.3a1 1 0 1 1 1.4 1.4l-4 4a1 1 0 0 1-1.4 0l-4-4a1 1 0 0 1 0-1.4Z" fill="currentColor"/>`,
  candles: `<rect x="4" y="6" width="5" height="10" rx="1.5" fill="currentColor"/><rect x="15" y="9" width="5" height="8" rx="1.5" fill="currentColor" ${D}/><rect x="5.75" y="3" width="1.5" height="17" rx=".75" fill="currentColor"/><rect x="16.75" y="5" width="1.5" height="15" rx=".75" fill="currentColor" ${D}/>`,
  indicators: `<rect x="3" y="3" width="18" height="18" rx="5" fill="currentColor" ${D}/><path d="M6.5 15.5l3.2-4 3 2.5 4.8-6" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>`,
  // 对比：两条走势叠在一起（主线实、对比线衬底色），端点实心圆点
  compare: `<path d="M3.5 17.5l5-5.5 4 3 7.5-8" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M3.5 9.5l5 4 4-5 7.5 5" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round" ${D}/><circle cx="20" cy="7" r="2.2" fill="currentColor"/>`,
  layout: `<rect x="3" y="3" width="8" height="18" rx="2.5" fill="currentColor"/><rect x="13" y="3" width="8" height="8" rx="2.5" fill="currentColor" ${D}/><rect x="13" y="13" width="8" height="8" rx="2.5" fill="currentColor" ${D}/>`,
  layout1: `<rect x="3" y="4" width="18" height="16" rx="3" fill="currentColor"/>`,
  layout2: `<rect x="3" y="4" width="8.5" height="16" rx="2.5" fill="currentColor"/><rect x="12.5" y="4" width="8.5" height="16" rx="2.5" fill="currentColor" ${D}/>`,
  layout2v: `<rect x="3" y="3.5" width="18" height="8" rx="2.5" fill="currentColor"/><rect x="3" y="12.5" width="18" height="8" rx="2.5" fill="currentColor" ${D}/>`,
  layout6: `<rect x="2.5" y="3.5" width="5.6" height="8" rx="1.8" fill="currentColor"/><rect x="9.2" y="3.5" width="5.6" height="8" rx="1.8" fill="currentColor" ${D}/><rect x="15.9" y="3.5" width="5.6" height="8" rx="1.8" fill="currentColor" ${D}/><rect x="2.5" y="12.5" width="5.6" height="8" rx="1.8" fill="currentColor" ${D}/><rect x="9.2" y="12.5" width="5.6" height="8" rx="1.8" fill="currentColor" ${D}/><rect x="15.9" y="12.5" width="5.6" height="8" rx="1.8" fill="currentColor" ${D}/>`,
  layout8: `<rect x="2" y="3.5" width="4.2" height="8" rx="1.5" fill="currentColor"/><rect x="7.1" y="3.5" width="4.2" height="8" rx="1.5" fill="currentColor" ${D}/><rect x="12.2" y="3.5" width="4.2" height="8" rx="1.5" fill="currentColor" ${D}/><rect x="17.3" y="3.5" width="4.2" height="8" rx="1.5" fill="currentColor" ${D}/><rect x="2" y="12.5" width="4.2" height="8" rx="1.5" fill="currentColor" ${D}/><rect x="7.1" y="12.5" width="4.2" height="8" rx="1.5" fill="currentColor" ${D}/><rect x="12.2" y="12.5" width="4.2" height="8" rx="1.5" fill="currentColor" ${D}/><rect x="17.3" y="12.5" width="4.2" height="8" rx="1.5" fill="currentColor" ${D}/>`,
  layout3: `<rect x="3" y="4" width="8.5" height="16" rx="2.5" fill="currentColor"/><rect x="12.5" y="4" width="8.5" height="7.5" rx="2.5" fill="currentColor" ${D}/><rect x="12.5" y="12.5" width="8.5" height="7.5" rx="2.5" fill="currentColor" ${D}/>`,
  layout9: gridIcon(3, 3),
  layout12: gridIcon(4, 3),
  layout16: gridIcon(4, 4),
  layout4: `<rect x="3" y="3.5" width="8.5" height="8" rx="2.5" fill="currentColor"/><rect x="12.5" y="3.5" width="8.5" height="8" rx="2.5" fill="currentColor" ${D}/><rect x="3" y="12.5" width="8.5" height="8" rx="2.5" fill="currentColor" ${D}/><rect x="12.5" y="12.5" width="8.5" height="8" rx="2.5" fill="currentColor" ${D}/>`,
  note: `<path d="M6 3h11a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1Z" fill="currentColor" ${D}/><path d="M6 3h3v18H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1Zm5.5 5h4.5a1 1 0 1 1 0 2h-4.5a1 1 0 1 1 0-2Zm0 4h3a1 1 0 1 1 0 2h-3a1 1 0 1 1 0-2Z" fill="currentColor"/>`,
  share: `<circle cx="17.5" cy="5.5" r="3" fill="currentColor"/><circle cx="6.5" cy="12" r="3" fill="currentColor"/><circle cx="17.5" cy="18.5" r="3" fill="currentColor"/><path d="M8.2 11l7.6-4.4M8.2 13l7.6 4.4" stroke="currentColor" stroke-width="2.2" ${D}/>`,
  camera: `<path d="M4 7.5A2.5 2.5 0 0 1 6.5 5h1.2l1.1-1.5A1.5 1.5 0 0 1 10 3h4a1.5 1.5 0 0 1 1.2.5L16.3 5h1.2A2.5 2.5 0 0 1 20 7.5v9A2.5 2.5 0 0 1 17.5 19h-11A2.5 2.5 0 0 1 4 16.5v-9Z" fill="currentColor" ${D}/><circle cx="12" cy="12" r="3.8" fill="currentColor"/>`,
  undo: `<path d="M9.7 4.3a1 1 0 0 1 0 1.4L7.4 8H14a6 6 0 0 1 0 12h-3a1 1 0 1 1 0-2h3a4 4 0 0 0 0-8H7.4l2.3 2.3a1 1 0 1 1-1.4 1.4l-4-4a1 1 0 0 1 0-1.4l4-4a1 1 0 0 1 1.4 0Z" fill="currentColor"/>`,
  redo: `<path d="M14.3 4.3a1 1 0 0 0 0 1.4L16.6 8H10a6 6 0 0 0 0 12h3a1 1 0 1 0 0-2h-3a4 4 0 0 1 0-8h6.6l-2.3 2.3a1 1 0 1 0 1.4 1.4l4-4a1 1 0 0 0 0-1.4l-4-4a1 1 0 0 0-1.4 0Z" fill="currentColor"/>`,
  refresh: `<path d="M12 5a7 7 0 0 1 6.3 4H16a1 1 0 1 0 0 2h4.5a1 1 0 0 0 1-1V5.5a1 1 0 1 0-2 0v1.8A9 9 0 1 0 21 13a1 1 0 1 0-2-.2A7 7 0 1 1 12 5Z" fill="currentColor"/>`,
  fullscreen: `<path d="M4 9V6a2 2 0 0 1 2-2h3M15 4h3a2 2 0 0 1 2 2v3M20 15v3a2 2 0 0 1-2 2h-3M9 20H6a2 2 0 0 1-2-2v-3" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="round"/><rect x="8" y="8" width="8" height="8" rx="2" fill="currentColor" ${D}/>`,
  gear: `<path d="M10.3 2.6a1 1 0 0 1 1-.6h1.4a1 1 0 0 1 1 .6l.6 1.7 1.7.7 1.6-.8a1 1 0 0 1 1.2.2l1 1a1 1 0 0 1 .2 1.2l-.8 1.6.7 1.7 1.7.6a1 1 0 0 1 .6 1v1.4a1 1 0 0 1-.6 1l-1.7.6-.7 1.7.8 1.6a1 1 0 0 1-.2 1.2l-1 1a1 1 0 0 1-1.2.2l-1.6-.8-1.7.7-.6 1.7a1 1 0 0 1-1 .6h-1.4a1 1 0 0 1-1-.6l-.6-1.7-1.7-.7-1.6.8a1 1 0 0 1-1.2-.2l-1-1a1 1 0 0 1-.2-1.2l.8-1.6-.7-1.7-1.7-.6a1 1 0 0 1-.6-1v-1.4a1 1 0 0 1 .6-1l1.7-.6.7-1.7-.8-1.6a1 1 0 0 1 .2-1.2l1-1a1 1 0 0 1 1.2-.2l1.6.8 1.7-.7.6-1.7Z" fill="currentColor" ${D}/><circle cx="12" cy="12" r="3.5" fill="currentColor"/>`,
  star: `<path d="M12 2.8l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 16.8l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9L12 2.8Z" fill="currentColor"/>`,
  starLine: `<path d="M12 3.6l2.4 4.9 5.4.8-3.9 3.8.9 5.4L12 16l-4.8 2.5.9-5.4-3.9-3.8 5.4-.8L12 3.6Z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>`,
  starOff: `<path d="M12 2.8l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 16.8l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9L12 2.8Z" fill="currentColor" opacity=".22"/>`,
  list: `<rect x="3" y="4" width="18" height="16" rx="4" fill="currentColor" ${D}/><path d="M7.2 8.2l.9 1.8 2 .3-1.4 1.4.3 2-1.8-1-1.8 1 .3-2L4.3 10.3l2-.3.9-1.8Z" fill="currentColor"/><rect x="12" y="8.5" width="6" height="2" rx="1" fill="currentColor"/><rect x="12" y="13.5" width="4" height="2" rx="1" fill="currentColor"/>`,
  layers: `<path d="M12 3.2l8.4 4.3a.8.8 0 0 1 0 1.4L12 13.2 3.6 8.9a.8.8 0 0 1 0-1.4L12 3.2Z" fill="currentColor"/><path d="M4.6 12.3L12 16.1l7.4-3.8 1 .5a.8.8 0 0 1 0 1.4L12 18.5l-8.4-4.3a.8.8 0 0 1 0-1.4l1-.5Z" fill="currentColor" ${D}/>`,
  trades: `<rect x="3" y="3" width="18" height="18" rx="5" fill="currentColor" ${D}/><path d="M8 7v10M8 7l-2.2 2.2M8 7l2.2 2.2M16 17V7m0 10l-2.2-2.2M16 17l2.2-2.2" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" fill="none"/>`,
  info: `<circle cx="12" cy="12" r="9" fill="currentColor" ${D}/><rect x="10.8" y="10.5" width="2.4" height="7" rx="1.2" fill="currentColor"/><circle cx="12" cy="7.5" r="1.5" fill="currentColor"/>`,
  plus: `<path d="M12 4.5a1.2 1.2 0 0 1 1.2 1.2v5.1h5.1a1.2 1.2 0 1 1 0 2.4h-5.1v5.1a1.2 1.2 0 1 1-2.4 0v-5.1H5.7a1.2 1.2 0 1 1 0-2.4h5.1V5.7A1.2 1.2 0 0 1 12 4.5Z" fill="currentColor"/>`,
  close: `<path d="M6.3 6.3a1.1 1.1 0 0 1 1.6 0L12 10.4l4.1-4.1a1.1 1.1 0 1 1 1.6 1.6L13.6 12l4.1 4.1a1.1 1.1 0 1 1-1.6 1.6L12 13.6l-4.1 4.1a1.1 1.1 0 1 1-1.6-1.6l4.1-4.1-4.1-4.1a1.1 1.1 0 0 1 0-1.6Z" fill="currentColor"/>`,
  check: `<path d="M19.2 6.3a1.1 1.1 0 0 1 0 1.6l-9 9a1.1 1.1 0 0 1-1.6 0l-4-4a1.1 1.1 0 1 1 1.6-1.6l3.2 3.2 8.2-8.2a1.1 1.1 0 0 1 1.6 0Z" fill="currentColor"/>`,
  eye: `<path d="M12 5C7 5 3.3 8.4 2 12c1.3 3.6 5 7 10 7s8.7-3.4 10-7c-1.3-3.6-5-7-10-7Z" fill="currentColor" ${D}/><circle cx="12" cy="12" r="3.6" fill="currentColor"/>`,
  eyeOff: `<path d="M12 5C7 5 3.3 8.4 2 12c1.3 3.6 5 7 10 7s8.7-3.4 10-7c-1.3-3.6-5-7-10-7Z" fill="currentColor" ${D}/><path d="M4.3 4.3a1 1 0 0 1 1.4 0l14 14a1 1 0 0 1-1.4 1.4l-14-14a1 1 0 0 1 0-1.4Z" fill="currentColor"/>`,
  trash: `<path d="M6 7h12l-.8 12.1A2 2 0 0 1 15.2 21H8.8a2 2 0 0 1-2-1.9L6 7Z" fill="currentColor" ${D}/><path d="M9.5 3.5a1 1 0 0 1 1-1h3a1 1 0 0 1 1 1V5H19a1 1 0 1 1 0 2H5a1 1 0 1 1 0-2h4.5V3.5ZM10 10a1 1 0 0 1 1 1v6a1 1 0 1 1-2 0v-6a1 1 0 0 1 1-1Zm4 0a1 1 0 0 1 1 1v6a1 1 0 1 1-2 0v-6a1 1 0 0 1 1-1Z" fill="currentColor"/>`,
  lock: `<rect x="4.5" y="10" width="15" height="11" rx="3" fill="currentColor"/><path d="M8 10V7.5a4 4 0 0 1 8 0V10" stroke="currentColor" stroke-width="2.2" fill="none" ${D}/>`,
  magnet: `<path d="M5 4h4v8a3 3 0 0 0 6 0V4h4v8a7 7 0 0 1-14 0V4Z" fill="currentColor" ${D}/><rect x="5" y="4" width="4" height="4" rx="1" fill="currentColor"/><rect x="15" y="4" width="4" height="4" rx="1" fill="currentColor"/>`,
  drag: `<circle cx="9" cy="7" r="1.5" fill="currentColor"/><circle cx="15" cy="7" r="1.5" fill="currentColor"/><circle cx="9" cy="12" r="1.5" fill="currentColor"/><circle cx="15" cy="12" r="1.5" fill="currentColor"/><circle cx="9" cy="17" r="1.5" fill="currentColor"/><circle cx="15" cy="17" r="1.5" fill="currentColor"/>`,
  more: `<circle cx="6" cy="12" r="1.8" fill="currentColor"/><circle cx="12" cy="12" r="1.8" fill="currentColor"/><circle cx="18" cy="12" r="1.8" fill="currentColor"/>`,
  play: `<path d="M8 5.2v13.6a1 1 0 0 0 1.5.9l10.6-6.8a1 1 0 0 0 0-1.8L9.5 4.3A1 1 0 0 0 8 5.2Z" fill="currentColor"/>`,
  pause: `<rect x="6.5" y="5" width="4" height="14" rx="1.5" fill="currentColor"/><rect x="13.5" y="5" width="4" height="14" rx="1.5" fill="currentColor"/>`,
  user: `<circle cx="12" cy="8" r="4" fill="currentColor"/><path d="M4 19.5C4 16 7.6 14 12 14s8 2 8 5.5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1Z" fill="currentColor" ${D}/>`,
  key: `<circle cx="8" cy="12" r="5" fill="currentColor"/><path d="M12 11h9v3h-2v2.5h-3V14h-4v-3Z" fill="currentColor" ${D}/><circle cx="8" cy="12" r="1.8" fill="var(--surface)"/>`,
  device: `<rect x="2.5" y="5" width="14" height="10.5" rx="2" fill="currentColor" ${D}/><rect x="15" y="8" width="6.5" height="12" rx="1.8" fill="currentColor"/><rect x="6" y="17.5" width="7" height="2" rx="1" fill="currentColor" ${D}/>`,
  palette: `<path d="M12 3a9 9 0 0 0 0 18c1.2 0 1.8-.9 1.4-1.9-.5-1.2.3-2.6 1.6-2.6H17a4 4 0 0 0 4-4c0-5.3-4-9.5-9-9.5Z" fill="currentColor" ${D}/><circle cx="7.5" cy="11" r="1.6" fill="currentColor"/><circle cx="10" cy="7" r="1.6" fill="currentColor"/><circle cx="15" cy="7.5" r="1.6" fill="currentColor"/>`,
  link: `<path d="M10.6 13.4a3.5 3.5 0 0 0 5 0l3.2-3.2a3.5 3.5 0 0 0-5-5l-1 1" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="round"/><path d="M13.4 10.6a3.5 3.5 0 0 0-5 0l-3.2 3.2a3.5 3.5 0 0 0 5 5l1-1" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="round" ${D}/>`,
  logout: `<path d="M5 4h7v16H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1Z" fill="currentColor" ${D}/><path d="M15.3 7.3a1 1 0 0 1 1.4 0l4 4a1 1 0 0 1 0 1.4l-4 4a1 1 0 1 1-1.4-1.4l2.3-2.3H10a1 1 0 1 1 0-2h7.6l-2.3-2.3a1 1 0 0 1 0-1.4Z" fill="currentColor"/>`,
  spec: `<rect x="3" y="3" width="8" height="8" rx="2.5" fill="currentColor"/><circle cx="17" cy="7" r="4" fill="currentColor" ${D}/><path d="M7 13.5l4 7H3l4-7Z" fill="currentColor" ${D}/><rect x="13" y="13" width="8" height="8" rx="4" fill="currentColor"/>`,
  wifiOff: `<path d="M12 18.5a1.8 1.8 0 1 1 0 3.6 1.8 1.8 0 0 1 0-3.6Z" fill="currentColor"/><path d="M3 9.5a13 13 0 0 1 18 0M6.5 13a8 8 0 0 1 11 0" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="round" ${D}/><path d="M4 4l16 16" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>`,

  // ---- 画线工具（线保留线形，端点实心）
  cursor: `<path d="M12 3v6M12 15v6M3 12h6M15 12h6" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><circle cx="12" cy="12" r="1.8" fill="currentColor"/>`,
  trend: `<path d="M5.5 18.5l13-13" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><circle cx="5.5" cy="18.5" r="2.6" fill="currentColor"/><circle cx="18.5" cy="5.5" r="2.6" fill="currentColor"/>`,
  ray: `<path d="M5.5 18.5L21 3" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><circle cx="5.5" cy="18.5" r="2.6" fill="currentColor"/><circle cx="12" cy="12" r="2.2" fill="currentColor" ${D}/>`,
  hline: `<path d="M3 12h18" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><circle cx="12" cy="12" r="2.6" fill="currentColor"/>`,
  vline: `<path d="M12 3v18" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><circle cx="12" cy="12" r="2.6" fill="currentColor"/>`,
  rect: `<rect x="5" y="6" width="14" height="12" rx="1.5" fill="currentColor" ${D}/><rect x="5" y="6" width="14" height="12" rx="1.5" stroke="currentColor" stroke-width="2.2" fill="none"/><circle cx="5" cy="6" r="2.2" fill="currentColor"/><circle cx="19" cy="18" r="2.2" fill="currentColor"/>`,
  fib: `<path d="M3 5h18M3 9.5h18M3 13.5h18M3 19h18" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" ${D}/><path d="M5 19L19 5" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-dasharray="2 3"/><circle cx="5" cy="19" r="2.4" fill="currentColor"/><circle cx="19" cy="5" r="2.4" fill="currentColor"/>`,
  measure: `<rect x="3" y="7" width="18" height="10" rx="2.5" fill="currentColor" ${D}/><path d="M7 7v4M11 7v3M15 7v4M19 7v3" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>`,
  // 锚定 VWAP：锚点一颗实心点，从它起一条线
  avwap: `<path d="M5 16.5C9 15 12 11 20 9.5" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" fill="none"/><path d="M5 5v14" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" ${D}/><circle cx="5" cy="16.5" r="2.6" fill="currentColor"/>`,
  // 固定区间成交量分布：两条边界竖线夹着横向柱，最长那根是控制点
  fvp: `<path d="M4 4v16M20 4v16" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" ${D}/><rect x="4" y="5.5" width="6" height="2.6" rx="1.3" fill="currentColor" ${D}/><rect x="4" y="9.3" width="10" height="2.6" rx="1.3" fill="currentColor" ${D}/><rect x="4" y="13.1" width="14" height="2.6" rx="1.3" fill="currentColor"/><rect x="4" y="16.9" width="8" height="2.6" rx="1.3" fill="currentColor" ${D}/>`,
  // 多空持仓：上面止盈（实）、下面止损（淡），中间开仓线
  position: `<rect x="4" y="4" width="16" height="8" rx="2" fill="currentColor"/><rect x="4" y="12" width="16" height="7" rx="2" fill="currentColor" ${D}/><path d="M3 12h18" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>`,
  channel: `<path d="M4 15L15 4M9 20L20 9" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><path d="M4 15l5 5 11-11-5-5z" fill="currentColor" ${D}/><circle cx="4" cy="15" r="2.2" fill="currentColor"/><circle cx="15" cy="4" r="2.2" fill="currentColor"/>`,
  // K 线回放：两个往回的三角（后一个淡）；跳到起点：一道竖杠挡着一个往回的三角
  replay: `<path d="M11 6.2v11.6a1 1 0 0 1-1.6.8l-7-5.8a1 1 0 0 1 0-1.6l7-5.8a1 1 0 0 1 1.6.8Z" fill="currentColor"/><path d="M21 6.2v11.6a1 1 0 0 1-1.6.8l-7-5.8a1 1 0 0 1 0-1.6l7-5.8a1 1 0 0 1 1.6.8Z" fill="currentColor" ${D}/>`,
  toStart: `<rect x="4.5" y="5" width="3" height="14" rx="1.5" fill="currentColor"/><path d="M19 6.2v11.6a1 1 0 0 1-1.6.8l-7.4-5.8a1 1 0 0 1 0-1.6l7.4-5.8a1 1 0 0 1 1.6.8Z" fill="currentColor"/>`,
}

export type IconName = keyof typeof P
export const iconNames = Object.keys(P)

export function icon(name: string, cls = 'icon'): string {
  return `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true">${P[name] || ''}</svg>`
}
