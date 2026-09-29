/* Hkline Web · 外壳与图表页
 *
 * 交互原则（和手机端刻意不同）：
 *   · 鼠标悬停就是查看：十字线、图例、大单详情、术语解释都跟着指针走，不用先点
 *   · 右键是「在这里做事」：在这个价位建提醒 / 画水平线 / 记一笔
 *   · 键盘直达：打字就是搜品种，打数字就是换周期，Alt+字母选画线工具，⌘Z 撤销
 *   · 画线不是一个模式：左侧工具栏常驻，选了工具就在当前图上画，画完回到光标
 *   · 大屏同时看：一 / 二 / 四图布局，十字线跨图按时间同步
 */
(function (g) {
  'use strict'
  const $ = (s, r = document) => r.querySelector(s)
  const $$ = (s, r = document) => [...r.querySelectorAll(s)]
  const I = (n, c) => KPIcon.icon(n, c)
  const D = KPData, F = KPFmt
  const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))

  // ------------------------------------------------------------ 状态（本机保存）
  const KEY = 'hkline-web-v1'
  const saved = (() => { try { return JSON.parse(localStorage.getItem(KEY)) || {} } catch { return {} } })()
  const st = Object.assign({
    theme: 'light', skin: 'sage', updown: 'red-up', loggedIn: true, user: 'mdd',
    layout: '1', cells: [{ symbol: 'BTCUSDT', iv: '1h' }], active: 0,
    pinned: ['1m', '5m', '15m', '1h', '4h', '1d', '1w'],
    panel: 'watch', watchTab: 'crypto', watch: JSON.parse(JSON.stringify(D.DEFAULT_WATCH)),
    ind: { ma: true, ema: false, boll: false, vol: true, subs: ['macd', 'rsi'] }, params: null,
    flowOn: true, drawings: {}, alerts: [], notes: [], magnet: false, drawHidden: false, drawLocked: false,
    drawColor: '#2962FF', route: 'direct', learn: true, moveAlert: true, listing: true, meSection: 'account', alertScope: 'symbol',
  }, saved)
  st.stale = false
  function save() {
    const { stale, ...rest } = st
    localStorage.setItem(KEY, JSON.stringify(rest))
  }
  function applyTheme() {
    document.documentElement.dataset.theme = st.theme
    document.documentElement.dataset.skin = st.skin || 'sage'
    document.documentElement.dataset.updown = st.updown
    $('#hdrTheme').innerHTML = I(st.theme === 'dark' ? 'sun' : 'moon')
    cells.forEach(c => c.chart.readTheme())
    App.onTheme?.forEach(fn => fn())
  }

  // ------------------------------------------------------------ 小工具
  const sym = s => D.S.symbols.get(s)
  const pctText = p => p == null ? '—' : `${p >= 0 ? '+' : ''}${p.toFixed(2)}%`
  const cls = p => p == null ? '' : p >= 0 ? 'up' : 'down'
  function priceText(s, v = s?.price) { return v == null ? '—' : F.fmt(v, s?.dec ?? 2) }
  const clamp01 = v => Math.max(0, Math.min(1, isFinite(v) ? v : 0))
  function badge(s, size = '') {
    const b = s?.base || '?'
    const t = b.length > 3 ? b.slice(0, 3) : b
    return `<span class="badge ${size}" style="background:${s?.color || '#888'}" aria-hidden="true">${esc(t)}</span>`
  }
  function kindName(s) { return s?.kind === 'us' ? '美股永续' : s?.kind === 'com' ? '大宗永续' : '永续' }
  function hydrateIcons(root = document) { $$('[data-icon]', root).forEach(e => { const [n, c] = e.dataset.icon.split(':'); e.outerHTML = I(n, c || 'icon') }) }
  function countdown(ms) {
    if (ms == null) return '—'
    const s = Math.max(0, Math.floor(ms / 1000))
    return `${F.pad(Math.floor(s / 3600))}:${F.pad(Math.floor(s % 3600 / 60))}:${F.pad(s % 60)}`
  }
  function shTime(t, withDate = true) {
    const d = F.sh(t)
    const hm = `${F.pad(d.getUTCHours())}:${F.pad(d.getUTCMinutes())}`
    return withDate ? `${d.getUTCMonth() + 1}月${d.getUTCDate()}日 ${hm}` : hm
  }

  // ------------------------------------------------------------ 提示与术语
  const GLOSSARY = {
    资金费率: '多空双方每 8 小时互付一次的费用。为正时多头付给空头，说明合约价高于现货、做多的人多。',
    持仓量: '所有还没平掉的合约加起来值多少美元。价格涨、持仓量也涨，多半是新资金进场。',
    多空人数比: '币安上做多的账户数 ÷ 做空的账户数（5 分钟一档）。大于 1 是多头人多。',
    大户持仓比: '持仓最大的前 20% 账户里，多头仓位 ÷ 空头仓位。大于 1 是大户偏多。',
    主动买卖比: '最近 5 分钟主动买入量 ÷ 主动卖出量。大于 1 是买盘更急。',
    标记价: '用来算强平与盈亏的价格，取指数价加上资金费率的均值，比最新价平滑。',
    指数价: '几家现货交易所的成交价加权平均，是合约价格的锚。',
    基差: '标记价相对指数价高出多少。为正说明合约比现货贵、市场偏多。',
    下次结算: '距离下一次收付资金费还有多久。',
    标记价格: '交易所用来算盈亏和强平的价格，比最新成交价更平滑，不容易被插针。',
    跑赢大盘: '板块里今天涨幅超过比特币的品种有几只。',
    中位涨跌: '板块里所有品种涨跌幅排在正中间的那个数，不会被一两只暴涨暴跌的带偏。',
    主力订单流: '币安、OKX、Coinbase 现货三家挂单簿合在一起，只画超过门槛的大单。紫色是合约、青色是现货；线越粗单越大，线断开表示单子撤了或成交了。',
    胜率: '赚钱的回合占全部回合的比例。',
    盈亏比: '平均每笔赚的钱 ÷ 平均每笔亏的钱。',
    每笔期望: '平均每做一个回合，净赚（或净亏）多少。',
    费用占毛利: '手续费吃掉了多少毛利。超过三成就说明交易太频繁了。',
    净盈亏: '扣掉手续费和资金费之后的盈亏。',
    回合: '从开仓到仓位归零算一个回合，中间的加减仓都并进去。',
  }
  const tip = { el: null, timer: null, target: null }
  function showTip(target) {
    const t = $('#tooltip')
    let html = ''
    if (target.dataset.term) html = `<b>${esc(target.dataset.term)}</b>${esc(GLOSSARY[target.dataset.term] || '')}`
    else html = esc(target.dataset.tip) + (target.dataset.kbd ? target.dataset.kbd.split(' ').map(k => `<kbd>${esc(k)}</kbd>`).join('') : '')
    t.innerHTML = html
    t.style.maxWidth = target.dataset.term ? '280px' : '360px'
    const r = target.getBoundingClientRect()
    t.classList.add('show')
    const tw = t.offsetWidth, th = t.offsetHeight
    let x = r.left + r.width / 2 - tw / 2, y = r.bottom + 8
    const side = target.dataset.tipSide
    if (side === 'right') { x = r.right + 8; y = r.top + r.height / 2 - th / 2 }
    else if (side === 'left') { x = r.left - tw - 8; y = r.top + r.height / 2 - th / 2 }
    else if (y + th > innerHeight - 8) y = r.top - th - 8
    t.style.left = Math.max(8, Math.min(innerWidth - tw - 8, x)) + 'px'
    t.style.top = Math.max(8, y) + 'px'
  }
  function hideTip() { clearTimeout(tip.timer); tip.target = null; $('#tooltip').classList.remove('show') }
  document.addEventListener('mouseover', e => {
    const t = e.target.closest('[data-tip],[data-term]')
    if (t === tip.target) return
    hideTip()
    if (!t) return
    tip.target = t
    tip.timer = setTimeout(() => showTip(t), t.dataset.term ? 250 : 450)
  })
  document.addEventListener('focusin', e => { const t = e.target.closest('[data-tip]'); if (t && t.matches(':focus-visible')) { tip.target = t; showTip(t) } })
  document.addEventListener('focusout', hideTip)
  document.addEventListener('mousedown', hideTip)
  function term(k, label = k) { return `<span class="term" data-term="${k}" tabindex="0">${label}</span>` }

  function toast(title, sub, icon = 'check', ms = 3600) {
    const e = document.createElement('div')
    e.className = 'toast'
    e.innerHTML = `${I(icon)}<div class="tx"><b>${esc(title)}</b>${sub ? `<span>${esc(sub)}</span>` : ''}</div>`
    $('#toasts').appendChild(e)
    setTimeout(() => e.remove(), ms)
  }

  // ------------------------------------------------------------ 菜单与对话框
  let openMenuEl = null
  function closeMenu() { openMenuEl?.remove(); openMenuEl = null }
  function menu(items, x, y, opts = {}) {
    closeMenu()
    const m = document.createElement('div')
    m.className = 'menu'; m.setAttribute('role', 'menu')
    if (opts.width) m.style.minWidth = opts.width + 'px'
    m.innerHTML = items.map((it, k) => {
      if (it === '-') return '<div class="sep" role="separator"></div>'
      if (it.header) return `<div class="mh">${esc(it.header)}</div>`
      return `<button class="mi ${it.checked ? 'checked' : ''}" role="menuitem" data-k="${k}" ${it.disabled ? 'disabled style="opacity:.45;cursor:default"' : ''}>${it.icon ? I(it.icon) : it.check !== undefined ? I('check', 'icon check') : ''}<span class="label">${it.html || esc(it.label)}</span>${it.sc ? `<span class="sc">${esc(it.sc)}</span>` : ''}</button>`
    }).join('')
    document.body.appendChild(m)
    const w = m.offsetWidth, h = m.offsetHeight
    m.style.left = Math.min(x, innerWidth - w - 8) + 'px'
    m.style.top = (y + h > innerHeight - 8 ? Math.max(8, y - h) : y) + 'px'
    m.addEventListener('click', e => {
      const b = e.target.closest('.mi'); if (!b || b.disabled) return
      const it = items[+b.dataset.k]; closeMenu(); it.run?.()
    })
    m.addEventListener('keydown', e => {
      const list = $$('.mi:not([disabled])', m), i = list.indexOf(document.activeElement)
      if (e.key === 'ArrowDown') { e.preventDefault(); list[(i + 1) % list.length].focus() }
      if (e.key === 'ArrowUp') { e.preventDefault(); list[(i - 1 + list.length) % list.length].focus() }
      if (e.key === 'Escape') { e.stopPropagation(); closeMenu(); opts.returnFocus?.focus() }
    })
    openMenuEl = m
    if (opts.focus) $('.mi', m)?.focus()
    return m
  }
  document.addEventListener('mousedown', e => { if (openMenuEl && !openMenuEl.contains(e.target)) closeMenu() }, true)
  function menuFrom(btn, items, opts = {}) { const r = btn.getBoundingClientRect(); return menu(items, r.left, r.bottom + 4, { ...opts, returnFocus: btn }) }

  const dialogs = []
  function dialog(html, cls, { center = false, onClose, label } = {}) {
    closeMenu()
    const scrim = document.createElement('div')
    scrim.className = 'scrim' + (center ? ' center' : '')
    scrim.innerHTML = `<div class="dialog ${cls}" role="dialog" aria-modal="true" aria-label="${esc(label || '')}">${html}</div>`
    const prevFocus = document.activeElement
    document.body.appendChild(scrim)
    const dlg = scrim.firstElementChild
    const close = () => { scrim.remove(); dialogs.splice(dialogs.indexOf(api), 1); onClose?.(); prevFocus?.focus?.() }
    const api = { scrim, dlg, close }
    dialogs.push(api)
    scrim.addEventListener('mousedown', e => { if (e.target === scrim) close() })
    $$('[data-close]', dlg).forEach(b => b.addEventListener('click', close))
    dlg.addEventListener('keydown', e => {
      if (e.key === 'Escape') { e.stopPropagation(); close() }
      if (e.key === 'Tab') { // 焦点留在对话框里
        const f = $$('button:not([disabled]),input,textarea,[tabindex="0"]', dlg).filter(x => x.offsetParent)
        if (!f.length) return
        if (e.shiftKey && document.activeElement === f[0]) { e.preventDefault(); f[f.length - 1].focus() }
        else if (!e.shiftKey && document.activeElement === f[f.length - 1]) { e.preventDefault(); f[0].focus() }
      }
    })
    return api
  }
  function head(title, extra = '') { return `<div class="dialog-head"><h2>${title}</h2>${extra}<button class="ibtn" data-close aria-label="关闭" data-tip="关闭" data-kbd="Esc">${I('close')}</button></div>` }

  // ------------------------------------------------------------ 页面切换
  const PAGES = ['chart', 'sectors', 'review', 'me', 'spec']
  function go(page, push = true) {
    if (!PAGES.includes(page)) page = 'chart'
    st.page = page
    PAGES.forEach(p => $('#page-' + p).classList.toggle('show', p === page))
    $$('.nav a').forEach(a => a.toggleAttribute('aria-current', a.dataset.page === page) || a.dataset.page === page && a.setAttribute('aria-current', 'page'))
    $$('.nav a').forEach(a => { if (a.dataset.page === page) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current') })
    if (push && location.hash !== '#' + page) history.replaceState(null, '', '#' + page)
    App.pageShown?.[page]?.()
    if (page === 'chart') cells.forEach(c => c.chart.resize())
    hideTip()
  }
  addEventListener('hashchange', () => go(location.hash.slice(1), false))

  // ------------------------------------------------------------ 图表格子
  const cells = []
  const RANGES = [['1天', '1m', 1], ['5天', '5m', 5], ['1月', '30m', 30], ['3月', '2h', 91], ['6月', '4h', 182], ['今年', '1d', 'ytd'], ['1年', '1d', 365], ['全部', '1w', 'all']]
  function metaFor(c) {
    const s = sym(c.symbol)
    return { symbol: c.symbol, iv: D.IV_MS[c.iv], title: c.symbol, sub: `· ${D.IV_LABEL[c.iv]} · 币安${kindName(s)}`, dec: s?.dec ?? 2, badge: badge(s), wallParam: '合约 ≥ 5M · 现货 ≥ 1M' }
  }
  function buildCells() {
    const n = { '1': 1, '2': 2, '2v': 2, '4': 4 }[st.layout]
    const fill = ['ETHUSDT', 'SOLUSDT', 'XAUUSDT']
    while (st.cells.length < n) st.cells.push({ symbol: fill[st.cells.length - 1] || 'BTCUSDT', iv: st.cells[0].iv })
    st.active = Math.min(st.active, n - 1)
    const area = $('#chartArea'); area.dataset.layout = st.layout
    while (cells.length > n) { const c = cells.pop(); c.chart.destroy(); c.el.remove() }
    for (let i = cells.length; i < n; i++) cells.push(makeCell(i))
    cells.forEach((c, i) => c.el.classList.toggle('active', i === st.active))
    save(); refreshStreams()
  }
  function makeCell(i) {
    const el = document.createElement('div')
    el.className = 'card chart-cell'
    el.innerHTML = `<div class="canvas-host"></div>
      <div class="cell-foot">
        ${RANGES.map(([l], k) => `<button data-range="${k}" data-tip="${l}：切到 ${D.IV_LABEL[RANGES[k][1]]}，显示最近${l === '全部' ? '全部历史' : l === '今年' ? '今年以来' : l}">${l}</button>`).join('')}
        <div class="foot-right">
          <span class="clock num" data-tip="时间统一按上海时间显示，日线在北京时间 8:00 换日"></span>
          <span class="tb-sep"></span>
          <button data-act="log" data-tip="对数坐标" aria-pressed="false">对数</button>
          <button data-act="auto" data-tip="价格轴自动缩放（双击价格轴也可以恢复）" aria-pressed="true">自动</button>
        </div>
      </div>`
    $('#chartArea').appendChild(el)
    const host = $('.canvas-host', el)
    const cell = { el, host, idx: i, bars: [], loadToken: 0, more: false, noMore: false }
    cell.chart = new TVChart(host, {
      onActivate: () => setActive(cell.idx),
      onNeedMore: () => loadMore(cell),
      onCrosshairMove: t => cells.forEach(o => o !== cell && o.chart.syncCrosshair(t)),
      onContextMenu: info => chartContextMenu(cell, info),
      onLegendAction: (id, act, btn) => legendAction(cell, id, act, btn),
      onWallHover: (w, x, y) => wallCard(cell, w, x, y),
      onToolDone: (d, keep) => { if (!keep) selectTool(null) ; else selectTool(null) },
      onSelectDrawing: d => showDrawProps(d, cell),
      onDrawingsChanged: () => drawingsChanged(cell),
      drawColor: () => st.drawColor,
      onAutoChange: on => { const b = $('[data-act="auto"]', el); b && b.setAttribute('aria-pressed', on) },
    })
    cell.chart.ind = JSON.parse(JSON.stringify(st.ind))
    if (st.params) Object.assign(cell.chart.params, JSON.parse(JSON.stringify(st.params)))
    cell.chart.setMagnet(st.magnet)
    cell.chart.drawingsHidden = st.drawHidden
    el.addEventListener('click', e => {
      const r = e.target.closest('[data-range]'); if (r) return applyRange(cell, +r.dataset.range)
      const a = e.target.closest('[data-act]')?.dataset.act
      if (a === 'log') { cell.chart.setLog(!cell.chart.log); e.target.setAttribute('aria-pressed', cell.chart.log) }
      if (a === 'auto') cell.chart.setAuto(!cell.chart.auto)
    })
    loadCell(cell)
    return cell
  }
  function cfg(cell) { return cell && st.cells[cell.idx] }
  async function loadCell(cell, then) {
    const c = cfg(cell), token = ++cell.loadToken
    cell.noMore = false
    const { bars, live } = await D.klines(c.symbol, c.iv)
    if (token !== cell.loadToken) return
    cell.bars = bars; cell.live = live
    cell.chart.setData(bars, metaFor(c))
    cell.chart.setDrawings(drawingsFor(c.symbol))
    cell.chart.setAlerts(st.alerts.filter(a => a.symbol === c.symbol && a.kind === 'price'))
    cell.chart.setWalls(st.flowOn ? D.demoWalls(c.symbol, bars, c.iv) : null)
    cell.chart.setStale(st.stale)
    then?.()
    if (cell.idx === st.active) { renderToolbar(); renderPanel() }
  }
  async function loadMore(cell) {
    if (cell.more || cell.noMore || !cell.bars.length) return
    cell.more = true; cell.chart.loadingMore = true
    const c = cfg(cell)
    const { bars } = await D.klines(c.symbol, c.iv, cell.chart.bars[0].t)
    cell.more = false; cell.chart.loadingMore = false
    if (!bars.length) { cell.noMore = true; return }
    cell.chart.prependData(bars)
  }
  function applyRange(cell, k) {
    const [, iv, days] = RANGES[k], c = cfg(cell)
    const now = Date.now()
    let t0
    if (days === 'ytd') { const d = F.sh(now); t0 = Date.UTC(d.getUTCFullYear(), 0, 1) - 8 * 36e5 }
    else if (days === 'all') t0 = 0
    else t0 = now - days * 864e5
    const fit = () => { const b = cell.chart.bars; cell.chart.setVisibleRange(Math.max(t0, b[0]?.t || 0), b[b.length - 1]?.t || now) }
    if (c.iv !== iv) { c.iv = iv; save(); loadCell(cell, fit); refreshStreams(); renderToolbar() } else fit()
  }
  function setActive(i) {
    if (i === st.active || i < 0) return
    st.active = i
    cells.forEach((c, k) => c.el.classList.toggle('active', k === i))
    save(); renderToolbar(); renderPanel()
  }
  const active = () => cells[st.active]
  function openSymbol(symbol, cell = active()) {
    const c = cfg(cell); if (!c) return
    if (c.symbol === symbol) return
    c.symbol = symbol; save()
    loadCell(cell); refreshStreams(); renderToolbar(); renderPanel()
  }
  function setInterval_(iv, cell = active()) {
    const c = cfg(cell); if (c.iv === iv) return
    c.iv = iv; save(); loadCell(cell); refreshStreams(); renderToolbar()
  }

  // ------------------------------------------------------------ 画线
  function drawingsFor(s) { return (st.drawings[s] ||= []) }
  const undoStack = [], redoStack = []
  const lastSnap = {}
  function snapOf(s) { return JSON.stringify(drawingsFor(s)) }
  function drawingsChanged(cell) {
    const s = cfg(cell).symbol
    undoStack.push({ s, json: lastSnap[s] ?? '[]' }); redoStack.length = 0
    lastSnap[s] = snapOf(s)
    cells.forEach(c => { if (cfg(c).symbol === s) c.chart.dirty = true })
    save(); renderToolbar()
  }
  function restoreDrawings(s, json, fromStack, toStack) {
    toStack.push({ s, json: snapOf(s) })
    st.drawings[s] = JSON.parse(json); lastSnap[s] = json
    cells.forEach(c => { if (cfg(c).symbol === s) c.chart.setDrawings(st.drawings[s]) })
    showDrawProps(null); save(); renderToolbar()
  }
  function undo() { const u = undoStack.pop(); if (!u) return; restoreDrawings(u.s, u.json, undoStack, redoStack); toast('已撤销', '⌘⇧Z 重做', 'undo', 1800) }
  function redo() { const u = redoStack.pop(); if (!u) return; restoreDrawings(u.s, u.json, redoStack, undoStack) }

  const TOOLS = [
    ['cursor', '十字光标', 'Esc'], null,
    ['trend', '趋势线', 'Alt T'], ['ray', '射线', ''], ['hline', '水平线', 'Alt H'], ['vline', '垂直线', 'Alt V'], null,
    ['rect', '矩形', 'Alt ⇧ R'], ['fib', '斐波那契回撤', 'Alt F'], ['measure', '测量（也可以按住 ⇧ 拖）', ''],
  ]
  let tool = null
  function selectTool(t) {
    tool = t === 'cursor' ? null : t
    cells.forEach(c => c.chart.setTool(tool))
    $$('#drawbar [data-tool]').forEach(b => b.setAttribute('aria-pressed', (b.dataset.tool === (tool || 'cursor'))))
  }
  function renderDrawbar() {
    $('#drawbar').innerHTML = TOOLS.map(t => t ? `<button class="ibtn" data-tool="${t[0]}" aria-label="${t[1]}" data-tip="${t[1]}" data-kbd="${t[2]}" data-tip-side="right" aria-pressed="${t[0] === 'cursor'}">${I(t[0])}</button>` : '<div class="grp-sep"></div>').join('') +
      `<div class="grp-sep"></div>
      <button class="ibtn" data-dact="magnet" aria-label="磁吸" data-tip="磁吸：贴到最近的开高低收" data-tip-side="right" aria-pressed="${st.magnet}">${I('magnet')}</button>
      <button class="ibtn" data-dact="lock" aria-label="锁定画线" data-tip="锁定全部画线" data-tip-side="right" aria-pressed="${st.drawLocked}">${I('lock')}</button>
      <button class="ibtn" data-dact="hide" aria-label="隐藏画线" data-tip="隐藏全部画线" data-tip-side="right" aria-pressed="${st.drawHidden}">${I(st.drawHidden ? 'eyeOff' : 'eye')}</button>
      <div class="spacer"></div>
      <button class="ibtn" data-dact="clear" aria-label="清除画线" data-tip="清除这只品种的全部画线" data-tip-side="right">${I('trash')}</button>`
  }
  $('#drawbar').addEventListener('click', e => {
    const b = e.target.closest('button'); if (!b) return
    if (b.dataset.tool) return selectTool(b.dataset.tool)
    const a = b.dataset.dact
    if (a === 'magnet') { st.magnet = !st.magnet; cells.forEach(c => c.chart.setMagnet(st.magnet)) }
    if (a === 'lock') { st.drawLocked = !st.drawLocked; Object.values(st.drawings).flat().forEach(d => d.locked = st.drawLocked) }
    if (a === 'hide') { st.drawHidden = !st.drawHidden; cells.forEach(c => { c.chart.drawingsHidden = st.drawHidden; c.chart.dirty = true }) }
    if (a === 'clear') {
      const s = cfg(active()).symbol, n = drawingsFor(s).length
      if (!n) return toast('这只品种还没有画线', '', 'info', 1800)
      undoStack.push({ s, json: snapOf(s) }); st.drawings[s] = []; lastSnap[s] = '[]'
      cells.forEach(c => { if (cfg(c).symbol === s) c.chart.setDrawings(st.drawings[s]) })
      toast(`已清除 ${n} 条画线`, '⌘Z 撤销', 'trash')
    }
    save(); renderDrawbar(); selectTool(tool)
  })
  const SWATCHES = ['#2962FF', '#F23645', '#089981', '#F59E0B', '#9C27B0', '#131722']
  let propsTarget = null
  function showDrawProps(d, cell) {
    propsTarget = d ? { d, cell } : null
    const el = $('#drawProps'); if (!el) return
    el.classList.toggle('show', !!d)
    if (!d) return
    el.innerHTML = SWATCHES.map(c => `<button class="swatch-btn" data-color="${c}" aria-label="颜色 ${c}" aria-pressed="${d.color === c}"><span class="swatch" style="background:${c}"></span></button>`).join('') +
      `<span class="tb-sep"></span>
      ${[1, 2, 3].map(w => `<button class="ibtn xs" data-w="${w}" aria-pressed="${(d.width || 2) === w}" data-tip="${w} px 粗细" aria-label="${w} px"><svg class="icon-16" viewBox="0 0 16 16"><rect x="2" y="${8 - w / 2}" width="12" height="${w}" rx="${w / 2}" fill="currentColor"/></svg></button>`).join('')}
      <span class="tb-sep"></span>
      ${d.type !== 'measure' && d.type !== 'fib' && d.type !== 'rect' ? `<button class="ibtn xs" data-p="alert" aria-pressed="${!!d.alert}" data-tip="价格碰到这条线时提醒我">${I('bellPlus', 'icon-16')}</button>` : ''}
      <button class="ibtn xs" data-p="lock" aria-pressed="${!!d.locked}" data-tip="锁定">${I('lock', 'icon-16')}</button>
      <button class="ibtn xs" data-p="del" data-tip="删除" data-kbd="Delete">${I('trash', 'icon-16')}</button>`
  }
  function drawPropsClick(e) {
    const b = e.target.closest('button'); if (!b || !propsTarget) return
    const { d, cell } = propsTarget
    if (b.dataset.color) d.color = b.dataset.color, st.drawColor = b.dataset.color
    if (b.dataset.w) d.width = +b.dataset.w
    if (b.dataset.p === 'lock') d.locked = !d.locked
    if (b.dataset.p === 'alert') { d.alert = !d.alert; if (d.alert) toast('画线提醒已开', '价格碰到这条线时通知你，响一次就结束', 'bell') }
    if (b.dataset.p === 'del') { cell.chart.deleteSelected(); return }
    drawingsChanged(cell); showDrawProps(d, cell)
  }

  // ------------------------------------------------------------ 工具栏
  function renderToolbar() {
    const cell = active(); if (!cell) return
    const c = cfg(cell), s = sym(c.symbol)
    const pinnedHas = st.pinned.includes(c.iv)
    $('#toolbar').innerHTML = `
      <button class="tb-btn symbol-btn" id="tbSymbol" data-tip="换品种" data-kbd="⌘ K">${badge(s)}<span>${c.symbol}</span><span class="kind">${kindName(s)}</span></button>
      <span class="tb-sep"></span>
      <div class="intervals" role="group" aria-label="周期">
        ${st.pinned.map(iv => `<button data-iv="${iv}" aria-pressed="${iv === c.iv}" data-tip="${D.IV_LABEL[iv]}" data-kbd="${ivKey(iv)}">${D.IV_SHORT[iv]}</button>`).join('')}
        ${pinnedHas ? '' : `<button data-iv="${c.iv}" aria-pressed="true">${D.IV_SHORT[c.iv]}</button>`}
        <button class="ibtn sm" id="tbMoreIv" aria-label="全部周期" data-tip="全部周期">${I('chevronDown', 'icon-16')}</button>
      </div>
      <span class="tb-sep"></span>
      <button class="tb-btn" id="tbInd" data-tip="指标" data-kbd="/">${I('indicators')}指标</button>
      <button class="tb-btn" id="tbAlert" data-tip="在现价创建提醒" data-kbd="Alt A">${I('bellPlus')}提醒</button>
      <button class="tb-btn" id="tbNote" data-tip="把这一刻记下来">${I('note')}记一笔</button>
      <div class="draw-props" id="drawProps" role="toolbar" aria-label="画线属性"></div>
      <div class="tb-right">
        <button class="ibtn sm" id="tbUndo" aria-label="撤销" data-tip="撤销" data-kbd="⌘ Z" ${undoStack.length ? '' : 'disabled style="opacity:.4"'}>${I('undo')}</button>
        <button class="ibtn sm" id="tbRedo" aria-label="重做" data-tip="重做" data-kbd="⌘ ⇧ Z" ${redoStack.length ? '' : 'disabled style="opacity:.4"'}>${I('redo')}</button>
        <span class="tb-sep"></span>
        <button class="ibtn sm" id="tbLayout" aria-label="布局" data-tip="图表布局">${I({ '1': 'layout1', '2': 'layout2', '2v': 'layout2v', '4': 'layout4' }[st.layout])}</button>
        <button class="ibtn sm" id="tbShot" aria-label="截图" data-tip="保存图表截图" data-kbd="⌥ S">${I('camera')}</button>
        <button class="ibtn sm" id="tbShare" aria-label="分享" data-tip="分享">${I('share')}</button>
        <button class="ibtn sm" id="tbFull" aria-label="全屏" data-tip="全屏" data-kbd="⇧ F">${I('fullscreen')}</button>
      </div>`
    $('#drawProps').addEventListener('click', drawPropsClick)
    if (propsTarget) showDrawProps(propsTarget.d, propsTarget.cell)
  }
  function ivKey(iv) { return { '1m': '1', '3m': '3', '5m': '5', '15m': '15', '30m': '30', '1h': '60', '2h': '120', '4h': '240', '6h': '360', '8h': '480', '12h': '720', '1d': '1 D', '1w': '1 W', '1M': '1 M' }[iv] }
  $('#toolbar').addEventListener('click', e => {
    const b = e.target.closest('button'); if (!b) return
    if (b.dataset.iv) return setInterval_(b.dataset.iv)
    switch (b.id) {
      case 'tbSymbol': return openSearch()
      case 'tbMoreIv': return intervalMenu(b)
      case 'tbInd': return openIndicators()
      case 'tbAlert': return openAlert()
      case 'tbNote': return openNote()
      case 'tbUndo': return undo()
      case 'tbRedo': return redo()
      case 'tbLayout': return menuFrom(b, [{ header: '布局' }, ...[['1', 'layout1', '一图'], ['2', 'layout2', '左右两图'], ['2v', 'layout2v', '上下两图'], ['4', 'layout4', '四图']].map(([k, ic, l]) => ({ icon: ic, label: l, checked: st.layout === k, sc: k === st.layout ? '当前' : '', run: () => { st.layout = k; buildCells(); renderToolbar() } })), '-', { label: '十字线跨图同步', icon: 'check', disabled: true, sc: '始终' }])
      case 'tbShot': return screenshot()
      case 'tbShare': return menuFrom(b, [{ icon: 'camera', label: '复制图表截图', run: () => screenshot(true) }, { icon: 'link', label: '复制这张图的链接', run: () => { navigator.clipboard?.writeText(`${location.origin}${location.pathname}?s=${cfg(active()).symbol}&i=${cfg(active()).iv}#chart`); toast('链接已复制', '') } }, '-', { icon: 'user', label: '把画线发给朋友…', run: () => toast('已发到朋友的收件箱', '他打开时画线会落在他自己的图表布局上', 'share') }])
      case 'tbFull': return fullscreen()
    }
  })
  function intervalMenu(btn) {
    const c = cfg(active())
    const groups = [['分钟', ['1m', '3m', '5m', '15m', '30m']], ['小时', ['1h', '2h', '4h', '6h', '8h', '12h']], ['日及以上', ['1d', '1w', '1M']]]
    const m = menuFrom(btn, groups.flatMap(([h, ivs]) => [{ header: h }, ...ivs.map(iv => ({
      html: `${D.IV_LABEL[iv]}<span style="float:right;display:flex;gap:4px"></span>`, checked: iv === c.iv, check: true, sc: st.pinned.includes(iv) ? '已钉在栏上' : '', run: () => setInterval_(iv),
    }))]).concat(['-', { header: '右键周期可钉到栏上 · 直接打数字也能换周期' }]), { width: 260 })
    // 右键一行 = 钉 / 取消钉
    m.addEventListener('contextmenu', e => {
      e.preventDefault()
      const b = e.target.closest('.mi'); if (!b) return
      const lab = b.querySelector('.label').textContent.trim()
      const iv = Object.keys(D.IV_LABEL).find(k => D.IV_LABEL[k] === lab); if (!iv) return
      st.pinned = st.pinned.includes(iv) ? st.pinned.filter(x => x !== iv) : D.INTERVALS.filter(x => st.pinned.includes(x) || x === iv)
      save(); closeMenu(); renderToolbar(); intervalMenu($('#tbMoreIv'))
    })
  }
  function screenshot(copy) {
    const cell = active(), cv = cell.chart.canvas, c = cfg(cell)
    const d = F.sh(Date.now()), stamp = `${d.getUTCFullYear()}${F.pad(d.getUTCMonth() + 1)}${F.pad(d.getUTCDate())}-${F.pad(d.getUTCHours())}${F.pad(d.getUTCMinutes())}`
    if (copy && navigator.clipboard && g.ClipboardItem) {
      cv.toBlob(b => navigator.clipboard.write([new ClipboardItem({ 'image/png': b })]).then(() => toast('截图已复制', '可以直接粘贴到聊天里', 'camera')).catch(() => toast('浏览器不让复制图片', '改用下载', 'info')))
      return
    }
    const a = document.createElement('a'); a.download = `Hkline-${c.symbol}-${c.iv}-${stamp}.png`; a.href = cv.toDataURL('image/png'); a.click()
    toast('截图已保存', a.download, 'camera')
  }
  function fullscreen() { document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen?.() }

  // ------------------------------------------------------------ 图例、右键、大单卡
  function legendAction(cell, id, act, btn) {
    if (act === 'remove') {
      if (id === 'walls') { st.flowOn = false; cells.forEach(c => c.chart.setWalls(null)) }
      else if (['ma', 'ema', 'boll', 'vol'].includes(id)) st.ind[id] = false
      else st.ind.subs = st.ind.subs.filter(x => x !== id)
      cells.forEach(c => c.chart.setIndicators(st.ind)); save()
      toast(`已移除 ${TVCatalog[id]?.name || '主力订单流'}`, '在「指标」里可以加回来', 'close', 2200)
    }
    if (act === 'settings') id === 'walls' ? openFlowSettings() : openParams(id)
  }
  function chartContextMenu(cell, info) {
    const c = cfg(cell), s = sym(c.symbol), p = info.price
    const pt = p != null ? F.fmt(p, s?.dec ?? 2) : ''
    const items = []
    if (info.drawing) {
      items.push({ header: '这条画线' }, { icon: info.drawing.locked ? 'lock' : 'lock', label: info.drawing.locked ? '解锁' : '锁定', run: () => { info.drawing.locked = !info.drawing.locked; drawingsChanged(cell) } },
        { icon: 'trash', label: '删除', sc: 'Delete', run: () => { cell.chart.selected = info.drawing; cell.chart.deleteSelected() } }, '-')
    }
    if (p != null) items.push(
      { icon: 'bellPlus', label: `在 ${pt} 创建提醒`, sc: 'Alt A', run: () => openAlert(p) },
      { icon: 'hline', label: `在 ${pt} 画水平线`, sc: 'Alt H', run: () => { drawingsFor(c.symbol).push({ id: 'd' + Date.now(), type: 'hline', pts: [{ t: info.time, p }], color: st.drawColor, width: 2 }); cell.chart.dirty = true; drawingsChanged(cell) } },
      { icon: 'note', label: '在这根 K 线记一笔…', run: () => openNote(info.time, p) },
      { icon: 'link', label: `复制价格 ${pt}`, run: () => { navigator.clipboard?.writeText(p.toFixed(s?.dec ?? 2)); toast('已复制', pt, 'check', 1500) } }, '-')
    items.push(
      { label: '重置视图', icon: 'candles', sc: 'Alt R', run: () => cell.chart.resetView() },
      { label: '对数坐标', check: true, checked: cell.chart.log, run: () => { cell.chart.setLog(!cell.chart.log); $('[data-act="log"]', cell.el).setAttribute('aria-pressed', cell.chart.log) } },
      { label: '隐藏画线', check: true, checked: st.drawHidden, run: () => $('#drawbar [data-dact="hide"]').click() },
      { label: '显示主力订单流', check: true, checked: st.flowOn, run: () => setFlow(!st.flowOn) },
    )
    menu(items, info.clientX, info.clientY, { width: 260 })
  }
  function setFlow(on) {
    st.flowOn = on; save()
    cells.forEach(c => c.chart.setWalls(on ? D.demoWalls(cfg(c).symbol, c.chart.bars, cfg(c).iv) : null))
    cells.forEach(c => c.chart.renderLegend())
    if (st.panel === 'flow') renderPanel()
  }
  let wallEl = null
  function wallCard(cell, w, x, y) {
    if (!w) { wallEl?.remove(); wallEl = null; return }
    const s = sym(cfg(cell).symbol), dec = s?.dec ?? 2
    const last = cell.chart.bars[cell.chart.bars.length - 1]?.c
    const dist = last ? (w.price - last) / last * 100 : 0
    const dur = (w.to || Date.now()) - w.from
    if (!wallEl) { wallEl = document.createElement('div'); wallEl.className = 'tooltip show'; wallEl.style.cssText = 'max-width:none;padding:10px 12px;min-width:220px'; document.body.appendChild(wallEl) }
    wallEl.innerHTML = `<b style="display:flex;gap:6px;align-items:center;margin-bottom:6px">${w.product === 'spot' ? '现货' : '合约'}${w.side === 'bid' ? '买单' : '卖单'} <span style="font-weight:600;margin-left:auto">${F.fmtCompact(w.size)}</span></b>
      <div style="display:grid;grid-template-columns:auto 1fr;gap:2px 16px;font-variant-numeric:tabular-nums">
      <span style="opacity:.7">价位区间</span><span style="text-align:right">${F.fmt(w.lo, dec)} – ${F.fmt(w.hi, dec)}</span>
      <span style="opacity:.7">距现价</span><span style="text-align:right">${dist >= 0 ? '+' : ''}${dist.toFixed(2)}%</span>
      <span style="opacity:.7">${w.to ? '挂了' : '已挂'}</span><span style="text-align:right">${F.durText(dur)}${w.to ? ' · 已撤' : ''}</span></div>`
    const tw = wallEl.offsetWidth
    wallEl.style.left = Math.min(innerWidth - tw - 12, x + 16) + 'px'; wallEl.style.top = (y + 16) + 'px'
  }

  // ------------------------------------------------------------ 侧栏
  const RAIL = [['watch', 'star', '自选'], ['alerts', 'bell', '提醒'], ['flow', 'layers', '主力订单流'], ['notes', 'note', '笔记'], ['trades', 'trades', '成交']]
  function renderRail() {
    $('#rail').innerHTML = RAIL.map(([k, ic, l]) => `<button class="ibtn ${st.panel === k ? 'on' : ''}" data-panel="${k}" aria-label="${l}" aria-pressed="${st.panel === k}" data-tip="${l}" data-tip-side="left">${I(ic)}${k === 'alerts' && st.alerts.length ? `<span class="dot">${st.alerts.length}</span>` : ''}</button>`).join('') +
      `<div class="rail-spacer"></div>
      <button class="ibtn" id="railKeys" aria-label="快捷键" data-tip="快捷键" data-kbd="?" data-tip-side="left">${I('info')}</button>
      <button class="ibtn" id="railSpec" aria-label="设计规范" data-tip="设计规范" data-tip-side="left">${I('spec')}</button>`
  }
  $('#rail').addEventListener('click', e => {
    const b = e.target.closest('button'); if (!b) return
    if (b.id === 'railKeys') return openShortcuts()
    if (b.id === 'railSpec') return go('spec')
    const p = b.dataset.panel
    st.panel = st.panel === p ? null : p
    save(); renderRail(); renderPanel()
  })
  function renderPanel() {
    const page = $('#page-chart')
    page.classList.toggle('panel-closed', !st.panel)
    cells.forEach(c => c.chart.resize())
    if (!st.panel) return
    const fn = { watch: panelWatch, alerts: panelAlerts, flow: panelFlow, notes: panelNotes, trades: panelTrades }[st.panel]
    fn($('#sidePanel'))
  }

  // ---- 自选
  const TABS = [['crypto', '加密'], ['us', '美股'], ['com', '大宗']]
  function panelWatch(el) {
    const cur = cfg(active()).symbol
    const list = st.watch[st.watchTab]
    el.innerHTML = `<div class="sp-head"><h3>自选</h3>
        <button class="ibtn sm" id="wAdd" aria-label="添加品种" data-tip="添加品种" data-kbd="⌘ K">${I('plus')}</button>
        <button class="ibtn sm" id="wMore" aria-label="更多" data-tip="更多">${I('more')}</button></div>
      <div class="sp-sub" role="tablist">${TABS.map(([k, l]) => `<button class="chip" role="tab" data-tab="${k}" aria-pressed="${st.watchTab === k}">${l} ${st.watch[k].length}</button>`).join('')}</div>
      <div class="scroll" style="flex:1;min-height:0">
        ${list.length ? `<table class="tbl" id="wTbl"><thead><tr><th>品种</th><th>最新价</th><th>涨跌幅</th><th>成交额</th></tr></thead>
        <tbody>${list.map(k => watchRow(k, cur)).join('')}</tbody></table>` : `<div class="empty">${I('star', 'icon-24')}<div>这一类还没有自选</div><button class="btn secondary sm" style="margin-top:12px" id="wAdd2">搜索品种</button></div>`}
      </div>
      <div class="detail" id="detail"></div>`
    renderDetail()
    const tbl = $('#wTbl', el)
    tbl && bindDrag(tbl)
  }
  function watchRow(k, cur) {
    const s = sym(k)
    return `<tr data-sym="${k}" draggable="true" class="${k === cur ? 'sel' : ''}" aria-selected="${k === cur}">
      <td><div class="sym">${badge(s)}<b>${s?.code || k}</b><span class="cn">${esc(s?.cn || '')}</span></div></td>
      <td class="num price-live" data-f="price">${priceText(s)}</td>
      <td class="num ${cls(s?.pct)} price-live" data-f="pct">${pctText(s?.pct)}</td>
      <td class="num muted" data-f="vol">${F.fmtCompact(s?.vol)}</td></tr>`
  }
  function bindDrag(tbl) {
    let from = null
    tbl.addEventListener('dragstart', e => { from = e.target.closest('tr'); from.classList.add('dragging'); e.dataTransfer.effectAllowed = 'move' })
    tbl.addEventListener('dragend', () => { from?.classList.remove('dragging'); $$('tr', tbl).forEach(r => r.classList.remove('drop-above', 'drop-below')) })
    tbl.addEventListener('dragover', e => {
      const tr = e.target.closest('tbody tr'); if (!tr || !from) return
      e.preventDefault(); $$('tr', tbl).forEach(r => r.classList.remove('drop-above', 'drop-below'))
      const r = tr.getBoundingClientRect(); tr.classList.add(e.clientY < r.top + r.height / 2 ? 'drop-above' : 'drop-below')
    })
    tbl.addEventListener('drop', e => {
      const tr = e.target.closest('tbody tr'); if (!tr || !from || tr === from) return
      e.preventDefault()
      const list = st.watch[st.watchTab], a = from.dataset.sym
      list.splice(list.indexOf(a), 1)
      let i = list.indexOf(tr.dataset.sym); if (tr.classList.contains('drop-below')) i++
      list.splice(i, 0, a); save(); renderPanel()
    })
  }
  $('#sidePanel').addEventListener('click', e => {
    const t = e.target
    const tab = t.closest('[data-tab]'); if (tab) { st.watchTab = tab.dataset.tab; save(); renderPanel(); refreshStreams(); return }
    if (t.closest('#wAdd,#wAdd2')) return openSearch()
    if (t.closest('#wMore')) return menuFrom(t.closest('#wMore'), [{ icon: 'drag', label: '拖动行可以排序', disabled: true }, { icon: 'trash', label: `清空「${TABS.find(x => x[0] === st.watchTab)[1]}」自选`, run: () => { const bak = st.watch[st.watchTab]; st.watch[st.watchTab] = []; save(); renderPanel(); toast('已清空', '⌘Z 撤销', 'trash'); lastWatchUndo = () => { st.watch[st.watchTab] = bak; save(); renderPanel() } } }])
    const tr = t.closest('tr[data-sym]'); if (tr) return openSymbol(tr.dataset.sym)
    const star = t.closest('[data-star]'); if (star) return toggleWatch(star.dataset.star)
    const sec = t.closest('[data-sector]'); if (sec) return App.openSector?.(sec.dataset.sector)
    const del = t.closest('[data-del-alert]'); if (del) return deleteAlert(del.dataset.delAlert)
    const scope = t.closest('[data-scope]'); if (scope) { st.alertScope = scope.dataset.scope; save(); renderPanel(); return }
    if (t.closest('#aNew')) return openAlert()
    const note = t.closest('[data-note]'); if (note) return jumpNote(note.dataset.note)
    const wall = t.closest('[data-wall]'); if (wall) { const c = active(); const w = c.chart.walls?.[+wall.dataset.wall]; if (w) { c.chart.hoverWall = w; c.chart.dirty = true; setTimeout(() => { c.chart.hoverWall = null; c.chart.dirty = true }, 1600) } return }
    if (t.closest('#flowToggle')) return setFlow(!st.flowOn)
    if (t.closest('#flowSet')) return openFlowSettings()
    if (t.closest('#tLogin')) return openLogin()
    const tr2 = t.closest('[data-trade]'); if (tr2) { location.hash = '#review'; App.openTrade?.(tr2.dataset.trade) }
  })
  let lastWatchUndo = null
  function toggleWatch(k) {
    const s = sym(k), tab = s?.kind || 'crypto'
    const list = st.watch[tab]
    const on = list.includes(k)
    if (on) list.splice(list.indexOf(k), 1); else list.push(k)
    save(); if (st.panel === 'watch') renderPanel(); refreshStreams()
    toast(on ? `已从自选移除 ${s?.code || k}` : `已加到自选 · ${TABS.find(x => x[0] === tab)[1]}`, '', on ? 'starOff' : 'star', 1800)
    return !on
  }
  const isWatched = k => Object.values(st.watch).some(l => l.includes(k))
  let oiCache = {}
  // 详情块里那几项不在推送里的数：持仓量、持仓量 24h 变化、多空人数比、大户持仓比、主动买卖比。
  // 币安 fapi 直接给（同一主机，跨域头一样有），一分钟刷一次，够用。
  async function fetchOI(k) {
    if (oiCache[k] && Date.now() - oiCache[k].t < 60e3) return
    const c = oiCache[k] = { t: Date.now(), ...(oiCache[k] || {}) }
    const get = (path, q) => fetch(`https://fapi.binance.com${path}?symbol=${k}&${q}`, { referrerPolicy: 'no-referrer' }).then(r => r.json())
    try {
      const [oi, hist, ls, top, taker] = await Promise.all([
        get('/fapi/v1/openInterest', ''), get('/futures/data/openInterestHist', 'period=1h&limit=25'),
        get('/futures/data/globalLongShortAccountRatio', 'period=5m&limit=1'), get('/futures/data/topLongShortPositionRatio', 'period=5m&limit=1'),
        get('/futures/data/takerlongshortRatio', 'period=5m&limit=1'),
      ])
      c.v = +oi.openInterest * (sym(k)?.price || 0)
      if (hist?.length > 1) c.oiChg = (+hist[hist.length - 1].sumOpenInterestValue / +hist[0].sumOpenInterestValue - 1) * 100
      if (ls?.[0]) c.ls = +ls[0].longShortRatio
      if (top?.[0]) c.top = +top[0].longShortRatio
      if (taker?.[0]) c.taker = +taker[0].buySellRatio
      renderDetail()
    } catch {}
  }
  function ratioText(r) { return r == null ? '—' : r.toFixed(2) }
  function ratioCls(r) { return r == null ? '' : r > 1 ? 'up' : r < 1 ? 'down' : '' }
  function renderDetail() {
    const el = $('#detail'); if (!el) return
    const k = cfg(active()).symbol, s = sym(k)
    if (!s) { el.innerHTML = ''; return }
    fetchOI(k)
    const oi = oiCache[k] || {}
    const secs = (g.KP_SECTORS.members[s.base] || []).map(id => g.KP_SECTORS.crypto.find(x => x[0] === id)).filter(Boolean)
    const usSecs = s.kind === 'us' ? g.KP_SECTORS.us.filter(x => x[2].includes(s.base)) : []
    el.innerHTML = `<div class="dh">${badge(s, 'xl')}<div class="names"><div class="code">${s.code}<span class="muted" style="font-weight:400;font-size:13px;margin-left:8px">${kindName(s)}</span></div><div class="cn">${esc(s.cn || '')}</div></div>
        <button class="ibtn" data-star="${k}" aria-pressed="${isWatched(k)}" aria-label="${isWatched(k) ? '移出自选' : '加入自选'}" data-tip="${isWatched(k) ? '移出自选' : '加入自选'}">${I(isWatched(k) ? 'star' : 'starOff')}</button></div>
      <div class="px"><span class="big num price-live ${st.stale ? '' : cls(s.pct)}" data-f="big">${priceText(s)}</span><span class="chg num ${cls(s.pct)}" data-f="chg">${s.chg >= 0 ? '+' : ''}${F.fmt(s.chg, s.dec)}  ${pctText(s.pct)}</span></div>
      ${s.hi && s.lo ? `<div class="range"><span class="num">${F.fmt(s.lo, s.dec)}</span><div class="bar"><i style="left:${clamp01((s.price - s.lo) / (s.hi - s.lo)) * 100}%"></i></div><span class="num">${F.fmt(s.hi, s.dec)}</span></div>` : ''}
      <div class="stats cols3">
        <div><div class="k">${term('持仓量')}</div><div class="v num">${oi.v ? F.fmtCompact(oi.v) : '—'}</div></div>
        <div><div class="k">持仓 24h</div><div class="v num ${cls(oi.oiChg)}">${oi.oiChg == null ? '—' : pctText(oi.oiChg)}</div></div>
        <div><div class="k">24h 成交额</div><div class="v num">${F.fmtCompact(s.vol)}</div></div>
        <div><div class="k">${term('资金费率')}</div><div class="v num ${s.fr > 0 ? 'up' : s.fr < 0 ? 'down' : ''}" data-f="fr">${s.fr == null ? '—' : (s.fr * 100).toFixed(4) + '%'}</div></div>
        <div><div class="k">${term('下次结算')}</div><div class="v num" data-f="cd">${s.nextFunding ? countdown(s.nextFunding - Date.now()) : '—'}</div></div>
        <div><div class="k">24h 笔数</div><div class="v num">${s.count ? F.fmtCompact(s.count) : '—'}</div></div>
        <div><div class="k">${term('多空人数比')}</div><div class="v num ${ratioCls(oi.ls)}">${ratioText(oi.ls)}</div></div>
        <div><div class="k">${term('大户持仓比')}</div><div class="v num ${ratioCls(oi.top)}">${ratioText(oi.top)}</div></div>
        <div><div class="k">${term('主动买卖比')}</div><div class="v num ${ratioCls(oi.taker)}">${ratioText(oi.taker)}</div></div>
        <div><div class="k">${term('标记价')}</div><div class="v num">${s.mark ? F.fmt(s.mark, s.dec) : '—'}</div></div>
        <div><div class="k">${term('指数价')}</div><div class="v num">${s.index ? F.fmt(s.index, s.dec) : '—'}</div></div>
        <div><div class="k">${term('基差')}</div><div class="v num ${s.mark && s.index ? cls(s.mark - s.index) : ''}">${s.mark && s.index ? pctText((s.mark / s.index - 1) * 100) : '—'}</div></div>
      </div>
      ${secs.length || usSecs.length ? `<div class="sectors">${secs.map(x => `<button class="tag" data-sector="c:${x[0]}">${esc(x[1])}</button>`).join('')}${usSecs.map(x => `<button class="tag" data-sector="u:${x[0]}">${esc(x[1])}</button>`).join('')}</div>` : ''}`
  }

  // ---- 提醒
  function panelAlerts(el) {
    const k = cfg(active()).symbol
    const list = st.alertScope === 'symbol' ? st.alerts.filter(a => a.symbol === k) : st.alerts
    const byKind = [['price', '价格'], ['line', '画线'], ['other', '指标']]
    el.innerHTML = `<div class="sp-head"><h3>提醒</h3><button class="btn secondary sm" id="aNew">${I('plus', 'icon-16')}新建</button></div>
      <div class="sp-sub"><button class="chip" data-scope="symbol" aria-pressed="${st.alertScope === 'symbol'}">${k.replace('USDT', '')}</button><button class="chip" data-scope="all" aria-pressed="${st.alertScope === 'all'}">全部 ${st.alerts.length}</button></div>
      <div class="scroll" style="flex:1;min-height:0">
      ${list.length ? byKind.map(([kd, l]) => {
        const rows = list.filter(a => (a.kind === 'price' ? 'price' : a.kind === 'line' ? 'line' : 'other') === kd)
        return rows.length ? `<div class="sec-title">${l}<span>${rows.length}</span></div>` + rows.map(a => alertRow(a)).join('') : ''
      }).join('') : `<div class="empty">${I('bell', 'icon-24')}<div>没有还在等的提醒</div><div class="faint" style="font-size:12px;margin-top:4px">在图上右键，或按 Alt A</div></div>`}
      </div>`
  }
  function alertDesc(a) {
    const s = sym(a.symbol)
    if (a.kind === 'price') return `价格达到 ${F.fmt(a.price, s?.dec ?? 2)}`
    if (a.kind === 'fr') return `资金费率 ${a.op === 'gt' ? '高于' : '低于'} ${a.value}%`
    if (a.kind === 'oi') return `持仓量 1 小时变化超过 ${a.value}%`
    if (a.kind === 'wall') return `出现 ≥ ${a.value}M 的大单`
    return ''
  }
  function alertRow(a) {
    const s = sym(a.symbol), last = s?.price
    const dist = a.kind === 'price' && last ? (a.price - last) / last * 100 : null
    return `<div class="list-row">${badge(s, 'lg')}<div class="main"><div class="t1">${s?.code || a.symbol}<span class="num">${alertDesc(a)}</span></div>
      <div class="t2">${dist != null ? `还差 ${dist >= 0 ? '+' : ''}${dist.toFixed(2)}% · ` : ''}${shTime(a.created)} 创建${a.webhook ? ' · 同时发 Webhook' : ''}</div></div>
      <button class="ibtn sm act" data-del-alert="${a.id}" aria-label="删除提醒" data-tip="删除">${I('trash')}</button></div>`
  }
  function deleteAlert(id) {
    st.alerts = st.alerts.filter(a => a.id !== id); save(); refreshAlerts()
  }
  function refreshAlerts() {
    cells.forEach(c => c.chart.setAlerts(st.alerts.filter(a => a.symbol === cfg(c).symbol && a.kind === 'price')))
    renderRail(); if (st.panel === 'alerts') renderPanel()
  }
  function checkAlerts(k) {
    const s = sym(k); if (!s || s.price == null) return
    for (const a of st.alerts.filter(a => a.symbol === k && a.kind === 'price')) {
      if ((a.dir > 0 && s.price >= a.price) || (a.dir < 0 && s.price <= a.price)) {
        st.alerts = st.alerts.filter(x => x !== a); save(); refreshAlerts()
        toast(`${s.code} 价格达到 ${F.fmt(a.price, s.dec)}`, `现价 ${priceText(s)} · 这条提醒已结束`, 'bell', 8000)
        if (g.Notification?.permission === 'granted') new Notification(`${s.code} 价格达到 ${F.fmt(a.price, s.dec)}`, { body: `现价 ${priceText(s)}` })
      }
    }
  }

  // ---- 订单流
  function panelFlow(el) {
    const c = active(), walls = (c.chart.walls || []).map((w, i) => ({ w, i })).filter(x => !x.w.to).sort((a, b) => b.w.size - a.w.size)
    const s = sym(cfg(c).symbol), dec = s?.dec ?? 2, last = c.chart.bars[c.chart.bars.length - 1]?.c
    el.innerHTML = `<div class="sp-head"><h3>${term('主力订单流')}</h3>
        <button class="ibtn sm" id="flowSet" aria-label="门槛设置" data-tip="门槛与步长">${I('gear')}</button>
        <button class="switch" id="flowToggle" role="switch" aria-checked="${st.flowOn}" aria-label="在图上显示"></button></div>
      <div class="sp-sub"><span class="tag perp">合约 ≥ 5M</span><span class="tag spot">现货 ≥ 1M</span><span class="faint" style="font-size:12px;margin-left:auto">币安 · OKX · Coinbase 聚合</span></div>
      <div class="scroll" style="flex:1;min-height:0">
      ${!st.flowOn ? `<div class="empty">${I('layers', 'icon-24')}<div>主力订单流已关</div></div>` : walls.length ? `<table class="tbl"><thead><tr><th>价位区间</th><th>类型</th><th>金额</th><th>距现价</th><th>已挂</th></tr></thead><tbody>
        ${walls.map(({ w, i }) => { const d = last ? (w.price - last) / last * 100 : 0; return `<tr data-wall="${i}"><td class="num">${rangeText(w)}</td><td><span class="tag ${w.product}">${w.product === 'spot' ? '现货' : '合约'}${w.side === 'bid' ? '买' : '卖'}</span></td><td class="num" style="font-weight:600">${F.fmtCompact(w.size)}</td><td class="num ${d >= 0 ? 'up' : 'down'}">${d >= 0 ? '+' : ''}${d.toFixed(2)}%</td><td class="num muted">${F.durText(Date.now() - w.from)}</td></tr>` }).join('')}
      </tbody></table>` : `<div class="empty">现在没有超过门槛的大单</div>`}
      </div>`
  }
  // 价位区间按步长的小数位写（BTC 步长 100 → 整数），窄面板里放得下
  function rangeText(w) {
    const step = Math.abs(w.hi - w.lo), d = step > 0 ? ((+step.toFixed(8)).toString().split('.')[1] || '').length : 2
    return `${F.fmt(w.lo, d)} – ${F.fmt(w.hi, d)}`
  }
  function openFlowSettings() {
    const s = sym(cfg(active()).symbol)
    const d = dialog(`${head('主力订单流 · ' + (s?.code || ''))}<div class="dialog-body"><div class="form-grid">
      <div class="field"><label>合约门槛</label><div class="input-wrap"><input class="input" value="5"><span class="suffix">M USDT</span></div></div>
      <div class="field"><label>现货门槛</label><div class="input-wrap"><input class="input" value="1"><span class="suffix">M USDT</span></div></div>
      <div class="field"><label>价位步长</label><div class="input-wrap"><input class="input" value="${s?.base === 'BTC' ? 100 : F.fmt(D.niceStep((s?.price || 100) * .0012), s?.dec ?? 2)}"><span class="suffix">USDT</span></div><div class="hint">步长以内的挂单并成一档；按品种记住，换设备也跟着走</div></div>
      </div></div><div class="dialog-foot"><button class="btn ghost" data-close>取消</button><button class="btn primary" id="fsOk">保存</button></div>`, 'alert-dlg', { label: '主力订单流设置' })
    $('#fsOk', d.dlg).onclick = () => { d.close(); toast('已保存', '所有设备同步', 'check', 1800) }
    $('input', d.dlg).focus()
  }

  // ---- 笔记
  function panelNotes(el) {
    el.innerHTML = `<div class="sp-head"><h3>笔记</h3><button class="btn secondary sm" id="nNew">${I('plus', 'icon-16')}记一笔</button></div>
      <div class="scroll" style="flex:1;min-height:0">${st.notes.length ? st.notes.slice().reverse().map(n => {
        const s = sym(n.symbol)
        return `<div class="list-row" data-note="${n.id}" style="cursor:pointer;align-items:flex-start">${badge(s, 'lg')}<div class="main"><div class="t1">${s?.code || n.symbol}<span class="tag">${D.IV_LABEL[n.iv]}</span><span class="faint" style="font-size:12px;font-weight:400;margin-left:auto">${shTime(n.t)}</span></div>
          <div class="t2" style="color:var(--text-1);font-size:13px;line-height:20px;white-space:pre-wrap">${esc(n.text)}</div></div></div>`
      }).join('') : `<div class="empty">${I('note', 'icon-24')}<div>还没有笔记</div><div class="faint" style="font-size:12px;margin-top:4px">在图上右键「在这根 K 线记一笔」</div></div>`}</div>`
    $('#nNew', el).onclick = () => openNote()
  }
  function openNote(t, p) {
    const c = cfg(active()), s = sym(c.symbol), b = active().chart.lastBar()
    t ??= b?.t; p ??= b?.c
    const d = dialog(`${head('记一笔')}<div class="dialog-body"><div class="form-grid">
      <div class="sym-card">${badge(s, 'lg')}<div style="flex:1"><b>${c.symbol}</b> <span class="muted">${D.IV_LABEL[c.iv]} · ${shTime(t)}</span></div><span class="num">${F.fmt(p, s?.dec ?? 2)}</span></div>
      <div class="field"><label for="nTx">这时候在想什么</label><textarea id="nTx" class="input" style="height:120px;padding:8px 12px;resize:vertical;line-height:20px" placeholder="比如：放量突破前高，回踩不破再看多"></textarea></div>
      </div></div><div class="dialog-foot"><span class="faint" style="margin-right:auto;font-size:12px;align-self:center"><kbd>⌘</kbd> <kbd>↵</kbd> 保存</span><button class="btn ghost" data-close>取消</button><button class="btn primary" id="nOk">保存</button></div>`, 'alert-dlg', { label: '记一笔' })
    const tx = $('#nTx', d.dlg); tx.focus()
    const ok = () => { if (!tx.value.trim()) return tx.focus(); st.notes.push({ id: 'n' + Date.now(), symbol: c.symbol, iv: c.iv, t, p, text: tx.value.trim() }); save(); d.close(); toast('已记下', '在右侧「笔记」里能找回来', 'note'); if (st.panel === 'notes') renderPanel() }
    $('#nOk', d.dlg).onclick = ok
    tx.addEventListener('keydown', e => { if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) ok() })
  }
  function jumpNote(id) {
    const n = st.notes.find(x => x.id === id); if (!n) return
    const cell = active(), c = cfg(cell)
    const center = () => { const i = cell.chart.indexAt(n.t); cell.chart.rightBar = i + cell.chart.plotW() / cell.chart.spacing / 2; cell.chart.syncCrosshair(n.t); cell.chart.dirty = true; setTimeout(() => cell.chart.syncCrosshair(null), 2000) }
    if (c.symbol !== n.symbol || c.iv !== n.iv) { c.symbol = n.symbol; c.iv = n.iv; save(); loadCell(cell, center); refreshStreams(); renderToolbar() } else center()
  }

  // ---- 成交（交易所只读）
  function panelTrades(el) {
    if (!st.loggedIn) { el.innerHTML = `<div class="sp-head"><h3>成交</h3></div><div class="empty">${I('trades', 'icon-24')}<div>登录并连上交易所只读密钥后，这里会列出你的开平仓</div><button class="btn primary sm" style="margin-top:16px" id="tLogin">登录</button></div>`; return }
    const trades = App.reviewTrades?.() || []
    el.innerHTML = `<div class="sp-head"><h3>成交</h3><span class="faint" style="font-size:12px">币安 · 3 分钟前同步</span></div>
      <div class="scroll" style="flex:1;min-height:0">${trades.length ? trades.slice().reverse().map(t => {
        const s = sym(t.symbol)
        return `<div class="list-row" data-trade="${t.id}" style="cursor:pointer">${badge(s, 'lg')}<div class="main"><div class="t1">${s?.code}<span class="dir ${t.side}">${t.side === 'long' ? '多' : '空'}</span><span class="num ${t.pnl >= 0 ? 'up' : 'down'}" style="margin-left:auto">${t.pnl >= 0 ? '+' : ''}${t.pnl.toFixed(2)}</span></div>
        <div class="t2 num">${shTime(t.entryT)} → ${shTime(t.exitT, false)} · ${F.fmt(t.entry, s?.dec ?? 2)} → ${F.fmt(t.exit, s?.dec ?? 2)}</div></div></div>`
      }).join('') : `<div class="empty">正在拉取…</div>`}</div>`
  }

  // ------------------------------------------------------------ 搜索
  function openSearch(initial = '') {
    if (dialogs.some(d => d.dlg.classList.contains('search-dlg'))) return
    let cat = 'all', q = initial, activeIdx = 0, results = []
    const d = dialog(`<div class="search-top">${I('search', 'icon-24')}<input id="sq" placeholder="搜索品种，比如 BTC、英伟达、黄金" autocomplete="off" spellcheck="false" aria-label="搜索品种" value="${esc(initial)}"><kbd>Esc</kbd></div>
      <div class="search-cats" role="tablist">${[['all', '全部'], ['crypto', '加密'], ['us', '美股'], ['com', '大宗']].map(([k, l]) => `<button class="chip" data-cat="${k}" aria-pressed="${k === cat}">${l}</button>`).join('')}</div>
      <div class="search-list scroll" id="sl" role="listbox"></div>
      <div class="search-foot"><span><kbd>↑</kbd><kbd>↓</kbd>选择</span><span><kbd>↵</kbd>打开</span><span><kbd>⇧</kbd><kbd>↵</kbd>加自选</span><span><kbd>Tab</kbd>换分类</span><span style="margin-left:auto">结果先按最匹配排，同档按 24h 成交额</span></div>`, 'search-dlg', { label: '搜索品种' })
    const inp = $('#sq', d.dlg), listEl = $('#sl', d.dlg)
    function score(s, qq) {
      if (!qq) return 1
      const code = s.code.toUpperCase(), full = s.symbol.toUpperCase()
      if (code === qq || full === qq) return 5
      if (code.startsWith(qq)) return 4
      if (full.includes(qq)) return 3
      if (s.cn && s.cn.toUpperCase().includes(qq)) return 2
      return 0
    }
    function render() {
      const qq = q.trim().toUpperCase()
      results = [...D.S.symbols.values()].filter(s => cat === 'all' || s.kind === cat).map(s => [score(s, qq), s]).filter(x => x[0] > 0)
        .sort((a, b) => b[0] - a[0] || (qq ? 0 : isWatched(b[1].symbol) - isWatched(a[1].symbol)) || b[1].vol - a[1].vol).slice(0, 80).map(x => x[1])
      activeIdx = Math.min(activeIdx, Math.max(0, results.length - 1))
      const hl = t => qq && t.toUpperCase().startsWith(qq) ? `<mark>${esc(t.slice(0, qq.length))}</mark>${esc(t.slice(qq.length))}` : esc(t)
      listEl.innerHTML = results.length ? results.map((s, i) => `<div class="sr ${i === activeIdx ? 'active' : ''}" role="option" aria-selected="${i === activeIdx}" data-i="${i}">
        ${badge(s, 'lg')}<div><div class="n1">${hl(s.code)}<span class="muted" style="font-weight:400;font-size:12px;margin-left:6px">${s.symbol.slice(s.code.length) || ''}</span></div><div class="n2">${esc(s.cn || '')}${s.cn ? ' · ' : ''}${kindName(s)}</div></div>
        <div class="r num">${priceText(s)}</div><div class="r num ${cls(s.pct)}">${pctText(s.pct)}</div><div class="r num muted">${F.fmtCompact(s.vol)}</div>
        <button class="ibtn sm" data-w="${s.symbol}" aria-label="${isWatched(s.symbol) ? '移出自选' : '加入自选'}" style="color:${isWatched(s.symbol) ? '#F5A623' : ''}">${I(isWatched(s.symbol) ? 'star' : 'starOff')}</button></div>`).join('')
        : `<div class="empty">没有找到「${esc(q)}」<div class="faint" style="font-size:12px;margin-top:4px">代号、中文名都能搜，比如「英伟达」「黄金」</div></div>`
    }
    function move(k) { activeIdx = Math.max(0, Math.min(results.length - 1, activeIdx + k)); render(); $('.sr.active', listEl)?.scrollIntoView({ block: 'nearest' }) }
    inp.addEventListener('input', () => { q = inp.value; activeIdx = 0; render() })
    inp.addEventListener('keydown', e => {
      if (e.key === 'ArrowDown') { e.preventDefault(); move(1) }
      else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1) }
      else if (e.key === 'Enter') { e.preventDefault(); const s = results[activeIdx]; if (!s) return; if (e.shiftKey) { toggleWatch(s.symbol); render() } else { d.close(); openSymbol(s.symbol) } }
      else if (e.key === 'Tab') { e.preventDefault(); const cs = ['all', 'crypto', 'us', 'com']; cat = cs[(cs.indexOf(cat) + (e.shiftKey ? 3 : 1)) % 4]; $$('[data-cat]', d.dlg).forEach(b => b.setAttribute('aria-pressed', b.dataset.cat === cat)); activeIdx = 0; render() }
    })
    d.dlg.addEventListener('click', e => {
      const c = e.target.closest('[data-cat]'); if (c) { cat = c.dataset.cat; $$('[data-cat]', d.dlg).forEach(b => b.setAttribute('aria-pressed', b.dataset.cat === cat)); activeIdx = 0; render(); inp.focus(); return }
      const w = e.target.closest('[data-w]'); if (w) { e.stopPropagation(); toggleWatch(w.dataset.w); render(); inp.focus(); return }
      const r = e.target.closest('.sr'); if (r) { d.close(); openSymbol(results[+r.dataset.i].symbol) }
    })
    listEl.addEventListener('mousemove', e => { const r = e.target.closest('.sr'); if (r && +r.dataset.i !== activeIdx) { activeIdx = +r.dataset.i; $$('.sr', listEl).forEach((x, i) => x.classList.toggle('active', i === activeIdx)) } })
    render(); inp.focus(); inp.setSelectionRange(q.length, q.length)
  }

  // ------------------------------------------------------------ 指标
  function openIndicators() {
    let cat = 'all'
    const rows = [
      ['ma', 'main', 'MA', '均线'], ['ema', 'main', 'EMA', '指数均线'], ['boll', 'main', 'BOLL', '布林带'], ['vol', 'main', '成交量', '叠在主图底部'],
      ['macd', 'sub', 'MACD', '平滑异同移动平均'], ['rsi', 'sub', 'RSI', '相对强弱'], ['kdj', 'sub', 'KDJ', '随机指标'], ['oi', 'sub', '持仓量', '币安 30 天内历史'],
      ['walls', 'flow', '主力订单流', '三家交易所聚合的大单'],
    ]
    const d = dialog(`${head('指标', `<span class="faint" style="font-size:12px">副图最多四个</span>`)}<div class="body"><div class="ind-cats">${[['all', '全部'], ['main', '主图'], ['sub', '副图'], ['flow', '订单流']].map(([k, l]) => `<button data-c="${k}" aria-pressed="${k === cat}">${l}<span class="faint">${k === 'all' ? rows.length : rows.filter(r => r[1] === k).length}</span></button>`).join('')}</div><div class="scroll" id="indList"></div></div>`, 'ind-dlg', { label: '指标' })
    const isOn = id => id === 'walls' ? st.flowOn : ['ma', 'ema', 'boll', 'vol'].includes(id) ? !!st.ind[id] : st.ind.subs.includes(id)
    function render() {
      const full = st.ind.subs.length >= 4
      $('#indList', d.dlg).innerHTML = rows.filter(r => cat === 'all' || r[1] === cat).map(([id, pl, n, sub]) => {
        const on = isOn(id), dis = pl === 'sub' && !on && full
        return `<div class="ind-row ${dis ? 'disabled' : ''}" data-id="${id}" tabindex="0" role="checkbox" aria-checked="${on}" aria-disabled="${dis}" ${dis ? 'data-tip="副图已经有三个了，先关一个"' : ''}>
          <span class="check-box ${on ? 'on' : ''}">${on ? I('check', 'icon-16') : ''}</span><span class="nm">${n}<small>${sub}</small></span>
          <span class="tag">${pl === 'main' ? '主图' : pl === 'sub' ? '副图' : '主图'}</span>
          ${id !== 'vol' && id !== 'oi' ? `<button class="ibtn xs" data-set="${id}" aria-label="参数" data-tip="参数">${I('gear', 'icon-16')}</button>` : '<span style="width:24px"></span>'}</div>`
      }).join('')
    }
    function toggle(id) {
      if (id === 'walls') setFlow(!st.flowOn)
      else if (['ma', 'ema', 'boll', 'vol'].includes(id)) st.ind[id] = !st.ind[id]
      else if (st.ind.subs.includes(id)) st.ind.subs = st.ind.subs.filter(x => x !== id)
      else if (st.ind.subs.length < 4) st.ind.subs = [...st.ind.subs, id]
      else return
      cells.forEach(c => c.chart.setIndicators(st.ind)); save(); render()
    }
    d.dlg.addEventListener('click', e => {
      const c = e.target.closest('[data-c]'); if (c) { cat = c.dataset.c; $$('[data-c]', d.dlg).forEach(b => b.setAttribute('aria-pressed', b.dataset.c === cat)); render(); return }
      const s = e.target.closest('[data-set]'); if (s) { e.stopPropagation(); s.dataset.set === 'walls' ? openFlowSettings() : openParams(s.dataset.set); return }
      const r = e.target.closest('.ind-row'); if (r && r.getAttribute('aria-disabled') !== 'true') toggle(r.dataset.id)
    })
    d.dlg.addEventListener('keydown', e => { if ((e.key === ' ' || e.key === 'Enter') && e.target.classList.contains('ind-row')) { e.preventDefault(); toggle(e.target.dataset.id) } })
    render(); $('.ind-row', d.dlg)?.focus()
  }
  function openParams(id) {
    const cat = TVCatalog[id], p = active().chart.params[id]
    const fields = p.periods ? p.periods.map((v, k) => [`周期 ${k + 1}`, v, 'periods', k]) : Object.entries(p).map(([k, v]) => [{ n: '周期', k: '倍数', fast: '快线', slow: '慢线', signal: '信号线', m1: '平滑 1', m2: '平滑 2' }[k] || k, v, k])
    const d = dialog(`${head(`${cat.name} 参数`)}<div class="dialog-body"><div style="display:grid;grid-template-columns:1fr 1fr;gap:16px">
      ${fields.map((f, i) => `<div class="field"><label for="pf${i}">${f[0]}</label><div class="input-wrap"><input id="pf${i}" class="input num" inputmode="decimal" value="${f[1]}"></div></div>`).join('')}
      </div></div><div class="dialog-foot"><button class="btn ghost" id="pReset" style="margin-right:auto">恢复默认</button><button class="btn ghost" data-close>取消</button><button class="btn primary" id="pOk">应用</button></div>`, 'alert-dlg', { label: cat.name + ' 参数' })
    $('#pf0', d.dlg).select()
    const apply = vals => {
      const np = p.periods ? { periods: vals } : Object.fromEntries(fields.map((f, i) => [f[2], vals[i]]))
      st.params = { ...(st.params || {}), [id]: np }
      cells.forEach(c => c.chart.setParams(id, np)); save(); d.close()
    }
    $('#pOk', d.dlg).onclick = () => {
      const vals = fields.map((f, i) => +$('#pf' + i, d.dlg).value)
      if (vals.some(v => !(v > 0))) return toast('参数要是正数', '', 'info', 1800)
      apply(vals)
    }
    $('#pReset', d.dlg).onclick = () => { const def = cat.params; apply(def.periods ? def.periods.slice() : Object.values(def)) }
    d.dlg.addEventListener('keydown', e => { if (e.key === 'Enter') $('#pOk', d.dlg).click() })
  }

  // ------------------------------------------------------------ 提醒对话框
  function openAlert(price) {
    const cell = active(), c = cfg(cell), s = sym(c.symbol), dec = s?.dec ?? 2
    const last = cell.chart.lastBar()?.c ?? s?.price
    price ??= cell.chart.crossPrice() ?? last
    let kind = 'price'
    const KINDS = [['price', '价格达到'], ['fr', '资金费率'], ['oi', '持仓量变化'], ['wall', '大单出现']]
    const d = dialog(`${head('创建提醒', `<button class="btn ghost sm" id="aAll">全部预警</button>`)}<div class="dialog-body"><div class="form-grid">
      <div class="sym-card">${badge(s, 'lg')}<div style="flex:1"><b>${c.symbol}</b><div class="muted" style="font-size:12px;line-height:16px">${esc(s?.cn || '')} ${kindName(s)}</div></div><div style="text-align:right"><div class="num" style="font-weight:600">${F.fmt(last, dec)}</div><div class="num ${cls(s?.pct)}" style="font-size:12px;line-height:16px">${pctText(s?.pct)}</div></div></div>
      <div class="field"><label>条件</label><div class="seg fill" id="aKind">${KINDS.map(([k, l]) => `<button data-k="${k}" aria-pressed="${k === kind}">${l}</button>`).join('')}</div></div>
      <div id="aVal"></div>
      <div class="field"><label for="aHook">Webhook 地址 <span class="faint" style="font-weight:400">选填</span></label><div style="display:flex;gap:8px"><input id="aHook" class="input" placeholder="https://" spellcheck="false"><button class="btn secondary" id="aTest" style="display:none">发一条测试</button></div></div>
      <div id="aExisting"></div>
      </div></div><div class="dialog-foot"><span class="faint" style="margin-right:auto;font-size:12px;align-self:center">触发一次就结束</span><button class="btn ghost" data-close>取消</button><button class="btn primary" id="aOk">创建</button></div>`, 'alert-dlg', { label: '创建提醒' })
    function renderVal() {
      const v = $('#aVal', d.dlg)
      if (kind === 'price') {
        v.innerHTML = `<div class="field"><label for="aPrice">价格</label><div class="input-wrap"><input id="aPrice" class="input lg num" inputmode="decimal" value="${price.toFixed(dec)}"><span class="suffix">USDT</span></div><div class="hint num" id="aHint"></div></div>`
        const inp = $('#aPrice', d.dlg), hint = () => { const p = +inp.value; $('#aHint', d.dlg).textContent = p > 0 ? `比现价${p >= last ? '高' : '低'} ${Math.abs((p - last) / last * 100).toFixed(2)}%，${p >= last ? '涨' : '跌'}到这里时通知你` : '填一个价格' }
        inp.addEventListener('input', hint); hint(); inp.focus(); inp.select()
      } else if (kind === 'fr') v.innerHTML = `<div class="field"><label>资金费率</label><div style="display:flex;gap:8px"><div class="seg" id="aOp"><button data-op="gt" aria-pressed="true">高于</button><button data-op="lt" aria-pressed="false">低于</button></div><div class="input-wrap" style="flex:1"><input id="aNum" class="input num" value="0.05"><span class="suffix">%</span></div></div><div class="hint">现在 ${s?.fr != null ? (s.fr * 100).toFixed(4) + '%' : '—'}</div></div>`
      else if (kind === 'oi') v.innerHTML = `<div class="field"><label>1 小时内持仓量变化超过</label><div class="input-wrap"><input id="aNum" class="input num" value="5"><span class="suffix">%</span></div><div class="hint">增减都算</div></div>`
      else v.innerHTML = `<div class="field"><label>出现不小于这个金额的大单</label><div class="input-wrap"><input id="aNum" class="input num" value="20"><span class="suffix">M USDT</span></div><div class="hint">三家交易所聚合，合约与现货都算</div></div>`
      $('#aNum', d.dlg)?.focus()
    }
    function renderExisting() {
      const mine = st.alerts.filter(a => a.symbol === c.symbol)
      $('#aExisting', d.dlg).innerHTML = mine.length ? `<div class="field"><label>这只品种还在等的提醒</label><div class="group" style="margin:0">${mine.map(a => `<div class="row" style="min-height:40px;padding:4px 8px 4px 12px"><div class="rl num">${alertDesc(a)}</div><button class="ibtn sm" data-x="${a.id}" aria-label="删除" data-tip="删除">${I('trash', 'icon-16')}</button></div>`).join('')}</div></div>` : ''
    }
    d.dlg.addEventListener('click', e => {
      const k = e.target.closest('#aKind [data-k]'); if (k) { kind = k.dataset.k; $$('#aKind button', d.dlg).forEach(b => b.setAttribute('aria-pressed', b === k)); renderVal() }
      const op = e.target.closest('[data-op]'); if (op) $$('[data-op]', d.dlg).forEach(b => b.setAttribute('aria-pressed', b === op))
      const x = e.target.closest('[data-x]'); if (x) { deleteAlert(x.dataset.x); renderExisting() }
    })
    $('#aAll', d.dlg).onclick = () => { d.close(); st.panel = 'alerts'; st.alertScope = 'all'; save(); renderRail(); renderPanel() }
    const hook = $('#aHook', d.dlg)
    hook.addEventListener('input', () => { $('#aTest', d.dlg).style.display = hook.value.trim() ? '' : 'none' })
    $('#aTest', d.dlg).onclick = () => toast('测试消息已发出', hook.value.trim(), 'link')
    const ok = () => {
      const a = { id: 'a' + Date.now(), symbol: c.symbol, kind, created: Date.now(), webhook: hook.value.trim() || null }
      if (kind === 'price') { const p = +$('#aPrice', d.dlg).value; if (!(p > 0)) return $('#aPrice', d.dlg).focus(); a.price = p; a.dir = p >= last ? 1 : -1 }
      else { const v = +$('#aNum', d.dlg).value; if (!(v > 0 || kind === 'fr')) return $('#aNum', d.dlg).focus(); a.value = v; a.op = $('[data-op][aria-pressed="true"]', d.dlg)?.dataset.op }
      st.alerts.push(a); save(); refreshAlerts(); d.close()
      toast('提醒已创建', `${c.symbol} ${alertDesc(a)}`, 'bell')
    }
    $('#aOk', d.dlg).onclick = ok
    d.dlg.addEventListener('keydown', e => { if (e.key === 'Enter' && e.target.tagName === 'INPUT' && e.target.id !== 'aHook') ok() })
    renderVal(); renderExisting()
  }

  // ------------------------------------------------------------ 登录
  function openLogin(then) {
    let mode = 'login'
    const d = dialog(`<div class="login-dlg"><span>${I('logo', 'mark')}</span><h2 id="lgT">登录 Hkline</h2><p id="lgP">自选、画线、提醒在手机和电脑之间同步</p>
      <div class="form-grid"><div class="field"><label for="lgU">用户名</label><input id="lgU" class="input lg" autocomplete="username" spellcheck="false"></div>
      <div class="field"><label for="lgPw">密码</label><input id="lgPw" type="password" class="input lg" autocomplete="current-password"></div>
      <div class="err" id="lgE" role="alert"></div>
      <button class="btn primary lg" id="lgOk" style="width:100%">登录</button>
      <div style="text-align:center;color:var(--text-2)"><span id="lgSw1">还没有账号？</span><button class="btn ghost sm" id="lgSw" style="color:var(--accent-text)">注册</button></div></div></div>`, '', { center: true, label: '登录' })
    const u = $('#lgU', d.dlg), p = $('#lgPw', d.dlg); u.focus()
    $('#lgSw', d.dlg).onclick = () => { mode = mode === 'login' ? 'reg' : 'login'; $('#lgT', d.dlg).textContent = mode === 'login' ? '登录 Hkline' : '注册 Hkline'; $('#lgOk', d.dlg).textContent = mode === 'login' ? '登录' : '注册并登录'; $('#lgSw1', d.dlg).textContent = mode === 'login' ? '还没有账号？' : '已经有账号？'; $('#lgSw', d.dlg).textContent = mode === 'login' ? '注册' : '登录'; $('#lgE', d.dlg).textContent = '' }
    const ok = () => {
      if (!/^[A-Za-z0-9_]{3,20}$/.test(u.value)) { $('#lgE', d.dlg).textContent = '用户名是 3–20 位字母、数字或下划线'; return u.focus() }
      if (p.value.length < 6) { $('#lgE', d.dlg).textContent = '密码至少 6 位'; return p.focus() }
      st.loggedIn = true; st.user = u.value; save(); d.close(); renderHeader(); App.onLogin?.forEach(f => f()); renderPanel()
      toast(mode === 'login' ? `欢迎回来，${u.value}` : '注册好了', '这台电脑算「电脑」一类设备；同类的另一台会被挤下线', 'user'); then?.()
    }
    $('#lgOk', d.dlg).onclick = ok
    d.dlg.addEventListener('keydown', e => { if (e.key === 'Enter') ok() })
  }

  // ------------------------------------------------------------ 快捷键
  const SHORTCUTS = [
    ['品种与周期', [['直接打字母', '搜索品种'], ['⌘ K', '搜索品种'], ['直接打数字', '换周期（如 15、240、1D）'], ['↑ ↓', '自选里上一只 / 下一只'], ['⇧ ↵', '在搜索里加自选']]],
    ['图表', [['滚轮', '缩放（以光标为中心）'], ['拖动', '平移'], ['← →', '平移一根（⇧ 十根）'], ['拖价格轴', '缩放价格'], ['双击价格轴', '价格回到自动'], ['Alt R', '重置视图'], ['右键', '在这里建提醒、画线、记一笔'], ['/', '指标']]],
    ['画线', [['Alt T', '趋势线'], ['Alt H', '水平线'], ['Alt V', '垂直线'], ['Alt F', '斐波那契回撤'], ['Alt ⇧ R', '矩形'], ['⇧ 拖', '临时测量'], ['Delete', '删除选中的画线'], ['Esc', '取消 / 回到光标'], ['⌘ Z / ⌘ ⇧ Z', '撤销 / 重做']]],
    ['其它', [['Alt A', '在现价（或十字线价位）建提醒'], ['⌥ S', '保存截图'], ['⇧ F', '全屏'], ['?', '这张表']]],
  ]
  function kbdHTML(s) { return s.split(' ').map(k => /^[直拖滚双右]/.test(k) ? `<span class="muted">${k}</span>` : k === '/' && s.includes('⌘') ? ' / ' : `<kbd>${k}</kbd>`).join(' ') }
  function openShortcuts() {
    dialog(`${head('快捷键')}<div class="dialog-body"><div style="display:grid;grid-template-columns:1fr 1fr;gap:8px 48px">${SHORTCUTS.map(([h, rows]) => `<div><div class="group-title" style="margin-top:8px">${h}</div><table class="kbd-table">${rows.map(([k, v]) => `<tr><td>${kbdHTML(k)}</td><td class="muted">${v}</td></tr>`).join('')}</table></div>`).join('')}</div></div>`, '', { label: '快捷键' }).dlg.style.width = '880px'
  }

  // ------------------------------------------------------------ 周期快输
  let ivPop = null
  function ivInput(ch) {
    if (!ivPop) { ivPop = { buf: '', el: document.createElement('div') }; ivPop.el.className = 'interval-pop'; document.body.appendChild(ivPop.el) }
    ivPop.buf += ch
    clearTimeout(ivPop.timer); ivPop.timer = setTimeout(() => ivCommit(), 2200)
    const iv = ivParse(ivPop.buf)
    ivPop.el.classList.toggle('bad', !iv)
    ivPop.el.innerHTML = `<div class="v num">${esc(ivPop.buf)}</div><div class="h">${iv ? `${D.IV_LABEL[iv]} · 回车切换` : ivPop.buf.match(/^\d+$/) ? '没有这个周期，接着打或按 Esc' : '只有 1 3 5 15 30 分，1 2 4 6 8 12 小时，日 周 月'}</div>`
  }
  function ivParse(b) {
    const m = b.match(/^(\d+)([mhdwMHDW]?)$/); if (!m) return null
    const n = +m[1], u = m[2]
    let min
    if (!u || u === 'm') min = n
    else if (/h/i.test(u)) min = n * 60
    else if (/d/i.test(u)) min = n * 1440
    else if (/w/i.test(u)) min = n * 10080
    else if (u === 'M') min = n * 43200
    return Object.keys(D.IV_MS).find(k => D.IV_MS[k] === min * 60e3 || (k === '1M' && min === 43200)) || null
  }
  function ivCommit(apply = true) {
    if (!ivPop) return
    const iv = ivParse(ivPop.buf)
    ivPop.el.remove(); clearTimeout(ivPop.timer); ivPop = null
    if (apply && iv) setInterval_(iv)
  }

  // ------------------------------------------------------------ 全局键盘
  addEventListener('keydown', e => {
    const tag = e.target.tagName
    const typing = tag === 'INPUT' || tag === 'TEXTAREA' || e.target.isContentEditable
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); return openSearch() }
    if (dialogs.length || typing) return
    if (openMenuEl) { if (e.key === 'Escape') closeMenu(); return }
    if (ivPop) {
      if (e.key === 'Enter') { e.preventDefault(); return ivCommit() }
      if (e.key === 'Escape') return ivCommit(false)
      if (e.key === 'Backspace') { ivPop.buf = ivPop.buf.slice(0, -1); if (!ivPop.buf) return ivCommit(false); ivPop.buf = ivPop.buf.slice(0, -1); return ivInput(ivPop.buf.slice(-1) ? '' : '') || ivInput('') }
      if (/^[0-9mhdwMHDW]$/.test(e.key)) { e.preventDefault(); return ivInput(e.key) }
      return
    }
    if (st.page !== 'chart') {
      if (e.key === '?') openShortcuts()
      return
    }
    const cell = active()
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z') { e.preventDefault(); return e.shiftKey ? redo() : undo() }
    if (e.metaKey || e.ctrlKey) return
    if (e.altKey) {
      const map = { KeyT: 'trend', KeyH: 'hline', KeyV: 'vline', KeyF: 'fib' }
      if (e.code === 'KeyR' && e.shiftKey) { e.preventDefault(); return selectTool('rect') }
      if (map[e.code]) { e.preventDefault(); return selectTool(map[e.code]) }
      if (e.code === 'KeyA') { e.preventDefault(); return openAlert() }
      if (e.code === 'KeyR') { e.preventDefault(); return cell.chart.resetView() }
      if (e.code === 'KeyS') { e.preventDefault(); return screenshot() }
      return
    }
    if (e.key === 'Escape') { if (cell.chart.cancelDraft()) return; if (tool) return selectTool(null); if (cell.chart.selected) { cell.chart.selected = null; cell.chart.dirty = true; showDrawProps(null) } return }
    if (e.key === 'Delete' || e.key === 'Backspace') { if (cell.chart.deleteSelected()) e.preventDefault(); return }
    if (e.key === '?') return openShortcuts()
    if (e.key === '/') { e.preventDefault(); return openIndicators() }
    if (e.key === 'F' && e.shiftKey) return fullscreen()
    if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') { e.preventDefault(); cell.chart.scrollBars((e.key === 'ArrowLeft' ? -1 : 1) * (e.shiftKey ? 10 : 1)); return }
    if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
      e.preventDefault()
      const list = st.watch[st.watchTab]; if (!list.length) return
      const i = list.indexOf(cfg(cell).symbol)
      const n = i < 0 ? 0 : (i + (e.key === 'ArrowDown' ? 1 : -1) + list.length) % list.length
      openSymbol(list[n]); $(`#wTbl tr[data-sym="${list[n]}"]`)?.scrollIntoView({ block: 'nearest' })
      return
    }
    if (e.key === '+' || e.key === '=') return cell.chart.zoom(1.25)
    if (e.key === '-') return cell.chart.zoom(0.8)
    if (/^[0-9]$/.test(e.key)) { e.preventDefault(); return ivInput(e.key) }
    if (/^[a-zA-Z]$/.test(e.key)) { e.preventDefault(); return openSearch(e.key.toUpperCase()) }
  })

  // ------------------------------------------------------------ 实时
  function refreshStreams() {
    const set = new Set()
    for (const c of st.cells.slice(0, cells.length)) { set.add(`${c.symbol.toLowerCase()}@kline_${c.iv}`); set.add(`${c.symbol.toLowerCase()}@ticker`) }
    const a = cfg(active()); if (a) set.add(`${a.symbol.toLowerCase()}@markPrice@1s`)
    for (const k of st.watch[st.watchTab]) set.add(`${k.toLowerCase()}@ticker`)
    for (const k of new Set(st.alerts.map(x => x.symbol))) set.add(`${k.toLowerCase()}@ticker`)
    App.extraStreams?.forEach(fn => fn().forEach(x => set.add(x)))
    D.setStreams([...set])
  }
  let pendingTick = new Map(), tickRAF = 0
  D.on(e => {
    if (e.type === 'kline') cells.forEach(c => { const cc = cfg(c); if (cc.symbol === e.symbol && cc.iv === e.iv && !st.stale) c.chart.updateBar({ ...e.bar }) })
    if (e.type === 'ticker') {
      pendingTick.set(e.symbol, e.dir); checkAlerts(e.symbol)
      if (!tickRAF) tickRAF = requestAnimationFrame(flushTicks)
    }
    if (e.type === 'oi') cells.forEach(c => c.chart.recalc())
    if (e.type === 'ws') updateStale()
  })
  function flushTicks() {
    tickRAF = 0
    for (const [k, dir] of pendingTick) {
      const tr = $(`#wTbl tr[data-sym="${k}"]`), s = sym(k)
      if (tr && s) {
        const p = $('[data-f="price"]', tr), pc = $('[data-f="pct"]', tr)
        p.textContent = priceText(s); pc.textContent = pctText(s.pct); pc.className = `num ${cls(s.pct)} price-live`
        if (dir) { p.classList.remove('flash-up', 'flash-down'); void p.offsetWidth; p.classList.add(dir > 0 ? 'flash-up' : 'flash-down') }
      }
      if (k === cfg(active())?.symbol) {
        const big = $('#detail [data-f="big"]'), chg = $('#detail [data-f="chg"]')
        if (big) { big.textContent = priceText(s); big.className = `big num price-live ${cls(s.pct)}` }
        if (chg) { chg.textContent = `${s.chg >= 0 ? '+' : ''}${F.fmt(s.chg, s.dec)}  ${pctText(s.pct)}`; chg.className = `chg num ${cls(s.pct)}` }
        document.title = `${s.code} ${priceText(s)} ${pctText(s.pct)} · Hkline`
      }
    }
    pendingTick.clear()
    App.onTicks?.forEach(f => f())
  }
  let staleTimer = null
  function updateStale() {
    const bad = D.S.forcedOffline || D.S.wsState === 'closed'
    clearTimeout(staleTimer)
    if (bad) staleTimer = setTimeout(() => setStale(true), D.S.forcedOffline ? 0 : 5000)
    else setStale(false)
  }
  function setStale(on) {
    if (st.stale === on) return
    st.stale = on
    document.body.classList.toggle('stale', on)
    cells.forEach(c => c.chart.setStale(on))
    App.onStale?.forEach(f => f(on))
  }
  // 每秒：钟、倒计时
  setInterval(() => {
    const d = F.sh(Date.now()), t = `${F.pad(d.getUTCHours())}:${F.pad(d.getUTCMinutes())}:${F.pad(d.getUTCSeconds())} UTC+8`
    $$('.cell-foot .clock').forEach(e => e.textContent = t)
    cells.forEach(c => c.chart.dirty = true)
    const s = sym(cfg(active())?.symbol || ''), cd = $('#detail [data-f="cd"]')
    if (cd && s?.nextFunding) cd.textContent = countdown(s.nextFunding - Date.now())
  }, 1000)

  // ------------------------------------------------------------ 头部
  function renderHeader() {
    const av = $('#hdrAvatar')
    av.className = 'avatar' + (st.loggedIn ? '' : ' out')
    av.innerHTML = st.loggedIn ? esc((st.user || 'M')[0].toUpperCase()) : I('user', 'icon-16')
    av.dataset.tip = st.loggedIn ? `我的 · ${st.user}` : '登录'
  }
  $('#hdrAvatar').onclick = () => st.loggedIn ? go('me') : openLogin()
  $('#hdrTheme').onclick = () => { st.theme = st.theme === 'dark' ? 'light' : 'dark'; save(); applyTheme() }
  $('#hdrAlerts').onclick = () => { go('chart'); st.panel = 'alerts'; save(); renderRail(); renderPanel() }
  $('#searchTrigger').onclick = () => openSearch()
  $$('.nav a').forEach(a => a.addEventListener('click', e => { e.preventDefault(); go(a.dataset.page) }))

  // ------------------------------------------------------------ 启动
  async function boot() {
    hydrateIcons()
    const qs = new URLSearchParams(location.search)
    if (qs.get('theme')) st.theme = qs.get('theme')
    if (['sage', 'terra', 'classic'].includes(qs.get('skin'))) st.skin = qs.get('skin')
    if (qs.get('s')) st.cells[0].symbol = qs.get('s').toUpperCase()
    if (qs.get('i') && D.IV_MS[qs.get('i')]) st.cells[0].iv = qs.get('i')
    if (qs.get('layout')) st.layout = qs.get('layout')
    if (qs.get('panel')) st.panel = qs.get('panel') === 'none' ? null : qs.get('panel')
    applyTheme(); renderHeader(); renderDrawbar(); renderRail()
    go(location.hash.slice(1) || 'chart', false)
    await D.loadUniverse()
    for (const tab of Object.keys(st.watch)) st.watch[tab] = st.watch[tab].filter(k => D.S.symbols.has(k))
    if (!D.S.symbols.has(st.cells[0].symbol)) st.cells[0].symbol = 'BTCUSDT'
    buildCells(); renderToolbar(); renderPanel()
    App.booted?.forEach(f => f())
    if (!D.S.live) toast('连不上行情接口', '现在显示的是演示数据', 'wifiOff', 6000)
  }

  const App = g.App = {
    st, save, $, $$, I, esc, sym, badge, kindName, priceText, pctText, cls, term, toast, menu, menuFrom, dialog, head, go,
    openSearch, openSymbol, openLogin, openAlert, openShortcuts, applyTheme, renderHeader, renderPanel, renderRail, setStale, refreshStreams,
    cells, cfg, active, setInterval_, selectTool, buildCells, renderToolbar, drawingsFor, drawingsChanged, isWatched, toggleWatch, shTime, SHORTCUTS, kbdHTML, GLOSSARY, setFlow,
    onTheme: [], onLogin: [], onStale: [], onTicks: [], pageShown: {}, booted: [], extraStreams: [],
  }
  addEventListener('DOMContentLoaded', boot)
})(window)
