/* Hkline Web · 主力订单流 · 门槛、步长与判定常数（照 OrderFlowSettings.swift）
 *
 * 门槛按产品各一个、步长一个，是用户可改、随账号同步的指标设置（同步字段 orderFlowOverrides，
 * 契约见 Backend/kanpan-api/contract/settings-fields.json）；这里只有初始默认值。
 */
import type { BigOrder, Product, Thresholds } from './types'
import { PRODUCTS, isContract } from './types'

export const D = {
  confirmationSamples: 2,
  confirmationMs: 300,
  exitRatio: 0.5,
  filledRatio: 0.8,
  fillMatchMs: 5_000,
  retentionMs: 3 * 86_400_000,
  maxEndedOrders: 20_000,
  recentKeepMs: 2 * 3_600_000,
  trimRatio: 0.9,
  scanRadiusBps: 1_000,
  exitRadiusBps: 1_500,
  tradfiPerpetual: 2_000_000,
  calibrationBandBps: 100,
  calibrationFraction: 0.03,
  calibrationFloor: 50_000,
  calibrationCeiling: 2_000_000,
  calibrationTimeoutMs: 8_000,
  unknownTurnoverTier: 2,
} as const

const MAJORS: Record<string, { spot: number; perpetual: number; step: number }> = {
  BTC: { spot: 1_000_000, perpetual: 5_000_000, step: 100 },
  ETH: { spot: 1_000_000, perpetual: 5_000_000, step: 1 },
  SOL: { spot: 750_000, perpetual: 2_500_000, step: 0.1 },
}
export const TRADFI_STEPS: Record<string, number> = { MU: 1, SNDK: 1, SPCX: 1, SKHYNIX: 1, SKHY: 0.1, XAU: 1, XAG: 0.1 }
export const COIN_TIERS: { turnover: number; perpetual: number; spot: number }[] = [
  { turnover: 10_000_000_000, perpetual: 5_000_000, spot: 1_000_000 },
  { turnover: 2_000_000_000, perpetual: 2_500_000, spot: 750_000 },
  { turnover: 500_000_000, perpetual: 1_000_000, spot: 300_000 },
  { turnover: 100_000_000, perpetual: 500_000, spot: 150_000 },
  { turnover: 20_000_000, perpetual: 200_000, spot: 60_000 },
  { turnover: 0, perpetual: 100_000, spot: 30_000 },
]

export function tier(turnover24h: number | null | undefined): number {
  if (turnover24h == null || !Number.isFinite(turnover24h) || turnover24h < 0) return D.unknownTurnoverTier
  const i = COIN_TIERS.findIndex(t => turnover24h >= t.turnover)
  return i < 0 ? COIN_TIERS.length - 1 : i
}

export function needsCalibration(base: string, crypto: boolean): boolean {
  return !crypto && !MAJORS[base.toUpperCase()]
}

/** 就近取 1 / 2 / 5 × 10ⁿ（一样近取小的）。 */
export function round125(x: number): number {
  if (!Number.isFinite(x) || x <= 0) return x
  const e = Math.floor(Math.log10(x))
  const c: number[] = []
  for (const k of [e - 1, e, e + 1]) { const p = Math.pow(10, k); c.push(p, 2 * p, 5 * p) }
  let best = c[0], bd = Math.abs(x - best)
  for (const v of c.slice(1)) { const d = Math.abs(x - v); if (d < bd - 1e-9 * Math.max(1, v)) { best = v; bd = d } }
  return best
}

export function calibratedThreshold(depth: number): number {
  if (!Number.isFinite(depth)) return D.tradfiPerpetual
  if (depth <= 0) return D.calibrationFloor
  return Math.min(D.calibrationCeiling, Math.max(D.calibrationFloor, round125(D.calibrationFraction * depth)))
}

/** 一只 base 的默认门槛与步长（步长可能缺，等前一日收盘推）。 */
export function defaultThresholds(base: string, crypto: boolean, turnover24h: number | null, calibrated?: number | null): Thresholds {
  const b = base.toUpperCase()
  const m = MAJORS[b]
  if (!crypto && !m) {
    const t = calibrated != null && Number.isFinite(calibrated) && calibrated > 0 ? calibrated : D.tradfiPerpetual
    return { usdtPerp: t, step: TRADFI_STEPS[b] }
  }
  if (m) return { spot: m.spot, usdtPerp: m.perpetual, coinPerp: m.perpetual, delivery: m.perpetual, step: m.step }
  const t = COIN_TIERS[tier(turnover24h)]
  return { spot: t.spot, usdtPerp: t.perpetual, coinPerp: t.perpetual, delivery: t.perpetual }
}

// ------------------------------------------------------------ 用户改过的项（同步字段 orderFlowOverrides）

export interface Override { spot?: number; usdtPerp?: number; coinPerp?: number; delivery?: number; step?: number }
export const THRESHOLD_RANGE: [number, number] = [1_000, 1_000_000_000]
export const STEP_RANGE: [number, number] = [0.000_000_01, 1_000_000]
export const MAX_OVERRIDES = 200

/** 输入框里的金额：「100K」「2.5M」「50,000」→ 美元；空或不合法给 null（用默认）。 */
export function parseAmount(s: string): number | null {
  const m = s.trim().toUpperCase().replace(/[,\s$]/g, '').match(/^(\d+(?:\.\d+)?)([KMB])?$/)
  if (!m) return null
  const v = +m[1] * (m[2] ? ({ K: 1e3, M: 1e6, B: 1e9 } as Record<string, number>)[m[2]] : 1)
  return v > 0 && Number.isFinite(v) ? v : null
}

const inRange = (v: unknown, [lo, hi]: [number, number]): v is number => typeof v === 'number' && Number.isFinite(v) && v >= lo && v <= hi

/** 越界、非数的项丢掉（不夹到边上）；一项都不剩就是 null。 */
export function normalizeOverride(o: Override | null | undefined): Override | null {
  if (!o || typeof o !== 'object') return null
  const out: Override = {}
  for (const p of PRODUCTS) if (inRange(o[p], THRESHOLD_RANGE)) out[p] = o[p]
  if (inRange(o.step, STEP_RANGE)) out.step = o.step
  return Object.keys(out).length ? out : null
}

/** 叠上用户改过的项。不能给这只没有的产品凭空加门槛。 */
export function applyOverride(t: Thresholds, o: Override | null | undefined): Thresholds {
  const n = normalizeOverride(o)
  if (!n) return { ...t }
  const out: Thresholds = { ...t }
  for (const p of PRODUCTS) if (out[p] != null && n[p] != null) out[p] = n[p]
  if (n.step != null) out.step = n.step
  return out
}

export const productsOf = (t: Thresholds): Product[] => PRODUCTS.filter(p => t[p] != null)

// ------------------------------------------------------------ base 与缩放前缀（照 OrderFlowBase.normalize）

export const SCALED_PREFIXES: [string, number][] = [['1000000', 1_000_000], ['1000', 1000], ['1M', 1_000_000]]
export const isValidBase = (b: string): boolean => /^[A-Z0-9]{1,20}$/.test(b)

/** `1000PEPE` → PEPE × 1000；`1MBABYDOGE` → BABYDOGE × 1e6；其余原样 × 1。 */
export function normalizeBase(raw: string): { base: string; scale: number } {
  const upper = raw.toUpperCase()
  for (const [prefix, scale] of SCALED_PREFIXES) {
    if (!upper.startsWith(prefix)) continue
    const rest = upper.slice(prefix.length)
    if (isValidBase(rest) && !/^[0-9]/.test(rest)) return { base: rest, scale }
  }
  return { base: upper, scale: 1 }
}

/** 图上的合约代号（BTCUSDT、1000PEPEUSDT）→ 订单流的 base 与缩放。 */
export function baseOfSymbol(symbol: string): { base: string; scale: number } {
  return normalizeBase(symbol.toUpperCase().replace(/USDT$|USDC$/, ''))
}

// ------------------------------------------------------------ 显示开关（网页本机，不同步）

export interface Display {
  spot: boolean; contract: boolean
  filledBid: boolean; filledAsk: boolean
  cancelledBid: boolean; cancelledAsk: boolean
}
export const DISPLAY_ALL: Display = { spot: true, contract: true, filledBid: true, filledAsk: true, cancelledBid: true, cancelledAsk: true }

/** 这一单画不画（挂着的、失联结束的只看产品开关）。 */
export function shows(d: Display, o: BigOrder): boolean {
  if (!(isContract(o.product) ? d.contract : d.spot)) return false
  if (o.status === 'filled') return o.side === 'bid' ? d.filledBid : d.filledAsk
  if (o.status === 'cancelled') return o.side === 'bid' ? d.cancelledBid : d.cancelledAsk
  return true
}

// ------------------------------------------------------------------ 门槛设置第二层的位置

/** 第二层贴着的位置：指标面板的外框与订单流那一行 */
export interface SettingsAnchor { panel: Box; row: Box }
/** 只用到的几项（DOMRect 满足它；测试里给普通对象） */
export interface Box { top: number; right: number; height: number }

const LAYER_W = 520
const GAP = 12

/**
 * 第二层放哪：面板右边放得下就贴在右边、顶端和那一行对齐（上下夹在视口里）；放不下就盖在面板右半边。
 * 返回左上角与箭头离第二层顶端的距离。
 */
export function layerSpot(a: SettingsAnchor, h: number, vw: number, vh: number, w = LAYER_W): { left: number; top: number; arrow: number; inside: boolean } {
  const inside = a.panel.right + GAP + w > vw - 16
  const left = inside ? Math.max(16, a.panel.right - w - GAP) : a.panel.right + GAP
  const rowMid = a.row.top + a.row.height / 2
  const top = Math.round(Math.min(Math.max(16, rowMid - 28), Math.max(16, vh - h - 16)))
  return { left: Math.round(left), top, arrow: Math.round(Math.min(Math.max(16, rowMid - top), h - 16)), inside }
}
