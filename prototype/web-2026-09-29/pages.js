/* Hkline Web · 板块 / 复盘 / 我的 / 规范 四页 + 原型控制台 */
(function (g) {
  'use strict'
  const A = g.App, D = g.KPData, F = g.KPFmt
  const { $, $$, I, esc, sym, badge, term, toast, dialog, head, go, st, save } = A

  // ============================================================ 板块
  const SEC = g.KP_SECTORS
  const sp = { market: 'crypto', sort: 'med', dir: -1, sel: null, msort: 'pct', mdir: -1, chart: null, preview: null }
  const median = a => { if (!a.length) return null; const b = a.slice().sort((x, y) => x - y), m = b.length >> 1; return b.length % 2 ? b[m] : (b[m - 1] + b[m]) / 2 }
  function sectors() {
    const btc = sym('BTCUSDT')?.pct ?? 0
    const list = sp.market === 'crypto'
      ? SEC.crypto.filter(([id]) => id !== '---').map(([id, cn]) => ({ id: 'c:' + id, cn, members: Object.keys(SEC.members).filter(b => SEC.members[b].includes(id)).map(b => b + 'USDT').filter(k => D.S.symbols.has(k)) }))
      : SEC.us.map(([id, cn, codes]) => ({ id: 'u:' + id, cn, members: codes.map(c => c + 'USDT').filter(k => D.S.symbols.has(k)) }))
    return list.filter(s => s.members.length >= 2).map(s => {
      const ps = s.members.map(k => sym(k).pct).filter(x => x != null)
      return { ...s, med: median(ps), beat: ps.filter(p => p > btc).length, n: ps.length, vol: s.members.reduce((a, k) => a + (sym(k).vol || 0), 0), up: ps.filter(p => p > 0).length }
    })
  }
  function renderSectors() {
    const list = sectors()
    const k = sp.sort, d = sp.dir
    list.sort((a, b) => d * ((a[k] ?? -1e9) - (b[k] ?? -1e9)))
    if (!sp.sel || !list.some(s => s.id === sp.sel)) sp.sel = list[0]?.id
    const maxAbs = Math.max(1, ...list.map(s => Math.abs(s.med || 0)))
    const th = (key, l, left) => `<th class="sortable ${left ? 'left' : ''}" data-sort="${key}" aria-sort="${k === key ? (d < 0 ? 'descending' : 'ascending') : 'none'}">${l}${k === key ? `<span class="arrow">${d < 0 ? '↓' : '↑'}</span>` : ''}</th>`
    $('#secList').innerHTML = `<div class="page-head"><h2>板块</h2><span class="sub">${list.length} 个</span><div style="margin-left:auto" class="seg" role="group" aria-label="市场">
        <button data-mk="crypto" aria-pressed="${sp.market === 'crypto'}">加密</button><button data-mk="us" aria-pressed="${sp.market === 'us'}">美股</button></div></div>
      <div class="scroll" style="flex:1;min-height:0"><table class="tbl"><thead><tr>${th('cn', '板块', 1).replace('data-sort="cn"', 'data-sort="n"')}${th('med', term('中位涨跌'))}${th('beat', term('跑赢大盘'))}${th('vol', '成交额')}</tr></thead><tbody>
      ${list.map(s => `<tr data-sec="${s.id}" class="${s.id === sp.sel ? 'sel' : ''}" aria-selected="${s.id === sp.sel}" tabindex="0">
        <td class="left"><b style="font-weight:600">${esc(s.cn)}</b> <span class="faint">${s.n}</span></td>
        <td><div style="display:flex;align-items:center;gap:8px;justify-content:flex-end"><span class="sec-bar" aria-hidden="true"><i style="width:${Math.abs(s.med || 0) / maxAbs * 100}%;background:var(${(s.med || 0) >= 0 ? '--up' : '--down'})"></i></span><span class="num ${A.cls(s.med)}" style="width:64px">${A.pctText(s.med)}</span></div></td>
        <td class="num">${s.beat}<span class="faint"> / ${s.n}</span></td><td class="num muted">${F.fmtCompact(s.vol)}</td></tr>`).join('')}
      </tbody></table></div>`
    renderMembers(list.find(s => s.id === sp.sel))
  }
  function renderMembers(s) {
    const el = $('#secMembers')
    if (!s) { el.innerHTML = '<div class="empty">没有板块</div>'; return }
    const ms = s.members.map(sym)
    const k = sp.msort, d = sp.mdir
    ms.sort((a, b) => d * ((a[k] ?? 0) - (b[k] ?? 0)))
    const th = (key, l) => `<th class="sortable" data-msort="${key}" aria-sort="${k === key ? (d < 0 ? 'descending' : 'ascending') : 'none'}">${l}${k === key ? `<span class="arrow">${d < 0 ? '↓' : '↑'}</span>` : ''}</th>`
    const btc = sym('BTCUSDT')
    el.innerHTML = `<div class="page-head"><h2>${esc(s.cn)}</h2><span class="sub">${s.n} 个品种 · ${s.up} 涨 ${s.n - s.up} 跌 · 跑赢比特币（${A.pctText(btc?.pct)}）的有 ${s.beat} 个</span></div>
      <div class="scroll" style="flex:1;min-height:0"><table class="tbl"><thead><tr><th class="left">品种</th>${th('price', '最新价')}${th('pct', '24h 涨跌')}${th('vol', '成交额')}${th('fr', term('资金费率'))}<th>24 小时</th><th style="width:40px"></th></tr></thead><tbody>
      ${ms.map(m => `<tr data-msym="${m.symbol}" class="${m.symbol === sp.preview ? 'sel' : ''}" tabindex="0">
        <td class="left"><div class="sym">${badge(m)}<b>${m.code}</b><span class="cn">${esc(m.cn || '')}</span></div></td>
        <td class="num">${A.priceText(m)}</td><td class="num ${A.cls(m.pct)}">${A.pctText(m.pct)}</td><td class="num muted">${F.fmtCompact(m.vol)}</td>
        <td class="num ${m.fr > 0 ? '' : m.fr < 0 ? 'down' : ''}">${m.fr == null ? '—' : (m.fr * 100).toFixed(4) + '%'}</td>
        <td><svg class="spark" data-spark="${m.symbol}" viewBox="0 0 96 24" aria-hidden="true">${sparkPath(m)}</svg></td>
        <td><button class="ibtn sm" data-star="${m.symbol}" aria-label="${A.isWatched(m.symbol) ? '移出自选' : '加入自选'}" style="color:${A.isWatched(m.symbol) ? '#F5A623' : ''}">${I(A.isWatched(m.symbol) ? 'star' : 'starOff', 'icon-16')}</button></td></tr>`).join('')}
      </tbody></table></div>`
    loadSparks(ms.slice(0, 40).map(m => m.symbol))
    if (!sp.preview || !s.members.includes(sp.preview)) setPreview(ms[0]?.symbol)
  }
  const sparks = new Map()
  function sparkPath(m) {
    const a = sparks.get(m.symbol); if (!a || a.length < 2) return ''
    const lo = Math.min(...a), hi = Math.max(...a), r = hi - lo || 1
    const pts = a.map((v, i) => `${(i / (a.length - 1) * 94 + 1).toFixed(1)},${(22 - (v - lo) / r * 20).toFixed(1)}`).join(' ')
    return `<polyline points="${pts}" fill="none" stroke="var(${a[a.length - 1] >= a[0] ? '--up' : '--down'})" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/>`
  }
  let sparkQ = [], sparkRunning = 0
  function loadSparks(list) {
    sparkQ = list.filter(k => !sparks.has(k))
    const pump = async () => {
      while (sparkRunning < 6 && sparkQ.length) {
        const k = sparkQ.shift(); sparkRunning++
        D.klines(k, '1h').then(({ bars }) => {
          sparks.set(k, bars.slice(-24).map(b => b.c))
          const el = $(`[data-spark="${k}"]`); if (el) el.innerHTML = sparkPath(sym(k))
        }).finally(() => { sparkRunning--; pump() })
      }
    }
    pump()
  }
  function setPreview(k) {
    if (!k) return
    sp.preview = k
    $$('#secMembers tr[data-msym]').forEach(r => r.classList.toggle('sel', r.dataset.msym === k))
    const s = sym(k), el = $('#secPreview')
    if (!sp.chart) {
      el.innerHTML = `<div class="page-head" id="pvHead"></div><div class="canvas-host" id="pvHost" style="flex:1;min-height:0;position:relative"></div>`
      sp.chart = new TVChart($('#pvHost'), { onActivate() {} })
      sp.chart.setIndicators({ ma: true, ema: false, boll: false, vol: true, subs: [] })
    }
    $('#pvHead').innerHTML = `${badge(s, 'lg')}<div><div style="font-weight:600;line-height:20px">${s.code} <span class="muted" style="font-weight:400">${esc(s.cn || '')}</span></div><div class="num ${A.cls(s.pct)}" style="font-size:12px;line-height:16px">${A.priceText(s)} · ${A.pctText(s.pct)}</div></div>
      <button class="btn primary sm" style="margin-left:auto" id="pvOpen">在图表中打开<kbd style="margin-left:6px;background:transparent;color:inherit;border-color:rgba(255,255,255,.4)">↵</kbd></button>`
    D.klines(k, '1h').then(({ bars }) => { if (sp.preview !== k) return; sp.chart.setData(bars, { symbol: k, iv: D.IV_MS['1h'], title: k, sub: '· 1 小时', dec: s.dec, badge: badge(s) }) })
  }
  A.openSector = id => {
    sp.market = id.startsWith('u:') ? 'us' : 'crypto'; sp.sel = id; sp.preview = null
    go('sectors'); renderSectors()
    $('#secList tr.sel')?.scrollIntoView({ block: 'center' })
  }
  $('#page-sectors').addEventListener('click', e => {
    const t = e.target
    const mk = t.closest('[data-mk]'); if (mk) { sp.market = mk.dataset.mk; sp.sel = null; sp.preview = null; return renderSectors() }
    const so = t.closest('[data-sort]'); if (so && !t.closest('.term')) { const k = so.dataset.sort; sp.dir = sp.sort === k ? -sp.dir : -1; sp.sort = k; return renderSectors() }
    const mso = t.closest('[data-msort]'); if (mso && !t.closest('.term')) { const k = mso.dataset.msort; sp.mdir = sp.msort === k ? -sp.mdir : -1; sp.msort = k; return renderSectors() }
    const star = t.closest('[data-star]'); if (star) { A.toggleWatch(star.dataset.star); return renderSectors() }
    const r = t.closest('[data-sec]'); if (r) { sp.sel = r.dataset.sec; sp.preview = null; $$('#secList tr[data-sec]').forEach(x => { x.classList.toggle('sel', x === r); x.setAttribute('aria-selected', x === r) }); return renderMembers(sectors().find(s => s.id === sp.sel)) }
    const m = t.closest('[data-msym]'); if (m) return setPreview(m.dataset.msym)
    if (t.closest('#pvOpen')) { go('chart'); A.openSymbol(sp.preview) }
  })
  $('#page-sectors').addEventListener('dblclick', e => { const m = e.target.closest('[data-msym]'); if (m) { go('chart'); A.openSymbol(m.dataset.msym) } })
  $('#page-sectors').addEventListener('keydown', e => {
    const r = e.target.closest('tr[data-sec],tr[data-msym]'); if (!r) return
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); const n = e.key === 'ArrowDown' ? r.nextElementSibling : r.previousElementSibling; if (n) { n.focus(); n.click() } }
    if (e.key === 'Enter') { if (r.dataset.msym) { go('chart'); A.openSymbol(r.dataset.msym) } else { r.click(); $('#secMembers tr[data-msym]')?.focus() } }
    if (e.key === 'ArrowRight' && r.dataset.sec) { e.preventDefault(); $('#secMembers tr[data-msym]')?.focus() }
    if (e.key === 'ArrowLeft' && r.dataset.msym) { e.preventDefault(); $('#secList tr.sel')?.focus() }
  })
  A.pageShown.sectors = () => { if (D.S.symbols.size) renderSectors(); sp.chart?.resize() }

  // ============================================================ 复盘
  const rv = { trades: [], sel: null, chart: null, bars: null, sym: 'all', range: '30', i: null, play: false, speed: 1, timer: null }
  async function loadTrades() {
    if (rv.trades.length) return
    const out = []
    for (const k of ['BTCUSDT', 'ETHUSDT']) { const { bars } = await D.klines(k, '1h'); out.push(...D.demoTrades(k, bars, '1h')) }
    rv.trades = out.sort((a, b) => a.exitT - b.exitT)
    rv.trades.forEach((t, i) => t.id = 'r' + i)
  }
  A.reviewTrades = () => rv.trades
  A.openTrade = id => { go('review'); setTimeout(() => selectTrade(id), 50) }
  async function renderReview() {
    const el = $('#page-review')
    if (!st.loggedIn) {
      el.style.gridTemplateColumns = '1fr'
      el.innerHTML = `<div class="card" style="display:grid;place-items:center;grid-column:1/-1;grid-row:1/-1"><div class="empty" style="max-width:420px">${I('trades', 'icon-24')}<div style="font-size:16px;color:var(--text-1);font-weight:600;margin-top:8px">复盘需要登录</div><div style="margin-top:4px">成交从你连上的交易所只读密钥里拉，回合拼接和统计在服务端算</div><button class="btn primary" style="margin-top:16px" id="rvLogin">登录</button></div></div>`
      $('#rvLogin').onclick = () => A.openLogin(() => renderReview())
      return
    }
    el.style.gridTemplateColumns = ''
    await loadTrades()
    const list = rv.trades.filter(t => rv.sym === 'all' || t.symbol === rv.sym)
    const wins = list.filter(t => t.pnl > 0), loss = list.filter(t => t.pnl <= 0)
    const net = list.reduce((a, t) => a + t.pnl, 0), gross = list.reduce((a, t) => a + t.gross, 0), fee = list.reduce((a, t) => a + t.fee, 0)
    const avgW = wins.length ? wins.reduce((a, t) => a + t.pnl, 0) / wins.length : 0, avgL = loss.length ? -loss.reduce((a, t) => a + t.pnl, 0) / loss.length : 0
    const money = v => `${v >= 0 ? '+' : '−'}${Math.abs(v).toLocaleString('en-US', { maximumFractionDigits: 2, minimumFractionDigits: 2 })}`
    const kpis = [
      ['净盈亏', `<span class="${A.cls(net)}">${money(net)}</span>`, `毛利 ${money(gross)} · 手续费 ${fee.toFixed(2)}`],
      ['胜率', `${list.length ? (wins.length / list.length * 100).toFixed(1) : '—'}%`, `${wins.length} 赚 · ${loss.length} 亏`],
      ['盈亏比', avgL ? (avgW / avgL).toFixed(2) : '—', `平均赚 ${avgW.toFixed(2)} · 平均亏 ${avgL.toFixed(2)}`],
      ['每笔期望', `<span class="${A.cls(net)}">${list.length ? money(net / list.length) : '—'}</span>`, 'USDT / 回合'],
      ['费用占毛利', gross > 0 ? `${(fee / gross * 100).toFixed(1)}%` : '—', gross > 0 && fee / gross > .3 ? '偏高，交易可能太频繁' : '在合理范围'],
      ['回合', list.length, `平均持仓 ${F.durText(list.reduce((a, t) => a + t.exitT - t.entryT, 0) / Math.max(1, list.length))}`],
    ]
    el.innerHTML = `<div class="card" style="grid-column:1/3">
        <div class="rv-head"><h2>复盘</h2><span class="muted">币安 · 3 分钟前同步</span>
          <div class="rv-filters"><div class="seg" role="group" aria-label="品种">${[['all', '全部'], ['BTCUSDT', 'BTC'], ['ETHUSDT', 'ETH']].map(([k, l]) => `<button data-rsym="${k}" aria-pressed="${rv.sym === k}">${l}</button>`).join('')}</div>
          <div class="seg" role="group" aria-label="时间">${[['7', '7 天'], ['30', '30 天'], ['90', '90 天']].map(([k, l]) => `<button data-rrange="${k}" aria-pressed="${rv.range === k}">${l}</button>`).join('')}</div></div>
          <button class="btn secondary sm" style="margin-left:auto" id="rvSync">${I('undo', 'icon-16')}立即同步</button></div>
        <div class="kpis">${kpis.map(([k, v, d]) => `<div class="kpi"><div class="k">${A.GLOSSARY[k] ? term(k) : k}</div><div class="v num">${v}</div><div class="d">${d}</div></div>`).join('')}</div></div>
      <div class="card rv-left"><div class="equity" id="equity"></div>
        <div class="sec-title" style="padding-top:12px">${term('回合', '回合')}<span>${list.length}</span></div>
        <div class="scroll" style="flex:1;min-height:0"><table class="tbl" id="rvTbl"><thead><tr><th class="left">品种</th><th class="left">方向</th><th class="left">开仓（上海时间）</th><th>持仓</th><th>开仓价</th><th>平仓价</th><th>成交笔数</th><th>手续费</th><th>净盈亏</th></tr></thead><tbody>
        ${list.slice().reverse().map(t => { const s = sym(t.symbol); return `<tr data-rt="${t.id}" tabindex="0" class="${t.id === rv.sel ? 'sel' : ''}">
          <td class="left"><div class="sym">${badge(s)}<b>${s.code}</b></div></td><td class="left"><span class="dir ${t.side}">${t.side === 'long' ? '多' : '空'}</span></td>
          <td class="left num muted">${A.shTime(t.entryT)}</td><td class="num">${F.durText(t.exitT - t.entryT)}</td>
          <td class="num">${F.fmt(t.entry, s.dec)}</td><td class="num">${F.fmt(t.exit, s.dec)}</td><td class="num muted">${t.fills}</td><td class="num muted">${t.fee.toFixed(2)}</td>
          <td class="num ${A.cls(t.pnl)}" style="font-weight:600">${money(t.pnl)}</td></tr>` }).join('')}</tbody></table></div></div>
      <div class="card rv-right"><div class="rv-trade-head" id="rvTH"></div><div class="canvas-host" id="rvHost" style="flex:1;min-height:0;position:relative"></div>
        <div class="replay-bar" id="rvBar"></div><div class="rv-trade-stats" id="rvStats"></div></div>`
    drawEquity(list)
    rv.chart?.destroy(); rv.chart = new TVChart($('#rvHost'), { onActivate() {} })
    rv.chart.setIndicators({ ma: true, ema: false, boll: false, vol: true, subs: [] })
    selectTrade(rv.sel && list.some(t => t.id === rv.sel) ? rv.sel : list[list.length - 1]?.id)
  }
  function drawEquity(list) {
    const el = $('#equity'), W = el.clientWidth, H = el.clientHeight, P = { l: 64, r: 16, t: 36, b: 16 }
    let c = 0; const pts = [0, ...list.map(t => (c += t.pnl))]
    const lo = Math.min(0, ...pts), hi = Math.max(0, ...pts), r = hi - lo || 1
    const x = i => P.l + i / Math.max(1, pts.length - 1) * (W - P.l - P.r), y = v => P.t + (hi - v) / r * (H - P.t - P.b)
    const ticks = [hi, (hi + lo) / 2, lo]
    const up = pts[pts.length - 1] >= 0
    el.innerHTML = `<svg width="${W}" height="${H}" role="img" aria-label="累计净盈亏曲线，最新 ${pts[pts.length - 1].toFixed(2)} USDT">
      <text x="16" y="20" fill="var(--text-2)" font-size="12">累计净盈亏（USDT）</text>
      ${ticks.map(v => `<line x1="${P.l}" x2="${W - P.r}" y1="${y(v)}" y2="${y(v)}" stroke="var(--line)"/><text x="${P.l - 8}" y="${y(v) + 4}" text-anchor="end" font-size="11" fill="var(--text-3)" font-family="var(--font-num)">${v.toFixed(0)}</text>`).join('')}
      <line x1="${P.l}" x2="${W - P.r}" y1="${y(0)}" y2="${y(0)}" stroke="var(--line-strong)" stroke-dasharray="3 3"/>
      <path d="M${x(0)},${y(0)} ${pts.map((v, i) => `L${x(i)},${y(v)}`).join(' ')} L${x(pts.length - 1)},${y(0)} Z" fill="var(${up ? '--up' : '--down'})" opacity=".08"/>
      <polyline points="${pts.map((v, i) => `${x(i)},${y(v)}`).join(' ')}" fill="none" stroke="var(${up ? '--up' : '--down'})" stroke-width="2" stroke-linejoin="round"/>
      ${list.map((t, i) => `<circle cx="${x(i + 1)}" cy="${y(pts[i + 1])}" r="${t.id === rv.sel ? 5 : 3}" fill="var(--surface)" stroke="var(${t.pnl >= 0 ? '--up' : '--down'})" stroke-width="2" data-rt="${t.id}" style="cursor:pointer"><title>${A.shTime(t.exitT)} ${t.pnl.toFixed(2)}</title></circle>`).join('')}
    </svg>`
  }
  async function selectTrade(id) {
    const t = rv.trades.find(x => x.id === id); if (!t) return
    stopPlay(); rv.sel = id
    $$('#rvTbl tr[data-rt]').forEach(r => r.classList.toggle('sel', r.dataset.rt === id))
    $$('#equity circle').forEach(c => c.setAttribute('r', c.dataset.rt === id ? 5 : 3))
    const s = sym(t.symbol)
    $('#rvTH').innerHTML = `${badge(s, 'lg')}<div class="ttl">${s.code} <span class="dir ${t.side}">${t.side === 'long' ? '做多' : '做空'}</span></div><span class="muted num">${A.shTime(t.entryT)} → ${A.shTime(t.exitT)}</span>
      <button class="btn ghost sm" style="margin-left:auto" id="rvOpen">在图表中打开</button>`
    const { bars } = await D.klines(t.symbol, '1h')
    rv.bars = bars
    rv.chart.setData(bars, { symbol: t.symbol, iv: D.IV_MS['1h'], title: t.symbol, sub: '· 1 小时 · 回放', dec: s.dec, badge: badge(s) })
    rv.chart.setMarkers([t])
    const ie = rv.chart.indexAt(t.entryT), ix = rv.chart.indexAt(t.exitT)
    rv.i0 = Math.max(0, Math.round(ie) - 60); rv.i1 = Math.min(bars.length - 1, Math.round(ix) + 20); rv.ie = Math.round(ie); rv.ix = Math.round(ix)
    rv.i = rv.i1
    rv.chart.setReplay(null)
    rv.chart.setVisibleRange(bars[rv.i0].t, bars[rv.i1].t)
    renderBar(); renderTradeStats(t)
  }
  function renderBar() {
    const span = rv.i1 - rv.i0, pos = i => (i - rv.i0) / span * 100
    $('#rvBar').innerHTML = `<button class="ibtn sm" id="rvPlay" aria-label="${rv.play ? '暂停' : '播放'}" data-tip="${rv.play ? '暂停' : '从开仓前开始回放'}" data-kbd="空格">${I(rv.play ? 'pause' : 'play')}</button>
      <div class="seg" role="group" aria-label="速度">${[1, 2, 4].map(v => `<button data-spd="${v}" aria-pressed="${rv.speed === v}">${v}×</button>`).join('')}</div>
      <div class="track" id="rvTrack" role="slider" tabindex="0" aria-label="回放进度" aria-valuemin="${rv.i0}" aria-valuemax="${rv.i1}" aria-valuenow="${rv.i}">
        <div class="rail-line"></div><div class="fill" style="width:${pos(rv.i)}%"></div>
        <div class="mk" style="left:${pos(rv.ie)}%;background:var(--accent)" data-tip="开仓"></div><div class="mk" style="left:${pos(rv.ix)}%;background:var(--warn)" data-tip="平仓"></div>
        <div class="knob" style="left:${pos(rv.i)}%"></div></div>
      <button class="btn ghost sm" data-jump="ie">开仓</button><button class="btn ghost sm" data-jump="ix">平仓</button>
      <span class="num muted" style="width:120px;text-align:right">${rv.bars ? A.shTime(rv.bars[rv.i].t) : ''}</span>`
  }
  function setReplayIdx(i) {
    rv.i = Math.max(rv.i0, Math.min(rv.i1, i))
    rv.chart.setReplay(rv.i >= rv.i1 ? null : rv.i)
    const span = rv.i1 - rv.i0, p = (rv.i - rv.i0) / span * 100
    $('#rvTrack .fill').style.width = p + '%'; $('#rvTrack .knob').style.left = p + '%'
    $('#rvTrack').setAttribute('aria-valuenow', rv.i)
    $('#rvBar .num').textContent = A.shTime(rv.bars[rv.i].t)
  }
  function startPlay() {
    if (rv.i >= rv.i1) setReplayIdx(rv.i0)
    rv.play = true; renderBar(); setReplayIdx(rv.i)
    const tick = () => { if (!rv.play) return; if (rv.i >= rv.i1) return stopPlay(); setReplayIdx(rv.i + 1); rv.timer = setTimeout(tick, 400 / rv.speed) }
    rv.timer = setTimeout(tick, 400 / rv.speed)
  }
  function stopPlay() { clearTimeout(rv.timer); if (rv.play) { rv.play = false; if ($('#rvBar')) { renderBar() } } }
  function renderTradeStats(t) {
    const s = sym(t.symbol), bars = rv.bars.slice(rv.ie, rv.ix + 1)
    const hi = Math.max(...bars.map(b => b.h)), lo = Math.min(...bars.map(b => b.l))
    const mfe = t.side === 'long' ? (hi - t.entry) / t.entry : (t.entry - lo) / t.entry
    const mae = t.side === 'long' ? (lo - t.entry) / t.entry : (t.entry - hi) / t.entry
    const cap = mfe > 0 ? ((t.side === 'long' ? t.exit - t.entry : t.entry - t.exit) / t.entry) / mfe : 0
    $('#rvStats').innerHTML = [
      ['净盈亏', `<span class="${A.cls(t.pnl)}">${t.pnl >= 0 ? '+' : ''}${t.pnl.toFixed(2)}</span>`],
      ['持仓中最多浮盈', `<span class="up">+${(mfe * 100).toFixed(2)}%</span>`],
      ['持仓中最多浮亏', `<span class="down">${(mae * 100).toFixed(2)}%</span>`],
      ['吃到了浮盈的', `${Math.max(0, cap * 100).toFixed(0)}%`],
    ].map(([k, v]) => `<div><div class="faint" style="font-size:12px;line-height:16px">${k}</div><div class="num" style="font-size:16px;line-height:24px;font-weight:600">${v}</div></div>`).join('')
  }
  $('#page-review').addEventListener('click', e => {
    const t = e.target
    const r = t.closest('[data-rt]'); if (r) return selectTrade(r.dataset.rt)
    const f = t.closest('[data-rsym]'); if (f) { rv.sym = f.dataset.rsym; return renderReview() }
    const rg = t.closest('[data-rrange]'); if (rg) { rv.range = rg.dataset.rrange; return renderReview() }
    if (t.closest('#rvSync')) return toast('已同步', '没有新的成交', 'check', 1800)
    if (t.closest('#rvPlay')) return rv.play ? stopPlay() : startPlay()
    const sp_ = t.closest('[data-spd]'); if (sp_) { rv.speed = +sp_.dataset.spd; $$('[data-spd]').forEach(b => b.setAttribute('aria-pressed', b === sp_)); return }
    const j = t.closest('[data-jump]'); if (j) { stopPlay(); return setReplayIdx(rv[j.dataset.jump] + (j.dataset.jump === 'ie' ? 0 : 0)) }
    if (t.closest('#rvOpen')) { const tr = rv.trades.find(x => x.id === rv.sel); go('chart'); A.openSymbol(tr.symbol) }
  })
  // 进度线：拖动定位（不给逐根步进）
  $('#page-review').addEventListener('pointerdown', e => {
    const tr = e.target.closest('#rvTrack'); if (!tr) return
    stopPlay()
    const rect = tr.getBoundingClientRect()
    const at = x => setReplayIdx(Math.round(rv.i0 + Math.max(0, Math.min(1, (x - rect.left) / rect.width)) * (rv.i1 - rv.i0)))
    at(e.clientX); tr.setPointerCapture(e.pointerId)
    const mv = ev => at(ev.clientX), up = () => { tr.removeEventListener('pointermove', mv); tr.removeEventListener('pointerup', up) }
    tr.addEventListener('pointermove', mv); tr.addEventListener('pointerup', up)
  })
  $('#page-review').addEventListener('keydown', e => {
    if (e.target.id === 'rvTrack' && (e.key === 'Home' || e.key === 'End')) { e.preventDefault(); setReplayIdx(e.key === 'Home' ? rv.i0 : rv.i1) }
    if (e.key === ' ' && !/INPUT|BUTTON/.test(e.target.tagName)) { e.preventDefault(); rv.play ? stopPlay() : startPlay() }
    const r = e.target.closest('tr[data-rt]')
    if (r && (e.key === 'ArrowDown' || e.key === 'ArrowUp')) { e.preventDefault(); const n = e.key === 'ArrowDown' ? r.nextElementSibling : r.previousElementSibling; if (n) { n.focus(); selectTrade(n.dataset.rt) } }
  })
  A.pageShown.review = () => renderReview()
  addEventListener('resize', () => { if (st.page === 'review' && rv.trades.length) drawEquity(rv.trades.filter(t => rv.sym === 'all' || t.symbol === rv.sym)) })

  // ============================================================ 我的
  const ME = [['account', 'user', '账号'], ['exchange', 'key', '交易所账号'], ['notify', 'bell', '通知'], ['look', 'palette', '外观'], ['general', 'gear', '通用'], ['devices', 'device', '设备'], ['about', 'info', '关于']]
  function renderMe() {
    if (!st.loggedIn && ['account', 'exchange', 'devices'].includes(st.meSection)) st.meSection = 'look'
    $('#meNav').innerHTML = `<div class="who"><span class="avatar ${st.loggedIn ? '' : 'out'}">${st.loggedIn ? esc(st.user[0].toUpperCase()) : I('user', 'icon-16')}</span><div><div style="font-weight:600">${st.loggedIn ? esc(st.user) : '未登录'}</div><div class="muted" style="font-size:12px;line-height:16px">${st.loggedIn ? '这台电脑 · 在线' : '登录后自选与画线跨设备同步'}</div></div></div>
      ${ME.map(([k, ic, l]) => `<a href="#me" data-me="${k}" ${st.meSection === k ? 'aria-current="page"' : ''}>${I(ic)}${l}</a>`).join('')}
      <div style="flex:1"></div>${st.loggedIn ? `<a href="#me" data-me="logout">${I('logout')}退出登录</a>` : `<button class="btn primary" id="meLogin">登录</button>`}`
    const row = (t, d, ctl) => `<div class="row"><div class="rl"><div class="t">${t}</div>${d ? `<div class="d">${d}</div>` : ''}</div>${ctl}</div>`
    const sw = (k, on, l) => `<button class="switch" role="switch" data-sw="${k}" aria-checked="${on}" aria-label="${l}"></button>`
    const seg = (k, v, opts) => `<div class="seg" role="group">${opts.map(([x, l]) => `<button data-seg="${k}" data-v="${x}" aria-pressed="${v === x}">${l}</button>`).join('')}</div>`
    const body = {
      account: () => `<h2>账号</h2><p class="lede">自选、画线、提醒、指标参数跟着账号走，手机和电脑之间实时同步；服务器断了本机照常能用。</p>
        <div class="group">${row('用户名', '', `<span class="muted">${esc(st.user)}</span>`)}${row('密码', '上次修改 32 天前', '<button class="btn secondary sm">修改密码</button>')}${row('同步', '上次同步 刚刚 · 自选 23 · 画线 41 · 提醒 ' + st.alerts.length, '<span class="tag accent">正常</span>')}</div>`,
      exchange: () => `<h2>交易所账号</h2><p class="lede">只读密钥，只用来拉成交做复盘。不能下单、不能提币。</p>
        <div class="group">${row(`${badge({ base: 'BN', color: '#F0B90B' }, 'lg')}<span style="margin-left:12px">币安</span>`.replace('<div class="t">', ''), '只读 · 3 分钟前同步 · 近 90 天 214 笔成交', '<button class="btn ghost sm">断开</button>')}${row('OKX', '还没连', '<button class="btn secondary sm">连接只读密钥</button>')}</div>`,
      notify: () => `<h2>通知</h2><p class="lede">提醒响一次就结束。浏览器开着时弹系统通知；关着时推到手机。</p>
        <div class="group">${row('浏览器通知', g.Notification ? ({ granted: '已允许', denied: '被浏览器拦了，要在地址栏左边的站点设置里打开', default: '还没问过' }[Notification.permission]) : '这个浏览器不支持', g.Notification?.permission === 'default' ? '<button class="btn secondary sm" id="meNotif">允许</button>' : '')}
        ${row('异动提醒', '自选里的品种 5 分钟内涨跌超过 3%', sw('moveAlert', st.moveAlert, '异动提醒'))}${row('新币上线', '币安上新永续合约时', sw('listing', st.listing, '新币上线'))}</div>`,
      look: () => `<h2>外观</h2><p class="lede">跟手机端分开记，这台电脑自己的选择。</p>
        <div class="group">${row('深浅色', '', seg('theme', st.theme, [['light', '浅色'], ['dark', '深色']]))}${row('涨跌颜色', '', seg('updown', st.updown, [['red-up', '红涨绿跌'], ['green-up', '绿涨红跌']]))}</div>`,
      general: () => `<h2>通用</h2><p class="lede">时间统一用上海时间，不能改；日线在北京时间 8:00 换日。</p>
        <div class="group">${row('行情线路', '只记在这台电脑上。网关走我们自己的服务器，直连连不上时手动切过去', seg('route', st.route, [['direct', '直连'], ['gateway', '网关']]))}
        ${row('按使用习惯自动调整', '比如常看的周期自动钉到栏上、常用的指标默认打开。关掉就一直按你手动设的来', sw('learn', st.learn, '按使用习惯自动调整'))}</div>`,
      devices: () => `<h2>设备</h2><p class="lede">每一类设备同时只能有一台在线：手机、平板、电脑各一台。同类的另一台登录时，这边会被挤下线。</p>
        <div class="group">${row(`${I('device')} 电脑 · 这台 Mac · Chrome`, '在线', '<span class="tag accent">当前</span>')}${row(`${I('device')} 手机 · iPhone 17 Pro Max`, '在线 · 2 分钟前活跃', '<button class="btn ghost sm">让它下线</button>')}${row(`${I('device')} 平板`, '没有', '')}</div>`,
      about: () => `<h2>关于</h2><p class="lede">Hkline 网页版 · 原型 2026-09-29</p><div class="group">${row('设计规范', '字号、间距、颜色、对比度、快捷键', '<button class="btn secondary sm" id="meSpec">查看</button>')}${row('快捷键', '', '<button class="btn secondary sm" id="meKeys">查看</button>')}</div>`,
    }
    $('#meBody').innerHTML = body[st.meSection]()
  }
  $('#page-me').addEventListener('click', e => {
    const t = e.target
    const a = t.closest('[data-me]'); if (a) { e.preventDefault(); if (a.dataset.me === 'logout') { st.loggedIn = false; save(); A.renderHeader(); renderMe(); toast('已退出', '本机缓存还在，下次登录直接接上', 'logout'); return } st.meSection = a.dataset.me; save(); return renderMe() }
    const s = t.closest('[data-sw]'); if (s) { st[s.dataset.sw] = !st[s.dataset.sw]; save(); s.setAttribute('aria-checked', st[s.dataset.sw]); return }
    const sg = t.closest('[data-seg]'); if (sg) {
      st[sg.dataset.seg] = sg.dataset.v; save()
      if (sg.dataset.seg === 'theme' || sg.dataset.seg === 'updown') A.applyTheme()
      if (sg.dataset.seg === 'route') toast(sg.dataset.v === 'gateway' ? '已切到网关' : '已切到直连', '只影响这台电脑', 'link', 1800)
      return renderMe()
    }
    if (t.closest('#meLogin')) return A.openLogin(renderMe)
    if (t.closest('#meSpec')) return go('spec')
    if (t.closest('#meKeys')) return A.openShortcuts()
    if (t.closest('#meNotif')) Notification.requestPermission().then(renderMe)
  })
  A.pageShown.me = renderMe

  // ============================================================ 规范
  function lum(hex) {
    const m = hex.match(/\d+(\.\d+)?/g); if (!m) return 0
    const [r, gg, b] = m.slice(0, 3).map(v => { v = +v / 255; return v <= .03928 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4 })
    return .2126 * r + .7152 * gg + .0722 * b
  }
  function contrast(a, b) { const x = lum(a), y = lum(b); return (Math.max(x, y) + .05) / (Math.min(x, y) + .05) }
  function resolve(varName, theme, updown = 'red-up') {
    const p = document.createElement('div'); p.dataset.theme = theme; p.dataset.updown = updown
    p.style.cssText = `position:absolute;visibility:hidden;color:var(${varName})`
    document.body.appendChild(p); const c = getComputedStyle(p).color; p.remove(); return c
  }
  const toHex = c => { const m = c.match(/\d+/g); return m ? '#' + m.slice(0, 3).map(v => (+v).toString(16).padStart(2, '0')).join('').toUpperCase() : c }
  function renderSpec() {
    const pairs = [
      ['--text-1', '--surface', '正文', 4.5], ['--text-2', '--surface', '次要文字', 4.5], ['--text-3', '--surface', '占位 / 禁用（非正文）', 3], ['--accent-text', '--surface', '链接 / 选中文字', 4.5],
      ['--up-text', '--surface', '涨（文字）', 4.5], ['--down-text', '--surface', '跌（文字）', 4.5], ['--text-1', '--surface-2', '表头 / 次级面板上的正文', 4.5], ['--control-line', '--surface', '输入框 / 开关边界（非文字）', 3],
      ['--chart-axis-text', '--chart-bg', '坐标轴刻度', 4.5], ['--text-2', '--app', '底色上的次要文字', 4.5],
    ]
    const sw = theme => pairs.map(([fg, bg, l, need]) => {
      const f = resolve(fg, theme), b = resolve(bg, theme), r = contrast(f, b)
      return `<div class="sw" data-theme="${theme}"><div class="chipc" style="background:${b};color:${f};display:grid;place-items:center;font-weight:600;font-size:${need === 3 && !l.includes('非') ? 13 : 16}px">${l.includes('边框') ? `<span style="width:80px;height:28px;border:1px solid ${f};border-radius:6px"></span>` : 'Aa 永 12,345.67'}</div>
        <div class="meta" style="background:var(--surface);color:var(--text-1)"><b>${l}</b><span class="muted num">${fg} ${toHex(f)} / ${bg} ${toHex(b)}</span><br><span class="ratio ${r >= 7 ? 'ok' : r >= need ? 'ok' : 'bad'}">${r.toFixed(2)}:1 ${r >= 7 ? 'AAA' : r >= need ? (need === 3 ? 'AA 非文字' : 'AA') : '不达标'}</span></div></div>`
    }).join('')
    const types = [[32, 40, 700, '页标题（仅规范页）'], [24, 32, 600, '页面标题 / 大数字（复盘 KPI）'], [20, 28, 600, '分区标题'], [16, 24, 600, '卡片标题 / 详情价格次级'], [14, 20, 400, '正文、表格、按钮（基准）'], [13, 20, 400, '图例、工具栏按钮'], [12, 16, 400, '说明、表头、坐标轴'], [11, 16, 600, '徽章、标签（只用在非正文）']]
    const spaces = [[4, '--s1', '图标与文字'], [8, '--s2', '控件内部'], [12, '--s3', '同组控件'], [16, '--s4', '卡片内边距（基准）'], [24, '--s6', '分组之间'], [32, '--s8', '页面区块'], [40, '--s10', '大留白']]
    const icons = KPIcon.names
    const cmp = `<div style="display:flex;flex-wrap:wrap;gap:12px;align-items:center">
      <button class="btn primary">主要操作</button><button class="btn secondary">次要操作</button><button class="btn ghost">文字按钮</button><button class="btn danger">删除</button>
      <button class="btn primary" disabled style="opacity:.45">不可用</button><span class="tb-sep"></span>
      <div class="seg"><button aria-pressed="true">选中</button><button aria-pressed="false">未选</button></div>
      <button class="switch" role="switch" aria-checked="true" aria-label="示例开关"></button><button class="switch" role="switch" aria-checked="false" aria-label="示例开关"></button>
      <button class="ibtn" aria-label="图标按钮">${I('gear')}</button><button class="ibtn on" aria-label="已选图标按钮">${I('magnet')}</button>
      <span class="tag">标签</span><span class="tag accent">强调</span><span class="tag spot">现货</span><span class="tag perp">合约</span>
      <input class="input" style="width:200px" placeholder="输入框 32px"><span>${term('资金费率', '带解释的术语')}</span></div>`
    const H = 1440, Wd = 2560, pct = (v, t) => v / t * 100 + '%'
    const box = (x, y, w, h, l, hl) => `<div class="${hl ? 'hl' : ''}" style="left:${pct(x, Wd)};top:${pct(y, H)};width:${pct(w, Wd)};height:${pct(h, H)}">${l}</div>`
    $('#page-spec').innerHTML = `<div class="spec">
      <h1>Hkline 网页版 · 设计规范</h1>
      <p class="lede">目标屏幕 27 英寸 2560 × 1440（约 109 ppi，按 1× 设计）。所有尺寸落在 4 px 网格上；字号成阶梯；每一对前景 / 背景颜色都在下面实时算对比度（按 WCAG 2.2，正文 ≥ 4.5:1、非文字元素 ≥ 3:1）。其它屏幕的适配后续再做。</p>

      <h2>布局 · 2560 × 1440</h2>
      <div class="spec-grid" style="grid-template-columns:2fr 1fr;align-items:start">
        <div class="layout-map">
          ${box(0, 0, 2560, 48, '头部 48 · 导航 / 搜索 ⌘K / 提醒 / 深浅色 / 我的')}
          ${box(4, 52, 2044, 40, '图表工具栏 40')}
          ${box(4, 96, 48, 1340, '画线<br>48')}
          ${box(56, 96, 1992, 1340, 'K 线区 1992 × 1340<br>画布约 1992 × 1308（底部 32 是范围与时钟）', true)}
          ${box(2052, 52, 400, 1384, '侧栏 400<br>自选 / 提醒 / 订单流<br>笔记 / 成交<br>可收起，K 线区变成 2396 宽')}
          ${box(2456, 52, 100, 1384, '图标栏<br>48')}
        </div>
        <div class="group" style="margin:0">${[['头部', '48'], ['工具栏', '40（控件 28–32）'], ['画线栏 / 图标栏', '48 宽，按钮 32 × 32'], ['侧栏', '400 宽'], ['卡片间距', '4（照 TradingView 的紧凑排布，让图更大）'], ['K 线画布', '约 1992 × 1308，一屏 ~200 根'], ['最小点击目标', '24 × 24（WCAG 2.2 2.5.8）；常用按钮 32'], ['对话框', '宽 520 / 760 / 840，居上 12vh']].map(([a, b]) => `<div class="row" style="min-height:40px"><div class="rl"><div class="t">${a}</div></div><span class="num muted">${b}</span></div>`).join('')}</div>
      </div>

      <h2>颜色与对比度 · 浅色</h2>
      <div class="spec-grid" style="grid-template-columns:repeat(5,1fr)">${sw('light')}</div>
      <h2>颜色与对比度 · 深色</h2>
      <div class="spec-grid" style="grid-template-columns:repeat(5,1fr)">${sw('dark')}</div>
      <p class="lede" style="margin-top:12px">K 线蜡烛用 TradingView 的红 #F23645 / 绿 #089981（图形，≥ 3:1 即可）；文字里的涨跌用加深版（上面的「涨 / 跌（文字）」），保证 4.5:1。涨跌颜色可以在「我的 › 外观」对调。涨跌从不只靠颜色表达：数字都带 + / − 号。</p>

      <h2>字号</h2>
      <div>${types.map(([s, lh, w, l]) => `<div class="type-row"><span class="meta num">${s} / ${lh} · ${w}</span><span class="meta">${l}</span><span style="font-size:${s}px;line-height:${lh}px;font-weight:${w}">BTCUSDT 永续 67,432.10 +2.35%</span></div>`).join('')}</div>
      <p class="lede" style="margin-top:12px">数字一律用等宽数字（tabular-nums），价格跳动时不左右抖。中文字体走系统（苹方），数字走 SF / Inter 系。</p>

      <h2>间距 · 圆角 · 控件高度</h2>
      <div class="spec-grid" style="grid-template-columns:1fr 1fr 1fr">
        <div>${spaces.map(([v, k, l]) => `<div class="space-row"><span class="num muted" style="width:72px">${k} ${v}</span><i style="width:${v * 3}px"></i><span class="muted">${l}</span></div>`).join('')}</div>
        <div style="display:flex;gap:16px;align-items:flex-end">${[[4, 'xs 标签'], [6, 'sm 按钮'], [8, 'md 卡片'], [12, 'lg 对话框']].map(([r, l]) => `<div style="text-align:center"><div style="width:72px;height:72px;border-radius:${r}px;background:var(--accent-soft);border:1px solid var(--accent)"></div><div class="muted num" style="font-size:12px;margin-top:4px">${r} · ${l}</div></div>`).join('')}</div>
        <div style="display:flex;gap:12px;align-items:flex-end">${[[24, 'xs 图例'], [28, 'sm 工具栏'], [32, 'md 默认'], [40, 'lg 主要']].map(([h, l]) => `<div style="text-align:center"><button class="btn secondary" style="height:${h}px;padding:0 12px">按钮</button><div class="muted num" style="font-size:12px;margin-top:4px">${h} · ${l}</div></div>`).join('')}</div>
      </div>

      <h2>图标 · 24 网格，实心双色</h2>
      <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(88px,1fr));gap:8px">${icons.map(n => `<div class="sw" style="display:grid;place-items:center;padding:12px 4px;gap:6px">${I(n, 'icon-24')}<span class="muted" style="font-size:11px">${n}</span></div>`).join('')}</div>

      <h2>组件</h2>${cmp}

      <h2>焦点与键盘</h2>
      <p class="lede">用 Tab 走到任何控件都会出现 2 px 强调色焦点环（:focus-visible，鼠标点击时不出现）。对话框打开时焦点锁在里面，Esc 关闭并回到原来的位置。所有图标按钮都有文字标签（aria-label）和悬停提示，常用操作的提示里带快捷键。</p>
      <div style="display:flex;gap:12px;margin-top:16px"><button class="btn secondary" style="outline:2px solid var(--accent);outline-offset:2px">焦点示例</button><button class="ibtn" style="outline:2px solid var(--accent);outline-offset:2px" aria-label="焦点示例">${I('bell')}</button></div>

      <h2>快捷键</h2>
      <div style="display:grid;grid-template-columns:repeat(4,1fr);gap:32px">${A.SHORTCUTS.map(([h, rows]) => `<div><div class="group-title">${h}</div><table class="kbd-table">${rows.map(([k, v]) => `<tr><td>${A.kbdHTML(k)}</td><td class="muted">${v}</td></tr>`).join('')}</table></div>`).join('')}</div>

      <h2>和手机端不一样的交互</h2>
      <div class="group">${[
        ['悬停就是查看', '十字线、图例数值、大单详情、术语解释都跟着鼠标走，不用先点。'],
        ['右键是「在这里做事」', '在 K 线上右键：在这个价位建提醒、画水平线、记一笔、复制价格。'],
        ['键盘直达', '打字母直接搜品种，打数字直接换周期，Alt + 字母选画线工具，⌘Z 撤销画线。'],
        ['画线不是一个模式', '左边画线栏常驻，选了工具就在当前图上画，画完自动回到光标；不用像手机那样转横屏进工作台。'],
        ['大屏同时看', '一 / 左右二 / 上下二 / 四图布局；点哪张图哪张就是当前图，十字线按时间跨图同步。'],
        ['拖放排序', '自选直接拖行排序；表格列头可以点着排序（板块页）。自选永远按你排的顺序。'],
        ['不做的', '不照搬手机的底栏、不做下拉刷新和长按，不在 K 线上浮按钮。'],
      ].map(([a, b]) => `<div class="row"><div class="rl"><div class="t">${a}</div><div class="d">${b}</div></div></div>`).join('')}</div>
    </div>`
  }
  A.pageShown.spec = renderSpec
  A.onTheme.push(() => { if (st.page === 'spec') renderSpec(); if (st.page === 'review' && rv.trades.length) drawEquity(rv.trades.filter(t => rv.sym === 'all' || t.symbol === rv.sym)) })

  // ============================================================ 原型控制台
  const panel = $('#protoPanel')
  function renderProto() {
    const b = (k, v, l, on) => `<button data-pk="${k}" data-pv="${v}" class="${on ? 'on' : ''}">${l}</button>`
    panel.innerHTML = `<h4>原型控制台（不属于产品界面）</h4>
      <div class="pr"><span>深浅色</span><div class="pbtns">${b('theme', 'light', '浅色', st.theme === 'light')}${b('theme', 'dark', '深色', st.theme === 'dark')}</div></div>
      <div class="pr"><span>涨跌色</span><div class="pbtns">${b('updown', 'red-up', '红涨', st.updown === 'red-up')}${b('updown', 'green-up', '绿涨', st.updown === 'green-up')}</div></div>
      <div class="pr"><span>登录</span><div class="pbtns">${b('login', '1', '已登录', st.loggedIn)}${b('login', '0', '未登录', !st.loggedIn)}</div></div>
      <div class="pr"><span>行情</span><div class="pbtns">${b('off', '0', '在线', !D.S.forcedOffline)}${b('off', '1', '模拟断线', D.S.forcedOffline)}</div></div>
      <h4 style="margin-top:12px">场景</h4>
      <div class="pbtns">${b('scene', 'alert', '触发一条提醒')}${b('scene', 'four', '四图布局')}${b('scene', 'draw', '示例画线')}${b('scene', 'empty', '空自选')}${b('scene', 'reset', '恢复初始')}${b('scene', 'spec', '看规范')}</div>
      <div class="note">状态记在本机浏览器里。「恢复初始」清掉所有本机状态。</div>`
  }
  $('#protoFab').onclick = () => { panel.classList.toggle('show'); renderProto() }
  panel.addEventListener('click', e => {
    const x = e.target.closest('[data-pk]'); if (!x) return
    const k = x.dataset.pk, v = x.dataset.pv
    if (k === 'theme' || k === 'updown') { st[k] = v; save(); A.applyTheme() }
    if (k === 'login') { st.loggedIn = v === '1'; save(); A.renderHeader(); A.renderPanel(); A.pageShown[st.page]?.() }
    if (k === 'off') D.forceOffline(v === '1')
    if (k === 'scene') {
      if (v === 'alert') {
        const c = A.cfg(A.active()), s = sym(c.symbol)
        const p = s.price ?? A.active().chart.lastBar().c
        st.alerts.push({ id: 'a' + Date.now(), symbol: c.symbol, kind: 'price', price: p * 0.999, dir: -1, created: Date.now() - 36e5 }); save()
        A.refreshStreams(); A.renderRail()
        setTimeout(() => { st.alerts = st.alerts.filter(a => a.price !== p * 0.999); save(); A.renderRail(); A.cells.forEach(cc => cc.chart.setAlerts(st.alerts.filter(a => a.symbol === A.cfg(cc).symbol && a.kind === 'price'))); if (st.panel === 'alerts') A.renderPanel(); toast(`${s.code} 价格达到 ${F.fmt(p * 0.999, s.dec)}`, `现价 ${A.priceText(s)} · 这条提醒已结束`, 'bell', 8000) }, 600)
      }
      if (v === 'four') { go('chart'); st.layout = '4'; A.buildCells(); A.renderToolbar() }
      if (v === 'draw') {
        go('chart'); const cell = A.active(), c = A.cfg(cell), b = cell.chart.bars, n = b.length
        const lo = Math.min(...b.slice(n - 120).map(x => x.l)), hi = Math.max(...b.slice(n - 120).map(x => x.h))
        const iL = b.slice(n - 120).findIndex(x => x.l === lo) + n - 120, iH = b.slice(n - 120).findIndex(x => x.h === hi) + n - 120
        const ds = A.drawingsFor(c.symbol)
        ds.push({ id: 'd1' + Date.now(), type: 'trend', pts: [{ t: b[n - 110].t, p: b[n - 110].l }, { t: b[n - 20].t, p: b[n - 20].l }], color: '#2962FF', width: 2 })
        ds.push({ id: 'd2' + Date.now(), type: 'hline', pts: [{ t: b[n - 1].t, p: hi }], color: '#F23645', width: 1 })
        ds.push({ id: 'd3' + Date.now(), type: 'fib', pts: [{ t: b[Math.min(iL, iH)].t, p: iL < iH ? lo : hi }, { t: b[Math.max(iL, iH)].t, p: iL < iH ? hi : lo }], color: '#9C27B0', width: 1 })
        A.cells.forEach(cc => { if (A.cfg(cc).symbol === c.symbol) cc.chart.dirty = true }); A.drawingsChanged(cell)
      }
      if (v === 'empty') { go('chart'); st.watch[st.watchTab] = []; st.panel = 'watch'; save(); A.renderRail(); A.renderPanel() }
      if (v === 'reset') { localStorage.clear(); location.href = location.pathname }
      if (v === 'spec') go('spec')
    }
    renderProto()
  })

  A.onLogin.push(() => { if (st.page === 'review') renderReview(); if (st.page === 'me') renderMe() })
  A.booted.push(() => { A.pageShown[st.page]?.() })
})(window)
