/* Hkline Web · 主力订单流 · 开图要等的两样东西记在本机（localStorage）
 *
 * - 步长：按前一 UTC 日收盘 × 0.1% 推（bucket.ts derivedStep），一天只变一次。按「代号 + 参考日」记：
 *   同一天再开直接用、不再问交易所；参考日过了（最多留 7 天）先拿上一份开张、取历史，新的一到再按 retarget 改过来。
 * - 标定门槛：美股、贵金属这类按盘口深度定门槛的，标定要等各本簿都就绪（最多 8 秒）。上一次标出来的记下（留 3 天），
 *   下次先拿它出帧、取历史，后台照样再标一次，标完有出入再改。
 * 两张表都只留 64 条，满了丢最旧的。存不下（满了、隐私模式）就当没有。
 */
export const STEP_CACHE_KEY = 'hkline-orderflow-step-v1'
export const CALIB_CACHE_KEY = 'hkline-orderflow-calib-v1'
const DAY_MS = 86_400_000
/** 参考日落后这么多天以内的步长还能先拿来开张 */
export const STEP_KEEP_MS = 7 * DAY_MS
/** 标定门槛留多久 */
export const CALIB_KEEP_MS = 3 * DAY_MS
export const START_CACHE_MAX = 64

interface KV { getItem(k: string): string | null; setItem(k: string, v: string): void }
const kv = (): KV | null => { try { return (globalThis as { localStorage?: KV }).localStorage ?? null } catch { return null } }

type Entry = { at: number } & Record<string, number>
function readMap(key: string): Record<string, Entry> {
  try {
    const v = JSON.parse(kv()?.getItem(key) ?? '{}') as unknown
    return v && typeof v === 'object' && !Array.isArray(v) ? v as Record<string, Entry> : {}
  } catch { return {} }
}
function writeEntry(key: string, id: string, e: Entry): void {
  const store = kv()
  if (!store) return
  try {
    const all = readMap(key)
    all[id] = e
    const ids = Object.keys(all)
    if (ids.length > START_CACHE_MAX) {
      ids.sort((a, b) => (all[a]?.at ?? 0) - (all[b]?.at ?? 0))
      for (const k of ids.slice(0, ids.length - START_CACHE_MAX)) delete all[k]
    }
    store.setItem(key, JSON.stringify(all))
  } catch { /* 存不下就不记 */ }
}

/** 本机记着的步长：exact = 就是这个参考日的；参考日落后 7 天以上、或比参考日还新（时钟乱了）当没有 */
export function cachedStep(symbol: string, refDay: number): { step: number; exact: boolean } | null {
  const e = readMap(STEP_CACHE_KEY)[symbol.toUpperCase()]
  if (!e || !(typeof e.step === 'number' && e.step > 0) || typeof e.day !== 'number') return null
  if (e.day > refDay || refDay - e.day > STEP_KEEP_MS) return null
  return { step: e.step, exact: e.day === refDay }
}
export function storeStep(symbol: string, refDay: number, step: number): void {
  if (!(step > 0) || !Number.isFinite(step)) return
  writeEntry(STEP_CACHE_KEY, symbol.toUpperCase(), { at: refDay, day: refDay, step })
}

/** 上一次标定出来的门槛（3 天内）；没有是 null */
export function cachedCalibration(base: string, now: number): number | null {
  const e = readMap(CALIB_CACHE_KEY)[base.toUpperCase()]
  if (!e || !(typeof e.threshold === 'number' && e.threshold > 0) || typeof e.at !== 'number') return null
  if (e.at > now + 60_000 || now - e.at > CALIB_KEEP_MS) return null
  return e.threshold
}
export function storeCalibration(base: string, threshold: number, now: number): void {
  if (!(threshold > 0) || !Number.isFinite(threshold)) return
  writeEntry(CALIB_CACHE_KEY, base.toUpperCase(), { at: now, threshold })
}
