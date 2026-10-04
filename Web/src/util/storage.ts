/* Hkline Web · 本机存储写不下时让位
 *
 * /web/ 与 /web/m/ 同源，共用一份 localStorage（Chrome 约 5M 字符）。主存档（自选、画线、提醒……）
 * 写不下时，以前整份静默丢掉，关页面再开这一段改动全没了。现在先清掉能让位的缓存再写：
 *   · 板块 5 日收盘：服务端随时能再取；
 *   · 记一笔待传的截图：设计上就是「存不下就不带图、记录照传」。
 * 清完还写不下才算失败（交给调用方告诉人）。 */

export const SECTOR_HISTORY_KEY = 'hkline-web-sector-history-v1'
export const NOTE_SHOTS_KEY = 'hkline-note-shots'
/** 按让位的先后排 */
const EVICTABLE = [SECTOR_HISTORY_KEY, NOTE_SHOTS_KEY]

function isQuota(e: unknown): boolean {
  if (!(e instanceof Error) && !(typeof DOMException !== 'undefined' && e instanceof DOMException)) return false
  const x = e as { name?: string; code?: number }
  return x.name === 'QuotaExceededError' || x.name === 'NS_ERROR_DOM_QUOTA_REACHED' || x.code === 22 || x.code === 1014
}

/** 写一个键，写不下就按顺序清掉可让位的缓存再试；返回最终有没有写进去 */
export function setItemMakingRoom(key: string, value: string, store: Storage | undefined = globalThis.localStorage): boolean {
  if (!store) return false
  try { store.setItem(key, value); return true } catch (e) { if (!isQuota(e)) return false }
  for (const k of EVICTABLE) {
    if (k === key || store.getItem(k) == null) continue
    store.removeItem(k)
    try { store.setItem(key, value); return true } catch (e) { if (!isQuota(e)) return false }
  }
  return false
}
