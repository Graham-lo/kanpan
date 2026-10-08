/* Hkline Web · 画线设置（照 TradingView 画线设置弹窗：输入 / 样式 / 文本 / 坐标 / 可见范围 + 底部模板菜单）
 *
 * 只管把 chart/drawSettingsModel 算出的行画出来、把改动按 path 交回 applyEdit：哪把工具有哪几页、一页排哪些行都在那边。
 * 改了立即重画（和图表设置一样没有确认 / 取消）；点选类（勾选、下拉、色块）当场记一步撤销并同步，
 * 打字类（数字、文字、拖取色器）边改边画、改完（失焦 / 回车 / 松手）才记，关框时没记的补一步。锁定的线只读。
 */
import { st, save } from '../app/store'
import type { Drawing } from '../chart/chart'
import { toolName } from '../chart/drawTools'
import { joinHex, rgbaOf, splitHex } from '../chart/drawSpec'
import { TEMPLATE_MAX, TEMPLATE_NAME_MAX, applyPreset, factoryPreset, presetOf, type DrawTemplate } from '../chart/drawPreset'
import { DASH_OPTS, TAB_LABEL, WIDTHS, applyEdit, rowsOf, shInput, shParse, tabsOf, type Ctl, type Dash, type Row, type TabId } from '../chart/drawSettingsModel'
import { DS, fill } from '../terms'
import { I, esc, tgt } from '../ui/dom'
import { closeMenu, dialog, head, menu, menuFrom, type MenuItem } from '../ui/overlay'

export interface DrawSettingsHost {
  /** 这条线还在图上吗（撤销、换品种、别处删掉后就不在了：关框） */
  alive(): boolean
  /** 只重画（打字、拖取色器的过程中） */
  redraw(): void
  /** 记一步撤销、落盘、同步、刷新快捷条 */
  commit(): void
  /** K 线区是深底吗（成交量分布的出厂灰随底色变） */
  dark(): boolean
  /** 价格小数位（坐标页） */
  dec(): number
}

const TAB_ICON: Readonly<Record<TabId, string>> = { inputs: 'spec', style: 'palette', text: 'pencil', coords: 'measure', vis: 'eye' }
/** 调色板（照 TradingView 画线色板的常用色，和图表设置同一组） */
const SWATCHES = ['#F23645', '#FF9800', '#FFEB3B', '#4CAF50', '#089981', '#00BCD4', '#2962FF', '#673AB7', '#9C27B0', '#E91E63',
  '#FFFFFF', '#D1D4DC', '#B2B5BE', '#787B86', '#5D606B', '#434651', '#2A2E39', '#131722', '#000000', '#F7525F']
const DASH_SVG: Readonly<Record<Dash, string>> = {
  solid: '<path d="M2 8h20" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
  dashed: '<path d="M2 8h20" stroke="currentColor" stroke-width="2" stroke-dasharray="4 3"/>',
  dotted: '<path d="M2.5 8h19.5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-dasharray="0.1 4"/>',
}
const dashSvg = (k: Dash): string => `<svg class="ds-sample" viewBox="0 0 24 16" aria-hidden="true">${DASH_SVG[k]}</svg>`
const widthSvg = (w: number): string => { const h = Math.max(1, Math.min(6, w)); return `<svg class="ds-sample" viewBox="0 0 24 16" aria-hidden="true"><rect x="2" y="${8 - h / 2}" width="20" height="${h}" rx="${h / 2}" fill="currentColor"/></svg>` }

/** 最近一次停在哪一页（同一把工具再开回到这一页；这把没有这一页就落到样式） */
let lastTab: TabId = 'style'

export function openDrawSettings(d: Drawing, host: DrawSettingsHost): void {
  const tabs = tabsOf(d.type); if (!tabs.length) return
  let tab: TabId = tabs.includes(lastTab) ? lastTab : tabs.includes('style') ? 'style' : tabs[0]
  const name = toolName(d.type)
  let pending = false
  const dlgApi = dialog(`${head(esc(name))}<div class="body"><nav class="ind-side cs-side"><div class="ind-cats" role="tablist">${tabs.map(id =>
    `<button role="tab" data-ds-tab="${id}">${I(TAB_ICON[id])}<span>${esc(TAB_LABEL[id])}</span></button>`).join('')}</div></nav><div class="cs-pane ds-pane" role="tabpanel"></div></div>
    <div class="dialog-foot"><button class="cs-dd ds-tpl" data-ds-tpl aria-haspopup="menu"><span>${esc(DS.template)}</span>${I('chevronDown', 'icon-12')}</button></div>`,
  'ind-dlg cs-dlg ds-dlg', { center: true, label: name, onClose: () => { closePop(); if (pending) { pending = false; if (host.alive()) host.commit() } } })
  const dlg = dlgApi.dlg
  const pane = dlg.querySelector<HTMLElement>('.ds-pane')!
  const ro = (): boolean => !!d.locked
  /** 这一次画出来的控件（data-ci 是下标） */
  let ctls: Ctl[] = []

  // ---------------------------------------------------------------- 改
  /** 改一处：now = 当场记撤销；否则只重画、等改完再记 */
  function edit(path: string, v: unknown, now: boolean): boolean {
    if (!host.alive()) { dlgApi.close(); return false }
    if (!applyEdit(d, path, v)) return false
    host.redraw()
    if (now) { pending = false; host.commit() } else pending = true
    return true
  }
  function flush(): void { if (pending && host.alive()) { pending = false; host.commit() } }

  // ---------------------------------------------------------------- 画
  const dis = (): string => ro() ? ' disabled' : ''
  const reg = (c: Ctl): number => { ctls.push(c); return ctls.length - 1 }
  /** 色块底：半透明的垫一层棋盘格，看得出透明度 */
  const swatchCss = (hex: string): string => {
    const c = rgbaOf(hex)
    return splitHex(hex)[1] < 1 ? `linear-gradient(${c},${c}),repeating-conic-gradient(#B2B5BE 0 25%,#FFFFFF 0 50%) 0 0/8px 8px` : c
  }
  const swatchBg = (hex: string): string => esc(swatchCss(hex))
  /** 输入框里显示的值（坐标价格按这只品种的小数位） */
  function inputVal(c: Ctl): string {
    if (c.kind === 'num') return c.path.startsWith('pt.') ? c.value.toFixed(Math.max(0, Math.min(10, host.dec()))) : String(+c.value.toFixed(4))
    if (c.kind === 'text') return c.value
    if (c.kind === 'time') return shInput(c.value)
    return ''
  }
  function ctlHtml(c: Ctl, label: string): string {
    const i = reg(c)
    switch (c.kind) {
      case 'color': return `<button class="cs-color ds-color${c.value ? ' set' : ''}" data-ci="${i}" aria-label="${esc(label)}" data-tip="${esc(label)}"${dis()}><span class="swatch" style="background:${swatchBg(c.shown)}"></span></button>`
      case 'width': return `<button class="cs-dd ds-dd-w" data-ci="${i}" aria-haspopup="menu" aria-label="${esc(fill(DS.px, { n: c.value }))}"${dis()}>${widthSvg(c.value)}${I('chevronDown', 'icon-12')}</button>`
      case 'dash': return `<button class="cs-dd ds-dd-w" data-ci="${i}" aria-haspopup="menu" aria-label="${esc(DASH_OPTS.find(x => x[0] === c.value)?.[1] ?? '')}"${dis()}>${dashSvg(c.value)}${I('chevronDown', 'icon-12')}</button>`
      case 'enum': {
        const t = c.options.find(x => x[0] === c.value)?.[1] ?? c.value
        return `<button class="cs-dd" data-ci="${i}" aria-haspopup="menu" aria-label="${esc(label)}" style="min-width:${c.options.every(x => x[1].length <= 3) ? 72 : 112}px"${dis()}><span>${esc(t)}</span>${I('chevronDown', 'icon-12')}</button>`
      }
      case 'num': {
        const coord = c.path.startsWith('pt.')
        return `<label class="cs-num${coord ? ' ds-price' : ''}">${c.pre ? `<span>${esc(c.pre)}</span>` : ''}<input class="input" type="number" data-ci="${i}" data-path="${c.path}"${Number.isFinite(c.min) ? ` min="${c.min}"` : ''}${Number.isFinite(c.max) ? ` max="${c.max}"` : ''} step="${c.step || 'any'}" value="${esc(inputVal(c))}" aria-label="${esc(label)}"${dis()}>${c.unit ? `<span>${c.unit}</span>` : ''}</label>`
      }
      case 'toggle': return `<button class="ibtn xs ds-tg ds-tg-${c.icon}" data-ci="${i}" aria-pressed="${c.value}" aria-label="${esc(c.label)}" data-tip="${esc(c.label)}"${dis()}>${c.icon === 'bold' ? 'B' : 'I'}</button>`
      case 'text': return `<textarea class="input ds-text" data-ci="${i}" data-path="${c.path}" rows="3" placeholder="${esc(DS.textPh)}" aria-label="${esc(label)}"${dis()}>${esc(c.value)}</textarea>`
      case 'time': return `<input class="input ds-time" type="datetime-local" data-ci="${i}" data-path="${c.path}" value="${inputVal(c)}" aria-label="${esc(label)}"${dis()}>`
      case 'check': return ''
    }
  }
  const chkHtml = (c: Ctl & { kind: 'check' }, label: string): string =>
    `<button class="cs-chk" role="checkbox" data-ci="${reg(c)}" aria-checked="${c.value}"${dis()}><span class="check-box${c.value ? ' on' : ''}">${c.value ? I('check', 'icon-12') : ''}</span><span>${esc(label)}</span></button>`
  function rowHtml(r: Row): string {
    if (r.kind === 'group') return `<div class="cs-gh">${esc(r.label)}</div>`
    if (r.kind === 'levels') {
      const cells = r.rows.map((x, i) => {
        const p = `lv.${r.key}.${i}`
        const on = reg({ kind: 'check', path: p + '.on', value: x.on })
        const vc: Ctl = { kind: 'num', path: p + '.v', value: x.v, min: -1000, max: 1000, step: 0 }, v = reg(vc)
        const c = reg({ kind: 'color', path: p + '.c', value: x.c, shown: x.c || r.lineColor, alpha: false, clear: true })
        return `<div class="ds-lv${x.on ? '' : ' off'}"><button class="cs-chk ds-lv-chk" role="checkbox" data-ci="${on}" aria-checked="${x.on}" aria-label="${esc(r.label)} ${x.v}"${dis()}><span class="check-box${x.on ? ' on' : ''}">${x.on ? I('check', 'icon-12') : ''}</span></button>`
          + `<input class="input" type="number" data-ci="${v}" data-path="${p}.v" step="any" value="${inputVal(vc)}" aria-label="${esc(r.label)}"${dis()}>`
          + `<button class="cs-color ds-color${x.c ? ' set' : ''}" data-ci="${c}" aria-label="${esc(DS.color)}" data-tip="${esc(DS.color)}"${dis()}><span class="swatch" style="background:${swatchBg(x.c || r.lineColor)}"></span></button></div>`
      }).join('')
      return `<div class="cs-gh">${esc(r.label)}</div><div class="ds-levels">${cells}</div>`
    }
    const ctlH = r.ctls.map(c => ctlHtml(c, r.label)).join('')
    if (r.key === 'text') return `<div class="ds-textrow">${ctlH}</div>`
    const vis = r.key.startsWith('vis.')
    const right = vis ? ctlH.replace('</label><label', '</label><span class="ds-to" aria-hidden="true"></span><label') : ctlH
    if (r.check) return `<div class="cs-row">${chkHtml(r.check, r.label)}${right ? `<div class="cs-ctl">${right}</div>` : ''}</div>`
    return `<div class="cs-row"><span class="cs-lab">${esc(r.label)}</span><div class="cs-ctl">${right}</div></div>`
  }
  function render(): void {
    if (!host.alive()) { dlgApi.close(); return }
    dlg.querySelectorAll<HTMLElement>('[data-ds-tab]').forEach(b => { const on = b.dataset.dsTab === tab; b.setAttribute('aria-pressed', String(on)); b.setAttribute('aria-selected', String(on)) })
    const tplBtn = dlg.querySelector<HTMLButtonElement>('[data-ds-tpl]'); if (tplBtn) tplBtn.disabled = ro()
    const sc = pane.scrollTop, focus = (document.activeElement as HTMLElement | null)?.dataset?.path
    ctls = []
    pane.innerHTML = rowsOf(d, tab, { dark: host.dark() }).map(rowHtml).join('')
    pane.classList.toggle('ds-ro', ro())
    pane.scrollTop = sc
    if (focus) pane.querySelector<HTMLElement>(`[data-path="${focus}"]`)?.focus()
  }

  /** 打字类改完：只把各输入框的值换成收过的（越界收到上下限、下限顶上去的上限……），不整页重画——
   *  失焦紧接着点了别的控件时，整页重画会把那一下点击吞掉 */
  function patchValues(): void {
    const fresh = new Map<string, string>()
    for (const r of rowsOf(d, tab, { dark: host.dark() })) {
      if (r.kind === 'row') for (const c of r.ctls) { if (c.kind === 'num' || c.kind === 'text' || c.kind === 'time') fresh.set(c.path, inputVal(c)) }
      else if (r.kind === 'levels') r.rows.forEach((x, i) => fresh.set(`lv.${r.key}.${i}.v`, String(+x.v.toFixed(4))))
    }
    pane.querySelectorAll<HTMLInputElement | HTMLTextAreaElement>('[data-path]').forEach(el => { const v = fresh.get(el.dataset.path!); if (v != null && el.value !== v) el.value = v })
  }

  // ---------------------------------------------------------------- 下拉
  function ddMenu(btn: HTMLElement, c: Ctl): void {
    let items: MenuItem[] = []
    const pick = (v: unknown) => () => { edit(c.path, v, true); render() }
    if (c.kind === 'width') items = WIDTHS.map(w => ({ html: `<span class="dq-sample">${widthSvg(w)}</span>${esc(fill(DS.px, { n: w }))}`, check: true, checked: c.value === w, run: pick(w) }))
    else if (c.kind === 'dash') items = DASH_OPTS.map(([k, l]) => ({ html: `<span class="dq-sample">${dashSvg(k)}</span>${esc(l)}`, check: true, checked: c.value === k, run: pick(k) }))
    else if (c.kind === 'enum') items = c.options.map(([v, l]) => ({ label: l, check: true, checked: c.value === v, run: pick(v) }))
    menuFrom(btn, items, { width: Math.max(btn.offsetWidth, 140) })
  }

  // ---------------------------------------------------------------- 调色板：常用色 + 不透明度 + 自定义（系统取色器）+ 默认（回到出厂 / 跟画线色）
  let pop: HTMLElement | null = null
  const closePop = (): void => { if (!pop) return; pop.remove(); pop = null; flush() }
  function colorPop(btn: HTMLElement, c: Ctl & { kind: 'color' }): void {
    closePop()
    const [hex0, a0] = splitHex(c.shown)
    let hex = hex0, a = a0
    const p = document.createElement('div'); p.className = 'cs-pop ds-pop'
    const cur = (c.value || '').slice(0, 7).toUpperCase()
    p.innerHTML = `<div class="cs-pop-grid ds-pop-grid">${SWATCHES.map(x => `<button class="swatch-btn" data-pc="${x}" aria-pressed="${cur === x}" aria-label="${x}"><span class="swatch" style="background:${x}"></span></button>`).join('')}</div>`
      + (c.alpha ? `<div class="ds-alpha"><span>${esc(DS.opaque)}</span><input type="range" min="0" max="100" step="1" value="${Math.round(a * 100)}" aria-label="${esc(DS.opaque)}"><output>${Math.round(a * 100)}%</output></div>` : '')
      + `<div class="cs-pop-foot"><label class="btn sm">${esc(DS.custom)}<input type="color" value="${esc(hex.toLowerCase())}"></label>${c.clear ? `<button class="btn sm" data-pc=""${c.value ? '' : ' disabled'}>${esc(DS.follow)}</button>` : ''}</div>`
    dlg.appendChild(p); pop = p
    const r = btn.getBoundingClientRect(), dr = dlg.getBoundingClientRect()
    p.style.left = Math.max(8, Math.min(r.left - dr.left, dr.width - p.offsetWidth - 8)) + 'px'
    p.style.top = (r.bottom - dr.top + 6 + p.offsetHeight > dr.height - 8 ? Math.max(8, r.top - dr.top - p.offsetHeight - 6) : r.bottom - dr.top + 6) + 'px'
    const paint = (): void => { const sw = btn.querySelector<HTMLElement>('.swatch'); if (sw) sw.style.background = swatchCss(joinHex(hex, c.alpha ? a : 1)) }
    const val = (): string => joinHex(hex, c.alpha ? a : 1)
    p.addEventListener('click', e => {
      const b = tgt(e).closest<HTMLElement>('[data-pc]'); if (!b) return
      if (b.dataset.pc) { hex = b.dataset.pc; edit(c.path, val(), true) } else edit(c.path, '', true)
      pop = null; p.remove(); render()
    })
    const range = p.querySelector<HTMLInputElement>('input[type="range"]')
    range?.addEventListener('input', () => { a = +range.value / 100; p.querySelector('output')!.textContent = range.value + '%'; if (edit(c.path, val(), false)) paint() })
    range?.addEventListener('change', flush)
    const picker = p.querySelector<HTMLInputElement>('input[type="color"]')!
    picker.addEventListener('input', () => { hex = picker.value.toUpperCase(); if (edit(c.path, val(), false)) paint() })
    picker.addEventListener('change', () => { flush(); closePop(); render() })
  }

  // ---------------------------------------------------------------- 模板
  const templates = (): DrawTemplate[] => st.drawTemplates[d.type] ?? []
  function setTemplates(list: DrawTemplate[]): void {
    if (list.length) st.drawTemplates[d.type] = list; else delete st.drawTemplates[d.type]
    save()
  }
  function tplMenu(btn: HTMLElement): void {
    const list = templates(), full = list.length >= TEMPLATE_MAX
    const items: MenuItem[] = list.map((tp): MenuItem => ({
      label: tp.name, run: () => { if (!host.alive()) return; applyPreset(d, tp); host.redraw(); host.commit(); render() },
      trail: I('trash', 'icon-16'), trailTip: DS.deleteTemplate,
      trailRun: () => { setTemplates(templates().filter(x => x.name !== tp.name)); closeMenu(); tplMenu(btn) },
    }))
    if (list.length) items.push('-')
    items.push(
      { label: full ? fill(DS.templatesFull, { n: TEMPLATE_MAX }) : DS.saveAs, disabled: full, run: () => askName() },
      { label: DS.saveDefault, run: () => { st.drawDefaults[d.type] = presetOf(d, false); save() } },
      { label: DS.resetFactory, run: () => { if (!host.alive()) return; applyPreset(d, factoryPreset(d.type)); host.redraw(); host.commit(); render() } },
    )
    const r = btn.getBoundingClientRect()
    const m = menu(items, r.left, r.bottom + 4, { width: 220, returnFocus: btn })
    // 按钮在对话框底边：菜单往上开
    m.style.top = Math.max(8, r.top - m.offsetHeight - 4) + 'px'
    m.classList.add('ds-tpl-menu')
  }
  function askName(): void {
    const n = dialog(`${head(esc(DS.templateName))}<div class="dialog-body"><input class="input" type="text" maxlength="${TEMPLATE_NAME_MAX}" spellcheck="false" autocomplete="off" aria-label="${esc(DS.templateName)}"></div>
      <div class="dialog-foot"><button class="btn secondary" data-close>${esc(DS.cancel)}</button><button class="btn primary" data-ok disabled>${esc(DS.save)}</button></div>`, 'ds-name-dlg', { center: true, label: DS.templateName })
    const inp = n.dlg.querySelector<HTMLInputElement>('input')!, ok = n.dlg.querySelector<HTMLButtonElement>('[data-ok]')!
    const name = (): string => inp.value.trim()
    inp.addEventListener('input', () => { ok.disabled = !name() })
    const done = (): void => {
      const v = name(); if (!v || !host.alive()) return
      const rest = templates().filter(x => x.name !== v)
      if (rest.length >= TEMPLATE_MAX) return
      setTemplates([...rest, { name: v, ...presetOf(d, true) }])
      n.close()
    }
    ok.addEventListener('click', done)
    inp.addEventListener('keydown', e => { if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); done() } })
    setTimeout(() => inp.focus(), 0)
  }

  // ---------------------------------------------------------------- 事件
  dlg.addEventListener('mousedown', e => { if (pop && !pop.contains(e.target as Node)) closePop() }, true)
  dlg.addEventListener('keydown', e => { if (e.key === 'Escape' && pop) { e.stopPropagation(); closePop() } }, true)
  dlg.addEventListener('click', e => {
    const t = tgt(e)
    const tb = t.closest<HTMLElement>('[data-ds-tab]')
    if (tb) { flush(); tab = lastTab = tb.dataset.dsTab as TabId; closePop(); pane.scrollTop = 0; render(); return }
    const tp = t.closest<HTMLButtonElement>('[data-ds-tpl]'); if (tp) { if (!tp.disabled) tplMenu(tp); return }
    const el = t.closest<HTMLElement>('[data-ci]'); if (!el || (el as HTMLButtonElement).disabled || el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') return
    const c = ctls[+el.dataset.ci!]; if (!c) return
    if (c.kind === 'check' || c.kind === 'toggle') { edit(c.path, !c.value, true); render(); return }
    if (c.kind === 'color') { colorPop(el, c); return }
    if (c.kind === 'width' || c.kind === 'dash' || c.kind === 'enum') ddMenu(el, c)
  })
  // 打字类：边输边画，改完（change：失焦 / 回车 / 选完时间）才记一步撤销
  pane.addEventListener('input', e => {
    const i = e.target as HTMLInputElement | HTMLTextAreaElement
    const c = ctls[+(i.dataset.ci ?? -1)]; if (!c) return
    // 可见范围不边输边改：输「30」的那个「3」会先把下限顶下来
    if (c.kind === 'num' && !c.path.startsWith('vis.')) { if (i.value === '' || !Number.isFinite(Number(i.value))) return; edit(c.path, Number(i.value), false) }
    else if (c.kind === 'text') edit(c.path, i.value, false)
  })
  pane.addEventListener('change', e => {
    const i = e.target as HTMLInputElement | HTMLTextAreaElement
    const c = ctls[+(i.dataset.ci ?? -1)]; if (!c) return
    if (!host.alive()) { dlgApi.close(); return }
    if (c.kind === 'time') { const ms = shParse(i.value); if (ms != null) edit(c.path, ms, true) }
    if (c.kind === 'num' && c.path.startsWith('vis.') && i.value !== '' && Number.isFinite(Number(i.value))) edit(c.path, Number(i.value), true)
    flush(); patchValues()
  })
  render()
}
