/* Hkline Web · 多图的底栏与每格右下角的「对数 / 自动」（UI 审查 2026-10-10 A3，原型 docs/prototypes/web-layout-2026-10-10.html 第 4 节）
 *
 * 原来每格各带一整条底栏（布局集 · 相机 · 回放 · 导出 · 1天…全部 · 钟 · 对数 · 自动），十六图就是十六条一样的按钮。
 * 现在整个图表区下面只有一条全局底栏，作用于当前格，左头写「作用于 · 格 N」（一图不写）；
 * 每格只在右下角留两颗小标签「对数 / 自动」，悬停或当前格时才露出来，点了只改这一格。
 * 这里是纯逻辑与 HTML（单测在 node 里跑），挂 DOM、接事件在 pages/chart.ts。
 */
import { esc } from '../ui/dom'
import { qsvg } from '../ui/qicons'
import { IV_LABEL } from '../market/symbols'
import { HL, fill } from '../terms'

/** 全局底栏高（app.css .chart-foot 与 #page-chart 的 --gfoot-h 照抄这里） */
export const GFOOT_H = 32

export type RangeDays = number | 'ytd' | 'all'
/** 底栏的时间范围：[字, 切到的周期, 最近几天] */
export const RANGES: [string, string, RangeDays][] = [['1天', '1m', 1], ['5天', '5m', 5], ['1月', '30m', 30], ['3月', '2h', 91], ['6月', '4h', 182], ['今年', '1d', 'ytd'], ['1年', '1d', 365], ['全部', '1w', 'all']]

/** 底栏上的按钮作用于哪一格：当前格（下标越界时退到第一格） */
export function footTarget<T>(cells: readonly T[], active: number): T | undefined { return cells[active] ?? cells[0] }

/** 底栏左头：多图时「作用于 · 格 N」（N 从 1 数），一图不写 */
export function footTargetLabel(n: number, active: number): string { return n > 1 ? fill(HL.cellTarget, { n: active + 1 }) : '' }

/** 视图开关：对数坐标 / 价格轴自动缩放。每格右下角两颗、全局底栏右头两颗，都只改传进来的那一格 */
export type ViewAct = 'log' | 'auto'
export interface ViewChart { log: boolean; auto: boolean; setLog(v: boolean): void; setAuto(v: boolean): void }
/** 切一下，回切完的状态 */
export function toggleView(ch: ViewChart, act: ViewAct): boolean {
  if (act === 'log') { ch.setLog(!ch.log); return ch.log }
  ch.setAuto(!ch.auto); return ch.auto
}
export const isViewAct = (a: string | undefined): a is ViewAct => a === 'log' || a === 'auto'

const VIEW_TIP: Record<ViewAct, string> = { log: '对数坐标', auto: '价格轴自动缩放（双击价格轴也可以恢复）' }
const viewBtn = (act: ViewAct, on: boolean): string =>
  `<button data-act="${act}" data-tip="${VIEW_TIP[act]}" aria-pressed="${on}">${act === 'log' ? HL.logScale : HL.autoScale}</button>`

/** 每格右下角的「对数 / 自动」 */
export function cellFootHTML(v: { log: boolean; auto: boolean }): string {
  return `<div class="cfoot">${viewBtn('log', v.log)}${viewBtn('auto', v.auto)}</div>`
}

const rangeTip = (l: string, iv: string): string => `${l}：切到 ${IV_LABEL[iv]}，显示最近${l === '全部' ? '全部历史' : l === '今年' ? '今年以来' : l}`
const ic = (key: string): string => qsvg(key, 'q-foot')

/** 全局底栏（第一次建的时候整块写；之后由 paintFoot 就地改字与按下态） */
export function footHTML(o: { label: string; sets: string; conn: string; connTip: string; log: boolean; auto: boolean; replayTip: string }): string {
  return `<span class="foot-target" ${o.label ? '' : 'hidden'}>${esc(o.label)}</span>
      <button class="foot-set" data-act="sets" aria-label="切换布局" data-tip="切换布局">${o.sets}</button>
      <button class="foot-ic" data-act="save" aria-label="保存图表截图" data-tip="保存图表截图" data-kbd="⌥ S">${ic('u_camera')}</button>
      <button class="foot-ic" data-act="replay" aria-label="K 线回放" data-tip="${esc(o.replayTip)}" data-kbd="⌥ R">${ic('u_replay')}</button>
      <button class="foot-ic" data-act="export" aria-label="导出" data-tip="导出 K 线与指标（CSV）">${ic('u_export')}</button>
      <div class="foot-right">
        ${RANGES.map(([l, iv], k) => `<button data-range="${k}" data-tip="${rangeTip(l, iv)}">${l}</button>`).join('')}
        <span class="tb-sep"></span>
        <span class="clock num" data-tip="时间统一按上海时间显示，日线在北京时间 8:00 换日"></span>
        <span class="conn-dot" data-conn="${o.conn}" data-tip="${esc(o.connTip)}"></span>
        <span class="tb-sep"></span>
        ${viewBtn('log', o.log)}${viewBtn('auto', o.auto)}
      </div>`
}
