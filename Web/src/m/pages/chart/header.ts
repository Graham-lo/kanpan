/* 手机网页版 · 行情页顶栏 + 头部（照 iOS Main/TopBar.swift、MainScreenParts.swift、HeaderStats.swift）
 *
 * 顶栏：有来路时左边一颗「‹」；徽章 28 · 基础币 · /USDT · 「永续」角标（品种名不是按钮）；
 *       右边五颗 32 圆片：对比＋、提醒铃（角上这只还没响的条数）、记一笔、分享、放大镜。
 * 头部：左边最新价（--t-price，按涨跌上色，停住变灰）+ 紧贴其下一行涨跌额 涨跌幅；
 *       右边两列六格：仓 / 市值 / 结算 · 额 / 费率 / 估值。
 *       十字线活着（主图或副图）时整行价格连同六格透明让位（行高不变），同一位置换成铺满整宽的开高低收读数。
 *       价格区横滑扫图（左滑下一只、右滑上一只）。
 */
import { S, detailOf, fetchDetail } from '../../../market'
import { settle } from '../../../market/settle'
import { esc, grouped, fmtPrice, MISSING } from '../../model/rowText'
import { badgeHTML, assetOf } from '../../model/badge'
import { glyph, icon } from '../../ui/icons'
import { termMark, type Term } from '../../ui/hint'
import { el, setText } from '../../ui/dom'

/** 顶栏「对比」那颗加号（看得见 15，与搜索放大镜同一视觉分量） */
const PLUS_DISC = '<svg width="15" height="15" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 4v16M4 12h16" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/></svg>'
/** 顶栏铃铛（照 iOS TopBarGlyph.bell：实心钟身 + 底下一颗铃舌，18 框，看得见 17） */
const BELL_DISC = '<svg width="17" height="17" viewBox="0 0 18 18" aria-hidden="true"><path fill="currentColor" d="M9 2.2c-2.9 0-5 2.3-5 5.1v3.2L2.6 12.6c-.4.5 0 1.2.6 1.2h11.6c.6 0 1-.7.6-1.2L14 10.5V7.3c0-2.8-2.1-5.1-5-5.1z"/><path fill="currentColor" d="M7.1 14.6h3.8a1.9 1.9 0 0 1-3.8 0z"/></svg>'
import {
  priceChangeText, openInterestText, turnoverText, marketCapText, valuationCell, fundingText, fundingCountdownText,
  type AssetKind,
} from './logic'
import { fetchValuation, valuationOf } from './data'

export const TERMS: Record<string, Term> = {
  oi: { id: 'oi', title: '仓 · 持仓量', body: '现在市场上还没平掉的合约一共值多少美元。\n它在涨，说明有更多资金押注在这只上；在跌，说明有人在离场。' },
  turnover: { id: 'turnover', title: '额 · 24 小时成交额', body: '过去 24 小时里这只一共成交了多少美元。\n数越大，交易越活跃，买卖越容易成交。' },
  om: { id: 'om', title: 'O/M · 持仓÷市值', body: '合约持仓量除以这个币的总市值。\n比例越高，说明合约上押的钱相对现货越多，价格越容易被合约带着大起大落。' },
  fpe: { id: 'fpe', title: 'FPE · 预期市盈率', body: '市值除以分析师预期的未来一年净利润。\n大致是按预期的赚钱速度，要多少年才能赚回现在的市值；越低越便宜。' },
  ps: { id: 'ps', title: 'P/S · 市销率', body: '市值除以一年的营收。\n还没赚钱的公司没法看市盈率，就看它：越低，说明每一块钱营收被定价得越便宜。' },
  scale: { id: 'scale', title: '刻度', body: '线性：每格代表同样多的钱。\n对数：每格代表同样的涨跌幅，看大涨大跌的长周期更公平。\n百分比：以屏幕最左边那根为 0，刻度直接写涨跌了多少 %。' },
  threshold: { id: 'threshold', title: '门槛', body: '挂单金额超过这个数才画到图上。\n现货、合约各有一个，按品种给好了默认值，也可以自己改。' },
  step: { id: 'step', title: '步长', body: '相邻这么多美元以内的挂单先并成一档，再和门槛比。\n步长越大，零散的挂单越容易并成一堵墙。' },
}

/** 顶栏圆片（照 iOS TopBar，2026-10-05 起五颗）：对比＋ · 提醒铃 · 记一笔 · 分享 · 搜索 */
export interface TopBarHandlers { onBack(): void; onCompare(): void; onAlerts(): void; onNote(): void; onShare(): void; onSearch(): void }

/** 「BTCUSDT」→ BTC / USDT；1000 前缀用全市场表的 base */
export function splitPair(sym: string): { base: string; quote: string } {
  const s = S.symbols.get(sym)
  // 美元指数没有计价币：顶栏只写 DXY，不写「/」
  if (s?.macro || sym === 'DXY') return { base: s?.base ?? sym, quote: '' }
  const quote = /USDC$/.test(sym) ? 'USDC' : 'USDT'
  return { base: s?.base ?? sym.replace(/USDT$|USDC$/, ''), quote }
}

export function createTopBar(host: HTMLElement, h: TopBarHandlers) {
  const bar = el('div', 'cp-top')
  bar.innerHTML = `
    <button class="cp-disc cp-back" aria-label="返回" hidden>${icon('chevronLeft', 17)}</button>
    <div class="cp-id"><span class="cp-badge"></span><span class="cp-base"></span><span class="cp-quote"></span><span class="cp-perp">永续</span></div>
    <div class="cp-top-acts">
      <button class="cp-disc cp-cmpdisc" data-act="compare" aria-label="对比" aria-pressed="false">${PLUS_DISC}</button>
      <button class="cp-disc cp-belldisc" data-act="alerts" aria-label="提醒">${BELL_DISC}<span class="cp-bellcount num" aria-hidden="true" hidden></span></button>
      <button class="cp-disc" data-act="note" aria-label="记一笔">${glyph('review', 20)}</button>
      <button class="cp-disc" data-act="share" aria-label="分享">${icon('share', 17)}</button>
      <button class="cp-disc" data-act="search" aria-label="搜索品种">${icon('search', 16)}</button>
    </div>`
  host.append(bar)
  const back = bar.querySelector<HTMLButtonElement>('.cp-back')!
  back.onclick = () => h.onBack()
  const cmpDisc = bar.querySelector<HTMLButtonElement>('[data-act=compare]')!
  cmpDisc.onclick = () => h.onCompare()
  const bell = bar.querySelector<HTMLButtonElement>('[data-act=alerts]')!
  const bellCount = bell.querySelector<HTMLElement>('.cp-bellcount')!
  bell.onclick = () => h.onAlerts()
  bar.querySelector<HTMLButtonElement>('[data-act=note]')!.onclick = () => h.onNote()
  bar.querySelector<HTMLButtonElement>('[data-act=share]')!.onclick = () => h.onShare()
  bar.querySelector<HTMLButtonElement>('[data-act=search]')!.onclick = () => h.onSearch()
  let shown = ''
  return {
    el: bar,
    render(sym: string, hasOrigin: boolean, comparing = false, alerts = 0): void {
      if (back.hidden === hasOrigin) back.hidden = !hasOrigin
      // 铃铛角标：这只还没响的提醒条数，0 条不画；读屏念在标签里（「提醒 2」）
      const n = alerts > 0 ? String(Math.min(alerts, 99)) : ''
      if (bellCount.textContent !== n) {
        bellCount.textContent = n; bellCount.hidden = !n
        bell.setAttribute('aria-label', n ? '提醒 ' + alerts : '提醒')
      }
      // 有对比品种时 ＋ 亮强调色
      if (cmpDisc.classList.contains('on') !== comparing) { cmpDisc.classList.toggle('on', comparing); cmpDisc.setAttribute('aria-pressed', String(comparing)) }
      const s = S.symbols.get(sym)
      const { base, quote } = splitPair(sym)
      const key = sym + '|' + (s?.kind ?? '') + '|' + document.documentElement.dataset.skin
      if (key === shown) return
      shown = key
      bar.querySelector('.cp-badge')!.innerHTML = badgeHTML(base, 28, assetOf(s?.kind, base))
      bar.querySelector('.cp-base')!.textContent = base
      bar.querySelector('.cp-quote')!.textContent = quote ? '/' + quote : ''
      // 产品角标：永续合约写「永续」，美元指数写「指数」
      bar.querySelector('.cp-perp')!.textContent = s?.macro ? '指数' : '永续'
    },
    invalidate(): void { shown = '' },
  }
}

export interface HeaderHandlers { onSwipe(dx: number, dy: number): void }

export function createHeader(host: HTMLElement, h: HeaderHandlers) {
  const head = el('div', 'cp-head')
  head.innerHTML = `
    <div class="cp-quotebox">
      <div class="cp-quoteinner"><div class="cp-price num"></div><div class="cp-chg num"></div></div>
    </div>
    <pre class="cp-readout" hidden></pre>
    <div class="cp-stats">
      <div class="cp-col">
        <div class="cp-cell" data-k="oi"><span class="cp-lab">仓</span><b class="num"></b></div>
        <div class="cp-cell" data-k="cap"><span class="cp-lab">市值</span><b class="num"></b></div>
        <div class="cp-cell" data-k="settle"><span class="cp-lab">结算</span><b class="num"></b></div>
      </div>
      <div class="cp-col">
        <div class="cp-cell" data-k="vol"><span class="cp-lab">额</span><b class="num"></b></div>
        <div class="cp-cell" data-k="fr"><span class="cp-lab">费率</span><b class="num"></b></div>
        <div class="cp-cell" data-k="val"><span class="cp-lab"></span><b class="num"></b></div>
      </div>
    </div>`
  host.append(head)
  const cell = (k: string) => head.querySelector<HTMLElement>(`[data-k=${k}]`)!
  cell('oi').querySelector('.cp-lab')!.append(termMark(TERMS.oi))
  cell('vol').querySelector('.cp-lab')!.append(termMark(TERMS.turnover))
  const priceEl = head.querySelector<HTMLElement>('.cp-price')!, chgEl = head.querySelector<HTMLElement>('.cp-chg')!
  const readout = head.querySelector<HTMLElement>('.cp-readout')!
  const valCell = cell('val')
  const stats = head.querySelector<HTMLElement>('.cp-stats')!
  let valKey = ''

  // 横滑扫图：只在价格区（左边报价 + 右边六格整块）。触摸走 touch（iOS Safari 的横滑会吃掉 pointerup），鼠标走 pointer
  let sx = 0, sy = 0, tracking = false
  head.addEventListener('pointerdown', e => { if (e.pointerType !== 'mouse') return; sx = e.clientX; sy = e.clientY; tracking = true })
  head.addEventListener('pointerup', e => {
    if (!tracking) return
    tracking = false
    h.onSwipe(e.clientX - sx, e.clientY - sy)
  })
  head.addEventListener('pointercancel', () => { tracking = false })
  let tx = 0, ty = 0
  head.addEventListener('touchstart', e => { const t = e.touches[0]; tx = t.clientX; ty = t.clientY }, { passive: true })
  head.addEventListener('touchend', e => { const t = e.changedTouches[0]; h.onSwipe(t.clientX - tx, t.clientY - ty) }, { passive: true })

  let shownSym = ''
  return {
    el: head,
    render(sym: string, stale: boolean, now = Date.now()): void {
      const s = S.symbols.get(sym)
      const dec = s?.dec ?? 2
      const up = (s?.pct ?? s?.chg ?? 0) >= 0
      // 一秒一次（结算倒计时）加上每跳行情都进来：同值不写
      setText(priceEl, s?.price != null ? grouped(fmtPrice(s.price, dec)) : MISSING)
      setText(chgEl, priceChangeText(s?.chg, s?.pct, dec))
      for (const x of [priceEl, chgEl]) {
        x.classList.toggle('stale', stale)
        x.classList.toggle('up', !stale && s?.price != null && up)
        x.classList.toggle('down', !stale && s?.price != null && !up)
      }
      const fresh = !stale
      // 六格的数：缺数或行情停住都退成 ink3（照 TopBar.statValue）
      const put = (k: string, text: string): HTMLElement => {
        const b = cell(k).querySelector('b')!
        setText(b, text)
        b.classList.toggle('miss', stale || text === MISSING)
        return b
      }
      shownSym = sym
      // 美元指数：没有持仓、成交额（恒 0）、市值、资金费率、结算、估值——右边六格整块不摆，也不去取详情
      const macro = !!s?.macro
      if (stats.hidden !== macro) stats.hidden = macro
      if (macro) return
      // 自己一分钟最多取一次；价还没到时取了算不出美元持仓、又要空等一分钟。扫图划过去的那只还排在限流里就不发
      // 详情的五个慢数不是首屏：品种停稳（market/settle）再取，同一个键只留最后那只
      if (s?.price != null) settle.whenSettled('m-detail', () => { if (shownSym === sym) void fetchDetail(sym, () => shownSym === sym) })
      const oi = detailOf(sym)?.oiValue
      put('oi', openInterestText(oi))
      put('vol', turnoverText(s?.vol, fresh))
      put('cap', marketCapText(s?.supply, s?.price, fresh))
      const f = fundingText(s?.fr, fresh)
      const frB = put('fr', f.text)
      frB.classList.toggle('up', f.dir > 0); frB.classList.toggle('down', f.dir < 0)
      put('settle', fundingCountdownText(s?.nextFunding, now) ?? MISSING)
      // 估值：加密 O/M、美股 FPE（亏损给 P/S），大宗不摆
      const kind = (s?.kind ?? 'crypto') as AssetKind
      if (kind === 'us') void fetchValuation(sym)
      else if (s && !s.supply) void fetchValuation(sym)
      const v = valuationOf(sym)
      const vc = valuationCell(kind, { oi, supply: s?.supply, price: fresh ? s?.price : null, forwardEarnings: v?.forwardEarnings, revenue: v?.revenue })
      valCell.hidden = !vc
      if (vc) {
        if (valKey !== vc.label) {
          valKey = vc.label
          const lab = valCell.querySelector('.cp-lab')!
          lab.textContent = vc.label
          lab.append(termMark(vc.label === 'O/M' ? TERMS.om : vc.label === 'P/S' ? TERMS.ps : TERMS.fpe))
        }
        put('val', vc.value ?? MISSING)
      }
    },
    /** 十字线读数：null = 收起，恢复价格 */
    setReadout(text: string | null): void {
      if (readout.hidden !== (text == null)) readout.hidden = text == null
      head.classList.toggle('reading', text != null)
      if (text != null) setText(readout, text)
    },
  }
}

export { esc }
