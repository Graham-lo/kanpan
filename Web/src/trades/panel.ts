/* Hkline Web · 图表侧栏「成交」
 *
 * 这只品种的逐笔成交：交易所只读密钥在手机上绑定，手机拉成交、传到服务端拼成交易回合，
 * 网页只读服务端的回合（GET /v1/native-review/records?kind=trade&symbol=…），把回合里的 fills 摊平，
 * 按时间倒序列出时间、方向、价、量、名义；点一行跳复盘页的那一回合，按当时的节奏回放。
 * 网页不存密钥、不直连交易所。
 *
 * 取数：打开面板、换品种、登录状态变了时各取一次，一分钟内重开不重取（右上角可手动刷新）；不开轮询。
 */
import { st, save } from '../app/store'
import { go, hooks } from '../app/shell'
import { onSession } from '../account/session'
import { I, esc, tgt } from '../ui/dom'
import { sym } from '../ui/common'
import { fmtAxis, fmtCompact, sh, pad } from '../util/format'
import { reviewApi, errorText, ReviewError } from '../review/api'
import type { TradeRecord, Fill } from '../review/types'
import { canUpload } from '../notes/sync'
import { ago } from '../util/clock'

export const NO_KEY_TEXT = '在手机上绑定交易所只读密钥后，成交会自动同步到这里'
const TTL = 60_000
/** 列多少条（一只品种几百笔成交足够了，更早的去复盘页看） */
const MAX_ROWS = 300

interface Entry { at: number; rows: TradeRecord[] | null; err: string | null; loading: boolean }
const cache = new Map<string, Entry>()
/** 账号下有没有任何交易回合：没有就说明手机上还没绑密钥（null = 还没问） */
let anyTrades: boolean | null = null
/** 换账号就换一代：上一个账号在途的请求回来时作废，不写缓存、不改 anyTrades */
let epoch = 0
let rerender: () => void = () => { /* 由宿主挂上 */ }

export interface FillRow { rec: string; fill: Fill; direction: 'long' | 'short' }

/** 把回合摊成逐笔成交，按时间倒序（同一毫秒按成交 id 倒序，结果稳定） */
export function flattenFills(records: readonly TradeRecord[]): FillRow[] {
  const out: FillRow[] = []
  for (const r of records) {
    if (r.voided) continue
    for (const f of r.round.fills || []) out.push({ rec: r.id, fill: f, direction: r.round.direction })
  }
  return out.sort((a, b) => b.fill.time - a.fill.time || (b.fill.id > a.fill.id ? 1 : b.fill.id < a.fill.id ? -1 : 0))
}

export interface VenueRow { venue: string; market: string; accountTag: string; title: string; rounds: number; lastUpload: number; lastFill: number }
const VENUE_CN: Record<string, string> = { binance: '币安', okx: 'OKX', coinbase: 'Coinbase', bybit: 'Bybit', bitget: 'Bitget' }
const MARKET_CN: Record<string, string> = { usd_m: 'U 本位合约', coin_m: '币本位合约', spot: '现货' }

/** 「交易所账号」页：按交易所 + 账户把回合归拢，最近一次上传 = 回合最晚的提交时间（服务端没有单独的绑定状态接口） */
export function venueRows(records: readonly TradeRecord[]): VenueRow[] {
  const m = new Map<string, VenueRow>()
  for (const r of records) {
    const o = r.round, k = `${o.venue}|${o.market}|${o.accountTag}`
    let v = m.get(k)
    if (!v) {
      v = { venue: o.venue, market: o.market, accountTag: o.accountTag || '', rounds: 0, lastUpload: 0, lastFill: 0,
        title: `${VENUE_CN[o.venue] ?? o.venue}${MARKET_CN[o.market] ? ' · ' + MARKET_CN[o.market] : ''}` }
      m.set(k, v)
    }
    v.rounds++
    v.lastUpload = Math.max(v.lastUpload, r.submitted || 0)
    for (const f of o.fills || []) v.lastFill = Math.max(v.lastFill, f.time)
  }
  return [...m.values()].sort((a, b) => b.lastUpload - a.lastUpload)
}

const ROLE: Record<string, string> = { open: '开', add: '加', reduce: '减', close: '平' }
/** 「买开」「卖平」「买加」…；角色不认识就只写买 / 卖 */
export function sideText(f: Fill): string { return (f.side === 'BUY' ? '买' : '卖') + (ROLE[f.role] ?? '') }

function qtyText(v: number): string {
  if (!isFinite(v)) return '—'
  const a = Math.abs(v)
  return v.toLocaleString('en-US', { maximumFractionDigits: a >= 100 ? 2 : a >= 1 ? 4 : 6 })
}
function dayOf(t: number): string { const d = sh(t); return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}` }
function hm(t: number): string { const d = sh(t); return `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())}` }
function dayLabel(t: number): string {
  const k = dayOf(t), today = dayOf(Date.now()), yest = dayOf(Date.now() - 864e5)
  if (k === today) return '今天'
  if (k === yest) return '昨天'
  const d = sh(t)
  return d.getUTCFullYear() === sh(Date.now()).getUTCFullYear() ? `${d.getUTCMonth() + 1}月${d.getUTCDate()}日` : `${d.getUTCFullYear()}年${d.getUTCMonth() + 1}月${d.getUTCDate()}日`
}

async function load(symbol: string, force = false): Promise<void> {
  const e = cache.get(symbol)
  if (e && (e.loading || (!force && ago(e.at) < TTL))) return
  const cur: Entry = { at: e?.at ?? 0, rows: e?.rows ?? null, err: null, loading: true }
  cache.set(symbol, cur)
  const ep = epoch
  try {
    const [rows, first] = await Promise.all([
      reviewApi.tradesOf(symbol),
      anyTrades && !force ? Promise.resolve(null) : reviewApi.tradesFirstPage(),
    ])
    if (ep !== epoch) return
    cur.rows = rows
    if (first) anyTrades = first.length > 0
    else if (rows.length) anyTrades = true
  } catch (err) {
    if (ep !== epoch) return
    cur.err = err instanceof ReviewError && err.status === 401 ? '登录已过期，重新登录后再看' : errorText(err)
  }
  cur.loading = false; cur.at = Date.now()
  rerender()
}

const loginBlock = (): string => `<div class="empty">${I('trades', 'icon-24')}<div>登录后这里列出这只品种的成交</div>
  <div class="faint" style="font-size:12px;margin-top:4px;max-width:260px">${NO_KEY_TEXT}</div>
  <button class="btn secondary sm" id="trLogin" style="margin-top:12px">去登录</button></div>`

export function renderTradesPanel(el: HTMLElement, symbol: string): void {
  const s = sym(symbol), dec = s?.dec ?? 2
  const headHTML = `<div class="sp-head"><h3>成交</h3><button class="ibtn sm" id="trReload" aria-label="重新取成交" data-tip="重新取">${I('refresh', 'icon-16')}</button></div>`
  if (!canUpload()) { el.innerHTML = `<div class="sp-head"><h3>成交</h3></div>${loginBlock()}`; return }
  const e = cache.get(symbol)
  if (!e || (!e.loading && ago(e.at) >= TTL)) void load(symbol)
  const ent = cache.get(symbol)!
  let body: string
  if (ent.rows == null) {
    body = ent.err ? `<div class="empty">${I('info', 'icon-24')}<div>成交没取到</div><div class="faint" style="font-size:12px;margin-top:4px">${esc(ent.err)}</div></div>`
      : `<div class="empty"><div class="faint">正在取成交…</div></div>`
  } else {
    const rows = flattenFills(ent.rows)
    if (!rows.length) {
      body = anyTrades === false
        ? `<div class="empty" data-tr-empty="nokey">${I('key', 'icon-24')}<div style="max-width:260px">${NO_KEY_TEXT}</div><div class="faint" style="font-size:12px;margin-top:4px">网页不存密钥，只读服务端上的成交</div></div>`
        : `<div class="empty" data-tr-empty="symbol">${I('trades', 'icon-24')}<div>${esc(s?.code || symbol)} 还没有成交</div><div class="faint" style="font-size:12px;margin-top:4px">手机上拉到的成交会自动同步到这里</div></div>`
    } else {
      let lastDay = ''
      const list = rows.slice(0, MAX_ROWS).map(r => {
        const f = r.fill, day = dayOf(f.time)
        const sep = day !== lastDay ? `<div class="tr-day">${dayLabel(f.time)}</div>` : ''
        lastDay = day
        const up = f.side === 'BUY'
        return `${sep}<button type="button" class="tr-row" data-tr-rec="${esc(r.rec)}" data-tip="在复盘里回放这一回合" data-tip-side="left">
          <span class="t num">${hm(f.time)}</span><span class="sd ${up ? 'up' : 'down'}">${sideText(f)}</span>
          <span class="num">${fmtAxis(+f.price, dec)}</span><span class="num">${qtyText(+f.qty)}</span><span class="num">${fmtCompact(+f.quoteQty)}</span></button>`
      }).join('')
      body = `<div class="tr-head"><span>时间</span><span>方向</span><span>价格</span><span>数量</span><span>名义</span></div>
        <div class="scroll tr-list" id="trList">${list}</div>
        <div class="tr-foot">${rows.length > MAX_ROWS ? `最近 ${MAX_ROWS} 笔，共 ${rows.length} 笔 · ` : `${rows.length} 笔 · `}点一行在复盘里回放</div>`
    }
  }
  const keep = el.querySelector<HTMLElement>('#trList')?.scrollTop ?? 0
  el.innerHTML = headHTML + body
  const l = el.querySelector<HTMLElement>('#trList'); if (l) l.scrollTop = keep
}

/** 侧栏点击：处理了返回 true */
export function tradesPanelClick(e: MouseEvent, symbol: string): boolean {
  const t = tgt(e)
  if (t.closest('#trLogin')) { st.meSection = 'account'; save(); go('me'); return true }
  if (t.closest('#trReload')) { void load(symbol, true); rerender(); return true }
  const row = t.closest<HTMLElement>('[data-tr-rec]')
  if (row) { hooks.openReview?.('trade', row.dataset.trRec || ''); return true }
  return false
}

/** 宿主挂一次：成交到了 / 登录状态变了时重画侧栏 */
export function installTradesPanel(render: () => void): void {
  rerender = render
  onSession(() => { epoch++; cache.clear(); anyTrades = null; render() })
}
