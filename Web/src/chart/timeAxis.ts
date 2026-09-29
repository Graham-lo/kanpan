/* Hkline Web · 时间轴刻度挑选
 *
 * 从原型 TVChart.timeTicks 抽出来的纯函数，不依赖 canvas，规则逐字照原型：
 *   · 刻度最小间隔 96 px（两刻度靠得比 96 × 0.8 还近就丢后一个；但后一个是加粗的、前一个不是时，换成加粗那个）
 *   · 按上海时间判断：换日处加粗（分时周期）；月初显示「N月」、1 月显示年份（日线及以上）
 *   · 步长取「≥ 96 px 能容下的时长、且 ≥ 周期」的第一档
 */
import { TZ_MS, pad, sh } from '../util/format'

export interface TimeTick { i: number; label: string; bold: boolean }

/** 刻度最小间隔（px） */
export const TIME_TICK_MIN_PX = 96

/** 可选步长（ms）：5 秒 … 1 年（秒级只有秒级周期用得到：步长要 ≥ 周期） */
export const TIME_STEPS = [5e3, 10e3, 15e3, 30e3, 60e3, 5 * 60e3, 15 * 60e3, 30 * 60e3, 36e5, 2 * 36e5, 3 * 36e5, 6 * 36e5, 12 * 36e5, 864e5, 2 * 864e5, 7 * 864e5, 14 * 864e5, 30 * 864e5, 91 * 864e5, 182 * 864e5, 365 * 864e5]

/** 由 bar 时间数组得到「下标 → 时间」，两头按周期外推（与 TVChart.timeAt 相同） */
export function timeAtFrom(times: number[], iv: number): (i: number) => number {
  return (i: number) => {
    const n = times.length
    if (!n) return 0
    const k = Math.round(i)
    if (k < 0) return times[0] + k * iv
    if (k >= n) return times[n - 1] + (k - n + 1) * iv
    return times[k]
  }
}

/**
 * 挑时间轴刻度。
 * @param timeAt  下标 → bar 开盘时间（ms，UTC）；也可以直接给时间数组（两头按 iv 外推）
 * @param lo      可见区最左的下标（原型：max(0, floor(xToIndex(0)))）
 * @param hi      可见区最右的下标（原型：ceil(rightBar)，可以超出数据）
 * @param spacing 每根 bar 的像素间距
 * @param iv      周期（ms）
 * @param minPx   刻度最小间隔，默认 96
 * @param xOf     下标 → x 像素；只用来算两刻度的间距，默认 i × spacing
 */
export function timeTicks(
  timeAt: ((i: number) => number) | number[],
  lo: number,
  hi: number,
  spacing: number,
  iv: number,
  minPx: number = TIME_TICK_MIN_PX,
  xOf: (i: number) => number = i => i * spacing,
): TimeTick[] {
  const out: TimeTick[] = []
  if (Array.isArray(timeAt)) { if (!timeAt.length) return out; timeAt = timeAtFrom(timeAt, iv) }
  const at = timeAt
  const barsPer = Math.max(1, Math.ceil(minPx / spacing))
  const span = barsPer * iv
  const step = TIME_STEPS.find(s => s >= span && s >= iv) || 365 * 864e5
  let lastX = -Infinity
  for (let i = lo; i <= hi; i++) {
    const t = at(i), tp = at(i - 1)
    const d = sh(t), dp = sh(tp)
    let hit = false, label = '', bold = false
    if (step >= 30 * 864e5) {
      const mStep = Math.round(step / (30 * 864e5))
      if (d.getUTCMonth() !== dp.getUTCMonth() && d.getUTCMonth() % mStep === 0) { hit = true; label = d.getUTCMonth() === 0 ? String(d.getUTCFullYear()) : `${d.getUTCMonth() + 1}月`; bold = d.getUTCMonth() === 0 }
    } else if (step >= 864e5) {
      const dStep = Math.round(step / 864e5)
      if (d.getUTCDate() !== dp.getUTCDate() || i === lo) {
        if (d.getUTCMonth() !== dp.getUTCMonth()) { hit = true; label = d.getUTCMonth() === 0 ? String(d.getUTCFullYear()) : `${d.getUTCMonth() + 1}月`; bold = true }
        else if (dStep === 7 ? d.getUTCDay() === 1 : (d.getUTCDate() - 1) % dStep === 0 && d.getUTCDate() < 29) { hit = true; label = String(d.getUTCDate()) }
      }
    } else {
      const ms = (t + TZ_MS) % 864e5
      if (d.getUTCDate() !== dp.getUTCDate()) { hit = true; label = d.getUTCDate() === 1 ? `${d.getUTCMonth() + 1}月` : String(d.getUTCDate()); bold = true }
      else if (ms % step === 0) { hit = true; label = `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}${step < 60e3 ? `:${pad(d.getUTCSeconds())}` : ''}` }
    }
    if (!hit) continue
    const x = xOf(i)
    if (x - lastX < minPx * 0.8) { if (bold && out.length && !out[out.length - 1].bold) { out[out.length - 1] = { i, label, bold }; lastX = x } continue }
    out.push({ i, label, bold }); lastX = x
  }
  return out
}
