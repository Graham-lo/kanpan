/* Hkline Web · 图表数据导出 CSV
 *
 * 导当前格子的 K 线：可见范围或全部已加载。列：时间（上海时区 ISO 8601）、开高低收、成交量、成交额、
 * 主动买入额（交易所给了才有）、以及这一格当前挂着的主图 / 副图指标各条线（列名中文，带参数）。
 * 文件 UTF-8 带 BOM（Excel 直接双击打开不乱码），行尾 CRLF；文件名「品种_周期_起_止.csv」。
 * buildCsv 是纯函数（单测直接喂 K 线和指标线）；exportChart 从图上取数并让浏览器下载。
 */
import { Calc, CATALOG, MAIN_IDS, type Bar, type CalcId, type IndicatorId, type Series } from './calc'
import { mainOn } from './mainIndicators'
import type { TVChart } from './chart'

/** 一条指标线一列 */
export interface CsvColumn { name: string; values: Series }
export interface CsvInput {
  bars: readonly Bar[]
  /** 价格小数位（开高低收按它出，指标多给四位） */
  dec: number
  columns?: CsvColumn[]
}

const SH = 8 * 3600e3
const p2 = (n: number): string => String(n).padStart(2, '0')
/** 上海时区的 ISO 8601：2026-10-07T08:00:00+08:00 */
export function shIso(t: number): string {
  const d = new Date(t + SH)
  return `${d.getUTCFullYear()}-${p2(d.getUTCMonth() + 1)}-${p2(d.getUTCDate())}T${p2(d.getUTCHours())}:${p2(d.getUTCMinutes())}:${p2(d.getUTCSeconds())}+08:00`
}
/** 文件名里的时刻：20261007-0800（上海） */
export function shStamp(t: number): string {
  const d = new Date(t + SH)
  return `${d.getUTCFullYear()}${p2(d.getUTCMonth() + 1)}${p2(d.getUTCDate())}-${p2(d.getUTCHours())}${p2(d.getUTCMinutes())}`
}
/** 数字：最多 d 位小数、去掉尾零；空值 / 非数留空 */
export function num(v: number | null | undefined, d: number): string {
  if (v == null || !Number.isFinite(v)) return ''
  const s = v.toFixed(Math.max(0, Math.min(12, d)))
  return s.includes('.') ? s.replace(/\.?0+$/, '') : s
}
const cell = (s: string): string => (/[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s)

export function buildCsv({ bars, dec, columns = [] }: CsvInput): string {
  const hasBase = bars.some(b => b.bv != null && Number.isFinite(b.bv))
  const hasTaker = bars.some(b => b.tb != null && Number.isFinite(b.tb) && b.tb > 0)
  const head = ['时间', '开盘', '最高', '最低', '收盘', ...(hasBase ? ['成交量'] : []), '成交额', ...(hasTaker ? ['主动买入额'] : []), ...columns.map(c => c.name)]
  const vd = Math.max(dec + 4, 6)
  const lines = [head.map(cell).join(',')]
  bars.forEach((b, i) => {
    lines.push([
      shIso(b.t), num(b.o, dec), num(b.h, dec), num(b.l, dec), num(b.c, dec),
      ...(hasBase ? [num(b.bv, 8)] : []), num(b.v, 2), ...(hasTaker ? [num(b.tb, 2)] : []),
      ...columns.map(c => num(c.values[i], vd)),
    ].map(cell).join(','))
  })
  return '﻿' + lines.join('\r\n') + '\r\n'
}

/** 几个老指标的线名（目录里没带 labels 的） */
const LINE_NAMES: Partial<Record<IndicatorId, string[]>> = {
  boll: ['中轨', '上轨', '下轨'],
  macd: ['快线', '慢线', '柱'],
  kdj: ['K', 'D', 'J'],
}
/** 一个指标的各列：列名「中文名 + 线名 / 周期」，单线带参数；不是逐根对齐的输出（成交量分布这类）不导 */
export function indicatorColumns(id: CalcId, series: readonly Series[], n: number, params: { periods?: number[] } & Record<string, unknown> | undefined): CsvColumn[] {
  const cat = CATALOG[id]; if (!cat) return []
  const base = cat.cn || cat.name
  const ok = series.filter(s => s.length === n)
  if (!ok.length || ok.length !== series.length) return []
  const names = LINE_NAMES[id] ?? cat.labels
  const ptxt = params && !params.periods ? Object.values(params).filter(v => typeof v === 'number').join(',') : ''
  return series.map((values, k) => {
    const lab = names?.[k] || (params?.periods?.[k] != null ? String(params.periods[k]) : series.length > 1 ? String(k + 1) : '')
    const tail = lab ? ` ${lab}` : ptxt ? `(${ptxt})` : ''
    return { name: `${base}${tail}`, values }
  })
}

/** 这一格挂着的主图 / 副图指标（含降级收掉没算的副图：这里补算一遍） */
export function chartColumns(chart: TVChart): CsvColumn[] {
  const n = chart.bars.length, out: CsvColumn[] = [], series = chart.series
  const env = chart.calcEnv()
  const ids: CalcId[] = [...MAIN_IDS.filter(id => mainOn(chart.ind, id)), ...chart.ind.subs]
  for (const id of ids) {
    if (!Calc[id]) continue
    const ser = series[id] ?? Calc[id](chart.bars, chart.params[id], env)
    out.push(...indicatorColumns(id, ser, n, chart.params[id] as never))
  }
  // 同名列（两条线名字一样）加序号，表头不重复
  const seen = new Map<string, number>()
  for (const c of out) { const k = (seen.get(c.name) ?? 0) + 1; seen.set(c.name, k); if (k > 1) c.name = `${c.name} ${k}` }
  return out
}

export type ExportRange = 'visible' | 'all'
/** 取范围 → 生成 → 下载；返回导了几根（没有 K 线返回 0） */
export function exportChart(chart: TVChart, symbol: string, ivKey: string, range: ExportRange): { rows: number; name: string } {
  const all = chart.bars
  if (!all.length) return { rows: 0, name: '' }
  let from = 0, to = all.length - 1
  if (range === 'visible') { const v = chart.visible(); from = Math.max(0, v.from); to = Math.min(all.length - 1, v.to) }
  if (to < from) return { rows: 0, name: '' }
  const cols = chartColumns(chart).map(c => ({ name: c.name, values: c.values.slice(from, to + 1) }))
  const bars = all.slice(from, to + 1)
  const csv = buildCsv({ bars, dec: chart.meta.dec, columns: cols })
  const name = csvFileName(symbol, ivKey, bars[0].t, bars[bars.length - 1].t)
  const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }))
  const a = document.createElement('a')
  a.href = url; a.download = name
  document.body.appendChild(a); a.click(); a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 2000)
  return { rows: bars.length, name }
}
export const csvFileName = (symbol: string, iv: string, t0: number, t1: number): string => `${symbol}_${iv}_${shStamp(t0)}_${shStamp(t1)}.csv`
