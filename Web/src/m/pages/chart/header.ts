/* 手机网页版 · 行情页顶栏 + 头部（照 iOS Main/TopBar.swift、MainScreenParts.swift、HeaderStats.swift）
 *
 * 顶栏：有来路时左边一颗「‹」；徽章 28 · 基础币（headName：DOGE、1000PEPE、kPEPE）· 角标小字「币安 USDT 永续」
 *       「HL USDC 永续」「CB USD 现货」「指数」（2026-10-08 三端一致，计价币写进角标、不再单写「/USDT」；品种名不是按钮）；
 *       放不下时（横滑扫图带着「‹」）先收徽章，最后才截基础币——角标一直在（iOS a9f64327）；
 *       右边三颗 32 圆片（2026-10-08 起，照 iOS）：提醒铃（角上这只还没响的条数）· ⋯（更多）· 放大镜。
 *       用户原话「分享和记一笔用的极少，我觉得可以放到二级菜单里」：「⋯」点开一张菜单，从上到下
 *       添加对比 · 记一笔 · 分享；对比满三只时「添加对比」那一项置灰（「分析」面板里的「对比」一节照旧）。
 * 头部：左边最新价（--t-price，按涨跌上色，停住变灰）+ 紧贴其下一行涨跌额 涨跌幅；
 *       右边两列六格：仓 / 市值 / 结算 · 额 / 费率 / 估值。
 *       十字线活着时价格、涨跌、六格照旧实时（2026-10-08 起读数挪到周期条那一行，见 intervalBar.ts）。
 *       价格区横滑扫图（左滑下一只、右滑上一只）。
 */
import { S, detailOf, fetchDetail } from '../../../market'
import { settle } from '../../../market/settle'
import { esc, grouped, fmtPrice, MISSING } from '../../model/rowText'
import { badgeHTML, assetOf } from '../../model/badge'
import { icon } from '../../ui/icons'
import { openMenu, type Popover } from '../../ui/sheet'
import { termMark, type Term } from '../../ui/hint'
import { el, setText } from '../../ui/dom'

/** 顶栏「⋯」（照 iOS TopBarGlyph.more：16 框里三颗 1.8 半径的实心圆点） */
const MORE_DISC = '<svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><g fill="currentColor"><circle cx="2.8" cy="8" r="1.8"/><circle cx="8" cy="8" r="1.8"/><circle cx="13.2" cy="8" r="1.8"/></g></svg>'
/** 顶栏铃铛（照 iOS TopBarGlyph.bell：实心钟身 + 底下一颗铃舌，18 框，看得见 17） */
const BELL_DISC = '<svg width="17" height="17" viewBox="0 0 18 18" aria-hidden="true"><path fill="currentColor" d="M9 2.2c-2.9 0-5 2.3-5 5.1v3.2L2.6 12.6c-.4.5 0 1.2.6 1.2h11.6c.6 0 1-.7.6-1.2L14 10.5V7.3c0-2.8-2.1-5.1-5-5.1z"/><path fill="currentColor" d="M7.1 14.6h3.8a1.9 1.9 0 0 1-3.8 0z"/></svg>'
import {
  priceChangeText, openInterestText, turnoverText, marketCapText, valuationCell, fundingText, fundingCountdownText,
  type AssetKind,
} from './logic'
import { fetchValuation, valuationOf } from './data'
import { liveOrCached } from '../../model/quoteCache'
import { chartSubOf, pairOf } from '../../model/symKey'
import { headName, type Sym } from '../../../market/symbols'

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

/** 顶栏圆片（照 iOS TopBar，2026-10-08 起三颗）：提醒铃 · ⋯（添加对比 / 记一笔 / 分享）· 搜索 */
export interface TopBarHandlers { onBack(): void; onCompare(): void; onAlerts(): void; onNote(): void; onShare(): void; onSearch(): void }

/** 「BTCUSDT」→ BTC / USDT；1000 前缀用全市场表的 base（分享卡、订单流卡、习惯分类按币认）。
 *  别家（okx/usd_m/BTCUSDT、coinbase/spot/BTC-USD、hyperliquid/usd_m/KPEPE）按品种表的 base / quote，表没到按键猜 */
export function splitPair(sym: string): { base: string; quote: string } {
  const s = S.symbols.get(sym)
  // 美元指数没有计价币：顶栏只写 DXY，不写「/」
  if (s?.macro || sym === 'DXY') return { base: s?.base ?? sym, quote: '' }
  if (sym.includes('/')) { const p = pairOf(sym, s); return { base: s?.base ?? p.base, quote: p.quote } }
  const quote = /USDC$/.test(sym) ? 'USDC' : 'USDT'
  return { base: s?.base ?? sym.replace(/USDT$|USDC$/, ''), quote }
}
/** 顶栏两截：品种名只写基础币（带交易所自己的倍数前缀，同电脑版 headName）+ 旁边那截小字（chartSubOf） */
export function topBarText(sym: string, s: Sym | undefined = liveOrCached(sym)): { name: string; sub: string } {
  return { name: headName(s ?? { symbol: sym }), sub: chartSubOf(sym, s) }
}

export function createTopBar(host: HTMLElement, h: TopBarHandlers) {
  const bar = el('div', 'cp-top')
  bar.innerHTML = `
    <button class="cp-disc cp-back" aria-label="返回" hidden>${icon('chevronLeft', 17)}</button>
    <div class="cp-id"><span class="cp-badge"></span><span class="cp-base"></span><span class="cp-quote"></span><span class="cp-perp">永续</span></div>
    <div class="cp-top-acts">
      <button class="cp-disc cp-belldisc" data-act="alerts" aria-label="提醒">${BELL_DISC}<span class="cp-bellcount num" aria-hidden="true" hidden></span></button>
      <button class="cp-disc" data-act="more" aria-label="更多" aria-haspopup="menu" aria-expanded="false">${MORE_DISC}</button>
      <button class="cp-disc" data-act="search" aria-label="搜索品种">${icon('search', 16)}</button>
    </div>`
  host.append(bar)
  const back = bar.querySelector<HTMLButtonElement>('.cp-back')!
  back.onclick = () => h.onBack()
  const bell = bar.querySelector<HTMLButtonElement>('[data-act=alerts]')!
  const bellCount = bell.querySelector<HTMLElement>('.cp-bellcount')!
  bell.onclick = () => h.onAlerts()
  const more = bar.querySelector<HTMLButtonElement>('[data-act=more]')!
  let compareFull = false
  let menu: Popover | null = null
  more.onclick = () => {
    if (menu && !menu.closed) { menu.close(); return }
    more.setAttribute('aria-expanded', 'true')
    menu = openMenu(more, [
      { title: '添加对比', icon: 'plus', act: 'compare', disabled: compareFull, run: () => h.onCompare() },
      { title: '记一笔', icon: 'note', act: 'note', run: () => h.onNote() },
      { title: '分享', icon: 'share', act: 'share', run: () => h.onShare() },
    ], () => { more.setAttribute('aria-expanded', 'false'); menu = null })
  }
  bar.querySelector<HTMLButtonElement>('[data-act=search]')!.onclick = () => h.onSearch()
  const id = bar.querySelector<HTMLElement>('.cp-id')!
  const baseEl = bar.querySelector<HTMLElement>('.cp-base')!
  let shown = ''
  let fitKey = ''
  /** 品种块放不下（基础币被截了）时一档一档退：先收徽章，再收计价币（照 iOS TopBar 的 ViewThatFits） */
  function fitId(hasOrigin: boolean): void {
    const k = shown + '|' + hasOrigin + '|' + innerWidth
    if (k === fitKey) return
    fitKey = k
    id.classList.remove('nobadge', 'noquote')
    const cut = (): boolean => baseEl.scrollWidth > baseEl.clientWidth + 0.5
    if (cut()) id.classList.add('nobadge')
    if (cut()) id.classList.add('noquote')
  }
  // 字体晚到时第一次量的是后备字体的宽度，到了再量一遍
  void document.fonts?.ready.then(() => { fitKey = ''; fitId(!back.hidden) })
  return {
    el: bar,
    /** full：对比集合已满三只（「⋯ › 添加对比」置灰） */
    render(sym: string, hasOrigin: boolean, full = false, alerts = 0): void {
      if (back.hidden === hasOrigin) back.hidden = !hasOrigin
      // 铃铛角标：这只还没响的提醒条数，0 条不画；读屏念在标签里（「提醒 2」）
      const n = alerts > 0 ? String(Math.min(alerts, 99)) : ''
      if (bellCount.textContent !== n) {
        bellCount.textContent = n; bellCount.hidden = !n
        bell.setAttribute('aria-label', n ? '提醒 ' + alerts : '提醒')
      }
      compareFull = full
      const s = liveOrCached(sym)
      const { base } = splitPair(sym)
      const { name, sub } = topBarText(sym, s)
      const key = sym + '|' + (s?.kind ?? '') + '|' + name + '|' + sub + '|' + document.documentElement.dataset.skin
      if (key !== shown) {
        shown = key
        bar.querySelector('.cp-badge')!.innerHTML = badgeHTML(base, 28, assetOf(s?.kind, base))
        baseEl.textContent = name
        bar.querySelector('.cp-quote')!.textContent = ''
        // 角标小字：交易所缩写 + 计价币 + 永续 / 现货；美元指数只写「指数」
        bar.querySelector('.cp-perp')!.textContent = sub
      }
      fitId(hasOrigin)
    },
    invalidate(): void { shown = ''; fitKey = '' },
  }
}

export interface HeaderHandlers { onSwipe(dx: number, dy: number): void }

export function createHeader(host: HTMLElement, h: HeaderHandlers) {
  const head = el('div', 'cp-head')
  head.innerHTML = `
    <div class="cp-quotebox">
      <div class="cp-quoteinner"><div class="cp-price num"></div><div class="cp-chg num"></div></div>
    </div>
    <div class="cp-busy" aria-hidden="true"><i></i></div>
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
      const live = S.symbols.get(sym)
      // 表还没到：先摆上次记下的价（退灰），实时的一到就换
      const s = live ?? liveOrCached(sym)
      if (!live && s) stale = true
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
      if (live?.price != null) settle.whenSettled('m-detail', () => { if (shownSym === sym) void fetchDetail(sym, () => shownSym === sym) })
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
      else if (live && !live.supply) void fetchValuation(sym)
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
    /** 换品种 / 周期取数中：头部下沿一条来回走的细条 */
    setBusy(on: boolean): void { head.classList.toggle('busy', on) },
  }
}

export { esc }
