/* 看盘 · 外壳
 * 只有四件事：品种、周期、K 线、指标。别的都不做。 */
(function () {
  'use strict'

  const D = window.KANPAN_DATA
  const K = window.Kanpan
  const $ = (id) => document.getElementById(id)

  // ------------------------------------------------------------ 数据索引
  const ALL_PERIODS = [
    ['1m', '1 分钟'], ['3m', '3 分钟'], ['5m', '5 分钟'], ['15m', '15 分钟'], ['30m', '30 分钟'],
    ['1h', '1 小时'], ['2h', '2 小时'], ['4h', '4 小时'], ['6h', '6 小时'], ['12h', '12 小时'],
    ['1d', '1 天'], ['3d', '3 天'], ['1w', '1 周'], ['1M', '1 月'],
  ]
  const QUICK = ['1m', '5m', '15m', '1h', '4h', '1d']

  // ------------------------------------------------------------ 机型
  // 覆盖真机上的四个极端：最窄最矮的 SE、最窄最高的 mini、最常见的 393、
  // 最大的 Pro Max，外加一台平板。屏幕里的排布按容器宽度自己收放，
  // 这张表只负责给出机身尺寸、圆角和安全区。
  // 机型按「点」的尺寸排，15 / 16 / 17 三代整条线都在里面。
  // 同尺寸的机型合成一条：屏幕一样大，布局就一样。
  const DEVICES = [
    { id: 'se',   name: 'SE 3',            w: 375, h: 667,  r: 22, top: 20, bot: 0,  cut: 'none' },
    { id: 'mini', name: '13 mini · 16e',   w: 375, h: 812,  r: 40, top: 50, bot: 34, cut: 'notch' },
    { id: 'std',  name: '15 · 15 Pro · 16', w: 393, h: 852, r: 47, top: 59, bot: 34, cut: 'island' },
    { id: 'pro',  name: '16 Pro · 17 · 17 Pro', w: 402, h: 874, r: 50, top: 62, bot: 34, cut: 'island' },
    { id: 'air',  name: 'Air',             w: 420, h: 912,  r: 52, top: 62, bot: 34, cut: 'island' },
    { id: 'plus', name: '15 Plus · 16 Plus', w: 430, h: 932, r: 50, top: 59, bot: 34, cut: 'island' },
    { id: 'max',  name: '16 · 17 Pro Max', w: 440, h: 956,  r: 52, top: 62, bot: 34, cut: 'island' },
    { id: 'ipad', name: 'iPad mini',       w: 744, h: 1133, r: 20, top: 24, bot: 21, cut: 'none' },
  ]

  // ------------------------------------------------------------ 风格
  // 十一套 K 线视觉方案，表在 styles.js。配色只有靛这一套（浅深两版），
  // 风格换的只是 K 线本身和它周围的距离。几何给 canvas，颜色一份给 canvas、
  // 一份展开成 CSS 令牌盖在根节点上——所以配色管的是整个 app，不只是图。
  const STYLES = window.KanpanStyles
  const PACK = window.KanpanPalette   // 配色只有一套：靛。浅色一版、深色一版。

  const have = new Map()   // symbol -> Set(interval)
  for (const key of Object.keys(D.series)) {
    if (key.startsWith('OI|')) continue
    const [sym, iv] = key.split('|')
    if (!have.has(sym)) have.set(sym, new Set())
    have.get(sym).add(iv)
  }
  const catalogBySym = new Map(D.catalog.map((r) => [r[0], r]))

  const bars = (sym, iv) => D.series[sym + '|' + iv] || null
  function oiOf(sym, iv) {
    const fine = iv === '1m' || iv === '5m'
    return (fine ? D.series['OI|' + sym + '|5m'] : null) || D.series['OI|' + sym + '|1h'] || null
  }

  // ------------------------------------------------------------ 存档
  const SAVE = 'kanpan.v3'   // 换默认值就换钥匙，不然老存档会把新默认盖掉
  function load() {
    try { return JSON.parse(localStorage.getItem(SAVE) || '{}') } catch (e) { return {} }
  }
  function save() {
    try {
      localStorage.setItem(SAVE, JSON.stringify({
        symbol: S.symbol, interval: S.interval, watch: S.watch,
        overlays: chart.overlays, subs: chart.subs, params: chart.params,
        price: chart.price.mode, magnet: chart.magnet, tz: chart.tz,
        redUp: S.redUp, draws: S.draws, theme: S.theme, device: S.device, style: S.style,
      }))
    } catch (e) { /* 无痕模式下写不进去，不影响用 */ }
  }

  const saved = load()
  const S = {
    symbol: have.has(saved.symbol) ? saved.symbol : 'BTCUSDT',
    interval: '1h',
    watch: Array.isArray(saved.watch) ? saved.watch : [...have.keys()],
    redUp: !!saved.redUp,
    draws: saved.draws && typeof saved.draws === 'object' ? saved.draws : {},
    demo: false,
    theme: ['auto', 'light', 'dark'].includes(saved.theme) ? saved.theme : 'auto',
    device: DEVICES.some((d) => d.id === saved.device) ? saved.device : 'std',
    style: STYLES.some((x) => x.id === saved.style) ? saved.style : 'stout',
    land: false,
  }
  if (saved.interval && have.get(S.symbol) && have.get(S.symbol).has(saved.interval)) S.interval = saved.interval
  if (!have.get(S.symbol).has(S.interval)) S.interval = [...have.get(S.symbol)][0]

  // ------------------------------------------------------------ 图
  const chart = new K.Chart($('plot'), {
    onCross: renderReadout,
    onView: () => { syncJump(); },
    onDrawChange: () => { stashDraws(); syncDrawBar() },
    onTap: () => syncDrawBar(),
  })
  if (Array.isArray(saved.overlays)) chart.overlays = saved.overlays.filter((k) => K.DEFS[k])
  if (Array.isArray(saved.subs)) chart.subs = saved.subs.filter((k) => K.DEFS[k])
  if (saved.params) for (const k in saved.params) if (chart.params[k]) chart.params[k] = saved.params[k]
  if (saved.price) chart.price.mode = saved.price
  if (typeof saved.magnet === 'boolean') chart.magnet = saved.magnet
  if (saved.tz) chart.tz = saved.tz

  function drawKey() { return S.symbol + '|' + S.interval }
  function stashDraws() { S.draws[drawKey()] = chart.draws; save() }

  function applyColors() {
    const T = pack()
    const up = S.redUp ? T.red : T.green
    const dn = S.redUp ? T.green : T.red
    chart.opt.theme.up = up
    chart.opt.theme.down = dn
    chart.opt.theme.volUp = up + '66'
    chart.opt.theme.volDn = dn + '66'
    const s = $('screen').style
    s.setProperty('--up', up)
    s.setProperty('--down', dn)
    chart.dirty = true
  }


  // ============================================================ 机身与深浅
  //
  // 宿主（claude.ai）会在根元素上盖一个 data-theme 表示看的人选了什么。
  // 「跟随系统」要把这块牌子原样还回去，所以开场先记下它是什么。
  const HOST_THEME = document.documentElement.getAttribute('data-theme')
  const DARKQ = window.matchMedia('(prefers-color-scheme: dark)')
  const SMALLQ = window.matchMedia('(max-width: 560px)')

  function resolved() {
    if (S.theme !== 'auto') return S.theme
    if (HOST_THEME === 'dark' || HOST_THEME === 'light') return HOST_THEME
    return DARKQ.matches ? 'dark' : 'light'
  }

  const styleOf = () => STYLES.find((x) => x.id === S.style) || STYLES[0]
  const pack = () => (resolved() === 'dark' ? PACK.D : PACK.L)

  function applyTheme() {
    const root = document.documentElement
    if (S.theme === 'auto') {
      if (HOST_THEME) root.setAttribute('data-theme', HOST_THEME)
      else root.removeAttribute('data-theme')
    } else {
      root.setAttribute('data-theme', S.theme)
    }
    const st = styleOf()
    const T = pack()
    for (const k in T.css) root.style.setProperty(k, T.css[k])
    Object.assign(chart.opt.style, st.geom)     // 形态、体积、影线、上下左右
    Object.assign(chart.opt.theme, T.chart)
    K.setPalette(T.palette)
    applyColors()          // 涨跌配色压在主题之上
    renderStage()
    chart.resize()
    chart.dirty = true
  }

  function setStyle(id) {
    S.style = id
    applyTheme()
    chart.applySpacing()   // 左右间距是方案的一部分，换方案就按新的密度重排
    save()
    if ($('shStyle').classList.contains('show')) renderStyleSheet()
    if ($('shSettings').classList.contains('show')) renderSettings()
  }
  DARKQ.addEventListener('change', () => { if (S.theme === 'auto') applyTheme() })

  const device = () => DEVICES.find((d) => d.id === S.device) || DEVICES[2]

  function applyFrame() {
    const d = device()
    const st = document.documentElement.style
    const land = S.land
    st.setProperty('--dw', (land ? d.h : d.w) + 'px')
    st.setProperty('--dh', (land ? d.w : d.h) + 'px')
    st.setProperty('--dr', d.r + 'px')
    st.setProperty('--dtop', (land ? 0 : d.top) + 'px')
    st.setProperty('--dbot', (land ? (d.bot ? 21 : 0) : d.bot) + 'px')
    st.setProperty('--dside', (land && d.cut !== 'none' ? 44 : 0) + 'px')
    $('statusbar').dataset.cut = d.cut
    $('homebar').classList.toggle('off', !d.bot)
    fitFrame()
    requestAnimationFrame(() => { chart.resize(); chart.dirty = true })
  }

  // 机身按真实点数排版，再整体缩放塞进窗口——这样 440 宽的 Pro Max
  // 在笔记本上也是完整一台，而不是被裁掉一截。
  function fitFrame() {
    const st = document.documentElement.style
    if (document.body.classList.contains('live')) { st.setProperty('--fit', '1'); return }
    const d = device()
    const w = S.land ? d.h : d.w
    const h = S.land ? d.w : d.h
    const bar = document.querySelector('.bar')
    const cap = document.querySelector('.caption')
    const chrome = (bar ? bar.offsetHeight : 0) + (cap ? cap.offsetHeight : 0) + 76
    const availH = Math.max(240, window.innerHeight - chrome)
    const availW = Math.max(240, window.innerWidth - 40)
    st.setProperty('--fit', Math.min(1, availH / h, availW / w).toFixed(4))
  }

  function setDevice(id) {
    S.device = id
    applyFrame()
    renderStage()
    save()
  }

  function setTheme(mode) {
    S.theme = mode
    applyTheme()
    save()
    if ($('shStyle').classList.contains('show')) renderStyleSheet()
    if ($('shSettings').classList.contains('show')) renderSettings()
  }

  // 风格缩略：拿同一串价格，按这一版的形态、体积、影线、间距真画一遍。
  // 配色不属于风格，所以缩略图和主图用的是同一套靛。
  const THUMB = [
    [52, 56, 49, 55], [55, 60, 54, 59], [59, 61, 53, 54], [54, 58, 50, 51],
    [51, 53, 44, 46], [46, 50, 45, 49], [49, 57, 48, 56], [56, 62, 55, 61],
    [61, 63, 58, 59], [59, 60, 52, 53], [53, 57, 52, 56], [56, 64, 55, 63],
  ]
  function styleThumb(st) {
    const G = st.geom, T = pack()
    const c = document.createElement('canvas')
    c.className = 'sc-k'
    const dpr = Math.min(3, window.devicePixelRatio || 1)
    const W = 230, H = 56
    c.width = W * dpr; c.height = H * dpr
    c.style.width = '100%'; c.style.height = H + 'px'
    const g = c.getContext('2d')
    g.scale(dpr, dpr)
    g.fillStyle = T.chart.bg
    g.fillRect(0, 0, W, H)
    // 网格按这一版的规矩：横线 / 右端刻度 / 不画
    const gm = G.grid
    if (gm !== 'none') {
      g.strokeStyle = T.chart.grid; g.lineWidth = 1
      for (let i = 1; i <= 3; i++) {
        const y = Math.round(H * i / 4) + 0.5
        const x0 = gm === 'tick' ? W - 14 : 0
        g.beginPath(); g.moveTo(x0, y); g.lineTo(W, y); g.stroke()
      }
      if (gm === 'both') {
        for (let i = 1; i <= 3; i++) {
          const x = Math.round(W * i / 4) + 0.5
          g.beginPath(); g.moveTo(x, 0); g.lineTo(x, H); g.stroke()
        }
      }
    }
    // 上下留白和左右间距都照这一版；间距小的自然塞进更多根
    const step = Math.max(3, Math.min(W / 6, G.spacing * 2.2))
    const cnt = Math.max(4, Math.floor((W - 6) / step))
    const bar = (i) => THUMB[i % THUMB.length]   // 间距小的版本就多铺几根，缩略图始终铺满
    let lo = Infinity, hi = -Infinity
    for (let i = 0; i < cnt; i++) { const b = bar(i); if (b[2] < lo) lo = b[2]; if (b[1] > hi) hi = b[1] }
    const padv = (hi - lo) * G.pad
    lo -= padv; hi += padv
    const yOf = (v) => H - 4 - ((v - lo) / (hi - lo)) * (H - 8)
    const bodyW = Math.max(1.2, step * G.bodyR)
    const wickW = Math.max(0.6, G.wick)
    const left = (W - cnt * step) / 2 + step / 2
    g.lineCap = G.wickCap === 'round' ? 'round' : 'butt'
    for (let i = 0; i < cnt; i++) {
      const [o, h, l, cl] = bar(i)
      const up = cl >= o
      const col = up ? T.green : T.red
      const x = left + i * step
      const wc = G.wickTint < 1 ? K.mixHex(T.chart.bg, col, G.wickTint) : col
      g.strokeStyle = wc; g.lineWidth = wickW
      g.beginPath(); g.moveTo(x, yOf(h)); g.lineTo(x, yOf(l)); g.stroke()
      const top = Math.min(yOf(o), yOf(cl))
      const bh = Math.max(G.minBody, Math.abs(yOf(cl) - yOf(o)))
      const xb = x - bodyW / 2
      const r = Math.min(G.radius, bodyW / 2, bh / 2)
      const hollow = G.shape === 'outline' || (G.shape === 'hollowUp' && up)
      g.beginPath()
      if (r > 0) K.roundRect(g, xb, top, bodyW, bh, r); else g.rect(xb, top, bodyW, bh)
      if (hollow && bodyW > 2.4) {
        g.fillStyle = T.chart.bg; g.fill()
        g.strokeStyle = col; g.lineWidth = 1; g.stroke()
      } else {
        g.fillStyle = col; g.fill()
      }
    }
    g.lineCap = 'butt'
    // 最新价线：虚实也是方案的一部分
    g.strokeStyle = T.chart.amber; g.lineWidth = 1
    g.setLineDash(G.lastDash ? [3, 3] : [])
    const yl = Math.round(yOf(bar(cnt - 1)[3])) + 0.5
    g.beginPath(); g.moveTo(0, yl); g.lineTo(W, yl); g.stroke()
    g.setLineDash([])
    return c
  }

  // 风格挑选：每一版给出名字、一句话、赌的是什么，外加一张按这版真画的小图。
  function styleGrid() {
    const wrap = document.createElement('div')
    wrap.className = 'stylebox'
    const lab = document.createElement('div')
    lab.className = 'name'
    lab.textContent = '风格'
    wrap.appendChild(lab)
    const grid = document.createElement('div')
    grid.className = 'styles'
    for (const st of STYLES) {
      const b = document.createElement('button')
      b.className = 'stylecard' + (st.id === S.style ? ' on' : '')
      b.innerHTML =
        '<div class="sc-h"><b></b><i></i></div>' +
        '<div class="sc-b"></div>'
      b.querySelector('b').textContent = st.name
      b.querySelector('i').textContent = st.one
      b.querySelector('.sc-b').textContent = st.bet
      b.appendChild(styleThumb(st))
      b.onclick = () => setStyle(st.id)
      grid.appendChild(b)
    }
    wrap.appendChild(grid)
    return wrap
  }

  // 风格面板：卡片 + 一条浅深开关，手机上从底栏「风格」进来。
  function renderStyleSheet() {
    const box = $('styleBody')
    box.innerHTML = ''
    box.appendChild(styleGrid())
    const row = document.createElement('div')
    row.className = 'row'
    row.innerHTML = '<div class="name">外观</div>'
    const seg = document.createElement('div')
    seg.className = 'seg'
    for (const [text, val] of [['跟随系统', 'auto'], ['浅色', 'light'], ['深色', 'dark']]) {
      const b = document.createElement('button')
      b.textContent = text
      if (val === S.theme) b.className = 'on'
      b.onclick = () => setTheme(val)
      seg.appendChild(b)
    }
    row.appendChild(seg)
    box.appendChild(row)
    const note = document.createElement('p')
    note.className = 'note'
    note.innerHTML = '每一套换的都是 <b>K 线本身</b>：实体占几成、影线多粗、端头平还是圆、' +
      '是否空心或只描边，连同价格上下留白、根与根的间距、右轴宽度、副图和时间轴高度一起换。' +
      '图表类型始终只有一种：K 线。'
    box.appendChild(note)
  }

  function setLand(v) {
    S.land = v
    $('screen').classList.toggle('land', v)
    applyFrame()
  }

  // ------------------------------------------------------------ 台面按钮
  function renderStage() {
    const ds = $('devset')
    const ts = $('themeset')
    const ss = $('styleset')
    ds.querySelectorAll('.chip').forEach((b) => b.remove())
    ts.querySelectorAll('.chip').forEach((b) => b.remove())
    ss.querySelectorAll('.chip').forEach((b) => b.remove())
    for (const st of STYLES) {
      const b = document.createElement('button')
      b.className = 'chip' + (st.id === S.style ? ' on' : '')
      b.title = st.bet
      b.innerHTML = '<span></span><span class="dim"></span>'
      b.firstChild.textContent = st.name
      b.lastChild.textContent = st.one
      b.onclick = () => setStyle(st.id)
      ss.appendChild(b)
    }
    for (const d of DEVICES) {
      const b = document.createElement('button')
      b.className = 'chip' + (d.id === S.device ? ' on' : '')
      b.innerHTML = '<span></span><span class="dim">' + d.w + '×' + d.h + '</span>'
      b.firstChild.textContent = d.name
      b.onclick = () => setDevice(d.id)
      ds.appendChild(b)
    }
    for (const [label, mode] of [['跟随系统', 'auto'], ['浅色', 'light'], ['深色', 'dark']]) {
      const b = document.createElement('button')
      b.className = 'chip' + (mode === S.theme ? ' on' : '')
      b.textContent = label
      b.onclick = () => setTheme(mode)
      ts.appendChild(b)
    }
  }

  // ------------------------------------------------------------ 真机 / 台面
  function syncLive() {
    const live = SMALLQ.matches
    document.body.classList.toggle('live', live)
    if (live) {
      // 真机上由手机自己决定横竖，按钮不再是开关
      setLand(window.innerWidth > window.innerHeight)
    } else {
      fitFrame()
      requestAnimationFrame(() => { chart.resize(); chart.dirty = true })
    }
  }
  SMALLQ.addEventListener('change', syncLive)
  window.addEventListener('resize', () => { syncLive(); fitFrame() })
  window.addEventListener('orientationchange', () => setTimeout(syncLive, 120))

  // 状态栏上的时间用真的，走一分钟动一下
  function tickClock() {
    const now = new Date()
    $('clock').textContent = now.getHours() + ':' + String(now.getMinutes()).padStart(2, '0')
  }
  tickClock()
  setInterval(tickClock, 20000)

  function loadSeries(keepSpacing) {
    const b = bars(S.symbol, S.interval)
    const meta = { key: drawKey(), p: b.p, symbol: S.symbol, interval: S.interval }
    if (keepSpacing) chart.switchInterval(b, oiOf(S.symbol, S.interval), meta)
    else chart.setSeries(b, oiOf(S.symbol, S.interval), meta)
    chart.draws = S.draws[drawKey()] || []
    chart.selected = null
    chart.dirty = true
    renderTop()
    renderPeriods()
    syncJump()
  }

  // ------------------------------------------------------------ 顶栏
  function renderTop() {
    const q = D.quote[S.symbol]
    const b = chart.bars
    const last = b.c[b.c.length - 1]
    $('symName').textContent = S.symbol
    $('last').textContent = K.fmtNum(last, b.p)
    const pct = q ? q[1] : 0
    const el = $('chg')
    el.textContent = (pct >= 0 ? '+' : '') + pct.toFixed(2) + '%'
    el.className = 'chg ' + (pct >= 0 ? 'up' : 'down')
    $('last').className = 'last ' + (pct >= 0 ? 'up' : 'down')
    // 24 小时的高低用手上最细的那一档现算，没有就留空
    const fine = ['1m', '5m', '15m', '1h'].find((iv) => have.get(S.symbol).has(iv))
    const fb = fine ? bars(S.symbol, fine) : null
    if (fb) {
      const n = Math.min(fb.c.length, Math.ceil(86400e3 / fb.step))
      let hi = -Infinity, lo = Infinity
      for (let i = fb.c.length - n; i < fb.c.length; i++) { if (fb.h[i] > hi) hi = fb.h[i]; if (fb.l[i] < lo) lo = fb.l[i] }
      $('s24h').textContent = K.fmtNum(hi, fb.p)
      $('s24l').textContent = K.fmtNum(lo, fb.p)
    } else { $('s24h').textContent = '—'; $('s24l').textContent = '—' }
    $('s24v').textContent = q ? K.fmtVol(q[2]) : '—'
    $('btnStar').classList.toggle('on', S.watch.includes(S.symbol))
  }

  // ------------------------------------------------------------ 周期
  function renderPeriods() {
    const box = $('pscroll')
    box.innerHTML = ''
    const set = have.get(S.symbol)
    const list = QUICK.filter((iv) => set.has(iv))
    if (!list.includes(S.interval)) list.unshift(S.interval)
    for (const iv of list) {
      const b = document.createElement('button')
      b.className = 'pchip' + (iv === S.interval ? ' on' : '')
      b.textContent = label(iv)
      b.onclick = () => pickPeriod(iv)
      box.appendChild(b)
    }
  }
  function label(iv) {
    const found = ALL_PERIODS.find((p) => p[0] === iv)
    return found ? found[0] : iv
  }
  function pickPeriod(iv) {
    if (!have.get(S.symbol).has(iv)) {
      toast('原型只内嵌了 ' + [...have.get(S.symbol)].join(' / ') + ' 的数据')
      return
    }
    if (iv === S.interval) return
    S.interval = iv
    loadSeries(true)
    save()
    closeAll()
    hint('根宽没变，看见的时间跨度变了')
  }

  function renderPeriodSheet() {
    const box = $('perBody')
    box.innerHTML = ''
    const set = have.get(S.symbol)
    for (const [iv, name] of ALL_PERIODS) {
      const row = document.createElement('div')
      row.className = 'row'
      const ok = set.has(iv)
      row.innerHTML = '<div><div class="name">' + name + '</div><div class="meta">' + iv + (ok ? '' : ' · 原型未内嵌') + '</div></div>'
      row.style.opacity = ok ? '1' : '.42'
      if (iv === S.interval) { row.querySelector('.name').style.color = 'var(--amber)' }
      row.onclick = () => pickPeriod(iv)
      box.appendChild(row)
    }
    const note = document.createElement('p')
    note.className = 'note'
    note.innerHTML = '真正的 app 里这 14 档都在。<b>原型只带了 6 档的真实数据</b>，其余留白而不是编一段假行情出来。'
    box.appendChild(note)
  }

  // ------------------------------------------------------------ 指标
  function renderIndicators() {
    const box = $('indBody')
    box.innerHTML = ''
    section('主图叠加', ['MA', 'EMA', 'BOLL'], chart.overlays)
    section('副图', ['VOL', 'MACD', 'RSI', 'KDJ', 'SRSI', 'ATR', 'OI'], chart.subs)
    const note = document.createElement('p')
    note.className = 'note'
    note.innerHTML = '副图按打开的先后从上往下排，最多同时开三个还看得清。' +
      '<b>持仓量</b>用的是币安 openInterestHist，交易所只保留最近 30 天、最细 5 分钟——超出这个范围原型会直说没有，不画假线。'
    box.appendChild(note)

    function section(title, keys, live) {
      const t = document.createElement('div')
      t.className = 'groupt'
      t.textContent = title
      box.appendChild(t)
      for (const key of keys) {
        const def = K.DEFS[key]
        const on = live.includes(key)
        const row = document.createElement('div')
        row.className = 'row'
        const left = document.createElement('div')
        left.style.flex = '1'
        left.innerHTML = '<div class="name">' +
          '<span class="swatch" style="background:' + swatch(key) + '"></span>' + def.name + '</div>' +
          '<div class="meta">' + hintFor(key) + '</div>'
        row.appendChild(left)
        const sw = document.createElement('button')
        sw.className = 'sw' + (on ? ' on' : '')
        sw.setAttribute('aria-pressed', on ? 'true' : 'false')
        sw.onclick = () => {
          const arr = def.where === 'main' ? chart.overlays : chart.subs
          const at = arr.indexOf(key)
          if (at >= 0) arr.splice(at, 1)
          else if (def.where === 'sub' && arr.length >= 3) { toast('副图最多同时开三个'); return }
          else arr.push(key)
          chart.cache.key = ''
          chart.dirty = true
          save()
          renderIndicators()
        }
        row.appendChild(sw)
        box.appendChild(row)
        if (on && def.params.length) {
          const p = document.createElement('div')
          p.className = 'row'
          p.style.paddingTop = '0'
          p.style.borderBottom = '0'
          const wrap = document.createElement('div')
          wrap.className = 'params'
          def.params.forEach((_, k) => wrap.appendChild(stepper(key, k, def.labels[k])))
          p.appendChild(wrap)
          box.appendChild(p)
        }
      }
    }
    function stepper(key, k, name) {
      const el = document.createElement('span')
      el.className = 'step'
      const dec = document.createElement('button'); dec.textContent = '−'
      const val = document.createElement('span')
      const inc = document.createElement('button'); inc.textContent = '+'
      const paint = () => { val.textContent = (name ? name + ' ' : '') + chart.params[key][k] }
      const bump = (d) => {
        const next = Math.max(1, Math.min(400, chart.params[key][k] + d))
        chart.params[key][k] = next
        paint(); chart.cache.key = ''; chart.dirty = true; save()
      }
      dec.onclick = () => bump(-1)
      inc.onclick = () => bump(1)
      paint()
      el.append(dec, val, inc)
      return el
    }
  }
  function swatch(key) {
    if (key === 'OI') return chart.opt.theme.oi
    if (key === 'BOLL') return chart.opt.theme.band
    return K.PALETTE[0]
  }
  function hintFor(key) {
    return {
      MA: '收盘价的简单均线', EMA: '指数加权，比 MA 跟得紧', BOLL: '中轨加减标准差',
      VOL: '成交量柱 + 均量线', MACD: '快慢均线的差与它的均线', RSI: '涨跌力量的比值',
      KDJ: '随机指标', SRSI: 'RSI 自己的随机指标，更灵敏', ATR: '真实波幅，拿来量止损距离',
      OI: '未平仓合约张数 · 币安只给近 30 天',
    }[key] || ''
  }

  // ------------------------------------------------------------ 设置
  function renderSettings() {
    const box = $('setBody')
    box.innerHTML = ''
    box.appendChild(segRow('外观', [['跟随系统', 'auto'], ['浅色', 'light'], ['深色', 'dark']], S.theme, setTheme))
    box.appendChild(segRow('涨跌配色', [['绿涨红跌', false], ['红涨绿跌', true]], S.redUp, (v) => {
      S.redUp = v; applyColors(); renderTop(); save(); renderSettings()
    }))
    box.appendChild(segRow('价格轴', [['常规', 'linear'], ['对数', 'log'], ['百分比', 'percent']], chart.price.mode, (v) => {
      chart.price.mode = v; chart.dirty = true; save(); renderSettings()
    }))
    box.appendChild(segRow('时区', [['本地', 'local'], ['UTC', 'utc'], ['交易所', 'exchange']], chart.tz, (v) => {
      chart.tz = v; chart.dirty = true; save(); renderSettings()
    }))
    box.appendChild(switchRow('十字线磁吸', '吸到最近一根 K 线上', chart.magnet, (v) => {
      chart.magnet = v; chart.dirty = true; save()
    }))
    box.appendChild(switchRow('演示实时跳动', '假的：只拿来看最新价那一下的手感', S.demo, (v) => {
      S.demo = v; demoTick(v)
    }))
    const note = document.createElement('p')
    note.className = 'note'
    note.innerHTML = '页面里的行情是 <b>2026-09-14 的币安合约真实快照</b>，不会自己更新。' +
      '真正的 app 走 WebSocket，最新价和右轴胶囊会一直跳。'
    box.appendChild(note)

    function segRow(title, opts, now, cb) {
      const row = document.createElement('div')
      row.className = 'row'
      row.innerHTML = '<div class="name">' + title + '</div>'
      const seg = document.createElement('div')
      seg.className = 'seg'
      for (const [text, val] of opts) {
        const b = document.createElement('button')
        b.textContent = text
        if (val === now) b.className = 'on'
        b.onclick = () => cb(val)
        seg.appendChild(b)
      }
      row.appendChild(seg)
      return row
    }
    function switchRow(title, sub, on, cb) {
      const row = document.createElement('div')
      row.className = 'row'
      row.innerHTML = '<div style="flex:1"><div class="name">' + title + '</div><div class="meta">' + sub + '</div></div>'
      const sw = document.createElement('button')
      sw.className = 'sw' + (on ? ' on' : '')
      sw.onclick = () => { const next = !sw.classList.contains('on'); sw.classList.toggle('on', next); cb(next) }
      row.appendChild(sw)
      return row
    }
  }

  let demoTimer = null
  function demoTick(on) {
    clearInterval(demoTimer)
    if (!on) { chart.dirty = true; return }
    demoTimer = setInterval(() => {
      const b = chart.bars
      const i = b.c.length - 1
      const scale = (b.h[i] - b.l[i]) || b.c[i] * 0.0004
      const next = Math.max(0, b.c[i] + (Math.random() - 0.5) * scale * 0.25)
      b.c[i] = Number(next.toFixed(b.p))
      if (b.c[i] > b.h[i]) b.h[i] = b.c[i]
      if (b.c[i] < b.l[i]) b.l[i] = b.c[i]
      chart.cache.key = ''
      chart.dirty = true
      $('last').textContent = K.fmtNum(b.c[i], b.p)
    }, 700)
  }

  // ------------------------------------------------------------ 品种
  function renderSymbols(q) {
    const box = $('symBody')
    box.innerHTML = ''
    const query = (q || '').trim().toUpperCase()
    const rows = D.catalog.filter((r) => !query || r[0].includes(query) || r[1].includes(query))
    $('symCount').textContent = D.catalog.length + ' 个永续合约'

    if (!query) {
      group('自选', S.watch.map((s) => catalogBySym.get(s)).filter(Boolean))
      group('原型带了数据的', [...have.keys()].filter((s) => !S.watch.includes(s)).map((s) => catalogBySym.get(s)).filter(Boolean))
      group('全部合约', rows.filter((r) => !have.has(r[0])).slice(0, 120), D.catalog.length - have.size - 120)
    } else {
      group('搜到 ' + rows.length + ' 个', rows.slice(0, 160), Math.max(0, rows.length - 160))
    }

    function group(title, list, more) {
      if (!list.length) return
      const t = document.createElement('div')
      t.className = 'groupt'
      t.textContent = title
      box.appendChild(t)
      for (const r of list) box.appendChild(symRow(r))
      if (more > 0) {
        const p = document.createElement('p')
        p.className = 'note'
        p.textContent = '还有 ' + more + ' 个，搜名字更快。'
        box.appendChild(p)
      }
    }
    function symRow(r) {
      const [sym, base, quoteAsset, p] = r
      const q = D.quote[sym]
      const row = document.createElement('div')
      row.className = 'row'
      const snap = have.has(sym)
      const left = document.createElement('div')
      left.style.flex = '1'
      left.innerHTML = '<div class="name">' + base + '<span style="color:var(--ink3);font-weight:400"> / ' + quoteAsset + '</span></div>' +
        '<div class="meta">' + (snap ? [...have.get(sym)].join(' · ') : '原型无快照') + '</div>'
      row.appendChild(left)
      const num = document.createElement('div')
      num.className = 'num'
      const pct = q ? q[1] : 0
      num.innerHTML = '<div>' + (q ? K.fmtNum(q[0], p) : '—') + '</div>' +
        '<div class="pct ' + (pct >= 0 ? 'up' : 'down') + '">' + (pct >= 0 ? '+' : '') + pct.toFixed(2) + '%</div>'
      row.appendChild(num)
      const star = document.createElement('button')
      star.className = 'star' + (S.watch.includes(sym) ? ' on' : '')
      star.innerHTML = '<svg width="15" height="15" viewBox="0 0 18 18" fill="' + (S.watch.includes(sym) ? 'currentColor' : 'none') + '" stroke="currentColor" stroke-width="1.5"><path d="M9 2.2l2 4.2 4.6.6-3.4 3.2.9 4.6L9 12.6 4.9 14.8l.9-4.6L2.4 7l4.6-.6z"/></svg>'
      star.onclick = (e) => { e.stopPropagation(); toggleWatch(sym); renderSymbols($('symQ').value) }
      row.appendChild(star)
      row.onclick = () => pickSymbol(sym)
      if (!snap) row.style.opacity = '.5'
      return row
    }
  }
  function toggleWatch(sym) {
    const at = S.watch.indexOf(sym)
    if (at >= 0) S.watch.splice(at, 1); else S.watch.push(sym)
    save()
    renderTop()
  }
  function pickSymbol(sym) {
    if (!have.has(sym)) { toast(sym + ' 没有内嵌快照，原型里只带了 ' + have.size + ' 个品种'); return }
    S.symbol = sym
    if (!have.get(sym).has(S.interval)) S.interval = have.get(sym).has('1h') ? '1h' : [...have.get(sym)][0]
    loadSeries(false)
    save()
    closePage()
  }

  // ------------------------------------------------------------ 十字线读数
  function renderReadout(info) {
    const el = $('readout')
    if (!info) { el.classList.remove('show'); return }
    const b = info.bar
    const p = chart.bars.p
    const up = b.c >= b.o
    const cls = up ? 'up' : 'down'
    el.innerHTML =
      '<div class="t">' + K.fmtFull(b.t, info.tz) + '</div>' +
      cell('开', K.fmtNum(b.o, p)) + cell('高', K.fmtNum(b.h, p)) +
      cell('低', K.fmtNum(b.l, p)) + cell('收', K.fmtNum(b.c, p), cls) +
      cell('涨跌', (b.chg >= 0 ? '+' : '') + b.chg.toFixed(2) + '%', b.chg >= 0 ? 'up' : 'down') +
      cell('振幅', b.amp.toFixed(2) + '%') +
      cell('量', K.fmtVol(b.v))
    el.classList.add('show')
    function cell(k, v, c) {
      return '<div class="cell"><span class="k">' + k + '</span><span class="v ' + (c || '') + '">' + v + '</span></div>'
    }
  }

  // ------------------------------------------------------------ 面板开合
  const sheets = ['shStyle', 'shIndicator', 'shPeriod', 'shSettings']
  function openSheet(id) {
    closeAll()
    if (id === 'shStyle') renderStyleSheet()
    if (id === 'shIndicator') renderIndicators()
    if (id === 'shPeriod') renderPeriodSheet()
    if (id === 'shSettings') renderSettings()
    $(id).classList.add('show')
    $('scrim').classList.add('show')
    syncTools()
  }
  function closeAll() {
    for (const id of sheets) $(id).classList.remove('show')
    $('scrim').classList.remove('show')
    syncTools()
  }
  function openPage() { renderSymbols(''); $('pgSymbol').classList.add('show') }
  function closePage() { $('pgSymbol').classList.remove('show') }

  function syncTools() {
    $('tStyle').classList.toggle('on', $('shStyle').classList.contains('show'))
    $('tIndicator').classList.toggle('on', $('shIndicator').classList.contains('show'))
    $('tSettings').classList.toggle('on', $('shSettings').classList.contains('show'))
    $('tDraw').classList.toggle('on', $('drawbar').classList.contains('show'))
  }

  // ------------------------------------------------------------ 画线
  function syncDrawBar() {
    $('dDel').disabled = !chart.selected
    for (const b of document.querySelectorAll('[data-draw]')) {
      b.classList.toggle('on', chart.drawMode === b.dataset.draw)
    }
  }
  for (const b of document.querySelectorAll('[data-draw]')) {
    b.onclick = () => {
      chart.drawMode = chart.drawMode === b.dataset.draw ? null : b.dataset.draw
      chart.pending = null
      chart.dirty = true
      syncDrawBar()
      if (chart.drawMode === 'trend') hint('点两下落两个端点')
      if (chart.drawMode === 'hline') hint('点一下放一条水平线')
    }
  }
  $('dDel').onclick = () => { chart.removeSelected(); syncDrawBar() }
  $('dDone').onclick = () => {
    chart.drawMode = null; chart.pending = null; chart.dirty = true
    $('drawbar').classList.remove('show')
    syncTools(); syncDrawBar()
  }

  // ------------------------------------------------------------ 提示
  let toastTimer = null
  function toast(text) {
    const el = $('toast')
    el.textContent = text
    el.classList.add('show')
    clearTimeout(toastTimer)
    toastTimer = setTimeout(() => el.classList.remove('show'), 2200)
  }
  let hintTimer = null
  function hint(text) {
    const el = $('hint')
    el.textContent = text
    el.classList.add('show')
    clearTimeout(hintTimer)
    hintTimer = setTimeout(() => el.classList.remove('show'), 1600)
  }

  function syncJump() {
    const b = chart.bars
    if (!b) return
    const lastT = b.t0 + (b.c.length - 1) * b.step
    $('jump').classList.toggle('show', chart.view.to < lastT)
  }

  // ------------------------------------------------------------ 接线
  $('symbtn').onclick = openPage
  $('btnSearch').onclick = () => { openPage(); setTimeout(() => $('symQ').focus(), 260) }
  $('symBack').onclick = closePage
  $('symClear').onclick = () => { $('symQ').value = ''; renderSymbols('') }
  $('symQ').oninput = (e) => renderSymbols(e.target.value)
  $('btnStar').onclick = () => { toggleWatch(S.symbol); toast(S.watch.includes(S.symbol) ? '已加入自选' : '已移出自选') }
  $('pmore').onclick = () => openSheet('shPeriod')
  $('tStyle').onclick = () => { $('shStyle').classList.contains('show') ? closeAll() : openSheet('shStyle') }
  $('tIndicator').onclick = () => { $('shIndicator').classList.contains('show') ? closeAll() : openSheet('shIndicator') }
  $('tSettings').onclick = () => { $('shSettings').classList.contains('show') ? closeAll() : openSheet('shSettings') }
  $('tDraw').onclick = () => {
    closeAll()
    const bar = $('drawbar')
    bar.classList.toggle('show')
    if (!bar.classList.contains('show')) { chart.drawMode = null; chart.pending = null; chart.dirty = true }
    syncTools(); syncDrawBar()
  }
  $('tLand').onclick = () => {
    if (document.body.classList.contains('live')) { toast('把手机横过来，图自己转'); return }
    setLand(!S.land)
  }
  $('scrim').onclick = closeAll
  $('jump').onclick = () => {
    const b = chart.bars
    const span = chart.view.to - chart.view.from
    const lastT = b.t0 + (b.c.length - 1) * b.step
    const to = lastT + span * 0.06
    chart.view = chart.clamp({ from: to - span, to })
    chart.dirty = true
    syncJump()
  }

  // ------------------------------------------------------------ 弹性滚动
  // iOS WebKit 的橡皮筋：手指按在任何地方往下一拖，整页跟着弹一下，
  // 上面还会露出一条底色。原生 app 没有这个动作，所以按住它。
  // 规矩：这一下如果落在一个真能滚的容器里（面板列表、周期条），放行；
  // 否则连默认行为一起吃掉。CSS 那边 overscroll-behavior: contain
  // 负责容器滚到头之后不把剩下的力传给页面。
  function scrollerFor(node, axis) {
    for (let el = node; el && el !== document.body; el = el.parentElement) {
      if (el.nodeType !== 1) continue
      const cs = getComputedStyle(el)
      if (axis === 'y') {
        if (/(auto|scroll)/.test(cs.overflowY) && el.scrollHeight - el.clientHeight > 1) return el
      } else if (/(auto|scroll)/.test(cs.overflowX) && el.scrollWidth - el.clientWidth > 1) return el
    }
    return null
  }
  const TG = { x: 0, y: 0, node: null }
  document.addEventListener('touchstart', (e) => {
    const t = e.touches[0]
    if (!t) return
    TG.x = t.clientX; TG.y = t.clientY; TG.node = e.target
    // 贴着顶或底起手时推进一个像素，免得这一帧的滚动被判给页面
    const sy = scrollerFor(e.target, 'y')
    if (sy) {
      if (sy.scrollTop <= 0) sy.scrollTop = 1
      else if (sy.scrollTop + sy.clientHeight >= sy.scrollHeight) sy.scrollTop = sy.scrollHeight - sy.clientHeight - 1
    }
  }, { passive: true })
  document.addEventListener('touchmove', (e) => {
    if (e.touches.length > 1) { e.preventDefault(); return }   // 双指：交给图自己处理，页面不缩放
    const t = e.touches[0]
    if (!t) return
    const axis = Math.abs(t.clientX - TG.x) > Math.abs(t.clientY - TG.y) ? 'x' : 'y'
    if (!scrollerFor(TG.node, axis)) e.preventDefault()
  }, { passive: false })
  // 双击放大也是网页手感，一并去掉
  document.addEventListener('gesturestart', (e) => e.preventDefault())
  const tap = { t: 0, x: 0, y: 0 }
  document.addEventListener('touchend', (e) => {
    const t = e.changedTouches[0]
    if (!t) return
    const now = Date.now()
    // 只有「同一个点上连着点两下」才拦，免得连点两个按钮时第二下丢掉
    if (now - tap.t < 320 && Math.abs(t.clientX - tap.x) < 24 && Math.abs(t.clientY - tap.y) < 24) e.preventDefault()
    tap.t = now; tap.x = t.clientX; tap.y = t.clientY
  }, { passive: false })

  // ------------------------------------------------------------ 起
  applyTheme()
  syncLive()
  applyFrame()
  loadSeries(false)
  setTimeout(() => hint('单指拖 · 双指缩放 · 长按出十字线'), 600)
})()
