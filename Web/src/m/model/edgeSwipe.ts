/* 手机网页版 · 页内左沿右划返回的判定（照 iOS 导航栈的边缘手势；画面在 pages/me.ts）
 *
 * 跟手：手指从左沿起手往右拖，上面这层跟着走、下面那层从 -24% 往回挪；松手过半或甩得够快就退一层，否则弹回。
 * 和浏览器自己的返回别叠着触发：
 * - Safari 标签页里最左那一条归 Safari（它的左沿右划会 history.back，壳的 backStack 已经接住、只退一层）；
 *   我们从离左沿 16 起才接管，Safari 真的抢走时页面收到 touchcancel，我们就弹回不退。
 * - 鸿蒙 / 安卓的系统侧边返回在屏幕最边上、由系统做，同样只走 backStack；所以非 iOS 主屏幕模式一律让出最左 16。
 * - 只有 iOS 从主屏幕打开（standalone，没有浏览器的左沿手势）时从 0 起接管，和 App 一样。
 * 逻辑不碰 DOM，单测直接测。
 */

/** 起手区：[min, max)，单位 CSS px */
export function edgeZone(standaloneIOS: boolean): { min: number; max: number } {
  return standaloneIOS ? { min: 0, max: 28 } : { min: 16, max: 44 }
}

/** 起手点在不在起手区里 */
export const inEdgeZone = (x: number, standaloneIOS: boolean): boolean => {
  const z = edgeZone(standaloneIOS)
  return x >= z.min && x < z.max
}

/** 起手先判方向（照 iOS 的边缘手势与 swipeRow）：挪过 8 点才判；横向占优且往右才算我们的，否则这一趟让给纵向滚动 */
export function edgeIntent(dx: number, dy: number): 'wait' | 'claim' | 'abandon' {
  if (Math.hypot(dx, dy) < 8) return 'wait'
  return dx > 0 && Math.abs(dx) > Math.abs(dy) ? 'claim' : 'abandon'
}

/** 拖到的进度 0…1 */
export const edgeProgress = (dx: number, width: number): number => width > 0 ? Math.min(1, Math.max(0, dx / width)) : 0

/** 松手：过半退；没过半但往右甩得够快（≥ 0.5 px/ms，约 iOS 的 500 pt/s）也退；往回甩的一律弹回 */
export function edgeShouldPop(dx: number, width: number, vx: number): boolean {
  if (vx < -0.1) return false
  return edgeProgress(dx, width) > 0.5 || (vx >= 0.5 && dx > 0)
}
