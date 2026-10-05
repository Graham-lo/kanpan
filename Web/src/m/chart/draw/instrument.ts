// 移植自 KanpanCore/Sources/KanpanCore/Model/InstrumentID.swift（只取画线存档要的 `canonical`）
//
// 美元指数在网页里存的是裸代号 DXY，规范键是 macro/index/DXY（见 market/macro.ts）。
// 画线按品种分桶，桶键是规范写法「venue/market/SYMBOL」；只写代号的老键一律算币安 U 本位。

export const DEFAULT_VENUE = 'binance'
export const DEFAULT_MARKET = 'usd_m'

/** Swift `InstrumentID.canonical(_:)`。空白串 → ""。 */
export function canonicalInstrument(value: string): string {
  const trimmed = value.trim()
  if (trimmed === '') return ''
  const parts = trimmed.split('/')
  if (parts.length === 3) return `${parts[0].toLowerCase()}/${parts[1].toLowerCase()}/${parts[2].toUpperCase()}`
  if (trimmed.toUpperCase() === 'DXY') return 'macro/index/DXY'
  return `${DEFAULT_VENUE}/${DEFAULT_MARKET}/${trimmed.toUpperCase()}`
}
