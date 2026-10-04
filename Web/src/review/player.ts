/* Hkline Web · 复盘：回放区（K 线 + 叠加层 + 播放条）
 *
 * 播放条照手机端 ReviewReplayControls：播放 / 暂停（放完变重播）· 进度线（带刻度，拖动定位）·
 * 速度 · 关键点跳转。没有「前一根 / 后一根」逐根步进——定位只靠拖进度线和跳关键点。
 * 拖动时暂停，松手后按拖之前的状态继续。
 */
import { TVChart } from '../chart/chart'
import { st } from '../app/store'
import type { Bar } from '../chart/calc'
import { I, esc } from '../ui/dom'
import { shTime } from '../ui/common'
import { IV_LABEL } from '../market/symbols'
import { fetchWindow } from './api'
import { ReviewOverlay } from './overlay'
import { SPEEDS, positionAt, stepDelay, timeAtPos, trackPos, type Plan } from './replay'

export interface PlayerMeta { title: string; dec: number; badge: string }

export class ReplayPlayer {
  wrap: HTMLElement
  bar: HTMLElement
  chart: TVChart
  overlay: ReviewOverlay
  caption: HTMLDivElement
  float: HTMLDivElement
  plan: Plan | null = null
  bars: Bar[] = []
  meta: PlayerMeta = { title: '', dec: 2, badge: '' }
  /** 已放到的 K 线开盘时间 */
  cur = 0
  playing = false
  speed = 1
  /** 正停在哪个关键点上（开仓处的「当时怎么想」只在这时出现） */
  pausedKey: string | null = null
  private timer: ReturnType<typeof setTimeout> | undefined
  private token = 0
  private dragging = false

  constructor(wrap: HTMLElement, bar: HTMLElement) {
    this.wrap = wrap
    this.bar = bar
    const host = document.createElement('div')
    host.className = 'rv-chart-host'
    wrap.appendChild(host)
    this.chart = new TVChart(host, {})
    this.chart.readOnly = true // 回放里只看：已有画线不能改，也不能新画
    this.chart.setIndicators({ ma: true, ema: false, boll: false, vol: true, subs: [] })
    this.overlay = new ReviewOverlay(wrap, this.chart)
    this.caption = document.createElement('div'); this.caption.className = 'rv-caption'; wrap.appendChild(this.caption)
    this.float = document.createElement('div'); this.float.className = 'rv-float num'; wrap.appendChild(this.float)
    this.bindBar()
  }

  readTheme(): void { this.chart.readTheme(); this.overlay.readTheme() }
  /** 复盘页切走：停播、上面那层不再逐帧跑；切回来再醒 */
  sleep(): void { this.stop(); this.overlay.sleep() }
  wake(): void { this.overlay.wake() }

  destroy(): void {
    this.stop()
    this.token++
    this.overlay.destroy()
    this.chart.destroy()
    this.wrap.innerHTML = ''
    this.bar.innerHTML = ''
  }

  /** 换一条记录：拉 K 线、定视野、停在打开时该停的那根 */
  async load(plan: Plan, meta: PlayerMeta): Promise<'ok' | 'empty' | 'stale'> {
    this.stop()
    const my = ++this.token
    this.plan = plan; this.meta = meta; this.speed = plan.speed; this.pausedKey = null
    this.renderBar(true)
    let bars: Bar[] = []
    try { bars = await fetchWindow(plan.symbol, plan.iv, plan.fetchFrom, plan.fetchTo) } catch { bars = [] }
    if (my !== this.token) return 'stale'
    this.bars = bars
    if (!bars.length) { this.chart.setData([], { symbol: plan.symbol, iv: plan.step }); this.overlay.set(null, 0, meta.dec); this.renderBar(); return 'empty' }
    this.chart.setData(bars, { symbol: plan.symbol + '·' + plan.kind, iv: plan.step, title: meta.title, sub: `· ${IV_LABEL[plan.iv] || plan.iv} · 上海时间`, dec: meta.dec, badge: meta.badge })
    this.chart.setDrawings(structuredClone((st.drawings[plan.symbol] ?? []).filter(d => d.type !== 'measure')))
    this.chart.setVisibleRange(plan.startBar, plan.stopBar)
    this.overlay.set(plan, plan.initialBar, meta.dec)
    this.seek(plan.initialBar)
    if (plan.kind === 'trade' && plan.initialBar === plan.openBar) this.pausedKey = 'open'
    this.renderOverlayHtml()
    this.renderBar()
    return 'ok'
  }

  // ---------------------------------------------------------------- 播放
  private idxOf(t: number): number {
    const b = this.bars
    let lo = 0, hi = b.length - 1
    if (!b.length) return 0
    if (t <= b[0].t) return 0
    if (t >= b[hi].t) return hi
    while (hi - lo > 1) { const m = (lo + hi) >> 1; if (b[m].t <= t) lo = m; else hi = m }
    return lo
  }

  /** 定位到某根（按开盘时间），未来的 K 线与成交一律不画 */
  seek(t: number): void {
    const p = this.plan; if (!p || !this.bars.length) return
    t = Math.max(p.startBar, Math.min(p.stopBar, t))
    const i = this.idxOf(t)
    this.cur = this.bars[i].t
    this.chart.setReplay(i >= this.bars.length - 1 ? null : i)
    this.overlay.setRevealed(this.cur)
    // 放到的那根跑出视野右边时，整体往左挪，让它留在右侧三分之一处
    const c = this.chart
    const right = c.xToIndex(c.plotW())
    if (i > right - 2 || i < c.xToIndex(0)) { c.rightBar = i + Math.max(6, (c.plotW() / c.spacing) / 3); c.dirty = true }
    this.pausedKey = null
    this.renderOverlayHtml()
    this.syncBar()
  }

  finished(): boolean { return !!this.plan && this.cur >= this.plan.stopBar }

  play(): void {
    const p = this.plan; if (!p || !this.bars.length) return
    if (this.finished()) this.seek(p.startBar)
    this.playing = true
    this.renderBar()
    this.schedule(stepDelay(this.speed, false))
  }

  stop(): void {
    clearTimeout(this.timer); this.timer = undefined
    if (this.playing) { this.playing = false; this.renderBar() }
  }

  toggle(): void { if (this.playing) this.stop(); else this.play() }

  private schedule(ms: number): void {
    clearTimeout(this.timer)
    this.timer = setTimeout(this.tick, ms)
  }

  private tick = (): void => {
    const p = this.plan
    if (!this.playing || !p) return
    const next = this.cur + p.step
    if (next > p.stopBar || next > this.bars[this.bars.length - 1].t) { this.playing = false; this.renderBar(); return }
    this.seek(next)
    const key = p.keys.find(k => k.t === this.cur && k.pause)
    if (key) { this.pausedKey = key.id; this.renderOverlayHtml() }
    if (this.cur >= p.stopBar) { this.playing = false; this.renderBar(); return }
    this.schedule(stepDelay(this.speed, !!key))
  }

  jump(id: string): void {
    const k = this.plan?.keys.find(x => x.id === id); if (!k) return
    this.stop()
    this.seek(k.t)
    this.pausedKey = k.id
    this.renderOverlayHtml()
  }

  // ---------------------------------------------------------------- 图上的文字（HTML，好折行）
  private renderOverlayHtml(): void {
    const p = this.plan
    this.float.style.right = (this.chart.aw + 12) + 'px'
    if (!p || !this.bars.length) { this.caption.hidden = true; this.float.hidden = true; return }
    if (p.kind === 'trade') {
      const b = this.bars[this.idxOf(this.cur)]
      const pos = positionAt(p, this.cur, b.c)
      if (pos) {
        const up = pos.floating >= 0
        this.float.hidden = false
        this.float.innerHTML = `<span class="k">持仓中</span><span class="${up ? 'up' : 'down'}">${up ? '+' : ''}${(pos.floating * 100).toFixed(2)}%</span>`
      } else if (p.closed && this.cur >= p.closeBar) {
        this.float.hidden = false
        this.float.innerHTML = `<span class="k">已平仓</span>`
      } else {
        this.float.hidden = false
        this.float.innerHTML = `<span class="k">开仓前</span>`
      }
      const showNote = !!p.note && this.pausedKey === 'open'
      this.caption.hidden = !showNote
      if (showNote) this.caption.innerHTML = `<b>当时怎么想</b>${esc(p.note)}`
    } else if (p.kind === 'note') {
      this.float.hidden = false
      this.float.innerHTML = this.cur < p.judgeBar ? `<span class="k">判断之前</span>` : this.cur === p.judgeBar ? `<span class="k">判断时</span>` : `<span class="k">判断后</span><span>${Math.round((this.cur - p.judgeBar) / p.step)} 根</span>`
      const showText = !!p.text && this.pausedKey === 'judge'
      this.caption.hidden = !showText
      if (showText) this.caption.innerHTML = `<b>当时的判断</b>${esc(p.text)}`
    } else {
      const after = Math.round((this.cur - (p.rangeEnd - p.step)) / p.step)
      this.float.hidden = false
      this.float.innerHTML = after > 0 ? `<span class="k">相似段之后</span><span>${after} 根</span>` : `<span class="k">相似段</span>`
      this.caption.hidden = true
    }
  }

  // ---------------------------------------------------------------- 播放条
  private renderBar(loading = false): void {
    const p = this.plan
    if (!p) { this.bar.innerHTML = ''; return }
    const done = this.finished()
    const playIcon = this.playing ? 'pause' : done ? 'undo' : 'play'
    const playLabel = this.playing ? '暂停' : done ? '重播' : '播放'
    const tickCol = (k: string) => k === 'entry' ? 'var(--up)' : k === 'exit' ? 'var(--down)' : 'var(--accent)'
    this.bar.innerHTML = `
      <button class="ibtn sm rv-play" data-rp="toggle" aria-label="${playLabel}" data-tip="${playLabel}" data-kbd="空格" ${loading ? 'disabled' : ''}>${I(playIcon)}</button>
      <div class="rv-track${this.dragging ? ' dragging' : ''}" role="slider" tabindex="0" aria-label="回放进度" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0">
        <div class="rail"></div><div class="played"></div>
        ${p.ticks.map(t => `<i class="tick" style="left:${(trackPos(p, t.t) * 100).toFixed(3)}%;background:${tickCol(t.kind)}"></i>`).join('')}
        <div class="knob"></div>
      </div>
      <span class="rv-time num">${loading ? '载入中…' : ''}</span>
      <div class="seg rv-speed" role="group" aria-label="速度">${SPEEDS.map(s => `<button data-rp="speed" data-v="${s}" aria-pressed="${this.speed === s}">${s}×</button>`).join('')}</div>
      ${p.keys.map(k => `<button class="btn ghost sm" data-rp="key" data-k="${esc(k.id)}">${esc(k.label)}</button>`).join('')}`
    this.syncBar()
  }

  private syncBar(): void {
    const p = this.plan; if (!p) return
    const pos = trackPos(p, this.cur) * 100
    const tr = this.bar.querySelector<HTMLElement>('.rv-track'); if (!tr) return
    tr.querySelector<HTMLElement>('.played')!.style.width = pos + '%'
    tr.querySelector<HTMLElement>('.knob')!.style.left = pos + '%'
    tr.setAttribute('aria-valuenow', String(Math.round(pos)))
    tr.setAttribute('aria-valuetext', this.bars.length ? shTime(this.cur) : '')
    const tm = this.bar.querySelector<HTMLElement>('.rv-time')
    if (tm && this.bars.length) tm.textContent = shTime(this.cur)
    const btn = this.bar.querySelector<HTMLElement>('[data-rp="toggle"]')
    const want = this.playing ? 'pause' : this.finished() ? 'undo' : 'play'
    if (btn && btn.dataset.icon !== want) {
      btn.dataset.icon = want
      btn.innerHTML = I(want)
      const lab = this.playing ? '暂停' : this.finished() ? '重播' : '播放'
      btn.setAttribute('aria-label', lab); btn.dataset.tip = lab
    }
  }

  private bindBar(): void {
    this.bar.addEventListener('click', e => {
      const b = (e.target as HTMLElement).closest<HTMLElement>('[data-rp]'); if (!b) return
      const act = b.dataset.rp
      if (act === 'toggle') this.toggle()
      else if (act === 'speed') {
        this.speed = +(b.dataset.v || 1)
        this.bar.querySelectorAll('[data-rp="speed"]').forEach(x => x.setAttribute('aria-pressed', String(x === b)))
        if (this.playing) this.schedule(stepDelay(this.speed, false))
      } else if (act === 'key') this.jump(b.dataset.k || '')
    })
    // 进度线：按下即定位，拖动跟手；拖的时候暂停，松手按之前的状态继续
    this.bar.addEventListener('pointerdown', e => {
      const tr = (e.target as HTMLElement).closest<HTMLElement>('.rv-track'); if (!tr || !this.plan || !this.bars.length) return
      e.preventDefault()
      const wasPlaying = this.playing
      this.stop()
      this.dragging = true; tr.classList.add('dragging')
      const rect = tr.getBoundingClientRect()
      const at = (x: number) => { if (this.plan) this.seek(timeAtPos(this.plan, (x - rect.left) / rect.width)) }
      at(e.clientX)
      tr.setPointerCapture(e.pointerId)
      const mv = (ev: PointerEvent) => at(ev.clientX)
      const up = () => {
        tr.removeEventListener('pointermove', mv); tr.removeEventListener('pointerup', up); tr.removeEventListener('pointercancel', up)
        this.dragging = false; tr.classList.remove('dragging')
        if (wasPlaying && !this.finished()) this.play()
      }
      tr.addEventListener('pointermove', mv); tr.addEventListener('pointerup', up); tr.addEventListener('pointercancel', up)
    })
    // 键盘：进度线上 Home / End 到头到尾（不给方向键逐根挪）
    this.bar.addEventListener('keydown', e => {
      const tr = (e.target as HTMLElement).closest('.rv-track'); if (!tr || !this.plan) return
      if (e.key === 'Home' || e.key === 'End') { e.preventDefault(); this.stop(); this.seek(e.key === 'Home' ? this.plan.startBar : this.plan.stopBar) }
    })
  }
}
