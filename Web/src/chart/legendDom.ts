/* Hkline Web · 图例 DOM：结构只在「指标集 / 参数 / 降级档」变了时重建，读数只改文字节点
 *
 * 2026-10-07 用户报「左上角指标悬停时一直跳、点不到隐藏按钮」，复现出的机制：推送 / 十字线一动，整块图例 innerHTML 重写——
 * 指针下那一行被换成新节点，新节点要等下一次 mousemove 才算 :hover，悬停才出的工具按钮先消失（行跟着变窄，
 * 指针落到画布上、十字线接着动、图例接着重写，按钮再也回不来）；按下与松开落在新旧两个节点上，click 不派发。
 * 照 TradingView 的做法：外壳（名称、参数、工具按钮）按「结构键」复用，读数格子按位置复用、只改字；
 * 显示 / 隐藏也就地改（行的类、眼睛图标），不重建。 */
import { icon } from '../ui/icons'

/** 一格读数：[颜色（空 = 跟随样式）, 前缀标签（空 = 无）, 文字, 类名（up / down / faint，可省）] */
export type LegVal = readonly [col: string, lab: string, txt: string, cls?: string]

type Memo = HTMLElement & { _k?: string; _c?: string; _x?: string; _l?: string; _h?: boolean }

/** 读数格子的外壳 HTML（每格 `<span><i>标签</i><b>字</b></span>`，字由 patchVals 填） */
function cellsHtml(vals: readonly LegVal[]): string {
  return vals.map(([, lab]) => `<span>${lab ? `<i>${lab}</i>` : ''}<b></b></span>`).join('')
}

/** 把一组读数写进读数盒：格数与标签不变时只改文字节点的字（不换节点）、颜色 / 类变了才改；
 *  格数或标签变了（带前缀的线这一根没值、分形上下切换）才重建这一个读数盒——工具按钮在读数之前，不受影响 */
export function patchVals(box: HTMLElement, vals: readonly LegVal[]): void {
  const m = box as Memo
  const vk = vals.map(v => v.join('\u0001')).join('\u0002')
  if (m._k === vk) return
  m._k = vk
  const lk = vals.map(v => v[1]).join('\u0001') + '|' + vals.length
  if (m._l !== lk) { m._l = lk; box.innerHTML = cellsHtml(vals) }
  const sp = box.children
  vals.forEach(([col, , txt, cls], j) => {
    const el = sp[j] as Memo | undefined; if (!el) return
    if (el._c !== col) { el.style.color = col; el._c = col }
    const k = cls ?? ''
    if (el._x !== k) { el.className = k; el._x = k }
    const b = el.lastElementChild as HTMLElement | null; if (!b) return
    const tn = b.firstChild as Text | null
    if (!tn) b.textContent = txt; else if (tn.data !== txt) tn.data = txt
  })
}

/** 行的显示 / 隐藏就地改：带 data-lid 的行（或 dense 的一块）切 hidden-ind 类、眼睛按钮换图标与提示 */
export function applyHidden(root: ParentNode, hidden: ReadonlySet<string>): void {
  for (const el of Array.from(root.querySelectorAll<HTMLElement>('[data-lid]'))) {
    const id = el.dataset.lid ?? '', h = hidden.has(id), m = el as Memo
    if (m._h === h) continue
    m._h = h
    el.classList.toggle('hidden-ind', h)
    const btn = el.querySelector<HTMLElement>('[data-act="toggle"]')
    if (btn) { btn.dataset.tip = h ? '显示' : '隐藏'; btn.setAttribute('aria-label', h ? '显示' : '隐藏'); btn.innerHTML = icon(h ? 'eyeOff' : 'eye', 'icon-16') }
  }
}

/** 一行图例的工具按钮（显示 / 参数 / 移除；没有可调参数的不放齿轮）。和显隐无关——显隐由 applyHidden 就地改，
 *  这样点「隐藏」不会让结构键变、整行重建（重建的新行要等下一次 mousemove 才算悬停，按钮会闪一下） */
export function toolsHtml(id: string, hasParams: boolean, lead = ''): string {
  const I = icon
  return `<span class="tools">${lead}<button class="ibtn xs" data-act="toggle" data-id="${id}" data-tip="隐藏" aria-label="隐藏">${I('eye', 'icon-16')}</button>${hasParams ? `<button class="ibtn xs" data-act="settings" data-id="${id}" data-tip="参数" aria-label="参数">${I('gear', 'icon-16')}</button>` : ''}<button class="ibtn xs" data-act="remove" data-id="${id}" data-tip="移除" aria-label="移除">${I('close', 'icon-16')}</button></span>`
}

/** 读数盒的占位（结构里的空盒；data-v 按出现顺序与读数组一一对应） */
export const VALS_BOX = '<span class="vals num" data-v></span>'
