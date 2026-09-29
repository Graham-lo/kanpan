/* Hkline Web · 复盘页
 *
 * 复盘的成交来自用户连上的交易所只读密钥，回合拼接与统计在 kanpan-api 里算，所以必须先登录。
 * 网页版登录下一阶段接入；这一阶段只放空态，不放演示成交。
 */
import { hooks, go } from '../app/shell'
import { $, I } from '../ui/dom'

function render(): void {
  const el = $('#page-review')
  el.style.gridTemplateColumns = '1fr'
  el.style.gridTemplateRows = '1fr'
  el.innerHTML = `<div class="card" style="display:grid;place-items:center">
    <div class="empty" style="max-width:420px">${I('trades', 'icon-24')}
      <div style="font-size:16px;color:var(--text-1);font-weight:600;margin-top:8px">复盘需要登录</div>
      <div style="margin-top:4px">成交从你连上的交易所只读密钥里拉，回合拼接和统计在服务端算。网页版登录下一阶段接入，现在可以在手机上看。</div>
      <button class="btn secondary" style="margin-top:16px" id="rvChart">回到图表</button>
    </div></div>`
  $('#rvChart').onclick = () => go('chart')
}

export function initReview(): void { hooks.pageShown.review = render }
