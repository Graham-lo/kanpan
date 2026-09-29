/* Hkline Web · 记一笔（弹窗）
 *
 * 照手机端取景卡（KanpanReview ReviewCaptureCard）：圈的就是图上看得见的那一段（只读一行，想换段就拖图），
 * 方向默认「只记录」；看多 / 看空时给目标、失效两个价和确认方式；一句话选填；来源默认「图在先」。
 * 到期按周期定、卡上不给改。保存先落本机，再传服务端成为一条观点记录（复盘页「观点记录」、手机上都看得到），
 * 带一张当时的图表截图。没登录照样能记，登录后自动补传。
 */
import { st, save, type Note } from '../app/store'
import { go } from '../app/shell'
import { $, $$, I, esc, tgt } from '../ui/dom'
import { dialog, head, toast } from '../ui/overlay'
import { badge, shTime, sym } from '../ui/common'
import { IV_LABEL } from '../market/symbols'
import { fmt, fmtAxis } from '../util/format'
import { uuid } from '../review/api'
import {
  buildDraft, captureRange, checkDraft, sideLevels, recordInterval,
  DIRECTION_LABEL, CONFIRMATION_LABEL, ORIGIN_LABEL,
  type BarLike, type Confirmation, type Direction, type Origin,
} from './draft'
import { canUpload, flushNotes, keepShot } from './sync'

export interface NoteContext {
  symbol: string
  iv: string
  bars: readonly BarLike[]
  /** 视野里的 K 线下标 */
  from: number
  to: number
  /** 图表画布（存一张截图随记录传上去） */
  canvas: HTMLCanvasElement | null
  /** 右键点的那根 K 线的时间与价位（侧栏笔记跳回图上用）；工具栏进来就是最新一根 */
  t: number
  p: number
  onSaved: (n: Note) => void
}

/** 区间一行：「48 根 · 9月27日 20:00 – 9月29日 20:00」 */
function rangeText(bars: number, start: number, end: number): string {
  return `${bars} 根 · ${shTime(start)} – ${shTime(end)}`
}

/** 图表截图：最宽 1600 px 的 JPEG（服务端上限 2 MiB，这个尺寸一般一两百 KB）；取不到返回 null */
export function snapshot(canvas: HTMLCanvasElement | null): string | null {
  if (!canvas || !canvas.width || !canvas.height) return null
  try {
    const k = Math.min(1, 1600 / canvas.width)
    const out = document.createElement('canvas')
    out.width = Math.round(canvas.width * k); out.height = Math.round(canvas.height * k)
    const c = out.getContext('2d'); if (!c) return null
    c.fillStyle = getComputedStyle(canvas.parentElement || canvas).getPropertyValue('--chart-bg').trim() || '#fff'
    c.fillRect(0, 0, out.width, out.height)
    c.drawImage(canvas, 0, 0, out.width, out.height)
    for (const q of [0.85, 0.7, 0.5]) {
      const b64 = out.toDataURL('image/jpeg', q).split(',')[1] || ''
      if (b64 && b64.length * 0.75 < 1.8 * 1024 * 1024) return b64
    }
  } catch { /* 画布被污染或浏览器不给：不带图 */ }
  return null
}

export function openNoteDialog(x: NoteContext): void {
  const s = sym(x.symbol), dec = s?.dec ?? 2
  const cap = captureRange(x.symbol, x.iv, x.bars, x.from, x.to, Date.now())
  let dir: Direction = 'observe', conf: Confirmation = 'bar_close', origin: Origin = 'chart_first'
  let target = 0, inv = 0, tEdited = false, iEdited = false
  if (cap) ({ target, invalidation: inv } = sideLevels('long', cap.reference, cap.high, cap.low))
  const ivLabel = IV_LABEL[x.iv] || x.iv
  const rec = cap ? recordInterval(x.iv) : ''
  const recNote = cap && rec !== x.iv ? `（服务端按 ${IV_LABEL[rec] || rec} 记）` : ''
  const pv = (v: number): string => Number.isFinite(v) ? v.toFixed(dec) : ''

  const segHTML = <K extends string>(id: string, labels: Record<K, string>, cur: K): string =>
    `<div class="seg fill" id="${id}" role="group">${(Object.keys(labels) as K[]).map(k => `<button type="button" data-v="${k}" aria-pressed="${k === cur}">${labels[k]}</button>`).join('')}</div>`

  const d = dialog(`${head('记一笔', `<span class="muted" style="font-size:12px">${esc(ivLabel)}</span>`)}<div class="dialog-body"><div class="form-grid note-form">
    <div class="sym-card">${badge(s, 'lg')}<div style="flex:1;min-width:0"><b>${esc(s?.code || x.symbol)}</b>
      <div class="muted num" style="font-size:12px;line-height:16px" id="nRange">${cap ? esc(rangeText(cap.range.bars, cap.range.start, cap.range.end)) + esc(recNote) : esc(`${ivLabel} · ${shTime(x.t)}`)}</div></div>
      <div style="text-align:right"><div class="num" style="font-weight:600">${fmtAxis(cap?.reference ?? x.p, dec)}</div><div class="faint" style="font-size:12px;line-height:16px">${cap ? '参考价' : ''}</div></div></div>
    ${cap ? `<div class="field"><label>看法</label>${segHTML('nDir', DIRECTION_LABEL, dir)}</div>
    <div id="nLevels"></div>` : `<div class="hint">${esc(x.symbol)} 不是 USDT 合约，服务端判不了对错：这一笔只存在这台电脑上。</div>`}
    <div class="field"><label for="nTx">一句话 <span class="faint" style="font-weight:400">选填</span></label><textarea id="nTx" class="input" style="height:88px;padding:8px 12px;resize:vertical;line-height:20px" placeholder="比如：放量突破前高，回踩不破再看多"></textarea></div>
    ${cap ? `<div class="field"><label>来源</label>${segHTML('nOrigin', ORIGIN_LABEL, origin)}</div>` : ''}
    ${cap && !canUpload() ? `<div class="note-login"><span>${I('info', 'icon-16')}没登录：先存在这台电脑上，登录后自动传到复盘「观点记录」，手机上也看得到。</span><button type="button" class="btn secondary sm" id="nLogin">去登录</button></div>` : ''}
    <div class="err" id="nErr" role="alert"></div>
    </div></div><div class="dialog-foot"><span class="faint" style="margin-right:auto;font-size:12px;align-self:center">${cap ? '到期按周期定 · ' : ''}<kbd>⌘</kbd> <kbd>↵</kbd> 记下</span><button class="btn ghost" data-close>取消</button><button class="btn primary" id="nOk">记下</button></div>`, 'alert-dlg note-dlg', { label: '记一笔' })

  const tx = $<HTMLTextAreaElement>('#nTx', d.dlg)
  const err = (m: string): void => { $('#nErr', d.dlg).textContent = m }

  function renderLevels(): void {
    const el = document.getElementById('nLevels'); if (!el || !cap) return
    if (dir === 'observe') { el.innerHTML = ''; return }
    el.innerHTML = `<div class="form-grid" style="gap:var(--s3)">
      <div class="note-levels">
        <div class="field"><label for="nTarget">目标</label><div class="input-wrap"><input id="nTarget" class="input num" inputmode="decimal" value="${pv(target)}"><span class="suffix" id="nTargetPct"></span></div></div>
        <div class="field"><label for="nInv">失效</label><div class="input-wrap"><input id="nInv" class="input num" inputmode="decimal" value="${pv(inv)}"><span class="suffix" id="nInvPct"></span></div></div>
      </div>
      <div class="note-refline"><span class="faint num">参考价 ${fmtAxis(cap.reference, dec)}</span><button type="button" class="btn ghost sm" id="nReset">按方向重置</button></div>
      <div class="field"><label>确认方式</label>${segHTML('nConf', CONFIRMATION_LABEL, conf)}</div>
    </div>`
    pcts()
  }
  function pcts(): void {
    if (!cap) return
    const p = (v: number): string => v > 0 ? `${v >= cap.reference ? '+' : ''}${((v - cap.reference) / cap.reference * 100).toFixed(2)}%` : ''
    const a = document.getElementById('nTargetPct'), b = document.getElementById('nInvPct')
    if (a) a.textContent = p(target)
    if (b) b.textContent = p(inv)
  }
  /** 方向切换：人没改过的那个价按新方向摆到参考价的另一侧（照手机端） */
  function setDir(nd: Direction): void {
    dir = nd
    if (cap && dir !== 'observe') {
      const hi = Math.max(target, inv), lo = Math.min(target, inv)
      if (!tEdited) target = dir === 'long' ? hi : lo
      if (!iEdited) inv = dir === 'long' ? lo : hi
    }
    renderLevels(); err('')
  }
  renderLevels()

  d.dlg.addEventListener('click', e => {
    const t = tgt(e)
    const b = t.closest<HTMLElement>('.seg [data-v]')
    if (b) {
      const g = b.parentElement!
      $$('button', g).forEach(x => x.setAttribute('aria-pressed', String(x === b)))
      const v = b.dataset.v!
      if (g.id === 'nDir') setDir(v as Direction)
      else if (g.id === 'nConf') conf = v as Confirmation
      else if (g.id === 'nOrigin') origin = v as Origin
      return
    }
    if (t.closest('#nReset') && cap) {
      const a = Math.max(target || 0, inv || 0, cap.reference * 1.01)
      const z = Math.min(target || Infinity, inv || Infinity, cap.reference * 0.99)
      target = dir === 'long' ? a : z; inv = dir === 'long' ? z : a
      tEdited = iEdited = false
      renderLevels(); err('')
      return
    }
    if (t.closest('#nLogin')) { d.close(); st.meSection = 'account'; save(); go('me') }
  })
  d.dlg.addEventListener('input', e => {
    const t = e.target as HTMLInputElement
    if (t.id === 'nTarget') { target = parseFloat(t.value.replace(/,/g, '')); tEdited = true; pcts(); err('') }
    if (t.id === 'nInv') { inv = parseFloat(t.value.replace(/,/g, '')); iEdited = true; pcts(); err('') }
  })

  const ok = (): void => {
    const text = tx.value.trim()
    const created = Date.now()
    const id = uuid()
    if (!cap) {
      if (!text) { tx.focus(); err('写一句话再记'); return }
      const n: Note = { id, symbol: x.symbol, iv: x.iv, t: x.t, p: x.p, text }
      st.notes.push(n); save(); d.close()
      toast('已记下', '这只品种只存在这台电脑上', 'note')
      x.onSaved(n)
      return
    }
    const draft = buildDraft({ id, capture: cap, direction: dir, confirmation: conf, target, invalidation: inv, targetEdited: tEdited, invalidationEdited: iEdited, text, origin, created })
    const bad = checkDraft(draft); if (bad) { err(bad); return }
    const shot = snapshot(x.canvas)
    const hasShot = !!shot && keepShot(id, shot)
    const n: Note = { id, symbol: x.symbol, iv: x.iv, t: x.t, p: x.p, text, draft, sync: 'pending', shot: hasShot ? 'pending' : 'none' }
    st.notes.push(n); save(); d.close()
    x.onSaved(n)
    if (!canUpload()) { toast('已记下', '登录后自动传到复盘「观点记录」', 'note'); return }
    void flushNotes().then(() => {
      if (n.sync === 'synced') toast('已记下', '复盘「观点记录」和手机上都看得到', 'note')
      else if (n.sync === 'failed') toast('服务端没收下', n.err || '笔记留在这台电脑上', 'info', 5000)
      else toast('已记下', '网络恢复后自动传上去', 'note')
    })
  }
  $('#nOk', d.dlg).onclick = ok
  d.dlg.addEventListener('keydown', e => { if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); ok() } })
  tx.focus()
}

/** 侧栏笔记一条的看法小字：「看多 · 目标 84,500.0 · 失效 82,000.0」 */
export function noteRuleText(n: Note): string {
  const r = n.draft?.rule; if (!r) return ''
  const dec = sym(n.symbol)?.dec ?? 2
  if (r.direction === 'observe') return DIRECTION_LABEL.observe
  return `${DIRECTION_LABEL[r.direction]} · 目标 ${fmt(r.target, dec)} · 失效 ${fmt(r.invalidation, dec)}`
}
