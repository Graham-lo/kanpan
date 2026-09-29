// 移植自 KanpanCore/Sources/KanpanCore/Indicator/IndicatorID.swift（文件末尾附 OINotice.swift）
//
// 指标标识与展示信息。rawValue 是存档用的（写进偏好、缓存键），英文、定死不许改；
// 界面上露脸的是 name 与 lineNames，一律中文。
//
// Swift 的 enum + 计算属性在这里拆成：`IndicatorID` 常量表（ma → 'MA' …）+ 同名字符串联合类型，
// 以及一组以 id 为第一个参数的函数。

/**
 * 声明顺序有约束：主图的全部排在副图前面（契约里 overlay ++ sub == allCases 按顺序比）。
 * 值就是 Swift 的 rawValue。
 */
export const IndicatorID = {
  ma: 'MA', ema: 'EMA', boll: 'BOLL',
  vwap: 'VWAP', supertrend: 'ST', sar: 'SAR',
  /** 主力订单流：不是 K 线算出来的指标，开关另存；枚举里有它是为了面板那一行与契约词表。 */
  orderFlow: 'ORDERFLOW',
  vol: 'VOL', macd: 'MACD', rsi: 'RSI', kdj: 'KDJ', srsi: 'SRSI', atr: 'ATR', oi: 'OI',
  lsr: 'LSR', taker: 'TAKER', basis: 'BASIS',
  dmi: 'DMI',
  cvd: 'CVD',
} as const
export type IndicatorID = (typeof IndicatorID)[keyof typeof IndicatorID]

/** allCases，声明顺序。 */
export const ALL_INDICATOR_IDS: readonly IndicatorID[] = Object.values(IndicatorID)

/** `IndicatorID(rawValue:)`：认不出来给 null。 */
export function indicatorFromRaw(raw: string): IndicatorID | null {
  return (ALL_INDICATOR_IDS as readonly string[]).includes(raw) ? (raw as IndicatorID) : null
}

export type Placement = 'main' | 'sub'

export function placement(id: IndicatorID): Placement {
  switch (id) {
    case 'MA': case 'EMA': case 'BOLL': case 'VWAP': case 'ST': case 'SAR': case 'ORDERFLOW': return 'main'
    default: return 'sub'
  }
}

const NAME: Record<IndicatorID, string> = {
  MA: '均线', EMA: '指数均线', BOLL: '布林带', VOL: '成交量', MACD: '平滑异同', RSI: '相对强弱',
  KDJ: '随机指标', SRSI: '随机强弱', ATR: '真实波幅', OI: '持仓量', LSR: '多空比', TAKER: '买卖比',
  BASIS: '基差', VWAP: '均价线', ST: '超级趋势', SAR: '抛物线', ORDERFLOW: '主力订单流',
  DMI: '动向指标', CVD: '量差',
}

/** 中文名。 */
export function indicatorName(id: IndicatorID): string { return NAME[id] }

// ---------------------------------------------------------------- 面板清单
//
// 面板上摆哪几把、按什么顺序摆，由下面两张表说了算，不是 allCases。
// SRSI 与 ATR 2026-09-22 撤出面板但枚举留着（老偏好里可能有它们），由 retired 在读偏好时滤掉。

/** 主图可选指标，面板顺序。 */
export const mainPalette: readonly IndicatorID[] = ['MA', 'EMA', 'BOLL', 'VWAP', 'ST', 'SAR', 'ORDERFLOW']
/** 副图可选指标，面板顺序（累计成交量差紧跟成交量）。 */
export const subPalette: readonly IndicatorID[] = ['VOL', 'CVD', 'MACD', 'RSI', 'KDJ', 'DMI', 'OI', 'LSR', 'TAKER', 'BASIS']
/** 面板上还摆着的全部。 */
export const palette: readonly IndicatorID[] = [...mainPalette, ...subPalette]
/** 退役的：还能解码、还能算，但不再出现在面板上，读偏好时要滤掉。 */
export const retired: readonly IndicatorID[] = ['SRSI', 'ATR']
export function isRetired(id: IndicatorID): boolean { return retired.includes(id) }
/** 把一串存档里的指标滤成「现在还摆着的」，顺序不动、不去重。 */
export function alive(ids: readonly IndicatorID[]): IndicatorID[] { return ids.filter(id => !isRetired(id)) }

/** 这个指标要几列外部数据；null 表示它只吃 K 线。 */
export function externalColumns(id: IndicatorID): number | null {
  switch (id) {
    case 'OI': case 'LSR': case 'TAKER': case 'BASIS': return 1
    default: return null
  }
}

/** 值是外面喂进来的（持仓量、多空比、主动买卖比、基差），不是 K 线算出来的。 */
export function isExternal(id: IndicatorID): boolean { return externalColumns(id) !== null }

/**
 * 每把指标的出厂参数（AICoin 手机端那一套）。客户端只此一份：偏好出厂值、图表状态缺省、
 * 存档修补、引擎补位都从这里取。每次调用给一份新数组，调用方可以随便改。
 */
export function defaultParams(id: IndicatorID): number[] {
  switch (id) {
    case 'MA': return [10, 30, 120, 256]
    case 'EMA': return [12, 144, 169, 200]
    case 'BOLL': return [20, 2]
    case 'VOL': return [5, 10, 30, 60, 120]
    case 'MACD': return [10, 30, 9]
    case 'RSI': return [6, 12, 24]
    case 'KDJ': return [9, 3, 3]
    case 'SRSI': return [14, 14, 3, 3]
    case 'ATR': return [14]
    case 'ST': return [10, 3]
    case 'DMI': return [14]
    // 当日VWAP、抛物线、主力订单流、累计成交量差、外部四把：没有该让用户拨的参数。
    case 'VWAP': case 'SAR': case 'ORDERFLOW': case 'CVD': case 'OI': case 'LSR': case 'TAKER': case 'BASIS': return []
  }
}

/** 新装时写进偏好的那几把（MA / EMA / VOL / MACD）的参数，值就是 defaultParams。 */
export const factoryParams: Readonly<Partial<Record<IndicatorID, readonly number[]>>> = Object.fromEntries(
  (['MA', 'EMA', 'VOL', 'MACD'] as IndicatorID[]).map(id => [id, defaultParams(id)]),
)

/**
 * 算之前把参数理成这把指标能直接下标取用的长度。
 * 按列表画的（MA、EMA、RSI、VOL）原样；固定个数的缺位用默认值补、多出来的丢掉。
 * 取值本身（0、负数）不改：各条线对脏窗口长度自有处理，画成「这段没有线」。
 *
 * Swift 的参数是 `[Int]`，小数和 NaN 进不来；TS 是 number[]，同步解码、深链、旧存档
 * 都可能送进 2.5 或 NaN。这里补上 Int 的语义：小数向零截断；非有限值当缺位——固定个数的
 * 用默认值补，按列表画的记成 0（那条线画成「没有线」，条数与配色下标不变）。
 * 不截的话 2.5 会让窗口循环多跑半根、往结果数组上写出 "1.5" 这种非下标属性，
 * NaN 会让 tailBars 变 NaN、尾部增量一根都不重算，参数比较也永远不等、缓存次次失效。
 */
export function normalizedParams(id: IndicatorID, params: readonly number[] | null | undefined): number[] {
  if (params == null) return defaultParams(id)
  switch (id) {
    case 'MA': case 'EMA': case 'RSI': case 'VOL':
      return params.map(v => (Number.isFinite(v) ? Math.trunc(v) || 0 : 0))
    default: {
      const d = defaultParams(id)
      return d.map((v, i) => (i < params.length && Number.isFinite(params[i]) ? Math.trunc(params[i]) || 0 : v))
    }
  }
}

export function paramLabels(id: IndicatorID): string[] {
  switch (id) {
    case 'MA': case 'EMA': case 'VOL': return defaultParams(id).map((_, i) => `周期${i + 1}`)
    case 'BOLL': return ['周期', '倍数']
    case 'MACD': return ['快', '慢', '信号']
    case 'RSI': return ['①', '②', '③']
    case 'KDJ': return ['周期', '快线', '慢线']
    case 'SRSI': return ['相对强弱', '随机周期', '快线', '慢线']
    case 'ATR': return ['周期']
    case 'ST': return ['周期', '倍数']
    case 'DMI': return ['周期']
    case 'VWAP': case 'SAR': case 'ORDERFLOW': case 'CVD': case 'OI': case 'LSR': case 'TAKER': case 'BASIS': return []
  }
}

/** 每条线的名字，图例里用。顺序与 IndicatorResult.lines 一致。 */
export function lineNames(id: IndicatorID, params: readonly number[]): string[] {
  switch (id) {
    case 'MA': case 'EMA': return params.map(p => `${NAME[id]}${p}`)
    case 'BOLL': return ['中轨', '上轨', '下轨']
    case 'VOL': return params.map(p => `均量${p}`)
    case 'MACD': return ['差值', '信号']
    case 'RSI': return params.map(p => `强弱${p}`)
    case 'KDJ': return ['快线', '慢线', '敏感线']
    case 'SRSI': return ['快线', '慢线']
    case 'ATR': return ['真实波幅']
    case 'OI': return ['持仓量']
    case 'LSR': return ['多空比']
    case 'TAKER': return ['买卖比']
    case 'BASIS': return ['基差率']
    // 超级趋势与抛物线转向都只有一条线，多空靠 IndicatorResult.dir 换色。
    case 'VWAP': return ['当日均价']
    case 'ST': return ['超级趋势']
    case 'SAR': return ['转向点']
    case 'ORDERFLOW': return ['主力']
    case 'DMI': return ['多头动向', '空头动向', '趋势强度']
    case 'CVD': return ['量差']
  }
}

/**
 * 这把主图指标从调色板（六格）的第几格开始取色：均线 0/1/2、指数均线 3/4、当日VWAP 5。
 * 超级趋势与抛物线转向按多空用皮肤涨跌色，不占调色板。
 */
export function paletteOffset(id: IndicatorID): number {
  switch (id) {
    case 'EMA': return 3
    case 'VWAP': return 5
    default: return 0
  }
}

export type Plot = 'line' | 'dots'
/** 画成什么。抛物线转向一根一个点，连起来就错了。 */
export function plot(id: IndicatorID): Plot { return id === 'SAR' ? 'dots' : 'line' }

/**
 * 锁死的纵轴区间。RSI 与 StochRSI 锁 0–100；KDJ 不锁（J 常年冲出 0–100）；
 * 多空比 / 买卖比 / 基差 / 动向也不锁，靠 guides 上的基准线读方向。
 */
export function fixedScale(id: IndicatorID): { lo: number; hi: number } | null {
  switch (id) {
    case 'RSI': case 'SRSI': return { lo: 0, hi: 100 }
    default: return null
  }
}

/** 参考线。RSI 30/70，KDJ 与 StochRSI 20/80，多空比 / 买卖比 1，基差 / 量差 0，动向 25。 */
export function guides(id: IndicatorID): number[] {
  switch (id) {
    case 'RSI': return [30, 70]
    case 'KDJ': case 'SRSI': return [20, 80]
    case 'LSR': case 'TAKER': return [1.0]
    case 'BASIS': case 'CVD': return [0]
    case 'DMI': return [25]
    default: return []
  }
}

/** 主图默认 MA；副图默认 MACD + RSI（§3.2，定死）。 */
export const defaultOverlays: readonly IndicatorID[] = ['MA']
export const defaultSubs: readonly IndicatorID[] = ['MACD', 'RSI']

/** Swift `[Int].max()`：空数组给 null。 */
function maxOf(a: readonly number[]): number | null {
  if (!a.length) return null
  let m = a[0]
  for (let i = 1; i < a.length; i++) if (a[i] > m) m = a[i]
  return m
}

/** 增量重算要回头算多少根：最长参数 + 1（§5.7）。 */
export function tailBars(id: IndicatorID, params: readonly number[]): number {
  const maxParam = maxOf(params) ?? 1
  switch (id) {
    case 'SRSI': return (params.length > 0 ? params[0] : 14) + (params.length > 1 ? params[1] : 14) + maxParam + 1
    case 'MACD': return (maxOf(params) ?? 26) * 2 + 1
    default: return maxParam + 1
  }
}

/** 一个指标算出来的东西。 */
export class IndicatorResult {
  /** 画成线的那些列，顺序与 lineNames 一致。 */
  lines: number[][]
  /** MACD 的柱；别的指标是 null。 */
  histogram: number[] | null
  /** 逐根的多空方向（> 0 多、< 0 空、NaN 不着色），只有超级趋势与抛物线转向给。 */
  dir: number[] | null

  constructor(lines: number[][], histogram: number[] | null = null, dir: number[] | null = null) {
    this.lines = lines
    this.histogram = histogram
    this.dir = dir
  }

  /** 第 i 根上每条线的值，图例用；越界或不是整数下标给 NaN。 */
  values(i: number): number[] {
    return this.lines.map(l => (Number.isInteger(i) && i >= 0 && i < l.length ? l[i] : NaN))
  }
}

// ---------------------------------------------------------------- OINotice.swift

/** 持仓量副图空着（这一屏一个有限值都没有）时那一行小字。 */
export const OINotice = {
  /** 当前行情线路（OKX 兜底）根本不报持仓量。 */
  routeMissing: '当前线路不提供持仓量',
  /** 请求还在路上。 */
  loading: '持仓量加载中',
  /** 问到了，这一段就是没有。 */
  empty: '这一段没有持仓量数据',
} as const
export type OINotice = (typeof OINotice)[keyof typeof OINotice]

export function oiNoticeForEmptyPane(routeSupportsOI: boolean, loaded: boolean): OINotice {
  if (!routeSupportsOI) return OINotice.routeMissing
  return loaded ? OINotice.empty : OINotice.loading
}
