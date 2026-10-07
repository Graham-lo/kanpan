/* P3-3：画线撤销栈一只品种一份——⌘Z 只退当前格这只品种的改动，不跨品种 */
import { describe, expect, it } from 'vitest'
import { UndoBySymbol, UNDO_CAP } from '../src/pages/undoStacks'

type Snap = { s: string; json: string }
/** 模拟页面：每只品种当前画线是一段 json，apply 装回快照并返回装之前的样子 */
function page() {
  const cur: Record<string, string> = {}
  const u = new UndoBySymbol<Snap>()
  const edit = (s: string, json: string): void => { u.push({ s, json: cur[s] ?? '[]' }); cur[s] = json }
  const apply = (x: Snap): Snap => { const inv = { s: x.s, json: cur[x.s] ?? '[]' }; cur[x.s] = x.json; return inv }
  return { cur, u, edit, undo: (s: string) => u.undo(s, apply), redo: (s: string) => u.redo(s, apply) }
}

describe('撤销栈按品种分开', () => {
  it('BTC 画了两条、ETH 画了一条：在 BTC 格 ⌘Z 只退 BTC 的最后一条，ETH 的线不动', () => {
    const p = page()
    p.edit('BTCUSDT', '[a]'); p.edit('ETHUSDT', '[x]'); p.edit('BTCUSDT', '[a,b]')
    expect(p.undo('BTCUSDT')).toBe(true)
    expect(p.cur).toEqual({ BTCUSDT: '[a]', ETHUSDT: '[x]' })
    expect(p.undo('BTCUSDT')).toBe(true)
    expect(p.cur.BTCUSDT).toBe('[]')
    // BTC 已经退到底：再按不会去退 ETH
    expect(p.undo('BTCUSDT')).toBe(false)
    expect(p.cur.ETHUSDT).toBe('[x]')
    expect(p.u.depth('ETHUSDT')).toEqual({ undo: 1, redo: 0 })
  })
  it('重做也只管这只品种；在别的品种上新改动不清掉这只的重做', () => {
    const p = page()
    p.edit('BTCUSDT', '[a]'); p.undo('BTCUSDT')
    p.edit('ETHUSDT', '[x]')
    expect(p.u.depth('BTCUSDT')).toEqual({ undo: 0, redo: 1 })
    expect(p.redo('BTCUSDT')).toBe(true)
    expect(p.cur.BTCUSDT).toBe('[a]')
    // 在 BTC 上新改动才清 BTC 的重做
    p.undo('BTCUSDT'); p.edit('BTCUSDT', '[c]')
    expect(p.u.depth('BTCUSDT').redo).toBe(0)
  })
  it('没碰过的品种：撤销 / 重做都是空操作；每只最多记 UNDO_CAP 步', () => {
    const p = page()
    expect(p.undo('SOLUSDT')).toBe(false)
    expect(p.redo('SOLUSDT')).toBe(false)
    for (let i = 0; i < UNDO_CAP + 20; i++) p.edit('BTCUSDT', `[${i}]`)
    expect(p.u.depth('BTCUSDT').undo).toBe(UNDO_CAP)
  })
})
