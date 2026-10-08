/* Hkline Web · 第三批副图指标（网页版大屏专有，照 TradingView 内置指标补齐）
 *
 * 只从 calc.ts 拿类型，运行时不反向依赖它（calc.ts 把这里的表并进 Calc / CATALOG），
 * 所以均线、滑窗求和、滑窗最值、标准差等小工具在这里各留一份实现。
 *
 * 口径一律照 TradingView 内置指标的公开 Pine 源码：
 * - 均线：sma 要整窗都有值；ema / rma 用头 n 个连续有值的 SMA 做种子（同 Pine 的 ta.ema / ta.rma）；
 *   wma 线性加权；中途遇到空值时 ema / rma 这一根出空、递推状态保留（Pine 会被 nz 归零，那是它的毛病，不照抄）。
 * - 「变化量」类（ta.change、前一根收盘）第 0 根没有值，所以依赖它的指标比窗口长度再晚一根才出值，和 TV 一样。
 * - 标准差是总体标准差（除以 n，同 ta.stdev 默认）。
 * - 成交量：TV 用的是基础币成交量；这里取 bar.bv，没有就拿成交额 / 收盘价折成币数（同 vwapWeight）。
 *   比值类指标（MFI、CMF、成交量震荡）不受单位影响；累计类（A/D、PVT、克林格、强力指数）的量级是「币」。
 * - 分母为 0 的退化情形（一整窗高低相同等）：有中性值的取中性值（随机指标 50、%B 0.5、钱德 0…），
 *   没有中性值的（波动指数、涡旋）出空，不拿 0 糊弄。
 * - 前面不够窗口的根一律 null。所有计算 O(n)（滑窗求和、单调队列求最值、EMA 递推），康纳 RSI 的百分位排名 O(n log n)。
 */
import type { Bar, Series, IndParams, CatalogEntry, CalcEnv } from './calc'
import { sharedName, sharedParams } from './sharedIndicators'

export type OscId =
  | 'stoch' | 'dmi' | 'mfi' | 'aroon' | 'cmf' | 'chosc' | 'ao' | 'ac' | 'mom' | 'roc'
  | 'trix' | 'dpo' | 'uo' | 'bbp' | 'efi' | 'chop' | 'coppock' | 'cmo' | 'vortex' | 'kst'
  | 'mass' | 'eom' | 'pvt' | 'bop' | 'hv' | 'stdev' | 'fisher' | 'rvgi' | 'rvi' | 'volosc'
  | 'klinger' | 'ad' | 'crsi' | 'tsi' | 'smi' | 'ppo' | 'bbw' | 'bbpct' | 'nv'
type Fn = (bars: Bar[], p: IndParams, env?: CalcEnv) => Series[]

/** 每条序列的画法：line 折线 / hist 零轴柱（正绿负红）/ histTrend 升降着色柱（比前一根高绿、低红）/
 *  hist4 四色柱（TV MACD 式：零轴上升、零轴上降、零轴下降、零轴下升）/ area 零轴填充 / dots 圆点 */
export type OscStyle = 'line' | 'hist' | 'histTrend' | 'hist4' | 'area' | 'dots'

// ------------------------------------------------------------ 小工具
const DAY = 864e5
const int = (v: number | undefined, d: number, min = 1): number => Math.max(min, Math.round(v && v > 0 ? v : d))
const nulls = (n: number): Series => new Array(n).fill(null)
/** 两条序列逐根运算，任一边没值就出空 */
function zip(a: Series, b: Series, f: (x: number, y: number) => number | null): Series {
  return a.map((x, i) => { const y = b[i]; return x == null || y == null ? null : f(x, y) })
}
/** 基础币成交量：bv 有就用它，没有拿成交额 / 收盘价折；坏值按 0 */
function vol(b: Bar): number {
  const w = b.bv != null && Number.isFinite(b.bv) ? b.bv : b.c > 0 ? b.v / b.c : 0
  return Number.isFinite(w) && w > 0 ? w : 0
}
const hl2 = (b: Bar): number => (b.h + b.l) / 2
const hlc3 = (b: Bar): number => (b.h + b.l + b.c) / 3
/** ta.change：第 0 根没有前一根，出空 */
function change(src: number[], k = 1): Series {
  return src.map((x, i) => i >= k ? x - src[i - k] : null)
}
/** 真实波幅；naFirst = true 时第 0 根出空（同 Pine 的 ta.tr），否则第 0 根取高 − 低（同 ta.tr(true) / ta.atr） */
function trueRange(bars: Bar[], naFirst: boolean): Series {
  return bars.map((b, i) => i === 0 ? (naFirst ? null : b.h - b.l) : Math.max(b.h - b.l, Math.abs(b.h - bars[i - 1].c), Math.abs(b.l - bars[i - 1].c)))
}

/** 滑窗求和：要整窗 n 根都有值；遇到空值从头数 */
function sum(src: Series, n: number): Series {
  const out = nulls(src.length); let run = 0, s = 0
  for (let i = 0; i < src.length; i++) {
    const x = src[i]
    if (x == null) { run = 0; s = 0; continue }
    run++; s += x
    if (run > n) s -= src[i - n] as number
    if (run >= n) out[i] = s
  }
  return out
}
function sma(src: Series, n: number): Series { return sum(src, n).map(v => v == null ? null : v / n) }
/** 指数类递推的公共骨架：头 n 个连续有值的均值做种子，之后 e = a·x + (1 − a)·e */
function smooth(src: Series, n: number, a: number): Series {
  const out = nulls(src.length); let run = 0, e: number | null = null
  for (let i = 0; i < src.length; i++) {
    const x = src[i]
    if (e == null) {
      if (x == null) { run = 0; continue }
      if (++run < n) continue
      let s = 0; for (let j = i - n + 1; j <= i; j++) s += src[j] as number
      e = s / n; out[i] = e; continue
    }
    if (x == null) continue
    e = a * x + (1 - a) * e; out[i] = e
  }
  return out
}
const ema = (src: Series, n: number): Series => smooth(src, n, 2 / (n + 1))
const rma = (src: Series, n: number): Series => smooth(src, n, 1 / n)
/** 线性加权均线（最新一根权重 n）：滑窗维护「和」与「加权和」，O(n) */
function wma(src: Series, n: number): Series {
  const out = nulls(src.length), den = n * (n + 1) / 2; let run = 0, s = 0, w = 0
  for (let i = 0; i < src.length; i++) {
    const x = src[i]
    if (x == null) { run = 0; continue }
    run++
    if (run < n) continue
    if (run === n) { s = 0; w = 0; for (let j = 0; j < n; j++) { const v = src[i - n + 1 + j] as number; s += v; w += (j + 1) * v } }
    else { w += n * x - s; s += x - (src[i - n] as number) }
    out[i] = w / den
  }
  return out
}
/** 对称加权（ta.swma）：(x[3] + 2x[2] + 2x[1] + x[0]) / 6 */
function swma(src: Series): Series {
  return src.map((x, i) => {
    if (i < 3 || x == null) return null
    const a = src[i - 1], b = src[i - 2], c = src[i - 3]
    return a == null || b == null || c == null ? null : (c + 2 * b + 2 * a + x) / 6
  })
}
/** 滑窗总体标准差：以窗口首值为基准累加偏差，每 n 根整窗重算一次防累积误差（摊还 O(1)）；常量序列严格为 0 */
function stdev(src: Series, n: number): Series {
  const out = nulls(src.length); let run = 0, since = 0, K = 0, s = 0, s2 = 0
  for (let i = 0; i < src.length; i++) {
    const x = src[i]
    if (x == null) { run = 0; continue }
    run++
    if (run < n) continue
    if (run === n || since >= n) {
      K = src[i - n + 1] as number; s = 0; s2 = 0; since = 0
      for (let j = i - n + 1; j <= i; j++) { const d = (src[j] as number) - K; s += d; s2 += d * d }
    } else {
      const d = x - K, o = (src[i - n] as number) - K
      s += d - o; s2 += d * d - o * o; since++
    }
    const m = s / n
    out[i] = Math.sqrt(Math.max(0, s2 / n - m * m))
  }
  return out
}
/** 滑窗最值的下标（单调队列）：win 根窗口里最高（max = true）/ 最低的那一根；并列取最近的一根 */
function extremeIdx(src: number[], win: number, max: boolean): (number | null)[] {
  const out: (number | null)[] = new Array(src.length).fill(null), q: number[] = []; let head = 0
  for (let i = 0; i < src.length; i++) {
    const x = src[i]
    while (q.length > head && (max ? src[q[q.length - 1]] <= x : src[q[q.length - 1]] >= x)) q.pop()
    q.push(i)
    if (q[head] <= i - win) head++
    if (i >= win - 1) out[i] = q[head]
  }
  return out
}
function highest(src: number[], n: number): Series { return extremeIdx(src, n, true).map(j => j == null ? null : src[j]) }
function lowest(src: number[], n: number): Series { return extremeIdx(src, n, false).map(j => j == null ? null : src[j]) }
/** Pine 的 ta.rsi：涨跌幅从第 1 根起算，Wilder 平滑；跌为 0 → 100，涨为 0 → 0 */
function rsi(src: number[], n: number): Series {
  const ch = change(src)
  const up = rma(ch.map(d => d == null ? null : Math.max(d, 0)), n), dn = rma(ch.map(d => d == null ? null : Math.max(-d, 0)), n)
  return zip(up, dn, (u, d) => d === 0 ? 100 : u === 0 ? 0 : 100 - 100 / (1 + u / d))
}
/** 变动率 100 ×（x − x[n]）/ x[n] */
function roc(src: number[], n: number): Series {
  return src.map((x, i) => i >= n && src[i - n] !== 0 ? 100 * (x - src[i - n]) / src[i - n] : null)
}
/** 累积派发线（ta.accdist）：收盘在高低区间里的位置 × 成交量，逐根累加 */
function accdist(bars: Bar[]): number[] {
  let s = 0
  return bars.map(b => (s += b.h === b.l ? 0 : (2 * b.c - b.l - b.h) / (b.h - b.l) * vol(b)))
}
function barInterval(bars: Bar[]): number {
  let m = Infinity
  for (let i = 1; i < Math.min(bars.length, 12); i++) { const d = bars[i].t - bars[i - 1].t; if (d > 0 && d < m) m = d }
  return isFinite(m) ? m : 36e5
}

// ------------------------------------------------------------ 各指标
/** 随机指标：%K = SMA(100·(收 − n 根最低)/(n 根最高 − 最低), m1)，%D = SMA(%K, m2)；高低相同取 50 */
export function stoch(bars: Bar[], n: number, m1: number, m2: number): Series[] {
  const hh = highest(bars.map(b => b.h), n), ll = lowest(bars.map(b => b.l), n)
  const raw: Series = bars.map((b, i) => { const h = hh[i], l = ll[i]; return h == null || l == null ? null : h === l ? 50 : 100 * (b.c - l) / (h - l) })
  const k = sma(raw, m1)
  return [k, sma(k, m2)]
}

/** 动向指标：+DI、−DI 用 Wilder 平滑 n 根，ADX = 100 · RMA(|+DI − −DI| / (+DI + −DI), m1)；波幅为 0 时 DI 沿用上一根（ta.fixnan） */
export function dmi(bars: Bar[], n: number, m1: number): Series[] {
  const pdm: Series = nulls(bars.length), mdm: Series = nulls(bars.length)
  for (let i = 1; i < bars.length; i++) {
    const up = bars[i].h - bars[i - 1].h, dn = bars[i - 1].l - bars[i].l
    pdm[i] = up > dn && up > 0 ? up : 0; mdm[i] = dn > up && dn > 0 ? dn : 0
  }
  const tr = rma(trueRange(bars, true), n), sp = rma(pdm, n), sm = rma(mdm, n)
  let lp = 0, lm = 0
  const plus = zip(sp, tr, (a, t) => (lp = t === 0 ? lp : 100 * a / t))
  const minus = zip(sm, tr, (a, t) => (lm = t === 0 ? lm : 100 * a / t))
  const adx = rma(zip(plus, minus, (a, b) => Math.abs(a - b) / (a + b === 0 ? 1 : a + b)), m1).map(v => v == null ? null : 100 * v)
  return [plus, minus, adx]
}

/** 资金流量（ta.mfi）：典型价涨的根「典型价 × 量」进流入、跌的进流出，n 根求和后折成 0–100；流入流出都为 0 取 50 */
export function mfi(bars: Bar[], n: number): Series[] {
  const tp = bars.map(hlc3), ch = change(tp)
  const mf = bars.map((b, i) => tp[i] * vol(b))
  const up = sum(ch.map((d, i) => d == null ? null : d <= 0 ? 0 : mf[i]), n), dn = sum(ch.map((d, i) => d == null ? null : d >= 0 ? 0 : mf[i]), n)
  return [zip(up, dn, (u, d) => d === 0 ? (u === 0 ? 50 : 100) : 100 - 100 / (1 + u / d))]
}

/** 阿隆：在 n + 1 根窗口里，上 = 100·(n − 距最高那根的根数)/n，下同理（并列取最近的一根） */
export function aroon(bars: Bar[], n: number): Series[] {
  const hi = extremeIdx(bars.map(b => b.h), n + 1, true), lo = extremeIdx(bars.map(b => b.l), n + 1, false)
  return [hi.map((j, i) => j == null ? null : 100 * (n - (i - j)) / n), lo.map((j, i) => j == null ? null : 100 * (n - (i - j)) / n)]
}

/** 蔡金资金流：Σ(收盘位置 × 量) / Σ量，n 根 */
export function cmf(bars: Bar[], n: number): Series[] {
  const mfv = bars.map(b => b.h === b.l ? 0 : (2 * b.c - b.l - b.h) / (b.h - b.l) * vol(b))
  return [zip(sum(mfv, n), sum(bars.map(vol), n), (a, v) => v === 0 ? 0 : a / v)]
}

/** 蔡金摆动：EMA(累积派发, fast) − EMA(累积派发, slow) */
export function chaikinOsc(bars: Bar[], fast: number, slow: number): Series[] {
  const ad = accdist(bars)
  return [zip(ema(ad, fast), ema(ad, slow), (a, b) => a - b)]
}

/** 动量震荡（比尔·威廉姆斯）：SMA(中价, fast) − SMA(中价, slow) */
function aoOf(bars: Bar[], fast: number, slow: number): Series {
  const m = bars.map(hl2)
  return zip(sma(m, fast), sma(m, slow), (a, b) => a - b)
}
export function ao(bars: Bar[], fast: number, slow: number): Series[] { return [aoOf(bars, fast, slow)] }
/** 加速震荡：AO − SMA(AO, 5) */
export function ac(bars: Bar[], fast: number, slow: number): Series[] {
  const a = aoOf(bars, fast, slow)
  return [zip(a, sma(a, 5), (x, y) => x - y)]
}

export function mom(bars: Bar[], n: number): Series[] { const c = bars.map(b => b.c); return [c.map((x, i) => i >= n ? x - c[i - n] : null)] }
export function rocInd(bars: Bar[], n: number): Series[] { return [roc(bars.map(b => b.c), n)] }

/** TRIX（照 TV）：10000 × 一根的变化量（EMA(EMA(EMA(ln 收, n), n), n)），即万分比 */
export function trix(bars: Bar[], n: number): Series[] {
  const e = ema(ema(ema(bars.map(b => b.c > 0 ? Math.log(b.c) : null), n), n), n)
  return [e.map((v, i) => { const p = e[i - 1]; return v == null || p == null ? null : 10000 * (v - p) })]
}

/** 去趋势价格（不居中）：收 − SMA(收, n) 往回 ⌊n/2⌋ + 1 根的值 */
export function dpo(bars: Bar[], n: number): Series[] {
  const c = bars.map(b => b.c), m = sma(c, n), back = Math.floor(n / 2) + 1
  return [c.map((x, i) => { const v = i >= back ? m[i - back] : null; return v == null ? null : x - v })]
}

/** 终极摆动：买压 = 收 − min(低, 前收)，波幅 = max(高, 前收) − min(低, 前收)；
 *  100 × (4·短 + 2·中 + 长) / 7，各段 = Σ买压 / Σ波幅（波幅全为 0 时取 0.5） */
export function uo(bars: Bar[], fast: number, mid: number, slow: number): Series[] {
  const bp: Series = nulls(bars.length), tr: Series = nulls(bars.length)
  for (let i = 1; i < bars.length; i++) {
    const b = bars[i], pc = bars[i - 1].c, lo = Math.min(b.l, pc)
    bp[i] = b.c - lo; tr[i] = Math.max(b.h, pc) - lo
  }
  const avg = (n: number): Series => zip(sum(bp, n), sum(tr, n), (a, t) => t === 0 ? 0.5 : a / t)
  const a1 = avg(fast), a2 = avg(mid), a3 = avg(slow)
  return [a1.map((x, i) => { const y = a2[i], z = a3[i]; return x == null || y == null || z == null ? null : 100 * (4 * x + 2 * y + z) / 7 })]
}

/** 多空力量（埃尔德）：(高 − EMA(收, n)) + (低 − EMA(收, n)) */
export function bbp(bars: Bar[], n: number): Series[] {
  const e = ema(bars.map(b => b.c), n)
  return [e.map((v, i) => v == null ? null : bars[i].h - v + bars[i].l - v)]
}

/** 强力指数（埃尔德）：EMA(收盘变化 × 量, n) */
export function efi(bars: Bar[], n: number): Series[] {
  return [ema(change(bars.map(b => b.c)).map((d, i) => d == null ? null : d * vol(bars[i])), n)]
}

/** 波动指数：100 · log10(Σ真实波幅(n) / (n 根最高 − 最低)) / log10(n)；高低相同出空（TV 同样是 na） */
export function chop(bars: Bar[], n: number): Series[] {
  const st = sum(trueRange(bars, false), n), hh = highest(bars.map(b => b.h), n), ll = lowest(bars.map(b => b.l), n), ln = Math.log10(n)
  return [st.map((s, i) => { const h = hh[i], l = ll[i]; return s == null || h == null || l == null || h === l || s <= 0 ? null : 100 * Math.log10(s / (h - l)) / ln })]
}

/** 科波克：WMA(ROC(收, 长) + ROC(收, 短), n) */
export function coppock(bars: Bar[], short: number, long: number, n: number): Series[] {
  const c = bars.map(b => b.c)
  return [wma(zip(roc(c, long), roc(c, short), (a, b) => a + b), n)]
}

/** 钱德动量：100 × (Σ涨 − Σ跌) / (Σ涨 + Σ跌)，n 根；全平取 0 */
export function cmo(bars: Bar[], n: number): Series[] {
  const ch = change(bars.map(b => b.c))
  const su = sum(ch.map(d => d == null ? null : Math.max(d, 0)), n), sd = sum(ch.map(d => d == null ? null : Math.max(-d, 0)), n)
  return [zip(su, sd, (u, d) => u + d === 0 ? 0 : 100 * (u - d) / (u + d))]
}

/** 涡旋：VI+ = Σ|高 − 前低| / Σ真实波幅，VI− = Σ|低 − 前高| / Σ真实波幅（n 根）；波幅和为 0 出空 */
export function vortex(bars: Bar[], n: number): Series[] {
  const vp: Series = nulls(bars.length), vm: Series = nulls(bars.length)
  for (let i = 1; i < bars.length; i++) { vp[i] = Math.abs(bars[i].h - bars[i - 1].l); vm[i] = Math.abs(bars[i].l - bars[i - 1].h) }
  const st = sum(trueRange(bars, false), n)
  return [zip(sum(vp, n), st, (a, t) => t === 0 ? null : a / t), zip(sum(vm, n), st, (a, t) => t === 0 ? null : a / t)]
}

/** 确然指标：ROC 10/15/20/30 各取 SMA 10/10/10/15，按 1:2:3:4 加权；信号 = SMA(KST, signal) */
export function kst(bars: Bar[], signal: number): Series[] {
  const c = bars.map(b => b.c)
  const r = [[10, 10, 1], [15, 10, 2], [20, 10, 3], [30, 15, 4]].map(([rl, sl, w]) => sma(roc(c, rl), sl).map(v => v == null ? null : v * w))
  const k = r[0].map((v, i) => { const b = r[1][i], cc = r[2][i], d = r[3][i]; return v == null || b == null || cc == null || d == null ? null : v + b + cc + d })
  return [k, sma(k, signal)]
}

/** 质量指数：Σ( EMA(高 − 低, n) / EMA(EMA(高 − 低, n), n) )，求和 m1 根；双重 EMA 为 0（全平）时比值取 1 */
export function mass(bars: Bar[], n: number, m1: number): Series[] {
  const e1 = ema(bars.map(b => b.h - b.l), n), e2 = ema(e1, n)
  return [sum(zip(e1, e2, (a, b) => b === 0 ? 1 : a / b), m1)]
}

/** 简易波动：SMA( 中价变化 × (高 − 低) / 量, n )。
 *  TV 的原式是 10000 × Δ中价 × (高 − 低) / 成交量（币），量级随价格的平方走：BTC 一小时几十万、DOGE 只有 1e−11，
 *  副图读数只留两位小数，低价币一律显示 0.00。这里把它改成不随价位、周期变的量级：
 *    1e15 × Δ中价 × (高 − 低) / (中价² × 成交额)
 *  价格项都除以中价（化成相对涨跌），「量」用成交额（报价币）。Δ中价·(高 − 低) 与成交额都和周期长度成正比，
 *  所以同一只品种 1 分钟与 1 小时的读数量级一样；1e15 让币安永续里 BTC、ETH 一小时落在个位到几十、
 *  小币几百到几千。同一只品种上和 TV 的曲线只差一个随价格缓慢变化的系数，形状一致。
 *  零成交的根贡献记 0（TV 是 na，会把后面 n 根整段挖空）。 */
export const EOM_SCALE = 1e15
export function eom(bars: Bar[], n: number): Series[] {
  const raw: Series = bars.map((b, i) => {
    if (i === 0) return null
    const m = hl2(b), d = m - hl2(bars[i - 1])
    return b.v > 0 && m > 0 && Number.isFinite(b.v) ? EOM_SCALE * d * (b.h - b.l) / (m * m * b.v) : 0
  })
  return [sma(raw, n)]
}

/** 价量趋势：Σ(收盘涨跌幅 × 量)，从第一根加载进来的 K 线起累计 */
export function pvt(bars: Bar[]): Series[] {
  let s = 0
  return [bars.map((b, i) => { if (i > 0 && bars[i - 1].c !== 0) s += (b.c - bars[i - 1].c) / bars[i - 1].c * vol(b); return s })]
}

/** 均势指标：(收 − 开) / (高 − 低)，再取 n 根 SMA（n = 1 即 TV 原样不平滑）；高低相同记 0 */
export function bop(bars: Bar[], n: number): Series[] {
  return [sma(bars.map(b => b.h === b.l ? 0 : (b.c - b.o) / (b.h - b.l)), n)]
}

/** 历史波动率（照 TV）：100 × stdev(ln(收/前收), n) × √(365 / per)，日线及以下 per = 1、多日 / 周线以上 per = 7 */
export function hv(bars: Bar[], n: number, iv: number): Series[] {
  const lr: Series = bars.map((b, i) => i > 0 && b.c > 0 && bars[i - 1].c > 0 ? Math.log(b.c / bars[i - 1].c) : null)
  const k = 100 * Math.sqrt(365 / (iv <= DAY ? 1 : 7))
  return [stdev(lr, n).map(v => v == null ? null : v * k)]
}

export function stdevInd(bars: Bar[], n: number): Series[] { return [stdev(bars.map(b => b.c), n)] }

/** 费舍尔转换：中价在 n 根（中价的）高低区间里的位置 → 0.66 平滑并夹在 ±0.999 → 0.5·ln((1+v)/(1−v)) + 0.5·上一根；
 *  触发线 = 上一根的值。高低相同按位置 0.5 */
export function fisher(bars: Bar[], n: number): Series[] {
  const m = bars.map(hl2), hh = highest(m, n), ll = lowest(m, n)
  const f = nulls(bars.length); let v = 0, fi = 0
  for (let i = 0; i < bars.length; i++) {
    const h = hh[i], l = ll[i]
    if (h == null || l == null) continue
    const pos = h === l ? 0.5 : (m[i] - l) / (h - l)
    v = 0.66 * (pos - 0.5) + 0.67 * v
    v = v > 0.99 ? 0.999 : v < -0.99 ? -0.999 : v
    fi = 0.5 * Math.log((1 + v) / (1 - v)) + 0.5 * fi
    f[i] = fi
  }
  return [f, f.map((_, i) => i > 0 ? f[i - 1] : null)]
}

/** 相对活力：Σ swma(收 − 开) / Σ swma(高 − 低)（n 根），信号 = swma(RVGI)；波幅和为 0 记 0 */
export function rvgi(bars: Bar[], n: number): Series[] {
  const r = zip(sum(swma(bars.map(b => b.c - b.o)), n), sum(swma(bars.map(b => b.h - b.l)), n), (a, d) => d === 0 ? 0 : a / d)
  return [r, swma(r)]
}

/** 相对波动：收盘涨的根取 stdev(收, n)、跌的根取 0 → EMA(m1) 为上；反之为下；100 × 上 / (上 + 下)，都为 0 取 50 */
export function rvi(bars: Bar[], n: number, m1: number): Series[] {
  const c = bars.map(b => b.c), sd = stdev(c, n), ch = change(c)
  const up = ema(sd.map((s, i) => s == null ? null : ch[i] != null && (ch[i] as number) <= 0 ? 0 : s), m1)
  const dn = ema(sd.map((s, i) => s == null ? null : ch[i] != null && (ch[i] as number) > 0 ? 0 : s), m1)
  return [zip(up, dn, (u, d) => u + d === 0 ? 50 : 100 * u / (u + d))]
}

/** 成交量震荡：100 × (EMA(量, fast) − EMA(量, slow)) / EMA(量, slow) */
export function volosc(bars: Bar[], fast: number, slow: number): Series[] {
  const v = bars.map(vol)
  return [zip(ema(v, fast), ema(v, slow), (a, b) => b === 0 ? 0 : 100 * (a - b) / b)]
}

/** 克林格（照 TV 的简化版）：典型价不跌记 +量、跌记 −量，KVO = EMA(fast) − EMA(slow)，信号 = EMA(KVO, signal)。
 *  第 0 根没有前一根，从第 1 根起算（TV 的 Pine 在第 0 根会因 na 比较记成 −量，给开头几十根带进一个假的偏移，不照抄） */
export function klinger(bars: Bar[], fast: number, slow: number, signal: number): Series[] {
  const sv: Series = bars.map((b, i) => i === 0 ? null : hlc3(b) - hlc3(bars[i - 1]) >= 0 ? vol(b) : -vol(b))
  const k = zip(ema(sv, fast), ema(sv, slow), (a, b) => a - b)
  return [k, ema(k, signal)]
}

export function ad(bars: Bar[]): Series[] { return [accdist(bars)] }

/** 康纳 RSI：[RSI(收, n) + RSI(连涨连跌根数, m1) + 一根涨跌幅在前 m2 根里的百分位] / 3 */
export function crsi(bars: Bar[], n: number, m1: number, m2: number): Series[] {
  const c = bars.map(b => b.c), len = c.length
  // 连涨连跌：平 0；涨时上一根 ≤ 0 记 1 否则 +1；跌时上一根 ≥ 0 记 −1 否则 −1（第 0 根同 Pine 记 −1）
  const ud: number[] = []
  for (let i = 0; i < len; i++) {
    const p = i > 0 ? ud[i - 1] : 0
    ud.push(i > 0 && c[i] === c[i - 1] ? 0 : i > 0 && c[i] > c[i - 1] ? (p <= 0 ? 1 : p + 1) : (p >= 0 ? -1 : p - 1))
  }
  const r1 = rsi(c, n), r2 = rsi(ud, m1), pr = percentRank(roc(c, 1), m2)
  return [r1.map((a, i) => { const b = r2[i], d = pr[i]; return a == null || b == null || d == null ? null : (a + b + d) / 3 })]
}
/** ta.percentrank：前 n 根（不含本根）里 ≤ 本根的占几成 × 100。树状数组按值排名计数，O(n log n) */
function percentRank(src: Series, n: number): Series {
  const out = nulls(src.length)
  const vals = Array.from(new Set(src.filter((v): v is number => v != null))).sort((a, b) => a - b)
  const rank = new Map(vals.map((v, i) => [v, i + 1])), tree = new Array(vals.length + 1).fill(0)
  const add = (r: number, d: number) => { for (; r <= vals.length; r += r & -r) tree[r] += d }
  const count = (r: number) => { let s = 0; for (; r > 0; r -= r & -r) s += tree[r]; return s }
  let run = 0
  for (let i = 0; i < src.length; i++) {
    const x = src[i]
    if (x == null) { // 断开就清空窗口重新数
      for (let j = i - Math.min(run, n); j < i; j++) add(rank.get(src[j] as number) as number, -1)
      run = 0; continue
    }
    const r = rank.get(x) as number
    if (run >= n) out[i] = 100 * count(r) / n
    add(r, 1); run++
    if (run > n) add(rank.get(src[i - n] as number) as number, -1)
  }
  return out
}

/** 真实强度：100 × EMA(EMA(Δ收, slow), fast) / EMA(EMA(|Δ收|, slow), fast)，信号 = EMA(TSI, signal) */
export function tsi(bars: Bar[], slow: number, fast: number, signal: number): Series[] {
  const ch = change(bars.map(b => b.c))
  const t = zip(ema(ema(ch, slow), fast), ema(ema(ch.map(d => d == null ? null : Math.abs(d)), slow), fast), (a, b) => b === 0 ? 0 : 100 * a / b)
  return [t, ema(t, signal)]
}

/** 随机动量：200 × EMA²(收 − 区间中点, m1) / EMA²(区间高低差, m1)（区间 n 根），信号 = EMA(SMI, m2) */
export function smi(bars: Bar[], n: number, m1: number, m2: number): Series[] {
  const hh = highest(bars.map(b => b.h), n), ll = lowest(bars.map(b => b.l), n)
  const rel: Series = bars.map((b, i) => { const h = hh[i], l = ll[i]; return h == null || l == null ? null : b.c - (h + l) / 2 })
  const rng = zip(hh, ll, (h, l) => h - l)
  const s = zip(ema(ema(rel, m1), m1), ema(ema(rng, m1), m1), (a, b) => b === 0 ? 0 : 200 * a / b)
  return [s, ema(s, m2)]
}

/** 价格震荡百分比：100 × (EMA 快 − EMA 慢) / EMA 慢，信号 = EMA(PPO, signal)，柱 = PPO − 信号 */
export function ppo(bars: Bar[], fast: number, slow: number, signal: number): Series[] {
  const c = bars.map(b => b.c)
  const p = zip(ema(c, fast), ema(c, slow), (a, b) => b === 0 ? null : 100 * (a - b) / b), s = ema(p, signal)
  return [p, s, zip(p, s, (a, b) => a - b)]
}

/** 布林带宽：(上轨 − 下轨) / 中轨 × 100 */
export function bbw(bars: Bar[], n: number, k: number): Series[] {
  const c = bars.map(b => b.c)
  return [zip(sma(c, n), stdev(c, n), (m, sd) => m === 0 ? null : 200 * k * sd / m)]
}
/** 布林 %B：(收 − 下轨) / (上轨 − 下轨)；带宽为 0 取 0.5 */
export function bbpct(bars: Bar[], n: number, k: number): Series[] {
  const c = bars.map(b => b.c)
  const m = sma(c, n), sd = stdev(c, n)
  return [c.map((x, i) => { const mm = m[i], s = sd[i]; return mm == null || s == null ? null : s === 0 ? 0.5 : (x - (mm - k * s)) / (2 * k * s) })]
}

/** 净成交量（主动买 − 主动卖，报价币计）：多交易所聚合的根把各家量差加起来，只有币安的根 = 2 × 主动买入 − 成交额，没有主动买入的根出空。
 *  TV 的 Net Volume 是「收涨记 +量、收跌记 −量」，这里有逐根真实的主动买卖拆分，用真的 */
export function nv(bars: Bar[]): Series[] {
  return [bars.map(b => {
    if (b.venueDelta) { let s = 0; for (const v of Object.values(b.venueDelta)) s += v || 0; return s }
    return b.tb != null && Number.isFinite(b.tb) ? 2 * b.tb - b.v : null
  })]
}

// ------------------------------------------------------------ 并进 Calc / CATALOG 的表
const kOf = (v: number | undefined): number => v && v > 0 ? v : 2
export const OSC_CALC: Record<OscId, Fn> = {
  stoch: (b, p) => stoch(b, int(p.n, 14), int(p.m1, 1), int(p.m2, 3)),
  dmi: (b, p) => dmi(b, int(p.n, 14), int(p.m1, 14)),
  mfi: (b, p) => mfi(b, int(p.n, 14)),
  aroon: (b, p) => aroon(b, int(p.n, 14)),
  cmf: (b, p) => cmf(b, int(p.n, 20)),
  chosc: (b, p) => chaikinOsc(b, int(p.fast, 3), int(p.slow, 10)),
  ao: (b, p) => ao(b, int(p.fast, 5), int(p.slow, 34)),
  ac: (b, p) => ac(b, int(p.fast, 5), int(p.slow, 34)),
  mom: (b, p) => mom(b, int(p.n, 10)),
  roc: (b, p) => rocInd(b, int(p.n, 9)),
  trix: (b, p) => trix(b, int(p.n, 18)),
  dpo: (b, p) => dpo(b, int(p.n, 21)),
  uo: (b, p) => uo(b, int(p.fast, 7), int(p.m1, 14), int(p.slow, 28)),
  bbp: (b, p) => bbp(b, int(p.n, 13)),
  efi: (b, p) => efi(b, int(p.n, 13)),
  chop: (b, p) => chop(b, int(p.n, 14, 2)),
  coppock: (b, p) => coppock(b, int(p.m1, 11), int(p.m2, 14), int(p.n, 10)),
  cmo: (b, p) => cmo(b, int(p.n, 9)),
  vortex: (b, p) => vortex(b, int(p.n, 14)),
  kst: (b, p) => kst(b, int(p.signal, 9)),
  mass: (b, p) => mass(b, int(p.n, 9), int(p.m1, 25)),
  eom: (b, p) => eom(b, int(p.n, 14)),
  pvt: b => pvt(b),
  bop: (b, p) => bop(b, int(p.n, 14)),
  hv: (b, p, env) => hv(b, int(p.n, 10), env?.iv || barInterval(b)),
  stdev: (b, p) => stdevInd(b, int(p.n, 20)),
  fisher: (b, p) => fisher(b, int(p.n, 9)),
  rvgi: (b, p) => rvgi(b, int(p.n, 10)),
  rvi: (b, p) => rvi(b, int(p.n, 10), int(p.m1, 14)),
  volosc: (b, p) => volosc(b, int(p.fast, 5), int(p.slow, 10)),
  klinger: (b, p) => klinger(b, int(p.fast, 34), int(p.slow, 55), int(p.signal, 13)),
  ad: b => ad(b),
  crsi: (b, p) => crsi(b, int(p.n, 3), int(p.m1, 2), int(p.m2, 100)),
  tsi: (b, p) => tsi(b, int(p.slow, 25), int(p.fast, 13), int(p.signal, 13)),
  smi: (b, p) => smi(b, int(p.n, 10), int(p.m1, 3), int(p.m2, 3)),
  ppo: (b, p) => ppo(b, int(p.fast, 12), int(p.slow, 26), int(p.signal, 9)),
  bbw: (b, p) => bbw(b, int(p.n, 20), kOf(p.k)),
  bbpct: (b, p) => bbpct(b, int(p.n, 20), kOf(p.k)),
  nv: b => nv(b),
}

// 目录：名字、默认参数（照 TV 默认）、线色（照 TV 默认色）、图例前缀。cn 一律空串（界面不再展示描述文案）。
// 参数只用 IndParams 已有的键，值都在 (0, 2000] 里（store 的 cleanParams 只认这个范围）。
const sub = (name: string, params: IndParams, colors: string[], labels?: string[]): CatalogEntry =>
  ({ name, cn: '', place: 'sub', params, colors, labels: labels ?? colors.map(() => '') })
export const OSC_CATALOG: Record<OscId, CatalogEntry> = {
  stoch: sub('随机指标', { n: 14, m1: 1, m2: 3 }, ['#2962FF', '#FF6D00'], ['K', 'D']),
  dmi: sub(sharedName('dmi'), sharedParams('dmi', { m1: 14 })!, ['#2962FF', '#FF6D00', '#F50057'], ['正向', '负向', '趋向']),
  mfi: sub('资金流量', { n: 14 }, ['#7E57C2']),
  aroon: sub('阿隆', { n: 14 }, ['#FB8C00', '#2962FF'], ['上', '下']),
  cmf: sub('蔡金资金流', { n: 20 }, ['#43A047']),
  chosc: sub('蔡金摆动', { fast: 3, slow: 10 }, ['#EC407A']),
  ao: sub('动量震荡', { fast: 5, slow: 34 }, ['#009688']),
  ac: sub('加速震荡', { fast: 5, slow: 34 }, ['#009688']),
  mom: sub('动量', { n: 10 }, ['#2962FF']),
  roc: sub('变动率', { n: 9 }, ['#2962FF']),
  trix: sub('TRIX', { n: 18 }, ['#F44336']),
  dpo: sub('去趋势价格', { n: 21 }, ['#43A047']),
  uo: sub('终极摆动', { fast: 7, m1: 14, slow: 28 }, ['#F44336']),
  bbp: sub('多空力量', { n: 13 }, ['#089981']),
  efi: sub('强力指数', { n: 13 }, ['#F44336']),
  chop: sub('波动指数', { n: 14 }, ['#2962FF']),
  coppock: sub('科波克', { m1: 11, m2: 14, n: 10 }, ['#2962FF']),
  cmo: sub('钱德动量', { n: 9 }, ['#2962FF']),
  vortex: sub('涡旋', { n: 14 }, ['#2962FF', '#E91E63'], ['正', '负']),
  kst: sub('确然指标', { signal: 9 }, ['#009688', '#F44336'], ['', '信号']),
  mass: sub('质量指数', { n: 9, m1: 25 }, ['#2962FF']),
  eom: sub('简易波动', { n: 14 }, ['#43A047']),
  pvt: sub('价量趋势', {}, ['#2962FF']),
  bop: sub('均势指标', { n: 14 }, ['#F23645']),
  hv: sub('历史波动率', { n: 10 }, ['#2962FF']),
  stdev: sub('标准差', { n: 20 }, ['#2962FF']),
  fisher: sub('费舍尔转换', { n: 9 }, ['#2962FF', '#FF6D00'], ['', '触发']),
  rvgi: sub('相对活力', { n: 10 }, ['#008000', '#FF0000'], ['', '信号']),
  rvi: sub('相对波动', { n: 10, m1: 14 }, ['#7E57C2']),
  volosc: sub('成交量震荡', { fast: 5, slow: 10 }, ['#2962FF']),
  klinger: sub('克林格', { fast: 34, slow: 55, signal: 13 }, ['#2962FF', '#43A047'], ['', '信号']),
  ad: sub('累积派发', {}, ['#999915']),
  crsi: sub('康纳 RSI', { n: 3, m1: 2, m2: 100 }, ['#2962FF']),
  tsi: sub('真实强度', { slow: 25, fast: 13, signal: 13 }, ['#2962FF', '#E91E63'], ['', '信号']),
  smi: sub('随机动量', { n: 10, m1: 3, m2: 3 }, ['#2962FF', '#FF9800'], ['', '信号']),
  ppo: sub('价格震荡百分比', { fast: 12, slow: 26, signal: 9 }, ['#2962FF', '#FF6D00', '#26A69A'], ['', '信号', '柱']),
  bbw: sub('布林带宽', { n: 20, k: 2 }, ['#2962FF']),
  bbpct: sub('布林 %B', { n: 20, k: 2 }, ['#2962FF']),
  nv: sub('净成交量', {}, ['#2962FF']),
}

/** 固定刻度的副图（不随可见数据伸缩） */
export const OSC_FIXED: Partial<Record<OscId, { min: number; max: number }>> = {
  stoch: { min: 0, max: 100 },
  mfi: { min: 0, max: 100 },
  aroon: { min: 0, max: 100 },
  uo: { min: 0, max: 100 },
  chop: { min: 0, max: 100 },
  cmo: { min: -100, max: 100 },
  rvi: { min: 0, max: 100 },
  crsi: { min: 0, max: 100 },
}
/** 副图上的参考线：逐个照 TV 内置指标（pine-facade STD;*）的 hline——TV 没画 hline 的（动量、AO、终极摆动、科波克、涡旋、
 *  质量指数、简易波动、均势、相对活力、克林格、动向、阿隆）这里也不画；线色 / 虚实在 indicators.ts 的 subLevelLines 里查 */
export const OSC_LEVELS: Partial<Record<OscId, number[]>> = {
  stoch: [80, 50, 20],
  mfi: [80, 50, 20],
  cmf: [0],
  chosc: [0],
  roc: [0],
  trix: [0],
  dpo: [0],
  bbp: [0],
  efi: [0],
  chop: [61.8, 50, 38.2],
  cmo: [0],
  kst: [0],
  fisher: [1.5, 0.75, 0, -0.75, -1.5],
  rvi: [80, 50, 20],
  volosc: [0],
  crsi: [70, 50, 30],
  tsi: [0],
  smi: [40, 0, -40],
  ppo: [0],
  bbpct: [1, 0.5, 0],
  nv: [0],
}
/** 两条参考线之间铺淡填充的「超买超卖带」：[上沿, 下沿]（照 TV 默认有 hline 间 fill 的那些；填充色在 subBandFills 里查） */
export const OSC_BAND: Partial<Record<OscId, [number, number]>> = {
  stoch: [80, 20],
  mfi: [80, 20],
  chop: [61.8, 38.2],
  rvi: [80, 20],
  crsi: [70, 30],
  smi: [40, -40],
  bbpct: [1, 0],
}
/** 各条序列的画法（没列的一律折线）：AO / AC 照 TV 是升绿降红柱（#009688 / #F44336），多空力量是正绿负红柱，
 *  PPO 柱照 TV MACD 四色柱；净成交量照 TV 是一条蓝线加零轴 */
export const OSC_STYLE: Partial<Record<OscId, OscStyle[]>> = {
  ao: ['histTrend'],
  ac: ['histTrend'],
  bbp: ['hist'],
  ppo: ['line', 'line', 'hist4'],
}
