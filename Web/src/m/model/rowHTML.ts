/* 手机网页版 · 品种行（照 iOS LiuliSymbolRow / ChangePill / SymbolRowView）
 *
 * 自选页与板块下钻共用「琉璃行」；搜索用整页行。输出 HTML 字符串，行情推送来时用 patch* 就地改字，不重建整行。
 */
import { assetOf, badgeHTML, liuliBadgeHTML, type BadgeAsset } from './badge'
import { changePercentText, esc, fmtVol, MISSING, priceText, textIsUp } from './rowText'
import { splitHighlight } from './search'
import type { Sym } from '../../market/symbols'

export interface RowFacts { symbol: string; base: string; quote: string; asset: BadgeAsset; kind?: Sym['kind']; cn?: string }
const QUOTES = ['USDT', 'USDC', 'FDUSD', 'BUSD', 'USD1', 'TUSD', 'USD']
/** 代号拆成 (base, quote)：BTCUSDT → BTC / USDT；1000PEPEUSDT → 1000PEPE / USDT */
export function splitSymbol(symbol: string): { base: string; quote: string } {
  for (const q of QUOTES) if (symbol.length > q.length && symbol.endsWith(q)) return { base: symbol.slice(0, -q.length), quote: q }
  return { base: symbol, quote: '' }
}
export function factsOf(symbol: string, s?: Pick<Sym, 'kind' | 'cn'> | null): RowFacts {
  const { base, quote } = splitSymbol(symbol)
  return { symbol, base, quote, asset: assetOf(s?.kind, base), kind: s?.kind, cn: s?.cn }
}

/** 涨跌药丸：宽 72 高 28，底是涨跌色 14%、描边 30%，字就是涨跌色；缺值画「—」 */
export function pillHTML(pct: number | null | undefined, text?: string): string {
  const t = text ?? changePercentText(pct)
  if (t === MISSING) return `<span class="m-pill none num">${MISSING}</span>`
  return `<span class="m-pill ${textIsUp(t) ? 'up' : 'down'} num">${esc(t)}</span>`
}

export interface LiuliData { price: number | null; dec?: number | null; pct: number | null; vol: number | null; priceText?: string; extra?: string }
/** 琉璃行（高 66）：徽章 33 · 名字 + 成交额 · 价格 + 药丸；第一行不画顶上那道发丝线 */
export function liuliRowHTML(f: RowFacts, d: LiuliData, first: boolean, extraCls = ''): string {
  const price = d.priceText ?? (d.price == null ? '' : priceText(d.price, d.dec))
  return `<div class="lr${first ? ' first' : ''}${extraCls ? ' ' + extraCls : ''}" data-sym="${esc(f.symbol)}" role="button" tabindex="0">`
    + `<div class="lr-in">${liuliBadgeHTML(f.base, f.asset)}`
    + `<div class="lr-name"><div class="lr-top"><span class="lr-base">${esc(f.base)}</span>${f.quote ? `<span class="lr-quote">${esc(f.quote)}</span>` : ''}</div>`
    + `<div class="lr-meta num"><span class="lr-vol">成交额 ${esc(fmtVol(d.vol))}</span>${d.extra ?? ''}</div></div>`
    + `<div class="lr-right">${price ? `<span class="lr-price num">${esc(price)}</span>` : '<span class="lr-price skel"></span>'}${pillHTML(d.pct)}</div>`
    + `</div></div>`
}
/** 推送来了：只改价格、药丸与成交额 */
export function patchLiuli(row: Element, d: LiuliData): void {
  const p = row.querySelector('.lr-price')
  if (p) {
    const t = d.priceText ?? (d.price == null ? '' : priceText(d.price, d.dec))
    if (t) { p.classList.remove('skel'); if (p.textContent !== t) p.textContent = t }
  }
  const pill = row.querySelector('.m-pill')
  if (pill) {
    const html = pillHTML(d.pct)
    const t = changePercentText(d.pct)
    if (pill.textContent !== t) pill.outerHTML = html
  }
  const v = row.querySelector('.lr-vol')
  if (v) { const t = '成交额 ' + fmtVol(d.vol); if (v.textContent !== t) v.textContent = t }
}

/** 搜索结果行（SymbolRowView）：徽章 32 · base（命中处着色）/ quote · 右侧价格与涨跌 · 星 */
export function listRowHTML(f: RowFacts, d: { price: number | null; dec?: number | null; pct: number | null; meta: string; fav: boolean; hl?: [number, number] | null }): string {
  const baseParts = splitHighlight(f.base, d.hl ?? null, 0).map(p => p.hit ? `<em>${esc(p.text)}</em>` : esc(p.text)).join('')
  const quoteParts = splitHighlight(f.quote, d.hl ?? null, f.base.length).map(p => p.hit ? `<em>${esc(p.text)}</em>` : esc(p.text)).join('')
  const chg = changePercentText(d.pct)
  const dir = chg === MISSING ? '' : textIsUp(chg) ? 'up' : 'down'
  return `<div class="sr" data-sym="${esc(f.symbol)}" role="button" tabindex="0">${badgeHTML(f.base, 32, f.asset)}`
    + `<div class="sr-name"><div class="sr-top"><span class="sr-base">${baseParts}</span>${f.quote ? `<span class="sr-sep"> / </span><span class="sr-quote">${quoteParts}</span>` : ''}</div>`
    + `<div class="sr-meta">${esc(d.meta)}</div></div>`
    + `<div class="sr-right num"><span class="sr-price">${esc(priceText(d.price, d.dec))}</span><span class="sr-chg ${dir}">${esc(chg)}</span></div>`
    + `<button type="button" class="sr-star${d.fav ? ' on' : ''}" data-star="${esc(f.symbol)}" aria-label="${d.fav ? '取消自选' : '加入自选'}" aria-pressed="${d.fav}">${STAR}</button>`
    + `</div>`
}
export const STAR = '<svg width="15" height="15" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.8l2.83 5.73 6.32.92-4.57 4.46 1.08 6.3L12 17.24l-5.66 2.97 1.08-6.3-4.57-4.46 6.32-.92z" stroke-linejoin="round"/></svg>'
