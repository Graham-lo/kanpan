/* 手机网页版 · 品种行上的字（照 KanpanCore Format.swift 的 fmtPrice / priceDecimalsFallback / fmtVol /
 * changePercentText 与 app 层 grouped / SymbolRowText）。负号一律 U+2212，数额一律 K / M / B / T。 */

export const MISSING = '—'
export const SEPARATOR = '  ·  '
export const MINUS = '−'

/** 四舍五入到 p 位（逢五进，负零不带号） */
export function toFixed(x: number, p: number): string {
  if (!Number.isFinite(x)) return String(x)
  const s = Math.abs(x).toFixed(p)
  const zero = !/[1-9]/.test(s)
  return x < 0 && !zero ? '-' + s : s
}

/** 价格：按精度写，但舍完成 0 的极小价补够位数 */
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
  return m >= 100 ? 2 : m >= 1 ? 4 : m >= 0.1 ? 5 : m >= 0.01 ? 6 : m >= 0.001 ? 7 : 8
}

/** 整数部分插千分位 */
export function grouped(text: string): string {
  const [head, ...rest] = text.split('.')
  const neg = head.startsWith('-')
  const digits = neg ? head.slice(1) : head
  if (digits.length <= 3 || !/^\d+$/.test(digits)) return text
  const out = digits.replace(/\B(?=(\d{3})+(?!\d))/g, ',')
  return (neg ? '-' : '') + out + (rest.length ? '.' + rest.join('.') : '')
}

/** 行上的价格：千分位 + 精度（没有就按价猜） */
export function priceText(price: number | null | undefined, decimals?: number | null): string {
  if (price == null || !Number.isFinite(price)) return MISSING
  return grouped(fmtPrice(price, decimals ?? priceDecimalsFallback(price)))
}

/** 涨跌幅：+1.23% / −1.23%；缺值 — */
export function changePercentText(pct: number | null | undefined, missing = MISSING): string {
  if (pct == null || !Number.isFinite(pct)) return missing
  const mag = toFixed(Math.abs(pct), 2)
  const zero = !/[1-9]/.test(mag)
  return (pct < 0 && !zero ? MINUS : '+') + mag + '%'
}

/** 写出来的涨跌是「涨」吗（按字面判：−0.004% 写成 +0.00% 就算涨） */
export const textIsUp = (text: string): boolean => !(text.startsWith(MINUS) || text.startsWith('-'))

/** 成交额：K / M / B / T 两位小数 */
export function fmtVol(x: number | null | undefined): string {
  if (x == null || !Number.isFinite(x)) return '--'
  const a = Math.abs(x)
  if (a >= 1e12) return toFixed(x / 1e12, 2) + 'T'
  if (a >= 1e9) return toFixed(x / 1e9, 2) + 'B'
  if (a >= 1e6) return toFixed(x / 1e6, 2) + 'M'
  if (a >= 1e3) return toFixed(x / 1e3, 2) + 'K'
  return a >= 100 ? toFixed(x, 0) : toFixed(x, 2)
}

/** HTML 转义 */
export function esc(s: unknown): string {
  return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))
}
