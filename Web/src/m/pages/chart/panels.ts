/* 手机网页版 · 行情页的几张面板（照 iOS Panels/IndicatorPanel.swift、ChartPanel.swift、OrderFlow/OrderFlowEditor.swift）
 *
 * - 分析（周期条行尾「分析」）：画线 · 指标（在用 / 主图叠加 / 副图）· 对比 · 主力订单流 · 恢复这一组的默认。
 *   开关即时生效：改 st 再 save()，行情页订阅 store 重画图；面板自己也订阅，改完就地重绘。
 * - 指标参数编辑：全 app 唯一一处「按保存才生效」（一组参数要一起改，逐字生效图会乱跳）。
 * - 图表设置（行尾记号）：K 线画法 · 盘口 · 价格轴刻度。
 * - 添加对比：小搜索表（rankSearch），只存 st.compareSymbols。
 * - 主力订单流门槛：按保存生效，写 st.orderFlowOverrides[base] 并立刻推给数据口。
 */
import { st, save, subscribe } from '../../app/store'
import {
  FACTORY_PARAMS_IDS, MAX_COMPARE, cleanCompare, currentLayout, factoryLayout, sameValue,
  type CandleKind, type IndicatorId, type PriceMode, type OrderFlowOverride,
} from '../../app/prefs'
import { indicatorName, mainPalette, subPalette, paletteOffset, paramLabels, normalizedParams, defaultParams, lineNames } from '../../indicator/ids'
import { openSheet, type Sheet } from '../../ui/sheet'
import { registerTerms, termHTML, type Term } from '../../ui/hint'
import { reorderable } from '../../ui/reorder'
import { swipeRow, deleteAction } from '../../ui/swipeDelete'
import { toast } from '../../ui/toast'
import { el, esc } from '../../ui/dom'
import { icon, glyph } from '../../ui/icons'
import { S, rankSearch } from '../../../market'
import { badgeHTML, assetOf } from '../../model/badge'
import { baseOfSymbol, defaultThresholds, applyOverride, isValidBase } from '../../../orderflow/settings'
import type { Thresholds } from '../../../orderflow/types'
import {
  toggleOverlay, toggleSub, moveSub, sanitizeParam, clampParam, VARIABLE_PARAMS, MAX_VARIABLE_PARAMS,
  sanitizeAmount, clampAmount, mergeOverride, compactAmount, plainNumber, learnedAfterAxisPick, type OrderFlowField,
} from './logic'
import { TERMS, splitPair } from './header'
import type { PagePort } from './data'

// ───────────────────────────── 术语（照 iOS Glossary：只给读不出意思的短名挂问号）

const GLOSSARY: Term[] = [
  { id: 'vwap', title: '均价线 · 当日 VWAP', body: '从当天起点（上海时间 8 点）算起，按成交量加权的平均成交价。\n价格在它上方，说明今天进场的人多数在赚；在下方则多数在亏。' },
  { id: 'sar', title: '抛物线 · SAR', body: '一串跟着价格走的点，趋势走得越久，点追得越紧。\n点在 K 线下方看涨、在上方看跌；价格碰到点，点就翻到另一边。' },
  { id: 'longShortRatio', title: '多空比', body: '币安上持有多单的账户数除以持有空单的账户数。\n大于 1 是做多的人多；一边倒得太厉害时，行情常往反方向走。' },
  { id: 'takerRatio', title: '买卖比 · 主动买卖比', body: '主动买入的量除以主动卖出的量（主动 = 直接吃掉别人挂单的一方）。\n大于 1 说明买方更急着进场，小于 1 说明卖方更急着走。' },
  { id: 'basis', title: '基差', body: '合约价格比现货指数高出多少，按百分比画。\n为正说明合约比现货贵、市场偏乐观；为负则偏悲观。' },
  { id: 'cvd', title: '量差 · 累计成交量差', body: '每根 K 线里主动买减主动卖，从当天起点一路累加。\n线往上走，这一段是被买上去的；往下走，是被卖下去的。' },
  TERMS.threshold, TERMS.step, TERMS.scale,
]
const INDICATOR_TERM: Partial<Record<IndicatorId, string>> = { VWAP: 'vwap', SAR: 'sar', LSR: 'longShortRatio', TAKER: 'takerRatio', BASIS: 'basis', CVD: 'cvd' }
let termsReady = false
function ensureTerms(): void { if (!termsReady) { registerTerms(GLOSSARY); termsReady = true } }

// ───────────────────────────── 小件

/** 指标的色点（PanelSwatch：8×8、圆角 2；颜色照 PanelTheme.swatch：持仓量、布林带各自一色，
 *  超级趋势 / 抛物线 / 订单流取涨色，其余一律取调色板上自己的起始那一支，主图副图同一张调色板） */
export function swatchVar(id: IndicatorId): string {
  if (id === 'OI') return 'var(--k-oi)'
  if (id === 'BOLL') return 'var(--k-band)'
  if (id === 'ST' || id === 'SAR' || id === 'ORDERFLOW') return 'var(--k-up)'
  return `var(--palette-${paletteOffset(id) % 6})`
}
const dot = (color: string): string => `<i class="cp-dot" style="background:${color}"></i>`
const sw = (on: boolean, act: string, label: string): string =>
  `<button type="button" class="cp-switch${on ? ' on' : ''}" role="switch" aria-checked="${on}" aria-label="${esc(label)}" data-act="${esc(act)}"><i></i></button>`
const chevron = (): string => `<span class="cp-chev">${icon('chevronRight', 12)}</span>`
const gt = (text: string): string => `<div class="cp-gt">${esc(text)}</div>`
function seg<T extends string>(opts: readonly [string, T][], value: T, act: string): string {
  return `<div class="cp-seg" role="radiogroup">${opts.map(([t, v]) =>
    `<button type="button" class="cp-seg-opt${v === value ? ' on' : ''}" role="radio" aria-checked="${v === value}" data-act="${esc(act)}" data-v="${esc(v)}">${esc(t)}</button>`).join('')}</div>`
}
const OVERLAY_ROWS = mainPalette.filter(x => x !== 'ORDERFLOW') as IndicatorId[]
const SUB_ROWS = subPalette as readonly IndicatorId[]

/** 面板要从行情页拿的几样 */
export interface PanelContext {
  symbol(): string
  port(): PagePort | null
  /** 「开始画线」（先关面板再调） */
  onDraw(): void
}

/** 当前生效参数（按指标能直接下标取用的长度） */
const paramsOf = (id: IndicatorId): number[] => normalizedParams(id, st.params[id] ?? defaultParams(id))
const compareName = (key: string): string => {
  const sym = key.split('/').pop() ?? key
  const { base, quote } = splitPair(sym)
  return `${base}/${quote}`
}

// ───────────────────────────── 分析

export function openAnalysis(ctx: PanelContext): Sheet {
  ensureTerms()
  let off: (() => void) | null = null
  let reorder: { destroy(): void } | null = null
  const sheet = openSheet(body => {
    const host = el('div', 'cp-panel')
    body.append(host)
    const render = (): void => { host.innerHTML = analysisHTML(ctx) }
    render()
    off = subscribe(() => { if (!sheet.closed) render() })
    host.addEventListener('click', e => {
      const b = (e.target as Element).closest<HTMLElement>('[data-act]')
      if (!b || b.hasAttribute('disabled')) return
      const [act, arg] = (b.dataset.act || '').split(':') as [string, string | undefined]
      const id = arg as IndicatorId
      switch (act) {
        case 'draw': sheet.close(); ctx.onDraw(); break
        case 'edit': openIndicatorEditor(id); break
        case 'height': delete st.subHeightOverrides[id]; save(); break
        case 'ov': st.overlays = toggleOverlay(st.overlays, id); save(); break
        case 'sub': {
          const r = toggleSub(st.subs, id)
          st.subs = r.list
          save()
          if (r.dropped) toast(`副图最多三个 · 已换下 ${indicatorName(r.dropped)}`)
          break
        }
        // 照 iOS compareSection：加、移除、清除都先收起面板（对比画在图上，要让人马上看到）
        case 'cmp-add': sheet.close(); openComparePicker(ctx); break
        case 'cmp-rm': st.compareSymbols = st.compareSymbols.filter(k => k !== arg); save(); sheet.close(); break
        case 'cmp-clear': st.compareSymbols = []; save(); sheet.close(); break
        case 'of': st.orderFlow = !st.orderFlow; save(); break
        case 'of-edit': openOrderFlowEditor(ctx); break
        case 'reset': resetLayout(); break
      }
    })
    reorder = reorderable(host, {
      item: '.cp-iu[data-sub]', handle: '.cp-grip',
      onMove(from, to) { if (from !== to) { st.subs = moveSub(st.subs, from, to); save() } },
    })
  }, { title: '分析', detent: 'medium', dim: 'large', id: 'analysis', className: 'cp-sheet cp-list', onClose: () => { off?.(); reorder?.destroy() } })
  return sheet
}

function analysisHTML(ctx: PanelContext): string {
  const out: string[] = []
  out.push(gt('画线'))
  out.push(`<div class="cp-group"><button type="button" class="cp-row cp-tap" data-act="draw"><span class="cp-rn">开始画线</span><span class="cp-drawglyph">${glyph('draw', 24)}</span></button></div>`)

  const overlays = st.overlays.filter(x => x !== 'ORDERFLOW')
  const inUse = overlays.length > 0 || st.subs.length > 0
  const handles = st.subs.length > 0
  if (inUse) {
    out.push(gt('指标'))
    const rows: string[] = []
    const line = (id: IndicatorId, sub: boolean): string => {
      const params = paramsOf(id).join(' · ')
      const resized = sub && st.subHeightOverrides[id] != null
      return `<div class="cp-iu"${sub ? ` data-sub="${id}"` : ''}>
        <button type="button" class="cp-iu-main" data-act="edit:${id}" aria-label="${esc(params ? `${indicatorName(id)}，${params}` : indicatorName(id))}">
          <span class="cp-rn">${dot(swatchVar(id))}${esc(indicatorName(id))}</span>
          ${params ? `<span class="cp-meta num">${esc(params)}</span>` : '<span></span>'}${chevron()}
        </button>
        ${resized ? `<button type="button" class="cp-reheight" data-act="height:${id}">还原高度</button>` : ''}
        ${sub ? `<span class="cp-grip" aria-label="拖动换序">${icon('grip', 16)}</span>` : handles ? '<span class="cp-grip cp-grip-pad" aria-hidden="true"></span>' : ''}
      </div>`
    }
    for (const id of overlays) rows.push(line(id, false))
    for (const id of st.subs) rows.push(line(id, true))
    out.push(`<div class="cp-inuse">${rows.join('')}</div>`)
  }
  const toggleRow = (id: IndicatorId, on: boolean, act: string): string => {
    const term = INDICATOR_TERM[id]
    return `<div class="cp-row"><span class="cp-rn">${dot(swatchVar(id))}${esc(indicatorName(id))}${term ? termHTML(term) : ''}</span>${sw(on, `${act}:${id}`, indicatorName(id))}</div>`
  }
  out.push(gt(inUse ? '主图叠加' : '指标 · 主图叠加'))
  out.push(`<div class="cp-group">${OVERLAY_ROWS.map(id => toggleRow(id, st.overlays.includes(id), 'ov')).join('')}</div>`)
  out.push(gt('副图 · 最多三个 · 成交量不占'))
  out.push(`<div class="cp-group">${SUB_ROWS.map(id => toggleRow(id, st.subs.includes(id), 'sub')).join('')}</div>`)

  out.push(gt('对比'))
  const cmp: string[] = []
  cmp.push(`<button type="button" class="cp-row cp-tap" data-act="cmp-add"${st.compareSymbols.length >= MAX_COMPARE ? ' disabled' : ''}><span class="cp-rn">添加对比</span>${chevron()}</button>`)
  for (const k of st.compareSymbols) cmp.push(`<div class="cp-row"><span class="cp-rn">${esc(compareName(k))}</span><button type="button" class="cp-textbtn" data-act="cmp-rm:${esc(k)}">移除</button></div>`)
  if (st.compareSymbols.length) cmp.push(`<button type="button" class="cp-row cp-tap" data-act="cmp-clear"><span class="cp-rn">清除对比</span></button>`)
  out.push(`<div class="cp-group">${cmp.join('')}</div>`)

  out.push(gt(indicatorName('ORDERFLOW')))
  const base = baseOfSymbol(ctx.symbol()).base
  const of: string[] = [`<div class="cp-row"><span class="cp-rn">${dot(swatchVar('ORDERFLOW'))}显示</span>${sw(st.orderFlow, 'of', '显示主力订单流')}</div>`]
  if (st.orderFlow && isValidBase(base)) {
    const meta = `${base} · ${st.orderFlowOverrides[base] ? '已改门槛' : '默认门槛'}`
    of.push(`<button type="button" class="cp-row cp-tap" data-act="of-edit" aria-label="门槛，${esc(meta)}"><span class="cp-rn">门槛${termHTML('threshold')}</span><span class="cp-meta num">${esc(meta)}</span>${chevron()}</button>`)
  }
  out.push(`<div class="cp-group">${of.join('')}</div>`)

  const factory = sameValue(currentLayout(st), factoryLayout())
  out.push(`<div class="cp-group cp-reset"><button type="button" class="cp-row cp-tap" data-act="reset"${factory ? ' disabled' : ''}><span class="cp-rn">恢复默认指标</span></button></div>`)
  return out.join('')
}

/** 「恢复默认指标」（PrefsStore.resetIndicatorLayout）：指标布局整份回到出厂（所有周期共用这一份），可撤销 */
function resetLayout(): void {
  const before = currentLayout(st)
  Object.assign(st, factoryLayout())
  save()
  toast('已恢复默认指标', { title: '撤销', run: () => { Object.assign(st, before); save() } })
}

// ───────────────────────────── 参数编辑

export const LINE_COLORS = ['#E2B34F', '#4A90E2', '#A078D0', '#37A78F', '#E46A76', '#D88040', '#B8C4D8']

/** 颜色那一行（照 iOS DrawingColorControl，指标参数与画线样式共用）：名字 + 右端系统取色圈（显示当前色），
 *  下面一排 22 的色卡、点击区 44；正好是色卡里那一色时它外面一圈墨色。
 *  act / pick：色卡的 data-act 与取色器的 data-pick */
export function colorControlHTML(name: string, cur: string, act: string, pick: string): string {
  const c = cur.slice(0, 7).toUpperCase()
  return `<div class="cp-crow"><div class="cp-crow-top"><span class="cp-rn">${esc(name)}</span>
      <label class="cp-cpick" style="--c:${c}" aria-label="${esc(name)} · 自选颜色"><input type="color" data-pick="${esc(pick)}" value="${c.toLowerCase()}"></label></div>
    <div class="cp-chips-c">${LINE_COLORS.map(col =>
      `<button type="button" class="cp-cchip${col === c ? ' on' : ''}" style="--c:${col}" data-act="${esc(act)}" data-c="${col}" aria-label="颜色 ${col}"></button>`).join('')}</div></div>`
}
/** 拖取色盘时只改这一行的取色圈与选中圈，不整块重写（重写会把正开着的取色器那个 input 拆掉） */
export function syncColorControl(input: HTMLInputElement, color: string): void {
  const row = input.closest<HTMLElement>('.cp-crow')
  input.closest<HTMLElement>('.cp-cpick')?.style.setProperty('--c', color)
  row?.querySelectorAll<HTMLElement>('.cp-cchip').forEach(b => b.classList.toggle('on', b.dataset.c === color))
}

/** 任意 CSS 颜色 → #RRGGBB（读令牌的默认色用） */
function toHex(css: string): string {
  const c = document.createElement('canvas').getContext('2d')
  if (!c) return '#E2B34F'
  c.fillStyle = '#000'
  c.fillStyle = css.trim() || '#000'
  const v = String(c.fillStyle)
  if (/^#[0-9a-f]{6}$/i.test(v)) return v.toUpperCase()
  const m = v.match(/(\d+(?:\.\d+)?)/g)
  if (!m || m.length < 3) return '#E2B34F'
  return '#' + m.slice(0, 3).map(x => Math.round(+x).toString(16).padStart(2, '0')).join('').toUpperCase()
}
function defaultLineColor(id: IndicatorId, i: number): string {
  const n = (i + paletteOffset(id)) % 6
  return toHex(getComputedStyle(document.documentElement).getPropertyValue(`--palette-${n}`))
}

export function openIndicatorEditor(id: IndicatorId): Sheet {
  ensureTerms()
  const variable = VARIABLE_PARAMS.includes(id)
  const hasColors = id === 'MA' || id === 'EMA' || id === 'VWAP'
  const draft = { params: paramsOf(id), colors: { ...(st.indicatorColors[id] ?? {}) } as Record<string, string> }
  const labels = paramLabels(id)
  const label = (i: number): string => (variable ? `周期${i + 1}` : labels[i] ?? `参数${i + 1}`)
  let host: HTMLElement
  const swipes: { destroy(): void }[] = []

  /** 把框里正在打的字收进 draft */
  const commitFields = (): void => {
    host.querySelectorAll<HTMLInputElement>('input[data-param]').forEach(inp => {
      const i = +inp.dataset.param!
      const v = clampParam(inp.value)
      if (v != null) draft.params[i] = v
    })
  }
  const render = (): void => {
    swipes.splice(0).forEach(s => s.destroy())
    const rows = draft.params.map((v, i) => `<div class="cp-prow" data-i="${i}"><div class="m-sw-content cp-prow-in">
      <label class="cp-rn" for="cp-param-${i}">${esc(label(i))}</label>
      <input id="cp-param-${i}" class="cp-field num" data-param="${i}" type="text" inputmode="numeric" pattern="[0-9]*" maxlength="3" autocomplete="off" enterkeyhint="done" value="${v}" aria-label="${esc(label(i))}">
    </div></div>`).join('')
    const add = variable && draft.params.length < MAX_VARIABLE_PARAMS ? '<button type="button" class="cp-row cp-tap cp-accent" data-act="add">添加周期</button>' : ''
    let colors = ''
    if (hasColors) {
      const names = lineNames(id, draft.params)
      colors = gt('线条颜色') + `<div class="cp-group">${names.map((name, i) =>
        colorControlHTML(name, draft.colors[i] ?? defaultLineColor(id, i), `color:${i}`, String(i))).join('')}<button type="button" class="cp-row cp-tap cp-accent" data-act="colors-reset">恢复默认颜色</button></div>`
    }
    host.innerHTML = (draft.params.length ? gt('参数') + `<div class="cp-group cp-params">${rows}${add}</div>` : '') + colors
    if (variable && draft.params.length > 1) {
      host.querySelectorAll<HTMLElement>('.cp-prow').forEach(row => {
        swipes.push(swipeRow(row, { trailing: [deleteAction(() => { commitFields(); draft.params.splice(+row.dataset.i!, 1); render() })], brick: 'flush' }))
      })
    }
  }
  const sheet = openSheet((body, sh) => {
    host = el('div', 'cp-panel cp-editor')
    body.append(host)
    render()
    host.addEventListener('input', e => {
      const t = e.target as HTMLInputElement
      if (t.dataset.param != null) { const c = sanitizeParam(t.value); if (c !== t.value) t.value = c }
      else if (t.dataset.pick != null) { draft.colors[t.dataset.pick] = t.value.toUpperCase(); syncColorControl(t, t.value.toUpperCase()) }
    })
    host.addEventListener('focusin', e => { const t = e.target as HTMLInputElement; if (t.dataset.param != null) setTimeout(() => t.select(), 0) })
    host.addEventListener('focusout', e => {
      const t = e.target as HTMLInputElement
      if (t.dataset.param == null) return
      const v = clampParam(t.value)
      const i = +t.dataset.param
      if (v != null) draft.params[i] = v
      t.value = String(draft.params[i])
    })
    host.addEventListener('click', e => {
      const b = (e.target as Element).closest<HTMLElement>('[data-act]')
      if (!b) return
      const [act, arg] = (b.dataset.act || '').split(':')
      if (act === 'add') {
        commitFields()
        const last = draft.params[draft.params.length - 1] ?? 5
        draft.params.push(Math.min(400, Math.max(1, last * 2)))
        render()
        host.querySelector<HTMLInputElement>(`input[data-param="${draft.params.length - 1}"]`)?.focus()
      } else if (act === 'color') { commitFields(); draft.colors[arg] = b.dataset.c!; render() }
      else if (act === 'colors-reset') { commitFields(); draft.colors = {}; render() }
    })
    const lead = sh.root.querySelector('.m-sheet-lead') // build 里 sheet 还没赋上，用回调给的那个
    if (lead) {
      const cancel = el('button', 'cp-cancel', '取消')
      cancel.type = 'button'
      cancel.addEventListener('click', () => sheet.close())
      lead.replaceWith(cancel)
    }
  }, {
    // 照 iOS IndicatorEditor：整页表单（页面底色上一张张白卡），顶上「取消 · 标题居中 · 保存」
    title: indicatorName(id), noBack: true, detent: 'large', className: 'cp-sheet cp-form', id: 'indicator-editor',
    action: {
      title: '保存', run: () => {
        commitFields()
        const params = draft.params.slice()
        const def = defaultParams(id)
        if (params.length && !sameValue(params, def)) st.params = { ...st.params, [id]: params }
        else {
          const next = { ...st.params }
          if (FACTORY_PARAMS_IDS.includes(id)) next[id] = def.slice(); else delete next[id]
          st.params = next
        }
        if (hasColors) {
          const colors: Record<string, string> = {}
          for (const [k, v] of Object.entries(draft.colors)) if (+k < draft.params.length || id === 'VWAP') colors[k] = v
          const next = { ...st.indicatorColors }
          if (Object.keys(colors).length) next[id] = colors; else delete next[id]
          st.indicatorColors = next
        }
        save()
        sheet.close()
      },
    },
    onClose: () => swipes.forEach(s => s.destroy()),
  })
  return sheet
}

// ───────────────────────────── 图表设置

const KINDS: readonly [string, CandleKind][] = [['蜡烛', 'candle'], ['平均K线', 'heikin'], ['收盘价', 'line']]
const SCALES: readonly [string, PriceMode][] = [['线性', 'linear'], ['对数', 'log'], ['百分比', 'percent']]

/** 图表设置要从行情页拿的：图上真正用的价格轴（学到的那档可能盖过设置）与这只的习惯类别 */
export interface AxisContext {
  mode(): PriceMode
  category(): string
}

export function openChartSettings(axis: AxisContext): Sheet {
  ensureTerms()
  let off: (() => void) | null = null
  const sheet = openSheet(body => {
    const host = el('div', 'cp-panel')
    body.append(host)
    const render = (): void => {
      host.innerHTML = gt('K 线') + `<div class="cp-group"><div class="cp-row"><span class="cp-rn">画法</span>${seg(KINDS, st.candleKind, 'kind')}</div></div>`
        + gt('显示') + `<div class="cp-group"><div class="cp-row"><span class="cp-rn">盘口</span>${sw(st.depth, 'depth', '盘口')}</div></div>`
        + gt('价格轴') + `<div class="cp-group"><div class="cp-row"><span class="cp-rn">刻度${termHTML('scale')}</span>${seg(SCALES, axis.mode(), 'scale')}</div></div>`
    }
    render()
    off = subscribe(() => { if (!sheet.closed) render() })
    host.addEventListener('click', e => {
      const b = (e.target as Element).closest<HTMLElement>('[data-act]')
      if (!b) return
      const act = b.dataset.act
      if (act === 'kind') st.candleKind = b.dataset.v as CandleKind
      else if (act === 'scale') {
        // 照 iOS：分段显示图上真正用的那档；亲手切线性 / 对数时这一类学到的结论当场换成它，不然学到的那档会把选择盖回去
        const mode = b.dataset.v as PriceMode
        const learned = learnedAfterAxisPick(st.learnedDefaults.priceAxis, st.habitLearning, axis.category(), mode, Date.now() / 1000)
        if (learned) st.learnedDefaults = { ...st.learnedDefaults, priceAxis: learned }
        st.priceMode = mode
      }
      else if (act === 'depth') st.depth = !st.depth
      else return
      save()
    })
  }, { title: '图表设置', detent: 'medium', dim: 'large', id: 'chart-settings', className: 'cp-sheet cp-list', onClose: () => off?.() })
  return sheet
}

// ───────────────────────────── 添加对比

export function openComparePicker(ctx: PanelContext): Sheet {
  const taken = new Set(st.compareSymbols.map(k => k.split('/').pop()))
  return openSymbolPicker({
    title: '添加对比', id: 'compare-picker',
    accept: sym => sym !== ctx.symbol() && !taken.has(sym) && /USDT$/.test(sym),
    onPick: sym => { st.compareSymbols = cleanCompare([...st.compareSymbols, 'binance/usd_m/' + sym]); save() },
  })
}

/** 挑一只品种的小表（对比、画线台换品种共用）：空搜索列自选里的，再按 24h 成交额补满；有字按 rankSearch */
export function openSymbolPicker(o: { title: string; id: string; accept(sym: string): boolean; onPick(sym: string): void; current?: string }): Sheet {
  const sheet = openSheet(body => {
    const host = el('div', 'cp-panel cp-cmp')
    host.innerHTML = `<div class="cp-cmp-search">${icon('search', 16)}<input type="search" enterkeyhint="search" placeholder="搜 BTC、ETH、SOL…" autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false" lang="en" inputmode="latin" aria-label="搜索品种"></div><div class="cp-cmp-list"></div>`
    body.append(host)
    const input = host.querySelector('input')!
    const list = host.querySelector<HTMLElement>('.cp-cmp-list')!
    const draw = (): void => {
      const pool = [...S.symbols.values()].filter(s => o.accept(s.symbol))
      const q = input.value.trim()
      const fav = new Set(st.symbols.favorites)
      let rows = q ? rankSearch(pool, q, k => fav.has(k), 40)
        : [...pool.filter(s => fav.has(s.symbol)), ...pool.filter(s => !fav.has(s.symbol)).sort((a, b) => (b.vol || 0) - (a.vol || 0))].slice(0, 40)
      rows = rows.slice(0, 40)
      list.innerHTML = rows.length ? rows.map(s => {
        const { base, quote } = splitPair(s.symbol)
        return `<button type="button" class="cp-row cp-tap cp-cmp-row${s.symbol === o.current ? ' on' : ''}" data-sym="${esc(s.symbol)}">
          <span class="cp-rn">${badgeHTML(s.base, 24, assetOf(s.kind, s.base))}<b>${esc(base)}</b><small>/${esc(quote)}</small></span>${chevron()}</button>`
      }).join('') : '<div class="cp-empty">没有找到</div>'
    }
    draw()
    input.addEventListener('input', draw)
    list.addEventListener('click', e => {
      const b = (e.target as Element).closest<HTMLElement>('[data-sym]')
      if (!b) return
      o.onPick(b.dataset.sym!)
      sheet.close()
    })
  }, { title: o.title, detent: 'large', id: o.id, className: 'cp-sheet' })
  return sheet
}

// ───────────────────────────── 主力订单流门槛

const PRODUCT_LABEL: Record<'spot' | 'usdtPerp' | 'coinPerp' | 'delivery', string> = { spot: '现货', usdtPerp: 'U本位永续', coinPerp: '币本位永续', delivery: '交割' }
const PRODUCTS = ['spot', 'usdtPerp', 'coinPerp', 'delivery'] as const

/** 这只的默认与生效门槛：数据口有就用它的（按成交额分过档），还没到就按品种事实查表 */
function thresholdsFor(ctx: PanelContext, base: string): { defaults: Thresholds; effective: Thresholds } {
  const port = ctx.port()
  const sym = ctx.symbol()
  const m = S.symbols.get(sym)
  const table = defaultThresholds(base, (m?.kind ?? 'crypto') === 'crypto', m?.vol ?? null)
  const defaults = port?.defaults ?? table
  const effective = port?.thresholds ?? applyOverride(defaults, st.orderFlowOverrides[base] as OrderFlowOverride | undefined)
  return { defaults, effective }
}

export function openOrderFlowEditor(ctx: PanelContext): Sheet {
  ensureTerms()
  const base = baseOfSymbol(ctx.symbol()).base
  const edited: Partial<Record<OrderFlowField, number>> = {}
  let resetting = false
  let host: HTMLElement
  const shownValue = (f: OrderFlowField): number | undefined => {
    const { defaults, effective } = thresholdsFor(ctx, base)
    return resetting ? (edited[f] ?? defaults[f] ?? effective[f]) : (edited[f] ?? effective[f])
  }
  const row = (f: OrderFlowField, label: string, term: string | null, amount: boolean): string => {
    const v = shownValue(f)
    const text = v != null ? plainNumber(v) : ''
    return `<div class="cp-row cp-ofrow"><span class="cp-rn">${esc(label)}${term ? termHTML(term) : ''}</span>
      ${amount ? `<span class="cp-meta num" data-compact="${f}">${v != null ? esc(compactAmount(v)) : ''}</span>` : ''}
      <input class="cp-field cp-field-wide num" data-f="${f}" type="text" inputmode="decimal" autocomplete="off" enterkeyhint="done" placeholder="自动" value="${esc(text)}" aria-label="${esc(label)}"></div>`
  }
  const render = (): void => {
    const { effective } = thresholdsFor(ctx, base)
    const products = PRODUCTS.filter(p => effective[p] != null)
    const changed = !resetting && st.orderFlowOverrides[base] != null
    host.innerHTML = gt(`${base} · 过滤门槛`) + `<div class="cp-group">${products.map(p => row(p, PRODUCT_LABEL[p], null, true)).join('')}</div>`
      + `<div class="cp-group cp-gap">${row('step', '步长', 'step', false)}${changed ? '<button type="button" class="cp-row cp-tap cp-accent" data-act="reset">恢复默认</button>' : ''}</div>`
  }
  const commit = (inp: HTMLInputElement): void => {
    const f = inp.dataset.f as OrderFlowField
    const v = Number(sanitizeAmount(inp.value))
    if (inp.value.trim() && Number.isFinite(v) && v > 0) edited[f] = clampAmount(v, f)
    const shown = shownValue(f)
    inp.value = shown != null ? plainNumber(shown) : ''
  }
  const sheet = openSheet((body, sh) => {
    host = el('div', 'cp-panel cp-editor')
    body.append(host)
    render()
    host.addEventListener('input', e => {
      const t = e.target as HTMLInputElement
      if (!t.dataset.f) return
      const c = sanitizeAmount(t.value)
      if (c !== t.value) t.value = c
      const meta = host.querySelector<HTMLElement>(`[data-compact="${t.dataset.f}"]`)
      if (meta) { const n = Number(c); meta.textContent = c && n > 0 ? compactAmount(n) : '' }
    })
    host.addEventListener('focusin', e => { const t = e.target as HTMLInputElement; if (t.dataset.f) setTimeout(() => t.select(), 0) })
    host.addEventListener('focusout', e => { const t = e.target as HTMLInputElement; if (t.dataset.f) commit(t) })
    host.addEventListener('click', e => {
      if ((e.target as Element).closest('[data-act="reset"]')) { resetting = true; for (const k of Object.keys(edited)) delete edited[k as OrderFlowField]; render() }
    })
    const lead = sh.root.querySelector('.m-sheet-lead') // build 里 sheet 还没赋上，用回调给的那个
    if (lead) {
      const cancel = el('button', 'cp-cancel', '取消')
      cancel.type = 'button'
      cancel.addEventListener('click', () => sheet.close())
      lead.replaceWith(cancel)
    }
  }, {
    title: indicatorName('ORDERFLOW'), noBack: true, detent: 'large', className: 'cp-sheet cp-form', id: 'orderflow-editor',
    action: {
      title: '保存', run: () => {
        host.querySelectorAll<HTMLInputElement>('input[data-f]').forEach(commit)
        const { defaults } = thresholdsFor(ctx, base)
        const merged = mergeOverride(defaults, resetting ? null : st.orderFlowOverrides[base], edited)
        const next = { ...st.orderFlowOverrides }
        if (Object.keys(merged).length) next[base] = merged; else delete next[base]
        st.orderFlowOverrides = next
        save()
        ctx.port()?.setOverride(next[base] ?? null)
        sheet.close()
      },
    },
  })
  return sheet
}
