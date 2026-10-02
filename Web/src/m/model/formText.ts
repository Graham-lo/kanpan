/* 手机网页版 · 表单上的纯文字规则（创建提醒的价格输入与提示行、账号表单的规则、登录设备那一行）
 * 照 iOS AlertForm.hintText、AccountFeature.usernameHint / passwordHint、AccountView 设备行。 */
import { priceText } from './rowText'
import type { AlertSound } from '../app/prefs'

/** 输入框里的数：去千分位、全角点，不是正数就 null */
export function parseTarget(text: string): number | null {
  const s = text.replace(/[,，\s]/g, '').replace(/[。．]/g, '.')
  if (!/^\d*\.?\d*$/.test(s) || !s || s === '.') return null
  const n = +s
  return n > 0 && isFinite(n) ? n : null
}
/** 提示行（照 AlertForm.hintText） */
export function hintText(target: number | null, price: number | null | undefined, dec?: number): string {
  if (target == null) return '输入一个价格'
  if (price == null || !(price > 0)) return '现价 —'
  const pct = (target - price) / price * 100
  if (Math.abs(pct) < 0.005) return '和现价相同'
  return `现价 ${priceText(price, dec)} · ${pct > 0 ? '高于现价' : '低于现价'} ${Math.abs(pct).toFixed(2)}%`
}

export const USERNAME_RULE = '用户名 3–32 位，只能用小写字母、数字、下划线'
export const PASSWORD_RULE = '密码至少 8 位，要同时有字母和数字'
export const validUsername = (u: string): boolean => /^[a-z0-9_]{3,32}$/.test(u)
export const validPassword = (p: string): boolean => p.length >= 8 && /[A-Za-z]/.test(p) && /\d/.test(p)
export const KIND_CN: Record<string, string> = { desktop: '电脑', phone: '手机', tablet: '平板' }
/** 登录设备那一行的第二行：「手机 · 本机」「电脑 · 9月28日 14:05」（上海时间） */
export function deviceMeta(d: { kind: string; current: boolean; lastSeen: number }): string {
  const kind = KIND_CN[d.kind] ?? '设备'
  if (d.current) return kind + ' · 本机'
  const t = new Date(d.lastSeen + 8 * 3600e3)
  const p = (n: number): string => String(n).padStart(2, '0')
  return `${kind} · ${t.getUTCMonth() + 1}月${t.getUTCDate()}日 ${p(t.getUTCHours())}:${p(t.getUTCMinutes())}`
}


// ───────── 账号页：导出我的数据、同步页的「上次同步」 ─────────

/** 导出文件名（照 iOS AccountExport.writeExport）：「Hkline-我的数据-20261003.json」，日期按上海时间 */
export function exportFileName(now: number): string {
  const t = new Date(now + 8 * 3600e3)
  const p = (n: number): string => String(n).padStart(2, '0')
  return `Hkline-我的数据-${t.getUTCFullYear()}${p(t.getUTCMonth() + 1)}${p(t.getUTCDate())}.json`
}

/** 导出正文：键按字典序、两格缩进（照 iOS .prettyPrinted + .sortedKeys），数组顺序不动 */
export function sortedJSON(v: unknown): string {
  const sort = (x: unknown): unknown => {
    if (Array.isArray(x)) return x.map(sort)
    if (x && typeof x === 'object') {
      const o = x as Record<string, unknown>
      return Object.fromEntries(Object.keys(o).sort().map(k => [k, sort(o[k])]))
    }
    return x
  }
  return JSON.stringify(sort(v), null, 2)
}

/** 同步页「上次同步」那一格（照 iOS Text(date, style: .relative) 的中文说法） */
export function syncAgo(last: number, now: number): string {
  const s = Math.max(0, Math.floor((now - last) / 1000))
  if (s < 60) return '刚刚'
  if (s < 3600) return `${Math.floor(s / 60)} 分钟前`
  if (s < 86_400) return `${Math.floor(s / 3600)} 小时前`
  return `${Math.floor(s / 86_400)} 天前`
}

/** 铃声四档（照 iOS AlertSound.allCases 与 title） */
export const SOUNDS: readonly [AlertSound, string][] = [['default', '默认'], ['crisp', '清脆'], ['electronic', '电子'], ['glass', '玻璃']]
export const soundTitle = (s: AlertSound): string => SOUNDS.find(([v]) => v === s)?.[1] ?? '默认'

/** 「关于」那一行的版本：线上读入口脚本名里的内容哈希（每次发版都变），本机开发写「开发版」 */
export function webVersion(scriptSrc: string | null, dev: boolean): string {
  if (dev) return 'Hkline 网页版（开发版）'
  const hash = scriptSrc?.match(/\/m-([A-Za-z0-9_-]+)\.js/)?.[1]
  return hash ? `Hkline 网页版（${hash}）` : 'Hkline 网页版'
}

/** 通知那一组最上面的提示行该不该出、点了说什么；不用出是 null */
export function permissionHint(p: NotificationPermission | 'unsupported', ua: string, standalone: boolean): string | null {
  if (p === 'denied') return '在浏览器的网站设置里把「通知」改成允许'
  if (p !== 'unsupported') return null
  // iPhone 的 Safari 只有加到主屏幕、从主屏幕打开时才有通知
  if (/iPhone|iPad/.test(ua) && !standalone) return '在 Safari 点「分享 › 添加到主屏幕」，从主屏幕打开后才能收通知'
  return '这个浏览器收不了通知，换一个浏览器或加到主屏幕再试'
}
