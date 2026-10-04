/* 手机网页版 · 行情页周期条（照 iOS Main/IntervalBar.swift、IntervalGridPopover.swift、CrosshairReadout.swift）
 *
 * 钉住的档位按 INTERVALS 顺序等宽铺满；当前档一颗贴字的 accent-soft 药丸（「最新」药丸 2026-10-02 按用户要求删了：
 * 回到最新靠双击图、或在行情页再点一下底栏「图表」）；
 * 一根 1×14 分隔线；行尾三件：「更多 ▾」（当前档没钉住时写成那一档并高亮）· 「分析」· 图表设置记号。
 * 长按一档 = 取消钉。十字线活着（主图或副图）时整行透明让位；落在主图上时同一行靠左换成「创建提醒」药丸。
 */
import { INTERVALS, MAX_QUICK, type IntervalId } from '../../app/prefs'
import { INTERVAL_SHORT, INTERVAL_DISPLAY } from '../../chart/series'
import { openPopover, type Popover } from '../../ui/sheet'
import { icon } from '../../ui/icons'
import { el, esc } from '../../ui/dom'
import { sortIntervals } from './logic'

/** SF Symbols pin / pin.fill 的描法（这一颗 icons.ts 里没有，只行情页用） */
const PIN = (filled: boolean) => `<svg class="cp-pin-g" width="10" height="12" viewBox="0 0 10 12" aria-hidden="true">
  <path d="M3 1h4l-.6 3.4L8.6 6.6V7.6H1.4V6.6L3.6 4.4Z" fill="${filled ? 'currentColor' : 'none'}" stroke="currentColor" stroke-width="1.1" stroke-linejoin="round"/>
  <path d="M5 7.6V11" stroke="currentColor" stroke-width="1.1" stroke-linecap="round"/></svg>`

export interface IntervalBarHandlers {
  onPick(iv: IntervalId): void
  /** 钉 / 取消钉（没钉满时） */
  onPin(iv: IntervalId): void
  onReplace(old: IntervalId, add: IntervalId): void
  onAnalysis(): void
  onSettings(): void
  onAlert(): void
}

export interface IntervalBarState {
  quick: readonly IntervalId[]; current: IntervalId
  /** 十字线活着（任何一格）：整行让位 */
  crosshair: boolean
  /** 十字线落在主图：让出来的位置摆「创建提醒」 */
  crosshairOnMain: boolean
}

export function createIntervalBar(host: HTMLElement, h: IntervalBarHandlers) {
  const row = el('div', 'cp-ivrow')
  const bar = el('div', 'cp-ivbar')
  const chips = el('div', 'cp-chips')
  const divider = el('span', 'cp-ivdiv')
  const more = el('button', 'cp-tail cp-more')
  more.type = 'button'
  const analysis = el('button', 'cp-tail', '分析')
  analysis.type = 'button'
  const settings = el('button', 'cp-tail cp-gear', icon('adjust', 18))
  settings.type = 'button'; settings.setAttribute('aria-label', '图表设置')
  bar.append(chips, divider, more, analysis, settings)
  const alert = el('button', 'cp-alertpill', `${icon('bell', 12)}<span>创建提醒</span>`)
  alert.type = 'button'
  row.append(bar, alert)
  host.append(row)

  let state: IntervalBarState = { quick: [], current: '1h', crosshair: false, crosshairOnMain: false }
  let grid: Popover | null = null
  let gridRender: (() => void) | null = null
  let chipsKey = ''
  let moreShown: string | null = null

  // 收「更多」网格由行情页开面板那一处统一做（chart.ts panel），这里只转发
  analysis.onclick = () => h.onAnalysis()
  settings.onclick = () => h.onSettings()
  alert.onclick = () => h.onAlert()
  more.onclick = () => { if (grid) grid.close(); else openGrid() }

  // 长按一档 = 取消钉（照 iOS §10.6，0.45 秒）
  let pressT = 0, pressed = false
  chips.addEventListener('pointerdown', e => {
    const b = (e.target as HTMLElement).closest<HTMLButtonElement>('[data-iv]')
    if (!b) return
    pressed = false
    clearTimeout(pressT)
    pressT = window.setTimeout(() => { pressed = true; h.onPin(b.dataset.iv as IntervalId) }, 450)
  })
  const cancelPress = () => clearTimeout(pressT)
  chips.addEventListener('pointerup', cancelPress)
  chips.addEventListener('pointercancel', cancelPress)
  chips.addEventListener('pointerleave', cancelPress)
  chips.addEventListener('contextmenu', e => e.preventDefault())
  chips.addEventListener('click', e => {
    const b = (e.target as HTMLElement).closest<HTMLButtonElement>('[data-iv]')
    if (!b) return
    if (pressed) { pressed = false; return }
    h.onPick(b.dataset.iv as IntervalId)
  })

  function onBar(): IntervalId[] { return sortIntervals(state.quick, INTERVALS).slice(0, MAX_QUICK) }

  function openGrid(): void {
    let replacing: IntervalId | null = null
    more.classList.add('open')
    grid = openPopover(row, (root, pop) => {
      root.classList.add('cp-grid')
      const cells = el('div', 'cp-grid-cells')
      root.append(cells)
      // 只在钉住的档 / 当前档 / 「换掉」态变了时重建：行情每跳都会调 render，整格重写会把按下去的那颗
      // 按钮换掉，手指抬起时 click 落到外层，这一下点击就丢了
      let cellsKey = ''
      gridRender = () => {
        const quick = state.quick
        const k = quick.join(',') + '|' + state.current + '|' + (replacing ?? '')
        if (k === cellsKey) return
        cellsKey = k
        cells.innerHTML = INTERVALS.map(iv => {
          const on = iv === state.current, pinned = quick.includes(iv)
          const target = replacing != null && pinned, chosen = replacing === iv
          const cls = ['cp-gcell', on ? 'on' : '', target ? 'target' : '', chosen ? 'chosen' : ''].filter(Boolean).join(' ')
          const label = target ? `换掉 ${INTERVAL_DISPLAY[iv]}` : INTERVAL_DISPLAY[iv]
          const pinLabel = pinned ? `从常用行移除 ${INTERVAL_DISPLAY[iv]}` : `加进常用行 ${INTERVAL_DISPLAY[iv]}`
          return `<div class="cp-gwrap"><button type="button" class="${cls}" data-pick="${iv}" aria-label="${esc(label)}">${INTERVAL_SHORT[iv]}</button>`
            + `<button type="button" class="cp-gpin${pinned || chosen ? ' on' : ''}" data-pin="${iv}" aria-label="${esc(pinLabel)}">${PIN(pinned || chosen)}</button></div>`
        }).join('')
      }
      gridRender()
      cells.addEventListener('click', e => {
        const t = e.target as HTMLElement
        const pinB = t.closest<HTMLElement>('[data-pin]'), pickB = t.closest<HTMLElement>('[data-pick]')
        if (pinB) {
          const iv = pinB.dataset.pin as IntervalId
          const pinned = state.quick.includes(iv)
          if (replacing) replacing = null
          else if (!pinned && state.quick.length >= MAX_QUICK) replacing = iv
          else h.onPin(iv)
          gridRender?.()
          return
        }
        if (pickB) {
          const iv = pickB.dataset.pick as IntervalId
          if (replacing) {
            const incoming = replacing
            replacing = null
            if (state.quick.includes(iv)) h.onReplace(iv, incoming)
            gridRender?.()
            return
          }
          h.onPick(iv)
          pop.close()
          return
        }
        if (replacing) { replacing = null; gridRender?.() }
      })
      // 上下滑收起
      let y0 = 0, x0 = 0
      root.addEventListener('touchstart', e => { y0 = e.touches[0].clientY; x0 = e.touches[0].clientX }, { passive: true })
      root.addEventListener('touchend', e => {
        const dy = e.changedTouches[0].clientY - y0, dx = e.changedTouches[0].clientX - x0
        if (Math.abs(dy) > 28 && Math.abs(dy) > Math.abs(dx)) pop.close()
      }, { passive: true })
    }, { className: 'cp-grid-pop', onClose: () => { grid = null; gridRender = null; more.classList.remove('open') } })
  }

  function render(next: Partial<IntervalBarState>): void {
    state = { ...state, ...next }
    const list = onBar()
    const key = list.join(',') + '|' + state.current
    if (key !== chipsKey) {
      chipsKey = key
      chips.innerHTML = list.map(iv => `<button type="button" class="cp-chip${iv === state.current ? ' on' : ''}" data-iv="${iv}" aria-label="${INTERVAL_DISPLAY[iv]}"${iv === state.current ? ' aria-selected="true"' : ''}><span>${INTERVAL_SHORT[iv]}</span></button>`).join('')
    }
    const off = !list.includes(state.current)
    const moreKey = off ? state.current : ''
    if (moreKey !== moreShown) {
      moreShown = moreKey
      more.innerHTML = `<span>${off ? INTERVAL_SHORT[state.current] : '更多'}</span>${icon('chevron', 9)}`
      more.classList.toggle('on', off)
      more.setAttribute('aria-label', off ? `更多周期，当前 ${INTERVAL_DISPLAY[state.current]}` : '更多周期')
    }
    row.classList.toggle('yield', state.crosshair)
    row.classList.toggle('alerting', state.crosshairOnMain)
    if (state.crosshair) grid?.close()
    gridRender?.()
  }

  return {
    el: row,
    render,
    openGrid(): void { if (!grid) openGrid() },
    closeGrid(): void { grid?.close() },
    get gridOpen(): boolean { return grid != null },
  }
}
