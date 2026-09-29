/* Hkline Web · K 线引擎（TradingView 桌面版的那一套）
 *
 * 和手机那套（AICoin 复刻）完全分开。对齐的是 TradingView 桌面版：
 *   · 多窗格：主图 + 最多三个副图，窗格之间 1 px 分隔、可拖动改高度
 *   · 右侧价格轴：最新价标签（实心、涨跌色）下面一行是本根收线倒计时；十字线在轴上出深色标签
 *   · 十字线：鼠标悬停就出（不用按住），虚线，横竖都在轴上标值
 *   · 左上角图例：品种 · 周期 · 交易所 + 开高低收 + 涨跌；每个指标一行，悬停出现 显示/设置/移除
 *   · 成交量叠在主图底部 20%，半透明
 *   · 滚轮缩放（以光标为中心）、拖动平移、拖价格轴缩放价格、拖时间轴缩放时间、双击价格轴回到自动
 *   · 往左拖到头自动加载更早的历史
 * 时间一律按上海时间（UTC+8）显示。
 */
(function (g) {
  'use strict'

  const TZ = 8 * 3600e3
  const AXIS_H = 28
  const MIN_PANE_H = 56 // 拖分隔线时任何一格都不能比这矮
  const MIN_SPACING = 1.5
  const MAX_SPACING = 60
  const DEFAULT_SPACING = 7
  const RIGHT_MARGIN_BARS = 6
  const SEP_HIT = 5
  const WEEK = ['日', '一', '二', '三', '四', '五', '六']

  // ------------------------------------------------------------ 指标计算
  function sma(src, n) {
    const out = new Array(src.length).fill(null); let s = 0
    for (let i = 0; i < src.length; i++) { s += src[i]; if (i >= n) s -= src[i - n]; if (i >= n - 1) out[i] = s / n }
    return out
  }
  function ema(src, n) {
    const out = new Array(src.length).fill(null); const k = 2 / (n + 1); let e = null
    for (let i = 0; i < src.length; i++) {
      if (src[i] == null) continue
      if (e == null) { if (i >= n - 1) { let s = 0; for (let j = i - n + 1; j <= i; j++) s += src[j]; e = s / n; out[i] = e } continue }
      e = src[i] * k + e * (1 - k); out[i] = e
    }
    return out
  }
  function rma(src, n) {
    const out = new Array(src.length).fill(null); let r = null, s = 0
    for (let i = 0; i < src.length; i++) {
      if (i < n) { s += src[i]; if (i === n - 1) { r = s / n; out[i] = r } continue }
      r = (r * (n - 1) + src[i]) / n; out[i] = r
    }
    return out
  }
  const Calc = {
    ma(bars, p) { const c = bars.map(b => b.c); return p.periods.map(n => sma(c, n)) },
    ema(bars, p) { const c = bars.map(b => b.c); return p.periods.map(n => ema(c, n)) },
    boll(bars, p) {
      const c = bars.map(b => b.c), n = p.n, k = p.k, mid = sma(c, n), up = [], dn = []
      for (let i = 0; i < c.length; i++) {
        if (mid[i] == null) { up.push(null); dn.push(null); continue }
        let v = 0; for (let j = i - n + 1; j <= i; j++) v += (c[j] - mid[i]) ** 2
        const sd = Math.sqrt(v / n); up.push(mid[i] + k * sd); dn.push(mid[i] - k * sd)
      }
      return [mid, up, dn]
    },
    macd(bars, p) {
      const c = bars.map(b => b.c), f = ema(c, p.fast), s = ema(c, p.slow)
      const dif = c.map((_, i) => f[i] != null && s[i] != null ? f[i] - s[i] : null)
      const firstIdx = dif.findIndex(v => v != null)
      const dea = new Array(c.length).fill(null)
      if (firstIdx >= 0) { const d2 = ema(dif.slice(firstIdx), p.signal); for (let i = 0; i < d2.length; i++) dea[firstIdx + i] = d2[i] }
      const hist = dif.map((v, i) => v != null && dea[i] != null ? v - dea[i] : null)
      return [dif, dea, hist]
    },
    rsi(bars, p) {
      const c = bars.map(b => b.c), up = [0], dn = [0]
      for (let i = 1; i < c.length; i++) { const d = c[i] - c[i - 1]; up.push(Math.max(d, 0)); dn.push(Math.max(-d, 0)) }
      const ru = rma(up, p.n), rd = rma(dn, p.n)
      return [c.map((_, i) => ru[i] == null ? null : rd[i] === 0 ? 100 : 100 - 100 / (1 + ru[i] / rd[i]))]
    },
    kdj(bars, p) {
      const K = [], D = [], J = []; let k = 50, d = 50
      for (let i = 0; i < bars.length; i++) {
        if (i < p.n - 1) { K.push(null); D.push(null); J.push(null); continue }
        let hi = -Infinity, lo = Infinity
        for (let j = i - p.n + 1; j <= i; j++) { hi = Math.max(hi, bars[j].h); lo = Math.min(lo, bars[j].l) }
        const rsv = hi === lo ? 50 : (bars[i].c - lo) / (hi - lo) * 100
        k = (k * (p.m1 - 1) + rsv) / p.m1; d = (d * (p.m2 - 1) + k) / p.m2
        K.push(k); D.push(d); J.push(3 * k - 2 * d)
      }
      return [K, D, J]
    },
    oi(bars) { return [bars.map(b => b.oi ?? null)] },
  }

  // 指标目录：名字、默认参数、线色。副图最多三个（手机端同一条规矩）。
  const CATALOG = {
    ma: { name: 'MA', cn: '均线', place: 'main', params: { periods: [10, 30, 120, 256] }, colors: ['#F7A600', '#2962FF', '#AB47BC', '#26C6DA'] },
    ema: { name: 'EMA', cn: '指数均线', place: 'main', params: { periods: [12, 26] }, colors: ['#FF6D00', '#00897B'] },
    boll: { name: 'BOLL', cn: '布林带', place: 'main', params: { n: 20, k: 2 }, colors: ['#FF6D00', '#2962FF', '#2962FF'] },
    vol: { name: '成交量', cn: '成交量', place: 'overlay' },
    macd: { name: 'MACD', cn: '平滑异同', place: 'sub', params: { fast: 12, slow: 26, signal: 9 }, colors: ['#2962FF', '#FF6D00'] },
    rsi: { name: 'RSI', cn: '相对强弱', place: 'sub', params: { n: 14 }, colors: ['#7E57C2'] },
    kdj: { name: 'KDJ', cn: '随机指标', place: 'sub', params: { n: 9, m1: 3, m2: 3 }, colors: ['#2962FF', '#FF6D00', '#AB47BC'] },
    oi: { name: '持仓量', cn: '持仓量', place: 'sub', params: {}, colors: ['#2962FF'] },
  }
  function paramText(id, p) {
    if (!p) return ''
    if (p.periods) return p.periods.join(' ')
    return Object.values(p).join(' ')
  }

  // ------------------------------------------------------------ 数字
  function fmt(v, dec) {
    if (v == null || !isFinite(v)) return '—'
    return v.toLocaleString('en-US', { minimumFractionDigits: dec, maximumFractionDigits: dec })
  }
  function fmtAxis(v, dec) { return v == null ? '' : v.toFixed(dec) }
  function fmtCompact(v) {
    if (v == null || !isFinite(v)) return '—'
    const a = Math.abs(v)
    if (a >= 1e12) return (v / 1e12).toFixed(2) + 'T'
    if (a >= 1e9) return (v / 1e9).toFixed(2) + 'B'
    if (a >= 1e6) return (v / 1e6).toFixed(2) + 'M'
    if (a >= 1e3) return (v / 1e3).toFixed(2) + 'K'
    return v.toFixed(a < 10 ? 2 : 0)
  }
  function sh(t) { return new Date(t + TZ) } // 读 UTC 字段 = 上海时间
  const pad = n => String(n).padStart(2, '0')
  function crossTimeLabel(t, iv) {
    const d = sh(t)
    const date = `${d.getUTCFullYear() % 100}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} 周${WEEK[d.getUTCDay()]}`
    return iv >= 864e5 ? date : `${date}  ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`
  }

  function niceStep(raw) {
    const p = Math.pow(10, Math.floor(Math.log10(raw))), f = raw / p
    const n = f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10
    return n * p
  }

  // ------------------------------------------------------------ 引擎
  class TVChart {
    constructor(host, opts = {}) {
      this.host = host
      this.o = opts
      this.canvas = document.createElement('canvas')
      host.appendChild(this.canvas)
      this.ctx = this.canvas.getContext('2d')
      this.legendEl = document.createElement('div'); this.legendEl.className = 'legend'; host.appendChild(this.legendEl)
      this.paneLegendEls = []
      this.bars = []
      this.iv = 36e5
      this.meta = { symbol: '', title: '', sub: '', dec: 2 }
      this.spacing = DEFAULT_SPACING
      this.rightBar = 0
      this.ind = { ma: true, ema: false, boll: false, vol: true, subs: ['macd', 'rsi'] }
      this.params = JSON.parse(JSON.stringify(Object.fromEntries(Object.entries(CATALOG).map(([k, v]) => [k, v.params || {}]))))
      this.hidden = new Set()
      this.paneH = {}
      this.series = {}
      this.log = false
      this.auto = true
      this.manual = null // 主图手动价格区间 {min,max}
      this.cross = null   // {x,y}
      this.extCross = null // 同步来的时间
      this.drawings = []
      this.tool = null
      this.draft = null
      this.selected = null
      this.magnet = false
      this.walls = null
      this.alerts = []
      this.markers = null
      this.replay = null
      this.stale = false
      this.drag = null
      this.dirty = true
      this.hoverWall = null
      this.colors = {}
      this.readTheme()
      this.bind()
      this.ro = new ResizeObserver(() => { this.resize(); this.render(true) })
      this.ro.observe(host)
      this.resize()
      this.loop = this.loop.bind(this)
      requestAnimationFrame(this.loop)
    }

    // ---------------------------------------------------------- 外部接口
    readTheme() {
      const cs = getComputedStyle(this.host)
      const v = n => cs.getPropertyValue(n).trim()
      this.colors = {
        bg: v('--chart-bg'), grid: v('--chart-grid'), text: v('--chart-axis-text'), text2: v('--text-2'), text3: v('--text-3'),
        cross: v('--chart-cross'), crossLabel: v('--chart-cross-label'), scaleLine: v('--chart-scale-line'),
        up: v('--up'), down: v('--down'), accent: v('--accent'), alert: v('--alert-line'), line: v('--line'),
      }
      this.font = `12px ${getComputedStyle(document.body).getPropertyValue('--font-num') || 'sans-serif'}`
      this.dirty = true
    }
    setData(bars, meta) {
      const sameSym = this.meta.symbol === meta.symbol && this.iv === meta.iv
      this.bars = bars
      this.iv = meta.iv
      this.meta = Object.assign({}, this.meta, meta)
      if (!sameSym) { this.rightBar = bars.length - 1 + RIGHT_MARGIN_BARS; this.manual = null; this.auto = true; this.o.onAutoChange?.(true) }
      this.recalc(); this.dirty = true; this.renderLegend()
    }
    prependData(more) {
      if (!more.length) return
      const first = this.bars[0]?.t ?? Infinity
      more = more.filter(b => b.t < first)
      this.bars = more.concat(this.bars)
      this.rightBar += more.length
      if (this.replay != null) this.replay += more.length
      this.recalc(); this.dirty = true
    }
    updateBar(b) {
      const n = this.bars.length
      if (!n) return
      const last = this.bars[n - 1]
      if (b.t === last.t) { Object.assign(last, b) }
      else if (b.t > last.t) {
        const atEdge = this.rightBar >= n - 1
        this.bars.push(b)
        if (atEdge) this.rightBar += 1
      } else return
      this.recalcTail(); this.dirty = true
      if (!this.cross) this.renderLegend()
    }
    setIndicators(ind) { this.ind = Object.assign({}, this.ind, ind); this.recalc(); this.dirty = true; this.renderLegend() }
    setParams(id, p) { this.params[id] = p; this.recalc(); this.dirty = true; this.renderLegend() }
    setDrawings(arr) { this.drawings = arr; this.selected = null; this.dirty = true }
    setTool(t) { this.tool = t; this.draft = null; this.canvas.style.cursor = t ? 'crosshair' : 'crosshair'; this.dirty = true }
    setMagnet(on) { this.magnet = on }
    setWalls(w) { this.walls = w; this.dirty = true }
    setAlerts(a) { this.alerts = a || []; this.dirty = true }
    setMarkers(m) { this.markers = m; this.dirty = true }
    setReplay(i) { this.replay = i; this.dirty = true; this.renderLegend() }
    setLog(on) { this.log = on; this.manual = null; this.dirty = true }
    setAuto(on) { this.auto = on; if (on) this.manual = null; this.dirty = true; this.o.onAutoChange?.(on) }
    setStale(on) { this.stale = on; this.dirty = true; this.renderLegend() }
    syncCrosshair(t) { this.extCross = t; this.dirty = true }
    resetView() { this.spacing = DEFAULT_SPACING; this.rightBar = this.lastIndex() + RIGHT_MARGIN_BARS; this.setAuto(true) }
    setVisibleRange(t0, t1) {
      const i0 = this.indexAt(t0), i1 = this.indexAt(t1)
      const n = Math.max(10, i1 - i0 + 1)
      this.spacing = clamp(this.plotW() / (n + RIGHT_MARGIN_BARS), MIN_SPACING, MAX_SPACING)
      this.rightBar = i1 + RIGHT_MARGIN_BARS; this.setAuto(true)
    }
    scrollBars(k) { this.rightBar += k; this.dirty = true; this.maybeMore() }
    zoom(f, anchorX) {
      const ax = anchorX ?? this.plotW()
      const idx = this.xToIndex(ax)
      this.spacing = clamp(this.spacing * f, MIN_SPACING, MAX_SPACING)
      this.rightBar = idx + (this.plotW() - ax) / this.spacing
      this.dirty = true; this.maybeMore()
    }
    lastIndex() { return this.replay != null ? this.replay : this.bars.length - 1 }
    destroy() { this.ro.disconnect(); this.dead = true; this.host.innerHTML = '' }

    // ---------------------------------------------------------- 指标
    recalc() {
      this.series = {}
      const b = this.bars
      if (!b.length) return
      for (const id of ['ma', 'ema', 'boll']) if (this.ind[id]) this.series[id] = Calc[id](b, this.params[id])
      for (const id of this.ind.subs) this.series[id] = Calc[id](b, this.params[id])
    }
    recalcTail() { this.recalc() }

    // ---------------------------------------------------------- 几何
    resize() {
      const r = this.host.getBoundingClientRect()
      this.w = Math.max(10, r.width); this.h = Math.max(10, r.height)
      const dpr = window.devicePixelRatio || 1
      this.canvas.width = Math.round(this.w * dpr); this.canvas.height = Math.round(this.h * dpr)
      this.canvas.style.width = this.w + 'px'; this.canvas.style.height = this.h + 'px'
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
      this.dirty = true
    }
    axisW() {
      this.ctx.font = this.font
      const r = this.mainRange || { max: this.bars[this.bars.length - 1]?.h || 100 }
      const s = fmtAxis(r.max, this.meta.dec)
      return Math.max(56, Math.ceil(this.ctx.measureText(s).width) + 20)
    }
    plotW() { return this.w - this.aw }
    // 副图默认矮：每个副图取画布高的 11%，夹在 96–136 px（2K 屏上约 132 px，TradingView 桌面版的比例），
    // 主图拿剩下的全部。副图再多也只是多几档，不是把每档拉高；合计不超过画布的 55%。
    // 用户拖过的分隔线记在 paneH（像素），窗口高度变了副图保持不动、主图跟着伸缩。
    subDefaultH() { return clamp(Math.round((this.h - AXIS_H) * 0.11), 96, 136) }
    panes() {
      const subs = this.ind.subs
      const H = this.h - AXIS_H, def = this.subDefaultH()
      let hs = subs.map(id => this.paneH[id] || def)
      const cap = Math.round(H * 0.55), sum = hs.reduce((a, b) => a + b, 0)
      if (sum > cap) hs = hs.map(h => Math.max(MIN_PANE_H, Math.round(h * cap / sum)))
      const mainH = H - hs.reduce((a, b) => a + b, 0)
      let y = 0
      return ['main', ...subs].map((id, i) => {
        const h = i === 0 ? mainH : i === subs.length ? H - y : hs[i - 1]
        const p = { id, y, h }; y += h; return p
      })
    }
    indexToX(i) { return this.plotW() - (this.rightBar - i) * this.spacing }
    xToIndex(x) { return this.rightBar - (this.plotW() - x) / this.spacing }
    indexAt(t) { // 时间 → 连续下标（可以在数据两头外推）
      const b = this.bars, n = b.length
      if (!n) return 0
      if (t <= b[0].t) return (t - b[0].t) / this.iv
      if (t >= b[n - 1].t) return n - 1 + (t - b[n - 1].t) / this.iv
      let lo = 0, hi = n - 1
      while (hi - lo > 1) { const m = (lo + hi) >> 1; if (b[m].t <= t) lo = m; else hi = m }
      return lo + (t - b[lo].t) / Math.max(1, b[hi].t - b[lo].t)
    }
    timeAt(i) {
      const b = this.bars, n = b.length
      if (!n) return 0
      const k = Math.round(i)
      if (k < 0) return b[0].t + k * this.iv
      if (k >= n) return b[n - 1].t + (k - n + 1) * this.iv
      return b[k].t
    }
    visible() {
      const n = this.lastIndex() + 1
      const from = Math.max(0, Math.floor(this.xToIndex(0)))
      const to = Math.min(n - 1, Math.ceil(this.rightBar))
      return { from, to }
    }
    tf(v) { return this.log ? Math.log(Math.max(v, 1e-12)) : v }
    itf(v) { return this.log ? Math.exp(v) : v }
    priceToY(p, pane, r) { const a = this.tf(r.max), b = this.tf(r.min); return pane.y + 8 + (a - this.tf(p)) / (a - b) * (pane.h - 16) }
    yToPrice(y, pane, r) { const a = this.tf(r.max), b = this.tf(r.min); return this.itf(a - (y - pane.y - 8) / (pane.h - 16) * (a - b)) }

    rangeMain(from, to) {
      if (this.manual) return this.manual
      let lo = Infinity, hi = -Infinity
      for (let i = from; i <= to; i++) { const b = this.bars[i]; if (!b) continue; lo = Math.min(lo, b.l); hi = Math.max(hi, b.h) }
      for (const id of ['ma', 'ema', 'boll']) {
        if (!this.series[id] || this.hidden.has(id)) continue
        for (const s of this.series[id]) for (let i = from; i <= to; i++) { const v = s[i]; if (v != null) { lo = Math.min(lo, v); hi = Math.max(hi, v) } }
      }
      if (!isFinite(lo)) { lo = 0; hi = 1 }
      if (this.log) { const a = Math.log(lo), b = Math.log(hi), pad = (b - a) * 0.08 || 0.01; return { min: Math.exp(a - pad), max: Math.exp(b + pad) } }
      const pad = (hi - lo) * 0.08 || hi * 0.01 || 1
      return { min: lo - pad, max: hi + pad }
    }
    rangeSub(id, from, to) {
      if (id === 'rsi') return { min: 0, max: 100 }
      let lo = Infinity, hi = -Infinity
      for (const s of this.series[id] || []) for (let i = from; i <= to; i++) { const v = s[i]; if (v != null) { lo = Math.min(lo, v); hi = Math.max(hi, v) } }
      if (!isFinite(lo)) return { min: 0, max: 1 }
      if (id === 'macd') { const m = Math.max(Math.abs(lo), Math.abs(hi)) || 1; return { min: -m * 1.1, max: m * 1.1 } }
      const pad = (hi - lo) * 0.1 || 1; return { min: lo - pad, max: hi + pad }
    }

    // ---------------------------------------------------------- 渲染
    loop() {
      if (this.dead) return
      if (this.dirty) { this.dirty = false; this.render() }
      requestAnimationFrame(this.loop)
    }
    render() {
      const c = this.ctx, C = this.colors
      this.aw = this.axisW()
      const W = this.w, H = this.h, PW = this.plotW()
      c.clearRect(0, 0, W, H)
      c.fillStyle = C.bg; c.fillRect(0, 0, W, H)
      if (!this.bars.length) return
      const { from, to } = this.visible()
      const panes = this.panes()
      this._panes = panes
      const mainPane = panes[0]
      const mr = this.rangeMain(from, to); this.mainRange = mr
      this._ranges = { main: mr }
      for (const p of panes.slice(1)) this._ranges[p.id] = this.rangeSub(p.id, from, to)

      // 网格 + 价格刻度
      c.font = this.font; c.textBaseline = 'middle'
      for (const p of panes) {
        const r = this._ranges[p.id]
        const ticks = this.priceTicks(p, r)
        p.ticks = ticks
        c.strokeStyle = C.grid; c.lineWidth = 1; c.beginPath()
        for (const t of ticks) { const y = Math.round(this.priceToY(t, p, r)) + .5; c.moveTo(0, y); c.lineTo(PW, y) }
        c.stroke()
      }
      const tticks = this.timeTicks(from, to)
      c.strokeStyle = C.grid; c.beginPath()
      for (const t of tticks) { const x = Math.round(this.indexToX(t.i)) + .5; c.moveTo(x, 0); c.lineTo(x, H - AXIS_H) }
      c.stroke()

      // 主图
      c.save(); c.beginPath(); c.rect(0, mainPane.y, PW, mainPane.h); c.clip()
      if (this.ind.vol && !this.hidden.has('vol')) this.drawVolume(mainPane, from, to)
      if (this.walls && !this.hidden.has('walls')) this.drawWalls(mainPane, mr, from, to)
      if (this.markers) this.drawTradeSpan(mainPane, mr)
      this.drawCandles(mainPane, mr, from, to)
      for (const id of ['boll', 'ema', 'ma']) if (this.series[id] && !this.hidden.has(id)) this.drawLines(id, mainPane, mr, from, to)
      this.drawLastLine(mainPane, mr)
      this.drawAlertLines(mainPane, mr)
      this.drawDrawings(mainPane, mr)
      if (this.markers) this.drawMarkers(mainPane, mr)
      c.restore()

      // 副图
      for (const p of panes.slice(1)) {
        c.save(); c.beginPath(); c.rect(0, p.y, PW, p.h); c.clip()
        this.drawSub(p, this._ranges[p.id], from, to)
        c.restore()
      }

      // 分隔线与轴
      c.strokeStyle = C.scaleLine; c.lineWidth = 1; c.beginPath()
      for (const p of panes.slice(1)) { c.moveTo(0, p.y + .5); c.lineTo(W, p.y + .5) }
      c.moveTo(PW + .5, 0); c.lineTo(PW + .5, H - AXIS_H)
      c.moveTo(0, H - AXIS_H + .5); c.lineTo(W, H - AXIS_H + .5)
      c.stroke()

      c.fillStyle = C.text; c.textAlign = 'left'
      for (const p of panes) {
        const r = this._ranges[p.id]
        for (const t of p.ticks) {
          const y = this.priceToY(t, p, r)
          if (y < p.y + 8 || y > p.y + p.h - 6) continue
          c.fillText(p.id === 'main' ? fmtAxis(t, this.meta.dec) : this.subFmt(p.id, t), PW + 8, y)
        }
      }
      c.textAlign = 'center'
      for (const t of tticks) {
        const x = this.indexToX(t.i)
        if (x < 20 || x > PW - 20) continue
        c.font = t.bold ? `600 ${this.font}` : this.font
        c.fillText(t.label, x, H - AXIS_H / 2)
      }
      c.font = this.font

      this.drawPriceLabels(mainPane, mr)
      this.drawCrosshair(panes)
      this.renderPaneLegends(panes)
    }

    priceTicks(p, r) {
      const n = Math.max(2, Math.floor(p.h / 56))
      if (this.log && p.id === 'main') {
        const out = [], a = Math.log(r.min), b = Math.log(r.max)
        for (let i = 1; i <= n; i++) { const v = Math.exp(a + (b - a) * i / (n + 1)); const st = niceStep(v / 20); out.push(Math.round(v / st) * st) }
        return out
      }
      const step = niceStep((r.max - r.min) / n)
      const out = []
      for (let v = Math.ceil(r.min / step) * step; v <= r.max; v += step) out.push(+v.toFixed(10))
      return out
    }
    subFmt(id, v) { if (id === 'rsi' || id === 'kdj') return v.toFixed(0); if (id === 'oi') return fmtCompact(v); return fmtCompact(v) === '—' ? '' : (Math.abs(v) >= 1000 ? fmtCompact(v) : v.toFixed(Math.abs(v) < 10 ? 2 : 1)) }

    timeTicks(from, to) {
      const out = []
      if (!this.bars.length) return out
      const minPx = 96
      const barsPer = Math.max(1, Math.ceil(minPx / this.spacing))
      const span = barsPer * this.iv
      const steps = [60e3, 5 * 60e3, 15 * 60e3, 30 * 60e3, 36e5, 2 * 36e5, 3 * 36e5, 6 * 36e5, 12 * 36e5, 864e5, 2 * 864e5, 7 * 864e5, 14 * 864e5, 30 * 864e5, 91 * 864e5, 182 * 864e5, 365 * 864e5]
      const step = steps.find(s => s >= span && s >= this.iv) || 365 * 864e5
      const lo = Math.max(0, Math.floor(this.xToIndex(0))), hi = Math.ceil(this.rightBar)
      let lastX = -Infinity
      for (let i = lo; i <= hi; i++) {
        const t = this.timeAt(i), tp = this.timeAt(i - 1)
        const d = sh(t), dp = sh(tp)
        let hit = false, label = '', bold = false
        if (step >= 30 * 864e5) {
          const mStep = Math.round(step / (30 * 864e5))
          if (d.getUTCMonth() !== dp.getUTCMonth() && d.getUTCMonth() % mStep === 0) { hit = true; label = d.getUTCMonth() === 0 ? String(d.getUTCFullYear()) : `${d.getUTCMonth() + 1}月`; bold = d.getUTCMonth() === 0 }
        } else if (step >= 864e5) {
          const dStep = Math.round(step / 864e5)
          if (d.getUTCDate() !== dp.getUTCDate() || i === lo) {
            if (d.getUTCMonth() !== dp.getUTCMonth()) { hit = true; label = d.getUTCMonth() === 0 ? String(d.getUTCFullYear()) : `${d.getUTCMonth() + 1}月`; bold = true }
            else if (dStep === 7 ? d.getUTCDay() === 1 : (d.getUTCDate() - 1) % dStep === 0 && d.getUTCDate() < 29) { hit = true; label = String(d.getUTCDate()) }
          }
        } else {
          const ms = (t + TZ) % 864e5
          if (d.getUTCDate() !== dp.getUTCDate()) { hit = true; label = d.getUTCDate() === 1 ? `${d.getUTCMonth() + 1}月` : String(d.getUTCDate()); bold = true }
          else if (ms % step === 0) { hit = true; label = `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}` }
        }
        if (!hit) continue
        const x = this.indexToX(i)
        if (x - lastX < minPx * 0.8) { if (bold && out.length && !out[out.length - 1].bold) { out[out.length - 1] = { i, label, bold }; lastX = x } continue }
        out.push({ i, label, bold }); lastX = x
      }
      return out
    }

    candleW() { return Math.max(1, Math.round(this.spacing * 0.78) - (this.spacing > 4 ? 1 : 0)) }
    drawCandles(p, r, from, to) {
      const c = this.ctx, C = this.colors, bw = this.candleW()
      const half = Math.floor(bw / 2)
      for (const pass of [0, 1]) {
        c.fillStyle = pass ? C.up : C.down
        c.beginPath()
        for (let i = from; i <= to; i++) {
          const b = this.bars[i]; if (!b) continue
          const up = b.c >= b.o
          if ((pass === 1) !== up) continue
          const x = Math.round(this.indexToX(i))
          const yh = this.priceToY(b.h, p, r), yl = this.priceToY(b.l, p, r)
          const yo = this.priceToY(b.o, p, r), yc = this.priceToY(b.c, p, r)
          c.rect(x, Math.round(yh), 1, Math.max(1, Math.round(yl) - Math.round(yh)))
          if (bw > 1) {
            const top = Math.round(Math.min(yo, yc)), bot = Math.round(Math.max(yo, yc))
            c.rect(x - half, top, bw, Math.max(1, bot - top))
          }
        }
        c.fill()
      }
    }
    drawVolume(p, from, to) {
      const c = this.ctx, C = this.colors, bw = this.candleW()
      let mx = 0
      for (let i = from; i <= to; i++) mx = Math.max(mx, this.bars[i]?.v || 0)
      if (!mx) return
      const h = p.h * 0.2, base = p.y + p.h
      const half = Math.floor(bw / 2)
      for (const pass of [0, 1]) {
        c.fillStyle = hexA(pass ? C.up : C.down, 0.42)
        c.beginPath()
        for (let i = from; i <= to; i++) {
          const b = this.bars[i]; if (!b) continue
          if ((b.c >= b.o) !== (pass === 1)) continue
          const x = Math.round(this.indexToX(i)), vh = Math.max(1, b.v / mx * h)
          c.rect(x - half, Math.round(base - vh), Math.max(1, bw), Math.round(vh))
        }
        c.fill()
      }
    }
    drawLines(id, p, r, from, to) {
      const c = this.ctx, cat = CATALOG[id], ser = this.series[id]
      if (id === 'boll') {
        c.fillStyle = hexA('#2962FF', 0.06); c.beginPath()
        let started = false
        for (let i = from; i <= to; i++) { const v = ser[1][i]; if (v == null) continue; const x = this.indexToX(i), y = this.priceToY(v, p, r); started ? c.lineTo(x, y) : (c.moveTo(x, y), started = true) }
        for (let i = to; i >= from; i--) { const v = ser[2][i]; if (v == null) continue; c.lineTo(this.indexToX(i), this.priceToY(v, p, r)) }
        c.fill()
      }
      c.lineWidth = 1.5; c.lineJoin = 'round'
      ser.forEach((s, k) => {
        c.strokeStyle = cat.colors[k % cat.colors.length]; c.beginPath()
        let started = false
        for (let i = Math.max(0, from - 1); i <= to; i++) {
          const v = s[i]; if (v == null) { started = false; continue }
          const x = this.indexToX(i), y = this.priceToY(v, p, r)
          started ? c.lineTo(x, y) : (c.moveTo(x, y), started = true)
        }
        c.stroke()
      })
    }
    drawSub(p, r, from, to) {
      const c = this.ctx, C = this.colors, id = p.id, ser = this.series[id], cat = CATALOG[id]
      if (!ser || this.hidden.has(id)) return
      const y = v => this.priceToY(v, p, r)
      if (id === 'macd') {
        const bw = this.candleW(), half = Math.floor(bw / 2), y0 = y(0)
        for (let i = from; i <= to; i++) {
          const v = ser[2][i]; if (v == null) continue
          const prev = ser[2][i - 1] ?? v
          const col = v >= 0 ? C.up : C.down
          c.fillStyle = (v >= 0 ? v >= prev : v <= prev) ? col : hexA(col, 0.45)
          const x = Math.round(this.indexToX(i)), yy = y(v)
          c.fillRect(x - half, Math.min(y0, yy), Math.max(1, bw), Math.max(1, Math.abs(yy - y0)))
        }
        this.polyline(ser[0], p, r, from, to, cat.colors[0]); this.polyline(ser[1], p, r, from, to, cat.colors[1])
      } else if (id === 'rsi') {
        const y70 = y(70), y30 = y(30)
        c.fillStyle = hexA('#7E57C2', 0.08); c.fillRect(0, y70, this.plotW(), y30 - y70)
        c.setLineDash([4, 4]); c.strokeStyle = hexA(C.text3 || '#888', 0.7); c.lineWidth = 1; c.beginPath()
        c.moveTo(0, Math.round(y70) + .5); c.lineTo(this.plotW(), Math.round(y70) + .5); c.moveTo(0, Math.round(y30) + .5); c.lineTo(this.plotW(), Math.round(y30) + .5); c.stroke(); c.setLineDash([])
        this.polyline(ser[0], p, r, from, to, cat.colors[0])
      } else {
        ser.forEach((s, k) => this.polyline(s, p, r, from, to, cat.colors[k % cat.colors.length]))
      }
    }
    polyline(s, p, r, from, to, col) {
      const c = this.ctx; c.strokeStyle = col; c.lineWidth = 1.5; c.beginPath(); let st = false
      for (let i = Math.max(0, from - 1); i <= to; i++) { const v = s[i]; if (v == null) { st = false; continue } const x = this.indexToX(i), y = this.priceToY(v, p, r); st ? c.lineTo(x, y) : (c.moveTo(x, y), st = true) }
      c.stroke()
    }
    lastBar() { return this.bars[this.lastIndex()] }
    drawLastLine(p, r) {
      const b = this.lastBar(); if (!b) return
      const c = this.ctx, y = Math.round(this.priceToY(b.c, p, r)) + .5
      c.strokeStyle = this.stale ? this.colors.text3 : (b.c >= b.o ? this.colors.up : this.colors.down)
      c.setLineDash([1, 2]); c.lineWidth = 1; c.beginPath(); c.moveTo(0, y); c.lineTo(this.plotW(), y); c.stroke(); c.setLineDash([])
    }
    drawAlertLines(p, r) {
      const c = this.ctx
      for (const a of this.alerts) {
        const y = Math.round(this.priceToY(a.price, p, r)) + .5
        if (y < p.y || y > p.y + p.h) continue
        c.strokeStyle = this.colors.alert; c.setLineDash([6, 4]); c.lineWidth = 1; c.beginPath(); c.moveTo(0, y); c.lineTo(this.plotW(), y); c.stroke(); c.setLineDash([])
      }
    }
    drawPriceLabels(p, r) {
      const c = this.ctx, C = this.colors, PW = this.plotW()
      const label = (y, text, bg, fg, sub) => {
        const h = sub ? 34 : 20
        const top = clamp(y - 10, p.y, p.y + p.h - h)
        c.fillStyle = bg; roundRect(c, PW + 1, top, this.aw - 2, h, 3); c.fill()
        c.fillStyle = fg; c.textAlign = 'left'; c.font = `600 ${this.font}`
        c.fillText(text, PW + 8, top + 10)
        if (sub) { c.font = this.font; c.globalAlpha = .85; c.fillText(sub, PW + 8, top + 25); c.globalAlpha = 1 }
        c.font = this.font
      }
      for (const a of this.alerts) {
        const y = this.priceToY(a.price, p, r); if (y < p.y || y > p.y + p.h) continue
        label(y, fmtAxis(a.price, this.meta.dec), C.alert, '#fff')
      }
      const b = this.lastBar(); if (!b) return
      const y = this.priceToY(b.c, p, r)
      const col = this.stale ? C.text3 : (b.c >= b.o ? C.up : C.down)
      let sub = null
      if (this.replay == null && this.iv < 30 * 864e5) {
        const left = Math.max(0, b.t + this.iv - Date.now())
        const s = Math.floor(left / 1000), hh = Math.floor(s / 3600), mm = Math.floor(s % 3600 / 60), ss = s % 60
        sub = hh >= 24 ? `${Math.floor(hh / 24)}天 ${pad(hh % 24)}时` : hh ? `${pad(hh)}:${pad(mm)}:${pad(ss)}` : `${pad(mm)}:${pad(ss)}`
      }
      label(y, fmtAxis(b.c, this.meta.dec), col, '#fff', sub)
      if (this.cross && this.cross.pane === 'main') {} // 十字线标签画在最上层
    }
    drawCrosshair(panes) {
      const c = this.ctx, C = this.colors, PW = this.plotW(), H = this.h
      let x = null, idx = null
      if (this.cross) { idx = Math.round(this.xToIndex(this.cross.x)); x = this.indexToX(idx) }
      else if (this.extCross != null) { idx = Math.round(this.indexAt(this.extCross)); x = this.indexToX(idx) }
      if (x == null || x < 0 || x > PW) return
      c.strokeStyle = C.cross; c.lineWidth = 1; c.setLineDash([5, 4])
      c.beginPath(); c.moveTo(Math.round(x) + .5, 0); c.lineTo(Math.round(x) + .5, H - AXIS_H)
      let y = null, pane = null
      if (this.cross) {
        y = this.cross.y
        if (this.magnet && this.cross.pane === 'main') { const b = this.bars[idx]; if (b) { const r = this._ranges.main, p = panes[0]; const cands = [b.o, b.h, b.l, b.c].map(v => this.priceToY(v, p, r)); y = cands.reduce((a, v) => Math.abs(v - this.cross.y) < Math.abs(a - this.cross.y) ? v : a) } }
        pane = panes.find(p => y >= p.y && y < p.y + p.h)
        if (pane) { c.moveTo(0, Math.round(y) + .5); c.lineTo(PW, Math.round(y) + .5) }
      }
      c.stroke(); c.setLineDash([])
      // 轴上标签
      c.font = this.font; c.textBaseline = 'middle'
      const tl = crossTimeLabel(this.timeAt(idx), this.iv)
      const tw = c.measureText(tl).width + 16
      c.fillStyle = C.crossLabel; roundRect(c, clamp(x - tw / 2, 0, PW - tw), H - AXIS_H + 2, tw, AXIS_H - 4, 3); c.fill()
      c.fillStyle = '#fff'; c.textAlign = 'center'; c.fillText(tl, clamp(x, tw / 2, PW - tw / 2), H - AXIS_H / 2)
      if (pane) {
        const r = this._ranges[pane.id], v = this.yToPrice(y, pane, r)
        const s = pane.id === 'main' ? fmtAxis(v, this.meta.dec) : this.subFmt(pane.id, v)
        c.fillStyle = C.crossLabel; roundRect(c, PW + 1, y - 10, this.aw - 2, 20, 3); c.fill()
        c.fillStyle = '#fff'; c.textAlign = 'left'; c.fillText(s, PW + 8, y)
      }
    }

    // ---- 订单流：大单画成垫在蜡烛下面的细线，签在右端
    drawWalls(p, r, from, to) {
      const c = this.ctx, PW = this.plotW()
      c.font = `500 11px ${this.font.split('px ')[1]}`
      for (const w of this.walls) {
        const y = Math.round(this.priceToY(w.price, p, r)) + .5
        if (y < p.y || y > p.y + p.h) continue
        const x0 = Math.max(0, this.indexToX(this.indexAt(w.from)))
        const x1 = w.to ? Math.min(PW, this.indexToX(this.indexAt(w.to))) : PW
        if (x1 < 0 || x0 > PW) continue
        const col = w.product === 'spot' ? '#06B6D4' : '#8B5CF6'
        const hot = this.hoverWall === w
        c.strokeStyle = hexA(col, hot ? 1 : Math.min(0.9, 0.35 + w.size / 4e7))
        c.lineWidth = hot ? 3 : 1 + Math.min(2, w.size / 1.5e7)
        c.beginPath(); c.moveTo(x0, y); c.lineTo(x1, y); c.stroke()
        if (!w.to) {
          const t = fmtCompact(w.size), tw = c.measureText(t).width + 10
          c.fillStyle = hexA(col, hot ? 1 : 0.85); roundRect(c, PW - tw - 4, y - 8, tw, 16, 3); c.fill()
          c.fillStyle = '#fff'; c.textAlign = 'center'; c.fillText(t, PW - 4 - tw / 2, y + .5)
        }
      }
      c.font = this.font
    }
    wallAt(x, y) {
      if (!this.walls || !this._panes) return null
      const p = this._panes[0], r = this._ranges.main
      let best = null, bd = 6
      for (const w of this.walls) {
        const wy = this.priceToY(w.price, p, r)
        const x0 = this.indexToX(this.indexAt(w.from)), x1 = w.to ? this.indexToX(this.indexAt(w.to)) : this.plotW()
        if (x < x0 - 4 || x > x1 + 4) continue
        const d = Math.abs(wy - y); if (d < bd) { bd = d; best = w }
      }
      return best
    }

    // ---- 复盘：持仓区间、进出场记号
    drawTradeSpan(p, r) {
      const c = this.ctx
      for (const m of this.markers) {
        const x0 = this.indexToX(this.indexAt(m.entryT)), x1 = this.indexToX(this.indexAt(m.exitT))
        const col = m.pnl >= 0 ? this.colors.up : this.colors.down
        c.fillStyle = hexA(col, 0.07); c.fillRect(x0, p.y, x1 - x0, p.h)
      }
    }
    drawMarkers(p, r) {
      const c = this.ctx, C = this.colors
      for (const m of this.markers) {
        const i0 = this.indexAt(m.entryT), i1 = this.indexAt(m.exitT)
        const x0 = this.indexToX(i0), x1 = this.indexToX(i1)
        const y0 = this.priceToY(m.entry, p, r), y1 = this.priceToY(m.exit, p, r)
        const shown = this.replay == null || this.replay >= Math.round(i1)
        c.strokeStyle = hexA(C.text2, .8); c.setLineDash([4, 3]); c.lineWidth = 1.2
        c.beginPath(); c.moveTo(x0, y0); c.lineTo(shown ? x1 : this.indexToX(this.lastIndex()), shown ? y1 : this.priceToY(this.lastBar().c, p, r)); c.stroke(); c.setLineDash([])
        const tag = (x, y, text, col, below) => {
          c.font = `600 11px ${this.font.split('px ')[1]}`
          const tw = c.measureText(text).width + 12, ty = below ? y + 14 : y - 30
          c.fillStyle = col; roundRect(c, x - tw / 2, ty, tw, 18, 4); c.fill()
          c.beginPath(); c.moveTo(x - 4, below ? ty : ty + 18); c.lineTo(x + 4, below ? ty : ty + 18); c.lineTo(x, below ? ty - 5 : ty + 23); c.closePath(); c.fill()
          c.fillStyle = '#fff'; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText(text, x, ty + 9)
          c.font = this.font
        }
        const longCol = C.up, shortCol = C.down
        if (this.replay == null || this.replay >= Math.round(i0)) tag(x0, y0, m.side === 'long' ? '开多' : '开空', m.side === 'long' ? longCol : shortCol, m.side === 'long')
        if (shown) tag(x1, y1, '平仓', C.text2, m.side !== 'long')
      }
    }

    // ---- 画线
    drawDrawings(p, r) {
      const all = this.draft ? this.drawings.concat([this.draft]) : this.drawings
      if (this.drawingsHidden) return
      for (const d of all) this.drawOne(d, p, r, d === this.selected || d === this.draft)
    }
    pt(q, p, r) { return { x: this.indexToX(this.indexAt(q.t)), y: this.priceToY(q.p, p, r) } }
    drawOne(d, p, r, sel) {
      const c = this.ctx, PW = this.plotW(), col = d.color || '#2962FF'
      c.strokeStyle = col; c.lineWidth = d.width || 2; c.fillStyle = col
      const pts = d.pts.map(q => this.pt(q, p, r))
      const a = pts[0], b = pts[1] || pts[0]
      c.beginPath()
      if (d.type === 'trend') { c.moveTo(a.x, a.y); c.lineTo(b.x, b.y) }
      else if (d.type === 'ray') { const k = extend(a, b, PW * 3); c.moveTo(a.x, a.y); c.lineTo(k.x, k.y) }
      else if (d.type === 'hline') { c.moveTo(0, a.y); c.lineTo(PW, a.y) }
      else if (d.type === 'vline') { c.moveTo(a.x, p.y); c.lineTo(a.x, p.y + p.h) }
      else if (d.type === 'rect') { c.rect(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y)); c.save(); c.fillStyle = hexA(col, .12); c.fill(); c.restore() }
      else if (d.type === 'fib') {
        const lv = [0, .236, .382, .5, .618, .786, 1], cols = ['#787B86', '#F23645', '#FF9800', '#4CAF50', '#089981', '#00BCD4', '#787B86']
        const x0 = Math.min(a.x, b.x), x1 = Math.max(a.x, b.x) + 0
        c.stroke(); c.lineWidth = 1
        lv.forEach((L, k) => {
          const pr = d.pts[1].p + (d.pts[0].p - d.pts[1].p) * L, y = Math.round(this.priceToY(pr, p, r)) + .5
          c.strokeStyle = cols[k]; c.beginPath(); c.moveTo(x0, y); c.lineTo(x1, y); c.stroke()
          c.fillStyle = cols[k]; c.textAlign = 'right'; c.textBaseline = 'bottom'; c.font = `11px ${this.font.split('px ')[1]}`
          c.fillText(`${L} (${fmt(pr, this.meta.dec)})`, x0 - 4, y + 5)
        })
        c.font = this.font; c.textBaseline = 'middle'
        c.setLineDash([3, 3]); c.strokeStyle = hexA('#787B86', .8); c.beginPath(); c.moveTo(a.x, a.y); c.lineTo(b.x, b.y); c.stroke(); c.setLineDash([])
        c.beginPath()
      }
      else if (d.type === 'measure') {
        const up = d.pts[1].p >= d.pts[0].p, mc = up ? '#2962FF' : '#F23645'
        c.fillStyle = hexA(mc, .12); c.fillRect(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y))
        c.strokeStyle = mc; c.lineWidth = 1.5; c.beginPath()
        const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2
        c.moveTo(mx, a.y); c.lineTo(mx, b.y); c.moveTo(a.x, my); c.lineTo(b.x, my); c.stroke()
        const dp = d.pts[1].p - d.pts[0].p, pct = dp / d.pts[0].p * 100
        const nb = Math.round(this.indexAt(d.pts[1].t) - this.indexAt(d.pts[0].t))
        const t1 = `${dp >= 0 ? '+' : ''}${fmt(dp, this.meta.dec)} (${pct >= 0 ? '+' : ''}${pct.toFixed(2)}%)`, t2 = `${nb} 根 · ${durText(Math.abs(nb) * this.iv)}`
        c.font = `600 12px ${this.font.split('px ')[1]}`
        const tw = Math.max(c.measureText(t1).width, c.measureText(t2).width) + 20
        const ly = up ? Math.min(a.y, b.y) - 50 : Math.max(a.y, b.y) + 8
        c.fillStyle = mc; roundRect(c, mx - tw / 2, ly, tw, 42, 6); c.fill()
        c.fillStyle = '#fff'; c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText(t1, mx, ly + 13); c.font = this.font; c.fillText(t2, mx, ly + 29)
        c.beginPath()
      }
      c.stroke()
      if (sel) {
        for (const q of pts) { c.fillStyle = this.colors.bg; c.strokeStyle = col; c.lineWidth = 2; c.beginPath(); c.arc(q.x, q.y, 5, 0, Math.PI * 2); c.fill(); c.stroke() }
      }
      if (d.alert && d.type !== 'fib') { c.fillStyle = this.colors.alert; c.beginPath(); c.arc(pts[pts.length - 1].x + 10, pts[pts.length - 1].y - 10, 4, 0, Math.PI * 2); c.fill() }
    }
    hitDrawing(x, y) {
      if (!this._panes) return null
      const p = this._panes[0], r = this._ranges.main, PW = this.plotW()
      for (let k = this.drawings.length - 1; k >= 0; k--) {
        const d = this.drawings[k]
        const pts = d.pts.map(q => this.pt(q, p, r)), a = pts[0], b = pts[1] || a
        for (let j = 0; j < pts.length; j++) if (Math.hypot(pts[j].x - x, pts[j].y - y) < 8) return { d, handle: j }
        let dist = Infinity
        if (d.type === 'trend') dist = segDist(x, y, a, b)
        else if (d.type === 'ray') dist = segDist(x, y, a, extend(a, b, PW * 3))
        else if (d.type === 'hline') dist = Math.abs(y - a.y)
        else if (d.type === 'vline') dist = Math.abs(x - a.x)
        else if (d.type === 'rect' || d.type === 'measure' || d.type === 'fib') {
          const x0 = Math.min(a.x, b.x), x1 = Math.max(a.x, b.x), y0 = Math.min(a.y, b.y), y1 = Math.max(a.y, b.y)
          if (x >= x0 - 4 && x <= x1 + 4 && y >= y0 - 4 && y <= y1 + 4) dist = 0
        }
        if (dist < 6) return { d, handle: null }
      }
      return null
    }
    toTP(x, y) {
      const p = this._panes[0], r = this._ranges.main
      let i = this.xToIndex(x), price = this.yToPrice(y, p, r)
      if (this.magnet) {
        const k = Math.round(i), b = this.bars[k]
        if (b) { i = k; price = [b.o, b.h, b.l, b.c].reduce((a, v) => Math.abs(this.priceToY(v, p, r) - y) < Math.abs(this.priceToY(a, p, r) - y) ? v : a) }
      } else i = Math.round(i)
      return { t: this.timeAt(i), p: price }
    }

    // ---------------------------------------------------------- 图例
    legendIndex() {
      if (this.cross) return clamp(Math.round(this.xToIndex(this.cross.x)), 0, this.lastIndex())
      if (this.extCross != null) return clamp(Math.round(this.indexAt(this.extCross)), 0, this.lastIndex())
      return this.lastIndex()
    }
    renderLegend() {
      const I = KPIcon.icon, b = this.bars[this.legendIndex()], dec = this.meta.dec
      if (!b) { this.legendEl.innerHTML = ''; return }
      const prev = this.bars[this.legendIndex() - 1]
      const chg = prev ? b.c - prev.c : b.c - b.o, pct = chg / (prev ? prev.c : b.o) * 100
      const cls = this.stale ? 'faint' : chg >= 0 ? 'up' : 'down'
      const v = (x) => `<span class="num ${cls}">${fmt(x, dec)}</span>`
      const tools = id => `<span class="tools"><button class="ibtn xs" data-act="toggle" data-id="${id}" data-tip="${this.hidden.has(id) ? '显示' : '隐藏'}">${I(this.hidden.has(id) ? 'eyeOff' : 'eye', 'icon-16')}</button><button class="ibtn xs" data-act="settings" data-id="${id}" data-tip="参数">${I('gear', 'icon-16')}</button><button class="ibtn xs" data-act="remove" data-id="${id}" data-tip="移除">${I('close', 'icon-16')}</button></span>`
      let h = `<div class="lrow"><span class="title">${this.meta.badge || ''}${this.meta.title}<span class="sub">${this.meta.sub}</span></span>
        <span class="ohlc"><span><i>开</i>${v(b.o)}</span><span><i>高</i>${v(b.h)}</span><span><i>低</i>${v(b.l)}</span><span><i>收</i>${v(b.c)}</span>
        <span class="num ${cls}">${chg >= 0 ? '+' : ''}${fmt(chg, dec)} (${pct >= 0 ? '+' : ''}${pct.toFixed(2)}%)</span></span></div>`
      const i = this.legendIndex()
      for (const id of ['ma', 'ema', 'boll']) {
        if (!this.ind[id]) continue
        const cat = CATALOG[id], s = this.series[id] || []
        h += `<div class="lrow ${this.hidden.has(id) ? 'hidden-ind' : ''}"><span class="ind-name">${cat.name}</span><span class="ind-param">${paramText(id, this.params[id])}</span>
          <span class="vals num">${s.map((ser, k) => `<span style="color:${cat.colors[k % cat.colors.length]}">${fmt(ser[i], dec)}</span>`).join('')}</span>${tools(id)}</div>`
      }
      if (this.ind.vol) h += `<div class="lrow ${this.hidden.has('vol') ? 'hidden-ind' : ''}"><span class="ind-name">成交量</span><span class="vals num"><span class="${b.c >= b.o ? 'up' : 'down'}">${fmtCompact(b.v)}</span></span>${tools('vol')}</div>`
      if (this.walls) h += `<div class="lrow ${this.hidden.has('walls') ? 'hidden-ind' : ''}"><span class="ind-name">主力订单流</span><span class="ind-param">${this.meta.wallParam || ''}</span><span class="vals num"><span style="color:#8B5CF6">合约 ${this.walls.filter(w => !w.to && w.product !== 'spot').length}</span><span style="color:#06B6D4">现货 ${this.walls.filter(w => !w.to && w.product === 'spot').length}</span></span>${tools('walls')}</div>`
      this.legendEl.innerHTML = h
      this.renderPaneLegends(this._panes || [])
    }
    renderPaneLegends(panes) {
      const subs = panes.slice(1)
      while (this.paneLegendEls.length < subs.length) { const e = document.createElement('div'); e.className = 'pane-legend'; this.host.appendChild(e); this.paneLegendEls.push(e) }
      this.paneLegendEls.forEach((e, k) => { e.style.display = k < subs.length ? '' : 'none' })
      const i = this.legendIndex(), I = KPIcon.icon
      subs.forEach((p, k) => {
        const e = this.paneLegendEls[k], cat = CATALOG[p.id], s = this.series[p.id] || []
        e.style.top = (p.y + 6) + 'px'
        const vals = s.map((ser, j) => {
          const val = ser[i]
          const col = p.id === 'macd' && j === 2 ? (val >= 0 ? 'var(--up-text)' : 'var(--down-text)') : cat.colors[j % cat.colors.length]
          return `<span style="color:${col}">${val == null ? '—' : this.subFmt(p.id, val)}</span>`
        }).join('')
        const key = p.id + ':' + i + ':' + vals
        if (e._k === key) return
        e._k = key
        e.innerHTML = `<div class="lrow ${this.hidden.has(p.id) ? 'hidden-ind' : ''}"><span class="ind-name">${cat.name}</span><span class="ind-param">${paramText(p.id, this.params[p.id])}</span><span class="vals num">${vals}</span>
          <span class="tools"><button class="ibtn xs" data-act="toggle" data-id="${p.id}" data-tip="${this.hidden.has(p.id) ? '显示' : '隐藏'}">${I(this.hidden.has(p.id) ? 'eyeOff' : 'eye', 'icon-16')}</button><button class="ibtn xs" data-act="settings" data-id="${p.id}" data-tip="参数">${I('gear', 'icon-16')}</button><button class="ibtn xs" data-act="remove" data-id="${p.id}" data-tip="移除">${I('close', 'icon-16')}</button></span></div>`
      })
    }

    // ---------------------------------------------------------- 交互
    region(x, y) {
      if (y > this.h - AXIS_H) return x > this.plotW() ? 'corner' : 'time'
      if (x > this.plotW()) return 'price'
      const panes = this._panes || []
      for (const p of panes.slice(1)) if (Math.abs(y - p.y) <= SEP_HIT) return 'sep:' + p.id
      return 'plot'
    }
    paneAt(y) { return (this._panes || []).find(p => y >= p.y && y < p.y + p.h) }
    bind() {
      const cv = this.canvas
      const pos = e => { const r = cv.getBoundingClientRect(); return { x: e.clientX - r.left, y: e.clientY - r.top } }
      this.host.addEventListener('mousedown', () => this.o.onActivate?.(), true)
      this.host.addEventListener('click', e => {
        const btn = e.target.closest('[data-act]'); if (!btn) return
        e.stopPropagation()
        const id = btn.dataset.id, act = btn.dataset.act
        if (act === 'toggle') { this.hidden.has(id) ? this.hidden.delete(id) : this.hidden.add(id); this.dirty = true; this.paneLegendEls.forEach(el => el._k = null); this.renderLegend() }
        else this.o.onLegendAction?.(id, act, btn)
      })
      cv.addEventListener('mousemove', e => {
        const { x, y } = pos(e)
        if (this.drag) return
        const reg = this.region(x, y)
        cv.style.cursor = reg === 'price' ? 'ns-resize' : reg === 'time' ? 'ew-resize' : reg.startsWith('sep') ? 'row-resize' : 'crosshair'
        if (reg === 'plot') {
          const pane = this.paneAt(y)
          this.cross = { x, y, pane: pane?.id }
          if (this.draft) { const tp = this.toTP(x, y); this.draft.pts[this.draft.pts.length - 1] = tp }
          if (!this.tool) {
            const hit = this.hitDrawing(x, y)
            if (hit) cv.style.cursor = hit.handle != null ? 'grab' : 'pointer'
            const w = pane?.id === 'main' && !hit ? this.wallAt(x, y) : null
            if (w !== this.hoverWall) { this.hoverWall = w; this.o.onWallHover?.(w, e.clientX, e.clientY) }
            else if (w) this.o.onWallHover?.(w, e.clientX, e.clientY)
          }
          this.o.onCrosshairMove?.(this.timeAt(Math.round(this.xToIndex(x))))
        } else { this.cross = null; this.o.onCrosshairMove?.(null) }
        this.dirty = true; this.renderLegend()
      })
      cv.addEventListener('mouseleave', () => {
        if (this.drag) return
        this.cross = null; this.dirty = true; this.renderLegend()
        if (this.hoverWall) { this.hoverWall = null; this.o.onWallHover?.(null) }
        this.o.onCrosshairMove?.(null)
      })
      cv.addEventListener('mousedown', e => {
        if (e.button !== 0) return
        const { x, y } = pos(e), reg = this.region(x, y)
        if (reg === 'plot' && this.tool) {
          const pane = this.paneAt(y); if (pane?.id !== 'main') return
          const tp = this.toTP(x, y)
          const one = this.tool === 'hline' || this.tool === 'vline'
          if (!this.draft) {
            if (one) { const d = { id: uid(), type: this.tool, pts: [tp], color: this.o.drawColor?.() || '#2962FF', width: 2 }; this.drawings.push(d); this.selected = d; this.finishTool(d); return }
            this.draft = { id: uid(), type: this.tool, pts: [tp, { ...tp }], color: this.o.drawColor?.() || '#2962FF', width: this.tool === 'measure' ? 1 : 2 }
          } else {
            this.draft.pts[1] = tp
            const d = this.draft; this.draft = null
            if (d.type === 'measure') { this.measure = d; this.drawings.push(d); this.finishTool(d, true); return }
            this.drawings.push(d); this.selected = d; this.finishTool(d)
          }
          this.dirty = true; return
        }
        if (reg === 'plot') {
          const hit = this.hitDrawing(x, y)
          if (hit) {
            this.selected = hit.d; this.o.onSelectDrawing?.(hit.d)
            const start = this.toTP(x, y), orig = hit.d.pts.map(q => ({ ...q }))
            this.drag = { kind: 'drawing', hit, start, orig }
            this.dirty = true; return
          }
          if (this.selected) { this.selected = null; this.o.onSelectDrawing?.(null) }
          if (this.measure) { this.drawings.splice(this.drawings.indexOf(this.measure), 1); this.measure = null }
          if (e.shiftKey) { // Shift + 拖 = 临时测量（TradingView 同款）
            const tp = this.toTP(x, y); this.draft = { id: uid(), type: 'measure', pts: [tp, { ...tp }], color: '#2962FF', width: 1 }; this.drag = { kind: 'measure' }; return
          }
        }
        const r0 = this.mainRange ? { ...this.mainRange } : null
        this.drag = { kind: reg, x0: x, y0: y, right0: this.rightBar, sp0: this.spacing, r0, moved: false, pane: this.paneAt(y) }
        if (reg === 'plot') cv.style.cursor = 'grabbing'
      })
      window.addEventListener('mousemove', e => {
        if (!this.drag || this.dead) return
        const { x, y } = pos(e), d = this.drag
        if (d.kind === 'measure') { this.draft.pts[1] = this.toTP(x, y); this.cross = { x, y, pane: 'main' }; this.dirty = true; return }
        if (d.kind === 'drawing') {
          const now = this.toTP(x, y), dd = d.hit.d
          if (dd.locked) return
          if (d.hit.handle != null) dd.pts[d.hit.handle] = now
          else {
            const dt = this.indexAt(now.t) - this.indexAt(d.start.t), dp = now.p - d.start.p
            dd.pts = d.orig.map(q => ({ t: this.timeAt(Math.round(this.indexAt(q.t) + dt)), p: q.p + dp }))
          }
          this.dirty = true; return
        }
        const dx = x - d.x0, dy = y - d.y0
        if (Math.abs(dx) + Math.abs(dy) > 2) d.moved = true
        if (d.kind === 'plot') {
          this.rightBar = d.right0 - dx / this.spacing
          if (!this.auto && d.pane?.id === 'main' && d.r0) {
            const p = this._panes[0]; const k = (this.tf(d.r0.max) - this.tf(d.r0.min)) / (p.h - 16) * dy
            this.manual = { min: this.itf(this.tf(d.r0.min) + k), max: this.itf(this.tf(d.r0.max) + k) }
          }
          this.cross = null; this.maybeMore()
        } else if (d.kind === 'time') {
          const f = Math.exp(dx / 200); this.spacing = clamp(d.sp0 * f, MIN_SPACING, MAX_SPACING)
          this.rightBar = d.right0; this.maybeMore()
        } else if (d.kind === 'price' && d.pane?.id === 'main' && d.r0) {
          const f = Math.exp(dy / 200), mid = (this.tf(d.r0.max) + this.tf(d.r0.min)) / 2, half = (this.tf(d.r0.max) - this.tf(d.r0.min)) / 2 * f
          this.manual = { min: this.itf(mid - half), max: this.itf(mid + half) }
          if (this.auto) { this.auto = false; this.o.onAutoChange?.(false) }
        } else if (d.kind.startsWith('sep:')) {
          const id = d.kind.slice(4), panes = this._panes, k = panes.findIndex(p => p.id === id)
          const above = panes[k - 1], cur = panes[k]
          const total = above.h + cur.h, ny = clamp(y - above.y, MIN_PANE_H, total - MIN_PANE_H)
          // 主图永远是「剩下的全部」，所以只记副图的像素高
          if (above.id !== 'main') this.paneH[above.id] = ny
          this.paneH[id] = total - ny
        }
        this.dirty = true; this.renderLegend()
      })
      window.addEventListener('mouseup', () => {
        if (!this.drag) return
        const d = this.drag; this.drag = null
        if (d.kind === 'measure') { const m = this.draft; this.draft = null; if (m) { this.measure = m; this.drawings.push(m) } this.dirty = true; return }
        if (d.kind === 'drawing') { this.o.onDrawingsChanged?.(); return }
        this.canvas.style.cursor = 'crosshair'
      })
      cv.addEventListener('dblclick', e => {
        const { x, y } = pos(e), reg = this.region(x, y)
        if (reg === 'price') this.setAuto(true)
        else if (reg === 'time') this.resetView()
      })
      cv.addEventListener('wheel', e => {
        e.preventDefault()
        const { x } = pos(e)
        if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) { this.rightBar += e.deltaX / this.spacing; this.maybeMore() }
        else this.zoom(Math.exp(-e.deltaY * (e.ctrlKey ? 0.01 : 0.0025)), Math.min(x, this.plotW()))
        this.dirty = true; this.renderLegend()
      }, { passive: false })
      cv.addEventListener('contextmenu', e => {
        e.preventDefault()
        const { x, y } = pos(e)
        if (this.region(x, y) !== 'plot') return
        const pane = this.paneAt(y)
        const hit = this.hitDrawing(x, y)
        const price = pane?.id === 'main' ? this.yToPrice(y, pane, this._ranges.main) : null
        this.o.onContextMenu?.({ clientX: e.clientX, clientY: e.clientY, price, time: this.timeAt(Math.round(this.xToIndex(x))), drawing: hit?.d })
      })
    }
    finishTool(d, keep) { this.o.onToolDone?.(d, keep); this.o.onDrawingsChanged?.(); this.dirty = true }
    deleteSelected() {
      if (!this.selected) return false
      const i = this.drawings.indexOf(this.selected); if (i >= 0) this.drawings.splice(i, 1)
      this.selected = null; this.o.onDrawingsChanged?.(); this.o.onSelectDrawing?.(null); this.dirty = true; return true
    }
    cancelDraft() { if (this.draft) { this.draft = null; this.dirty = true; return true } if (this.measure) { this.drawings.splice(this.drawings.indexOf(this.measure), 1); this.measure = null; this.dirty = true; return true } return false }
    maybeMore() {
      if (this.bars.length && this.xToIndex(0) < 60 && !this.loadingMore) this.o.onNeedMore?.()
    }
    crossPrice() {
      if (!this.cross || this.cross.pane !== 'main') return null
      return this.yToPrice(this.cross.y, this._panes[0], this._ranges.main)
    }
  }

  // ------------------------------------------------------------ 小工具
  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)) }
  function hexA(hex, a) {
    if (!hex || hex[0] !== '#') return hex
    const n = parseInt(hex.slice(1, 7), 16)
    return `rgba(${n >> 16 & 255},${n >> 8 & 255},${n & 255},${a})`
  }
  function roundRect(c, x, y, w, h, r) { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath() }
  function segDist(x, y, a, b) {
    const dx = b.x - a.x, dy = b.y - a.y, L = dx * dx + dy * dy
    const t = L ? clamp(((x - a.x) * dx + (y - a.y) * dy) / L, 0, 1) : 0
    return Math.hypot(x - (a.x + t * dx), y - (a.y + t * dy))
  }
  function extend(a, b, len) { const dx = b.x - a.x, dy = b.y - a.y, L = Math.hypot(dx, dy) || 1; return { x: a.x + dx / L * len, y: a.y + dy / L * len } }
  function durText(ms) {
    const m = Math.round(ms / 60e3)
    if (m < 60) return `${m} 分钟`
    const h = m / 60; if (h < 48) return `${+h.toFixed(1)} 小时`
    return `${+(h / 24).toFixed(1)} 天`
  }
  let _u = 0; function uid() { return 'd' + Date.now().toString(36) + (_u++) }

  g.TVChart = TVChart
  g.TVCatalog = CATALOG
  g.KPFmt = { fmt, fmtCompact, fmtAxis, crossTimeLabel, durText, sh, pad, hexA, paramText }
})(window)
