/* Hkline Web · 我的 → 通用 →「从 TradingView 导入」
 *
 * 粘贴代号（BINANCE:BTCUSDT.P 这类，逗号或换行分隔）或选 TradingView 导出的 .txt，
 * 按币安合约表匹配后追加到自选末尾；自选改了就走现有的自选同步（save() 推云端）。
 * 解析与匹配是纯函数，在 tvImport.ts。
 */
import { st, save } from '../app/store'
import { S, TABS, type Kind } from '../market'
import { $, I, esc, tgt } from '../ui/dom'
import { toast } from '../ui/overlay'
import { importTv, applyTv, type TvResult, type TvUniverse } from './tvImport'
import '../styles/watch.css'

interface Last { r: TvResult; n: number }
let text = ''
let last: Last | null = null

const KIND_CN = Object.fromEntries(TABS) as Record<Kind, string>
const universe: TvUniverse = { has: s => S.symbols.has(s), kindOf: s => S.symbols.get(s)?.kind }

export function tvImportHTML(): string {
  const ready = S.symbols.size > 0
  return `<div class="group-title">从 TradingView 导入自选</div>
    <div class="group tvi" id="tvi">
      <textarea class="input tvi-text" id="tviText" rows="5" spellcheck="false" autocapitalize="off" aria-label="TradingView 代号"
        placeholder="粘贴代号，逗号或换行分隔，如 BINANCE:BTCUSDT.P, NASDAQ:NVDA；###分区 对应到加密 / 美股 / 大宗">${esc(text)}</textarea>
      <div class="tvi-bar">
        <label class="btn secondary sm tvi-file">${I('plus', 'icon-16')}选 .txt 文件<input type="file" accept=".txt,text/plain" id="tviFile" hidden></label>
        <span class="tvi-hint">${ready ? `按币安合约表匹配，共 ${S.symbols.size} 只；追加到各分类末尾` : '品种表还没取到，连上行情后再导入'}</span>
        <button class="btn primary sm" id="tviGo" ${ready ? '' : 'disabled'}>导入</button>
      </div>
      ${last ? resultHTML(last) : ''}
    </div>`
}

function resultHTML({ r, n }: Last): string {
  const by = (Object.keys(r.added) as Kind[]).filter(k => r.added[k].length).map(k => `${KIND_CN[k]} ${r.added[k].length}`).join(' · ')
  const head = n ? `导入 ${n} 只${by ? `：${by}` : ''}` : r.total ? '没有新品种' : '没认出代号'
  const parts: string[] = []
  if (r.already.length) parts.push(`已在自选 ${r.already.length} 只`)
  if (r.unmatched.length) parts.push(`对不上 ${r.unmatched.length} 只`)
  const secs = r.sections.length ? `<div class="tvi-row"><span class="k">分区</span><span>${r.sections.map(s => `${esc(s.name)} → ${KIND_CN[s.kind]}${s.mapped ? '' : '<span class="faint">（没有同名分类，并进加密）</span>'}`).join('　')}</span></div>` : ''
  const bad = r.unmatched.length ? `<div class="tvi-row"><span class="k">对不上</span><span class="tvi-bad">${r.unmatched.map(x => `<span class="tag">${esc(x)}</span>`).join('')}</span></div>` : ''
  return `<div class="tvi-result" id="tviResult" data-added="${n}" data-unmatched="${r.unmatched.length}" data-already="${r.already.length}">
      <div class="tvi-head">${I(n ? 'check' : 'info', 'icon-16')}<b>${head}</b>${parts.length ? `<span class="muted">${parts.join(' · ')}</span>` : ''}</div>
      ${secs}${bad}
    </div>`
}

function run(src: string, onDone: () => void): void {
  text = src
  if (!S.symbols.size) { toast('品种表还没取到', '连上行情后再导入', 'wifiOff', 2400); return }
  const r = importTv(src, universe, st.watch)
  const n = applyTv(st.watch, r)
  last = { r, n }
  if (n) {
    // 追加到末尾；切到新增最多的那一类，回到图表就能看到
    const top = (Object.keys(r.added) as Kind[]).sort((a, b) => r.added[b].length - r.added[a].length)[0]
    st.watchTab = top
    save()
    hooksAfter.forEach(f => f())
    toast(`已导入 ${n} 只自选`, r.unmatched.length ? `${r.unmatched.length} 只对不上` : '', 'star', 2400)
  }
  onDone()
}

/** 自选改了以后图表页要做的事（重画侧栏、改订阅），由调用方注入，免得这里反过来依赖图表页 */
const hooksAfter: (() => void)[] = []
export function onTvImported(f: () => void): void { hooksAfter.push(f) }

/** 「我的」页的点击 / 文件选择委托；返回 true 表示已处理 */
export function tvImportClick(e: MouseEvent, rerender: () => void): boolean {
  const t = tgt(e)
  if (t.closest('#tviGo')) { run(($('#tviText') as HTMLTextAreaElement | null)?.value || '', rerender); return true }
  return false
}
export function tvImportChange(e: Event, rerender: () => void): boolean {
  const inp = e.target as HTMLInputElement
  if (inp.id === 'tviText') { text = (inp as unknown as HTMLTextAreaElement).value; return true }
  if (inp.id !== 'tviFile' || !inp.files?.[0]) return false
  const f = inp.files[0]
  void f.text().then(src => run(src, rerender))
  return true
}
