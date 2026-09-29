/* Hkline Web · 同步在本机用的键名与锁名
 *
 * 跟着账号模块的键前缀走（`configureAccount({ keyPrefix })`）：PC 是 hkline-web-*，手机网页版是 hkline-m-*。
 * /web/ 与 /web/m/ 同源、共用一份 localStorage，两端的账本、「最后一次改」、领头锁必须各用各的，
 * 否则 PC 的账本会被手机那份当成自己的续上。每次现取，不怕 import 顺序早于 configureAccount。
 */
import { accountConfig } from '../account/client'

export function syncKeys(): { archive: string; owner: string; edited: string; lock: string } {
  const p = accountConfig().keyPrefix
  return {
    /** 账本：后面接 userId */
    archive: p + '-sync-v1:',
    owner: p + '-sync-owner',
    edited: p + '-edited-v1',
    /** Web Locks 名：后面接 userId。PC 沿用原名 hkline-sync: */
    lock: p === 'hkline-web' ? 'hkline-sync:' : p + '-sync:',
  }
}
