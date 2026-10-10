/* Hkline Web · 画布上的字号（价格轴标签、关键价位、十字线读数、图上小字…）集中从这里取
 *
 * 画布不吃 CSS，原来各处直接写 11 / 12 px。2026-10-10 起一律按字号令牌取：canvasPx(12) = app.css 里 --t12 的计算值，
 * 以后按视口分档的「密度层级」令牌改了 --t11 / --t12，画布上的字跟着走。读不到（node 单测、令牌没定义）就用档位本身。
 * 令牌变了（换视口档 / 换皮肤）调 refreshCanvasType() 清缓存，再让图重画。
 */
const cache = new Map<number, number>()

/** 字号令牌 --t{step} 的像素值（step = 11 / 12 / 13 / 14 / 16…） */
export function canvasPx(step: number): number {
  const hit = cache.get(step); if (hit != null) return hit
  let px = step
  try {
    if (typeof document !== 'undefined' && document.documentElement) {
      const v = parseFloat(getComputedStyle(document.documentElement).getPropertyValue(`--t${step}`))
      if (Number.isFinite(v) && v > 0) px = v
    }
  } catch { /* 没有 DOM：用档位 */ }
  cache.set(step, px)
  return px
}
/** 令牌换了：清掉缓存，下次取现读 */
export function refreshCanvasType(): void { cache.clear() }
/** 价格轴标签高：跟 --t12 走（12 px 时 20 px，字上下各留 4 px） */
export function axisTagH(): number { return Math.round(canvasPx(12) * 5 / 3) }
