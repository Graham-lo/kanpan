/* 手机网页版 · 一层界面的生命期（搜索页、创建提醒、「我的」推进去的表单这类会被关掉的东西）
 *
 * 关掉一层时，它挂过的全局监听、排着的下一帧、还在路上的请求回调必须一起作废——
 * 否则关掉之后迟到的那一下会去碰别人：搜索页关了以后迟到的 ensureUniverse / 排着的那一帧
 * 会把「search」的订阅重新订上；上一次搜索没摘掉的 hashchange 会把下一次打开的搜索页关掉一半
 * （状态清了、盖板还留在屏上）；登录请求回来时那一层早被退掉了，却照样 popToRoot 把人家后来推的层弹掉。
 *
 *   const L = life()
 *   L.listen(window, 'hashchange', close)        // end() 时摘掉
 *   L.add(on(marketEvent))                        // 登记收尾
 *   promise.then(L.guard(() => render()))         // end() 之后到的回调什么都不做
 *   const schedule = L.frame(render)              // 同一帧里多次调用只跑一次，end() 时取消
 *   L.end()                                       // 只第一次返回 true
 */
export interface Life {
  readonly ended: boolean
  listen(target: EventTarget | null | undefined, type: string, fn: EventListener, opts?: AddEventListenerOptions): void
  add(off: () => void): void
  guard<A extends unknown[]>(fn: (...a: A) => void): (...a: A) => void
  frame(fn: () => void): () => void
  end(): boolean
}

type Raf = (cb: FrameRequestCallback) => number
type Caf = (id: number) => void

export function life(
  raf: Raf = cb => requestAnimationFrame(cb),
  caf: Caf = id => cancelAnimationFrame(id),
): Life {
  let ended = false
  const offs: (() => void)[] = []
  const L: Life = {
    get ended() { return ended },
    listen(target, type, fn, opts) {
      if (!target || ended) return
      target.addEventListener(type, fn, opts)
      offs.push(() => target.removeEventListener(type, fn, opts))
    },
    add(off) { if (ended) off(); else offs.push(off) },
    guard: fn => (...a) => { if (!ended) fn(...a) },
    frame(fn) {
      let id = 0
      offs.push(() => { if (id) caf(id); id = 0 })
      return () => {
        if (ended || id) return
        id = raf(() => { id = 0; if (!ended) fn() })
      }
    },
    end() {
      if (ended) return false
      ended = true
      offs.splice(0).reverse().forEach(f => f())
      return true
    },
  }
  return L
}

/** 叠在一层底上、推进去又会退回来的那几层（面板 sheet.push 推的「编辑提醒」「全部预警」）。
 *  推一层就开一段生命期；退回底层（settle(true)）时这些层一起收尾——否则退回去的那张表
 *  还挂着行情与提醒监听，每来一笔都去画一张已经不在屏上的表，推几次就叠几份，直到整张面板关掉。 */
export interface Layers {
  readonly count: number
  push(): Life
  settle(atBase: boolean): void
  endAll(): void
}
export function layers(make: () => Life = () => life()): Layers {
  const open: Life[] = []
  const endAll = (): void => { open.splice(0).reverse().forEach(l => l.end()) }
  return {
    get count() { return open.length },
    push() { const l = make(); open.push(l); return l },
    settle(atBase) { if (atBase) endAll() },
    endAll,
  }
}
