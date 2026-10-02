/* 手机网页版 · 页内导航栈（「我的」推进去的那几层；照 iOS NavigationStack 的语义）
 *
 * 只管「谁在栈里、谁在栈顶」，画面由调用方在 popped 里做。
 * whenTop：异步请求回来时用——只有发起它的那一层仍在栈顶才动导航。人在请求路上退出那一层、
 * 又推了别的层时，迟到的 popToRoot / back 不能把人家后来推的那层弹掉。
 *
 * 根以上的每一层都登记进系统返回（../ui/backStack）：鸿蒙 / 安卓侧边返回、Safari 左沿右划退一层，
 * 作用域是推进去那一刻站着的页——切到别的页时，「我的」里还开着的层不会被那边的返回弹掉。
 */
import { onBack, backScope } from '../ui/backStack'

export interface NavStack<T> {
  readonly depth: number
  readonly top: T | undefined
  push(l: T): void
  /** 退一层；已在根上返回 false */
  back(): boolean
  popToRoot(): void
  whenTop(l: T, fn: () => void): boolean
}

export function navStack<T>(popped: (l: T, next: T) => void): NavStack<T> {
  const items: T[] = []
  /** 与 items 对齐：每层的系统返回注销函数（根那层没有） */
  const unback: ((() => void) | null)[] = []
  const s: NavStack<T> = {
    get depth() { return items.length },
    get top() { return items[items.length - 1] },
    push(l) {
      items.push(l)
      unback.push(items.length > 1 ? onBack(() => { if (items[items.length - 1] === l) s.back() }, backScope()) : null)
    },
    back() {
      if (items.length <= 1) return false
      const l = items.pop()!
      unback.pop()?.()
      popped(l, items[items.length - 1])
      return true
    },
    popToRoot() { while (s.back()) { /* 一层一层退，每层都走 popped 收尾 */ } },
    whenTop(l, fn) {
      if (items[items.length - 1] !== l) return false
      fn()
      return true
    },
  }
  return s
}
