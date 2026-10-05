/* Hkline Web · 各页共用的展示小件（价格、涨跌、徽标、时间） */
import { S } from '../market/state'
import type { Sym } from '../market/symbols'
import { fmt, pad, sh } from '../util/format'
import { esc } from './dom'

export const sym = (k: string): Sym | undefined => S.symbols.get(k)
export const pctText = (p: number | null | undefined): string => p == null || !isFinite(p) ? '—' : `${p >= 0 ? '+' : ''}${p.toFixed(2)}%`
export const cls = (p: number | null | undefined): string => p == null || !isFinite(p) || p === 0 ? '' : p > 0 ? 'up' : 'down'
export function priceText(s: Sym | undefined, v: number | null | undefined = s?.price): string { return v == null ? '—' : fmt(v, s?.dec ?? 2) }
export const clamp01 = (v: number): number => Math.max(0, Math.min(1, isFinite(v) ? v : 0))

type BadgeSrc = Pick<Sym, 'base' | 'color'> | undefined
/** 美元指数：和手机同一枚描粗美元符号（钞票绿渐变、圆头），不写首字母，免得和 USDT / USDC 的圆片读成一类 */
const DXY_MARK = '<svg viewBox="0 0 24 24" width="66%" height="66%"><path fill="none" stroke="#fff" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round" d="M16.2 8.3c-.8-1.5-2.4-2.4-4.2-2.4-2.4 0-4.2 1.4-4.2 3.2 0 2 1.8 2.7 4.2 3.2s4.2 1.3 4.2 3.3c0 1.9-1.8 3.2-4.2 3.2-1.9 0-3.5-.9-4.3-2.4M12 3.4v17.2"/></svg>'
export function badge(s: BadgeSrc, size = ''): string {
  const b = s?.base || '?'
  if (b === 'DXY') return `<span class="badge ${size}" style="background:linear-gradient(135deg,#6FBF8E,#23634A)" aria-hidden="true">${DXY_MARK}</span>`
  const t = b.length > 3 ? b.slice(0, 3) : b
  return `<span class="badge ${size}" style="background:${s?.color || '#888'}" aria-hidden="true">${esc(t)}</span>`
}

export function countdown(ms: number | null | undefined): string {
  if (ms == null) return '—'
  const s = Math.max(0, Math.floor(ms / 1000))
  return `${pad(Math.floor(s / 3600))}:${pad(Math.floor(s % 3600 / 60))}:${pad(s % 60)}`
}

/** 上海时间：「9月29日 14:05」或「14:05」 */
export function shTime(t: number, withDate = true): string {
  const d = sh(t)
  const hm = `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`
  return withDate ? `${d.getUTCMonth() + 1}月${d.getUTCDate()}日 ${hm}` : hm
}

export const ratioText = (r: number | null | undefined): string => r == null || !isFinite(r) ? '—' : r.toFixed(2)
export const ratioCls = (r: number | null | undefined): string => r == null ? '' : r > 1 ? 'up' : r < 1 ? 'down' : ''
