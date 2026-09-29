/* 手机网页版 · 主力订单流详情卡（照 iOS Main/OrderFlowDetailCard.swift）
 *
 * 卡不接触摸，放进图的视图层里；框 x=8、y=place.top，宽 plotW−16、高 place.maxHeight，
 * 按 below 贴底 / 贴顶、按 leading 贴左 / 贴右；卡宽不超过 maxWidth；主图矮时出两行卡。
 * 标题「价 · 委托买单 · 合约」+ 右上「持续 X」（放不下依次换短写），下面两行键值；状态按在场 / 成交 / 撤上色。
 * 还挂着的单持续时长每 30 秒跳一次。
 */
import type { ChartOrderFlowFocus } from '../../chart/renderer.orderflow'
import { el, esc } from '../../ui/dom'
import { cardText, type CardGroup, type CardText } from './logic'

const SIDE_INSET = 8

export function createOrderFlowCard(host: HTMLElement) {
  const box = el('div', 'cp-ofbox')
  box.hidden = true
  host.append(box)
  let focus: ChartOrderFlowFocus | null = null
  let meta = { base: '', dec: 2 }
  let timer = 0

  function card(t: CardText, compact: boolean, side: 'bid' | 'ask', maxW: number): HTMLElement {
    const c = el('div', 'cp-ofcard')
    c.style.maxWidth = Math.max(0, maxW) + 'px'
    const rows = compact ? [t.compactPair] : t.pairs
    const statusCls = t.state === 'live' ? 'live' : t.state === 'cancelled' ? 'gone' : 'done'
    c.innerHTML = `<div class="cp-of-title"><span class="cp-of-head num">${esc(t.price)} · <em class="${side === 'bid' ? 'up' : 'down'}">${t.sideTitle}</em> · ${t.kind}</span>`
      + `<span class="cp-of-dur" data-d="0">${esc(t.duration)}</span></div>`
      + `<div class="cp-of-grid num">` + rows.map((p, i) => {
        const last = i === rows.length - 1
        const left = `<span class="k">${p[0].label}</span><span class="v">${esc(p[0].value)}</span>`
        const right = last
          ? `<span class="cp-of-status"><span class="k">${p[1].label}</span><b class="${statusCls}">${esc(t.statusText)}</b></span>`
          : `<span class="k k2">${p[1].label}</span><span class="v">${esc(p[1].value)}</span>`
        return left + right
      }).join('') + `</div>`
    return c
  }

  /** 右上时长与状态：放不下依次换短写（ViewThatFits） */
  function fit(c: HTMLElement, t: CardText): void {
    const title = c.querySelector<HTMLElement>('.cp-of-title')!
    const dur = c.querySelector<HTMLElement>('.cp-of-dur')!
    for (const d of [t.duration, t.durationShort, t.durationCompact]) {
      dur.textContent = d
      if (title.scrollWidth <= title.clientWidth + 0.5) break
    }
    const st = c.querySelector<HTMLElement>('.cp-of-status')
    if (st) {
      const grid = c.querySelector<HTMLElement>('.cp-of-grid')!
      const b = st.querySelector('b')!, k = st.querySelector<HTMLElement>('.k')!
      if (grid.scrollWidth > grid.clientWidth + 0.5) b.textContent = t.statusTight
      if (grid.scrollWidth > grid.clientWidth + 0.5) k.hidden = true
    }
  }

  function render(): void {
    const f = focus
    if (!f) { box.hidden = true; box.replaceChildren(); return }
    const place = f.cardPlacement
    const g = f.group as unknown as CardGroup
    const t = cardText(g, meta.base, meta.dec, Math.max(Date.now(), f.asOfMs))
    box.hidden = false
    box.style.left = SIDE_INSET + 'px'
    box.style.top = place.top + 'px'
    box.style.width = Math.max(0, f.plotW - 2 * SIDE_INSET) + 'px'
    box.style.height = Math.max(0, place.maxHeight) + 'px'
    box.style.justifyContent = place.leading ? 'flex-start' : 'flex-end'
    box.style.alignItems = place.below ? 'flex-end' : 'flex-start'
    let c = card(t, place.compact, g.side, place.maxWidth)
    box.replaceChildren(c)
    if (!place.compact && c.offsetHeight > place.maxHeight + 0.5) { c = card(t, true, g.side, place.maxWidth); box.replaceChildren(c) }
    // 两行也放不下时照样整张画出来，按贴远端的方向往带那边伸（不裁）
    fit(c, t)
  }

  return {
    set(next: ChartOrderFlowFocus | null, base: string, dec: number): void {
      focus = next
      meta = { base, dec }
      clearInterval(timer)
      if (next) timer = window.setInterval(render, 30_000)
      render()
    },
    get open(): boolean { return focus != null },
    refresh: render,
    destroy(): void { clearInterval(timer); box.remove() },
  }
}
