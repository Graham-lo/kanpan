/* 手机网页版 · 行情页的纯函数（不碰 DOM，tests/m-chartpage.test.ts 逐条测）
 *
 * 口径逐条照 iOS：
 *   头部          Main/HeaderStats.swift（六格、估值、倍数写法）、Main/MainScreenParts.swift（涨跌行）
 *   结算倒计时    Main/FundingBook.swift（过点往后滚 8 小时、≥ 32 小时不写）
 *   扫图          Main/ScanList.swift + MainScreenParts 的横滑判定
 *   周期条        Settings/Model/Prefs.swift 的 toggleQuick / replaceQuick
 *   指标开关      Panels/IndicatorPanel.swift + Prefs.toggle / moveSub（副图最多三个，成交量不占名额）
 *   参数          IndicatorParamRule（1…400，最多 3 位数字）
 *   订单流门槛    OrderFlow/OrderFlowEditor.swift 的 sanitize / clamp / override / plain / compact
 *   订单流详情卡  Main/OrderFlowDetailCard.swift 的 OrderFlowCardText
 *   十字线读数    Main/CrosshairReadout.swift 的 crosshairOHLCText
 */
import { MINUS, MISSING, fmtPrice, fmtVol, grouped, toFixed, changePercentText } from '../../model/rowText'
import { MAX_QUICK, MAX_SUBS, type IntervalId, type IndicatorId, type OrderFlowOverride } from '../../app/prefs'
import { THRESHOLD_RANGE, STEP_RANGE } from '../../../orderflow/settings'

export { MAX_QUICK, MAX_SUBS, THRESHOLD_RANGE, STEP_RANGE }

// ───────────────────────────── 头部

/** 涨跌额 + 涨跌幅：「+1,234.5  +1.23%」；涨跌额按品种位数、千分位，负号 U+2212 */
export function priceChangeText(change: number | null | undefined, pct: number | null | undefined, dec: number): string {
  if (change == null || !Number.isFinite(change)) return MISSING
  const mag = toFixed(Math.abs(change), dec)
  const neg = change < 0 && /[1-9]/.test(mag)
  return (neg ? MINUS : '+') + grouped(mag) + '  ' + changePercentText(pct)
}

/** 倍数：<10 两位、<100 一位、再大取整 */
export function ratioText(x: number): string {
  return toFixed(x, x < 10 ? 2 : x < 100 ? 1 : 0)
}

const positive = (x: number | null | undefined): number | null => x != null && Number.isFinite(x) && x > 0 ? x : null

/** 仓：持仓量（美元）>0 才写 */
export function openInterestText(oi: number | null | undefined): string {
  const v = positive(oi)
  return v == null ? MISSING : fmtVol(v)
}
/** 额：行情新鲜且 >0 */
export function turnoverText(vol: number | null | undefined, fresh: boolean): string {
  const v = positive(vol)
  return fresh && v != null ? fmtVol(v) : MISSING
}
/** 市值：总供应量 × 现价（新鲜时） */
export function marketCapValue(supply: number | null | undefined, price: number | null | undefined): number | null {
  const s = positive(supply), p = positive(price)
  return s != null && p != null ? s * p : null
}
export function marketCapText(supply: number | null | undefined, price: number | null | undefined, fresh: boolean): string {
  const c = marketCapValue(supply, price)
  return fresh && c != null ? fmtVol(c) : MISSING
}

export type AssetKind = 'crypto' | 'us' | 'com'
/** 估值那一格：加密 O/M、美股 FPE（预期亏损的给 P/S）、其它类别不摆（返回 null） */
export function valuationCell(kind: AssetKind, o: {
  oi?: number | null; supply?: number | null; price?: number | null; forwardEarnings?: number | null; revenue?: number | null
}): { label: string; value: string | null } | null {
  const cap = marketCapValue(o.supply, o.price)
  if (kind === 'crypto') {
    const oi = positive(o.oi)
    return { label: 'O/M', value: oi != null && cap != null ? ratioText(oi / cap * 100) + '%' : null }
  }
  if (kind === 'us') {
    const e = positive(o.forwardEarnings)
    if (e != null) return { label: 'FPE', value: cap != null ? ratioText(cap / e) : null }
    const r = positive(o.revenue)
    if (r != null) return { label: 'P/S', value: cap != null ? ratioText(cap / r) : null }
    return { label: 'FPE', value: null }
  }
  return null
}

/** 费率：「+0.0100%」；新鲜才写；返回方向用来上色 */
export function fundingText(rate: number | null | undefined, fresh: boolean): { text: string; dir: 1 | -1 | 0 } {
  if (!fresh || rate == null || !Number.isFinite(rate)) return { text: MISSING, dir: 0 }
  const body = toFixed(rate * 100, 4)
  const zero = !/[1-9]/.test(body)
  if (zero) return { text: toFixed(0, 4) + '%', dir: 0 }
  return rate > 0 ? { text: '+' + body + '%', dir: 1 } : { text: MINUS + body.replace('-', '') + '%', dir: -1 }
}

const EIGHT_HOURS = 8 * 3_600_000
/** 结算倒计时：已过点按 8 小时往后滚；剩 ≥ 32 小时不写；「<1分」「X时Y分」「Y分」 */
export function fundingCountdownText(nextFunding: number | null | undefined, now: number): string | null {
  if (nextFunding == null || !Number.isFinite(nextFunding) || nextFunding <= 0) return null
  let t = nextFunding
  if (t <= now) t += Math.ceil((now - t + 1) / EIGHT_HOURS) * EIGHT_HOURS
  const left = t - now
  if (left >= 32 * 3_600_000) return null
  const mins = Math.floor(left / 60_000)
  if (mins < 1) return '<1分'
  const h = Math.floor(mins / 60), m = mins % 60
  return h > 0 ? `${h}时${m}分` : `${m}分`
}

/** 行情是不是停住了：全局停住标、全市场表断了、或这只 60 秒没有新价 */
export function isStale(o: { flag: boolean; live: boolean | null | undefined; lastTick?: number | null; now: number }): boolean {
  if (o.flag || o.live === false) return true
  return o.lastTick != null && o.lastTick > 0 && o.now - o.lastTick > 60_000
}

// ───────────────────────────── 扫图

/** 价格区的横滑：|dx| > 44 且比竖向大 1.5 倍才算；左滑下一只、右滑上一只；到头不循环 */
export function swipeTarget(list: readonly string[], current: string, dx: number, dy: number): string | null {
  if (Math.abs(dx) <= 44 || Math.abs(dx) <= Math.abs(dy) * 1.5) return null
  const i = list.indexOf(current)
  if (i < 0) return null
  const j = dx < 0 ? i + 1 : i - 1
  return j >= 0 && j < list.length ? list[j] : null
}

// ───────────────────────────── 周期条

/** 按周期全表的顺序排 */
export function sortIntervals(list: readonly IntervalId[], order: readonly IntervalId[]): IntervalId[] {
  return [...new Set(list)].filter(x => order.includes(x)).sort((a, b) => order.indexOf(a) - order.indexOf(b))
}
/** 钉 / 取消钉：至少留一档、最多六档；返回新表或拒绝原因 */
export function toggleQuick(quick: readonly IntervalId[], iv: IntervalId, order: readonly IntervalId[]):
  { list: IntervalId[] } | { refused: string } {
  if (quick.includes(iv)) {
    if (quick.length <= 1) return { refused: '常用行至少留一档' }
    return { list: sortIntervals(quick.filter(x => x !== iv), order) }
  }
  if (quick.length >= MAX_QUICK) return { refused: '常用行最多 6 档' }
  return { list: sortIntervals([...quick, iv], order) }
}
/** 钉满时换一档：old 换成 add */
export function replaceQuick(quick: readonly IntervalId[], old: IntervalId, add: IntervalId, order: readonly IntervalId[]): IntervalId[] {
  if (!quick.includes(old) || quick.includes(add)) return [...quick]
  return sortIntervals(quick.map(x => (x === old ? add : x)), order)
}

// ───────────────────────────── 指标

/** 主图叠加开关 */
export function toggleOverlay(list: readonly IndicatorId[], id: IndicatorId): IndicatorId[] {
  return list.includes(id) ? list.filter(x => x !== id) : [...list, id]
}
/** 副图开关：成交量不占名额；开第四个时换下最早开的那个（返回被换下的） */
export function toggleSub(list: readonly IndicatorId[], id: IndicatorId): { list: IndicatorId[]; dropped: IndicatorId | null } {
  if (list.includes(id)) return { list: list.filter(x => x !== id), dropped: null }
  const next = [...list, id]
  if (id === 'VOL') return { list: next, dropped: null }
  const counted = next.filter(x => x !== 'VOL')
  if (counted.length <= MAX_SUBS) return { list: next, dropped: null }
  const drop = counted[0]
  return { list: next.filter(x => x !== drop), dropped: drop }
}
/** 副图换序（from / to 是在 list 里的下标） */
export function moveSub(list: readonly IndicatorId[], from: number, to: number): IndicatorId[] {
  const out = [...list]
  if (from < 0 || from >= out.length) return out
  const [x] = out.splice(from, 1)
  out.splice(Math.max(0, Math.min(out.length, to)), 0, x)
  return out
}

/** 参数框：只收数字、最多 3 位 */
export function sanitizeParam(raw: string): string {
  return toHalfWidth(raw).replace(/[^0-9]/g, '').slice(0, 3)
}
/** 参数值夹到 1…400；空 / 非数返回 null */
export function clampParam(raw: string): number | null {
  const s = sanitizeParam(raw)
  if (!s) return null
  return Math.min(400, Math.max(1, parseInt(s, 10)))
}
/** 周期数量可变的三把（均线、指数均线、成交量），最多 20 个 */
export const VARIABLE_PARAMS: readonly IndicatorId[] = ['MA', 'EMA', 'VOL']
export const MAX_VARIABLE_PARAMS = 20

// ───────────────────────────── 订单流门槛（OrderFlowEditor）


function toHalfWidth(s: string): string {
  let out = ''
  for (const ch of s) {
    const c = ch.codePointAt(0)!
    if (c >= 0xff10 && c <= 0xff19) out += String.fromCharCode(c - 0xff10 + 0x30)
    else if (c === 0xff0e || c === 0x3002) out += '.'
    else out += ch
  }
  return out
}

/** 框里的数：整数不带小数点，小数去掉尾零 */
export function plainNumber(v: number): string {
  if (v >= 1 && v === Math.round(v)) return String(Math.trunc(v))
  let s = v.toFixed(8)
  s = s.replace(/0+$/, '').replace(/\.$/, '')
  return s
}

/** 金额 / 步长框：全角转半角；只留数字与一个小数点（至多 14 位）；万 / 亿 / k / m / b 展开；科学计数整串认 */
export function sanitizeAmount(raw: string): string {
  const trimmed = raw.trim()
  if (/[eE]/.test(trimmed) && /^[0-9.eE+-]+$/.test(trimmed)) {
    const v = Number(trimmed)
    if (Number.isFinite(v) && v > 0 && v < 1e14) return plainNumber(v)
  }
  const UNIT: Record<string, number> = { '万': 1e4, '亿': 1e8, k: 1e3, K: 1e3, m: 1e6, M: 1e6, b: 1e9, B: 1e9 }
  let digits = '', dot = false, scale = 1
  for (const c of toHalfWidth(raw)) {
    if (c >= '0' && c <= '9') {
      if (scale !== 1 || digits.replace('.', '').length >= 14) continue
      digits += c
    } else if (c === '.') {
      if (dot || scale !== 1 || digits.replace('.', '').length >= 14) continue
      dot = true; digits += c
    } else if (scale === 1 && /[0-9]/.test(digits) && UNIT[c]) {
      scale = UNIT[c]
    }
  }
  if (scale === 1) return digits
  const v = Number(digits)
  if (!Number.isFinite(v)) return digits
  const scaled = v * scale
  return Number.isFinite(scaled) && scaled < 1e14 ? plainNumber(scaled) : digits
}

export type OrderFlowField = 'spot' | 'usdtPerp' | 'coinPerp' | 'delivery' | 'step'
export function clampAmount(v: number, field: OrderFlowField): number {
  const [lo, hi] = field === 'step' ? STEP_RANGE : THRESHOLD_RANGE
  return Math.min(hi, Math.max(lo, v))
}
/** 保存时写进改动表的那一份：在原来那份上改打过的格；和默认一样的格拿掉（默认还没到时一格都不拿） */
export function mergeOverride(defaults: Partial<Record<OrderFlowField, number>> | null | undefined,
  existing: OrderFlowOverride | null | undefined, edited: Partial<Record<OrderFlowField, number>>): OrderFlowOverride {
  const out: OrderFlowOverride = { ...(existing ?? {}) }
  for (const k of Object.keys(edited) as OrderFlowField[]) {
    const v = edited[k]!
    if (defaults && defaults[k] === v) delete out[k]
    else out[k] = v
  }
  return out
}
/** K / M / B 读法（「5M」「2.5K」） */
export function compactAmount(v: number): string {
  const f = (x: number, u: string): string => (x === Math.round(x) ? String(Math.trunc(x)) : x.toFixed(2).replace(/\.?0+$/, '')) + u
  if (v >= 1e9) return f(v / 1e9, 'B')
  if (v >= 1e6) return f(v / 1e6, 'M')
  if (v >= 1e3) return f(v / 1e3, 'K')
  return plainNumber(v)
}

// ───────────────────────────── 订单流详情卡（OrderFlowCardText）

/** 卡片要的那一堵墙（OrderFlowGroup 的子集，测试好造） */
export interface CardGroup {
  side: 'bid' | 'ask'
  contract: boolean
  isRange: boolean
  price: number
  priceLow: number
  priceHigh: number
  step: number | null
  notional: number
  books: readonly { latest: { price: number; notional: number } }[]
  hasFill: boolean
  isLive: boolean
  fillRatio: number
  firstSeenMs: number
  endMs: number | null
}
export type CardState = 'live' | 'filled' | 'cancelled'
export interface CardText {
  price: string
  sideTitle: string
  kind: string
  duration: string
  durationShort: string
  durationCompact: string
  pairs: [{ label: string; value: string }, { label: string; value: string }][]
  compactPair: [{ label: string; value: string }, { label: string; value: string }]
  statusText: string
  statusTight: string
  state: CardState
}

export function stepDecimals(step: number): number {
  if (!Number.isFinite(step) || step <= 0) return 0
  for (let d = 0; d <= 8; d++) {
    const s = step * 10 ** d
    if (Math.abs(s - Math.round(s)) <= 1e-9 * Math.max(1, s)) return d
  }
  return 8
}
export function percent(ratio: number): string {
  const v = ratio * 100
  return (v >= 10 ? toFixed(v, 0) : toFixed(v, 1)) + '%'
}
export function fillSplit(ratio: number): { filled: string; cancelled: string } | null {
  const v = Math.min(100, Math.max(0, ratio * 100))
  if (v >= 1) {
    const f = Math.round(v)
    return f >= 100 ? null : { filled: `${f}%`, cancelled: `${100 - f}%` }
  }
  const tenths = Math.max(1, Math.round(v * 10))
  return { filled: toFixed(tenths / 10, 1) + '%', cancelled: toFixed((1000 - tenths) / 10, 1) + '%' }
}
export function cardStatus(g: Pick<CardGroup, 'isLive' | 'hasFill' | 'fillRatio'>): { text: string; state: CardState } {
  if (g.isLive) return { text: g.hasFill ? '在场 · 成交 ' + percent(g.fillRatio) : '在场', state: 'live' }
  if (!g.hasFill) return { text: '已撤', state: 'cancelled' }
  const s = fillSplit(g.fillRatio)
  return s ? { text: `成交 ${s.filled} · 撤 ${s.cancelled}`, state: 'filled' } : { text: '已成交', state: 'filled' }
}
export function durationText(ms: number): string {
  const minutes = Math.floor(Math.max(0, ms) / 60_000)
  if (minutes < 1) return '不到 1 分'
  const days = Math.floor(minutes / 1440), hours = Math.floor((minutes % 1440) / 60), mins = minutes % 60
  if (days > 0) return `${days} 天 ${hours} 小时`
  if (hours > 0) return `${hours} 小时 ${mins} 分`
  return `${mins} 分`
}
export function quantityText(q: number): string {
  if (!Number.isFinite(q)) return '--'
  if (Math.abs(q) >= 1000) return fmtVol(q)
  return toFixed(q, Math.abs(q) >= 1 || q === 0 ? 2 : 4)
}
const pad2 = (n: number): string => (n < 10 ? '0' + n : String(n))
/** 「09-24 02:38」（上海时间） */
export function monthDayTime(ms: number, offsetMin = 480): string {
  const d = new Date(ms + offsetMin * 60_000)
  return `${pad2(d.getUTCMonth() + 1)}-${pad2(d.getUTCDate())} ${pad2(d.getUTCHours())}:${pad2(d.getUTCMinutes())}`
}
export function cardText(g: CardGroup, base: string, dec: number, nowMs: number): CardText {
  const bd = Math.min(dec, g.step != null ? stepDecimals(g.step) : dec)
  const price = g.isRange
    ? grouped(fmtPrice(g.priceLow, bd)) + ' – ' + grouped(fmtPrice(g.priceHigh, bd))
    : grouped(fmtPrice(g.price, dec))
  const short = durationText((g.endMs ?? nowMs) - g.firstSeenMs)
  const qty = g.books.reduce((s, b) => {
    const p = b.latest.price
    return s + (p > 0 ? b.latest.notional / p : 0)
  }, 0)
  const st = cardStatus(g)
  const amount = { label: '总金额', value: fmtVol(g.notional) + ' USDT' }
  const status = { label: '状态', value: st.text }
  return {
    price,
    sideTitle: g.side === 'bid' ? '委托买单' : '委托卖单',
    kind: g.contract ? '合约' : '现货',
    duration: '持续 ' + short,
    durationShort: short,
    durationCompact: short.replace(/ /g, '').replace('小时', '时'),
    pairs: [
      [amount, { label: '总数量', value: quantityText(qty) + ' ' + base }],
      [{ label: '开始', value: monthDayTime(g.firstSeenMs) }, status],
    ],
    compactPair: [amount, status],
    statusText: st.text,
    statusTight: st.text.replace(/ · /g, '·').replace(/ /g, ''),
    state: st.state,
  }
}

// ───────────────────────────── 十字线读数

export interface OHLC { t: number; o: number; h: number; l: number; c: number; v: number }
/** 「2026-09-30 14:00  量 V\n开 X  高 X\n低 X  收 X」（时间上海） */
export function crosshairOHLC(b: OHLC, dec: number, fmtTime: (ms: number) => string): string {
  // 量跟在时间后面：三行里最短的是时间那行，放在「低 收」后面会顶进右侧六格
  return fmtTime(b.t) + '  量 ' + fmtVol(b.v)
    + '\n开 ' + fmtPrice(b.o, dec) + '  高 ' + fmtPrice(b.h, dec)
    + '\n低 ' + fmtPrice(b.l, dec) + '  收 ' + fmtPrice(b.c, dec)
}

// ───────────────────────────── 画线台

/** 横屏左侧周期栏：钉住的档 + 当前档（没钉住时插在它该在的位置） */
export function railIntervals(quick: readonly IntervalId[], current: IntervalId, order: readonly IntervalId[]): IntervalId[] {
  return sortIntervals(quick.includes(current) ? quick : [...quick, current], order)
}

// ───────────────────────────── 个性化学习

const METALS = new Set(['XAU', 'XAG', 'XPT', 'XPD'])
/** 品种的习惯类别（HabitCategory） */
export function habitCategory(kind: string | undefined, base: string): 'crypto' | 'equity' | 'metal' | 'index' | 'other' {
  if (!kind || kind === 'crypto') return 'crypto'
  if (kind === 'us') return 'equity'
  return METALS.has(base) ? 'metal' : 'other'
}

/** 算不算横屏（画线台）：视口够扁（媒体查询）且设备自己也是横着的。
 *  安卓竖着拿弹出键盘时视口会宽 > 高，但 screen.orientation 仍是 portrait-*；拿不到朝向时只看视口 */
export function isLandscape(viewportLandscape: boolean, orientationType: string | undefined | null): boolean {
  return viewportLandscape && (!orientationType || orientationType.startsWith('landscape'))
}
