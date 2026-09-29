/* 手机网页版 · 表单上的纯文字规则（创建提醒的价格输入与提示行、账号表单的规则、登录设备那一行）
 * 照 iOS AlertForm.hintText、AccountFeature.usernameHint / passwordHint、AccountView 设备行。 */
import { priceText } from './rowText'

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

