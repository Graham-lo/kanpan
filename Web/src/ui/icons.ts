/* Hkline Web · 图标
 *
 * 2026-10-08 起两套并存、一个入口：
 *   · 功能图标一套（ui/qicons.ts，2026-10-10 晚起照 OpenMarket：24 格单一粗细细线、描边 1.5 物理像素、单色）——画线工具全套、
 *     左画线栏、右侧栏、工具条、顶栏以及别处用到同名记号的地方都走它；状态（悬停软底 / 当前工具反相块 / 开关浮起块）与
 *     各处尺寸、描边换算由 styles/icons.css 按所在位置套上，静止不垫块。
 *   · 下面 P 里剩下的是还没有质感版的杂项小记号（关闭、勾、加号、播放……）：24 格，实心圆润双调，
 *     主体 currentColor 实填、衬底同色 30% 透明，描边 2.2。
 * 画线种类名直接取质感字形；「note」在界面上是笔记 / 记一笔，画线里是文字注释——要画线那只就写 'draw:note'（toolIcon）。
 */
import { G, UI_Q, qsvg } from './qicons'

const D = 'opacity=".3"'
const P: Record<string, string> = {
  logo: `<rect x="2" y="2" width="20" height="20" rx="6" fill="var(--accent)"/><path d="M7 16.5V9.2M12 15V6.5M17 13.5v-5" stroke="#fff" stroke-width="2.4" stroke-linecap="round"/><path d="M7 7.2v1M12 16.9v.8M17 15.6v.8M17 6.4v.8" stroke="#fff" stroke-width="2.4" stroke-linecap="round" opacity=".55"/>`,
  chevronDown: `<path d="M7.3 9.3a1 1 0 0 1 1.4 0L12 12.6l3.3-3.3a1 1 0 1 1 1.4 1.4l-4 4a1 1 0 0 1-1.4 0l-4-4a1 1 0 0 1 0-1.4Z" fill="currentColor"/>`,
  candles: `<rect x="4" y="6" width="5" height="10" rx="1.5" fill="currentColor"/><rect x="15" y="9" width="5" height="8" rx="1.5" fill="currentColor" ${D}/><rect x="5.75" y="3" width="1.5" height="17" rx=".75" fill="currentColor"/><rect x="16.75" y="5" width="1.5" height="15" rx=".75" fill="currentColor" ${D}/>`,
  refresh: `<path d="M12 5a7 7 0 0 1 6.3 4H16a1 1 0 1 0 0 2h4.5a1 1 0 0 0 1-1V5.5a1 1 0 1 0-2 0v1.8A9 9 0 1 0 21 13a1 1 0 1 0-2-.2A7 7 0 1 1 12 5Z" fill="currentColor"/>`,
  layers: `<path d="M12 3.2l8.4 4.3a.8.8 0 0 1 0 1.4L12 13.2 3.6 8.9a.8.8 0 0 1 0-1.4L12 3.2Z" fill="currentColor"/><path d="M4.6 12.3L12 16.1l7.4-3.8 1 .5a.8.8 0 0 1 0 1.4L12 18.5l-8.4-4.3a.8.8 0 0 1 0-1.4l1-.5Z" fill="currentColor" ${D}/>`,
  plus: `<path d="M12 4.5a1.2 1.2 0 0 1 1.2 1.2v5.1h5.1a1.2 1.2 0 1 1 0 2.4h-5.1v5.1a1.2 1.2 0 1 1-2.4 0v-5.1H5.7a1.2 1.2 0 1 1 0-2.4h5.1V5.7A1.2 1.2 0 0 1 12 4.5Z" fill="currentColor"/>`,
  close: `<path d="M6.3 6.3a1.1 1.1 0 0 1 1.6 0L12 10.4l4.1-4.1a1.1 1.1 0 1 1 1.6 1.6L13.6 12l4.1 4.1a1.1 1.1 0 1 1-1.6 1.6L12 13.6l-4.1 4.1a1.1 1.1 0 1 1-1.6-1.6l4.1-4.1-4.1-4.1a1.1 1.1 0 0 1 0-1.6Z" fill="currentColor"/>`,
  check: `<path d="M19.2 6.3a1.1 1.1 0 0 1 0 1.6l-9 9a1.1 1.1 0 0 1-1.6 0l-4-4a1.1 1.1 0 1 1 1.6-1.6l3.2 3.2 8.2-8.2a1.1 1.1 0 0 1 1.6 0Z" fill="currentColor"/>`,
  download: `<path d="M12 3.5a1.2 1.2 0 0 1 1.2 1.2v8.4l2.9-2.9a1.2 1.2 0 1 1 1.7 1.7l-4.95 4.95a1.2 1.2 0 0 1-1.7 0L6.2 11.9a1.2 1.2 0 1 1 1.7-1.7l2.9 2.9V4.7A1.2 1.2 0 0 1 12 3.5ZM5 17.3a1.2 1.2 0 0 1 1.2 1.2v.3h11.6v-.3a1.2 1.2 0 1 1 2.4 0v.5a2.2 2.2 0 0 1-2.2 2.2H6a2.2 2.2 0 0 1-2.2-2.2v-.5A1.2 1.2 0 0 1 5 17.3Z" fill="currentColor"/>`,
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

  // K 线回放：两个往回的三角（后一个淡）；跳到起点：一道竖杠挡着一个往回的三角
  replay: `<path d="M11 6.2v11.6a1 1 0 0 1-1.6.8l-7-5.8a1 1 0 0 1 0-1.6l7-5.8a1 1 0 0 1 1.6.8Z" fill="currentColor"/><path d="M21 6.2v11.6a1 1 0 0 1-1.6.8l-7-5.8a1 1 0 0 1 0-1.6l7-5.8a1 1 0 0 1 1.6.8Z" fill="currentColor" ${D}/>`,
  toStart: `<rect x="4.5" y="5" width="3" height="14" rx="1.5" fill="currentColor"/><path d="M19 6.2v11.6a1 1 0 0 1-1.6.8l-7.4-5.8a1 1 0 0 1 0-1.6l7.4-5.8a1 1 0 0 1 1.6.8Z" fill="currentColor"/>`,
}

export const iconNames = [...Object.keys(P), ...Object.keys(UI_Q), ...Object.keys(G).filter(k => !k.startsWith('u_'))]

export function icon(name: string, cls = 'icon'): string {
  const q = name.startsWith('draw:') ? name.slice(5) : UI_Q[name] ?? name
  if (G[q]) return qsvg(q, cls)
  return `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true">${P[name] || ''}</svg>`
}

/** 画线种类的记号（和界面同名记号分开：文字注释 note ≠ 笔记 note） */
export const toolIcon = (kind: string, cls = 'icon'): string => icon('draw:' + kind, cls)
