/* Hkline 手机网页版 · 术语小问号与居中解释卡（照 iOS Glossary/TermMark.swift、GlossaryCard.swift）
 *
 * 小问号：12px 细圈里一个「?」，颜色跟着所在文字、55% 不透明；点击框撑到 32×32 但不撑大排版。
 * 解释卡：屏幕正中，宽 280、圆角 18、raised 底；标题（heading）+ 两三行正文（14，ink2）+ 发丝线 + 强调色「知道了」。
 * 遮罩深色 0.5 / 浅色 0.32，点遮罩或「知道了」都关，进出 0.2 秒淡入淡出；同一刻只弹一张。
 *
 * 两种用法：
 *   1. 直接拿元素：label.after(termMark(TERM))
 *   2. 拼 HTML：先 registerTerms([...])，再在模板里写 termHTML('oi')；点击由全局委托接住。
 */
import { el, esc, layer } from './dom'
import { pushLayer } from './sheet'

export interface Term {
  /** 英文小写短词（拼 data-term / 测试标识用） */
  id: string
  /** 「短标签 · 全称」，如「仓 · 持仓量」 */
  title: string
  /** 两三行说人话的解释 */
  body: string
}

const registry = new Map<string, Term>()
let wired = false

/** 登记术语（termHTML 按 id 找） */
export function registerTerms(list: Term[]): void {
  list.forEach(t => registry.set(t.id, t))
  wire()
}

const MARK = '<svg width="12" height="12" viewBox="0 0 12 12" aria-hidden="true"><circle cx="6" cy="6" r="5.5" fill="none" stroke="currentColor" stroke-width="1"/><text x="6" y="8.6" text-anchor="middle" font-size="8.5" font-weight="700" fill="currentColor" font-family="ui-rounded, -apple-system, system-ui">?</text></svg>'

/** 小问号的 HTML（需先 registerTerms） */
export function termHTML(id: string): string {
  const t = registry.get(id)
  return `<button type="button" class="m-term" data-term="${esc(id)}" aria-label="${esc((t?.title ?? id) + ' 说明')}">${MARK}</button>`
}

/** 小问号元素（不需要登记） */
export function termMark(term: Term): HTMLButtonElement {
  registry.set(term.id, term)
  wire()
  const b = el('button', 'm-term', MARK)
  b.type = 'button'
  b.dataset.term = term.id
  b.setAttribute('aria-label', term.title + ' 说明')
  return b
}

function wire(): void {
  if (wired) return
  wired = true
  // 捕获阶段接住，免得整行的点击（进详情等）先跑；只在真正点在问号上时拦
  document.addEventListener('click', e => {
    const b = (e.target as Element | null)?.closest?.('.m-term') as HTMLElement | null
    if (!b) return
    const t = registry.get(b.dataset.term || '')
    if (!t) return
    e.preventDefault(); e.stopPropagation()
    showTerm(t)
  }, true)
}

let open: HTMLElement | null = null

/** 屏幕正中弹一张解释卡 */
export function showTerm(term: Term): void {
  if (open) return
  const scrim = el('div', 'm-term-scrim')
  scrim.innerHTML = `<div class="m-term-card" role="dialog" aria-modal="true" aria-label="${esc(term.title)}">
    <div class="m-term-main"><div class="m-term-title">${esc(term.title)}</div><div class="m-term-body">${esc(term.body)}</div></div>
    <button type="button" class="m-term-ok">知道了</button></div>`
  let done = false
  const close = (): void => {
    if (done) return
    done = true; unlayer()
    scrim.classList.remove('in')
    setTimeout(() => { scrim.remove(); if (open === scrim) open = null }, 200)
  }
  // 排进弹层那一摞：切页时一起收，系统返回 / Esc 先关它
  const unlayer = pushLayer(close)
  scrim.addEventListener('click', e => { if (e.target === scrim) close() })
  scrim.querySelector<HTMLElement>('.m-term-ok')!.onclick = close
  layer().appendChild(scrim)
  open = scrim
  requestAnimationFrame(() => scrim.classList.add('in'))
}
