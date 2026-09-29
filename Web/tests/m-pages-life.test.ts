/* 手机网页版 · 审查（页面）：一层界面的生命期（model/life.ts）
 * 回归的是三处真 bug 的机制：搜索页关掉后没摘的 hashchange 把下一次打开的搜索页关掉一半；
 * 关掉之后迟到的 ensureUniverse / 排着的帧把「search」订阅重新订上；登录请求回来时那一层已退，却照样弹栈。 */
import { describe, expect, it } from 'vitest'
import { layers, life } from '../src/m/model/life'
import { navStack } from '../src/m/model/navStack'

const fakeRaf = () => {
  const q = new Map<number, FrameRequestCallback>()
  let n = 0
  return {
    raf: (cb: FrameRequestCallback) => { q.set(++n, cb); return n },
    caf: (id: number) => { q.delete(id) },
    tick: () => { const cbs = [...q.values()]; q.clear(); cbs.forEach(cb => cb(0)) },
    get size() { return q.size },
  }
}

describe('手机网页版 · 审查（页面）：一层界面的生命期', () => {
  it('关掉的那一层摘掉自己的 hashchange：下一次打开的那层只被自己的监听关、只关一次', () => {
    const win = new EventTarget()
    let current: object | null = null
    const closes: string[] = []
    const open = (name: string) => {
      const L = life()
      const me = {}
      const close = () => { if (!L.end()) return; if (current === me) current = null; closes.push(name) }
      L.listen(win, 'hashchange', close)
      current = me
      return { me, close }
    }
    const a = open('A')
    a.close()                                   // 点「取消」关的
    const b = open('B')
    win.dispatchEvent(new Event('hashchange'))
    expect(closes).toEqual(['A', 'B'])          // A 的监听已摘掉，不会再替 B 关一次
    expect(current).toBe(null)
    win.dispatchEvent(new Event('hashchange'))
    expect(closes).toEqual(['A', 'B'])          // B 也摘干净了
    void b
  })

  it('关掉之后：排着的帧取消、迟到的回调不执行、登记的收尾各跑一次', () => {
    const f = fakeRaf()
    const L = life(f.raf, f.caf)
    const calls: string[] = []
    const schedule = L.frame(() => calls.push('render'))
    schedule(); schedule(); schedule()
    expect(f.size).toBe(1)                      // 同一帧只排一次
    f.tick()
    expect(calls).toEqual(['render'])
    schedule()
    const late = L.guard((x: string) => calls.push('late ' + x))
    let offs = 0
    L.add(() => offs++)
    expect(L.end()).toBe(true)
    expect(L.end()).toBe(false)                 // 幂等
    f.tick()
    late('universe')
    schedule()
    expect(calls).toEqual(['render'])           // 关掉之后什么都不再动
    expect(f.size).toBe(0)
    expect(offs).toBe(1)
    L.add(() => offs++)                         // 关掉之后才登记的收尾立刻跑
    expect(offs).toBe(2)
  })
})

describe('手机网页版 · 审查（页面）：「我的」页内导航栈', () => {
  it('登录请求在路上时退出登录层、推了「设置」：请求回来不许把「设置」弹掉', () => {
    const popped: string[] = []
    const s = navStack<string>((l, next) => popped.push(`${l}→${next}`))
    s.push('我的'); s.push('登录')
    const login = s.top!
    s.back(); s.push('设置')                      // 人在请求路上退回去、又进了设置
    expect(s.whenTop(login, () => s.popToRoot())).toBe(false)
    expect(s.top).toBe('设置')
    expect(popped).toEqual(['登录→我的'])
  })
  it('发起那层仍在栈顶：照常退回根；每一层都走收尾；根上再退什么都不做', () => {
    const popped: string[] = []
    const s = navStack<string>((l, next) => popped.push(`${l}→${next}`))
    s.push('我的'); s.push('账号'); s.push('修改密码')
    expect(s.whenTop('修改密码', () => s.back())).toBe(true)
    expect(s.top).toBe('账号')
    s.popToRoot()
    expect(s.depth).toBe(1)
    expect(s.back()).toBe(false)
    expect(popped).toEqual(['修改密码→账号', '账号→我的'])
  })
})

describe('手机网页版 · 审查（页面）：创建提醒面板里推进去的层', () => {
  it('推「编辑提醒」再退回：那层挂的行情 / 提醒监听当场摘掉，推几次都不叠；底层照常活着', () => {
    const f = fakeRaf()
    const base = life(f.raf, f.caf)
    const above = layers(() => life(f.raf, f.caf))
    const market = new EventTarget()
    let basePaints = 0, editPaints = 0
    base.listen(market, 'ticker', () => { basePaints++ })
    for (let i = 0; i < 5; i++) {
      const l = above.push()
      l.listen(market, 'ticker', () => { editPaints++ })
      above.settle(false) // 推进去之后：还在上面
      market.dispatchEvent(new Event('ticker'))
      above.settle(true) // 退回底层
    }
    expect(editPaints).toBe(5)
    expect(above.count).toBe(0)
    market.dispatchEvent(new Event('ticker'))
    expect(editPaints).toBe(5)
    expect(basePaints).toBe(6)
  })

  it('逐笔成交一帧里来几十下：现价只画一次；关掉面板时排着的那一帧取消', () => {
    const f = fakeRaf()
    const L = life(f.raf, f.caf)
    let paints = 0
    const soon = L.frame(() => { paints++ })
    for (let i = 0; i < 40; i++) soon()
    f.tick()
    expect(paints).toBe(1)
    soon(); L.end(); f.tick()
    expect(paints).toBe(1)
    expect(f.size).toBe(0)
  })
})
