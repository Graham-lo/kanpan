/* Hkline 手机网页版 · 系统「返回」接到 app 自己的返回
 *
 * 鸿蒙 / 安卓的侧边返回手势与返回键、Safari 左沿右划，浏览器都只会做 history.back()。
 * 壳换页一律 replaceState、不留历史，于是开着面板时一划就直接退出了 app——iOS 上同一个动作是「收掉最上面那层」。
 *
 * 做法：只要有一层能退（面板 / 菜单 / 确认框 / 解释卡 / 搜索盖板 / 「我的」推进去的层 / 图表页的来路），
 * 就在历史栈顶多垫一格同地址的「哨兵」。系统返回把哨兵弹掉 → popstate → 退最上面那一层 → 还有能退的就再垫一格。
 * 层是程序自己关掉的（点遮罩、点「‹」、换页），哨兵就用 history.back() 撤掉，那一次 popstate 不算返回。
 *
 * 每层可以带一个作用域（页 id）：只在那一页站着时才算数（「我的」里推进去的层切到别的页时不该被返回弹掉）。
 * 逻辑与浏览器隔开（BackEnv），单测不碰 DOM。
 */

export interface BackEnv {
  /** 垫一格哨兵（history.pushState） */
  arm(): void
  /** 撤掉哨兵（history.back） */
  disarm(): void
  /** popstate 来了 */
  onPop(fn: () => void): void
  /** 推迟到这一串同步动作之后（关一层紧接着开一层时不要来回撤垫） */
  defer(fn: () => void): void
  /** 撤哨兵若迟迟等不到 popstate（地址被外部改走了），多久后放弃等待 */
  timeout(fn: () => void, ms: number): void
  /** 每次 popstate 处理完（地址已回到上一格；壳在这里把 hash 改回当前页，免得 hashchange 把页切回去） */
  afterPop?(): void
}

export interface BackStack {
  /** 登记一层能退的；fn 是「退这一层」（关面板 / 回上一层）。返回注销函数 */
  add(fn: () => void, scope?: string): () => void
  /** 作用域可能变了（换页后壳调一次） */
  sync(): void
  /** 当前算数的层数 */
  readonly depth: number
  /** 哨兵在不在（测试用） */
  readonly armed: boolean
}

interface Entry { fn: () => void; scope?: string }

export function createBackStack(env: BackEnv, scopeNow: () => string | undefined = () => undefined, startArmed = false): BackStack {
  const entries: Entry[] = []
  let armed = startArmed
  let ignoring = false
  let pending = false
  let ignoreSeq = 0
  const live = (): Entry[] => { const s = scopeNow(); return entries.filter(e => e.scope == null || e.scope === s) }

  /** 让「有没有哨兵」与「有没有能退的层」一致 */
  const settle = (): void => {
    if (ignoring) return
    const want = live().length > 0
    if (want && !armed) { armed = true; env.arm() }
    else if (!want && armed) {
      armed = false; ignoring = true
      const seq = ++ignoreSeq
      env.disarm()
      env.timeout(() => { if (ignoring && seq === ignoreSeq) { ignoring = false; settle() } }, 800)
    }
  }
  const schedule = (): void => {
    if (pending) return
    pending = true
    env.defer(() => { pending = false; settle() })
  }

  env.onPop(() => {
    if (ignoring) { ignoring = false; env.afterPop?.(); settle(); return }
    if (!armed) { env.afterPop?.(); return } // 不是我们垫的那一格（早先残留的历史），只把地址摆正
    armed = false
    const top = live().at(-1)
    if (top) { try { top.fn() } catch (e) { console.error(e) } }
    env.afterPop?.()
    settle()
  })

  return {
    add(fn, scope) {
      const e: Entry = { fn, scope }
      entries.push(e)
      schedule()
      return () => {
        const i = entries.indexOf(e)
        if (i < 0) return
        entries.splice(i, 1)
        schedule()
      }
    },
    sync: schedule,
    get depth() { return live().length },
    get armed() { return armed },
  }
}

// ───────── 浏览器里的那一份 ─────────

const KEY = 'hklineBack'
let scopeGetter: () => string | undefined = () => undefined
let afterPopHook: () => void = () => {}
let inst: BackStack | null = null

function browserStack(): BackStack {
  if (inst) return inst
  // 刷新时历史还停在上一轮垫的哨兵上：当它已经垫着，没有层就会被撤掉
  const startArmed = typeof history !== 'undefined' && !!(history.state as Record<string, unknown> | null)?.[KEY]
  inst = createBackStack({
    arm: () => history.pushState({ [KEY]: 1 }, '', location.href),
    disarm: () => history.back(),
    onPop: fn => addEventListener('popstate', fn),
    defer: fn => queueMicrotask(fn),
    timeout: (fn, ms) => { setTimeout(fn, ms) },
    afterPop: () => afterPopHook(),
  }, () => scopeGetter(), startArmed)
  if (startArmed) inst.sync()
  return inst
}

/** 登记一层「系统返回会退掉的」；返回注销函数。scope 给页 id 时只在那一页站着时算数 */
export function onBack(fn: () => void, scope?: string): () => void {
  if (typeof window === 'undefined') return () => {}
  return browserStack().add(fn, scope)
}

/** 壳装上：作用域取当前页、popstate 之后把地址摆回当前页 */
export function installBack(scope: () => string | undefined, afterPop: () => void): void {
  scopeGetter = scope
  afterPopHook = afterPop
  browserStack()
}

/** 现在站着的作用域（页 id）：页内推层的登记时用 */
export function backScope(): string | undefined { return scopeGetter() }

/** 换页之后：作用域变了，重新对一下哨兵 */
export function syncBack(): void { inst?.sync() }
