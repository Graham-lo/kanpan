/* 手机网页版 · 徽章记号的形状与生成规则
 *
 * 照 Kanpan/Kanpan/Main/CoinBadge.swift（CoinSpec / 品类记号 / material / spare）与
 * CoinBadgeGenerated.swift（长尾标：12 外形 × 24 内芯，FNV-1a 散列）。
 * 这一层只有数据与纯函数，不碰 DOM；怎么画在 badge.ts。
 */

/** 一层笔画：给了 stroke 就描边（24 格坐标系里声明的宽度），没给就填充 */
export interface Part { d: string[]; stroke: number | null }
export type Mark = { text: string } | { parts: Part[] }
export interface CoinSpec { from: string; to: string; mark: Mark; inset: number }

export const part = (d: string[], w: number | null): Part => ({ d, stroke: w })
export const parts = (list: Part[]): Mark => ({ parts: list })
export const fill = (d: string[]): Mark => ({ parts: [part(d, null)] })
export const stroke = (d: string[], w: number): Mark => ({ parts: [part(d, w)] })
export const text = (s: string): Mark => ({ text: s })
export const spec = (from: string, to: string, mark: Mark, inset = 0.62): CoinSpec => ({ from, to, mark, inset })

// ---- 品类记号（实物商品共用：画的是这块东西本身）
/** 金砖：贵金属、XAUT、PAXG、铜 */
export const INGOT = stroke(['M8.6 7.4h6.8l4 9.2H4.6z', 'M7.6 11h8.8'], 2.1)
/** 油滴：原油（CL / BZ）与其它大宗 */
export const DROP = stroke(['M12 4.2c3.9 4.7 5.9 7.7 5.9 10.1a5.9 5.9 0 0 1-11.8 0c0-2.4 2-5.4 5.9-10.1z'], 2.1)
/** 火苗：天然气 */
export const FLAME = stroke(['M12 3.4c3.2 3.4 5.1 6.1 5.1 8.9a5.1 5.1 0 0 1-10.2 0c0-1.8.6-3.2 1.8-4.6 .2 1.4.8 2.3 1.8 2.8-.4-2.8.4-5.3 1.5-7.1z'], 2.1)

export const PRECIOUS = new Set(['XAU', 'XAG', 'XPT', 'XPD'])
export const GOLD_TOKENS = new Set(['XAUT', 'PAXG'])
export const OILS = new Set(['CL', 'BZ'])
export const GAS = new Set(['NATGAS'])
export const COPPER = new Set(['COPPER'])

/** 材料该是材料的颜色：这几支不参与散列 */
export const MATERIAL: Record<string, [string, string]> = {
  XAU: ['#F5D07A', '#C08A1E'], XAG: ['#C3CCD6', '#6E7B8A'],
  XPT: ['#D6E0E4', '#7B8B93'], XPD: ['#CBD4CF', '#73827B'],
  XAUT: ['#F5D07A', '#C08A1E'], PAXG: ['#F2CE85', '#B8862A'],
  COPPER: ['#E3A778', '#A9552A'],
  CL: ['#5A6672', '#232B33'], BZ: ['#6B7784', '#2C343D'],
  NATGAS: ['#7FC8E8', '#2C7BA8'],
}

/** 认不出来的：散列到八对备用渐变里的一对 */
export const SPARE: [string, string][] = [
  ['#B9B3C6', '#6E6880'], ['#8FC7C0', '#3E8178'], ['#E8B98C', '#B87333'],
  ['#9FB8E8', '#4C6CB5'], ['#D7A8C8', '#95568A'], ['#A9C98C', '#5E8A45'],
  ['#E0C27A', '#A8812C'], ['#93BCD4', '#3D7391'],
]

/** spare 的下标：key 的 UTF-8 字节 reduce((h*31+b) % 8)，照 Swift */
export function spareIndex(key: string): number {
  let h = 0
  for (const b of new TextEncoder().encode(key)) h = (h * 31 + b) % SPARE.length
  return h
}

export const OUTERS: Part[] = [
  part(["M12 4.6a7.4 7.4 0 1 1 0 14.8 7.4 7.4 0 0 1 0-14.8z"], 2.1),
  part(["M12 4.2l6.9 4v8L12 20.2l-6.9-4v-8z"], 2.1),
  part(["M7.2 4.9h9.6a2.3 2.3 0 0 1 2.3 2.3v9.6a2.3 2.3 0 0 1-2.3 2.3H7.2a2.3 2.3 0 0 1-2.3-2.3V7.2a2.3 2.3 0 0 1 2.3-2.3z"], 2.1),
  part(["M12 3.9l8.1 8.1-8.1 8.1L3.9 12z"], 2.1),
  part(["M12 4.2l6.6 2.5v5c0 3.9-2.7 6.6-6.6 8.3-3.9-1.7-6.6-4.4-6.6-8.3v-5z"], 2.1),
  part(["M8.9 4.4h6.2l3.9 3.9v6.2l-3.9 3.9H8.9L5 14.5V8.3z"], 2.1),
  part(["M16.8 6.4a7.3 7.3 0 1 0 2.6 4.2"], 2.2),
  part(["M12 4.1l7.5 5.45-2.87 8.85H7.37L4.5 9.55z"], 2.1),
  part(["M12 4.6a4.6 4.6 0 0 1 4.6 4.6v5.6a4.6 4.6 0 0 1-9.2 0V9.2A4.6 4.6 0 0 1 12 4.6z"], 2.1),
  part(["M8.1 5.6h7.8l3.9 6.4-3.9 6.4H8.1L4.2 12z"], 2.1),
  part(["M4.9 19.1v-7.1a7.1 7.1 0 0 1 14.2 0v7.1"], 2.2),
  part(["M6.4 6.6h11.2a2.2 2.2 0 0 1 2.2 2.2v6.4a2.2 2.2 0 0 1-2.2 2.2H6.4a2.2 2.2 0 0 1-2.2-2.2V8.8a2.2 2.2 0 0 1 2.2-2.2z"], 2.1),
]

export const CORES: Part[] = [
  part([], null),
  part(["M12 9.2a2.8 2.8 0 1 1 0 5.6 2.8 2.8 0 0 1 0-5.6z"], null),
  part(["M9.4 9.4h5.2v5.2H9.4z"], null),
  part(["M12 9.1l2.9 2.9-2.9 2.9L9.1 12z"], null),
  part(["M9.2 11h5.6v2H9.2z"], null),
  part(["M11 9.2h2v5.6h-2z"], null),
  part(["M11 9.2h2v5.6h-2z", "M9.2 11h5.6v2H9.2z"], null),
  part(["M10.6 10.7a1.3 1.3 0 1 1 0 2.6 1.3 1.3 0 0 1 0-2.6z", "M13.4 10.7a1.3 1.3 0 1 1 0 2.6 1.3 1.3 0 0 1 0-2.6z"], null),
  part(["M12 9.3a1.3 1.3 0 1 1 0 2.6 1.3 1.3 0 0 1 0-2.6z", "M12 12.1a1.3 1.3 0 1 1 0 2.6 1.3 1.3 0 0 1 0-2.6z"], null),
  part(["M9.8 10.85a1.15 1.15 0 1 1 0 2.3 1.15 1.15 0 0 1 0-2.3z", "M12 10.85a1.15 1.15 0 1 1 0 2.3 1.15 1.15 0 0 1 0-2.3z", "M14.2 10.85a1.15 1.15 0 1 1 0 2.3 1.15 1.15 0 0 1 0-2.3z"], null),
  part(["M12 8.7a1.2 1.2 0 1 1 0 2.4 1.2 1.2 0 0 1 0-2.4z", "M9.8 12.9a1.2 1.2 0 1 1 0 2.4 1.2 1.2 0 0 1 0-2.4z", "M14.2 12.9a1.2 1.2 0 1 1 0 2.4 1.2 1.2 0 0 1 0-2.4z"], null),
  part(["M10.3 9.15a1.15 1.15 0 1 1 0 2.3 1.15 1.15 0 0 1 0-2.3z", "M13.7 9.15a1.15 1.15 0 1 1 0 2.3 1.15 1.15 0 0 1 0-2.3z", "M10.3 12.55a1.15 1.15 0 1 1 0 2.3 1.15 1.15 0 0 1 0-2.3z", "M13.7 12.55a1.15 1.15 0 1 1 0 2.3 1.15 1.15 0 0 1 0-2.3z"], null),
  part(["M12 9.2l3 5.6H9z"], null),
  part(["M9 9.2h6L12 14.8z"], null),
  part(["M12 9.2l3 5.6h-1.9L12 12.4l-1.1 2.4H9z"], null),
  part(["M10.2 14.8L12.9 9.2h1.5L11.7 14.8z"], null),
  part(["M9.8 9.2h2v3.6h3.2v2H9.8z"], null),
  part(["M12 9.4a2.6 2.6 0 1 1 0 5.2 2.6 2.6 0 0 1 0-5.2z"], 2),
  part(["M9.2 10h5.6v1.7H9.2z", "M9.2 12.8h5.6v1.7H9.2z"], null),
  part(["M12 9.2a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3z", "M9.4 13.3h5.2v1.6H9.4z"], null),
  part(["M9.4 9.4h5.2l-5.2 5.4h5.2"], 2),
  part(["M9.2 13.8l1.9-2.6 1.8 1.8 1.9-2.8"], 2),
  part(["M12 9.2a2.8 2.8 0 0 1 0 5.6z"], null),
  part(["M12 9.2v5.6", "M9.6 10.6l4.8 2.8", "M14.4 10.6l-4.8 2.8"], 1.9),
]

const MASK64 = (1n << 64n) - 1n
/** FNV-1a 64 位，末尾 h ^= h >> 33，取低 31 位（照 CoinBadgeGenerated.scatter） */
export function scatter(key: string, salt: number): number {
  let h = (0xcbf29ce484222325n + BigInt(salt)) & MASK64
  for (const b of new TextEncoder().encode(key)) h = ((h ^ BigInt(b)) * 0x100000001b3n) & MASK64
  h ^= h >> 33n
  return Number(h & 0x7fffffffn)
}

/** 长尾标：代号决定外形、内芯；配色由调用方给 */
export function generated(key: string, pair: [string, string]): CoinSpec {
  const outer = OUTERS[scatter(key, 0x9e37) % OUTERS.length]
  const core = CORES[scatter(key, 0x85eb) % CORES.length]
  return { from: pair[0], to: pair[1], mark: parts([outer, core]), inset: 0.58 }
}

/** 倍数前缀剥掉再认（照 SymbolAliases.key）：1 后跟三个以上 0，或 1M（剩余 ≥ 3 位） */
export function aliasKey(base: string): string {
  const upper = base.toUpperCase()
  const digits = /^[0-9]*/.exec(upper)![0]
  let rest = upper.slice(digits.length)
  if (digits === '1' && rest[0] === 'M' && rest.length >= 3) rest = rest.slice(1)
  else if (!(digits.length >= 4 && /^10+$/.test(digits))) return upper
  return rest ? rest : upper
}
