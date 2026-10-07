/* Hkline Web · 各页共用的展示小件（价格、涨跌、徽标、时间） */
import { S } from '../market/state'
import type { Sym } from '../market/symbols'
import { fmt, pad, sh } from '../util/format'
import { esc } from './dom'
import { assetOf, badgeLine, coinSpec } from '../m/model/badge'

export const sym = (k: string): Sym | undefined => S.symbols.get(k)
export const pctText = (p: number | null | undefined): string => p == null || !isFinite(p) ? '—' : `${p >= 0 ? '+' : ''}${p.toFixed(2)}%`
export const cls = (p: number | null | undefined): string => p == null || !isFinite(p) || p === 0 ? '' : p > 0 ? 'up' : 'down'
export function priceText(s: Sym | undefined, v: number | null | undefined = s?.price): string { return v == null ? '—' : fmt(v, s?.dec ?? 2) }
export const clamp01 = (v: number): number => Math.max(0, Math.min(1, isFinite(v) ? v : 0))

type BadgeSrc = (Pick<Sym, 'base'> & Partial<Pick<Sym, 'kind'>>) | undefined
const BADGE_PX: Record<string, number> = { '': 20, lg: 28, xl: 40 }
const r2 = (n: number): string => String(Math.round(n * 100) / 100)
/** 美元指数：和手机同一枚描粗美元符号（钞票绿渐变、圆头），不写首字母，免得和 USDT / USDC 的圆片读成一类 */
const DXY_MARK = '<svg viewBox="0 0 24 24" width="66%" height="66%"><path fill="none" stroke="#fff" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round" d="M16.2 8.3c-.8-1.5-2.4-2.4-4.2-2.4-2.4 0-4.2 1.4-4.2 3.2 0 2 1.8 2.7 4.2 3.2s4.2 1.3 4.2 3.3c0 1.9-1.8 3.2-4.2 3.2-1.9 0-3.5-.9-4.3-2.4M12 3.4v17.2"/></svg>'
/** 品种徽标：和 iOS / 手机网页同一套记号（认得出的牌子画牌子的白色标志，其余按代号生成几何记号），
 *  底色用牌子自己的渐变，不往皮肤主色拢——电脑网页是自己的一套视觉，圆形外框照旧 */
export function badge(s: BadgeSrc, size = ''): string {
  const b = s?.base || '?'
  if (b === 'DXY') return `<span class="badge ${size}" style="background:linear-gradient(135deg,#6FBF8E,#23634A)" aria-hidden="true">${DXY_MARK}</span>`
  const px = BADGE_PX[size] ?? 20
  const spec = coinSpec(b, assetOf(s?.kind, b))
  let mark: string
  if ('text' in spec.mark) {
    const n = [...spec.mark.text].length
    const fs = Math.max(Math.min(px * 0.46, (px * 0.8) / Math.max(1, n * 0.62)), px * 0.25)
    mark = `<span style="font-size:${r2(fs)}px">${esc(spec.mark.text)}</span>`
  } else {
    const box = px * Math.min(spec.inset, 0.66)
    mark = `<svg width="${r2(box)}" height="${r2(box)}" viewBox="0 0 24 24">` + spec.mark.parts.map(p => {
      if (!p.d.length) return ''
      if (p.stroke == null) return `<path fill="#fff" d="${p.d.join('')}"/>`
      return `<path fill="none" stroke="#fff" stroke-width="${r2(badgeLine(p.stroke, px) * 24 / box)}" stroke-linecap="round" stroke-linejoin="round" d="${p.d.join('')}"/>`
    }).join('') + '</svg>'
  }
  return `<span class="badge ${size}" style="background:linear-gradient(135deg,${spec.from},${spec.to})" aria-hidden="true">${mark}</span>`
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
