/* Hkline Web · 就地打补丁：推送 / 定时器 / 订单流帧驱动的刷新只改字、改属性、改样式，不换节点
 *
 * 2026-10-07 用户报行情页左上角图例「悬停一直跳、点不到隐藏」，排查同类问题时探针（scripts/legend-hover-probe.mjs）
 * 在订单流盘口 / 大单 / 抽屉、板块页上都量到「指针下的节点被整块 innerHTML 重写换掉」：新节点要等下一次 mousemove
 * 才算 :hover，悬停提示（overlay.ts 记着旧节点，450 ms 后拿到的是脱离文档的 0,0 矩形）跑到左上角或出不来，
 * 按下与松开落在新旧两个节点上 click 不派发，键盘焦点丢掉。这里几样小工具让刷新路径只动值、不动结构：
 *   · patchShell：结构（外壳）按键复用，键没变不写 innerHTML
 *   · rowPool：一列行按位置复用（行数变了才增删尾部），行里的字由调用方用 patchText 等改
 *   · patchText / patchAttr / patchClass / patchStyle：值没变就不写 */

type Memo = Element & { _pk?: Record<string, string> }
const memo = (el: Element): Record<string, string> => ((el as Memo)._pk ??= {})

/** 外壳：key 跟上次一样就不动；变了才整块写 html。返回这次是否重建了 */
export function patchShell(el: Element, key: string, html: string): boolean {
  const m = memo(el)
  if (m.$shell === key) return false
  m.$shell = key
  el.innerHTML = html
  return true
}

/** 一列行按位置复用：保证 box 里正好 n 个由 tpl 生成的行（多了删尾、少了补尾），返回这些行。
 *  box 之前在别的外壳状态（等待提示等）时先清空 */
export function rowPool(box: HTMLElement, n: number, tpl: string): HTMLElement[] {
  const m = memo(box)
  if (m.$shell !== '#pool:' + tpl) { m.$shell = '#pool:' + tpl; box.textContent = '' }
  while (box.children.length < n) {
    const t = document.createElement('template'); t.innerHTML = tpl.trim()
    box.appendChild(t.content.firstElementChild!)
  }
  while (box.children.length > n) box.lastElementChild!.remove()
  return Array.from(box.children) as HTMLElement[]
}

/** 改字：只有一个文字子节点时改它的 data（不换节点），否则字不同才整体换 */
export function patchText(el: Element | null | undefined, t: string): void {
  if (!el) return
  const f = el.firstChild
  if (f && f === el.lastChild && f.nodeType === 3) { if ((f as Text).data !== t) (f as Text).data = t }
  else if (el.textContent !== t) el.textContent = t
}

export function patchAttr(el: Element | null | undefined, k: string, v: string | null): void {
  if (!el) return
  if (v == null) { if (el.hasAttribute(k)) el.removeAttribute(k) }
  else if (el.getAttribute(k) !== v) el.setAttribute(k, v)
}

export function patchClass(el: Element | null | undefined, c: string): void {
  if (el && el.getAttribute('class') !== c) el.setAttribute('class', c)
}

/** 改一条行内样式（CSS 属性名用连字符写法）：记着上次写的原样字符串比，不拿浏览器规范化回来的值比 */
export function patchStyle(el: Element | null | undefined, prop: string, v: string): void {
  if (!el) return
  const m = memo(el), k = 's:' + prop
  if (m[k] === v) return
  m[k] = v
  ;(el as HTMLElement).style.setProperty(prop, v)
}

/** 把 to 的属性同步到 from（删多的、改变了的） */
function syncAttrs(from: Element, to: Element): void {
  for (const a of Array.from(from.attributes)) if (!to.hasAttribute(a.name)) from.removeAttribute(a.name)
  for (const a of Array.from(to.attributes)) if (from.getAttribute(a.name) !== a.value) from.setAttribute(a.name, a.value)
}

/** 小号 morph：把 from 的子树就地改成 to 的样子。子节点按顺序对：类型与标签对得上就递归（文字改 data、属性逐个改）；
 *  对不上时往后找同标签的旧节点（中间的旧节点删掉），找不到就插新节点——多出 / 少了一块（如详情的高低区间条
 *  出现）只影响那一块，前后的按钮等节点都留着 */
function morph(from: Element, to: Element): void {
  syncAttrs(from, to)
  morphKids(from, to)
}
const kin = (x: Node, y: Node): boolean => x.nodeType === y.nodeType && (x.nodeType !== 1 || (x as Element).tagName === (y as Element).tagName)
function morphKids(from: Element, to: Element): void {
  const olds = Array.from(from.childNodes), news = Array.from(to.childNodes)
  let j = 0
  for (const y of news) {
    let k = j
    while (k < olds.length && !kin(olds[k]!, y)) k++
    if (k < olds.length) {
      for (; j < k; j++) olds[j]!.remove()
      const x = olds[j++]!
      if (x.nodeType === 1) morph(x as Element, y as Element)
      else if (x.nodeType === 3 && (x as Text).data !== (y as Text).data) (x as Text).data = (y as Text).data
    } else from.insertBefore(y, olds[j] ?? null)
  }
  for (; j < olds.length; j++) olds[j]!.remove()
}

function parse(html: string): DocumentFragment {
  const t = document.createElement('template'); t.innerHTML = html.trim()
  return t.content
}

/** 一块内容就地改成 html 的样子（morph：按钮、行等节点留着，只改变了的字与属性）。不按「跟上次一样」跳过——
 *  同一块可能被别的路径直接写过（如复盘右栏），每次对一遍才可靠；对得上的节点一个都不写 */
export function morphHtml(el: Element, html: string): void {
  const box = document.createElement('div')
  box.append(parse(html))
  morphKids(el, box) // 只改子树，el 自己的属性（id、类）不动
}

/** 一列带键的行（如表格 tbody）：同一个键的行节点一直复用（morph 成新内容，只改变了的字与属性），新键插新行、没了的键删掉、
 *  顺序变了就挪位置。不按「HTML 跟上次一样」跳过——行里的字可能被推送就地改过（如板块页 patchTicks），每次都对一遍才可靠。
 *  rows = [键, 这一行的 HTML]；attr = 行上放键的属性名 */
export function patchKeyedRows(box: Element, rows: readonly (readonly [string, string])[], attr: string): void {
  const m = memo(box)
  if (m.$shell !== '#k:' + attr) { m.$shell = '#k:' + attr; box.textContent = '' }
  const old = new Map<string, Element>()
  for (const el of Array.from(box.children)) { const k = el.getAttribute(attr); if (k != null && !old.has(k)) old.set(k, el); else el.remove() }
  let prev: Element | null = null
  for (const [k, html] of rows) {
    const nu = parse(html).firstElementChild
    if (!nu) continue
    let el = old.get(k)
    if (el) { old.delete(k); morph(el, nu) } else el = nu
    const want: Element | null = prev ? prev.nextElementSibling : box.firstElementChild
    if (want !== el) box.insertBefore(el, want)
    prev = el
  }
  for (const el of old.values()) el.remove()
}
