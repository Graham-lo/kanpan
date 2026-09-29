/* Hkline 手机网页版 · 最早执行的一段：账号模块换成手机那一套键名与设备类别。
 * 必须是 main.ts 的第一个 import（ESM 按顺序求值），在任何读账号 / 同步的模块副作用之前。 */
import { configureAccount } from '../account/client'

configureAccount({ keyPrefix: 'hkline-m', kind: 'phone' })
