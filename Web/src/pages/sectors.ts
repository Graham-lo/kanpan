/* Hkline Web · 板块页：左板块表、中成员表、右预览图（数据全是币安实时的 24h 行情） */
import { st } from '../app/store'
import { hooks, go } from '../app/shell'
import { $, $$, I, esc, tgt } from '../ui/dom'
import { term } from '../ui/overlay'
import { sym, pctText, cls, priceText, badge } from '../ui/common'
import { TVChart } from '../chart/chart'
import { fmtCompact, IV_MS } from '../util/format'
import { S, SEC, klines, streamName, type Sym } from '../market'
import { openSymbol, toggleWatch, isWatched, refreshStreams } from './chart'

interface Sector { id: string; cn: string; members: string[]; med: number | null; beat: number; n: number; vol: number; up: number }
type SecKey = 'n' | 'med' | 'beat' | 'vol'
type MemKey = 'price' | 'pct' | 'vol' | 'fr'
const sp = {
  market: 'crypto' as 'crypto' | 'us', sort: 'med' as SecKey, dir: -1, sel: null as string | null,
  msort: 'pct' as MemKey, mdir: -1, chart: null as TVChart | null, preview: null as string | null,
  members: [] as string[], token: 0,
}
const median = (a: number[]): number | null => { if (!a.length) return null; const b = a.slice().sort((x, y) => x - y), m = b.length >> 1; return b.length % 2 ? b[m] : (b[m - 1] + b[m]) / 2 }

function sectors(): Sector[] {
  const btc = sym('BTCUSDT')?.pct ?? 0
  const raw = sp.market === 'crypto'
    ? SEC.crypto.filter(([id]) => id !== '---').map(([id, cn]) => ({ id: 'c:' + id, cn, members: Object.keys(SEC.members).filter(b => SEC.members[b].includes(id)).map(b => b + 'USDT').filter(k => S.symbols.has(k)) }))
    : SEC.us.map(([id, cn, codes]) => ({ id: 'u:' + id, cn, members: codes.map(c => c + 'USDT').filter(k => S.symbols.has(k)) }))
  return raw.filter(s => s.members.length >= 2).map(s => {
    const ps = s.members.map(k => sym(k)?.pct).filter((x): x is number => x != null)
    return { ...s, med: median(ps), beat: ps.filter(p => p > btc).length, n: ps.length, vol: s.members.reduce((a, k) => a + (sym(k)?.vol || 0), 0), up: ps.filter(p => p > 0).length }
  })
}

function render(): void {
  if (!S.symbols.size) {
    const msg = S.live === false ? '连不上币安合约接口' : '正在取行情…'
    $('#secList').innerHTML = `<div class="empty">${I('wifiOff', 'icon-24')}<div>${msg}</div></div>`
    $('#secMembers').innerHTML = ''; $('#secPreview').innerHTML = ''
    return
  }
  const list = sectors()
  const k = sp.sort, d = sp.dir
  list.sort((a, b) => d * (((a[k] as number | null) ?? -1e9) - ((b[k] as number | null) ?? -1e9)))
  if (!sp.sel || !list.some(s => s.id === sp.sel)) sp.sel = list[0]?.id ?? null
  const maxAbs = Math.max(1, ...list.map(s => Math.abs(s.med || 0)))
  const th = (key: SecKey, l: string, left = false) => `<th class="sortable ${left ? 'left' : ''}" data-sort="${key}" aria-sort="${k === key ? (d < 0 ? 'descending' : 'ascending') : 'none'}">${l}${k === key ? `<span class="arrow">${d < 0 ? '↓' : '↑'}</span>` : ''}</th>`
  $('#secList').innerHTML = `<div class="page-head"><h2>板块</h2><span class="sub">${list.length} 个</span><div style="margin-left:auto" class="seg" role="group" aria-label="市场">
      <button data-mk="crypto" aria-pressed="${sp.market === 'crypto'}">加密</button><button data-mk="us" aria-pressed="${sp.market === 'us'}">美股</button></div></div>
    <div class="scroll" style="flex:1;min-height:0"><table class="tbl"><thead><tr>${th('n', '板块', true)}${th('med', term('中位涨跌'))}${th('beat', term('跑赢大盘'))}${th('vol', '成交额')}</tr></thead><tbody>
    ${list.map(s => `<tr data-sec="${s.id}" class="${s.id === sp.sel ? 'sel' : ''}" aria-selected="${s.id === sp.sel}" tabindex="0">
      <td class="left"><b style="font-weight:600">${esc(s.cn)}</b> <span class="faint">${s.n}</span></td>
      <td><div style="display:flex;align-items:center;gap:8px;justify-content:flex-end"><span class="sec-bar" aria-hidden="true"><i style="width:${Math.abs(s.med || 0) / maxAbs * 100}%;background:var(${(s.med || 0) >= 0 ? '--up' : '--down'})"></i></span><span class="num ${cls(s.med)}" style="width:64px">${pctText(s.med)}</span></div></td>
      <td class="num">${s.beat}<span class="faint"> / ${s.n}</span></td><td class="num muted">${fmtCompact(s.vol)}</td></tr>`).join('')}
    </tbody></table></div>`
  renderMembers(list.find(s => s.id === sp.sel))
}

function renderMembers(s: Sector | undefined): void {
  const el = $('#secMembers')
  if (!s) { el.innerHTML = '<div class="empty">没有板块</div>'; sp.members = []; refreshStreams(); return }
  const ms = s.members.map(sym).filter((x): x is Sym => !!x)
  const k = sp.msort, d = sp.mdir
  ms.sort((a, b) => d * ((a[k] ?? 0) - (b[k] ?? 0)))
  const th = (key: MemKey, l: string) => `<th class="sortable" data-msort="${key}" aria-sort="${k === key ? (d < 0 ? 'descending' : 'ascending') : 'none'}">${l}${k === key ? `<span class="arrow">${d < 0 ? '↓' : '↑'}</span>` : ''}</th>`
  const btc = sym('BTCUSDT')
  el.innerHTML = `<div class="page-head"><h2>${esc(s.cn)}</h2><span class="sub">${s.n} 个品种 · ${s.up} 涨 ${s.n - s.up} 跌 · 跑赢比特币（${pctText(btc?.pct)}）的有 ${s.beat} 个</span></div>
    <div class="scroll" style="flex:1;min-height:0"><table class="tbl"><thead><tr><th class="left">品种</th>${th('price', '最新价')}${th('pct', '24h 涨跌')}${th('vol', '成交额')}${th('fr', term('资金费率'))}<th>24 小时</th><th style="width:40px"></th></tr></thead><tbody>
    ${ms.map(m => `<tr data-msym="${m.symbol}" class="${m.symbol === sp.preview ? 'sel' : ''}" tabindex="0">
      <td class="left"><div class="sym">${badge(m)}<b>${esc(m.code)}</b><span class="cn">${esc(m.cn || '')}</span></div></td>
      <td class="num" data-f="price">${priceText(m)}</td><td class="num ${cls(m.pct)}" data-f="pct">${pctText(m.pct)}</td><td class="num muted" data-f="vol">${fmtCompact(m.vol)}</td>
      <td class="num ${m.fr != null && m.fr < 0 ? 'down' : ''}">${m.fr == null ? '—' : (m.fr * 100).toFixed(4) + '%'}</td>
      <td><svg class="spark" data-spark="${m.symbol}" viewBox="0 0 96 24" aria-hidden="true">${sparkPath(m.symbol)}</svg></td>
      <td><button class="ibtn sm" data-star="${m.symbol}" aria-label="${isWatched(m.symbol) ? '移出自选' : '加入自选'}" style="color:${isWatched(m.symbol) ? '#F5A623' : ''}">${I(isWatched(m.symbol) ? 'star' : 'starOff', 'icon-16')}</button></td></tr>`).join('')}
    </tbody></table></div>`
  sp.members = ms.map(m => m.symbol)
  refreshStreams()
  loadSparks(ms.slice(0, 40).map(m => m.symbol))
  if (!sp.preview || !s.members.includes(sp.preview)) setPreview(ms[0]?.symbol)
}

// 24 小时迷你走势：1 小时 K 线最后 24 根，最多 6 个请求同时在路上
const sparks = new Map<string, number[]>()
function sparkPath(k: string): string {
  const a = sparks.get(k); if (!a || a.length < 2) return ''
  const lo = Math.min(...a), hi = Math.max(...a), r = hi - lo || 1
  const pts = a.map((v, i) => `${(i / (a.length - 1) * 94 + 1).toFixed(1)},${(22 - (v - lo) / r * 20).toFixed(1)}`).join(' ')
  return `<polyline points="${pts}" fill="none" stroke="var(${a[a.length - 1] >= a[0] ? '--up' : '--down'})" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/>`
}
let sparkQ: string[] = [], sparkRunning = 0
function loadSparks(list: string[]): void {
  sparkQ = list.filter(k => !sparks.has(k))
  const pump = (): void => {
    while (sparkRunning < 6 && sparkQ.length) {
      const k = sparkQ.shift() as string; sparkRunning++
      klines(k, '1h', undefined, 25, false).then(({ bars }) => {
        if (bars.length) sparks.set(k, bars.slice(-24).map(b => b.c))
        const el = document.querySelector(`[data-spark="${k}"]`); if (el) el.innerHTML = sparkPath(k)
      }).finally(() => { sparkRunning--; pump() })
    }
  }
  pump()
}

function setPreview(k: string | undefined): void {
  if (!k) return
  sp.preview = k
  $$('#secMembers tr[data-msym]').forEach(r => r.classList.toggle('sel', r.dataset.msym === k))
  const s = sym(k), el = $('#secPreview')
  if (!s) return
  if (!sp.chart) {
    el.innerHTML = `<div class="page-head" id="pvHead"></div><div class="canvas-host" id="pvHost" style="flex:1;min-height:0;position:relative"></div>`
    sp.chart = new TVChart($('#pvHost'), { onActivate() { /* 预览图只看不改 */ } })
    sp.chart.setIndicators({ ma: false, ema: false, boll: false, vol: true, subs: [] })
  }
  $('#pvHead').innerHTML = `${badge(s, 'lg')}<div><div style="font-weight:600;line-height:20px">${esc(s.code)} <span class="muted" style="font-weight:400">${esc(s.cn || '')}</span></div><div class="num ${cls(s.pct)}" style="font-size:12px;line-height:16px">${priceText(s)} · ${pctText(s.pct)}</div></div>
    <button class="btn primary sm" style="margin-left:auto" id="pvOpen">在图表中打开<kbd style="margin-left:6px;background:transparent;color:inherit;border-color:rgba(255,255,255,.4)">↵</kbd></button>`
  const token = ++sp.token
  void klines(k, '1h', undefined, 500, false).then(({ bars }) => {
    if (token !== sp.token || !sp.chart) return
    sp.chart.setData(bars, { symbol: k, iv: IV_MS['1h'], title: k, sub: '· 1 小时', dec: s.dec, badge: badge(s) })
  })
}

function openSector(id: string): void {
  sp.market = id.startsWith('u:') ? 'us' : 'crypto'; sp.sel = id; sp.preview = null
  go('sectors'); render()
  document.querySelector('#secList tr.sel')?.scrollIntoView({ block: 'center' })
}

function openInChart(k: string | null): void { if (!k) return; go('chart'); openSymbol(k) }

// 推送来的 ticker 只改成员表里那几格
function patchMembers(): void {
  if (st.page !== 'sectors') return
  for (const k of sp.members) {
    const tr = document.querySelector(`#secMembers tr[data-msym="${k}"]`), s = sym(k); if (!tr || !s) continue
    const p = tr.querySelector('[data-f="price"]'), pc = tr.querySelector('[data-f="pct"]'), v = tr.querySelector('[data-f="vol"]')
    if (p) p.textContent = priceText(s)
    if (pc) { pc.textContent = pctText(s.pct); pc.className = `num ${cls(s.pct)}` }
    if (v) v.textContent = fmtCompact(s.vol)
  }
}

export function initSectors(): void {
  const page = $('#page-sectors')
  page.addEventListener('click', e => {
    const t = tgt(e)
    const mk = t.closest<HTMLElement>('[data-mk]'); if (mk) { sp.market = mk.dataset.mk as 'crypto' | 'us'; sp.sel = null; sp.preview = null; render(); return }
    const so = t.closest<HTMLElement>('[data-sort]'); if (so && !t.closest('.term')) { const k = so.dataset.sort as SecKey; sp.dir = sp.sort === k ? -sp.dir : -1; sp.sort = k; render(); return }
    const mso = t.closest<HTMLElement>('[data-msort]'); if (mso && !t.closest('.term')) { const k = mso.dataset.msort as MemKey; sp.mdir = sp.msort === k ? -sp.mdir : -1; sp.msort = k; render(); return }
    const star = t.closest<HTMLElement>('[data-star]'); if (star) { toggleWatch(star.dataset.star || ''); render(); return }
    const r = t.closest<HTMLElement>('[data-sec]'); if (r) { sp.sel = r.dataset.sec || null; sp.preview = null; $$('#secList tr[data-sec]').forEach(x => { x.classList.toggle('sel', x === r); x.setAttribute('aria-selected', String(x === r)) }); renderMembers(sectors().find(s => s.id === sp.sel)); return }
    const m = t.closest<HTMLElement>('[data-msym]'); if (m) { setPreview(m.dataset.msym); return }
    if (t.closest('#pvOpen')) openInChart(sp.preview)
  })
  page.addEventListener('dblclick', e => { const m = tgt(e).closest<HTMLElement>('[data-msym]'); if (m) openInChart(m.dataset.msym || null) })
  page.addEventListener('keydown', e => {
    const r = tgt(e).closest<HTMLElement>('tr[data-sec],tr[data-msym]'); if (!r) return
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); const n = (e.key === 'ArrowDown' ? r.nextElementSibling : r.previousElementSibling) as HTMLElement | null; if (n) { n.focus(); n.click() } }
    if (e.key === 'Enter') { if (r.dataset.msym) openInChart(r.dataset.msym); else { r.click(); $('#secMembers tr[data-msym]')?.focus() } }
    if (e.key === 'ArrowRight' && r.dataset.sec) { e.preventDefault(); $('#secMembers tr[data-msym]')?.focus() }
    if (e.key === 'ArrowLeft' && r.dataset.msym) { e.preventDefault(); $('#secList tr.sel')?.focus() }
  })
  hooks.openSector = openSector
  hooks.pageShown.sectors = () => { render(); sp.chart?.resize() }
  hooks.pageHidden.sectors = () => { sp.members = []; refreshStreams() }
  hooks.extraStreams.push(() => st.page === 'sectors' ? sp.members.map(k => streamName.ticker(k)) : [])
  hooks.onTicks.push(patchMembers)
  hooks.onTheme.push(() => sp.chart?.readTheme())
  hooks.booted.push(() => { if (st.page === 'sectors') render() })
}
