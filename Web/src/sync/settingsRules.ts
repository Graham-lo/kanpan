/* Hkline 网页 · settings 字段的通用值规则（读契约，不手写）
 *
 * 母表是 iOS 的 `PrefsFieldPlan.rules`（Kanpan/Kanpan/Settings/Model/PrefsFieldRules.swift），`make sync-contract`
 * 把它连同按规则造出来的正反样例写进 Backend/kanpan-api/contract/settings-fields.json 的 `rules`。
 * 服务端 `settings_rules.rs` 按同一份校验，这里按同一份清洗——三边的值规则只有一份（2026-10-10「同步字段解耦」）。
 *
 * `custom` 的那几个（对比品种、订单流门槛、学到的结论、指标参数 / 颜色 / 副图高）通用描述装不下，
 * 清洗仍在 m/app/prefs.ts 手写；这里的 `cleanByRule` 碰到它们直接退回出厂值，调用方别拿它洗 custom 字段。
 *
 * 读法与服务端一致，唯一的差别是客户端可以更严、不能更宽（更宽就是推上去被拒）：
 *   - interval / intervals 只认现行周期，不认服务端为老存档留着的 legacyIntervals（8h / 3d）；
 *   - string 带 known 的只认 known 里的那几个（服务端只看长度）；
 *   - stringArray 一律去重（服务端只在 unique 时查重）；countMap 丢掉 0 次的键。
 */

import contract from '../../../Backend/kanpan-api/contract/settings-fields.json'
import instruments from '../../../Backend/kanpan-api/contract/instruments.json'

/** 契约 `rules.<字段>` 的形状（与 Swift `SettingsFieldContract.RuleDoc` 同名同义；样例只给测试用） */
export type FieldRule =
  | { type: 'bool' }
  | { type: 'enum'; values: string[] }
  | { type: 'string'; maxBytes: number; known?: string[] }
  | { type: 'number'; min: number; max: number }
  | { type: 'int'; min: number; max: number }
  | { type: 'interval' }
  | { type: 'intervals'; maxCount: number }
  | { type: 'stringArray'; values: string[]; maxCount: number; unique?: boolean }
  | { type: 'countMap'; keys: string[]; maxKeys: number; max: number }
  | { type: 'custom'; name: string }

export type RuleDoc = FieldRule & { accept?: unknown[]; reject?: unknown[] }

/** 契约里全部字段的规则（含样例） */
export const RULES: Readonly<Record<string, RuleDoc>> = (contract as unknown as { rules: Record<string, RuleDoc> }).rules

/** 现行周期（instruments.json 的 intervals）；服务端另收的 legacyIntervals 客户端不认 */
const CURRENT_INTERVALS: readonly string[] = instruments.intervals
/** 服务端认的周期：现行 + 老存档里的 8h / 3d（`instruments::is_synced_interval`） */
const SERVER_INTERVALS: readonly string[] = [...instruments.intervals, ...instruments.legacyIntervals]

/** 这个字段在契约里的规则；契约里没有（网页独有的、退役的）是 undefined */
export function ruleOf(field: string): RuleDoc | undefined { return Object.prototype.hasOwnProperty.call(RULES, field) ? RULES[field] : undefined }

const utf8 = (s: string): number => new TextEncoder().encode(s).length
const isRecord = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v)

/** **服务端**收不收这个值（与 `settings_rules::Rule::accepts` 逐项相同）。custom 一律 false——那几个看手写函数 */
export function accepts(rule: FieldRule, v: unknown): boolean {
  switch (rule.type) {
    case 'bool': return typeof v === 'boolean'
    case 'enum': return typeof v === 'string' && rule.values.includes(v)
    case 'string': return typeof v === 'string' && utf8(v) <= rule.maxBytes
    case 'number': return typeof v === 'number' && Number.isFinite(v) && v >= rule.min && v <= rule.max
    case 'int': return Number.isInteger(v) && (v as number) >= rule.min && (v as number) <= rule.max
    case 'interval': return typeof v === 'string' && SERVER_INTERVALS.includes(v)
    case 'intervals': return Array.isArray(v) && v.length <= rule.maxCount && v.every(x => typeof x === 'string' && SERVER_INTERVALS.includes(x))
    case 'stringArray': return Array.isArray(v) && v.length <= rule.maxCount
      && v.every(x => typeof x === 'string' && rule.values.includes(x))
      && (!rule.unique || new Set(v).size === v.length)
    case 'countMap': return isRecord(v) && Object.keys(v).length <= rule.maxKeys
      && Object.entries(v).every(([k, n]) => rule.keys.includes(k) && Number.isInteger(n) && (n as number) >= 0 && (n as number) <= rule.max)
    case 'custom': return false
  }
}

/** 把任意来源（本机旧档、云端）的值洗成这条规则下**客户端认**的值；洗不出来退回 `fallback`。
 *  数夹到边上；数组滤掉认不出的、去重、截到 maxCount；计次表只留 1…max 的整数、按次数多到少留前 maxKeys 个；其余不合规则退回 fallback。 */
export function cleanByRule<T>(rule: FieldRule, v: unknown, fallback: T): T {
  switch (rule.type) {
    case 'bool': return (typeof v === 'boolean' ? v : fallback) as T
    case 'enum': return (typeof v === 'string' && rule.values.includes(v) ? v : fallback) as T
    case 'string': return (typeof v === 'string' && utf8(v) <= rule.maxBytes && (!rule.known || rule.known.includes(v)) ? v : fallback) as T
    case 'number': return (typeof v === 'number' && Number.isFinite(v) ? Math.min(rule.max, Math.max(rule.min, v)) : fallback) as T
    case 'int': return (typeof v === 'number' && Number.isFinite(v) ? Math.min(rule.max, Math.max(rule.min, Math.round(v))) : fallback) as T
    case 'interval': return (typeof v === 'string' && CURRENT_INTERVALS.includes(v) ? v : fallback) as T
    case 'intervals': return (Array.isArray(v) ? strings(v, CURRENT_INTERVALS, rule.maxCount) : fallback) as T
    case 'stringArray': return (Array.isArray(v) ? strings(v, rule.values, rule.maxCount) : fallback) as T
    case 'countMap': {
      if (!isRecord(v)) return fallback
      const kept = Object.entries(v)
        .filter((e): e is [string, number] => rule.keys.includes(e[0]) && Number.isInteger(e[1]) && (e[1] as number) > 0)
        .map(([k, n]) => [k, Math.min(n, rule.max)] as const)
        .sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
        .slice(0, rule.maxKeys)
      return Object.fromEntries(kept) as T
    }
    case 'custom': return fallback
  }
}

/** 按字段名洗（字段必须在契约里有通用规则；拿 custom 字段来洗是写错了，直接抛） */
export function cleanField<T>(field: string, v: unknown, fallback: T): T {
  const rule = ruleOf(field)
  if (!rule || rule.type === 'custom') throw new Error(`settingsRules: \`${field}\` 在契约里没有通用规则（${rule ? `custom:${rule.name}` : '不在契约里'}），清洗要手写`)
  return cleanByRule(rule, v, fallback)
}

function strings(v: unknown[], pool: readonly string[], maxCount: number): string[] {
  const out: string[] = []
  for (const x of v) if (typeof x === 'string' && pool.includes(x) && !out.includes(x)) out.push(x)
  return out.slice(0, maxCount)
}
