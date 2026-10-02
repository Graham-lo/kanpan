/* 手机网页版 · 设置「恢复默认」与它的撤销（照 iOS PrefsStore.resetToDefaults / restore(_:from:)）
 *
 * - 恢复默认只动体验类设置（Prefs 的字段）：回到出厂值，本机字段（行情线路）留着；
 *   自选、提醒、当前品种、页面这些不是设置，一个不碰。
 * - 返回这次真改到的字段和改之前的整份，交给「撤销」：撤销只把这几个字段还原，
 *   撤销窗口那几秒里在别处改的、云端刚落地的别的字段不被抹掉。
 */
import { defaultPrefs, DEVICE_ONLY_FIELDS, sameValue, type Prefs } from '../app/prefs'

export type PrefKey = keyof Prefs

const clone = <T>(v: T): T => (v === undefined ? v : JSON.parse(JSON.stringify(v)) as T)

/** 恢复默认（原地改 target）；返回改到的字段与改之前那几项的值 */
export function resetPrefs(target: Prefs): { changed: PrefKey[]; before: Partial<Prefs> } {
  const d = defaultPrefs()
  const deviceOnly = new Set<string>(DEVICE_ONLY_FIELDS)
  const changed: PrefKey[] = []
  const before: Partial<Prefs> = {}
  for (const k of Object.keys(d) as PrefKey[]) {
    if (deviceOnly.has(k) || sameValue(target[k], d[k])) continue
    changed.push(k)
    ;(before as Record<string, unknown>)[k] = clone(target[k])
    ;(target as unknown as Record<string, unknown>)[k] = d[k]
  }
  return { changed, before }
}

/** 撤销：只把 changed 这几项还原成 before 里的样子；返回真还原了的字段 */
export function restorePrefs(target: Prefs, changed: readonly PrefKey[], before: Partial<Prefs>): PrefKey[] {
  const out: PrefKey[] = []
  for (const k of changed) {
    if (!(k in before) || sameValue(target[k], before[k])) continue
    ;(target as unknown as Record<string, unknown>)[k] = clone(before[k])
    out.push(k)
  }
  return out
}
