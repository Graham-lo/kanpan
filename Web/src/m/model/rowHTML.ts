/* 手机网页版 · 品种行（照 iOS LiuliSymbolRow / ChangePill / SymbolRowView）
 *
 * 自选页与板块下钻共用「琉璃行」；搜索用整页行。输出 HTML 字符串，行情推送来时用 patch* 就地改字，不重建整行。
 */
import type { CompareRowState } from './compareMode'
import { assetOf, badgeHTML, liuliBadgeHTML, type BadgeAsset } from './badge'
import { changePercentText, esc, fmtVol, MISSING, priceText, textIsUp } from './rowText'
import { splitHighlight } from './search'
import { pairOf, splitSymbol, venueTagHTML } from './symKey'
import type { Sym } from '../../market/symbols'

/** venue：名字前那截灰小字缩写的 HTML（币安 / OKX / Bybit / HL / CB；美元指数空串）；mark：徽章按哪个币认（别家用品种表的 base，kPEPE → PEPE） */
export interface RowFacts { symbol: string; base: string; quote: string; asset: BadgeAsset; kind?: Sym['kind']; cn?: string; isNew?: boolean; venue?: string; mark?: string }
/** 上线 30 天内挂「新」字（iOS SymbolInfo.isNewListing：onboardDate 缺 / 非正 / 在未来都不挂） */
export const NEW_LISTING_MS = 30 * 86_400_000
export function isNewListing(onboard: number | null | undefined, now = Date.now()): boolean {
  if (!onboard || onboard <= 0) return false
  const age = now - onboard
  return age >= 0 && age <= NEW_LISTING_MS
}
/** 「新」字记号（NewListingMark：12 medium、强调色） */
const NEW_MARK = '<span class="row-new" aria-label="新上线">新</span>'
/** 代号拆成 (base, quote)：BTCUSDT → BTC / USDT；1000PEPEUSDT → 1000PEPE / USDT（实现挪到 symKey，老调用照旧从这里拿） */
export { splitSymbol }
/** 一行的事实：名字两截按品种所属交易所拆（币安按代号；别家按品种表 title / quote，表没到按键猜），名字前带交易所缩写 */
export function factsOf(symbol: string, s?: (Pick<Sym, 'kind' | 'cn' | 'onboard'> & Partial<Pick<Sym, 'title' | 'quote' | 'macro' | 'base'>>) | null, now = Date.now()): RowFacts {
  const { base, quote } = pairOf(symbol, s)
  const mark = symbol.includes('/') && s?.base ? s.base : base
  return { symbol, base, quote, asset: assetOf(s?.kind, mark), kind: s?.kind, cn: s?.cn, isNew: isNewListing(s?.onboard, now), venue: venueTagHTML(symbol), mark }
}

/** 涨跌药丸：宽 72 高 28，底是涨跌色 14%、描边 30%，字就是涨跌色。
 *  缺值两种：还在路上（骨架，只剩一块底不写字）；gone = 目录说它没有实时价（已下架 / 目录里没有），写「—」 */
export function pillHTML(pct: number | null | undefined, text?: string, gone = false, muted = false): string {
  const t = text ?? changePercentText(pct)
  if (t === MISSING) return `<span class="m-pill none${gone ? ' gone' : ''} num">${MISSING}</span>`
  // 休市 / 上次记下的（还没连上实时）：照写涨跌、退成弱墨，不着涨跌色（不是骨架）
  if (muted) return `<span class="m-pill none muted num">${esc(t)}</span>`
  return `<span class="m-pill ${textIsUp(t) ? 'up' : 'down'} num">${esc(t)}</span>`
}

/** gone：目录说它没有实时价（已下架 / 目录里没有）——不摆骨架（那块灰底会永远亮着，读起来像永远加载不完），
 *  价格与涨跌写「—」、退成次要文字色（照 iOS FavoritesView 行：skeleton = 价缺 && !stale） */
export interface LiuliData { price: number | null; dec?: number | null; pct: number | null; vol: number | null; priceText?: string; extra?: string; gone?: boolean
  /** 行情帧自己说了休市（美元指数周末）：价格退灰、涨跌药丸退成中性灰，数照摆（照 iOS FavoritesView） */
  closed?: boolean
  /** 自选行那条 24 小时走势线（model/favoriteTrend 的 trendSVG）。undefined = 这张表不摆这一列（开关关着 / 板块下钻）；
   *  空串 = 摆着这一格但还没数据（空着那 44，不摆占位） */
  trend?: string }
/** 成交额那格缺数写「—」，和同一行价格 / 涨跌的缺数一个样（iOS sectorVolumeText） */
const volText = (v: number | null): string => v != null && Number.isFinite(v) ? fmtVol(v) : MISSING
const priceCell = (d: LiuliData): { cls: string; text: string } => {
  const t = d.priceText ?? (d.price == null ? '' : priceText(d.price, d.dec))
  if (t) return { cls: d.gone || d.closed ? 'lr-price num gone' : 'lr-price num', text: t }
  return d.gone ? { cls: 'lr-price num gone', text: MISSING } : { cls: 'lr-price skel', text: '' }
}
/** 没有计价币的指数（美元指数）：代号后面不写斜杠，跟一截灰的中文名（照 iOS 行） */
const idxName = (f: RowFacts): string => f.kind === 'idx' && !f.quote && f.cn ? f.cn : ''
/** 琉璃行（高 66）：徽章 33 · 名字 + 成交额 · 价格 + 药丸；第一行不画顶上那道发丝线 */
export function liuliRowHTML(f: RowFacts, d: LiuliData, first: boolean, options: { extraCls?: string; compactName?: boolean } = {}): string {
  const price = priceCell(d)
  const { extraCls = '', compactName = false } = options
  const name = compactName ? `<span class="lr-base">${esc(f.base + f.quote)}</span>`
    : `${f.venue ?? ''}<span class="lr-base">${esc(f.base)}</span>${f.quote ? `<span class="lr-quote">${esc(f.quote)}</span>` : idxName(f) ? `<span class="lr-quote">${esc(idxName(f))}</span>` : ''}`
  return `<div class="lr${first ? ' first' : ''}${extraCls ? ' ' + extraCls : ''}" data-sym="${esc(f.symbol)}" role="button" tabindex="0">`
    + `<div class="lr-in">${liuliBadgeHTML(f.mark ?? f.base, f.asset)}`
    + `<div class="lr-name"><div class="lr-top">${name}${f.isNew ? NEW_MARK : ''}</div>`
    + `<div class="lr-meta num"><span class="lr-vol">成交额 ${esc(volText(d.vol))}</span>${d.extra ?? ''}</div></div>`
    + `<div class="lr-right${d.trend === undefined ? ' solo' : ''}"><span class="${price.cls}">${esc(price.text)}</span>${d.trend === undefined ? pillHTML(d.pct, undefined, !!d.gone, !!d.closed)
      : `<span class="lr-tp"><span class="lr-trend">${d.trend}</span>${pillHTML(d.pct, undefined, !!d.gone, !!d.closed)}</span>`}</div>`
    + `</div></div>`
}
/** 推送来了：只改价格、药丸与成交额 */
export function patchLiuli(row: Element, d: LiuliData): void {
  const p = row.querySelector('.lr-price')
  if (p) {
    const c = priceCell(d)
    // 还在路上时不把已经摆出来的价格擦回骨架
    if (c.text) { if (p.className !== c.cls) p.className = c.cls; if (p.textContent !== c.text) p.textContent = c.text }
  }
  const pill = row.querySelector('.m-pill')
  if (pill) {
    const t = changePercentText(d.pct)
    const cls = 'm-pill ' + (t === MISSING ? (d.gone ? 'none gone' : 'none') : d.closed ? 'none muted' : textIsUp(t) ? 'up' : 'down') + ' num'
    if (pill.textContent !== t || pill.className !== cls) pill.outerHTML = pillHTML(d.pct, undefined, !!d.gone, !!d.closed)
  }
  const v = row.querySelector('.lr-vol')
  if (v) { const t = '成交额 ' + volText(d.vol); if (v.textContent !== t) v.textContent = t }
  if (d.trend !== undefined) {
    const tr = row.querySelector('.lr-trend')
    if (tr && drawnTrend.get(tr) !== d.trend) { drawnTrend.set(tr, d.trend); tr.innerHTML = d.trend }
  }
}
/** 走势线那一格上次画的是哪一份（innerHTML 读回来会被浏览器改写，比不出来） */
const drawnTrend = new WeakMap<Element, string>()

/** 搜索结果行（SymbolRowView）：徽章 32 · base（命中处着色）/ quote · 右侧价格与涨跌 · 星 */
export function listRowHTML(f: RowFacts, d: { price: number | null; dec?: number | null; pct: number | null; meta: string; fav: boolean; hl?: [number, number] | null; cmp?: CompareRowState }): string {
  const baseParts = splitHighlight(f.base, d.hl ?? null, 0).map(p => p.hit ? `<em>${esc(p.text)}</em>` : esc(p.text)).join('')
  const quoteParts = splitHighlight(f.quote, d.hl ?? null, f.base.length).map(p => p.hit ? `<em>${esc(p.text)}</em>` : esc(p.text)).join('')
  const chg = changePercentText(d.pct)
  const dir = chg === MISSING ? '' : textIsUp(chg) ? 'up' : 'down'
  // 对比模式（搜索页顶栏 ＋ 开的那一副）：主图那一行整行退成禁用色、点不动
  const main = d.cmp === 'main'
  return `<div class="sr${main ? ' cmp-main' : ''}" data-sym="${esc(f.symbol)}" role="button" tabindex="${main ? -1 : 0}"${main ? ' aria-disabled="true"' : ''}>${badgeHTML(f.mark ?? f.base, 32, f.asset)}`
    + `<div class="sr-name"><div class="sr-top">${f.venue ?? ''}<span class="sr-base">${baseParts}</span>${f.quote ? `<span class="sr-sep"> / </span><span class="sr-quote">${quoteParts}</span>` : idxName(f) ? `<span class="sr-sep"> </span><span class="sr-quote">${esc(idxName(f))}</span>` : ''}${f.isNew ? NEW_MARK : ''}</div>`
    + `<div class="sr-meta">${esc(d.meta)}</div></div>`
    + `<div class="sr-right num"><span class="sr-price">${esc(priceText(d.price, d.dec))}</span><span class="sr-chg ${dir}">${esc(chg)}</span></div>`
    + (d.cmp ? compareMarkHTML(f.symbol, d.cmp)
      : `<button type="button" class="sr-star${d.fav ? ' on' : ''}" data-star="${esc(f.symbol)}" aria-label="${d.fav ? '取消自选' : '加入自选'}" aria-pressed="${d.fav}">${STAR}</button>`)
    + `</div>`
}
const CMP_VALUE: Record<CompareRowState, string> = { add: '可添加', added: '已添加', full: '已满', main: '主图' }
/** 对比模式的行尾（照 iOS SymbolListRow.compareMark）：可加是一颗淡底 ＋，已加是强调色实心圆里一个 ✓，满了是退色的 ＋；看得见 24、点击区 44 */
function compareMarkHTML(symbol: string, state: CompareRowState): string {
  const added = state === 'added'
  const glyph = added
    ? '<svg width="12" height="12" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5" fill="none" stroke="currentColor" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
    : PLUS_GLYPH
  return `<button type="button" class="sr-cmp ${state}" data-cmp="${esc(symbol)}" aria-label="${added ? '移除对比' : '添加对比'}" aria-description="${CMP_VALUE[state]}" aria-pressed="${added}"${state === 'main' ? ' tabindex="-1"' : ''}><span>${glyph}</span></button>`
}
/** 顶栏「对比＋」与对比行尾共用的加号 */
export const PLUS_GLYPH = '<svg width="12" height="12" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 4.5v15M4.5 12h15" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/></svg>'
export const STAR = '<svg width="15" height="15" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.8l2.83 5.73 6.32.92-4.57 4.46 1.08 6.3L12 17.24l-5.66 2.97 1.08-6.3-4.57-4.46 6.32-.92z" stroke-linejoin="round"/></svg>'
