/* 看盘 · 自绘 K 线引擎
 *
 * 这里没有图表库。所有几何、刻度、指标都是纯函数，和将来 Swift 里 KanpanCore
 * 的结构一一对应：算一遍视野 → 算一遍指标 → 画一遍。视野用时间表示（from/to
 * 两个毫秒数），不是「第几根到第几根」，所以切周期的时候 K 线的像素宽度能原样
 * 留住，变的是看见多长的时间。
 */
(function (global) {
  'use strict'

  /** 在两个 #rrggbb 之间取一点，画影线减淡和挖空用。 */
  function mixHex(a, b, k) {
    const pa = parseInt(a.slice(1, 7), 16), pb = parseInt(b.slice(1, 7), 16)
    const m = (sh) => Math.round((((pa >> sh) & 255) * (1 - k) + ((pb >> sh) & 255) * k))
    return '#' + ((1 << 24) + (m(16) << 16) + (m(8) << 8) + m(0)).toString(16).slice(1)
  }

  // ---------------------------------------------------------------- 手感常数
  // 这几个数是从现有前端里量出来的，将来照搬进 Swift。
  const MIN_BAR_SPACING = 0.4        // 再挤就只剩一根竖线
  const MAX_BAR_SPACING = 40         // 再拉开就没有「盘」的样子了
  const DEFAULT_BAR_SPACING = 4.8    // 手机默认：细，像 AICoin
  const FLING_TAU_MS = 325           // 惯性衰减时间常数
  const FLING_MAX_MS = 1400
  const FLING_MIN_PX_PER_MS = 0.2    // 比这慢就不算甩
  const FLING_MAX_PX_PER_MS = 3
  const FLING_EPS_PX = 0.5           // 剩下不到半像素就停
  const PINCH_MIN_PX = 8             // 两指距离小于这个不算数

  const AXIS_W = 54                  // 右侧价格轴：窄
  const TIME_H = 22
  const SUB_H = 74                   // 一个副图的高度

  // ---------------------------------------------------------------- 指标数学
  const nan = (n) => new Array(n).fill(NaN)

  function sma(src, n) {
    const out = nan(src.length)
    if (n < 1) return out
    let sum = 0
    for (let i = 0; i < src.length; i++) {
      sum += src[i]
      if (i >= n) sum -= src[i - n]
      if (i >= n - 1) out[i] = sum / n
    }
    return out
  }

  /** 用前 n 根的均值起步，和 TradingView 一个口径。 */
  function ema(src, n) {
    const out = nan(src.length)
    if (src.length < n || n < 1) return out
    const k = 2 / (n + 1)
    let sum = 0
    for (let i = 0; i < n; i++) sum += src[i]
    let prev = sum / n
    out[n - 1] = prev
    for (let i = n; i < src.length; i++) {
      prev = src[i] * k + prev * (1 - k)
      out[i] = prev
    }
    return out
  }

  /** Wilder 的平滑（RSI、ATR 用的那种，衰减比 EMA 慢一半）。 */
  function rma(src, n) {
    const out = nan(src.length)
    if (src.length < n || n < 1) return out
    let sum = 0
    for (let i = 0; i < n; i++) sum += src[i]
    let prev = sum / n
    out[n - 1] = prev
    for (let i = n; i < src.length; i++) {
      prev = (prev * (n - 1) + src[i]) / n
      out[i] = prev
    }
    return out
  }

  function boll(close, n, k) {
    const mid = sma(close, n)
    const up = nan(close.length)
    const dn = nan(close.length)
    for (let i = n - 1; i < close.length; i++) {
      let s = 0
      for (let j = i - n + 1; j <= i; j++) { const d = close[j] - mid[i]; s += d * d }
      const sd = Math.sqrt(s / n)
      up[i] = mid[i] + k * sd
      dn[i] = mid[i] - k * sd
    }
    return { mid, up, dn }
  }

  function macd(close, fast, slow, sig) {
    const f = ema(close, fast)
    const s = ema(close, slow)
    const dif = nan(close.length)
    for (let i = 0; i < close.length; i++) {
      if (Number.isFinite(f[i]) && Number.isFinite(s[i])) dif[i] = f[i] - s[i]
    }
    // DEA 从 DIF 真正开始的地方起算，否则前面一段 NaN 会把均线拖坏。
    const start = dif.findIndex(Number.isFinite)
    const dea = nan(close.length)
    if (start >= 0) {
      const tail = ema(dif.slice(start), sig)
      for (let i = 0; i < tail.length; i++) dea[start + i] = tail[i]
    }
    const hist = nan(close.length)
    for (let i = 0; i < close.length; i++) {
      if (Number.isFinite(dif[i]) && Number.isFinite(dea[i])) hist[i] = (dif[i] - dea[i]) * 2
    }
    return { dif, dea, hist }
  }

  function rsi(close, n) {
    const up = nan(close.length)
    const dn = nan(close.length)
    up[0] = 0; dn[0] = 0
    for (let i = 1; i < close.length; i++) {
      const d = close[i] - close[i - 1]
      up[i] = d > 0 ? d : 0
      dn[i] = d < 0 ? -d : 0
    }
    const au = rma(up, n)
    const ad = rma(dn, n)
    const out = nan(close.length)
    for (let i = 0; i < close.length; i++) {
      if (!Number.isFinite(au[i])) continue
      out[i] = ad[i] === 0 ? 100 : 100 - 100 / (1 + au[i] / ad[i])
    }
    return out
  }

  function hhv(src, n, i) { let m = -Infinity; for (let j = Math.max(0, i - n + 1); j <= i; j++) if (src[j] > m) m = src[j]; return m }
  function llv(src, n, i) { let m = Infinity; for (let j = Math.max(0, i - n + 1); j <= i; j++) if (src[j] < m) m = src[j]; return m }

  function kdj(high, low, close, n, kn, dn2) {
    const K = nan(close.length), D = nan(close.length), J = nan(close.length)
    let k = 50, d = 50
    for (let i = 0; i < close.length; i++) {
      const hi = hhv(high, n, i), lo = llv(low, n, i)
      const rsv = hi === lo ? 50 : ((close[i] - lo) / (hi - lo)) * 100
      k = ((kn - 1) * k + rsv) / kn
      d = ((dn2 - 1) * d + k) / dn2
      if (i >= n - 1) { K[i] = k; D[i] = d; J[i] = 3 * k - 2 * d }
    }
    return { K, D, J }
  }

  function stochRsi(close, rlen, slen, kn, dn2) {
    const r = rsi(close, rlen)
    const raw = nan(close.length)
    for (let i = 0; i < close.length; i++) {
      if (!Number.isFinite(r[i])) continue
      let hi = -Infinity, lo = Infinity, ok = true
      for (let j = i - slen + 1; j <= i; j++) {
        if (j < 0 || !Number.isFinite(r[j])) { ok = false; break }
        if (r[j] > hi) hi = r[j]
        if (r[j] < lo) lo = r[j]
      }
      if (!ok) continue
      raw[i] = hi === lo ? 0 : ((r[i] - lo) / (hi - lo)) * 100
    }
    const K = smaSkip(raw, kn)
    const D = smaSkip(K, dn2)
    return { K, D }
  }

  /** 会跳过前面 NaN 的简单均线。 */
  function smaSkip(src, n) {
    const out = nan(src.length)
    const start = src.findIndex(Number.isFinite)
    if (start < 0) return out
    const tail = sma(src.slice(start), n)
    for (let i = 0; i < tail.length; i++) out[start + i] = tail[i]
    return out
  }

  function atr(high, low, close, n) {
    const tr = nan(close.length)
    tr[0] = high[0] - low[0]
    for (let i = 1; i < close.length; i++) {
      tr[i] = Math.max(high[i] - low[i], Math.abs(high[i] - close[i - 1]), Math.abs(low[i] - close[i - 1]))
    }
    return rma(tr, n)
  }

  // ---------------------------------------------------------------- K 线宽度
  /** 桌面那一份是复刻图表库的算法；手机这一份取根宽的 0.55，更细。 */
  function libraryBody(spacing, ratio) {
    const raw = Math.floor(spacing * ratio)
    const dev = Math.floor(ratio)
    const scaled = Math.max(dev, Math.floor(raw * 0.8))
    return Math.max(dev, Math.min(scaled, raw))
  }
  function evenUp(raw, body, wick) {
    if ((body % 2) !== (wick % 2)) {
      const up = body + 1, down = body - 1
      body = (down >= wick && Math.abs(raw - down) <= Math.abs(raw - up)) ? down : up
    }
    return Math.max(body, wick)
  }
  /** 返回设备像素。影线半个设备像素，实体和影线奇偶对齐，边缘才不起毛。 */
  function candleWidths(barSpacing, dpr, mobile, bodyR) {
    const ratio = Number.isFinite(dpr) && dpr > 0 ? dpr : 1
    const spacing = Number.isFinite(barSpacing) && barSpacing > 0 ? barSpacing : 0
    const ratioBody = Number.isFinite(bodyR) && bodyR > 0 ? bodyR : 0.55
    if (!mobile) {
      let body = libraryBody(spacing, ratio)
      const line = Math.floor(ratio)
      if (body >= 2 && (line % 2) !== (body % 2)) body -= 1
      let wick = Math.min(Math.floor(ratio), Math.floor(spacing * ratio))
      wick = Math.max(Math.floor(ratio), Math.min(wick, body))
      return { body, wick }
    }
    const wick = Math.max(1, Math.round(ratio / 2))
    const raw = spacing * ratioBody * ratio
    if (raw < 2) return { body: wick, wick }
    return { body: evenUp(raw, Math.max(1, Math.round(raw)), wick), wick }
  }

  // ---------------------------------------------------------------- 惯性
  function flingAt(speedPxPerMs, elapsedMs, tauMs) {
    const tau = tauMs || FLING_TAU_MS
    const time = Math.max(0, elapsedMs)
    const left = Math.exp(-time / tau)
    const total = speedPxPerMs * tau
    const pastPx = total * (1 - left)
    const done = time >= FLING_MAX_MS || Math.abs(total) * left < FLING_EPS_PX
    return { pastPx, done }
  }

  // ---------------------------------------------------------------- 刻度
  function niceStep(span, want) {
    if (!(span > 0)) return 1
    const rough = span / Math.max(1, want)
    const mag = Math.pow(10, Math.floor(Math.log10(rough)))
    const n = rough / mag
    const step = n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10
    return step * mag
  }

  const MIN = 60e3, HOUR = 3600e3, DAY = 86400e3
  const TIME_STEPS = [MIN, 5 * MIN, 15 * MIN, 30 * MIN, HOUR, 2 * HOUR, 4 * HOUR, 6 * HOUR, 12 * HOUR,
    DAY, 2 * DAY, 7 * DAY, 14 * DAY, 30 * DAY, 90 * DAY, 180 * DAY, 365 * DAY]
  function timeStep(spanMs, plotW, perLabelPx) {
    const want = Math.max(2, Math.floor(plotW / perLabelPx))
    const rough = spanMs / want
    for (const s of TIME_STEPS) if (s >= rough) return s
    return TIME_STEPS[TIME_STEPS.length - 1]
  }

  const pad2 = (n) => (n < 10 ? '0' + n : '' + n)
  function tzOffsetMin(tz) {
    if (tz === 'utc') return 0
    if (tz === 'exchange') return 480
    return -new Date().getTimezoneOffset()
  }
  function parts(ms, offMin) {
    const d = new Date(ms + offMin * 60e3)
    return {
      y: d.getUTCFullYear(), mo: d.getUTCMonth() + 1, d: d.getUTCDate(),
      h: d.getUTCHours(), mi: d.getUTCMinutes(),
    }
  }
  function fmtTick(ms, step, offMin) {
    const p = parts(ms, offMin)
    if (step >= 180 * DAY) return p.y + '-' + pad2(p.mo)
    if (step >= DAY) return pad2(p.mo) + '-' + pad2(p.d)
    if (p.h === 0 && p.mi === 0) return pad2(p.mo) + '-' + pad2(p.d)
    return pad2(p.h) + ':' + pad2(p.mi)
  }
  function fmtFull(ms, offMin) {
    const p = parts(ms, offMin)
    return p.y + '-' + pad2(p.mo) + '-' + pad2(p.d) + ' ' + pad2(p.h) + ':' + pad2(p.mi)
  }

  function fmtNum(x, p) {
    if (!Number.isFinite(x)) return '--'
    return x.toFixed(p)
  }
  function fmtVol(x) {
    if (!Number.isFinite(x)) return '--'
    const a = Math.abs(x)
    if (a >= 1e8) return (x / 1e8).toFixed(2) + '亿'
    if (a >= 1e4) return (x / 1e4).toFixed(2) + '万'
    if (a >= 100) return x.toFixed(0)
    return x.toFixed(2)
  }

  // ---------------------------------------------------------------- 指标表
  // 指标线的颜色。深浅两套底色对同一组颜色的观感差很多，所以这一组是活的：
  // 换主题时 setPalette 原地改写它，画图那边照旧按下标取色。
  const PALETTE = ['#FFB454', '#8C95FF', '#4FD1B5', '#F78FB3', '#C8B6FF', '#7FD0FF']
  function setPalette(list) { for (let i = 0; i < PALETTE.length; i++) PALETTE[i] = list[i % list.length] }
  const DEFS = {
    MA:   { name: 'MA',       where: 'main', params: [7, 25, 99],       labels: ['短', '中', '长'] },
    EMA:  { name: 'EMA',      where: 'main', params: [12, 26],          labels: ['短', '长'] },
    BOLL: { name: 'BOLL',     where: 'main', params: [20, 2],           labels: ['周期', '倍数'] },
    VOL:  { name: '成交量',    where: 'sub',  params: [5, 10],           labels: ['MA1', 'MA2'] },
    MACD: { name: 'MACD',     where: 'sub',  params: [12, 26, 9],       labels: ['快', '慢', '信号'] },
    RSI:  { name: 'RSI',      where: 'sub',  params: [6, 12, 24],       labels: ['①', '②', '③'] },
    KDJ:  { name: 'KDJ',      where: 'sub',  params: [9, 3, 3],         labels: ['N', 'K', 'D'] },
    SRSI: { name: 'StochRSI', where: 'sub',  params: [14, 14, 3, 3],    labels: ['RSI', 'Stoch', 'K', 'D'] },
    ATR:  { name: 'ATR',      where: 'sub',  params: [14],              labels: ['周期'] },
    OI:   { name: '持仓量',    where: 'sub',  params: [],                labels: [] },
  }

  // ---------------------------------------------------------------- 图
  class Chart {
    constructor(root, opts) {
      this.root = root
      this.opt = Object.assign({
        theme: {
          bg: '#161A3F', grid: '#232858', axis: '#2A2E6E', text: '#A6A9C0', dim: '#6D719A',
          ink: '#EDEEF8', up: '#2FBF8F', down: '#F0567B', amber: '#FFB454', cross: '#9AA0D0',
          volUp: '#2FBF8F66', volDn: '#F0567B66',
          band: '#C8B6FF',        // 布林上下轨
          oi: '#7FD0FF',          // 持仓量
          oiFill: '#7FD0FF33',
          chip: '#0B0E24',        // 压在涨跌色胶囊上的字
          panel: '#0F1230',       // 画线手柄这类实心小件的底
          crossBg: '#3A3F86',     // 十字线两轴的标签
          crossInk: '#EDEEF8',
        },
        // K 线本身的视觉方案：形态、体积、影线、上下留白、左右间距，全在这里。
        // 换一板 = 换这一张表，画法一行不用改。
        style: {
          bodyR: 0.55,      // 实体占根间距的比例
          wick: 0.5,        // 影线粗细（设备像素）
          wickCap: 'butt',  // 影线端头：butt / round
          wickTint: 1,      // 影线相对实体的浓度
          shape: 'solid',   // solid / hollowUp / outline / round
          radius: 0,        // 实体圆角（CSS 像素）
          minBody: 1,       // 十字星时实体的最小高度（设备像素）
          spacing: 4.8,     // 默认根间距（左右距离）
          pad: 0.08,        // 价格上下留白
          axisW: 54,        // 右侧价格轴宽（左右距离）
          timeH: 22,        // 时间轴高
          subH: 74,         // 单个副图高（上下距离）
          grid: 'both',     // both / h / tick / none
          lastDash: true,
        },
        onCross: null, onView: null, onTap: null, onDrawChange: null,
      }, opts || {})

      this.base = document.createElement('canvas')
      this.over = document.createElement('canvas')
      this.over.className = 'over'
      root.appendChild(this.base)
      root.appendChild(this.over)
      this.bctx = this.base.getContext('2d')
      this.octx = this.over.getContext('2d')

      this.bars = null
      this.oi = null
      this.view = { from: 0, to: 1 }
      this.price = { mode: 'linear', zoom: 1, shift: 0 }
      this.overlays = ['MA']
      this.subs = ['MACD', 'RSI']
      this.params = {}
      for (const k in DEFS) this.params[k] = DEFS[k].params.slice()
      this.cross = null
      this.draws = []
      this.drawMode = null
      this.pending = null          // 画线时已经落下的第一点
      this.selected = null
      this.tz = 'local'
      this.magnet = true
      this.dirty = true
      this.mobile = true
      this.cache = { key: '', v: null }
      this.anim = null

      this._bind()
      this._observe()
      this._loop()
    }

    // ------------------------------------------------------------ 数据
    setSeries(bars, oi, meta) {
      const first = !this.bars
      this.bars = bars
      this.oi = oi || null
      this.meta = meta || {}
      this.cache.key = ''
      if (first || !this.keepSpacing) this.resetView()
      else this.retainSpacing()
      this.cross = null
      this.dirty = true
    }

    /** 切周期：根宽不变，看见的时间跨度跟着周期走——TradingView 的规矩。 */
    switchInterval(bars, oi, meta) {
      const spacing = this.bars ? this.barSpacing() : this.opt.style.spacing
      const anchorRight = this.bars ? this.view.to : null
      this.bars = bars
      this.oi = oi || null
      this.meta = meta || {}
      this.cache.key = ''
      const plotW = this.layout().plotW
      const span = (plotW / Math.min(MAX_BAR_SPACING, Math.max(MIN_BAR_SPACING, spacing))) * bars.step
      const lastT = bars.t0 + (bars.c.length - 1) * bars.step
      const to = anchorRight != null ? Math.min(anchorRight, lastT + span * 0.06) : lastT + span * 0.06
      this.view = this.clamp({ from: to - span, to })
      this.price.zoom = 1; this.price.shift = 0
      this.cross = null
      this.dirty = true
    }

    /** 换风格时用：右边缘不动，按新方案的默认根间距重新定视野宽度。 */
    applySpacing() {
      const b = this.bars
      if (!b) return
      const plotW = this.layout().plotW
      const span = (plotW / this.opt.style.spacing) * b.step
      const to = this.view.to
      this.view = this.clamp({ from: to - span, to })
      this.dirty = true
    }
    resetView() {
      const b = this.bars
      if (!b) return
      const plotW = this.layout().plotW
      const span = (plotW / this.opt.style.spacing) * b.step
      const lastT = b.t0 + (b.c.length - 1) * b.step
      const to = lastT + span * 0.06
      this.view = this.clamp({ from: to - span, to })
      this.price.zoom = 1; this.price.shift = 0
      this.dirty = true
    }

    retainSpacing() { this.view = this.clamp(this.view); this.dirty = true }

    // ------------------------------------------------------------ 布局
    layout() {
      const W = this.root.clientWidth || 360
      const H = this.root.clientHeight || 420
      const S = this.opt.style
      const plotW = Math.max(40, W - S.axisW)
      const subH = Math.min(S.subH, Math.max(44, (H - S.timeH) * 0.3))
      const subs = this.subs.length
      const mainH = Math.max(80, H - S.timeH - subs * subH)
      const panes = [{ key: '__main', y: 0, h: mainH }]
      let y = mainH
      for (const k of this.subs) { panes.push({ key: k, y, h: subH }); y += subH }
      return { W, H, plotW, panes, mainH, subH, timeY: H - S.timeH }
    }

    barSpacing() {
      const b = this.bars
      if (!b) return this.opt.style.spacing
      const plotW = this.layout().plotW
      return plotW / ((this.view.to - this.view.from) / b.step)
    }

    x(t) {
      const L = this.layout()
      return ((t - this.view.from) / (this.view.to - this.view.from)) * L.plotW
    }
    tAt(x) {
      const L = this.layout()
      return this.view.from + (x / L.plotW) * (this.view.to - this.view.from)
    }
    indexAt(x) {
      const b = this.bars
      if (!b) return 0
      const i = Math.round((this.tAt(x) - b.t0) / b.step)
      return Math.max(0, Math.min(b.c.length - 1, i))
    }

    /** 视野只允许越界一点点：左边到头留半屏，右边最多把最后一根推到 30% 处。 */
    clamp(v, soft) {
      const b = this.bars
      if (!b) return v
      const plotW = this.layout().plotW
      const span0 = v.to - v.from
      const minSpan = (plotW / MAX_BAR_SPACING) * b.step
      const maxSpan = Math.min((plotW / MIN_BAR_SPACING) * b.step, b.c.length * b.step * 3)
      const span = Math.max(minSpan, Math.min(maxSpan, span0))
      let to = v.to + (span - span0) / 2
      const firstT = b.t0
      const lastT = b.t0 + (b.c.length - 1) * b.step
      const give = soft ? span * 0.12 : 0
      const maxTo = lastT + span * 0.7 + give
      const minTo = firstT + span * 0.3 - give
      if (to > maxTo) to = maxTo
      if (to < minTo) to = minTo
      return { from: to - span, to }
    }

    // ------------------------------------------------------------ 指标缓存
    calc() {
      const b = this.bars
      if (!b) return null
      const key = this.meta.key + '|' + JSON.stringify(this.overlays) + JSON.stringify(this.subs) + JSON.stringify(this.params)
      if (this.cache.key === key) return this.cache.v
      const v = {}
      const want = new Set([].concat(this.overlays, this.subs))
      if (want.has('MA')) v.MA = this.params.MA.map((n) => sma(b.c, n))
      if (want.has('EMA')) v.EMA = this.params.EMA.map((n) => ema(b.c, n))
      if (want.has('BOLL')) v.BOLL = boll(b.c, this.params.BOLL[0], this.params.BOLL[1])
      if (want.has('VOL')) v.VOL = this.params.VOL.map((n) => sma(b.v, n))
      if (want.has('MACD')) v.MACD = macd(b.c, this.params.MACD[0], this.params.MACD[1], this.params.MACD[2])
      if (want.has('RSI')) v.RSI = this.params.RSI.map((n) => rsi(b.c, n))
      if (want.has('KDJ')) v.KDJ = kdj(b.h, b.l, b.c, this.params.KDJ[0], this.params.KDJ[1], this.params.KDJ[2])
      if (want.has('SRSI')) v.SRSI = stochRsi(b.c, this.params.SRSI[0], this.params.SRSI[1], this.params.SRSI[2], this.params.SRSI[3])
      if (want.has('ATR')) v.ATR = atr(b.h, b.l, b.c, this.params.ATR[0])
      if (want.has('OI')) v.OI = this.oiAligned()
      this.cache = { key, v }
      return v
    }

    /** OI 按各自的时间戳取「不晚于这根开盘」的那一个。 */
    oiAligned() {
      const b = this.bars, o = this.oi
      if (!b || !o) return null
      const out = nan(b.c.length)
      for (let i = 0; i < b.c.length; i++) {
        const t = b.t0 + i * b.step
        const j = Math.floor((t - o.t0) / o.step)
        if (j >= 0 && j < o.v.length) out[i] = o.v[j]
      }
      return out
    }

    visible() {
      const b = this.bars
      const lo = Math.max(0, Math.floor((this.view.from - b.t0) / b.step) - 1)
      const hi = Math.min(b.c.length - 1, Math.ceil((this.view.to - b.t0) / b.step) + 1)
      return { lo, hi }
    }

    // ------------------------------------------------------------ 价格映射
    priceRange() {
      const b = this.bars
      const { lo, hi } = this.visible()
      let min = Infinity, max = -Infinity
      for (let i = lo; i <= hi; i++) {
        if (b.h[i] > max) max = b.h[i]
        if (b.l[i] < min) min = b.l[i]
      }
      const v = this.calc()
      const eat = (arr) => { for (let i = lo; i <= hi; i++) { const x = arr[i]; if (Number.isFinite(x)) { if (x > max) max = x; if (x < min) min = x } } }
      if (this.overlays.includes('MA') && v.MA) v.MA.forEach(eat)
      if (this.overlays.includes('EMA') && v.EMA) v.EMA.forEach(eat)
      if (this.overlays.includes('BOLL') && v.BOLL) { eat(v.BOLL.up); eat(v.BOLL.dn) }
      for (const d of this.draws) {
        const pts = d.type === 'hline' ? [d.a] : [d.a, d.b]
        for (const p of pts) { if (p.p > max) max = p.p; if (p.p < min) min = p.p }
      }
      if (!Number.isFinite(min) || !Number.isFinite(max)) { min = 0; max = 1 }
      if (max === min) { max = min * 1.001 + 1; min = min * 0.999 - 1 }
      const padf = this.opt.style.pad
      let a = min - (max - min) * padf
      let z = max + (max - min) * padf
      const mid = (a + z) / 2
      const half = ((z - a) / 2) / Math.max(0.15, this.price.zoom)
      const off = half * 2 * this.price.shift
      return { lo: mid - half + off, hi: mid + half + off, base: b.c[lo] }
    }

    fwd(p, r) {
      if (this.price.mode === 'log') return Math.log(Math.max(1e-12, p))
      if (this.price.mode === 'percent') return (p / r.base - 1) * 100
      return p
    }
    yOf(p, pane, r) {
      const a = this.fwd(r.lo, r), z = this.fwd(r.hi, r)
      const f = this.fwd(p, r)
      return pane.y + pane.h - ((f - a) / (z - a)) * pane.h
    }
    pOf(y, pane, r) {
      const a = this.fwd(r.lo, r), z = this.fwd(r.hi, r)
      const f = a + ((pane.y + pane.h - y) / pane.h) * (z - a)
      if (this.price.mode === 'log') return Math.exp(f)
      if (this.price.mode === 'percent') return (f / 100 + 1) * r.base
      return f
    }

    // ------------------------------------------------------------ 画
    _observe() {
      const ro = new ResizeObserver(() => { this.resize(); this.dirty = true })
      ro.observe(this.root)
      this.resize()
    }
    resize() {
      const dpr = Math.min(3, global.devicePixelRatio || 1)
      const W = this.root.clientWidth || 360, H = this.root.clientHeight || 420
      for (const c of [this.base, this.over]) {
        c.width = Math.max(1, Math.round(W * dpr))
        c.height = Math.max(1, Math.round(H * dpr))
      }
      this.dpr = dpr
      this.bctx.setTransform(dpr, 0, 0, dpr, 0, 0)
      this.octx.setTransform(dpr, 0, 0, dpr, 0, 0)
    }

    _loop() {
      const tick = () => {
        if (this.anim) this.anim()
        if (this.dirty) { this.dirty = false; this.paint() }
        requestAnimationFrame(tick)
      }
      requestAnimationFrame(tick)
    }

    hair(y) { const d = this.dpr; return (Math.round(y * d) + 0.5) / d }

    paint() {
      if (!this.bars) return
      const t = this.opt.theme
      const L = this.layout()
      const ctx = this.bctx
      ctx.clearRect(0, 0, L.W, L.H)
      ctx.fillStyle = t.bg
      ctx.fillRect(0, 0, L.W, L.H)

      const r = this.priceRange()
      const main = L.panes[0]
      this.r = r

      this.drawPriceGrid(ctx, main, r, L)
      this.drawTimeGrid(ctx, L)
      this.drawCandles(ctx, main, r, L)
      this.drawOverlays(ctx, main, r, L)
      this.drawDrawings(ctx, main, r, L)
      this.drawLastPrice(ctx, main, r, L)
      for (let k = 1; k < L.panes.length; k++) this.drawSub(ctx, L.panes[k], L)
      this.drawTimeAxis(ctx, L)
      this.drawLegend(ctx, main, L)
      this.paintOver(L, r)
    }

    drawPriceGrid(ctx, pane, r, L) {
      const t = this.opt.theme
      const a = this.fwd(r.lo, r), z = this.fwd(r.hi, r)
      const step = niceStep(z - a, Math.max(2, Math.floor(pane.h / 46)))
      ctx.lineWidth = 1 / this.dpr
      ctx.strokeStyle = t.grid
      ctx.fillStyle = t.dim
      ctx.font = '10px ui-monospace, SFMono-Regular, Menlo, monospace'
      ctx.textAlign = 'left'
      ctx.textBaseline = 'middle'
      const p = this.meta.p != null ? this.meta.p : 2
      const gm = this.opt.style.grid
      for (let f = Math.ceil(a / step) * step; f <= z; f += step) {
        const y = pane.y + pane.h - ((f - a) / (z - a)) * pane.h
        if (y < pane.y + 6 || y > pane.y + pane.h - 2) continue
        if (gm !== 'none') {
          const x0 = gm === 'tick' ? L.plotW - 22 : 0
          ctx.beginPath(); ctx.moveTo(x0, this.hair(y)); ctx.lineTo(L.plotW, this.hair(y)); ctx.stroke()
        }
        let label
        if (this.price.mode === 'percent') label = (f >= 0 ? '+' : '') + f.toFixed(1) + '%'
        else if (this.price.mode === 'log') label = fmtNum(Math.exp(f), p)
        else label = fmtNum(f, p)
        ctx.fillText(label, L.plotW + 5, y)
      }
      ctx.strokeStyle = t.axis
      ctx.beginPath(); ctx.moveTo(this.hair(L.plotW), 0); ctx.lineTo(this.hair(L.plotW), L.H); ctx.stroke()
    }

    timeTicks(L) {
      const span = this.view.to - this.view.from
      const step = timeStep(span, L.plotW, 74)
      const off = tzOffsetMin(this.tz)
      const out = []
      const shift = off * 60e3
      let first = Math.ceil((this.view.from + shift) / step) * step - shift
      for (let t = first; t <= this.view.to; t += step) out.push({ t, step })
      return out
    }

    drawTimeGrid(ctx, L) {
      const t = this.opt.theme
      if (this.opt.style.grid !== 'both') return
      ctx.strokeStyle = t.grid
      ctx.lineWidth = 1 / this.dpr
      for (const k of this.timeTicks(L)) {
        const x = this.hair(this.x(k.t))
        if (x < 0 || x > L.plotW) continue
        ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, L.timeY); ctx.stroke()
      }
    }

    drawTimeAxis(ctx, L) {
      const t = this.opt.theme
      const off = tzOffsetMin(this.tz)
      ctx.strokeStyle = t.axis
      ctx.lineWidth = 1 / this.dpr
      ctx.beginPath(); ctx.moveTo(0, this.hair(L.timeY)); ctx.lineTo(L.W, this.hair(L.timeY)); ctx.stroke()
      ctx.fillStyle = t.dim
      ctx.font = '10px ui-monospace, SFMono-Regular, Menlo, monospace'
      ctx.textAlign = 'center'
      ctx.textBaseline = 'middle'
      for (const k of this.timeTicks(L)) {
        const x = this.x(k.t)
        if (x < 18 || x > L.plotW - 18) continue
        ctx.fillText(fmtTick(k.t, k.step, off), x, L.timeY + this.opt.style.timeH / 2)
      }
    }

    drawCandles(ctx, pane, r, L) {
      const b = this.bars, t = this.opt.theme, S = this.opt.style
      const { lo, hi } = this.visible()
      const spacing = this.barSpacing()
      const w = candleWidths(spacing, this.dpr, this.mobile, S.bodyR)
      const bodyW = w.body / this.dpr
      const wickW = Math.max(0.5, S.wick) / this.dpr
      const minBody = Math.max(wickW, S.minBody / this.dpr)
      const thin = spacing < 1.3 || bodyW <= wickW * 1.2
      const radius = Math.min(S.radius, bodyW / 2)
      const hollow = S.shape === 'hollowUp' || S.shape === 'outline'
      const lw = Math.max(1, Math.round(this.dpr * 0.9)) / this.dpr
      ctx.save()
      ctx.beginPath(); ctx.rect(0, pane.y, L.plotW, pane.h); ctx.clip()
      ctx.lineCap = S.wickCap === 'round' ? 'round' : 'butt'
      for (let i = lo; i <= hi; i++) {
        const xc = this.x(b.t0 + i * b.step)
        if (xc < -4 || xc > L.plotW + 4) continue
        const up = b.c[i] >= b.o[i]
        const col = up ? t.up : t.down
        const yh = this.yOf(b.h[i], pane, r), yl = this.yOf(b.l[i], pane, r)

        // 影线：可以比实体淡，端头可以是圆的
        if (S.wickCap === 'round' && !thin) {
          ctx.strokeStyle = S.wickTint < 1 ? mixHex(t.bg, col, S.wickTint) : col
          ctx.lineWidth = wickW
          ctx.beginPath()
          ctx.moveTo(this.hair(xc), yh + wickW / 2)
          ctx.lineTo(this.hair(xc), yl - wickW / 2)
          ctx.stroke()
        } else {
          ctx.fillStyle = S.wickTint < 1 ? mixHex(t.bg, col, S.wickTint) : col
          const xw = Math.round((xc - wickW / 2) * this.dpr) / this.dpr
          ctx.fillRect(xw, yh, wickW, Math.max(wickW, yl - yh))
        }
        if (thin) continue

        const yo = this.yOf(b.o[i], pane, r), yc = this.yOf(b.c[i], pane, r)
        const top = Math.min(yo, yc)
        const h = Math.max(minBody, Math.abs(yc - yo))
        const xb = Math.round((xc - bodyW / 2) * this.dpr) / this.dpr
        const drawHollow = S.shape === 'outline' || (S.shape === 'hollowUp' && up)

        ctx.fillStyle = col
        ctx.strokeStyle = col
        if (drawHollow && h > lw * 2.2 && bodyW > lw * 2.2) {
          // 描边实体：先用底色挖空，K 线之间才不会互相糊住
          ctx.lineWidth = lw
          if (radius > 0) { roundRect(ctx, xb, top, bodyW, h, radius); ctx.fillStyle = t.bg; ctx.fill(); ctx.strokeStyle = col; ctx.stroke() }
          else {
            ctx.fillStyle = t.bg
            ctx.fillRect(xb, top, bodyW, h)
            ctx.strokeStyle = col
            ctx.strokeRect(xb + lw / 2, top + lw / 2, bodyW - lw, h - lw)
          }
        } else if (radius > 0 && h > radius * 2) {
          roundRect(ctx, xb, top, bodyW, h, radius); ctx.fill()
        } else {
          ctx.fillRect(xb, top, bodyW, h)
        }
      }
      ctx.lineCap = 'butt'
      ctx.restore()
    }

    line(ctx, pane, r, arr, color, lo, hi, width) {
      const b = this.bars
      ctx.strokeStyle = color
      ctx.lineWidth = width || 1
      ctx.lineJoin = 'round'
      ctx.beginPath()
      let on = false
      for (let i = lo; i <= hi; i++) {
        const y = arr[i]
        if (!Number.isFinite(y)) { on = false; continue }
        const x = this.x(b.t0 + i * b.step)
        const py = this.yOf(y, pane, r)
        if (!on) { ctx.moveTo(x, py); on = true } else ctx.lineTo(x, py)
      }
      ctx.stroke()
    }

    drawOverlays(ctx, pane, r, L) {
      const t = this.opt.theme
      const v = this.calc()
      const { lo, hi } = this.visible()
      ctx.save()
      ctx.beginPath(); ctx.rect(0, pane.y, L.plotW, pane.h); ctx.clip()
      if (this.overlays.includes('MA') && v.MA) v.MA.forEach((a, k) => this.line(ctx, pane, r, a, PALETTE[k % PALETTE.length], lo, hi))
      if (this.overlays.includes('EMA') && v.EMA) v.EMA.forEach((a, k) => this.line(ctx, pane, r, a, PALETTE[(k + 3) % PALETTE.length], lo, hi))
      if (this.overlays.includes('BOLL') && v.BOLL) {
        this.line(ctx, pane, r, v.BOLL.up, t.band, lo, hi)
        this.line(ctx, pane, r, v.BOLL.mid, t.amber, lo, hi)
        this.line(ctx, pane, r, v.BOLL.dn, t.band, lo, hi)
      }
      ctx.restore()
    }

    drawLastPrice(ctx, pane, r, L) {
      const b = this.bars, t = this.opt.theme
      const i = b.c.length - 1
      const p = b.c[i]
      const y = this.yOf(p, pane, r)
      if (y < pane.y || y > pane.y + pane.h) return
      const up = b.c[i] >= b.o[i]
      ctx.save()
      if (this.opt.style.lastDash) ctx.setLineDash([3 / this.dpr, 3 / this.dpr])
      ctx.strokeStyle = up ? t.up : t.down
      ctx.lineWidth = 1 / this.dpr
      ctx.beginPath(); ctx.moveTo(0, this.hair(y)); ctx.lineTo(L.plotW, this.hair(y)); ctx.stroke()
      ctx.restore()
      const label = fmtNum(p, this.meta.p != null ? this.meta.p : 2)
      ctx.font = '10px ui-monospace, SFMono-Regular, Menlo, monospace'
      const w = Math.min(this.opt.style.axisW - 2, ctx.measureText(label).width + 10)
      const h = 15
      ctx.fillStyle = up ? t.up : t.down
      roundRect(ctx, L.plotW + 2, y - h / 2, w, h, 3)
      ctx.fill()
      ctx.fillStyle = t.chip
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle'
      ctx.fillText(label, L.plotW + 2 + w / 2, y)
    }

    // ------------------------------------------------------------ 副图
    drawSub(ctx, pane, L) {
      const t = this.opt.theme
      const b = this.bars, v = this.calc()
      const { lo, hi } = this.visible()
      ctx.strokeStyle = t.axis
      ctx.lineWidth = 1 / this.dpr
      ctx.beginPath(); ctx.moveTo(0, this.hair(pane.y)); ctx.lineTo(L.W, this.hair(pane.y)); ctx.stroke()
      const inner = { y: pane.y + 15, h: pane.h - 19 }
      ctx.save()
      ctx.beginPath(); ctx.rect(0, pane.y + 1, L.plotW, pane.h - 1); ctx.clip()
      const key = pane.key
      if (key === 'VOL') this.subVol(ctx, inner, L, lo, hi, v)
      else if (key === 'MACD') this.subMacd(ctx, inner, L, lo, hi, v)
      else if (key === 'OI') this.subOi(ctx, inner, L, lo, hi, v)
      else if (key === 'RSI') this.subLines(ctx, inner, L, lo, hi, v.RSI, [0, 100], [30, 70])
      else if (key === 'KDJ') this.subLines(ctx, inner, L, lo, hi, [v.KDJ.K, v.KDJ.D, v.KDJ.J], null, [20, 80])
      else if (key === 'SRSI') this.subLines(ctx, inner, L, lo, hi, [v.SRSI.K, v.SRSI.D], [0, 100], [20, 80])
      else if (key === 'ATR') this.subLines(ctx, inner, L, lo, hi, [v.ATR], null, null)
      ctx.restore()
      this.subLegend(ctx, pane, L, key, v)
    }

    extent(arrs, lo, hi, fixed) {
      if (fixed) return fixed
      let min = Infinity, max = -Infinity
      for (const a of arrs) {
        if (!a) continue
        for (let i = lo; i <= hi; i++) { const x = a[i]; if (Number.isFinite(x)) { if (x > max) max = x; if (x < min) min = x } }
      }
      if (!Number.isFinite(min)) { min = 0; max = 1 }
      if (min === max) { max = min + 1 }
      const pad = (max - min) * 0.1
      return [min - pad, max + pad]
    }

    subY(inner, ext, x) { return inner.y + inner.h - ((x - ext[0]) / (ext[1] - ext[0])) * inner.h }

    subLines(ctx, inner, L, lo, hi, arrs, fixed, guides) {
      const b = this.bars, t = this.opt.theme
      const ext = this.extent(arrs, lo, hi, fixed)
      if (guides) {
        ctx.save(); ctx.setLineDash([2 / this.dpr, 3 / this.dpr]); ctx.strokeStyle = t.grid; ctx.lineWidth = 1 / this.dpr
        for (const g of guides) {
          const y = this.subY(inner, ext, g)
          if (y < inner.y || y > inner.y + inner.h) continue
          ctx.beginPath(); ctx.moveTo(0, this.hair(y)); ctx.lineTo(L.plotW, this.hair(y)); ctx.stroke()
        }
        ctx.restore()
      }
      arrs.forEach((a, k) => {
        if (!a) return
        ctx.strokeStyle = PALETTE[k % PALETTE.length]
        ctx.lineWidth = 1
        ctx.beginPath()
        let on = false
        for (let i = lo; i <= hi; i++) {
          const x = a[i]
          if (!Number.isFinite(x)) { on = false; continue }
          const px = this.x(b.t0 + i * b.step), py = this.subY(inner, ext, x)
          if (!on) { ctx.moveTo(px, py); on = true } else ctx.lineTo(px, py)
        }
        ctx.stroke()
      })
    }

    subVol(ctx, inner, L, lo, hi, v) {
      const b = this.bars, t = this.opt.theme
      let max = 0
      for (let i = lo; i <= hi; i++) if (b.v[i] > max) max = b.v[i]
      if (max <= 0) max = 1
      const ext = [0, max * 1.1]
      const spacing = this.barSpacing()
      const w = candleWidths(spacing, this.dpr, this.mobile, this.opt.style.bodyR)
      const bodyW = w.body / this.dpr
      for (let i = lo; i <= hi; i++) {
        const xc = this.x(b.t0 + i * b.step)
        if (xc < -4 || xc > L.plotW + 4) continue
        const y = this.subY(inner, ext, b.v[i])
        ctx.fillStyle = b.c[i] >= b.o[i] ? t.volUp : t.volDn
        const xb = Math.round((xc - bodyW / 2) * this.dpr) / this.dpr
        ctx.fillRect(xb, y, bodyW, inner.y + inner.h - y)
      }
      if (v.VOL) v.VOL.forEach((a, k) => {
        ctx.strokeStyle = PALETTE[k % PALETTE.length]; ctx.lineWidth = 1
        ctx.beginPath(); let on = false
        for (let i = lo; i <= hi; i++) {
          if (!Number.isFinite(a[i])) { on = false; continue }
          const px = this.x(b.t0 + i * b.step), py = this.subY(inner, ext, a[i])
          if (!on) { ctx.moveTo(px, py); on = true } else ctx.lineTo(px, py)
        }
        ctx.stroke()
      })
    }

    subMacd(ctx, inner, L, lo, hi, v) {
      const b = this.bars, t = this.opt.theme
      const m = v.MACD
      const ext = this.extent([m.dif, m.dea, m.hist], lo, hi, null)
      const span = Math.max(Math.abs(ext[0]), Math.abs(ext[1]))
      const e = [-span, span]
      const zero = this.subY(inner, e, 0)
      const spacing = this.barSpacing()
      const bw = Math.max(1 / this.dpr, candleWidths(spacing, this.dpr, this.mobile, this.opt.style.bodyR).body / this.dpr)
      for (let i = lo; i <= hi; i++) {
        const x = m.hist[i]
        if (!Number.isFinite(x)) continue
        const xc = this.x(b.t0 + i * b.step)
        const y = this.subY(inner, e, x)
        const rising = !Number.isFinite(m.hist[i - 1]) || x >= m.hist[i - 1]
        ctx.fillStyle = x >= 0 ? (rising ? t.up : t.volUp) : (rising ? t.volDn : t.down)
        ctx.fillRect(Math.round((xc - bw / 2) * this.dpr) / this.dpr, Math.min(y, zero), bw, Math.max(1 / this.dpr, Math.abs(zero - y)))
      }
      ctx.strokeStyle = t.grid; ctx.lineWidth = 1 / this.dpr
      ctx.beginPath(); ctx.moveTo(0, this.hair(zero)); ctx.lineTo(L.plotW, this.hair(zero)); ctx.stroke()
      const put = (arr, color) => {
        ctx.strokeStyle = color; ctx.lineWidth = 1; ctx.beginPath(); let on = false
        for (let i = lo; i <= hi; i++) {
          if (!Number.isFinite(arr[i])) { on = false; continue }
          const px = this.x(b.t0 + i * b.step), py = this.subY(inner, e, arr[i])
          if (!on) { ctx.moveTo(px, py); on = true } else ctx.lineTo(px, py)
        }
        ctx.stroke()
      }
      put(m.dif, PALETTE[0]); put(m.dea, PALETTE[1])
    }

    subOi(ctx, inner, L, lo, hi, v) {
      const t = this.opt.theme
      const a = v.OI
      if (!a) {
        ctx.fillStyle = t.dim
        ctx.font = '11px -apple-system, system-ui, sans-serif'
        ctx.textAlign = 'left'; ctx.textBaseline = 'middle'
        ctx.fillText('这个周期币安不提供持仓量历史（最细 5 分钟）', 8, inner.y + inner.h / 2)
        return
      }
      let has = false
      for (let i = lo; i <= hi; i++) if (Number.isFinite(a[i])) { has = true; break }
      if (!has) {
        ctx.fillStyle = t.dim
        ctx.font = '11px -apple-system, system-ui, sans-serif'
        ctx.textAlign = 'left'; ctx.textBaseline = 'middle'
        ctx.fillText('这一段没有持仓量：币安只保留最近 30 天', 8, inner.y + inner.h / 2)
        return
      }
      const b = this.bars
      const ext = this.extent([a], lo, hi, null)
      ctx.beginPath()
      let started = false, lastX = 0
      for (let i = lo; i <= hi; i++) {
        if (!Number.isFinite(a[i])) continue
        const px = this.x(b.t0 + i * b.step), py = this.subY(inner, ext, a[i])
        if (!started) { ctx.moveTo(px, py); started = true } else ctx.lineTo(px, py)
        lastX = px
      }
      ctx.strokeStyle = t.oi; ctx.lineWidth = 1.2; ctx.stroke()
      ctx.lineTo(lastX, inner.y + inner.h)
      const first = this.x(b.t0 + lo * b.step)
      ctx.lineTo(first, inner.y + inner.h)
      ctx.closePath()
      const g = ctx.createLinearGradient(0, inner.y, 0, inner.y + inner.h)
      g.addColorStop(0, t.oiFill); g.addColorStop(1, t.oi + '00')
      ctx.fillStyle = g; ctx.fill()
    }

    // ------------------------------------------------------------ 图例
    legendIndex() {
      if (this.cross) return this.cross.i
      return this.bars.c.length - 1
    }

    drawLegend(ctx, pane, L) {
      const t = this.opt.theme
      const v = this.calc()
      const i = this.legendIndex()
      const p = this.meta.p != null ? this.meta.p : 2
      let x = 8
      const y = pane.y + 11
      ctx.font = '10px ui-monospace, SFMono-Regular, Menlo, monospace'
      ctx.textAlign = 'left'; ctx.textBaseline = 'middle'
      const put = (text, color) => { ctx.fillStyle = color; ctx.fillText(text, x, y); x += ctx.measureText(text).width + 8 }
      if (this.overlays.includes('MA') && v.MA) this.params.MA.forEach((n, k) => put('MA' + n + ' ' + fmtNum(v.MA[k][i], p), PALETTE[k % PALETTE.length]))
      if (this.overlays.includes('EMA') && v.EMA) this.params.EMA.forEach((n, k) => put('EMA' + n + ' ' + fmtNum(v.EMA[k][i], p), PALETTE[(k + 3) % PALETTE.length]))
      if (this.overlays.includes('BOLL') && v.BOLL) {
        put('UP ' + fmtNum(v.BOLL.up[i], p), t.band)
        put('MB ' + fmtNum(v.BOLL.mid[i], p), t.amber)
        put('DN ' + fmtNum(v.BOLL.dn[i], p), t.band)
      }
    }

    subLegend(ctx, pane, L, key, v) {
      const t = this.opt.theme
      const i = this.legendIndex()
      let x = 8
      const y = pane.y + 9
      ctx.font = '10px ui-monospace, SFMono-Regular, Menlo, monospace'
      ctx.textAlign = 'left'; ctx.textBaseline = 'middle'
      const put = (text, color) => { ctx.fillStyle = color; ctx.fillText(text, x, y); x += ctx.measureText(text).width + 8 }
      if (key === 'VOL') {
        put('VOL ' + fmtVol(this.bars.v[i]), t.text)
        if (v.VOL) this.params.VOL.forEach((n, k) => put('MA' + n + ' ' + fmtVol(v.VOL[k][i]), PALETTE[k % PALETTE.length]))
      } else if (key === 'MACD') {
        put('MACD(' + this.params.MACD.join(',') + ')', t.dim)
        put('DIF ' + fmtNum(v.MACD.dif[i], 2), PALETTE[0])
        put('DEA ' + fmtNum(v.MACD.dea[i], 2), PALETTE[1])
        put('M ' + fmtNum(v.MACD.hist[i], 2), v.MACD.hist[i] >= 0 ? t.up : t.down)
      } else if (key === 'RSI') {
        put('RSI', t.dim)
        this.params.RSI.forEach((n, k) => put(n + ' ' + fmtNum(v.RSI[k][i], 1), PALETTE[k % PALETTE.length]))
      } else if (key === 'KDJ') {
        put('KDJ(' + this.params.KDJ.join(',') + ')', t.dim)
        put('K ' + fmtNum(v.KDJ.K[i], 1), PALETTE[0])
        put('D ' + fmtNum(v.KDJ.D[i], 1), PALETTE[1])
        put('J ' + fmtNum(v.KDJ.J[i], 1), PALETTE[2])
      } else if (key === 'SRSI') {
        put('StochRSI', t.dim)
        put('K ' + fmtNum(v.SRSI.K[i], 1), PALETTE[0])
        put('D ' + fmtNum(v.SRSI.D[i], 1), PALETTE[1])
      } else if (key === 'ATR') {
        put('ATR' + this.params.ATR[0] + ' ' + fmtNum(v.ATR[i], this.meta.p != null ? this.meta.p : 2), PALETTE[0])
      } else if (key === 'OI') {
        const x0 = v.OI && Number.isFinite(v.OI[i]) ? fmtVol(v.OI[i]) : '--'
        put('持仓量 ' + x0, t.oi)
        put('币安 · 近 30 天', t.dim)
      }
    }

    // ------------------------------------------------------------ 画线
    drawDrawings(ctx, pane, r, L) {
      const t = this.opt.theme
      for (const d of this.draws) {
        const sel = this.selected === d.id
        ctx.strokeStyle = sel ? t.amber : (d.color || t.band)
        ctx.lineWidth = sel ? 1.8 : 1.3
        ctx.setLineDash([])
        if (d.type === 'hline') {
          const y = this.yOf(d.a.p, pane, r)
          ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(L.plotW, y); ctx.stroke()
          ctx.font = '10px ui-monospace, monospace'
          ctx.textAlign = 'right'; ctx.textBaseline = 'bottom'
          ctx.fillStyle = ctx.strokeStyle
          ctx.fillText(fmtNum(d.a.p, this.meta.p != null ? this.meta.p : 2), L.plotW - 4, y - 3)
          if (sel) this.handle(ctx, L.plotW / 2, y)
        } else {
          const x1 = this.x(d.a.t), y1 = this.yOf(d.a.p, pane, r)
          const x2 = this.x(d.b.t), y2 = this.yOf(d.b.p, pane, r)
          ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke()
          if (sel) { this.handle(ctx, x1, y1); this.handle(ctx, x2, y2) }
        }
      }
      if (this.pending) {
        const x1 = this.x(this.pending.t), y1 = this.yOf(this.pending.p, pane, r)
        ctx.fillStyle = t.amber
        ctx.beginPath(); ctx.arc(x1, y1, 4, 0, Math.PI * 2); ctx.fill()
      }
    }
    handle(ctx, x, y) {
      ctx.fillStyle = this.opt.theme.panel
      ctx.strokeStyle = this.opt.theme.amber
      ctx.lineWidth = 1.4
      ctx.beginPath(); ctx.arc(x, y, 5, 0, Math.PI * 2); ctx.fill(); ctx.stroke()
    }

    hitDraw(px, py) {
      const L = this.layout(), pane = L.panes[0], r = this.r || this.priceRange()
      for (let k = this.draws.length - 1; k >= 0; k--) {
        const d = this.draws[k]
        if (d.type === 'hline') {
          if (Math.abs(this.yOf(d.a.p, pane, r) - py) < 9) return { d, part: 'body' }
          continue
        }
        const x1 = this.x(d.a.t), y1 = this.yOf(d.a.p, pane, r)
        const x2 = this.x(d.b.t), y2 = this.yOf(d.b.p, pane, r)
        if (Math.hypot(px - x1, py - y1) < 12) return { d, part: 'a' }
        if (Math.hypot(px - x2, py - y2) < 12) return { d, part: 'b' }
        if (distSeg(px, py, x1, y1, x2, y2) < 9) return { d, part: 'body' }
      }
      return null
    }

    point(px, py) {
      const L = this.layout(), pane = L.panes[0], r = this.r || this.priceRange()
      const b = this.bars
      let t = this.tAt(px)
      if (this.magnet) { const i = this.indexAt(px); t = b.t0 + i * b.step }
      return { t, p: this.pOf(py, pane, r) }
    }

    // ------------------------------------------------------------ 十字线层
    paintOver(L, r) {
      const ctx = this.octx, t = this.opt.theme
      ctx.clearRect(0, 0, L.W, L.H)
      if (!this.cross) { if (this.opt.onCross) this.opt.onCross(null); return }
      const b = this.bars
      const i = this.cross.i
      const pane = L.panes[0]
      const xc = this.magnet ? this.x(b.t0 + i * b.step) : this.cross.x
      const y = Math.max(0, Math.min(L.timeY, this.cross.y))
      ctx.save()
      ctx.setLineDash([3 / this.dpr, 3 / this.dpr])
      ctx.strokeStyle = t.cross
      ctx.lineWidth = 1 / this.dpr
      ctx.beginPath(); ctx.moveTo(this.hair(xc), 0); ctx.lineTo(this.hair(xc), L.timeY); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(0, this.hair(y)); ctx.lineTo(L.plotW, this.hair(y)); ctx.stroke()
      ctx.restore()

      // 右轴价格
      if (y <= pane.y + pane.h) {
        const p = this.pOf(y, pane, r)
        const label = this.price.mode === 'percent'
          ? ((p / r.base - 1) * 100).toFixed(2) + '%'
          : fmtNum(p, this.meta.p != null ? this.meta.p : 2)
        ctx.font = '10px ui-monospace, SFMono-Regular, Menlo, monospace'
        const w = Math.min(this.opt.style.axisW - 2, ctx.measureText(label).width + 10)
        ctx.fillStyle = t.crossBg
        roundRect(ctx, L.plotW + 2, y - 7.5, w, 15, 3); ctx.fill()
        ctx.fillStyle = t.crossInk
        ctx.textAlign = 'center'; ctx.textBaseline = 'middle'
        ctx.fillText(label, L.plotW + 2 + w / 2, y)
      }
      // 下轴时间
      const tl = fmtFull(b.t0 + i * b.step, tzOffsetMin(this.tz))
      ctx.font = '10px ui-monospace, SFMono-Regular, Menlo, monospace'
      const tw = ctx.measureText(tl).width + 12
      const tx = Math.max(2, Math.min(L.plotW - tw - 2, xc - tw / 2))
      ctx.fillStyle = t.crossBg
      roundRect(ctx, tx, L.timeY + 3, tw, this.opt.style.timeH - 6, 3); ctx.fill()
      ctx.fillStyle = t.crossInk
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle'
      ctx.fillText(tl, tx + tw / 2, L.timeY + this.opt.style.timeH / 2)

      if (this.opt.onCross) this.opt.onCross({ i, bar: this.barAt(i), tz: tzOffsetMin(this.tz) })
    }

    barAt(i) {
      const b = this.bars
      const prev = i > 0 ? b.c[i - 1] : b.o[i]
      return {
        t: b.t0 + i * b.step, o: b.o[i], h: b.h[i], l: b.l[i], c: b.c[i], v: b.v[i],
        chg: prev ? ((b.c[i] - prev) / prev) * 100 : 0,
        amp: b.l[i] ? ((b.h[i] - b.l[i]) / b.l[i]) * 100 : 0,
      }
    }

    // ------------------------------------------------------------ 手势
    _bind() {
      const el = this.base
      const pts = new Map()
      let mode = null            // 'pan' | 'pinch' | 'axis' | 'drag'
      let start = null
      let snap = null
      let press = null
      let moved = 0
      let vel = { v: 0, t: 0 }
      let lastTap = 0

      // 桌面上整台机身是按 transform 缩放摆进窗口的，所以量出来的矩形是
      // 缩放后的视觉尺寸，而画布的坐标系是缩放前的点。差一个比例就得除回去，
      // 否则十字线和手指会错位。
      const local = (e) => {
        const r = el.getBoundingClientRect()
        const k = r.width ? el.clientWidth / r.width : 1
        return { x: (e.clientX - r.left) * k, y: (e.clientY - r.top) * k }
      }
      const two = () => { const a = [...pts.values()]; return { d: Math.hypot(a[0].x - a[1].x, a[0].y - a[1].y), m: (a[0].x + a[1].x) / 2 } }

      el.addEventListener('pointerdown', (e) => {
        el.setPointerCapture(e.pointerId)
        const q = local(e)
        pts.set(e.pointerId, q)
        this.anim = null
        if (pts.size === 2) {
          const { d, m } = two()
          snap = { from0: this.view.from, span0: this.view.to - this.view.from, d0: Math.max(PINCH_MIN_PX, d), m0: m }
          mode = 'pinch'
          press = null
          return
        }
        moved = 0
        start = { ...q, view: { ...this.view }, shift: this.price.shift, zoom: this.price.zoom, at: e.timeStamp }
        vel = { v: 0, t: e.timeStamp, x: q.x }
        const L = this.layout()
        if (q.x > L.plotW) { mode = 'axis'; return }
        if (this.drawMode) { mode = 'draw'; return }
        const hit = this.hitDraw(q.x, q.y)
        if (hit && (this.selected === hit.d.id || hit.part !== 'body')) {
          mode = 'drag'
          this.selected = hit.d.id
          start.hit = hit
          start.a = { ...hit.d.a }
          start.b = hit.d.b ? { ...hit.d.b } : null
          this.dirty = true
          return
        }
        mode = 'pan'
        press = setTimeout(() => {
          press = null
          if (moved > 6) return
          this.setCross(q.x, q.y)
          if (navigator.vibrate) navigator.vibrate(8)
        }, 320)
      })

      el.addEventListener('pointermove', (e) => {
        if (!pts.has(e.pointerId)) return
        const q = local(e)
        pts.set(e.pointerId, q)
        if (mode === 'pinch' && pts.size === 2) {
          // 一次快照，不逐帧累乘：先捏开再捏拢和反过来，速度一样。
          const { d, m } = two()
          const L = this.layout()
          const b = this.bars
          const minSpan = (L.plotW / MAX_BAR_SPACING) * b.step
          const maxSpan = Math.min((L.plotW / MIN_BAR_SPACING) * b.step, b.c.length * b.step * 3)
          const span = Math.max(minSpan, Math.min(maxSpan, snap.span0 * snap.d0 / Math.max(PINCH_MIN_PX, d)))
          const mid = snap.from0 + (snap.m0 / L.plotW) * snap.span0
          const from = mid - (m / L.plotW) * span
          this.view = this.clamp({ from, to: from + span }, true)
          this.dirty = true
          return
        }
        if (!start) return
        const dx = q.x - start.x, dy = q.y - start.y
        moved = Math.max(moved, Math.hypot(dx, dy))
        if (press && moved > 6) { clearTimeout(press); press = null }

        if (mode === 'axis') {
          this.price.zoom = Math.max(0.25, Math.min(6, start.zoom * Math.exp(-dy / 220)))
          this.dirty = true
          return
        }
        if (mode === 'draw') return
        if (mode === 'drag') {
          const L = this.layout(), pane = L.panes[0], r = this.r
          const d = start.hit.d
          const dt = (dx / L.plotW) * (this.view.to - this.view.from)
          const shiftP = (p0, ypx) => this.pOf(this.yOf(p0, pane, r) + dy, pane, r)
          if (start.hit.part === 'body') {
            if (d.type === 'hline') d.a = { t: start.a.t, p: shiftP(start.a.p) }
            else {
              d.a = { t: start.a.t + dt, p: shiftP(start.a.p) }
              d.b = { t: start.b.t + dt, p: shiftP(start.b.p) }
            }
          } else if (start.hit.part === 'a') d.a = { t: start.a.t + dt, p: shiftP(start.a.p) }
          else d.b = { t: start.b.t + dt, p: shiftP(start.b.p) }
          this.dirty = true
          return
        }
        if (this.cross) { this.setCross(q.x, q.y); return }
        // 横向拖动 + 纵向平移
        const L = this.layout()
        const span = start.view.to - start.view.from
        const shift = -(dx / L.plotW) * span
        this.view = this.clamp({ from: start.view.from + shift, to: start.view.to + shift }, true)
        if (Math.abs(dy) > 14) this.price.shift = start.shift - dy / (L.panes[0].h * 2)
        const dt2 = e.timeStamp - vel.t
        if (dt2 > 0) { vel = { v: (q.x - vel.x) / dt2, t: e.timeStamp, x: q.x } }
        this.dirty = true
      })

      const up = (e) => {
        if (!pts.has(e.pointerId)) return
        const q = pts.get(e.pointerId)
        pts.delete(e.pointerId)
        if (press) { clearTimeout(press); press = null }
        if (mode === 'pinch') { if (pts.size < 2) { mode = pts.size ? 'pan' : null; start = null; this.settle() } return }
        if (mode === 'draw' && moved < 8) this.placePoint(q.x, q.y)
        else if (mode === 'pan' && moved < 8) {
          const now = e.timeStamp
          if (now - lastTap < 280) { this.resetView(); lastTap = 0 }
          else {
            lastTap = now
            if (this.cross) { this.cross = null; this.dirty = true }
            else {
              const hit = this.hitDraw(q.x, q.y)
              this.selected = hit ? hit.d.id : null
              this.dirty = true
              if (this.opt.onTap) this.opt.onTap(this.selected)
            }
          }
        } else if (mode === 'pan' && !this.cross) {
          this.flick(vel.v, e.timeStamp - vel.t)
        }
        if (mode === 'drag' && this.opt.onDrawChange) this.opt.onDrawChange()
        mode = pts.size ? mode : null
        start = null
        if (!pts.size) this.settle()
      }
      el.addEventListener('pointerup', up)
      el.addEventListener('pointercancel', up)

      el.addEventListener('wheel', (e) => {
        e.preventDefault()
        const L = this.layout()
        const r = el.getBoundingClientRect()
        const mx = (e.clientX - r.left) * (r.width ? el.clientWidth / r.width : 1)
        const span0 = this.view.to - this.view.from
        const k = Math.exp(e.deltaY * 0.0015)
        const b = this.bars
        const minSpan = (L.plotW / MAX_BAR_SPACING) * b.step
        const maxSpan = Math.min((L.plotW / MIN_BAR_SPACING) * b.step, b.c.length * b.step * 3)
        const span = Math.max(minSpan, Math.min(maxSpan, span0 * k))
        const at = this.view.from + (mx / L.plotW) * span0
        const from = at - (mx / L.plotW) * span
        this.view = this.clamp({ from, to: from + span })
        this.dirty = true
      }, { passive: false })
    }

    setCross(x, y) {
      const L = this.layout()
      const px = Math.max(0, Math.min(L.plotW, x))
      this.cross = { x: px, y, i: this.indexAt(px) }
      this.dirty = true
    }

    /** 甩出去之后按指数衰减滑行；到边界就停。 */
    flick(speed, gap) {
      if (gap > 90) return
      const s = Math.abs(speed)
      if (s < FLING_MIN_PX_PER_MS) return
      const v = Math.sign(speed) * Math.min(FLING_MAX_PX_PER_MS, s)
      const L = this.layout()
      const startView = { ...this.view }
      const span = startView.to - startView.from
      const t0 = performance.now()
      this.anim = () => {
        const { pastPx, done } = flingAt(v, performance.now() - t0, FLING_TAU_MS)
        const shift = -(pastPx / L.plotW) * span
        this.view = this.clamp({ from: startView.from + shift, to: startView.to + shift })
        this.dirty = true
        if (done) { this.anim = null; this.settle() }
      }
    }

    /** 越界之后弹回来。 */
    settle() {
      const target = this.clamp(this.view)
      if (Math.abs(target.from - this.view.from) < 1) { if (this.opt.onView) this.opt.onView(); return }
      const from0 = this.view.from, to0 = this.view.to
      const t0 = performance.now()
      this.anim = () => {
        const k = Math.min(1, (performance.now() - t0) / 240)
        const e = 1 - Math.pow(1 - k, 3)
        this.view = { from: from0 + (target.from - from0) * e, to: to0 + (target.to - to0) * e }
        this.dirty = true
        if (k >= 1) { this.anim = null; if (this.opt.onView) this.opt.onView() }
      }
    }

    // ------------------------------------------------------------ 画线动作
    placePoint(x, y) {
      const pt = this.point(x, y)
      if (this.drawMode === 'hline') {
        this.draws.push({ id: 'd' + Date.now(), type: 'hline', a: pt })
        this.drawMode = null
        this.pending = null
      } else if (this.drawMode === 'trend') {
        if (!this.pending) { this.pending = pt }
        else {
          this.draws.push({ id: 'd' + Date.now(), type: 'trend', a: this.pending, b: pt })
          this.pending = null
          this.drawMode = null
        }
      }
      this.dirty = true
      if (this.opt.onDrawChange) this.opt.onDrawChange()
    }
    removeSelected() {
      if (!this.selected) return
      this.draws = this.draws.filter((d) => d.id !== this.selected)
      this.selected = null
      this.dirty = true
      if (this.opt.onDrawChange) this.opt.onDrawChange()
    }
    clearDraws() { this.draws = []; this.selected = null; this.pending = null; this.dirty = true; if (this.opt.onDrawChange) this.opt.onDrawChange() }
  }

  function roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath()
    ctx.moveTo(x + r, y)
    ctx.arcTo(x + w, y, x + w, y + h, r)
    ctx.arcTo(x + w, y + h, x, y + h, r)
    ctx.arcTo(x, y + h, x, y, r)
    ctx.arcTo(x, y, x + w, y, r)
    ctx.closePath()
  }

  function distSeg(px, py, x1, y1, x2, y2) {
    const dx = x2 - x1, dy = y2 - y1
    const len = dx * dx + dy * dy
    let t = len ? ((px - x1) * dx + (py - y1) * dy) / len : 0
    t = Math.max(0, Math.min(1, t))
    return Math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))
  }

  global.Kanpan = { Chart, DEFS, PALETTE, mixHex, roundRect, setPalette, fmtNum, fmtVol, fmtFull, tzOffsetMin, sma, ema, boll, macd, rsi, kdj, stochRsi, atr, candleWidths, flingAt }
})(window)
