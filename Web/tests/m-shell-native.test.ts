// 手机网页版 · 壳的「像 app」那几件：系统返回接到 app 的返回、面板躲键盘、长按菜单、看图不锁屏
import { describe, expect, it } from 'vitest'
import { createBackStack, type BackEnv } from '../src/m/ui/backStack'
import { keyboardInset, sheetHeight, SHEET_FLOAT } from '../src/m/ui/sheet'
import { allowsSystemMenu, wantsWakeLock } from '../src/m/ui/native'

/** 假的浏览器历史：entries 是一摞，idx 指当前；back() 之后 popstate 异步到达（与浏览器一致） */
function fakeHistory() {
  let depth = 1
  const log: string[] = []
  let pop: () => void = () => {}
  const micro: (() => void)[] = []
  const later: (() => void)[] = []
  const env: BackEnv = {
    arm: () => { depth++; log.push('arm') },
    disarm: () => { log.push('disarm'); later.push(() => { depth--; pop() }) },
    onPop: fn => { pop = fn },
    defer: fn => { micro.push(fn) },
    timeout: () => {},
    afterPop: () => log.push('afterPop'),
  }
  return {
    env, log,
    get depth() { return depth },
    /** 跑完这一串同步动作之后的微任务 */
    flush() { while (micro.length) micro.shift()!() },
    /** 浏览器把排着的 popstate 发出来 */
    tick() { while (later.length) later.shift()!(); this.flush() },
    /** 用户做了一次系统返回（侧边返回 / Safari 左沿右划） */
    systemBack() { depth--; pop(); this.flush() },
  }
}

describe('系统返回 · backStack', () => {
  it('开一层就垫一格哨兵；系统返回退掉这一层、不再垫', () => {
    const h = fakeHistory()
    const b = createBackStack(h.env)
    let open = true
    const off = b.add(() => { open = false; off() })
    h.flush()
    expect(b.armed).toBe(true)
    expect(h.depth).toBe(2)
    h.systemBack()
    expect(open).toBe(false)
    expect(b.armed).toBe(false)
    expect(h.depth).toBe(1) // 没有多出来的历史，再返回一次才是离开
  })

  it('叠两层：一次返回只退最上面那层，还有层就再垫一格', () => {
    const h = fakeHistory()
    const b = createBackStack(h.env)
    const closed: string[] = []
    const offA = b.add(() => { closed.push('A'); offA() })
    const offB = b.add(() => { closed.push('B'); offB() })
    h.flush()
    expect(h.log.filter(x => x === 'arm')).toHaveLength(1)
    h.systemBack()
    expect(closed).toEqual(['B'])
    expect(b.armed).toBe(true)
    expect(h.depth).toBe(2)
    h.systemBack()
    expect(closed).toEqual(['B', 'A'])
    expect(h.depth).toBe(1)
  })

  it('层被程序自己关掉（点遮罩）：撤掉哨兵，那一次 popstate 不算返回', () => {
    const h = fakeHistory()
    const b = createBackStack(h.env)
    let calls = 0
    const off = b.add(() => { calls++ })
    h.flush()
    off(); h.flush()
    expect(h.log).toContain('disarm')
    h.tick()
    expect(calls).toBe(0)
    expect(h.depth).toBe(1)
    expect(h.log.at(-1)).toBe('afterPop') // 壳在这里把 hash 摆回当前页
  })

  it('关一层紧接着开一层（同一串动作里）：哨兵不来回撤垫', () => {
    const h = fakeHistory()
    const b = createBackStack(h.env)
    const off = b.add(() => {})
    h.flush()
    off(); b.add(() => {}); h.flush()
    expect(h.log).toEqual(['arm'])
  })

  it('撤哨兵的路上又开了一层：等那次 popstate 回来再垫', () => {
    const h = fakeHistory()
    const b = createBackStack(h.env)
    const off = b.add(() => {})
    h.flush()
    off(); h.flush()
    b.add(() => {}); h.flush()
    expect(b.armed).toBe(false)
    h.tick()
    expect(b.armed).toBe(true)
    expect(h.depth).toBe(2)
  })

  it('作用域：别的页的层不算数，切回那页才垫', () => {
    const h = fakeHistory()
    let page = 'me'
    const b = createBackStack(h.env, () => page)
    let popped = 0
    b.add(() => { popped++ }, 'me')
    h.flush()
    expect(b.armed).toBe(true)
    page = 'chart'; b.sync(); h.flush(); h.tick()
    expect(b.armed).toBe(false)
    expect(b.depth).toBe(0)
    page = 'me'; b.sync(); h.flush()
    expect(b.armed).toBe(true)
    expect(popped).toBe(0)
  })

  it('刷新时停在上一轮的哨兵上、又没有层：撤掉它', () => {
    const h = fakeHistory()
    const b = createBackStack(h.env, () => undefined, true)
    b.sync(); h.flush()
    expect(h.log).toEqual(['disarm'])
  })

  it('不是我们垫的那一格被弹掉：什么层都不动，只摆正地址', () => {
    const h = fakeHistory()
    const b = createBackStack(h.env)
    let calls = 0
    b.add(() => { calls++ }, 'me')
    // 作用域对不上 → 没垫
    h.systemBack()
    expect(calls).toBe(0)
    expect(h.log).toEqual(['afterPop'])
  })
})

describe('面板 · 键盘与档位', () => {
  it('键盘盖住的高度：布局视口底到可视视口底，地址栏这种小伸缩不算', () => {
    expect(keyboardInset(932, 0, 932)).toBe(0)
    expect(keyboardInset(932, 0, 596)).toBe(336)
    // iOS 把可视视口往下推了一截（offsetTop）也照算
    expect(keyboardInset(932, 120, 476)).toBe(336)
    expect(keyboardInset(720, 0, 690)).toBe(0)
  })

  it('档位高度：medium 半屏、large 留出状态栏、auto 按内容封顶；键盘起来时 medium 撑到 large', () => {
    const base = { view: 932, safeTop: 59, content: 300 }
    expect(sheetHeight('medium', base)).toBe(Math.round(932 * 0.52))
    expect(sheetHeight('large', base)).toBe(932 - 59 - 10)
    expect(sheetHeight('auto', base)).toBe(300)
    expect(sheetHeight('auto', { ...base, content: 2000 })).toBe(932 - 59 - 10 - SHEET_FLOAT)
    expect(sheetHeight('medium', { view: 596, safeTop: 59, content: 300, kb: 336 })).toBe(596 - 59 - 10)
    // 没有刘海（鸿蒙 nova 16 的安全区上沿是 0）：至少留 20
    expect(sheetHeight('large', { view: 720, safeTop: 0, content: 0 })).toBe(720 - 20 - 10)
  })
})

describe('长按菜单与不锁屏', () => {
  const node = (match: boolean) => ({ closest: () => (match ? {} : null) }) as unknown as Element
  it('只有输入框、可编辑区里长按才放系统菜单', () => {
    expect(allowsSystemMenu(node(true))).toBe(true)
    expect(allowsSystemMenu(node(false))).toBe(false)
    expect(allowsSystemMenu(null)).toBe(false)
    expect(allowsSystemMenu({} as EventTarget)).toBe(false)
  })

  it('照 KeepAwakeGate：图表页在前台才撑着屏幕，没充电且电量 ≤ 20% 放手，电量未知不算低电', () => {
    const on = { onChart: true, visible: true, charging: false, battery: 0.8 }
    expect(wantsWakeLock(on)).toBe(true)
    expect(wantsWakeLock({ ...on, onChart: false })).toBe(false)
    expect(wantsWakeLock({ ...on, visible: false })).toBe(false)
    expect(wantsWakeLock({ ...on, battery: 0.2 })).toBe(false)
    expect(wantsWakeLock({ ...on, battery: 0.2, charging: true })).toBe(true)
    expect(wantsWakeLock({ ...on, battery: -1 })).toBe(true)
  })
})
