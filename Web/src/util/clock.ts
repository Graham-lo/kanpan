/* Hkline Web · 墙上时钟往回拨时的「过了多久」
 *
 * 缓存过期、节流、失败重试、看门狗都用 Date.now() 记时间点、再拿「现在 − 那时」比阈值。系统时钟往回拨
 * （手动改时间、电脑时钟原本快了被校回来）之后，这个差是负的：「一分钟内取过」会一直成立到时钟追回来那一刻，
 * 往回拨两小时，详情、持仓额、板块走势、同步、订单流就整整停两小时（2026-10-05 F 线挂机压测）。
 * 往前跳（睡眠唤醒）不用管：差变大，本来就该重取。
 *
 * 不能改用 performance.now()：电脑睡眠时它不走，睡一夜醒来缓存还当是新的。
 */

/** 往回拨不到这么多（NTP 微调、两处取时有先后）当作刚刚发生，不为此重连 / 重取 */
export const CLOCK_SKEW_MS = 5_000

/** 从 at 到 now 过了多久（毫秒）。at 比 now 还晚超过 CLOCK_SKEW_MS ⇒ 时钟往回拨过，真实间隔不可知，
 *  当作早就过期（Infinity）：缓存照常重取、节流放行、失败照常重试、看门狗照常查 */
export function ago(at: number, now = Date.now()): number {
  const d = now - at
  return d >= 0 ? d : d > -CLOCK_SKEW_MS ? 0 : Infinity
}

/** 「until 之前先别做」（失败退避、作废留撤销）还没到点？剩下的比当初定的最长时长 span 还长，说明时钟往回拨过：
 *  当作已经到点——不然往回拨多久就要多等多久 */
export function before(until: number, span: number, now = Date.now()): boolean {
  const left = until - now
  return left > 0 && left <= span + CLOCK_SKEW_MS
}
