/* Hkline Web · 账号会话
 *
 * 网页版的账号登录（用户名 + 密码，走 kanpan-api）在下一阶段接入。这一阶段不做假登录：
 * 会话恒为未登录，自选、画线、提醒、笔记都只存在这台电脑的浏览器里；
 * 需要登录的功能（复盘、成交、跨设备同步）显示空态。
 */
export const session = {
  user: null as string | null,
}

export function loggedIn(): boolean { return !!session.user }
