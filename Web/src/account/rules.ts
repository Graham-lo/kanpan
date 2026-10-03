/* 账号字段的规则只有这一份（电脑网页、手机网页的登录 / 注册、加朋友、发给朋友、服务端报错的文案都用它），
 * 照 iOS KanpanAccount.AccountCredentialRules：
 * 用户名去首尾空白、只认 ASCII 字母数字下划线、大小写都收、交出去是小写（服务端也这样存）；
 * 密码下限按码点数、上限按 UTF-8 字节数（服务端 chars().count() 与 128 字节）。 */
export const USERNAME_RULE = '用户名需 3–32 位字母、数字或下划线'
export const PASSWORD_RULE = '密码至少 8 位，需含字母和数字'
/** 服务端会存下来的样子；不合规则时是 null */
export function normalUsername(raw: string): string | null {
  const v = raw.trim()
  return /^[A-Za-z0-9_]{3,32}$/.test(v) ? v.toLowerCase() : null
}
export const validUsername = (u: string): boolean => normalUsername(u) != null
export const validPassword = (p: string): boolean =>
  [...p].length >= 8 && new TextEncoder().encode(p).length <= 128 && /[A-Za-z]/.test(p) && /\d/.test(p)
