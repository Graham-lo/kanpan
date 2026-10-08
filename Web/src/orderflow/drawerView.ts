/* Hkline Web · 主力订单流 · 底部抽屉「大单列表」的纯计算与 HTML / SVG 片段（2026-10-08 改版，照 docs/prototypes/web-bigtrade-drawer-2026-10-08.html）
 *
 * 这里不碰 DOM、不读全局状态，drawer.ts 量好尺寸、取好数据后交给这里出字符串；测试直接测这里：
 *   · barText：对撞条比金额字短时字怎么摆（挪到条外 / 把条撑到字宽）
 *   · placeAxis：价位块的竖向价格轴，按真实价摆、挤了互相让开
 *   · liqBuckets：今天的爆仓按 15 分钟（窄了自动并成 30 分 / 1 时）一桶
 *   · histFmt：只有服务端历史的那几项（笔数、最大一笔、来源）写「—」
 *   · cumPoints：今日累计净额的点位（迷你走势与拉高后的大图共用）
 * 颜色一律写 CSS 变量（--up / --down / --of-*），皮肤与深浅色跟着变，不在这里挑色。
 */
import { udOf, type BarBig, type BarLiq } from './bigTags'
import type { LiqRow } from './liquidation'
import { amt, amtTight, hm, mdhm } from './state'
import { BT, fill } from '../terms'
import { EXCHANGE_COLORS, EXCHANGE_NAMES } from '../venues'

export const MINUS = '−'
export const DASH = '<span class="dash">—</span>'
const MIN = 60_000, HOUR = 3_600_000, DAY = 86_400_000

/** 带符号的金额：+1.2M / −3.4M / 0 */
export const signed = (v: number): string => Math.abs(v) < 0.5 ? '0' : v > 0 ? `+${amt(v)}` : `${MINUS}${amt(-v)}`
/** 涨跌色类名 */
export const tone = (v: number): string => v > 0 ? 'up' : v < 0 ? 'dn' : 't3'
/** 只有浏览器实时记到才有的项（笔数、最大一笔、占比）：没有就是「—」 */
export function histFmt<T>(v: T | null | undefined, f: (v: T) => string): string { return v == null ? '—' : f(v) }
/** 占比整数百分比；总数为 0 时「—」 */
export const pct = (v: number, tot: number): string => tot > 0 ? `${Math.round(v / tot * 100)}%` : '—'

// ------------------------------------------------------------------ 对撞条

/** 半边条长 bar（px）、金额字宽 text（含左右内边距）、半边可用宽 half：
 *  条比字长 → 字在条里；条比字短且条 + 字 + 2 放得下 → 字挪到条外（shift = 条长）；放不下 → 条撑到字宽 + 4、字仍在条里 */
export function barText(bar: number, text: number, half: number): { bar: number; shift: number } {
  if (!(bar > 0) || bar >= text) return { bar: Math.max(0, bar), shift: 0 }
  if (bar + text + 2 <= half) return { bar, shift: bar }
  return { bar: Math.min(half, text + 4), shift: 0 }
}

export interface BfIn { s: number; b: number; max: number; half: number; tw: (t: string) => number }
/** 半边条里写哪一档金额：完整（15.2M）→ 收成整数（15M）→ 都放不下就不写字（''，只剩条）。字宽含左右各 5 的内边距 */
export function bfLabel(v: number, half: number, tw: (t: string) => number): string {
  const t0 = v > 0 ? amt(v) : '0'
  if (tw(t0) + 10 <= half) return t0
  const t1 = amtTight(v)
  return tw(t1) + 10 <= half ? t1 : ''
}
/** 一条对撞条：左半卖（跌色，从中线往左）、右半买（涨色，往右），金额写在条里；max = 比例尺（窄屏按本行、宽屏整列共用） */
export function bfHtml({ s, b, max, half, tw }: BfIn): string {
  const m = Math.max(1, max)
  const side = (v: number, cls: 's' | 'b'): string => {
    // 半边放不下完整金额就收成整数（15.2M → 15M），再放不下就只画条不写字——字不许溢出到中线另一侧、时间列或旁边的净额列
    const t = bfLabel(v, half, tw)
    if (!t) return `<div class="h ${cls}"><i style="width:${(v > 0 ? Math.max(2, v / m * half) : 0).toFixed(1)}px"></i></div>`
    const p = barText(v > 0 ? Math.max(2, v / m * half) : 0, tw(t) + 10, half)
    const mg = p.shift ? ` style="margin-${cls === 's' ? 'right' : 'left'}:${p.shift.toFixed(1)}px"` : ''
    return `<div class="h ${cls}"><i style="width:${p.bar.toFixed(1)}px"></i><span class="num${v > 0 ? '' : ' z'}"${mg}>${t}</span></div>`
  }
  return `<div class="bf">${side(s, 's')}${side(b, 'b')}</div>`
}

// ------------------------------------------------------------------ 逐根：列布局与行
//
// 原来是 CSS 里三套写死的像素列（窄卡 52 / ≥76 / 52 / 38 / 50 / 26），字比列宽就压到隔壁：1 时「242/191」有 45 px 却只给 38，
// 顶到最大单笔；对撞条半边比收短的金额还窄时字往左漫进时间列。现在先按这一屏的真实字宽量出每列要多宽（barNeed），
// 再按行宽挑列（barCols）：放得下照原来的疏密，放不下各列贴着字宽，再放不下依次省「来源」「笔数」「最大单笔」（悬停卡里都有）。

/** 量字宽：weight / size 默认 600 / 11；ui = 界面字体（表头的中文），否则数字字体 */
export type Measure = (t: string, weight?: number, size?: number, ui?: boolean) => number
/** 逐根各列要多宽（px，按真实字宽量好、已含小点等装饰）。tm / tmWide：窄卡只写时:分（日线月-日）/ 宽卡带日期，表头「逐根 15分」也在这一列；
 *  bf：对撞条单边收短金额最宽的那个 + 内边距；n 净额；c 笔数「买/卖」；m 最大单笔；x 现货占比；v 来源 */
export interface BarNeed { tm: number; tmWide: number; bf: number; n: number; c: number; m: number; x: number; v: number }
/** 逐根的列：cols = grid-template-columns，gap 列间距；wide = 宽卡（时间带日期、多一列现货、整列共用一把尺子）；c / m / v = 笔数、最大单笔、来源在不在 */
export interface BarCols { cols: string; gap: number; wide: boolean; c: boolean; m: boolean; v: boolean }

/** 设计宽（字比它窄时照这个摆，留住原来的疏密）。min = 行内宽（卡内宽减行左右各 6）到多少才用宽卡那两档 */
const COLS_NARROW = { tm: 52, bf: 76, n: 52, c: 38, m: 50, v: 26, gap: 6 }
const COLS_WIDE = [
  { min: 788, tm: 92, bf: 200, n: 80, c: 64, m: 80, x: 60, v: 120, gap: 10 },
  { min: 628, tm: 80, bf: 150, n: 68, c: 50, m: 70, x: 50, v: 90, gap: 8 },
] as const

const cpx = (v: number): string => `${Math.ceil(v)}px`

/** 按行内宽 w 挑列。宽卡两档放得下才用；窄卡依次试：设计宽全列 → 设计宽省来源 → 贴字宽省来源 → 再省笔数 → 再省最大单笔。
 *  连最后一档都放不下时对撞条退到 minmax(0, 1fr)，条里的字由 bfLabel 自己收（收不下就不写），不会压到别列 */
export function barCols(w: number, need: BarNeed): BarCols {
  const bfMin = Math.ceil(2 * need.bf + 2)
  for (const d of COLS_WIDE) {
    if (w < d.min) continue
    const ws = [Math.max(d.tm, need.tmWide), Math.max(d.n, need.n), Math.max(d.c, need.c), Math.max(d.m, need.m), Math.max(d.x, need.x), Math.max(d.v, need.v)].map(Math.ceil)
    const bf = Math.max(d.bf, bfMin)
    if (ws.reduce((a, b) => a + b, 0) + bf + 6 * d.gap <= w) {
      return { cols: `${cpx(ws[0])} minmax(${bf}px, 1fr) ${ws.slice(1).map(cpx).join(' ')}`, gap: d.gap, wide: true, c: true, m: true, v: true }
    }
  }
  const d = COLS_NARROW, g = d.gap
  // [照设计宽, 笔数, 最大单笔, 来源]
  const tries: readonly [boolean, boolean, boolean, boolean][] = [[true, true, true, true], [true, true, true, false], [false, true, true, false], [false, false, true, false], [false, false, false, false]]
  let last: BarCols | null = null
  for (const [loose, c, m, v] of tries) {
    const pick = (k: 'tm' | 'n' | 'c' | 'm' | 'v'): number => Math.ceil(loose ? Math.max(d[k], need[k]) : need[k])
    const ws = [pick('tm'), pick('n'), ...(c ? [pick('c')] : []), ...(m ? [pick('m')] : []), ...(v ? [Math.max(d.v, Math.ceil(need.v))] : [])]
    const bf = loose ? Math.max(d.bf, bfMin) : bfMin
    const fits = ws.reduce((a, b) => a + b, 0) + bf + ws.length * g <= w
    last = { cols: `${cpx(ws[0])} minmax(${fits ? bf : 0}px, 1fr) ${ws.slice(1).map(cpx).join(' ')}`, gap: g, wide: false, c, m, v }
    if (fits) return last
  }
  return last!
}

/** 一根的时间：日线及以上写月-日；宽卡带日期；窄卡只写时:分（跨天处另插一行日期） */
export function barTime(t: number, wide: boolean, daily: boolean): string {
  const md = mdhm(t)
  return daily ? md.slice(0, 5) : wide ? md : hm(t)
}

export interface BarRowIn { t: number; d: BarBig }
const LIVE_W = 10 // 正在走那根的小点 6 + 间距 4
const SLACK = 2 // 量出来的字宽与真实排版之间留一点余量（亚像素、字距）
/** 量这一屏要多宽：每列取表头与各行里最宽的那个 */
export function barNeed(rows: readonly BarRowIn[], iv: number, tw: Measure): BarNeed {
  const daily = iv >= DAY
  const title = tw(BT.perBar, 650, 12, true) + 4 + tw(ivShort(iv), 500, 11, true)
  let tm = 0, tmW = 0, bf = tw('0') + 10
  let n = tw(BT.net, 400, 11, true), c = tw(BT.trades, 400, 11, true), m = tw(BT.maxSingle, 400, 11, true)
  const x = Math.max(tw(BT.spot, 400, 11, true), tw('100%', 400)), v = tw(BT.source, 400, 11, true)
  for (const { t, d } of rows) {
    tm = Math.max(tm, tw(barTime(t, false, daily)))
    tmW = Math.max(tmW, tw(barTime(t, true, daily)))
    for (const a of [d.bs, d.bb]) if (a > 0) bf = Math.max(bf, tw(amtTight(a)) + 10)
    n = Math.max(n, tw(signed(d.bb - d.bs), 650, 12))
    c = Math.max(c, d.bn != null && d.sn != null ? tw(`${d.bn}/${d.sn}`, 400) : tw('—', 400))
    const mx = d.exact ? maxOf(d) : null
    m = Math.max(m, mx ? 9 + tw(amt(mx.usd), 400) : tw('—', 400))
  }
  return {
    tm: Math.max(title, tm + LIVE_W) + SLACK, tmWide: Math.max(title, tmW + LIVE_W) + SLACK, bf: bf + 1,
    n: n + SLACK, c: c + SLACK, m: m + SLACK, x: x + SLACK, v: v + SLACK,
  }
}

/** 逐根的表头：只摆 k 里在的列；k = null（没有行）只写标题 */
export function barHeadHtml(iv: number, k: BarCols | null): string {
  const t = `<span class="t">${BT.perBar}<em>${ivShort(iv)}</em></span>`
  if (!k) return t
  return t + `<div class="bf-h"><span>${BT.sellShort}</span><span>${BT.buyShort}</span></div><span class="rt">${BT.net}</span>` +
    (k.c ? `<span class="rt">${BT.trades}</span>` : '') + (k.m ? `<span class="rt">${BT.maxSingle}</span>` : '') +
    (k.wide ? `<span class="rt">${BT.spot}</span>` : '') + (k.v ? `<span class="rt">${BT.source}</span>` : '')
}

export interface BarRowEnv {
  k: BarCols; half: number; max: number; lastT: number; live: boolean; daily: boolean
  /** 选中的那根、十字线停的那根（开盘时间） */
  sel: number | null; cross: number | null
  tw: (t: string) => number
}
/** 逐根一行：时间 | 对撞条 | 净额 |（笔数）|（最大单笔）|（现货）|（来源），括号里的按 k 摆 */
export function barRowHtml(r: BarRowIn, e: BarRowEnv): string {
  const d = r.d, n = d.bb - d.bs, k = e.k
  const cur = r.t === e.lastT, xh = e.cross === r.t, sel = e.sel === r.t
  const tm = barTime(r.t, k.wide, e.daily)
  const mark = !xh && cur && e.live ? '<span class="live"></span>' : ''
  const tot = d.bb + d.bs
  let tail = ''
  if (k.c) tail += `<span class="c num">${d.bn != null && d.sn != null ? `<span class="up">${d.bn}</span><span class="t3">/</span><span class="dn">${d.sn}</span>` : DASH}</span>`
  if (k.m) { const mx = d.exact ? maxOf(d) : null; tail += `<span class="m num">${mx ? `<i style="background:var(--${mx.buy ? 'up' : 'down'})"></i>${amt(mx.usd)}` : DASH}</span>` }
  if (k.wide) tail += `<span class="c num">${d.spot != null && tot > 0 ? pct(d.spot, tot) : DASH}</span>`
  if (k.v) tail += `<span class="v">${d.ex && tot > 0 ? seg3(VENUES.map(([, col], j) => [d.ex![j], col] as [number, string]), 'v3') : `<span class="dash">—</span>`}</span>`
  return `<div class="br${cur ? ' cur' : ''}${xh ? ' xh' : ''}${sel ? ' sel' : ''}" role="listitem" data-t="${r.t}" data-k="${r.t}">` +
    `<span class="tm num">${xh ? `<span class="xtag">${tm}</span>` : tm}${mark}</span>` +
    bfHtml({ s: d.bs, b: d.bb, max: k.wide ? e.max : Math.max(d.bs, d.bb), half: e.half, tw: e.tw }) +
    `<span class="n num ${tone(n)}">${signed(n)}</span>` + tail + '</div>'
}

/** 三段细带（各家 / 现货合约）：没有数据画一条底轨 */
export function seg3(parts: readonly [number, string][] | null, cls = 'seg3'): string {
  const tot = parts ? parts.reduce((a, [v]) => a + v, 0) : 0
  if (!parts || !(tot > 0)) return `<div class="${cls}"><i style="flex:1;background:var(--of-track)"></i></div>`
  return `<div class="${cls}">${parts.filter(([v]) => v > 0).map(([v, c]) => `<i style="flex:${(v / tot).toFixed(4)};background:${c}"></i>`).join('')}</div>`
}

/** 各家名字 + 颜色（顺序与 EXCHANGE_CH 一致），全从注册表来 */
export const VENUES: readonly [string, string][] = EXCHANGE_NAMES.map((n, i) => [n, EXCHANGE_COLORS[i]] as [string, string])

/** 现货 / 合约 + 各家占比两条（汇总底部、悬停卡共用）；spot / ex 为 null（只有历史）时数字写「—」、条是底轨 */
export function srcHtml(tot: number, spot: number | null, ex: readonly number[] | null): string {
  const has = tot > 0
  const sp = spot != null && has ? spot : null
  const a = `<div class="of-sr"><div class="tx"><span>${BT.spot}<b class="num">${sp == null ? '—' : pct(sp, tot)}</b></span><span>${BT.contract}<b class="num">${sp == null ? '—' : pct(tot - sp, tot)}</b></span></div>` +
    seg3(sp == null ? null : [[sp, 'var(--of-spot)'], [Math.max(0, tot - sp), 'var(--of-perp)']]) + '</div>'
  const e = ex && has ? ex : null
  const b = `<div class="of-sr"><div class="tx vn">${VENUES.map(([n, c], j) => `<span><i style="background:${c}"></i>${n}<b class="num">${e ? pct(e[j], tot) : '—'}</b></span>`).join('')}</div>` +
    seg3(e ? VENUES.map(([, c], j) => [e[j], c] as [number, string]) : null) + '</div>'
  return a + b
}

/** 一根里最大的那一笔（买、卖各一笔里取大的） */
export function maxOf(d: Pick<BarBig, 'bmax' | 'smax'>): { usd: number; price: number; exchange: string; buy: boolean } | null {
  const b = d.bmax, s = d.smax
  if (!b && !s) return null
  const m = b && (!s || b.usd >= s.usd) ? b : s!
  return { usd: m.usd, price: m.price, exchange: m.exchange, buy: m === b }
}

/** 周期短名：1秒 / 5分 / 1时 / 1日 / 1周 / 1月 */
export function ivShort(ms: number): string {
  const S = 1000, D = 24 * HOUR
  if (ms >= 28 * D) return `${Math.max(1, Math.round(ms / (30 * D)))}月`
  if (ms >= 7 * D && ms % (7 * D) === 0) return `${ms / (7 * D)}周`
  if (ms >= D) return `${Math.round(ms / D)}日`
  if (ms >= HOUR) return `${Math.round(ms / HOUR)}时`
  if (ms >= MIN) return `${Math.round(ms / MIN)}分`
  return `${Math.max(1, Math.round(ms / S))}秒`
}

// ------------------------------------------------------------------ 悬停卡（图上大单与爆仓气泡）

/** 悬停卡读数格顶上的向上 / 向下两行（照原型）：「向上 U  买入 x · 空单爆仓 y」「向下 D  卖出 x · 多单爆仓 y」，为 0 的那一项不写 */
export function udRowsHtml(d: { bb: number; bs: number } | null, l: BarLiq | null): string {
  const u = udOf(d, l)
  // 拆分：两项都有写「卖出 X · 多单爆仓 Y」；只有一项时整数就是它，只写来源名（「多单爆仓」）不再重复金额；都没有不写
  const parts = (a: [string, number], b: [string, number]): string => {
    const on = [a, b].filter(([, v]) => v > 0)
    return on.length === 2 ? on.map(([k, v]) => `${k} ${amt(v)}`).join(' · ') : on.length === 1 ? on[0][0] : ''
  }
  return `<span>${BT.up}</span><b class="num up">${amt(u.up)}</b><em class="num">${parts([BT.buyShort, d?.bb ?? 0], [BT.shortLiq, l?.short ?? 0])}</em>` +
    `<span>${BT.down}</span><b class="num dn">${amt(u.down)}</b><em class="num">${parts([BT.sellShort, d?.bs ?? 0], [BT.longLiq, l?.long ?? 0])}</em>`
}

/** 图上气泡的悬停卡（抽屉「每根」同一套样子）：时间 · 周期、净额大字 + 对撞条；读数格顶上是向上 / 向下两行（大单与爆仓在这里拆开），
 *  往下大卖 / 大买（额 + 笔）、最大一笔、现货 / 合约、各家。这根只有爆仓没有大单（d = null）时只摆时间与那两行。
 *  这根有一分钟来自服务端历史（exact = false）时笔数 / 最大一笔 / 来源都没有：这几项直接不摆（不写「—」也不写说明）。
 *  liq 不传（undefined）= 这只没有爆仓项（现货、DXY）或秒级周期，不加那两行 */
export function hoverCardHtml(d: BarBig | null, when: string, iv: string, liq?: BarLiq | null): string {
  const head = `<div class="hc-h"><b class="num">${when}</b>· ${iv}</div>`
  const ud = liq !== undefined ? udRowsHtml(d, liq) : ''
  if (!d) return `<div class="hc">${head}<div class="hc-kv">${ud}</div></div>`
  const n = d.bb - d.bs, t = d.bb + d.bs || 1
  const mx = d.exact ? maxOf(d) : null
  const cnt = (k: number | null): string => k == null ? '' : fill(BT.count, { n: k })
  const tail = d.exact
    ? `<span>${BT.maxSingle}</span><b class="num">${mx ? amt(mx.usd) : '—'}</b><em class="${mx ? (mx.buy ? 'up' : 'dn') : ''}">${mx ? (mx.buy ? BT.buyShort : BT.sellShort) : ''}</em></div>` +
      `<div class="hc-src">${srcHtml(d.bb + d.bs, d.spot, d.ex)}</div>`
    : '</div>'
  return `<div class="hc">${head}` +
    `<div class="hc-net"><span class="v num ${tone(n)}">${signed(n)}</span><span class="l">${BT.net}</span></div>` +
    `<div class="hc-fly"><i class="s" style="flex:${(d.bs / t).toFixed(4)}"></i><i class="b" style="flex:${(d.bb / t).toFixed(4)}"></i></div>` +
    `<div class="hc-kv">${ud}<span>${BT.sellShort}</span><b class="num dn">${amt(d.bs)}</b><em class="num">${cnt(d.sn)}</em>` +
    `<span>${BT.buyShort}</span><b class="num up">${amt(d.bb)}</b><em class="num">${cnt(d.bn)}</em>` + tail + '</div>'
}

// ------------------------------------------------------------------ 价位：竖向价格轴

export interface AxIn { p: number; hh: number }
/** 按真实价把条目摆到竖轴上（价高在上），挤了互相让开：相邻两项至少隔 (h1 + h2) / 2 + gap；
 *  最下一项越过 h − pad 时整列往上推（反向再让一遍）。返回与入参同序的 y（中心线） */
export function placeAxis(items: readonly AxIn[], h: number, pad = 9, gap = 2): number[] {
  if (!items.length) return []
  const order = items.map((_, i) => i).sort((a, b) => items[b].p - items[a].p)
  let hi = -Infinity, lo = Infinity
  for (const it of items) { hi = Math.max(hi, it.p); lo = Math.min(lo, it.p) }
  if (!(hi - lo > hi * 1e-9)) { const d = Math.max(Math.abs(hi) * 0.001, 1e-9); hi += d; lo -= d }
  const span = Math.max(1, h - pad * 2)
  const y = order.map(i => pad + (hi - items[i].p) / (hi - lo) * span)
  const g = (a: number, b: number): number => (items[order[a]].hh + items[order[b]].hh) / 2 + gap
  for (let k = 1; k < y.length; k++) y[k] = Math.max(y[k], y[k - 1] + g(k - 1, k))
  const last = y.length - 1
  if (y[last] > h - pad) {
    y[last] = h - pad
    for (let k = last - 1; k >= 0; k--) y[k] = Math.min(y[k], y[k + 1] - g(k, k + 1))
  }
  const out = new Array<number>(items.length)
  order.forEach((i, k) => { out[i] = y[k] })
  return out
}

/** 挂了多久的小圆环：满一圈 = 1 小时 */
export function ring(cx: number, cy: number, r: number, frac: number, color: string): string {
  const a = Math.max(0.02, Math.min(0.999, frac)) * Math.PI * 2, x2 = cx + r * Math.sin(a), y2 = cy - r * Math.cos(a)
  return `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="var(--of-track)" stroke-width="2"/>` +
    `<path d="M${cx},${cy - r}A${r},${r} 0 ${a > Math.PI ? 1 : 0} 1 ${x2.toFixed(2)},${y2.toFixed(2)}" fill="none" stroke="${color}" stroke-width="2" stroke-linecap="round"/>`
}

export interface LvWall { price: number; usd: number; age: number }
export interface LvIn {
  w: number; h: number
  sell: readonly { price: number; usd: number }[]
  buy: readonly { price: number; usd: number }[]
  ask: LvWall | null; bid: LvWall | null
  cur: number | null
  fmt: (p: number) => string
  /** 一档条目都没有时现价线上方的一句（如「近1时无成交大单」） */
  note?: string
  /** 左侧价格列宽（按最宽的价格字量好传进来） */
  pxCol?: number
  /** 量字宽（11px 数字字体）；给了就在「N分」放不下时把它省掉 */
  tw?: (t: string) => number
}
/** 价位块整张 SVG；同时给出两道墙的命中区（点了让图挪过去） */
export function levelsSvg(o: LvIn): { svg: string; hits: { y0: number; y1: number; ask: boolean }[] } {
  const { w, h } = o
  type It = { k: 'wall' | 'lv' | 'cur'; s: 'a' | 'b' | 's'; p: number; hh: number; usd: number; age: number }
  const it: It[] = []
  if (o.ask) it.push({ k: 'wall', s: 'a', p: o.ask.price, hh: 16, usd: o.ask.usd, age: o.ask.age })
  for (const l of o.sell) it.push({ k: 'lv', s: 's', p: l.price, hh: 12, usd: l.usd, age: 0 })
  if (o.cur != null) it.push({ k: 'cur', s: 's', p: o.cur, hh: 16, usd: 0, age: 0 })
  for (const l of o.buy) it.push({ k: 'lv', s: 'b', p: l.price, hh: 12, usd: l.usd, age: 0 })
  if (o.bid) it.push({ k: 'wall', s: 'b', p: o.bid.price, hh: 16, usd: o.bid.usd, age: o.bid.age })
  const ys = placeAxis(it, h)
  const PX = Math.max(40, Math.round(o.pxCol ?? 46)), bw = Math.max(10, w - PX - 36)
  const m = Math.max(1, ...it.filter(x => x.k === 'lv').map(x => x.usd))
  const hits: { y0: number; y1: number; ask: boolean }[] = []
  let g = `<line x1="${PX - 1}" x2="${PX - 1}" y1="2" y2="${h - 2}" stroke="var(--line)"/>`
  it.forEach((x, i) => {
    const y = ys[i], ty = (y + 4).toFixed(1), yt = (y - 8).toFixed(1)
    if (x.k === 'wall') {
      hits.push({ y0: y - 9, y1: y + 9, ask: x.s === 'a' })
      const word = x.s === 'a' ? BT.sellWall : BT.buyWall, ago = `${Math.max(1, Math.round(x.age / MIN))}分`
      // 窄卡（1366 下价位卡只有 160）：先省「N分」只留圆环，再把金额收短，再省「卖墙 / 买墙」两字（墙在现价上 / 下自明）——字不许压到圆环底下
      const room = w - 15 - PX - 9
      const labs = [`${word} ${amt(x.usd)}`, `${word} ${amtTight(x.usd)}`, amt(x.usd), amtTight(x.usd)]
      const lab = !o.tw ? labs[0] : labs.find(t => o.tw!(t) + 2 <= room) ?? labs[3]
      const fits = !o.tw || PX + 9 + o.tw(lab) + 6 <= w - 18 - o.tw(ago)
      g += `<g class="wall" data-wall="${x.s}"><rect x="${PX}" y="${yt}" width="${w - PX}" height="16" rx="5" fill="var(--of-wall-a)"/>` +
        `<rect x="${PX}" y="${yt}" width="2.5" height="16" rx="1" fill="var(--of-wall)"/>` +
        `<text x="${PX - 6}" y="${ty}" text-anchor="end" class="num b1">${o.fmt(x.p)}</text>` +
        `<text x="${PX + 9}" y="${ty}" class="num b1">${lab}</text>` +
        (fits ? `<text x="${w - 18}" y="${ty}" text-anchor="end" class="num t3">${ago}</text>` : '') +
        ring(w - 7.5, +y.toFixed(1), 5, x.age / HOUR, 'var(--of-wall)') + '</g>'
    } else if (x.k === 'lv') {
      const c = x.s === 's' ? 'var(--down)' : 'var(--up)', r = x.usd / m, len = Math.max(8, r * bw), id = `ofdr-lv${i}`
      g += `<defs><linearGradient id="${id}" x1="0" x2="1"><stop offset="0" stop-color="${c}" stop-opacity="${(0.22 + 0.3 * r).toFixed(2)}"/><stop offset="1" stop-color="${c}" stop-opacity="${(0.55 + 0.45 * r).toFixed(2)}"/></linearGradient></defs>` +
        `<rect x="${PX}" y="${(y - 5).toFixed(1)}" width="${bw}" height="10" rx="3" fill="var(--of-track)" opacity=".6"/>` +
        `<rect x="${PX}" y="${(y - 5).toFixed(1)}" width="${len.toFixed(1)}" height="10" rx="3" fill="url(#${id})"/>` +
        `<text x="${PX - 6}" y="${ty}" text-anchor="end" class="num t2">${o.fmt(x.p)}</text>` +
        `<text x="${w}" y="${ty}" text-anchor="end" class="num b ${x.s === 's' ? 'dn' : 'up'}">${amt(x.usd)}</text>`
    } else {
      g += `<line x1="${PX}" x2="${w}" y1="${y.toFixed(1)}" y2="${y.toFixed(1)}" stroke="var(--text-1)" stroke-dasharray="3 3" opacity=".5"/>` +
        `<rect x="0" y="${yt}" width="${PX - 3}" height="16" rx="4" fill="var(--text-1)"/>` +
        `<text x="${(PX - 3) / 2}" y="${ty}" text-anchor="middle" class="num inv">${o.fmt(x.p)}</text>`
      if (o.note) g += `<text x="${PX + (w - PX) / 2}" y="${(y - 16).toFixed(1)}" text-anchor="middle" class="t3">${o.note}</text>`
    }
  })
  return { svg: svgWrap(w, h, g), hits }
}

export const svgWrap = (w: number, h: number, inner: string): string =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" aria-hidden="true">${inner}</svg>`

// ------------------------------------------------------------------ 时间分桶

/** 今天（from 起到 now）按 bucket 分的桶数（含正在走的那一桶） */
export const bucketCount = (from: number, now: number, bucket: number): number => Math.max(1, Math.floor((now - from) / bucket) + 1)

/** 柱子按宽度挑一个桶长：从 cands 里取第一个 ≥ floor 且每柱至少 minPx 宽的 */
export function pickBucket(from: number, now: number, w: number, cands: readonly number[], minPx = 3, floor = 0): number {
  for (const b of cands) if (b >= floor && bucketCount(from, now, b) * minPx <= w) return b
  return cands[cands.length - 1]
}
export const LIQ_BUCKETS = [15 * MIN, 30 * MIN, HOUR, 2 * HOUR] as const
export const NET_BUCKETS = [MIN, 5 * MIN, 15 * MIN, 30 * MIN, HOUR, 2 * HOUR, 4 * HOUR] as const

export interface LiqBucket { t: number; long: number; short: number }
/** 今天的爆仓按桶合计：long = 多头被平（往下、跌色），short = 空头被平（往上、涨色） */
export function liqBuckets(rows: Iterable<LiqRow>, from: number, now: number, bucket: number): LiqBucket[] {
  const n = bucketCount(from, now, bucket)
  const out: LiqBucket[] = Array.from({ length: n }, (_, i) => ({ t: from + i * bucket, long: 0, short: 0 }))
  for (const r of rows) {
    if (r[0] < from || r[0] > now) continue
    const i = Math.floor((r[0] - from) / bucket)
    if (i < 0 || i >= n) continue
    out[i].long += r[1]; out[i].short += r[2]
  }
  return out
}

export interface LiqSvgIn { w: number; h: number; q: readonly LiqBucket[]; hourFrom: number; tall: boolean; startLabel: string }
/** 爆仓镜像柱：上涨色 = 空头被平、下跌色 = 多头被平，开方比例；近 1 小时那段打底 */
export function liqSvg({ w, h, q, hourFrom, tall, startLabel }: LiqSvgIn): string {
  const LAB = 13, mid = Math.round((h - LAB) / 2) + 0.5
  const m = Math.sqrt(Math.max(1, ...q.map(b => Math.max(b.long, b.short))))
  const bw = w / Math.max(1, q.length)
  const i0 = Math.max(0, q.findIndex(b => b.t + (q.length > 1 ? q[1].t - q[0].t : 0) > hourFrom))
  let g = `<rect x="${(i0 * bw).toFixed(1)}" y="0" width="${(w - i0 * bw).toFixed(1)}" height="${h - LAB}" rx="4" fill="var(--surface-3)" opacity=".7"/>`
  g += `<line x1="0" x2="${w}" y1="${mid}" y2="${mid}" stroke="var(--line-strong)"/>`
  q.forEach((b, i) => {
    const x = (i * bw + 0.6).toFixed(1), ww = Math.max(1.5, bw - 1.6).toFixed(1)
    if (b.short > 0) { const r = Math.sqrt(b.short) / m, hh = Math.max(1.5, r * (mid - 2)); g += `<rect x="${x}" y="${(mid - 1 - hh).toFixed(1)}" width="${ww}" height="${hh.toFixed(1)}" rx="1.2" fill="var(--up)" opacity="${(0.45 + 0.55 * r).toFixed(2)}"/>` }
    if (b.long > 0) { const r = Math.sqrt(b.long) / m, hh = Math.max(1.5, r * (mid - 2)); g += `<rect x="${x}" y="${(mid + 1).toFixed(1)}" width="${ww}" height="${hh.toFixed(1)}" rx="1.2" fill="var(--down)" opacity="${(0.45 + 0.55 * r).toFixed(2)}"/>` }
  })
  g += `<text x="0" y="${h - 1}" class="num t3">${startLabel}</text><text x="${w}" y="${h - 1}" text-anchor="end" class="t3">${BT.now}</text>`
  if (tall && i0 * bw > 70) g += `<text x="${(i0 * bw - 4).toFixed(1)}" y="${h - 1}" text-anchor="end" class="t3">${BT.hour} ▸</text>`
  return svgWrap(w, h, g)
}

// ------------------------------------------------------------------ 今日累计净额

/** 逐桶净额 → 累计净额点位：x 均分在 [0, w − 4]，y 在 [top, top + ah]，零线也算进上下界 */
export function cumPoints(nets: readonly number[], w: number, top: number, ah: number): { pts: [number, number][]; zero: number; min: number; max: number; last: number } {
  let acc = 0
  const vals = nets.map(v => (acc += v))
  const mn = Math.min(0, ...vals), mx = Math.max(0, ...vals)
  const span = mx - mn || 1
  const y = (v: number): number => top + (mx - v) / span * ah
  const n = vals.length
  const pts = vals.map((v, i): [number, number] => [n > 1 ? i / (n - 1) * (w - 4) : (w - 4), y(v)])
  return { pts, zero: y(0), min: mn, max: mx, last: n ? vals[n - 1] : 0 }
}

export interface CumIn { w: number; h: number; nets: readonly number[]; tall: boolean; ticks?: readonly { i: number; label: string }[]; startLabel?: string; empty?: boolean }
/** 今日累计净额面积（零线上涨色、下跌色）+ 末端一点；tall 时下面再加一排逐桶净额柱与整点刻度 */
export function cumSvg({ w, h, nets, tall, ticks = [], startLabel = '8:00', empty }: CumIn): string {
  if (empty || !nets.length) return svgWrap(w, h, `<line x1="0" x2="${w}" y1="${h / 2}" y2="${h / 2}" stroke="var(--line-strong)" stroke-dasharray="2 3"/>`)
  const padT = tall ? 18 : 4, colH = tall ? Math.min(84, h * 0.34) : 0
  const ah = Math.max(8, tall ? h - padT - 10 - 16 - colH - 16 : h - padT - 2)
  const c = cumPoints(nets, w, padT, ah)
  const line = c.pts.map(([x, y], i) => `${i ? 'L' : 'M'}${x.toFixed(1)},${y.toFixed(1)}`).join('')
  const lx = c.pts[c.pts.length - 1][0], ly = c.pts[c.pts.length - 1][1]
  const z = c.zero.toFixed(1)
  const area = `${line}L${lx.toFixed(1)},${z}L0,${z}Z`
  const id = `ofdr-cum${tall ? 't' : 's'}`
  let g = `<defs><linearGradient id="${id}u" x1="0" y1="${padT}" x2="0" y2="${z}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="var(--up)" stop-opacity=".38"/><stop offset="1" stop-color="var(--up)" stop-opacity=".02"/></linearGradient>` +
    `<linearGradient id="${id}d" x1="0" y1="${z}" x2="0" y2="${(padT + ah).toFixed(1)}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="var(--down)" stop-opacity=".02"/><stop offset="1" stop-color="var(--down)" stop-opacity=".34"/></linearGradient>` +
    `<clipPath id="${id}a"><rect x="-2" y="-10" width="${w + 4}" height="${(c.zero + 10).toFixed(1)}"/></clipPath>` +
    `<clipPath id="${id}b"><rect x="-2" y="${z}" width="${w + 4}" height="${h}"/></clipPath></defs>`
  g += `<line x1="0" x2="${w}" y1="${z}" y2="${z}" stroke="var(--line-strong)" stroke-dasharray="2 3"/>`
  g += `<path d="${area}" fill="url(#${id}u)" clip-path="url(#${id}a)"/><path d="${area}" fill="url(#${id}d)" clip-path="url(#${id}b)"/>`
  g += `<path d="${line}" fill="none" stroke="var(--up)" stroke-width="1.6" stroke-linejoin="round" clip-path="url(#${id}a)"/>` +
    `<path d="${line}" fill="none" stroke="var(--down)" stroke-width="1.6" stroke-linejoin="round" clip-path="url(#${id}b)"/>`
  const ec = c.last >= 0 ? 'var(--up)' : 'var(--down)'
  g += `<circle cx="${lx.toFixed(1)}" cy="${ly.toFixed(1)}" r="5" fill="${ec}" opacity=".18"/><circle cx="${lx.toFixed(1)}" cy="${ly.toFixed(1)}" r="2.6" fill="${ec}" stroke="var(--surface)" stroke-width="1"/>`
  if (tall) {
    g += `<text x="0" y="10" class="t3">${fill(BT.cumNet, { t: startLabel })}</text>`
    if (c.min < 0) g += `<text x="${w}" y="${(padT + ah + 12).toFixed(1)}" text-anchor="end" class="num t3">${signed(c.min)}</text>`
    const by = padT + ah + 10 + 16, mid = by + colH / 2
    const mm = Math.max(1, ...nets.map(Math.abs)), bw = (w - 4) / nets.length
    g += `<text x="0" y="${(by - 4).toFixed(1)}" class="t3">${BT.barNet}</text><line x1="0" x2="${w}" y1="${mid.toFixed(1)}" y2="${mid.toFixed(1)}" stroke="var(--line)"/>`
    nets.forEach((v, i) => {
      if (!v) return
      const hh = Math.max(1.5, Math.abs(v) / mm * (colH / 2 - 2))
      g += `<rect x="${(i * bw + 0.5).toFixed(1)}" y="${(v > 0 ? mid - hh : mid).toFixed(1)}" width="${Math.max(1.5, bw - 1.2).toFixed(1)}" height="${hh.toFixed(1)}" rx="1" fill="${v > 0 ? 'var(--up)' : 'var(--down)'}" opacity="${(0.45 + 0.55 * Math.abs(v) / mm).toFixed(2)}"/>`
    })
    for (const t of ticks) g += `<text x="${(t.i * bw).toFixed(1)}" y="${(by + colH + 13).toFixed(1)}" text-anchor="${t.i === 0 ? 'start' : 'middle'}" class="num t3">${t.label}</text>`
  }
  return svgWrap(w, h, g)
}

/** 整点刻度：从 from 起每 k 小时一个（k 取使相邻刻度至少隔 minPx 的最小档），给出所在桶的下标；hourOf 把时间换成北京时间的小时 */
export function hourTicks(from: number, now: number, bucket: number, w: number, hourOf: (t: number) => number, minPx = 44): { i: number; label: string }[] {
  const n = bucketCount(from, now, bucket), bw = (w - 4) / n
  const k = [1, 2, 3, 4, 6, 12].find(s => s * HOUR / bucket * bw >= minPx) ?? 24
  const out: { i: number; label: string }[] = []
  for (let t = from; t <= now; t += k * HOUR) {
    const i = Math.floor((t - from) / bucket)
    if (i > 0 && i * bw > w - 22) break
    out.push({ i, label: `${hourOf(t)}:00` })
  }
  return out
}
