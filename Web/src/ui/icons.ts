/* Hkline Web · 图标
 *
 * 2026-10-08 起两套并存、一个入口：
 *   · 「质感」一套（ui/qicons.ts，18 格 SF Symbols 分层）——画线工具全套、左画线栏、右侧栏、工具条、顶栏、
 *     以及别处用到同名记号的地方都走它；底块（磨砂块 / 悬停 / 选中玻璃块）由 styles/icons.css 按所在位置套上。
 *   · 关闭、勾、加号、播放、账号、钥匙……这些杂项小记号 2026-10-09 起也补齐了质感版（u_ 一组），
 *     不再有 24 格实心双调（衬底 30%）的老图标；P 里只剩品牌记号。
 * 画线种类名直接取质感字形；「note」在界面上是笔记 / 记一笔，画线里是文字注释——要画线那只就写 'draw:note'（toolIcon）。
 */
import { G, UI_Q, qsvg } from './qicons'

// 只剩品牌记号：其余杂项小记号 2026-10-09 起全部改走质感字形（qicons.ts 里 u_ 开头那一组）
const P: Record<string, string> = {
  logo: `<rect x="2" y="2" width="20" height="20" rx="6" fill="var(--accent)"/><path d="M7 16.5V9.2M12 15V6.5M17 13.5v-5" stroke="#fff" stroke-width="2.4" stroke-linecap="round"/><path d="M7 7.2v1M12 16.9v.8M17 15.6v.8M17 6.4v.8" stroke="#fff" stroke-width="2.4" stroke-linecap="round" opacity=".55"/>`,
}

export const iconNames = [...Object.keys(P), ...Object.keys(UI_Q), ...Object.keys(G).filter(k => !k.startsWith('u_'))]

export function icon(name: string, cls = 'icon'): string {
  const q = name.startsWith('draw:') ? name.slice(5) : UI_Q[name] ?? name
  if (G[q]) return qsvg(q, cls)
  return `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true">${P[name] || ''}</svg>`
}

/** 画线种类的记号（和界面同名记号分开：文字注释 note ≠ 笔记 note） */
export const toolIcon = (kind: string, cls = 'icon'): string => icon('draw:' + kind, cls)
