import { describe, it, expect } from 'vitest'
import { escOwner } from '../src/ui/overlay'

// Esc「谁在最上层谁吃掉」：菜单 / 弹层压在对话框上，开着就先关它；焦点在哪一层里就交给那一层自己
describe('escOwner', () => {
  const s = (o: Partial<Parameters<typeof escOwner>[0]>) => ({ menu: false, inMenu: false, dialogs: 0, inDialog: false, ...o })

  it('什么都没开：不管', () => {
    expect(escOwner(s({}))).toBe(null)
  })
  it('只开着菜单 / 弹层、焦点在外面：关菜单', () => {
    expect(escOwner(s({ menu: true }))).toBe('menu')
  })
  it('菜单开在对话框上（对话框里的下拉、右键）：先关菜单，对话框留着', () => {
    expect(escOwner(s({ menu: true, dialogs: 1 }))).toBe('menu')
    expect(escOwner(s({ menu: true, dialogs: 2, inDialog: true }))).toBe('menu')
  })
  it('焦点就在菜单里：交给菜单自己的 keydown（里面输入框可先接走）', () => {
    expect(escOwner(s({ menu: true, inMenu: true }))).toBe(null)
    expect(escOwner(s({ menu: true, inMenu: true, dialogs: 1 }))).toBe(null)
  })
  it('只开着对话框：焦点在里面交给它自己，掉到外面由兜底关最上面那个', () => {
    expect(escOwner(s({ dialogs: 1, inDialog: true }))).toBe(null)
    expect(escOwner(s({ dialogs: 1 }))).toBe('dialog')
  })
})
