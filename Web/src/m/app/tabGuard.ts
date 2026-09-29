/* Hkline 手机网页版 · 两个标签页（Safari 两个标签、或者网页与添加到主屏幕那份）共用一份本机状态
 *
 * 本机状态（hkline-m-v1）与画线本（hkline-m-drawings-v1）都是整份写的：不管的话，后台那页一存
 * （同步拉到东西、提醒响了、滚动位置）就把另一页刚改的皮肤、自选、画线整份盖回旧的；而且只有领头那页
 * 推拉同步，非领头页的改动领头页读不到，永远上不了云端。
 *
 * 规矩照 PC 的 app/store.ts tabGuard：人最近一次动过的那页内存为准。每次写盘顺带记下「写的这页最近一次
 * 被人动的时刻」；
 *   · 别的页写了，而它比我更近被人动过：我这份旧了，此后不再写盘；人一回到这页（变可见、获得焦点、
 *     或者直接在这页上点 / 按键）就整页重载，读新的（重载后领头的那页会把新状态记账推上去）；
 *   · 别的页写了，但我才是更近被人动过的（它是后台自动存的旧内存）：立刻用我这份把两份都写回去。
 *
 * 手机上多出来的一条：同步只有领头那页推拉（Web Locks），而 iOS 会把后台标签页冻很久——领头页一直
 * 不回来，非领头页的改动就一直上不了云端。所以旧了的页还会把别的页写下的那份「收养」进内存（不写盘、
 * 不动界面上的人为操作，只走平常 save() 的通知），领头的同步据此记账推上去；人回到这页照旧整页重载。
 * 读不出 / 解不开的存档不收养（否则同步会把「空的」当成本机删光了推上去）。
 */
const WRITER_KEY = 'hkline-m-v1-writer'

interface Writer { serialize: () => string; adopt?: () => void }
const writers = new Map<string, Writer>()
let adoptTimer: ReturnType<typeof setTimeout> | null = null
const pendingAdopt = new Set<string>()
let stale = false
let touchedAt = 0

function ls(): Storage | null { try { return globalThis.localStorage ?? null } catch { return null } }

/** 写进本机存储；返回写成了没有（存储满了、被禁用时是 false：这一轮不落盘，内存照常用，下一次写再试） */
function put(key: string, value: string): boolean {
  const s = ls(); if (!s) return false
  try {
    s.setItem(WRITER_KEY, JSON.stringify({ at: touchedAt }))
    s.setItem(key, value)
    return true
  } catch (e) {
    console.warn('[m] 本机存储写不进去', key, e)
    return false
  }
}

export const tabGuard = {
  /** 登记一份整份写的存档：key、「现在该写什么」、以及旧了之后怎么把别的页写的那份收进内存 */
  register(key: string, serialize: () => string, adopt?: () => void): void { writers.set(key, { serialize, adopt }) },
  /** 写这一份（已经被别的页比下去了就不写，免得把新的盖成旧的）。返回真的写进去了没有 */
  write(key: string): boolean {
    const w = writers.get(key)
    if (stale || !w) return false
    return put(key, w.serialize())
  },
  /** 别的标签页写了登记过的键；theirs = 它写时记下的「最近被人动的时刻」 */
  onForeignWrite(theirs: number, key: string | null = null): 'stale' | 'repair' {
    if (stale || theirs >= touchedAt) {
      stale = true
      if (key && writers.get(key)?.adopt) { pendingAdopt.add(key); adoptTimer ??= setTimeout(adoptNow, 300) }
      return 'stale'
    }
    for (const [k, w] of writers) put(k, w.serialize())
    return 'repair'
  },
  /** 测试用：立刻收养排着的 */
  flush(): void { if (adoptTimer) { clearTimeout(adoptTimer); adoptNow() } },
  touch(now = Date.now()): void { touchedAt = now },
  get stale(): boolean { return stale },
  /** 测试用 */
  reset(): void { stale = false; touchedAt = 0; pendingAdopt.clear(); if (adoptTimer) clearTimeout(adoptTimer); adoptTimer = null },
}

function adoptNow(): void {
  adoptTimer = null
  const keys = [...pendingAdopt]; pendingAdopt.clear()
  for (const k of keys) { try { writers.get(k)?.adopt?.() } catch (e) { console.error(e) } }
}

function theirs(): number {
  try { return Number(JSON.parse(ls()?.getItem(WRITER_KEY) || '{}').at) || 0 } catch { return Infinity }
}

if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  window.addEventListener('storage', e => {
    if (e.key !== null && !writers.has(e.key)) return
    tabGuard.onForeignWrite(theirs(), e.key)
  })
  const back = (): void => { if (stale) location.reload() }
  // 人在这页上动手：旧了就先重载（这一下不生效，免得改在旧内存上又被丢掉），没旧就记下时刻
  const hand = (e: Event): void => {
    if (stale) { e.preventDefault(); e.stopImmediatePropagation(); location.reload(); return }
    tabGuard.touch()
  }
  window.addEventListener('pointerdown', hand, true)
  window.addEventListener('keydown', hand, true)
  window.addEventListener('focus', back)
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') back() })
  window.addEventListener('pageshow', back)
}
