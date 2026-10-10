/* Hkline Web · 图表设置（照 TradingView「图表设置」：商品 / 状态栏 / 比例尺与线 / 画布 四页）
 * 改了立即生效、十六格同一份、跟人走（store + 账号同步 webChart）；底部只有「恢复默认」，Esc 关 */
import { st, save } from '../app/store'
import { I, esc, tgt } from '../ui/dom'
import { dialog, head, menuFrom, type MenuItem } from '../ui/overlay'
import type { ThemeColors } from '../chart/chart'
import {
  DATE_FMTS, DEFAULTS, GRID_MODES, LIMITS, LINE_STYLES, TITLE_MODES,
  clean, dateText, type ChartSettings,
} from '../chart/chartSettings'

type Tab = 'symbol' | 'status' | 'scales' | 'canvas'
const TABS: [Tab, string, string][] = [['symbol', '商品', 'candles'], ['status', '状态栏', 'info'], ['scales', '比例尺与线', 'spec'], ['canvas', '画布', 'palette']]
const SWATCHES = ['#089981', '#26A69A', '#4CAF50', '#2962FF', '#00BCD4', '#9C27B0', '#F23645', '#EF5350', '#FF9800', '#F59E0B', '#FFEB3B', '#E91E63',
  '#FFFFFF', '#D1D4DC', '#B2B5BE', '#787B86', '#434651', '#2A2E39', '#1E222D', '#131722', '#000000']
type K = keyof ChartSettings
type BoolK = { [P in K]: ChartSettings[P] extends boolean ? P : never }[K]
type ColorK = 'bodyUp' | 'bodyDown' | 'borderUp' | 'borderDown' | 'wickUp' | 'wickDown' | 'bg' | 'bg2' | 'vertColor' | 'horzColor' | 'crossColor' | 'scaleText' | 'scaleLine'
type NumK = 'marginTop' | 'marginBottom' | 'rightBars' | 'legendBgOpacity' | 'watermarkOpacity'

export interface ChartSettingsHost { apply: () => void; base: () => ThemeColors | undefined }
let tab: Tab = 'symbol'

export function openChartSettings(host: ChartSettingsHost): void {
  const d = dialog(`${head('图表设置')}<div class="body"><nav class="ind-side cs-side"><div class="ind-cats" role="tablist">${TABS.map(([id, l, ic]) =>
    `<button role="tab" data-cs-tab="${id}">${I(ic)}<span>${l}</span></button>`).join('')}</div></nav><div class="cs-pane" role="tabpanel"></div></div>
    <div class="dialog-foot"><button class="btn" data-cs-reset>恢复默认</button></div>`, 'ind-dlg cs-dlg', { center: true, label: '图表设置' })
  const pane = d.dlg.querySelector<HTMLElement>('.cs-pane')!
  const S = (): ChartSettings => st.chartSettings
  const set = (patch: Partial<ChartSettings>, redraw = true): void => {
    st.chartSettings = clean({ ...st.chartSettings, ...patch }); save(); host.apply()
    if (redraw) render()
  }
  // 色块：没改过的显示当前皮肤下实际用的颜色
  const shown = (k: ColorK): string => {
    const v = S()[k]; if (v) return v
    const b = host.base(), up = getComputedStyle(document.documentElement)
    const css = (n: string): string => up.getPropertyValue(n).trim()
    switch (k) {
      case 'bodyUp': case 'borderUp': case 'wickUp': return b?.up || css('--up')
      case 'bodyDown': case 'borderDown': case 'wickDown': return b?.down || css('--down')
      case 'bg': return b?.bg || css('--bg')
      case 'bg2': return S().bg || b?.bg || css('--bg')
      case 'vertColor': case 'horzColor': return b?.grid || '#888'
      case 'crossColor': return b?.cross || '#888'
      case 'scaleText': return b?.text || '#888'
      case 'scaleLine': return b?.scaleLine || '#888'
    }
  }
  const color = (k: ColorK, tip: string): string =>
    `<button class="cs-color${S()[k] ? ' set' : ''}" data-color="${k}" aria-label="${esc(tip)}" data-tip="${esc(tip)}"><span class="swatch" style="background:${esc(shown(k))}"></span></button>`
  const chk = (k: BoolK, label: string, extra = ''): string =>
    `<div class="cs-row"><button class="cs-chk" role="checkbox" data-chk="${k}" aria-checked="${S()[k]}"><span class="check-box${S()[k] ? ' on' : ''}">${S()[k] ? I('check', 'icon-12') : ''}</span><span>${label}</span></button>${extra ? `<div class="cs-ctl">${extra}</div>` : ''}</div>`
  const row = (label: string, ctl: string): string => `<div class="cs-row"><span class="cs-lab">${label}</span><div class="cs-ctl">${ctl}</div></div>`
  const dd = (k: string, text: string, w = 120): string => `<button class="cs-dd" data-dd="${k}" style="min-width:${w}px" aria-haspopup="menu"><span>${esc(text)}</span>${I('chevronDown', 'icon-12')}</button>`
  const num = (k: NumK, unit: string, lo: number, hi: number, off = false): string =>
    `<label class="cs-num"><input class="input" type="number" data-num="${k}" min="${lo}" max="${hi}" step="1" value="${S()[k]}"${off ? ' disabled' : ''}><span>${unit}</span></label>`
  const seg = (k: string, v: string, opts: [string, string][]): string =>
    `<div class="seg" role="group">${opts.map(([x, l]) => `<button data-seg="${k}" data-v="${x}" aria-pressed="${v === x}">${l}</button>`).join('')}</div>`
  const gh = (t: string): string => `<div class="cs-gh">${t}</div>`
  const lbl = <T extends string>(list: [T, string][], v: T): string => list.find(x => x[0] === v)?.[1] ?? ''
  const precText = (p: number | null): string => p === null ? '默认' : p === 0 ? '1' : (1 / 10 ** p).toFixed(p)
  const SAMPLE = Date.UTC(2026, 8, 29, 6, 30)

  function body(): string {
    const s = S()
    if (tab === 'symbol') return gh('K 线')
      + chk('prevCloseColor', '按前一根收盘价着色')
      + chk('body', '实体', color('bodyUp', '实体 · 涨') + color('bodyDown', '实体 · 跌'))
      + chk('border', '边框', color('borderUp', '边框 · 涨') + color('borderDown', '边框 · 跌'))
      + chk('wick', '影线', color('wickUp', '影线 · 涨') + color('wickDown', '影线 · 跌'))
      + gh('价格线')
      + chk('lastLine', '最新价线', dd('lastLineStyle', lbl(LINE_STYLES, s.lastLineStyle), 96))
      + chk('hiloLine', '最高价和最低价线')
      + gh('数据修改')
      + row('精度', dd('precision', precText(s.precision)))
      + row('时区', `<span class="cs-ro">(UTC+8) 上海</span>`)
    if (tab === 'status') return gh('品种')
      + row('标题', dd('title', lbl(TITLE_MODES, s.title)))
      + chk('ohlc', '开高低收')
      + chk('barChange', 'K 线涨跌')
      + chk('volume', '成交量')
      + gh('指标')
      + chk('indTitles', '名称')
      + chk('indArgs', '参数')
      + chk('indValues', '数值')
      + gh('外观')
      + chk('legendBg', '背景', num('legendBgOpacity', '%', 0, 100, !s.legendBg))
    if (tab === 'scales') return gh('价格标签与线')
      + chk('lastLabel', '最新价标签')
      + chk('indLabels', '指标数值标签')
      + chk('hiloLabel', '最高价和最低价标签')
      + chk('prevClose', '昨日收盘价线与标签')
      + gh('时间')
      + chk('weekday', '星期')
      + row('日期格式', dd('dateFmt', dateText(SAMPLE, s.dateFmt), 140))
      + row('时间格式', seg('hour12', s.hour12 ? '12' : '24', [['24', '24 小时'], ['12', '12 小时']]))
    return gh('图表基本样式')
      + row('背景', dd('bgType', s.bgType === 'gradient' ? '渐变' : '纯色', 96) + color('bg', s.bgType === 'gradient' ? '背景 · 上' : '背景') + (s.bgType === 'gradient' ? color('bg2', '背景 · 下') : ''))
      + row('网格线', dd('grid', lbl(GRID_MODES, s.grid), 96) + (s.grid === 'both' || s.grid === 'vert' ? color('vertColor', '竖线') : '') + (s.grid === 'both' || s.grid === 'horz' ? color('horzColor', '横线') : ''))
      + row('十字光标', color('crossColor', '十字光标') + dd('crossWidth', `${s.crossWidth} 像素`, 88) + dd('crossStyle', lbl(LINE_STYLES, s.crossStyle), 88))
      + chk('watermark', '水印', num('watermarkOpacity', '%', 1, 100, !s.watermark))
      + gh('比例尺')
      + row('文字', color('scaleText', '比例尺文字'))
      + row('线', color('scaleLine', '比例尺线'))
      + gh('边距')
      + row('上边距', num('marginTop', '%', LIMITS.margin[0], LIMITS.margin[1]))
      + row('下边距', num('marginBottom', '%', LIMITS.margin[0], LIMITS.margin[1]))
      + row('右侧留白', num('rightBars', '根', LIMITS.rightBars[0], LIMITS.rightBars[1]))
  }
  function render(): void {
    d.dlg.querySelectorAll<HTMLElement>('[data-cs-tab]').forEach(b => { const on = b.dataset.csTab === tab; b.setAttribute('aria-pressed', String(on)); b.setAttribute('aria-selected', String(on)) })
    const sc = pane.scrollTop, focus = (document.activeElement as HTMLElement | null)?.dataset?.num
    pane.innerHTML = body()
    pane.scrollTop = sc
    if (focus) pane.querySelector<HTMLInputElement>(`[data-num="${focus}"]`)?.focus()
  }

  function ddMenu(btn: HTMLElement, k: string): void {
    const s = S()
    const opt = <T>(list: [T, string][], cur: T, apply: (v: T) => void): MenuItem[] => list.map(([v, l]) => ({ label: l, check: true, checked: v === cur, run: () => apply(v) }))
    let items: MenuItem[] = []
    if (k === 'lastLineStyle' || k === 'crossStyle') items = opt(LINE_STYLES, s[k], v => set({ [k]: v }))
    else if (k === 'precision') items = opt<number | null>([[null, '默认'], ...Array.from({ length: LIMITS.precision[1] + 1 }, (_, i) => [i, precText(i)] as [number, string])], s.precision, v => set({ precision: v }))
    else if (k === 'title') items = opt(TITLE_MODES, s.title, v => set({ title: v }))
    else if (k === 'dateFmt') items = opt(DATE_FMTS.map(f => [f, dateText(SAMPLE, f)] as [typeof f, string]), s.dateFmt, v => set({ dateFmt: v }))
    else if (k === 'bgType') items = opt<ChartSettings['bgType']>([['solid', '纯色'], ['gradient', '渐变']], s.bgType, v => set({ bgType: v }))
    else if (k === 'grid') items = opt(GRID_MODES, s.grid, v => set({ grid: v }))
    else if (k === 'crossWidth') items = opt([1, 2, 3, 4].map(w => [w, `${w} 像素`] as [number, string]), s.crossWidth, v => set({ crossWidth: v }))
    menuFrom(btn, items, { width: Math.max(btn.offsetWidth, 140) })
  }

  // 调色板：常用色 + 自定义（系统取色器，拖着就生效）+ 默认（跟皮肤 / 涨跌色走）
  let pop: HTMLElement | null = null
  const closePop = (): void => { pop?.remove(); pop = null }
  function colorPop(btn: HTMLElement, k: ColorK): void {
    closePop()
    const cur = S()[k]
    const p = document.createElement('div'); p.className = 'cs-pop'
    p.innerHTML = `<div class="cs-pop-grid">${SWATCHES.map(c => `<button class="swatch-btn" data-pc="${c}" aria-pressed="${cur === c}" aria-label="${c}"><span class="swatch" style="background:${c}"></span></button>`).join('')}</div>
      <div class="cs-pop-foot"><label class="btn sm">自定义<input type="color" value="${esc(shown(k).slice(0, 7).toLowerCase())}"></label><button class="btn sm" data-pc=""${cur ? '' : ' disabled'}>默认</button></div>`
    d.dlg.appendChild(p); pop = p
    const r = btn.getBoundingClientRect(), dr = d.dlg.getBoundingClientRect()
    p.style.left = Math.min(r.left - dr.left, dr.width - p.offsetWidth - 8) + 'px'
    p.style.top = (r.bottom - dr.top + 6 + p.offsetHeight > dr.height - 8 ? r.top - dr.top - p.offsetHeight - 6 : r.bottom - dr.top + 6) + 'px'
    p.addEventListener('click', e => {
      const b = tgt(e).closest<HTMLElement>('[data-pc]'); if (!b) return
      set({ [k]: b.dataset.pc || null }); closePop()
    })
    p.querySelector<HTMLInputElement>('input')!.addEventListener('input', e => {
      const v = (e.target as HTMLInputElement).value.toUpperCase()
      set({ [k]: v }, false)
      const sw = pane.querySelector<HTMLElement>(`[data-color="${k}"] .swatch`); if (sw) sw.style.background = v
    })
    p.querySelector<HTMLInputElement>('input')!.addEventListener('change', () => { closePop(); render() })
  }

  d.dlg.addEventListener('mousedown', e => { if (pop && !pop.contains(e.target as Node)) closePop() }, true)
  d.dlg.addEventListener('keydown', e => { if (e.key === 'Escape' && pop) { e.stopPropagation(); closePop() } }, true)
  d.dlg.addEventListener('click', e => {
    const t = tgt(e)
    const tb = t.closest<HTMLElement>('[data-cs-tab]'); if (tb) { tab = tb.dataset.csTab as Tab; closePop(); pane.scrollTop = 0; render(); return }
    if (t.closest('[data-cs-reset]')) { st.chartSettings = { ...DEFAULTS }; save(); host.apply(); render(); return }
    const c = t.closest<HTMLElement>('[data-chk]'); if (c) { const k = c.dataset.chk as BoolK; set({ [k]: !S()[k] }); return }
    const sg = t.closest<HTMLElement>('[data-seg]')
    if (sg) {
      if (sg.dataset.seg === 'hour12') set({ hour12: sg.dataset.v === '12' })
      return
    }
    const dv = t.closest<HTMLElement>('[data-dd]'); if (dv) { ddMenu(dv, dv.dataset.dd!); return }
    const cb = t.closest<HTMLElement>('[data-color]'); if (cb) { colorPop(cb, cb.dataset.color as ColorK); return }
  })
  // 数字：边输边生效（越界的按上下限收），离开输入框时把收过的值写回框里
  pane.addEventListener('input', e => {
    const i = e.target as HTMLInputElement; const k = i.dataset.num as NumK | undefined; if (!k || i.value === '') return
    let v = Number(i.value); if (!Number.isFinite(v)) return
    // 上下边距加起来不超过 80%：改哪个就收哪个，不去动另一个
    if (k === 'marginTop') v = Math.min(v, LIMITS.marginSum - S().marginBottom)
    if (k === 'marginBottom') v = Math.min(v, LIMITS.marginSum - S().marginTop)
    set({ [k]: v }, false)
  })
  pane.addEventListener('change', e => { if ((e.target as HTMLElement).dataset.num) render() })
  render()
}
