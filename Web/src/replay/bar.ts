/* Hkline Web · K 线回放：浮在图表区下沿的回放条 + 选起点时跟着鼠标的「起点」竖线
 * 回放条照复盘播放条（review/player.ts）的样子：播放键、倍速分段、进度线、当前时刻；
 * 另有起点时间输入、跳到起点、退出回放。不给「前一根 / 后一根」逐根步进。 */
import type { TVChart } from '../chart/chart'
import { I, esc } from '../ui/dom'
import * as M from './model'
import '../styles/replay.css'

export interface BarState {
  playing: boolean
  speed: number
  /** 进度线位置 0–1 */
  pos: number
  /** 当前那根的开盘时刻 */
  time: number | null
  /** 起点的回放钟 */
  start: number
  iv: string
  loading: boolean
  /** 播到最新了 */
  end: boolean
}
export interface BarHandlers {
  toggle(): void
  speed(v: number): void
  seek(pos: number, phase: 'start' | 'move' | 'end'): void
  toStart(): void
  exit(): void
  cancel(): void
  startAt(text: string): void
}

/** 起点那一根的开盘时刻（起点钟是它的收线时刻） */
const startOpen = (start: number, iv: string): number => M.barOpen(start - 1, iv)

export class ReplayBar {
  el: HTMLElement
  private mode: 'pick' | 'play' | null = null
  private dragging = false
  private ac = new AbortController()

  constructor(parent: HTMLElement, private h: BarHandlers) {
    this.el = document.createElement('div')
    this.el.className = 'rp-bar'
    this.el.setAttribute('role', 'toolbar')
    this.el.setAttribute('aria-label', 'K 线回放')
    parent.appendChild(this.el)
    this.bind()
  }

  pick(): void {
    this.mode = 'pick'
    this.el.classList.add('picking')
    this.el.innerHTML = `
      <span class="rp-hint">${I('replay', 'icon-16')}<span>在图上点一下定起点</span></span>
      <span class="rp-sep"></span>
      <label class="rp-start"><span>或输入</span><input class="num" data-rp="start" spellcheck="false" autocomplete="off" aria-label="起点时间（上海时间）" placeholder="${M.fmtShTime(Date.now() - 3 * 864e5)}"></label>
      <button class="btn ghost sm" data-rp="cancel" data-kbd="Esc">取消</button>`
  }

  play(s: BarState): void {
    if (this.mode !== 'play') {
      this.mode = 'play'
      this.el.classList.remove('picking')
      this.el.innerHTML = `
        <button class="ibtn sm rp-play" data-rp="toggle" aria-label="播放" data-tip="播放" data-kbd="空格">${I('play')}</button>
        <div class="seg rp-speed" role="group" aria-label="速度">${M.REPLAY_SPEEDS.map(v => `<button data-rp="speed" data-v="${v}" aria-pressed="false">${v}×</button>`).join('')}</div>
        <div class="rp-track" role="slider" tabindex="0" aria-label="回放进度" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0"><div class="rp-rail"></div><div class="rp-played"></div><div class="rp-kwrap"><div class="rp-knob"></div></div></div>
        <span class="rp-time num"></span>
        <span class="rp-sep"></span>
        <label class="rp-start" data-tip="改了按回车，从这一刻重新开始（上海时间）"><span>起点</span><input class="num" data-rp="start" spellcheck="false" autocomplete="off" aria-label="起点时间（上海时间）"></label>
        <button class="ibtn sm" data-rp="toStart" aria-label="跳到起点" data-tip="跳到起点" data-kbd="Home">${I('toStart')}</button>
        <button class="btn ghost sm rp-exit" data-rp="exit" data-tip="回到实时" data-kbd="⌥ R">退出回放</button>`
    }
    const icon = s.playing ? 'pause' : s.end ? 'undo' : 'play'
    const btn = this.el.querySelector<HTMLElement>('[data-rp="toggle"]')
    if (btn && btn.dataset.icon !== icon) {
      const lab = s.playing ? '暂停' : s.end ? '从起点重播' : '播放'
      btn.dataset.icon = icon; btn.innerHTML = I(icon); btn.setAttribute('aria-label', lab); btn.dataset.tip = lab
    }
    // 16× 每秒刷 16 次：只写变了的；进度用 transform 挪，不触发排版
    this.el.querySelectorAll<HTMLElement>('[data-rp="speed"]').forEach(b => put(b, 'aria-pressed', String(+(b.dataset.v || 0) === s.speed)))
    const tr = this.el.querySelector<HTMLElement>('.rp-track')
    if (tr) {
      const p = Math.max(0, Math.min(1, s.pos)).toFixed(4)
      tr.querySelector<HTMLElement>('.rp-played')!.style.transform = `scaleX(${p})`
      tr.querySelector<HTMLElement>('.rp-kwrap')!.style.transform = `translateX(${(+p * 100).toFixed(2)}%)`
      put(tr, 'aria-valuenow', String(Math.round(s.pos * 100)))
      if (s.time != null) put(tr, 'aria-valuetext', M.fmtShTime(s.time))
    }
    const tm = this.el.querySelector<HTMLElement>('.rp-time')
    const txt = s.loading ? '载入中…' : s.time != null ? M.fmtShTime(s.time) : ''
    if (tm && tm.textContent !== txt) tm.textContent = txt
    const inp = this.el.querySelector<HTMLInputElement>('[data-rp="start"]')
    const sv = M.fmtShTime(startOpen(s.start, s.iv))
    if (inp && document.activeElement !== inp && inp.value !== sv) inp.value = sv
  }

  destroy(): void { this.ac.abort(); this.el.remove() }

  private bind(): void {
    const signal = this.ac.signal
    this.el.addEventListener('click', e => {
      const b = (e.target as HTMLElement).closest<HTMLElement>('button[data-rp]'); if (!b) return
      const act = b.dataset.rp
      // 点完不留焦点在按钮上：空格是播放 / 暂停，不能再「按一下这个按钮」
      b.blur()
      if (act === 'toggle') this.h.toggle()
      else if (act === 'speed') this.h.speed(+(b.dataset.v || 1))
      else if (act === 'toStart') this.h.toStart()
      else if (act === 'exit') this.h.exit()
      else if (act === 'cancel') this.h.cancel()
    }, { signal })
    this.el.addEventListener('keydown', e => {
      const t = e.target as HTMLElement
      if (t instanceof HTMLInputElement && t.dataset.rp === 'start') {
        if (e.key === 'Enter') { e.preventDefault(); this.h.startAt(t.value); t.blur() }
        else if (e.key === 'Escape') { e.preventDefault(); t.blur() }
        e.stopPropagation()
        return
      }
      // 进度线上 Home / End 到头到尾（不给方向键逐根挪）
      if (t.closest('.rp-track') && (e.key === 'Home' || e.key === 'End')) {
        e.preventDefault(); e.stopPropagation()
        if (e.key === 'Home') this.h.toStart()
        else { this.h.seek(1, 'start'); this.h.seek(1, 'end') }
      }
    }, { signal })
    // 进度线：按下即定位，拖动跟手；拖的时候暂停，松手按之前的状态继续
    this.el.addEventListener('pointerdown', e => {
      const tr = (e.target as HTMLElement).closest<HTMLElement>('.rp-track'); if (!tr || this.dragging) return
      e.preventDefault()
      const rect = tr.getBoundingClientRect()
      const at = (x: number) => Math.max(0, Math.min(1, (x - rect.left) / (rect.width || 1)))
      this.dragging = true; tr.classList.add('dragging')
      this.h.seek(at(e.clientX), 'start')
      tr.setPointerCapture(e.pointerId)
      let raf = 0, lastX = e.clientX
      const mv = (ev: PointerEvent) => { lastX = ev.clientX; if (!raf) raf = requestAnimationFrame(() => { raf = 0; this.h.seek(at(lastX), 'move') }) }
      const up = () => {
        tr.removeEventListener('pointermove', mv); tr.removeEventListener('pointerup', up); tr.removeEventListener('pointercancel', up)
        if (raf) { cancelAnimationFrame(raf); raf = 0; this.h.seek(at(lastX), 'move') }
        this.dragging = false; tr.classList.remove('dragging')
        this.h.seek(at(lastX), 'end')
      }
      tr.addEventListener('pointermove', mv); tr.addEventListener('pointerup', up); tr.addEventListener('pointercancel', up)
    }, { signal })
  }
}

/** 选起点：一道竖线跟着鼠标走（吸到 K 线中心），右边整片压暗表示「这之后会先藏起来」，底下标出那一根的时间；
 *  在图上点一下（没拖动）就定起点。拖动照常平移；选着画线工具时点一下也只定起点、不画线。 */
export class PickOverlay {
  private el: HTMLElement
  private ac = new AbortController()
  private down: { x: number; y: number } | null = null

  constructor(private chart: TVChart, private iv: () => string, private onPick: (t: number) => void) {
    this.el = document.createElement('div')
    this.el.className = 'rp-pick'
    this.el.hidden = true
    this.el.innerHTML = '<div class="shade"></div><div class="line"></div><div class="lab num"></div>'
    chart.host.appendChild(this.el)
    const host = chart.host, cv = chart.canvas, signal = this.ac.signal
    host.addEventListener('mousemove', e => { if (e.target === cv) this.show(e); else this.el.hidden = true }, { signal })
    host.addEventListener('mouseleave', () => { this.el.hidden = true }, { signal })
    host.addEventListener('mousedown', e => {
      if (e.target !== cv || e.button !== 0) return
      const p = this.local(e); if (!this.inPlot(p.x, p.y)) return
      this.down = { x: e.clientX, y: e.clientY }
      // 选着画线工具：这一下只定起点，不交给图表去画
      if (chart.tool) { e.stopPropagation(); e.preventDefault() }
    }, { capture: true, signal })
    window.addEventListener('mouseup', e => {
      const d = this.down; this.down = null
      if (!d || e.button !== 0 || Math.hypot(e.clientX - d.x, e.clientY - d.y) > 4) return
      const i = this.index(this.local(e).x); if (i == null) return
      this.onPick(this.chart.bars[i].t)
    }, { signal })
  }

  destroy(): void { this.ac.abort(); this.el.remove() }

  private local(e: MouseEvent): { x: number; y: number } {
    const r = this.chart.canvas.getBoundingClientRect()
    return { x: e.clientX - r.left, y: e.clientY - r.top }
  }
  private inPlot(x: number, y: number): boolean { return x >= 0 && x < this.chart.plotW() && y >= 0 && y < this.chart.h - 28 }
  /** 鼠标下的那一根（最多到最后一根走完的，正在走的那根不能当起点） */
  private index(x: number): number | null {
    const ch = this.chart, n = ch.bars.length; if (!n) return null
    const max = M.visibleCount(ch.bars, M.liveEnd(Date.now(), this.iv()), this.iv()) - 1
    if (max < 0) return null
    return Math.max(0, Math.min(max, Math.round(ch.xToIndex(x))))
  }
  private show(e: MouseEvent): void {
    const p = this.local(e), ch = this.chart
    if (!this.inPlot(p.x, p.y)) { this.el.hidden = true; return }
    const i = this.index(p.x); if (i == null) { this.el.hidden = true; return }
    const x = Math.round(ch.indexToX(i)), pw = ch.plotW(), half = Math.max(1, ch.spacing / 2)
    this.el.hidden = false
    this.el.style.setProperty('--x', x + 'px')
    this.el.style.setProperty('--sx', x + half + 'px')
    this.el.style.setProperty('--sw', Math.max(0, pw - x - half) + 'px')
    this.el.style.setProperty('--h', ch.h - 28 + 'px')
    const lab = this.el.querySelector<HTMLElement>('.lab')!
    lab.innerHTML = `<b>起点</b> ${esc(M.fmtShTime(ch.bars[i].t))}`
  }
}

/** 属性没变就不写（写一次就要重算样式） */
function put(el: Element, k: string, v: string): void { if (el.getAttribute(k) !== v) el.setAttribute(k, v) }
