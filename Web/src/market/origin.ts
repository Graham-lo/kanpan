/* Hkline Web · 自家服务器的根（网关线路、元数据、美元指数都打它）
 *
 * 单独一个文件：交易所模块（src/venues/*）和行情层（rest.ts）都要它，放在 rest.ts 里会让两边互相引用。
 */

/** 自家服务器的根：线上与页面同源；本机开发（localhost）直接打线上那台。 */
export function apiOrigin(): string {
  if (typeof location !== 'undefined' && /^https:$/.test(location.protocol) && !/^localhost$|^127\./.test(location.hostname)) return location.origin
  return 'https://kanpan.43-160-232-253.sslip.io'
}

/** 网关的 WebSocket 根：wss://主机 */
export function gatewayWs(): string { return apiOrigin().replace(/^http/, 'ws') }
