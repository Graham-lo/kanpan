/* Hkline Web · 数字与时间格式
 *
 * 从原型 chart.js（KPFmt）搬过来，行为逐字照原型。时间一律按上海时间（UTC+8）显示。
 */

/** 上海时区相对 UTC 的偏移：8 小时 */
export const TZ_MS = 8 * 3600e3

/** 周期 → 毫秒（照 data.js：月线按 30 天算） */
export const IV_MS: Record<string, number> = {
  '1m': 60e3, '3m': 180e3, '5m': 300e3, '15m': 900e3, '30m': 1800e3,
  '1h': 36e5, '2h': 72e5, '4h': 144e5, '6h': 216e5, '8h': 288e5, '12h': 432e5,
  '1d': 864e5, '1w': 6048e5, '1M': 2592e6,
}

const WEEK = ['日', '一', '二', '三', '四', '五', '六']

/** 读 UTC 字段 = 上海时间 */
export function sh(t: number): Date { return new Date(t + TZ_MS) }

export const pad = (n: number): string => String(n).padStart(2, '0')

export function clamp(v: number, a: number, b: number): number { return Math.max(a, Math.min(b, v)) }

// 每种小数位一个格式器：toLocaleString 带选项每调一次都新建一个 Intl.NumberFormat，是图表重画里自耗时最多的一项
// （2026-09-29 A 路压测剖面：悬停扫图 8 秒里 fmt 自耗 750 ms，排第一）；输出一字不差
const NF = new Map<number, Intl.NumberFormat>()
export function fmt(v: number | null | undefined, dec: number): string {
  if (v == null || !isFinite(v)) return '—'
  let f = NF.get(dec)
  if (!f) { f = new Intl.NumberFormat('en-US', { minimumFractionDigits: dec, maximumFractionDigits: dec }); NF.set(dec, f) }
  return f.format(v)
}

/** 价格轴、十字线读数、现价 / 提醒标签：带千分位（84,070.0），和梯子价格列、侧栏价格同一写法；null 为空串 */
export function fmtAxis(v: number | null | undefined, dec: number): string { return v == null || !isFinite(v) ? '' : fmt(v, dec) }

/** K / M / B / T 金融单位。单位按四舍五入之后的值挑：999,999 是「1.00M」不是「1000.00K」；
 *  舍成 0 的负数不带负号（-0.001 是「0.00」不是「-0.00」） */
const UNITS: readonly [number, string][] = [[1, ''], [1e3, 'K'], [1e6, 'M'], [1e9, 'B'], [1e12, 'T']]
export function fmtCompact(v: number | null | undefined): string {
  if (v == null || !isFinite(v)) return '—'
  for (let i = 0; i < UNITS.length; i++) {
    const [u, s] = UNITS[i], x = v / u
    const t = x.toFixed(i === 0 && Math.abs(v) >= 10 ? 0 : 2)
    if (Math.abs(+t) < 1000 || i === UNITS.length - 1) return (+t === 0 ? t.replace('-', '') : t) + s
  }
  return '—'
}

/** 副图读数（图例、刻度、十字线）。MACD、ATR 是价格单位，低价品种（DOGE 0.1、PEPE 0.00001）的值常在 0.001 以下，
 *  原来一律 < 10 取两位，DOGE 日线的 MACD 图例与刻度全是「0.00」；这两个按品种价格精度 dec 取位（至少两位、至多 10 位）。
 *  RSI、KDJ 取整；持仓量用 K/M/B/T；其余（成交量类、CCI、威廉）照旧。 */
/** 0–100 刻度的副图：整数位就够 */
const PCT100 = new Set(['rsi', 'kdj', 'stochrsi', 'stoch', 'mfi', 'uo', 'chop', 'rvi', 'crsi', 'aroon', 'cmo', 'dmi'])
/** 以价格为单位的副图：小数位跟品种价格的小数位走（低价币上 2 位会一律显示 0.00） */
const PRICE_UNIT = new Set(['macd', 'atr', 'ao', 'ac', 'mom', 'dpo', 'stdev'])
export function fmtSub(id: string, v: number, dec: number): string {
  if (!isFinite(v)) return ''
  if (PCT100.has(id)) return v.toFixed(0)
  if (id === 'oi') return fmtCompact(v)
  const a = Math.abs(v)
  if (a >= 1000) return fmtCompact(v)
  if (PRICE_UNIT.has(id)) return v.toFixed(Math.min(10, Math.max(a < 10 ? 2 : 1, dec)))
  // 极小量（低价币的量价类、比值类）：留三位有效数字，不要显示成 0.00
  if (a > 0 && a < 0.01) return v.toFixed(Math.min(10, 2 - Math.floor(Math.log10(a))))
  return v.toFixed(a < 10 ? 2 : 1)
}

/** 十字线时间标签：「26-09-29 周二  00:30」；日线及以上不带时分 */
export function crossTimeLabel(t: number, iv: number): string {
  const d = sh(t)
  const date = `${d.getUTCFullYear() % 100}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} 周${WEEK[d.getUTCDay()]}`
  return iv >= 864e5 ? date : `${date}  ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}${iv < 60e3 ? `:${pad(d.getUTCSeconds())}` : ''}`
}

/** 时长：分钟 / 小时 / 天 */
export function durText(ms: number): string {
  const m = Math.round(ms / 60e3)
  if (m < 60) return `${m} 分钟`
  const h = m / 60; if (h < 48) return `${+h.toFixed(1)} 小时`
  return `${+(h / 24).toFixed(1)} 天`
}

/** #RRGGBB（或 #RGB）→ rgba(…, a)；不是 # 开头的原样返回 */
export function hexA(hex: string, a: number): string {
  if (!hex || hex[0] !== '#') return hex
  // 原型只认 6 位；3 位简写先展开，免得算出错的颜色
  const h = hex.length === 4 ? hex.slice(1).split('').map(ch => ch + ch).join('') : hex.slice(1, 7)
  const n = parseInt(h, 16)
  return `rgba(${n >> 16 & 255},${n >> 8 & 255},${n & 255},${a})`
}

/** 坐标轴步长：1 / 2 / 2.5 / 5 / 10 × 10^k */
export function niceStep(raw: number): number {
  const p = Math.pow(10, Math.floor(Math.log10(raw))), f = raw / p
  const n = f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10
  return n * p
}
