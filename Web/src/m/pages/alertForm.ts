/* 手机网页版 · 创建提醒（照 iOS Alerts/AlertForm.swift，2026-09-25 v2 定稿）
 *
 * 图上十字线那颗「创建提醒」开的整页面板：左上关闭、标题「创建提醒」、右上「全部预警」（推进总表）。
 * 分组卡片一种语言到底：
 *   品种卡（不可编辑）：徽章 + BTC/USDT + 币安 · USDT 永续，右侧现价与涨跌幅（涨跌色）。
 *   条件卡：「价格」输入井（铅笔记号、数字右对齐、后缀计价币）+ 提示行（现价 X · 高于 / 低于现价 N%）
 *           + 发丝线 +「条件 ?」两段分段「价格达到 | 收盘穿过」（槽取页面底色，和输入井同一个底）。没有 ±% 快捷。
 *   通知卡：「Webhook ?」只填地址（https://），没有单独的开关——填了就发、空着就不发（iOS 2026-09-28 收设置项 E 组去掉了开关）；
 *           框里有字时下面靠右一颗「发一条测试」，地址不合法时灰着点不了（不另写错误字）。
 *   主按钮「创建提醒」（胶囊 48 高；不能交时换中性底 + ink3 字，不整块降透明度）。
 *   「当前提醒 N」：列这只品种还没触发的价格与画线提醒，价格提醒点一条进「编辑提醒」（同一页，按钮「保存」），行上删除 icon。
 * 没有备注、没有重复提醒（只响一次）。建完请求一次通知权限。
 * 条件提醒（资金费率 / 持仓量 / 均线 / 大单墙）iOS 只在登录 + 币安 U 本位时由服务端判，网页版暂不摆。
 */
import '../styles/alerts.css'
import { S, on, streamName } from '../../market'
import { alertLevel, cleanWebhook, makePriceAlert, validWebhook } from '../../alerts/shape'
import { openSheet, type Sheet } from '../ui/sheet'
import { icon } from '../ui/icons'
import { registerTerms, termHTML } from '../ui/hint'
import { toast } from '../ui/toast'
import { el } from '../ui/dom'
import { esc, priceText, changePercentText, fmtPrice, priceDecimalsFallback } from '../model/rowText'
import { hintText, parseTarget } from '../model/formText'
import { badgeHTML } from '../model/badge'
import { factsOf, splitSymbol } from '../model/rowHTML'
import { addPriceAlert, onAlertsChange, records, updatePriceAlert, webhookBody, type Alert, type Condition } from '../model/alerts'
import { openSymbol } from '../app/shell'
import { askNotifyPermission, buildAlertList, deleteWithUndo, pairName, recordRowHTML, startAlertWatcher, venueLine } from './alerts'
import { wantStreams } from './_streams'
import { life, layers, type Life } from '../model/life'

registerTerms([
  { id: 'alertCondition', title: '条件', body: '价格达到：盘中价格一碰到就响。\n收盘穿过：要等 K 线收盘、收盘价越过这个价才响，盘中来回插针不算。' },
  { id: 'webhook', title: 'Webhook', body: '触发时向这个地址发一条 JSON，里面是一句提醒文字，格式由我们定好。\n可以接到自己的机器人或群里；点「发一条测试」先试一下。' },
])

const CONDITIONS: readonly [Condition, string][] = [['touch', '价格达到'], ['close', '收盘穿过']]

const PENCIL = '<svg width="14" height="14" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 20h4L19 9a2.8 2.8 0 0 0-4-4L4 16v4z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg>'

/** 打开「创建提醒」。price：十字线那一口（预填） */
export function openAlertForm(symbol: string, price?: number | null): Sheet {
  startAlertWatcher()
  // 底层（创建提醒）活到整张面板关掉；推进去的「编辑提醒」「全部预警」退回底层就收尾
  const base = life()
  const above = layers()
  const sheet = openSheet((body, sh) => {
    body.classList.add('alf-body')
    buildForm(body, sh, symbol, null, price ?? null, base)
  }, {
    title: '创建提醒', detent: 'large', expandable: false, className: 'alf-sheet', id: 'alerts.new',
    action: { title: '全部预警', run: () => pushAll() },
    onClose: () => { above.endAll(); base.end(); wantStreams('alertForm', []) },
  })
  // 左上是关闭（×），不是返回
  const back = sheet.root.querySelector<HTMLElement>('.m-sheet-back')
  if (back) { back.innerHTML = icon('close', 18); back.setAttribute('aria-label', '关闭') }
  const action = sheet.root.querySelector<HTMLElement>('.m-sheet-action')
  function pushAll(): void {
    sheet.push('全部预警', b => {
      b.classList.add('alf-body')
      above.push().add(buildAlertList(b, { onOpen: a => { sheet.close(); openSymbol(a.symbol) } }))
    })
  }
  // 只在最底层（创建提醒）摆「全部预警」；推进下一层就收起，回来再摆
  const mo = new MutationObserver(() => {
    const pushed = sheet.root.classList.contains('pushed')
    if (action) action.hidden = pushed
    above.settle(!pushed)
  })
  mo.observe(sheet.root, { attributes: true, attributeFilter: ['class'] })
  base.add(() => mo.disconnect())
  wantStreams('alertForm', [streamName.ticker(symbol)])
  return sheet

  function buildForm(host: HTMLElement, sh: Sheet, sym: string, existing: Alert | null, preset: number | null, L: Life): void {
    const s0 = S.symbols.get(sym)
    const f = factsOf(sym, s0)
    const { quote } = splitSymbol(sym)
    const dec = s0?.dec
    const start = existing ? alertLevel(existing) : preset
    let cond: Condition = existing?.condition ?? 'touch'
    const startText = start != null && start > 0 ? fmtPrice(start, dec ?? priceDecimalsFallback(start)) : ''
    const form = el('div', 'alf-form')
    form.dataset.title = existing ? '编辑提醒' : '创建提醒'
    form.innerHTML = `
      <div class="al-card alf-symbol">
        ${badgeHTML(f.base, 28, f.asset)}
        <span class="alf-names"><span class="alf-pair">${esc(pairName(sym))}</span><span class="alf-venue">${esc(venueLine(sym))}</span></span>
        <span class="alf-quote"><span class="alf-px num"></span><span class="alf-pct num"></span></span>
      </div>
      <div class="al-card alf-cond">
        <label class="alf-row alf-price-row"><span class="alf-label">价格</span>
          <span class="alf-well">${PENCIL}<input class="num" type="text" inputmode="decimal" enterkeyhint="done" autocomplete="off" autocorrect="off" spellcheck="false" placeholder="0" aria-label="价格" value="${esc(startText)}"><span class="alf-unit">${esc(quote || (sym === 'DXY' ? '' : 'USDT'))}</span></span>
        </label>
        <div class="alf-hint num"></div>
        <div class="al-div"></div>
        <div class="alf-row alf-cond-row"><span class="alf-label">条件${termHTML('alertCondition')}</span><div class="m-seg" role="radiogroup" aria-label="条件">${CONDITIONS.map(([v, t]) => `<button type="button" class="m-seg-opt${v === cond ? ' on' : ''}" role="radio" aria-checked="${v === cond}" data-v="${v}">${t}</button>`).join('')}</div></div>
      </div>
      <div class="al-card alf-notify">
        <label class="alf-row"><span class="alf-label">Webhook${termHTML('webhook')}</span>
          <input class="alf-hook" type="url" inputmode="url" autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false" placeholder="https://" aria-label="Webhook 地址" value="${esc(existing?.webhook ?? '')}"></label>
      </div>
      <div class="alf-under" hidden><button type="button" class="alf-test">发一条测试</button></div>
      <button type="button" class="alf-submit">${existing ? '保存' : '创建提醒'}</button>
      <div class="alf-records"></div>`
    host.appendChild(form)
    const input = form.querySelector<HTMLInputElement>('.alf-well input')!
    const well = form.querySelector<HTMLElement>('.alf-well')!
    const hook = form.querySelector<HTMLInputElement>('.alf-hook')!
    const hint = form.querySelector<HTMLElement>('.alf-hint')!
    const test = form.querySelector<HTMLButtonElement>('.alf-test')!
    const under = form.querySelector<HTMLElement>('.alf-under')!
    const seg = form.querySelector<HTMLElement>('.m-seg')!
    const submit = form.querySelector<HTMLButtonElement>('.alf-submit')!
    const recHost = form.querySelector<HTMLElement>('.alf-records')!
    const pxEl = form.querySelector<HTMLElement>('.alf-px')!
    const pctEl = form.querySelector<HTMLElement>('.alf-pct')!
    let testing = false

    const now = (): { price: number | null; pct: number | null } => {
      const s = S.symbols.get(sym)
      return { price: s?.price ?? null, pct: s?.pct ?? null }
    }
    const ready = (): boolean => parseTarget(input.value) != null && validWebhook(hook.value)
    const paintQuote = (): void => {
      const q = now()
      pxEl.textContent = priceText(q.price, dec)
      pctEl.textContent = changePercentText(q.pct)
      const dir = q.pct == null ? '' : q.pct >= 0 ? 'up' : 'down'
      pxEl.className = 'alf-px num ' + dir; pctEl.className = 'alf-pct num ' + dir
      hint.textContent = hintText(parseTarget(input.value), q.price, dec)
    }
    const paint = (): void => {
      paintQuote()
      const hv = hook.value.trim()
      const hookOk = validWebhook(hook.value)
      under.hidden = !hv
      test.disabled = !hookOk || testing
      test.textContent = testing ? '发送中…' : '发一条测试'
      submit.disabled = !ready()
    }
    const paintRecords = (): void => {
      if (existing) { recHost.innerHTML = ''; return }
      const list = records(sym)
      recHost.innerHTML = list.length ? `<div class="al-title num">当前提醒 ${list.length}</div>
        <div class="al-card">${list.map((a, i) => recordRowHTML(a, { divider: i < list.length - 1 })).join('')}</div>` : ''
    }
    input.addEventListener('focus', () => well.classList.add('focus'))
    input.addEventListener('blur', () => well.classList.remove('focus'))
    input.addEventListener('input', paint)
    input.addEventListener('keydown', e => { if (e.key === 'Enter') input.blur() })
    hook.addEventListener('input', paint)
    seg.addEventListener('click', e => {
      const opt = (e.target as HTMLElement).closest<HTMLElement>('.m-seg-opt')
      if (!opt || opt.dataset.v === cond) return
      cond = opt.dataset.v as Condition
      seg.querySelectorAll<HTMLElement>('.m-seg-opt').forEach(b => { const on = b.dataset.v === cond; b.classList.toggle('on', on); b.setAttribute('aria-checked', String(on)) })
    })
    hook.addEventListener('keydown', e => { if (e.key === 'Enter') hook.blur() })
    test.onclick = () => {
      const url = cleanWebhook(hook.value)
      if (!url || testing) return
      const q = now()
      const target = parseTarget(input.value) ?? q.price ?? 0
      const draft = makePriceAlert(sym, target, q.price, { dec, webhook: url })
      if (existing) draft.id = existing.id
      const payload = { ...webhookBody(draft, q.price ?? target, Date.now(), target), event: 'test' }
      testing = true; paint()
      const ctl = new AbortController()
      const timer = setTimeout(() => ctl.abort(), 8000)
      fetch(url, { method: 'POST', mode: 'no-cors', signal: ctl.signal, headers: { 'Content-Type': 'text/plain;charset=utf-8' }, body: JSON.stringify(payload) })
        .then(() => toast('已发出'), (e: unknown) => toast((e as Error)?.name === 'AbortError' ? '发送失败 · 超时' : '发送失败 · 连不上'))
        .finally(() => { clearTimeout(timer); testing = false; if (!L.ended) paint() })
    }
    submit.onclick = () => {
      const target = parseTarget(input.value)
      if (target == null || !validWebhook(hook.value)) return
      input.blur(); hook.blur()
      const q = now()
      const a = existing
        ? updatePriceAlert(existing.id, target, q.price, dec, hook.value, Date.now(), cond)
        : addPriceAlert(sym, target, q.price, dec, hook.value, Date.now(), cond)
      if (!a) { toast('没建成，再试一次'); return }
      if (!existing) askNotifyPermission()
      if (existing) { sh.back(); return }
      sh.close()
    }
    recHost.addEventListener('click', e => {
      const t = e.target as HTMLElement
      const del = t.closest<HTMLElement>('[data-del]')
      if (del) { deleteWithUndo(del.dataset.del!); return }
      const open = t.closest<HTMLElement>('[data-open]')
      if (!open) return
      const a = records(sym).find(x => x.id === open.dataset.open)
      if (!a || a.kind !== 'price') return
      sh.push('编辑提醒', b => { b.classList.add('alf-body'); buildForm(b, sh, sym, a, null, above.push()) })
    })
    // 这只品种在行情页上时逐笔成交也发 ticker（一秒几十下）：并到下一帧画一次
    const paintQuoteSoon = L.frame(paintQuote)
    L.add(on(e => { if (e.type === 'ticker' && e.symbol === sym) paintQuoteSoon() }))
    L.add(onAlertsChange(paintRecords))
    paint(); paintRecords()
    if (!startText) L.frame(() => input.focus({ preventScroll: true }))()
  }
}
