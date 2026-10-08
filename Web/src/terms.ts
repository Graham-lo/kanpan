/* Hkline Web · 三端共用的用词（「大单与爆仓」、画线设置）
 *
 * 唯一的一份在 KanpanCore/Sources/KanpanCore/Terms/terms.json；iOS（BigTradeTerm）与这里读的都是它。
 * 改字只改那一个文件，界面代码里不再写这些字面量。模板里的 {n} {t} {v} {h} {side} 用 fill 填。
 */
import termsJson from '../../KanpanCore/Sources/KanpanCore/Terms/terms.json'

export type BigTradeTermKey = keyof typeof termsJson.bigTrade

/** 「大单与爆仓」用词：BT.longLiq →「多单爆仓」 */
export const BT: Readonly<Record<BigTradeTermKey, string>> = termsJson.bigTrade

/** 填好占位符：fill(BT.buyCount, { n: 12 }) →「买 12 笔」 */
export function fill(tpl: string, args: Record<string, string | number>): string {
  return tpl.replace(/\{(\w+)\}/g, (m, k: string) => (k in args ? String(args[k]) : m))
}

export type DrawSettingsTermKey = keyof typeof termsJson.drawSettings

/** 画线设置对话框的用词：DS.tabStyle →「样式」 */
export const DS: Readonly<Record<DrawSettingsTermKey, string>> = termsJson.drawSettings
