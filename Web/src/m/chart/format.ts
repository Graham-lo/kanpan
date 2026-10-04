// 移植自 KanpanCore/Format/Format.swift 与 Model/UTCCalendar.swift（图表要用到的那部分）
//
// 时间一律上海时区（UTC+8 固定，kanpan-timezone-shanghai）；数额 K / M / B / T。

import { type Interval, INTERVAL_STEP } from './series'

export interface DateParts { year: number; month: number; day: number; hour: number; minute: number }

/** Howard Hinnant 的 civil_from_days，与 Swift 逐字一致（整数除法向零截断）。 */
export function dateParts(ms: number, offsetMinutes: number): DateParts {
  const shifted = ms + offsetMinutes * 60_000
  const secs = Math.floor(shifted / 1000)
  let days = Math.trunc(secs / 86_400)
  let rem = secs % 86_400
  if (rem < 0) { rem += 86_400; days -= 1 }
  const hour = Math.trunc(rem / 3600)
  const minute = Math.trunc((rem % 3600) / 60)
  let z = days + 719_468
  const era = Math.trunc((z >= 0 ? z : z - 146_096) / 146_097)
  z -= era * 146_097
  const doe = z
  const yoe = Math.trunc((doe - Math.trunc(doe / 1460) + Math.trunc(doe / 36_524) - Math.trunc(doe / 146_096)) / 365)
  const y = yoe + era * 400
  const doy = doe - (365 * yoe + Math.trunc(yoe / 4) - Math.trunc(yoe / 100))
  const mp = Math.trunc((5 * doy + 2) / 153)
  const day = doy - Math.trunc((153 * mp + 2) / 5) + 1
  const month = mp < 10 ? mp + 3 : mp - 9
  const year = month <= 2 ? y + 1 : y
  return { year, month, day, hour, minute }
}

export const pad2 = (n: number): string => (n < 10 ? `0${n}` : `${n}`)

/** 时间轴刻度文案：≥1 年给年，≥1 月给年-月，≥1 天给月-日，跨零点给月-日，其余给时:分。 */
export function fmtTick(ms: number, step: number, offsetMinutes: number): string {
  const p = dateParts(ms, offsetMinutes)
  const day = 86_400_000
  // 一月及以上的刻度都落在某月 1 号（见 timeTicks），写「03-01」没有信息量；年档都在 1 月 1 号，
  // 写「2026-01」只是白占宽度（同 iOS · 审查 B·P3-3）。
  if (step >= 365 * day) return `${p.year}`
  if (step >= 30 * day) return `${p.year}-${pad2(p.month)}`
  if (step >= day) return `${pad2(p.month)}-${pad2(p.day)}`
  if (p.hour === 0 && p.minute === 0) return `${pad2(p.month)}-${pad2(p.day)}`
  return `${pad2(p.hour)}:${pad2(p.minute)}`
}

export function fmtFull(ms: number, offsetMinutes: number): string {
  const p = dateParts(ms, offsetMinutes)
  return `${p.year}-${pad2(p.month)}-${pad2(p.day)} ${pad2(p.hour)}:${pad2(p.minute)}`
}

export function fmtDayTime(ms: number, offsetMinutes: number): string {
  const p = dateParts(ms, offsetMinutes)
  return `${p.month}/${p.day} ${pad2(p.hour)}:${pad2(p.minute)}`
}

export function fmtCountdown(ms: number): string | null {
  if (!Number.isFinite(ms) || !(ms > 0)) return null
  const total = Math.floor(ms / 1000)
  const d = Math.trunc(total / 86_400)
  const h = Math.trunc((total % 86_400) / 3600)
  const m = Math.trunc((total % 3600) / 60)
  const s = total % 60
  if (d > 0) return `${d}d ${pad2(h)}:${pad2(m)}`
  if (total >= 3600) return `${h}:${pad2(m)}:${pad2(s)}`
  return `${pad2(m)}:${pad2(s)}`
}

/**
 * JS 的 toFixed 本来就是「按精确二进制值、逢五进」（ECMA-262 Number.prototype.toFixed：两个 n 一样近取大的），
 * 和 Swift 的 toFixedFast / toFixedReference 一致；只差两处：舍完全是 0 的负数不带负号、≥1e21 不走科学计数。
 */
export function toFixed(x: number, p: number): string {
  if (!Number.isFinite(x)) return String(x)
  const q = Math.max(0, Math.min(100, p))
  let s: string
  if (Math.abs(x) >= 1e21) {
    s = BigInt(Math.round(Math.abs(x))).toString() + (q > 0 ? '.' + '0'.repeat(q) : '')
    if (x < 0) s = '-' + s
  } else s = x.toFixed(q)
  if (s.startsWith('-') && !/[1-9]/.test(s)) s = s.slice(1)
  return s
}

export const fmtNum = (x: number, p: number): string => (Number.isFinite(x) ? toFixed(x, p) : '--')

export function fmtPrice(x: number, decimals: number): string {
  if (!Number.isFinite(x)) return '--'
  const p = Math.max(0, Math.min(12, decimals))
  const s = toFixed(x, p)
  if (x === 0 || /[1-9]/.test(s)) return s
  const need = Math.min(12, Math.ceil(-Math.log10(Math.abs(x))) + 1)
  return toFixed(x, Math.max(p, need))
}

export function priceDecimalsFallback(price: number): number {
  const m = Math.abs(price)
  if (!Number.isFinite(m)) return 2
  if (m >= 100) return 2
  if (m >= 1) return 4
  if (m >= 0.1) return 5
  if (m >= 0.01) return 6
  if (m >= 0.001) return 7
  return 8
}

export type VolUnit = 'plain' | 'k' | 'm' | 'b' | 't'
const VOL_UNITS: { unit: VolUnit; scale: number }[] = [
  { unit: 't', scale: 1e12 }, { unit: 'b', scale: 1e9 }, { unit: 'm', scale: 1e6 }, { unit: 'k', scale: 1e3 },
]

/**
 * 选 K / M / B / T 哪一档，按印出来的样子选：低一档按 decimals 位小数（不满一千按 plainDecimals 位）
 * 进位成「1000」时就升一档。从前只比原始数值，999,999 两位小数印成「1000.00K」、订单流签 999,960
 * 印成「1000.0K」（同 iOS cccf6fff · 审查 B·单位进位）。坏数回落到不带单位。
 */
export function volUnit(x: number, decimals = 2, plainDecimals = 0): VolUnit {
  const a = Math.abs(x)
  if (!Number.isFinite(a)) return 'plain'
  for (let i = 0; i < VOL_UNITS.length; i++) {
    const u = VOL_UNITS[i]
    if (a >= u.scale) return u.unit
    // 离这一档还差 1% 以上的不可能进位上来，不必格式化。
    if (a < u.scale * 0.99) continue
    const lower = i + 1 < VOL_UNITS.length ? VOL_UNITS[i + 1].scale : 1
    const places = i + 1 < VOL_UNITS.length ? decimals : plainDecimals
    if (Number(toFixed(a / lower, places)) >= u.scale / lower) return u.unit
  }
  return 'plain'
}

export function fmtVol(x: number, unit: VolUnit = volUnit(x)): string {
  if (!Number.isFinite(x)) return '--'
  switch (unit) {
    case 't': return toFixed(x / 1e12, 2) + 'T'
    case 'b': return toFixed(x / 1e9, 2) + 'B'
    case 'm': return toFixed(x / 1e6, 2) + 'M'
    case 'k': return toFixed(x / 1e3, 2) + 'K'
    case 'plain': return Math.abs(x) >= 100 ? toFixed(x, 0) : toFixed(x, 2)
  }
}

export function changePercentText(percent: number | null | undefined, missing = '—'): string {
  if (percent == null || !Number.isFinite(percent)) return missing
  const magnitude = toFixed(Math.abs(percent), 2)
  const zero = !/[1-9]/.test(magnitude)
  return (percent < 0 && !zero ? '−' : '+') + magnitude + '%'
}

// ------------------------------------------------------------------ UTCCalendar

export function addingMonths(months: number, ms: number): number {
  const d = new Date(ms)
  const y = d.getUTCFullYear(), m = d.getUTCMonth() + months
  const day = d.getUTCDate()
  // Foundation 的 date(byAdding:.month) 在月底会夹到目标月最后一天。
  const lastDay = new Date(Date.UTC(y, m + 1, 0)).getUTCDate()
  return Date.UTC(y, m, Math.min(day, lastDay), d.getUTCHours(), d.getUTCMinutes(), d.getUTCSeconds(), d.getUTCMilliseconds())
}

/** Interval.advancing：月线 / 年线按日历走，其余按步长。 */
export function advancing(iv: Interval, time: number, bars: number): number {
  if (iv === '1M') return addingMonths(bars, time)
  if (iv === '1y') return addingMonths(12 * bars, time)
  return time + bars * INTERVAL_STEP[iv]
}
