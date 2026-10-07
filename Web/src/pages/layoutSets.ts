/* Hkline Web · 多套图表布局（布局集）的切换菜单
 *
 * 格子底栏「图表布局」按钮旁一颗「当前那套的名字 ▾」：点开列出各套（当前打勾、前九套带 ⌥1…⌥9），
 * 列表尾「另存为… / 重命名 / 删除」——名字就在菜单那一行里改（回车定、Esc 取消），不弹新页。
 * 数据在 app/layouts.ts（纯函数），这里只管菜单；切过去之后各格怎么换由 chart.ts 的 applyLayoutSet 做。
 */
import { st, save } from '../app/store'
import { activeSet, deleteLayout, renameLayout, saveAsLayout, switchLayout, uniqueName, LAYOUT_N, MAX_LAYOUTS, NAME_MAX } from '../app/layouts'
import { menuFrom, closeMenu, toast, type MenuItem } from '../ui/overlay'
import { $, I, esc } from '../ui/dom'

/** 切到第 k 套之后 chart.ts 要做的（格子就地换品种 / 周期、底栏名字、工具栏） */
type Apply = () => void
type Edit = { kind: 'new' } | { kind: 'rename' } | { kind: 'delete' } | null

const N_WORD: Record<number, string> = { 1: '一图', 2: '两图', 3: '三图', 4: '四图', 6: '六图', 8: '八图', 9: '九图', 12: '十二图', 16: '十六图' }

export const currentSetName = (): string => activeSet(st.layouts).name
/** 格子底栏那颗按钮的内容：名字 + 小箭头 */
export const setButtonHTML = (): string => `<span class="set-name">${esc(currentSetName())}</span>${I('chevronDown', 'icon-16')}`
export function paintSetButtons(): void {
  const html = setButtonHTML(), tip = `布局「${currentSetName()}」：切换、另存、改名`
  document.querySelectorAll<HTMLElement>('.cell-foot [data-act="sets"]').forEach(e => { if (e.innerHTML !== html) e.innerHTML = html; e.dataset.tip = tip })
}

/** 切到某一套；就是当前这套返回 false */
export function switchTo(id: string, apply: Apply): boolean {
  if (!switchLayout(st, id)) return false
  save(); apply()
  return true
}
/** ⌥1…⌥9：切到第 k 套（从 0 数）；没有这一套返回 false（按键不吃） */
export function switchNth(k: number, apply: Apply): boolean {
  const set = st.layouts.sets[k]; if (!set) return false
  if (switchTo(set.id, apply)) toast(`布局「${set.name}」`, `${N_WORD[LAYOUT_N[set.layout]] ?? ''}`, 'check', 1600)
  return true
}

export function setsMenu(btn: HTMLElement, apply: Apply, edit: Edit = null): void {
  const b = st.layouts, cur = activeSet(b), full = b.sets.length >= MAX_LAYOUTS, only = b.sets.length <= 1
  const rows: MenuItem[] = b.sets.map((x, k): MenuItem => ({
    html: `<span class="set-row-name">${esc(x.name)}</span><span class="faint set-row-n">${N_WORD[LAYOUT_N[x.layout]] ?? ''}</span>`,
    check: true, checked: x.id === cur.id, sc: k < 9 ? `⌥ ${k + 1}` : '',
    run: () => { switchTo(x.id, apply) },
  }))
  const tail: MenuItem[] = edit?.kind === 'delete'
    ? [{ html: `<span class="danger-text">删除「${esc(cur.name)}」</span>`, icon: 'trash', run: () => { if (deleteLayout(st, cur.id)) { save(); apply(); toast('布局已删除', cur.name, 'trash', 2400) } } },
       { label: '取消', run: () => setsMenu(btn, apply) }]
    : [{ icon: 'plus', label: '另存为…', disabled: full, sc: full ? `最多 ${MAX_LAYOUTS} 套` : '', run: () => setsMenu(btn, apply, { kind: 'new' }) },
       { icon: 'pencil', label: '重命名', run: () => setsMenu(btn, apply, { kind: 'rename' }) },
       { icon: 'trash', label: '删除', disabled: only, run: () => setsMenu(btn, apply, { kind: 'delete' }) }]
  const m = menuFrom(btn, [{ header: '布局' }, ...rows, '-', ...tail], { width: 240 })
  if (edit?.kind === 'new' || edit?.kind === 'rename') inlineEdit(m, btn, apply, edit.kind)
}

/** 菜单里就地改名：改名是把当前那一行换成输入框；另存为是在当前那一行下面插一行输入框 */
function inlineEdit(m: HTMLElement, btn: HTMLElement, apply: Apply, kind: 'new' | 'rename'): void {
  const b = st.layouts, cur = activeSet(b), k = b.sets.indexOf(cur)
  const row = m.querySelectorAll<HTMLElement>('.mi')[k]; if (!row) return
  const box = document.createElement('div'); box.className = 'set-edit'
  const init = kind === 'new' ? uniqueName(b, cur.name) : cur.name
  box.innerHTML = `${I(kind === 'new' ? 'plus' : 'pencil', 'icon-16')}<input class="input" type="text" maxlength="${NAME_MAX}" aria-label="${kind === 'new' ? '新布局的名字' : '布局名字'}"><span class="faint">回车</span>`
  if (kind === 'new') row.after(box); else row.replaceWith(box)
  const inp = $<HTMLInputElement>('input', box)
  inp.value = init
  const reopen = (): void => setsMenu(btn, apply)
  // 输入框里的按键不往外冒：不让菜单的上下键、图表页的打字搜品种接走
  inp.addEventListener('keydown', e => {
    e.stopPropagation()
    if (e.key === 'Escape') { e.preventDefault(); reopen(); return }
    if (e.key !== 'Enter' || e.isComposing) return
    e.preventDefault()
    const name = inp.value.trim()
    if (!name) { inp.classList.add('bad'); return }
    if (kind === 'new') {
      const set = saveAsLayout(st, name); if (!set) { closeMenu(); return }
      save(); apply(); closeMenu()
      toast('已另存为新布局', set.name, 'check', 2400)
    } else {
      if (renameLayout(st.layouts, cur.id, name) != null) { save(); apply() }
      closeMenu()
    }
  })
  inp.addEventListener('input', () => inp.classList.remove('bad'))
  inp.addEventListener('click', e => e.stopPropagation())
  inp.focus(); inp.select()
}
