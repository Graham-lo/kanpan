/* Hkline Web · 指标对话框的清单：全部指标按类分组（均线 / 通道 / 趋势 / 动量 / 成交量），主图在前、副图在后，
 * 搜索按中文名、英文名或 id。对话框的开关、参数在 pages/chart.ts 的 openIndicators。 */
import { CATALOG, type IndicatorId } from '../chart/calc'
import { MORE_MAIN_IDS } from '../chart/mainIndicators'
import { OSC_CATALOG } from '../chart/oscillators'

export type IndGroup = '均线类' | '通道类' | '趋势类' | '动量类' | '成交量类'
export const IND_GROUPS: IndGroup[] = ['均线类', '通道类', '趋势类', '动量类', '成交量类']
export interface IndRow { id: IndicatorId; place: 'main' | 'sub'; name: string; group: IndGroup }

// 第三批副图（oscillators.ts）按 id 认类；认不出的归动量类
const VOLUME = new Set(['vol', 'vwap', 'vpvr', 'oi', 'cvd', 'whale', 'obv', 'mfi', 'cmf', 'chosc', 'efi', 'eom', 'pvt', 'volosc', 'klinger', 'ad', 'nv'])
const CHANNEL = new Set(['boll', 'kc', 'dc', 'env', 'atr', 'hv', 'stdev', 'bbw', 'bbpct', 'mass', 'rvi'])
const TREND = new Set(['st', 'ichi', 'keys', 'sar', 'vstop', 'alligator', 'fractals', 'zigzag', 'pivots', 'dmi', 'aroon', 'vortex', 'chop', 'trix', 'dpo', 'coppock', 'kst'])
const MA = new Set(['ma', 'ema', 'wma', 'hma', 'dema', 'tema', 'smma', 'vwma', 'lsma', 'alma', 'mcg'])

export function groupOf(id: string): IndGroup {
  if (MA.has(id)) return '均线类'
  if (VOLUME.has(id)) return '成交量类'
  if (CHANNEL.has(id)) return '通道类'
  if (TREND.has(id)) return '趋势类'
  return '动量类'
}

const MAIN_ORDER: IndicatorId[] = ['ma', 'ema', 'boll', 'vol', 'vwap', 'st', 'ichi', 'vpvr', 'keys', ...MORE_MAIN_IDS]
const SUB_ORDER: IndicatorId[] = ['macd', 'rsi', 'kdj', 'stochrsi', 'cci', 'wr', 'atr', 'oi', 'cvd', 'whale', 'obv']

/** 全部指标：先按类，类里主图在前、副图在后，各自保持目录顺序 */
export function indicatorRows(): IndRow[] {
  const oscIds = Object.keys(OSC_CATALOG).filter(id => !SUB_ORDER.includes(id as IndicatorId)) as IndicatorId[]
  const all: IndRow[] = [
    ...MAIN_ORDER.map((id): IndRow => ({ id, place: 'main', name: CATALOG[id].name, group: groupOf(id) })),
    ...[...SUB_ORDER, ...oscIds].filter(id => CATALOG[id]).map((id): IndRow => ({ id, place: 'sub', name: CATALOG[id].name, group: groupOf(id) })),
  ]
  return IND_GROUPS.flatMap(g => [...all.filter(r => r.group === g && r.place === 'main'), ...all.filter(r => r.group === g && r.place === 'sub')])
}

/** 搜索：中文名、英文名（目录 cn 里留的短名，如 MA 的「均线」）或 id，忽略大小写与空格 */
export function matchRow(r: IndRow, q: string): boolean {
  const k = q.toLowerCase().replace(/\s+/g, '')
  if (!k) return true
  const hay = [r.name, r.id, CATALOG[r.id]?.cn || ''].join('|').toLowerCase().replace(/\s+/g, '')
  return hay.includes(k)
}
