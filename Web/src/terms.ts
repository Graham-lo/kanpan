/* Hkline Web · 三端共用的用词（「大单与爆仓」BT、「分析」AN）
 *
 * 唯一的一份在 KanpanCore/Sources/KanpanCore/Terms/terms.json；iOS（BigTradeTerm / AnalysisTerm）与这里读的都是它。
 * 改字只改那一个文件，界面代码里不再写这些字面量。模板里的 {n} {t} {v} {h} {side} 用 fill 填。
 */
import termsJson from '../../KanpanCore/Sources/KanpanCore/Terms/terms.json'

export type BigTradeTermKey = keyof typeof termsJson.bigTrade

/** 「大单与爆仓」用词：BT.longLiq →「多单爆仓」 */
export const BT: Readonly<Record<BigTradeTermKey, string>> = termsJson.bigTrade

export type AnalysisTermKey = keyof typeof termsJson.analysis

/** 「分析」里自动画的那几样的用词：AN.fvg →「公允价值缺口」（iOS AnalysisTerm） */
export const AN: Readonly<Record<AnalysisTermKey, string>> = termsJson.analysis

/** 填好占位符：fill(BT.buyCount, { n: 12 }) →「买 12 笔」 */
export function fill(tpl: string, args: Record<string, string | number>): string {
  return tpl.replace(/\{(\w+)\}/g, (m, k: string) => (k in args ? String(args[k]) : m))
}
