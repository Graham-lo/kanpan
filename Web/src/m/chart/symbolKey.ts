// 手机网页版 · 品种键归一（2026-10-08 多交易所）。图表这一层原来拿 toUpperCase() 归一裸代号，
// 别家的完整键（okx/usd_m/BTCUSDT）大写之后就对不上了：一律走这里。只依赖 market/identity（纯函数）。
import { keyOf } from '../../market/identity'

/** 任何写法 → 网页里存的规范键：裸代号大写（币安 / DXY）；完整键 venue / market 小写、代号大写，
 *  binance/usd_m/X 回裸代号、macro/index/DXY 回 DXY。空白串 → '' */
export function normKey(raw: string): string {
  const t = raw.trim()
  if (!t) return ''
  const p = t.split('/')
  if (p.length === 3 && p.every(Boolean)) return keyOf(p[0].toLowerCase(), p[1].toLowerCase(), p[2].toUpperCase())
  return t.toUpperCase()
}
