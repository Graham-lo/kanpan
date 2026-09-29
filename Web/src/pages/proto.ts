/* Hkline Web · 原型控制台（顶栏中间的「原型」按钮）：不属于产品界面，给设计验收切皮肤与布局槽位用 */
import { st, save, resetAll } from '../app/store'
import { applyTheme, go } from '../app/shell'
import { $, tgt } from '../ui/dom'
import { layoutSlots, setLayout, renderPanel } from './chart'

function render(): void {
  const b = (k: string, v: string, l: string, on = false) => `<button data-pk="${k}" data-pv="${v}" class="${on ? 'on' : ''}">${l}</button>`
  $('#protoPanel').innerHTML = `<h4>原型控制台（不属于产品界面）</h4>
    <div class="pr"><span>皮肤</span><div class="pbtns">${b('skin', 'sage', '青苔', st.skin === 'sage')}${b('skin', 'terra', '陶土', st.skin === 'terra')}${b('skin', 'classic', '经典', st.skin === 'classic')}</div></div>
    <div class="pr"><span>深浅色</span><div class="pbtns">${b('theme', 'light', '浅色', st.theme === 'light')}${b('theme', 'dark', '深色', st.theme === 'dark')}</div></div>
    <div class="pr"><span>涨跌色</span><div class="pbtns">${b('updown', 'red-up', '红涨', st.updown === 'red-up')}${b('updown', 'green-up', '绿涨', st.updown === 'green-up')}</div></div>
    <div class="pr"><span>深度梯子列</span><div class="pbtns">${b('ladder', '1', '开', st.slots.ladder)}${b('ladder', '0', '关', !st.slots.ladder)}</div></div>
    <div class="pr"><span>底部抽屉</span><div class="pbtns">${b('drawer', '1', '开', st.slots.drawer)}${b('drawer', '0', '关', !st.slots.drawer)}</div></div>
    <h4 style="margin-top:12px">场景</h4>
    <div class="pbtns">${b('scene', 'four', '四图布局')}${b('scene', 'one', '一图布局')}${b('scene', 'reset', '恢复初始')}</div>
    <div class="note">状态记在本机浏览器里。「恢复初始」清掉这个网页存的全部状态。</div>`
}

export function initProto(): void {
  const panel = $('#protoPanel')
  $('#protoFab').onclick = () => { panel.classList.toggle('show'); render() }
  panel.addEventListener('click', e => {
    const x = tgt(e).closest<HTMLElement>('[data-pk]'); if (!x) return
    const k = x.dataset.pk, v = x.dataset.pv || ''
    if (k === 'skin') { st.skin = v as typeof st.skin; save(); applyTheme() }
    if (k === 'theme') { st.theme = v as typeof st.theme; save(); applyTheme() }
    if (k === 'updown') { st.updown = v as typeof st.updown; save(); applyTheme() }
    if (k === 'ladder' || k === 'drawer') { st.slots[k] = v === '1'; save(); go('chart'); layoutSlots() }
    if (k === 'scene') {
      if (v === 'four') { go('chart'); setLayout('4') }
      if (v === 'one') { go('chart'); setLayout('1') }
      if (v === 'reset') { resetAll(); location.href = location.pathname; return }
      renderPanel()
    }
    render()
  })
}
