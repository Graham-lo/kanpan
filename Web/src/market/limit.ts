/* Hkline Web · 交易所 REST 限流闸
 *
 * 币安按 IP 计权重（合约 2400 / 分钟），超了回 429；429 之后还接着打，就升级成 418 封 IP——
 * 这台电脑和用户的手机常常是同一个出口 IP，封了连 iOS 端也取不到行情。
 * 所以任何一个主机回了 429 / 418，这个主机在冷却期内的请求一律在本地直接失败，不再发出去；
 * 冷却按 Retry-After（跨域读不到时 429 记 60 秒、418 记 5 分钟）。
 * 按主机名分：fapi / dapi / 现货 / OKX 各有各的额度，一家限流不连累别家。
 */

export const COOL_429_MS = 60_000
export const COOL_418_MS = 300_000

const until = new Map<string, number>()

function hostOf(url: string): string {
  try { return new URL(url, 'http://localhost').host } catch { return url }
}

/** 这个地址的主机还要冷却多久（毫秒）；0 = 可以发 */
export function coolingFor(url: string, now = Date.now()): number {
  const t = until.get(hostOf(url))
  if (t == null) return 0
  if (t <= now) { until.delete(hostOf(url)); return 0 }
  return t - now
}

/** 记一次响应：429 / 418 就把主机关进冷却；其它状态什么都不做 */
export function noteStatus(url: string, status: number, retryAfter?: string | null, now = Date.now()): void {
  if (status !== 429 && status !== 418) return
  const sec = retryAfter != null && retryAfter !== '' ? Number(retryAfter) : NaN
  const ms = Number.isFinite(sec) && sec > 0 ? sec * 1000 : status === 418 ? COOL_418_MS : COOL_429_MS
  const host = hostOf(url)
  until.set(host, Math.max(until.get(host) ?? 0, now + ms))
}

/** 冷却中的请求抛的错；消息带状态码开头，和真的 429 一样好认 */
export class RateLimited extends Error {
  constructor(readonly url: string, readonly waitMs: number) {
    super(`429 限流冷却中（${Math.ceil(waitMs / 1000)} 秒） ${url}`)
  }
}

export const isRateLimit = (e: unknown): boolean =>
  e instanceof RateLimited || /^(429|418)\b/.test(String((e as Error)?.message ?? e))

/** 测试用 */
export function resetLimits(): void { until.clear() }
