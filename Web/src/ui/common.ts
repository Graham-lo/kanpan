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
export function badge(s: BadgeSrc, size = ''): string {
  const b = s?.base || '?'
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
