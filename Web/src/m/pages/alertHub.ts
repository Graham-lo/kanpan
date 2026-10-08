/* 手机网页版 · 顶栏铃铛开的「提醒」表（照 iOS Alerts/AlertHubSheet.swift，2026-10-05，TradingView 手机版的 Alerts：列表 | 日志）
 *
 * - 列表：提醒总表（buildAlertList），图上这只置顶成一组（下面分价格 / 画线），其余品种照旧；
 *         底部一颗通栏「创建提醒」开创建页——品种锁定为图上这只、价格预填最新价。
 * - 日志：响过的提醒（alerts/log.ts，账在服务端、留 30 天），按上海时间分天，一行是徽章 + 品种、
 *         条件 · 触发价、时刻。进表就拉一趟；右上「清空」（登录了且有记录时才摆）要确认。没登录只有一句「登录后可查看」；
 *         一条没有时照 iOS 空态「还没有响过的提醒」+「去创建」（切回列表、开创建页）。
 * 十字线那颗「创建提醒」与「我的 › 全部预警」照旧，不受这张表影响。
 */
import '../styles/alerts.css'
import { S } from '../../market'
import { alertLog, logDays, logClock, logDetail, logName, logOwner, bareSymbol, type AlertLogRecord } from '../../alerts/log'
import { openSheet, confirmDialog, type Sheet } from '../ui/sheet'
import { icon } from '../ui/icons'
import { toast } from '../ui/toast'
import { esc } from '../model/rowText'
import { badgeHTML } from '../model/badge'
import { factsOf } from '../model/rowHTML'
import { openSymbol } from '../app/shell'
import { alertEmptyHTML, buildAlertList, pairName, startAlertWatcher } from './alerts'
import { openAlertForm } from './alertForm'

type Tab = 'list' | 'log'

/** 日志一行：徽章 + 品种 / 条件 · 触发价 / 时刻 */
export function logRowHTML(r: AlertLogRecord, last: boolean): string {
  const sym = bareSymbol(r.symbol)
  const f = sym ? factsOf(sym, S.symbols.get(sym)) : null
  const detail = logDetail(r, sym ? S.symbols.get(sym)?.dec : undefined)
  return `<div class="alg${last ? ' last' : ''}" data-sym="${esc(sym)}">
    ${f ? badgeHTML(f.base, 28, f.asset) : '<span class="alg-nobadge"></span>'}
    <span class="alg-text"><span class="alg-name">${esc(logName(r, pairName))}</span>${detail ? `<span class="alg-detail num">${esc(detail)}</span>` : ''}</span>
    <span class="alg-clock num">${logClock(r.firedAt)}</span>
  </div>`
}

/** 打开「提醒」表。price：开表那一刻的最新价（创建页预填） */
export function openAlertHub(symbol: string, price?: number | null): Sheet {
  startAlertWatcher()
  const log = alertLog()
  let tab: Tab = 'list'
  let offList: (() => void) | null = null
  const offs: (() => void)[] = []
  const sheet = openSheet((body) => {
    body.classList.add('alf-body', 'alhub-body')
    body.innerHTML = `<div class="alhub-tabs"><div class="m-seg alhub-seg" role="tablist" aria-label="提醒">
        <button type="button" class="m-seg-opt on" role="tab" aria-selected="true" data-tab="list">列表</button>
        <button type="button" class="m-seg-opt" role="tab" aria-selected="false" data-tab="log">日志</button></div></div>
      <div class="alhub-pane"></div>
      <div class="alhub-foot"><button type="button" class="alf-submit alhub-create">创建提醒</button></div>`
  }, {
    title: '提醒', detent: 'large', expandable: false, className: 'alf-sheet alhub-sheet', id: 'alerts.hub',
    action: { title: '清空', run: () => void clearLog() },
    onClose: () => { offList?.(); offs.forEach(f => f()) },
  })
  const back = sheet.root.querySelector<HTMLElement>('.m-sheet-back')
  if (back) { back.innerHTML = icon('close', 18); back.setAttribute('aria-label', '关闭') }
  const action = sheet.root.querySelector<HTMLElement>('.m-sheet-action')!
  const body = sheet.body
  const pane = body.querySelector<HTMLElement>('.alhub-pane')!
  const foot = body.querySelector<HTMLElement>('.alhub-foot')!

  const paintAction = (): void => { action.hidden = !(tab === 'log' && logOwner() && log.records.length > 0) }

  function renderLog(): void {
    if (tab !== 'log') return
    paintAction()
    if (!logOwner()) { pane.innerHTML = `<div class="al-empty alg-empty"><span>登录后可查看</span></div>`; return }
    const days = logDays(log.records)
    if (!days.length) {
      pane.innerHTML = log.phase === 'loading' || log.phase === 'idle' || log.phase === 'failed'
        ? `<div class="al-empty alg-empty"><span>${log.phase === 'failed' ? '暂时取不到记录' : '正在载入…'}</span></div>`
        // 照 iOS：「还没有响过的提醒」+ 一句 +「去创建」（切回列表、推创建页）
        : alertEmptyHTML('还没有响过的提醒', '提醒响了会按天记在这里', 'alerts.log.empty')
      return
    }
    pane.innerHTML = `<div class="alg-list">${days.map(d => `<section class="al-sec"><div class="al-title">${esc(d.title)}</div>
      <div class="al-card">${d.records.map((r, i) => logRowHTML(r, i === d.records.length - 1)).join('')}</div></section>`).join('')}</div>`
  }
  function show(t: Tab): void {
    tab = t
    body.querySelectorAll<HTMLElement>('[data-tab]').forEach(b => { const on = b.dataset.tab === t; b.classList.toggle('on', on); b.setAttribute('aria-selected', String(on)) })
    offList?.(); offList = null
    pane.innerHTML = ''
    pane.className = 'alhub-pane'
    foot.hidden = t !== 'list'
    paintAction()
    if (t === 'list') {
      offList = buildAlertList(pane, {
        pinned: symbol,
        onCreate: create,
        // 图上这只：开创建页（底下「当前提醒」点进去能改）；别的品种：关表去那只
        onOpen: a => { if (a.symbol === symbol) openAlertForm(symbol, S.symbols.get(symbol)?.price ?? price ?? null); else { sheet.close(); openSymbol(a.symbol) } },
      })
    } else {
      renderLog()
      void log.refresh(logOwner())
    }
  }
  async function clearLog(): Promise<void> {
    if (!(await confirmDialog({ title: '清空全部记录？', confirm: '清空', destructive: true }))) return
    if (!(await log.clear())) toast('没清掉，稍后再试')
  }

  body.querySelector<HTMLElement>('.alhub-seg')!.addEventListener('click', e => {
    const b = (e.target as HTMLElement).closest<HTMLElement>('[data-tab]')
    if (b && b.dataset.tab !== tab) show(b.dataset.tab as Tab)
  })
  // 日志里点一行：关表去那只
  pane.addEventListener('click', e => {
    if (tab !== 'log') return
    if ((e.target as HTMLElement).closest('[data-create]')) { show('list'); create(); return }
    const row = (e.target as HTMLElement).closest<HTMLElement>('.alg[data-sym]')
    const sym = row?.dataset.sym
    if (sym && sym !== symbol && S.symbols.has(sym)) { sheet.close(); openSymbol(sym) }
  })
  function create(): void { openAlertForm(symbol, S.symbols.get(symbol)?.price ?? price ?? null) }
  body.querySelector<HTMLElement>('.alhub-create')!.onclick = create
  offs.push(log.onChange(renderLog))
  log.select(logOwner())
  show('list')
  return sheet
}
