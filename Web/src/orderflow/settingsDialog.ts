/* Hkline Web · 主力订单流 · 门槛与步长（设计稿 2.7）
 *
 * 「指标 › 主力订单流」行上的齿轮打开。每种产品一个门槛、再加一个步长，都是手动输入框（不给加减步进器）；
 * 输入框里空着就是用默认值（默认值写在占位字里）。改过的项按 base 存进 st.orderFlowOverrides，随账号同步；
 * 存完立刻让数据层换门槛，梯子、大单带、大单列表下一帧就按新门槛重算。
 */
import { st, save } from '../app/store'
import { $ } from '../ui/dom'
import { dialog, head, toast } from '../ui/overlay'
import { defaultThresholds, normalizeOverride, productsOf, baseOfSymbol, parseAmount, THRESHOLD_RANGE, STEP_RANGE, MAX_OVERRIDES, type Override } from './settings'
import type { Product, Thresholds } from './types'
import { OF, amt, PRODUCT_FULL } from './state'

const PRODUCT_HINT: Record<Product, string> = {
  spot: '现货簿上一个价位的挂单不小于这个金额才算大单',
  usdtPerp: 'U 本位永续簿上的门槛',
  coinPerp: '币本位永续簿上的门槛',
  delivery: '交割合约簿上的门槛',
}

/** 这只品种此刻的默认门槛与步长（数据层在跑就用它的——含校准与服务端推的步长）。 */
function defaultsFor(symbol: string): { base: string; t: Thresholds } {
  const { base } = baseOfSymbol(symbol)
  const f = OF.feed
  if (f && f.base === base) {
    const t = f.defaults()
    if (t.step == null && f.model.thresholds.step != null && !(st.orderFlowOverrides[base]?.step)) t.step = f.model.thresholds.step
    return { base, t }
  }
  const api = OF.api
  return { base, t: defaultThresholds(base, api?.crypto(symbol) ?? true, api?.turnover(symbol) ?? null) }
}

const stepText = (v: number): string => String(+v.toPrecision(10))

export function openOrderFlowSettings(symbol: string): void {
  const { base, t } = defaultsFor(symbol)
  const own: Override = st.orderFlowOverrides[base] || {}
  const products = productsOf(t)
  const field = (id: string, label: string, value: string, ph: string, hint: string, suffix: string): string =>
    `<div class="field"><label for="${id}">${label}</label>
      <div class="input-wrap"><input id="${id}" class="input num" inputmode="decimal" spellcheck="false" autocomplete="off" value="${value}" placeholder="${ph}" data-tip="${hint}"><span class="suffix">${suffix}</span></div></div>`
  const d = dialog(`${head(`主力订单流 · ${base}`)}
    <div class="dialog-body">
      <div class="of-set-grid">
        ${products.map(p => field(`ofT_${p}`, `${PRODUCT_FULL[p]}门槛`, own[p] != null ? amt(own[p]) : '', `默认 ${amt(t[p])}`, PRODUCT_HINT[p], '美元')).join('')}
        ${field('ofStep', '价位步长', own.step != null ? stepText(own.step) : '', t.step != null ? `默认 ${stepText(t.step)}` : '默认按前一日收盘定', '挂单按这个价差并成一个价位，梯子和大单带的最小一格', '')}
      </div>
      <div class="faint of-set-note">空着就用默认值。金额可以写 500K、2.5M；改完三端同步，梯子、大单带、大单列表马上按新门槛重算。</div>
    </div>
    <div class="dialog-foot"><button class="btn ghost" id="ofSetReset" style="margin-right:auto">恢复默认</button><button class="btn ghost" data-close>取消</button><button class="btn primary" id="ofSetOk">保存</button></div>`,
  'alert-dlg of-set-dlg', { label: `主力订单流 ${base} 门槛与步长` })

  const apply = (o: Override | null): void => {
    const all = { ...st.orderFlowOverrides }
    if (o) all[base] = o; else delete all[base]
    // 条数有上限：超出时丢最早加的
    const keys = Object.keys(all)
    if (keys.length > MAX_OVERRIDES) for (const k of keys.slice(0, keys.length - MAX_OVERRIDES)) if (k !== base) delete all[k]
    st.orderFlowOverrides = all
    save()
    if (OF.feed && OF.feed.base === base) OF.feed.setOverride(o)
    OF.version++
    OF.api?.charts().forEach(c => { c.chart.dirty = true })
    d.close()
  }

  $('#ofSetOk', d.dlg).onclick = () => {
    const o: Override = {}
    for (const p of products) {
      const raw = $<HTMLInputElement>(`#ofT_${p}`, d.dlg).value.trim()
      if (!raw) continue
      const v = parseAmount(raw)
      if (v == null || v < THRESHOLD_RANGE[0] || v > THRESHOLD_RANGE[1]) { toast(`${PRODUCT_FULL[p]}门槛不对`, `要在 ${amt(THRESHOLD_RANGE[0])} 到 ${amt(THRESHOLD_RANGE[1])} 之间`, 'info', 2400); $<HTMLInputElement>(`#ofT_${p}`, d.dlg).select(); return }
      if (v !== t[p]) o[p] = v
    }
    const rs = $<HTMLInputElement>('#ofStep', d.dlg).value.trim().replace(/,/g, '')
    if (rs) {
      const v = +rs
      if (!(v >= STEP_RANGE[0] && v <= STEP_RANGE[1])) { toast('步长要是正数', '', 'info', 2000); $<HTMLInputElement>('#ofStep', d.dlg).select(); return }
      if (v !== t.step) o.step = v
    }
    apply(normalizeOverride(o))
    toast('已保存', `${base} 的门槛与步长`, 'check', 1600)
  }
  $('#ofSetReset', d.dlg).onclick = () => { apply(null); toast('已恢复默认', base, 'check', 1600) }
  d.dlg.addEventListener('keydown', e => { if (e.key === 'Enter') $('#ofSetOk', d.dlg).click() })
  d.dlg.querySelector<HTMLInputElement>('input')?.focus()
}
