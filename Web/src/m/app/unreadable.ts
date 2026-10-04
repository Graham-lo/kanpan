/* Hkline 手机网页版 · 读不全的本机存档原文另存
 *
 * 本机状态（hkline-m-v1）与画线本（hkline-m-drawings-v1）都是整份写的：读出来解不开就当空的用，
 * 下一次落盘会把主键整份盖掉——没登录的人那份东西只存在这一处。所以解不开（或解出来会丢东西）时
 * 先把原文放到 `<键>.unreadable-<时间>`：同一份原文只存一次，每个键最多留 KEEP 份最新的。
 */
const KEEP = 3

export const unreadablePrefix = (key: string): string => key + '.unreadable-'

export function backupUnreadable(key: string, raw: string, now = Date.now()): void {
  try {
    const prefix = unreadablePrefix(key)
    const old: string[] = []
    for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i); if (k?.startsWith(prefix)) old.push(k) }
    old.sort((a, b) => Number(a.slice(prefix.length)) - Number(b.slice(prefix.length)))
    if (old.some(k => localStorage.getItem(k) === raw)) return
    localStorage.setItem(prefix + now, raw)
    for (const k of old.slice(0, Math.max(0, old.length + 1 - KEEP))) localStorage.removeItem(k)
  } catch (e) { console.warn('[m] 存档原文另存失败', key, e) }
}
