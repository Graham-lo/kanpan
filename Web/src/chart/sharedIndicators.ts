/* Hkline Web · 三端共用的指标名与出厂参数
 *
 * 唯一的一份在 KanpanCore/Sources/KanpanCore/Indicator/indicators.json（键是 iOS 的 IndicatorID rawValue，
 * 每项 { name, params }）；iOS（IndicatorID.name / defaultParams）、手机网页（m/indicator/ids.ts）与这里读的都是它。
 * 电脑网页的参数是带键的对象（{ fast, slow, signal } 这种），这里按每个指标一张键表把 JSON 的数组翻过来；
 * 电脑网页独有的额外参数（动向指标的 ADX 平滑 m1 等）由调用方作为 extras 传进来，JSON 里有的键以 JSON 为准。
 * 只从 calc.ts 拿类型，运行时不反向依赖它。
 */
import catalogJson from '../../../KanpanCore/Sources/KanpanCore/Indicator/indicators.json'
import type { IndParams } from './calc'

/** 三端都有的那几只（电脑网页的 id） */
export type SharedPcId =
  | 'ma' | 'ema' | 'boll' | 'vol' | 'macd' | 'rsi' | 'kdj' | 'oi'
  | 'vwap' | 'st' | 'sar' | 'stochrsi' | 'atr' | 'cvd' | 'dmi'

interface Link {
  /** indicators.json 里的键（iOS rawValue） */
  ios: string
  /** JSON 参数数组 → 电脑网页参数对象：'periods' = 整串当周期列表；键表 = 按位取；null = 电脑网页这只没有可调参数 */
  keys: 'periods' | (keyof IndParams)[] | null
}

const LINK: Record<SharedPcId, Link> = {
  ma: { ios: 'MA', keys: 'periods' },
  ema: { ios: 'EMA', keys: 'periods' },
  boll: { ios: 'BOLL', keys: ['n', 'k'] },
  vol: { ios: 'VOL', keys: null }, // 电脑网页的成交量是主图叠加柱，不带均量线
  macd: { ios: 'MACD', keys: ['fast', 'slow', 'signal'] },
  rsi: { ios: 'RSI', keys: ['n'] }, // 电脑网页的 RSI 只画一条，取列表第一个周期
  kdj: { ios: 'KDJ', keys: ['n', 'm1', 'm2'] },
  oi: { ios: 'OI', keys: [] },
  vwap: { ios: 'VWAP', keys: [] },
  st: { ios: 'ST', keys: ['n', 'k'] },
  sar: { ios: 'SAR', keys: [] },
  stochrsi: { ios: 'SRSI', keys: ['n', 'stoch', 'm1', 'm2'] },
  atr: { ios: 'ATR', keys: ['n'] },
  cvd: { ios: 'CVD', keys: [] },
  dmi: { ios: 'DMI', keys: ['n'] },
}

type Entry = { name: string; params: number[] }
const JSON_CATALOG = catalogJson as Record<string, Entry>

function entry(id: SharedPcId): Entry {
  const e = JSON_CATALOG[LINK[id].ios]
  if (!e) throw new Error(`indicators.json 缺 ${LINK[id].ios}`)
  return e
}

/** 三端统一的显示名 */
export function sharedName(id: SharedPcId): string { return entry(id).name }

/** 三端统一的出厂参数（翻成电脑网页的参数对象）；电脑网页这只没有参数时返回 undefined */
export function sharedParams(id: SharedPcId, extras: IndParams = {}): IndParams | undefined {
  const keys = LINK[id].keys, arr = entry(id).params
  if (keys === null) return undefined
  // 共用的键排在前面、电脑网页独有的跟在后面：参数框与图例（Object.values 顺序）照这个次序摆
  if (keys === 'periods') return { periods: [...arr], ...extras }
  if (arr.length < keys.length) throw new Error(`indicators.json ${LINK[id].ios} 参数不够 ${keys.length} 个`)
  const out: Record<string, number | number[]> = {}
  keys.forEach((k, i) => { out[k] = arr[i] })
  for (const [k, v] of Object.entries(extras)) if (!(k in out) && v != null) out[k] = v
  return out as IndParams
}

/** 名字 + 参数一起给目录用：`{ ...shared('macd'), cn, place, colors }` */
export function shared(id: SharedPcId, extras?: IndParams): { name: string; params?: IndParams } {
  const params = sharedParams(id, extras)
  return params ? { name: sharedName(id), params } : { name: sharedName(id) }
}

export const SHARED_PC_IDS = Object.keys(LINK) as SharedPcId[]
