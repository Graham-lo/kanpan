/* 手机网页版 · 行情页的几张面板（照 iOS Panels/IndicatorPanel.swift、ChartPanel.swift、OrderFlow/OrderFlowEditor.swift）
 *
 * - 分析（周期条行尾「分析」）：画线（开始画线 · 隐藏画线）· 指标（在用 / 主图叠加 / 副图）· 对比 · 主力订单流 · 恢复这一组的默认。
 *   对比 10-05 搬到顶栏 ＋ 之后，10-06 用户要求两处并存（「分析里的对比要留」，照 iOS IndicatorPage.compareSection）：
 *   这一节的「添加对比」开的就是顶栏 ＋ 那张对比模式搜索页（pages/search.ts），共用同一份 compareSymbols；
 *   此刻不能对比（复盘回放、横屏画线台、看朋友分享的线）时整节不排。
 * - 主图指标（横屏画线台顶行「主图˅」，iOS IndicatorPage.mainOnly）：只有使用中的主图指标与主图叠加开关。
 *   开关即时生效：改 st 再 save()，行情页订阅 store 重画图；面板自己也订阅，改完就地重绘。
 * - 指标参数编辑：全 app 唯一一处「按保存才生效」（一组参数要一起改，逐字生效图会乱跳）。
 * - 图表设置（行尾记号）：K 线画法 · 盘口 · 价格轴刻度。
 * - 挑品种小表（rankSearch）：画线台换品种用。
 * - 主力订单流门槛：按保存生效，写 st.orderFlowOverrides[base] 并立刻推给数据口。
 */
import { st, save, subscribe } from '../../app/store'
import {
  FACTORY_PARAMS_IDS, MAX_COMPARE, currentLayout, factoryLayout, sameValue,
  type CandleKind, type IndicatorId, type PriceMode, type OrderFlowOverride,
} from '../../app/prefs'
import { indicatorName, mainPalette, subPalette, paletteOffset, paramLabels, normalizedParams, defaultParams, lineNames } from '../../indicator/ids'
import { openSheet, type Sheet } from '../../ui/sheet'
import { registerTerms, termHTML, type Term } from '../../ui/hint'
import { reorderable, type ReorderHandle } from '../../ui/reorder'
import { swipeRow, deleteAction } from '../../ui/swipeDelete'
import { toast } from '../../ui/toast'
import { el, esc } from '../../ui/dom'
import { icon, glyph } from '../../ui/icons'
import { S, rankSearch } from '../../../market'
import { badgeHTML, assetOf } from '../../model/badge'
import { lineSwatchOptions, swatchRoleName, type LineSwatch } from '../../model/lineSwatches'
import { baseOfSymbol, defaultThresholds, applyOverride, isValidBase } from '../../../orderflow/settings'
import type { Thresholds } from '../../../orderflow/types'
import {
  toggleOverlay, toggleSub, moveSubAmong, sanitizeParam, clampParam, VARIABLE_PARAMS, MAX_VARIABLE_PARAMS,
  sanitizeAmount, clampAmount, mergeOverride, compactAmount, plainNumber, type OrderFlowField,
  mainOverlaysOf, toggleMainOverlay,
} from './logic'
import { TERMS, splitPair } from './header'
import type { PagePort } from './data'
import { notePriceAxisPicked } from '../habitsRuntime'

// ───────────────────────────── 术语（照 iOS Glossary：只给读不出意思的短名挂问号）

const GLOSSARY: Term[] = [
  { id: 'vwap', title: `${indicatorName('VWAP')} · 当日成交量加权均价`, body: '从当天起点（上海时间 8 点）算起，按成交量加权的平均成交价。\n价格在它上方，说明今天进场的人多数在赚；在下方则多数在亏。' },
  { id: 'sar', title: `${indicatorName('SAR')} · SAR`, body: '一串跟着价格走的点，趋势走得越久，点追得越紧。\n点在 K 线下方看涨、在上方看跌；价格碰到点，点就翻到另一边。' },
  { id: 'longShortRatio', title: indicatorName('LSR'), body: '币安上持有多单的账户数除以持有空单的账户数。\n大于 1 是做多的人多；一边倒得太厉害时，行情常往反方向走。' },
  { id: 'takerRatio', title: `${indicatorName('TAKER')} · 主动买卖比`, body: '主动买入的量除以主动卖出的量（主动 = 直接吃掉别人挂单的一方）。\n大于 1 说明买方更急着进场，小于 1 说明卖方更急着走。' },
  { id: 'basis', title: indicatorName('BASIS'), body: '合约价格比现货指数高出多少，按百分比画。\n为正说明合约比现货贵、市场偏乐观；为负则偏悲观。' },
  { id: 'cvd', title: `${indicatorName('CVD')} · CVD`, body: '每根 K 线里主动买减主动卖，从当天起点一路累加。\n线往上走，这一段是被买上去的；往下走，是被卖下去的。' },
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
  /** 「添加对比」：开顶栏 ＋ 那张对比模式搜索页（先关面板再调）。没有时「对比」整节不排 */
  onAddCompare?(): void
  /** 此刻能不能对比（复盘回放、横屏画线台、看朋友分享的线时不能）；不给当能 */
  canCompare?(): boolean
}

/** 当前生效参数（按指标能直接下标取用的长度） */
const paramsOf = (id: IndicatorId): number[] => normalizedParams(id, st.params[id] ?? defaultParams(id))
/** 对比品种键 → 显示名：binance/usd_m/ETHUSDT → ETH/USDT，macro/index/DXY → DXY */
export const compareName = (key: string): string => {
  const sym = key.split('/').pop() ?? key
  const { base, quote } = splitPair(sym)
  return quote ? `${base}/${quote}` : base
}

// ───────────────────────────── 分析

export function openAnalysis(ctx: PanelContext): Sheet {
  ensureTerms()
  let off: (() => void) | null = null
  let reorder: ReorderHandle | null = null
  /** 拖副图把手的途中别的设置落盘（同步、学到的周期……）会经 subscribe 重画面板：先记下，松手再画 */
  let redrawAfterDrag = false
  const sheet = openSheet(body => {
    const host = el('div', 'cp-panel')
    body.append(host)
    const render = (): void => {
      if (reorder?.dragging) { redrawAfterDrag = true; return }
      host.innerHTML = analysisHTML(ctx)
    }
    render()
    off = subscribe(() => { if (!sheet.closed) render() })
    host.addEventListener('click', e => {
      const b = (e.target as Element).closest<HTMLElement>('[data-act]')
      if (!b || b.hasAttribute('disabled')) return
      const [act, arg] = (b.dataset.act || '').split(':') as [string, string | undefined]
      const id = arg as IndicatorId
      switch (act) {
        case 'draw': sheet.close(); ctx.onDraw(); break
        case 'draw-hide': st.drawingsHidden = !st.drawingsHidden; save(); break
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
        // 照 iOS compareSection：加、移除、清除都先收起面板（对比画在图上，要让人马上看到）；
        // 「添加对比」开顶栏 ＋ 那张对比模式搜索页（两处入口共用一页）
        case 'cmp-add': sheet.close(); ctx.onAddCompare?.(); break
        case 'cmp-rm': st.compareSymbols = st.compareSymbols.filter(k => k !== arg); save(); sheet.close(); break
        case 'cmp-clear': st.compareSymbols = []; save(); sheet.close(); break
        case 'of': st.orderFlow = !st.orderFlow; save(); break
        case 'of-edit': openOrderFlowEditor(ctx); break
        case 'reset': resetLayout(); break
      }
    })
    reorder = reorderable(host, {
      item: '.cp-iu[data-sub]', handle: '.cp-grip',
      // 按起拖那一刻的行挪（键是 data-sub），途中副图组成变了也不会挪走别的
      onMove(from, to, rows) { st.subs = moveSubAmong(st.subs, rows.map(r => r.dataset.sub as IndicatorId), from, to); save() },
      onEnd() { if (redrawAfterDrag) { redrawAfterDrag = false; render() } },
    })
  }, { title: '分析', detent: 'medium', dim: 'large', id: 'analysis', className: 'cp-sheet cp-list cp-cards', onClose: () => { off?.(); reorder?.destroy() } })
  return sheet
}

/** 在用那一行：名字 + 参数 + 「›」，点进参数编辑（副图行带拖动把手；同一段里有把手时主图行垫一块空位对齐） */
function inUseLine(id: IndicatorId, sub: boolean, handles: boolean): string {
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
function toggleRowHTML(id: IndicatorId, on: boolean, act: string): string {
  const term = INDICATOR_TERM[id]
  return `<div class="cp-row"><span class="cp-rn">${dot(swatchVar(id))}${esc(indicatorName(id))}${term ? termHTML(term) : ''}</span>${sw(on, `${act}:${id}`, indicatorName(id))}</div>`
}

// ───────────────────────────── 主图指标（横屏画线台「主图˅」）

/**
 * 画线台那一版「分析」（iOS IndicatorPage.mainOnly，2026-10-05）：画线台不画副图、不画主力订单流，
 * 那几段在这儿点了图上看不出任何变化，所以只摆主图那几段——开着的主图指标（点进参数）和主图叠加那排开关；
 * 「恢复默认指标」会连副图一起动、「开始画线」已经在画，都不摆。改的仍是同一份指标布局（跟人走，不另起横屏配置）。
 * 眼睛（drawingOverlaysShown）关着时新开一个主图指标，眼睛跟着睁开。
 */
export function openMainIndicators(): Sheet {
  ensureTerms()
  let off: (() => void) | null = null
  const sheet = openSheet(body => {
    const host = el('div', 'cp-panel')
    body.append(host)
    const render = (): void => { host.innerHTML = mainOnlyHTML() }
    render()
    off = subscribe(() => { if (!sheet.closed) render() })
    host.addEventListener('click', e => {
      const b = (e.target as Element).closest<HTMLElement>('[data-act]')
      if (!b || b.hasAttribute('disabled')) return
      const [act, arg] = (b.dataset.act || '').split(':') as [string, string | undefined]
      const id = arg as IndicatorId
      if (act === 'edit') openIndicatorEditor(id)
      else if (act === 'ov') {
        const next = toggleMainOverlay({ overlays: st.overlays, drawingOverlaysShown: st.drawingOverlaysShown }, id)
        st.overlays = next.overlays
        st.drawingOverlaysShown = next.drawingOverlaysShown
        save()
      }
    })
  }, { title: '主图指标', detent: 'large', dim: 'large', id: 'main-indicators', className: 'cp-sheet cp-list cp-cards', onClose: () => { off?.() } })
  return sheet
}

function mainOnlyHTML(): string {
  const out: string[] = []
  const overlays = mainOverlaysOf(st.overlays)
  if (overlays.length) {
    out.push(gt('使用中'))
    out.push(`<div class="cp-inuse">${overlays.map(id => inUseLine(id, false, false)).join('')}</div>`)
  }
  out.push(gt('主图叠加'))
  out.push(`<div class="cp-group">${OVERLAY_ROWS.map(id => toggleRowHTML(id, st.overlays.includes(id), 'ov')).join('')}</div>`)
  return out.join('')
}

export function analysisHTML(ctx: PanelContext): string {
  const out: string[] = []
  out.push(gt('画线'))
  // 「隐藏画线」（iOS IndicatorPage 画线节同一行，跟账号同步）：竖屏看行情时线全收起来，提醒照判、图上改画提醒线；
  // 横屏画线台一律显示，不受它管
  out.push(`<div class="cp-group"><button type="button" class="cp-row cp-tap" data-act="draw"><span class="cp-rn">开始画线</span><span class="cp-drawglyph">${glyph('draw', 24)}</span></button>`
    + `<div class="cp-row"><span class="cp-rn">隐藏画线</span>${sw(st.drawingsHidden, 'draw-hide', '隐藏画线')}</div></div>`)

  const overlays = st.overlays.filter(x => x !== 'ORDERFLOW')
  const inUse = overlays.length > 0 || st.subs.length > 0
  const handles = st.subs.length > 0
  if (inUse) {
    out.push(gt('指标'))
    const rows: string[] = []
    for (const id of overlays) rows.push(inUseLine(id, false, handles))
    for (const id of st.subs) rows.push(inUseLine(id, true, handles))
    out.push(`<div class="cp-inuse">${rows.join('')}</div>`)
  }
  const toggleRow = toggleRowHTML
  out.push(gt(inUse ? '主图叠加' : '指标 · 主图叠加'))
  out.push(`<div class="cp-group">${OVERLAY_ROWS.map(id => toggleRow(id, st.overlays.includes(id), 'ov')).join('')}</div>`)
  out.push(gt('副图 · 最多三个 · 成交量不占'))
  out.push(`<div class="cp-group">${SUB_ROWS.map(id => toggleRow(id, st.subs.includes(id), 'sub')).join('')}</div>`)

  out.push(compareSectionHTML(ctx))

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

/** 「对比」一节（照 iOS IndicatorPage.compareSection，10-06 恢复、与顶栏 ＋ 并存）：
 *  「添加对比」（满三只置灰）开顶栏 ＋ 那张对比模式搜索页；每只一行带「移除」；有对比时「清除对比」。
 *  此刻不能对比（复盘回放、横屏画线台、看朋友分享的线）或没接入口时整节不排。 */
export function compareSectionHTML(ctx: PanelContext): string {
  if (!ctx.onAddCompare || ctx.canCompare?.() === false) return ''
  const keys = st.compareSymbols
  const rows: string[] = []
  rows.push(`<button type="button" class="cp-row cp-tap" data-act="cmp-add"${keys.length >= MAX_COMPARE ? ' disabled' : ''}><span class="cp-rn">添加对比</span>${chevron()}</button>`)
  for (const k of keys) rows.push(`<div class="cp-row"><span class="cp-rn">${esc(compareName(k))}</span><button type="button" class="cp-textbtn" data-act="cmp-rm:${esc(k)}">移除</button></div>`)
  if (keys.length) rows.push(`<button type="button" class="cp-row cp-tap" data-act="cmp-clear"><span class="cp-rn">清除对比</span></button>`)
  return gt('对比') + `<div class="cp-group">${rows.join('')}</div>`
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

/** 指标线的色卡（照 iOS IndicatorColorControl 2026-10-08）：第一支是出厂色、下面标「默认」，点它清掉自选色；
 *  其余从当前皮肤派生（强调色 / 浅强调色 / 涨色 / 跌色 / 墨色，对图表底色至少 3:1、去重，见 model/lineSwatches）。
 *  选中：默认那支在没改过或正好改成出厂色时亮，其余是正好那一色时亮；外面一圈墨色。标识 indicator.color.N.<角色> */
function lineSwatchesFor(id: IndicatorId, i: number): LineSwatch[] {
  const cs = getComputedStyle(document.documentElement)
  const v = (name: string): string => toHex(cs.getPropertyValue(name))
  return lineSwatchOptions(defaultLineColor(id, i), { accent: v('--accent'), ink: v('--ink'), up: v('--k-up'), down: v('--k-down'), bg: v('--k-bg') })
}
function indicatorColorHTML(i: number, name: string, picked: string | undefined, swatches: LineSwatch[]): string {
  const p = picked?.slice(0, 7).toUpperCase()
  const cur = p ?? swatches[0].hex
  return `<div class="cp-crow"><div class="cp-crow-top"><span class="cp-rn">${esc(name)}</span>
      <label class="cp-cpick" style="--c:${cur}" aria-label="${esc(name)} · 自选颜色"><input type="color" data-pick="${i}" value="${cur.toLowerCase()}"></label></div>
    <div class="cp-chips-c cp-ichips">${swatches.map((sw, k) => {
      const def = k === 0
      const on = def ? p == null || p === sw.hex : p === sw.hex
      return `<button type="button" class="cp-cchip${def ? ' cp-cdef' : ''}${on ? ' on' : ''}" style="--c:${sw.hex}" data-act="${def ? 'color-default' : 'color'}:${i}" data-c="${sw.hex}" data-id="indicator.color.${i}.${sw.role}" aria-label="${def ? '默认' : swatchRoleName(sw.role)}" aria-pressed="${on}">${def ? '<small>默认</small>' : ''}</button>`
    }).join('')}</div></div>`
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
        indicatorColorHTML(i, name, draft.colors[i], lineSwatchesFor(id, i))).join('')}<button type="button" class="cp-row cp-tap cp-accent" data-act="colors-reset">恢复默认颜色</button></div>`
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
      else if (act === 'color-default') { commitFields(); delete draft.colors[arg]; render() }
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
        // 照 iOS ChartPanel：分段显示图上真正用的那档；手动换的这一档先记成这一类品种的一笔（按习惯时它立刻生效，
        // 不然学到的那档会把选择盖回去），再照旧写进设置
        const mode = b.dataset.v as PriceMode
        notePriceAxisPicked(mode, axis.category())
        st.priceMode = mode
      }
      else if (act === 'depth') st.depth = !st.depth
      else return
      save()
    })
  }, { title: '图表设置', detent: 'fit', dim: 'large', id: 'chart-settings', className: 'cp-sheet cp-list cp-cards', onClose: () => off?.() })
  return sheet
}

/** 挑一只品种的小表（画线台换品种用；对比 2026-10-05 起改走顶栏 ＋ 的对比搜索页）：空搜索列自选里的，再按 24h 成交额补满；有字按 rankSearch */
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
