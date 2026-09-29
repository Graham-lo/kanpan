/* Hkline Web · 复盘：服务端 /v1/native-review 的数据形状
 *
 * 字段照 kanpan-api（Rust）原样：价格、数量、金额在「交易回合」里是十进制字符串（交易所原文，
 * 不丢精度），在「观点记录」的规则里是数字；时间一律是毫秒时间戳（UTC），显示时再换成上海时间。
 */

/** 一段图表区间：start / end 都对齐到周期，bars = (end - start) / 周期 */
export interface ChartRange {
  venue: string
  market: string
  symbol: string
  interval: string
  start: number
  end: number
  bars: number
}

export type ViewDirection = 'long' | 'short' | 'observe'

export interface ViewRule {
  version: string
  direction: ViewDirection
  /** bar_close 收盘确认 · trade_touch 触价确认 */
  confirmation: 'bar_close' | 'trade_touch'
  reference: number
  target: number
  invalidation: number
  expires: number
}

export interface Assessment {
  /** waiting 等答案 · realized 判对 · unrealized 判错 · needs_verification 待核实 · observation 只记录 */
  outcome: string
  reason: string
  eventAt: number | null
  assessedAt: number
}

/** 观点记录（手机上「记一笔」写下的判断） */
export interface ViewRecord {
  draft: {
    id: string
    range: ChartRange
    rule: ViewRule
    text: string
    confidence: number | null
    /** chart_first 图在先 · thought_first 想法在先 · interwoven 两者交织 · unknown 不确定 */
    origin: string
    created: number
  }
  serverId: string | null
  submitted: number | null
  revision: number
  assessment: Assessment | null
  reflection?: { note: string; nextTime: string; publishedAt: number | null; revision: number } | null
  eligible: boolean
  voided: boolean
  groupPending?: boolean
}

/** 交易回合里的一笔成交 */
export interface Fill {
  id: string
  orderId: string
  time: number
  side: 'BUY' | 'SELL'
  positionSide: string
  price: string
  qty: string
  quoteQty: string
  commission: string
  commissionAsset: string
  realizedPnl: string
  maker: boolean
  /** open 开仓 · add 加仓 · reduce 减仓 · close 平仓 */
  role: string
  split: boolean
}

/** 一个交易回合：从开仓到仓位归零（服务端用成交拼出来的） */
export interface Round {
  id: string
  version: number
  venue: string
  market: string
  symbol: string
  accountTag: string
  positionSide: string
  direction: 'long' | 'short'
  status: 'open' | 'closed'
  quoteAsset: string
  openedAt: number
  closedAt: number | null
  holdingMs: number | null
  openAvgPrice: string
  closeAvgPrice: string | null
  openedQty: string
  closedQty: string
  maxQty: string
  peakNotional: string
  leverage: number | null
  realizedPnl: string
  commission: string
  commissionUnpriced?: boolean
  /** 资金费：正数是收到、负数是付出 */
  funding: string
  netPnl: string
  fills: Fill[]
  updatedAt: number
}

export interface AfterPoint { at: number; changePct: string; price: string }

/** 服务端给平掉的回合算的结果：持仓中最大浮盈浮亏、平仓后 1 / 4 / 24 小时的走势 */
export interface TradeResult {
  after: { h1: AfterPoint | null; h4: AfterPoint | null; h24: AfterPoint | null }
  chart: { interval: string; start: number; end: number } | null
  computedAt: number
  excursion: {
    maxFavorable: string
    maxFavorableAt: number
    maxFavorablePct: string
    maxAdverse: string
    maxAdverseAt: number
    maxAdversePct: string
    rewardRisk: string
  } | null
  unavailable?: Record<string, unknown>
  version: number
}

export interface TradeRecord {
  kind: 'trade'
  id: string
  revision: number
  submitted: number
  updated: number
  voided: boolean
  round: Round
  result: TradeResult | null
  note: { text: string; updatedAt: number } | null
}

export interface StatGroup {
  id: string
  title: string
  correct: number
  total: number
  /** insufficient 样本不足 · verdict_due 够格给结论 · observing 观察中 */
  verdictStatus?: string
  /** 最近十笔明显比整体差，服务端要人回头看一眼 */
  recheck?: boolean
}

/** 证据里每一组的判定（内层键是蛇形，照服务端原样） */
export interface StatProofGroup { denominator?: number; numerator?: number; verdict_status?: string; recheck?: boolean; title?: string }
export interface StatProof { compatible_groups?: Record<string, StatProofGroup> }

export interface Statistics {
  groups: StatGroup[]
  /** 相对口径（同方向 / 确认方式 / 品种 / 周期 + 目标与止损幅度分档 + 时长分档）；老服务端没有 */
  comparableGroups?: StatGroup[]
  proof?: StatProof
  comparableProof?: StatProof
  grouping: string
  comparableGrouping?: string
  asOf: number
  ruleVersion?: string
}

export interface Match {
  id: string
  range: ChartRange
  /** 0–1 的相似度 */
  score: number
  /** history 全市场历史 · private 我自己的记录 */
  source: string
}

export interface SavedMatch { item: Match; revision: number }

export type SearchState = 'queued' | 'running' | 'completed' | 'failed' | 'cancelled'

export interface SearchStatus {
  id: string
  status: SearchState
  checked: number
  processed: number
  total: number
  error: string | null
  cutoff?: number
}

export interface SearchResults { items: Match[]; next: string | null; cutoff: number; model: string; partial: boolean }
