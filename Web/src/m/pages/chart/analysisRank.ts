/* 「分析」面板四节怎么排（照 iOS Panels/AnalysisSectionRank.swift，2026-10-08）
 *
 * 用户：主力订单流、大单与爆仓放在分析里太靠后，常用的应该有位置权重、能动态调整。机制和画线条（m/chart/draw/toolRank.ts）同一套：
 * - 出厂顺序 DEFAULT_ORDER：画线 → 主力订单流 → 指标 → 对比；
 * - 在某一节里做一次实事（开始画线、拨开关、点进参数、加对比……）给那一节 +1（countedSection），
 *   次数记在 Prefs.analysisUsage（随账号同步，iOS / 手机网页 / 服务端同一张表，键名不要改），
 *   总数过 DECAY_CEILING 整体减半、减成 0 的删掉——量的是「最近常用」；
 * - 面板打开那一刻定一次顺序，开着期间不重排（panels.ts openAnalysis 里冻结），不然拨一下开关节就在手指底下跳。
 * 不给「固定哪节在上」的设置。
 */

export const ANALYSIS_SECTIONS = ['draw', 'orderFlow', 'indicators', 'compare'] as const
export type AnalysisSection = typeof ANALYSIS_SECTIONS[number]

export const isAnalysisSection = (k: unknown): k is AnalysisSection => (ANALYSIS_SECTIONS as readonly unknown[]).includes(k)

/** 一次都没用过的节按这个顺序补位，新人第一次打开看到的就是它 */
export const DEFAULT_ORDER: readonly AnalysisSection[] = ['draw', 'orderFlow', 'indicators', 'compare']
/** 四节次数加起来超过它就整体减半 */
export const DECAY_CEILING = 256

/** 四节从上到下的顺序，一个不少：用过的按次数从多到少、次数一样按出厂序；没用过的按出厂序补齐 */
export function sectionOrder(usage: Readonly<Record<string, number>> | undefined): AnalysisSection[] {
  const u = usage ?? {}
  const used = DEFAULT_ORDER
    .map((s, at) => ({ s, n: u[s] ?? 0, at }))
    .filter(e => Number.isFinite(e.n) && e.n > 0)
    .sort((a, b) => b.n - a.n || a.at - b.at)
    .map(e => e.s)
  const order = [...used]
  for (const s of DEFAULT_ORDER) if (!order.includes(s)) order.push(s)
  return order
}

/** 在 s 那一节里做了一次事之后的次数表（新对象）。认不出的键顺手丢掉，表里最多四个键 */
export function countedSection(usage: Readonly<Record<string, number>> | undefined, s: AnalysisSection): Record<string, number> {
  let next: Record<string, number> = {}
  for (const [k, n] of Object.entries(usage ?? {})) if (isAnalysisSection(k) && Number.isInteger(n) && n > 0) next[k] = n
  next[s] = (next[s] ?? 0) + 1
  if (Object.values(next).reduce((a, b) => a + b, 0) > DECAY_CEILING) {
    const halved: Record<string, number> = {}
    for (const [k, n] of Object.entries(next)) { const m = Math.floor(n / 2); if (m > 0) halved[k] = m }
    next = halved
  }
  return next
}
